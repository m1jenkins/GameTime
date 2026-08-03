-- Step 2B fake authorization behavior: deterministic outcomes, exact retries,
-- atomic rollback, logical terminal mappings, appeals, and D109 deletion.

begin;
select no_plan();

set local timezone = 'UTC';

select is(
  (
    select contract_creation_enabled
    from app.solo_contract_runtime
    where singleton
  ),
  false,
  'Step 2B leaves the authoritative Solo creation switch disabled'
);

select is(
  (select count(*) from app.solo_beta_eligibility),
  0::bigint,
  'Step 2B leaves the Solo beta allowlist empty'
);

-- ---------------------------------------------------------------------------
-- Isolated owners and deterministic helpers
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('d7111111-1111-1111-1111-111111111111'), -- authorized retry
  ('d7222222-2222-2222-2222-222222222222'), -- refused
  ('d7333333-3333-3333-3333-333333333333'), -- retryable then authorized
  ('d7444444-4444-4444-4444-444444444444'), -- injected failure
  ('d7555555-5555-5555-5555-555555555555'), -- cancellation
  ('d7666666-6666-6666-6666-666666666666'), -- pass/release
  ('d7777777-7777-7777-7777-777777777777'), -- inconclusive/waive
  ('d7888888-8888-8888-8888-888888888888'), -- failed/forfeit
  ('d7999999-9999-9999-9999-999999999999'), -- appeal upheld
  ('d7aaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), -- appeal denied
  ('d7bbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), -- appeal waived
  ('d7cccccc-cccc-cccc-cccc-cccccccccccc'), -- pre-start deletion
  ('d7dddddd-dddd-dddd-dddd-dddddddddddd'); -- post-start deletion

insert into public.profiles (id, handle, display_name, timezone) values
  ('d7111111-1111-1111-1111-111111111111', 'fake_auth_success', 'Fake Auth Success', 'UTC'),
  ('d7222222-2222-2222-2222-222222222222', 'fake_auth_refused', 'Fake Auth Refused', 'UTC'),
  ('d7333333-3333-3333-3333-333333333333', 'fake_auth_retry', 'Fake Auth Retry', 'UTC'),
  ('d7444444-4444-4444-4444-444444444444', 'fake_auth_failure', 'Fake Auth Failure', 'UTC'),
  ('d7555555-5555-5555-5555-555555555555', 'fake_auth_cancel', 'Fake Auth Cancel', 'UTC'),
  ('d7666666-6666-6666-6666-666666666666', 'fake_auth_pass', 'Fake Auth Pass', 'UTC'),
  ('d7777777-7777-7777-7777-777777777777', 'fake_auth_unknown', 'Fake Auth Inconclusive', 'UTC'),
  ('d7888888-8888-8888-8888-888888888888', 'fake_auth_forfeit', 'Fake Auth Forfeit', 'UTC'),
  ('d7999999-9999-9999-9999-999999999999', 'fake_auth_upheld', 'Fake Auth Upheld', 'UTC'),
  ('d7aaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fake_auth_denied', 'Fake Auth Denied', 'UTC'),
  ('d7bbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'fake_auth_waived', 'Fake Auth Waived', 'UTC'),
  ('d7cccccc-cccc-cccc-cccc-cccccccccccc', 'fake_auth_delete_early', 'Fake Auth Delete Early', 'UTC'),
  ('d7dddddd-dddd-dddd-dddd-dddddddddddd', 'fake_auth_delete_live', 'Fake Auth Delete Live', 'UTC');

select is(
  public.set_solo_contract_runtime_v1(
    'd7000000-0000-0000-0000-000000000001',
    true,
    'solo-test-v1'
  ),
  true,
  'the service explicitly enables the local fake test fixture'
);

create temporary table t_fake_eligibility (
  owner_id uuid primary key,
  eligible boolean not null
);

insert into t_fake_eligibility (owner_id, eligible)
select fixture.owner_id,
       public.set_solo_beta_eligibility_v1(
         fixture.owner_id,
         fixture.owner_id,
         true
       )
from (
  values
    ('d7111111-1111-1111-1111-111111111111'::uuid),
    ('d7222222-2222-2222-2222-222222222222'::uuid),
    ('d7333333-3333-3333-3333-333333333333'::uuid),
    ('d7444444-4444-4444-4444-444444444444'::uuid),
    ('d7555555-5555-5555-5555-555555555555'::uuid),
    ('d7666666-6666-6666-6666-666666666666'::uuid),
    ('d7777777-7777-7777-7777-777777777777'::uuid),
    ('d7888888-8888-8888-8888-888888888888'::uuid),
    ('d7999999-9999-9999-9999-999999999999'::uuid),
    ('d7aaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
    ('d7bbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid),
    ('d7cccccc-cccc-cccc-cccc-cccccccccccc'::uuid),
    ('d7dddddd-dddd-dddd-dddd-dddddddddddd'::uuid)
) fixture(owner_id);

select is(
  (select count(*) from t_fake_eligibility where eligible),
  13::bigint,
  'every fake lifecycle fixture is explicitly beta eligible'
);

create function pg_temp.create_fake_authorized(
  p_owner_id uuid,
  p_request_id uuid,
  p_start_date date,
  p_amount integer default 1000
)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', p_owner_id)::text,
    true
  );

  return public.create_solo_contract_with_fake_authorization_v2(
    p_request_id,
    'solo-test-v1',
    'daily',
    10000,
    p_amount,
    'UTC',
    p_start_date,
    1::smallint
  );
end;
$$;

create function pg_temp.advance_fake_to_evaluation(p_contract_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_contract public.solo_contracts;
begin
  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  perform app.advance_solo_contract_at_v1(
    p_contract_id,
    gen_random_uuid(),
    'active',
    v_contract.starts_at
  );
  perform app.advance_solo_contract_at_v1(
    p_contract_id,
    gen_random_uuid(),
    'awaiting_evaluation',
    v_contract.evidence_cutoff
  );
end;
$$;

create function pg_temp.evaluate_fake(
  p_contract_id uuid,
  p_outcome public.solo_evaluation_outcome
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_cutoff timestamptz;
begin
  select contract.evidence_cutoff into strict v_cutoff
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  return app.record_solo_evaluation_at_v1(
    p_contract_id,
    gen_random_uuid(),
    p_outcome,
    p_outcome::text || '_fake_authorization_fixture',
    'solo-fake-evaluator-v1',
    extensions.digest(
      pg_catalog.convert_to(p_contract_id::text, 'UTF8'),
      'sha256'
    ),
    v_cutoff
  );
end;
$$;

create temporary table t_fake_contracts (
  label text primary key,
  owner_id uuid not null,
  contract_id uuid not null unique,
  authorization_id uuid not null unique
);

create temporary table t_fake_evaluations (
  label text primary key,
  evaluation_id uuid not null unique
);

create temporary table t_fake_appeals (
  label text primary key,
  appeal_id uuid not null unique
);

-- ---------------------------------------------------------------------------
-- Authorized creation, exact retry, and mutable-gate recovery
-- ---------------------------------------------------------------------------

create temporary table t_fake_success_result as
select pg_temp.create_fake_authorized(
  'd7111111-1111-1111-1111-111111111111',
  'd7100000-0000-0000-0000-000000000001',
  '2098-01-01',
  1000
) as result;

insert into t_fake_contracts (
  label,
  owner_id,
  contract_id,
  authorization_id
)
select 'success',
       'd7111111-1111-1111-1111-111111111111',
       (result ->> 'contract_id')::uuid,
       (result ->> 'authorization_id')::uuid
from t_fake_success_result;

select ok(
  (
    select result ->> 'outcome' = 'authorized'
       and result ->> 'adapter_version' = 'local-fake-v1'
       and (result ->> 'contract_id')::uuid is not null
       and (result ->> 'authorization_id')::uuid is not null
    from t_fake_success_result
  ),
  'the public v2 boundary deterministically returns one safe authorized result'
);

select ok(
  (
    select authorization_row.contract_id = contract.id
       and authorization_row.owner_id = contract.owner_id
       and authorization_row.policy_version = contract.policy_version
       and authorization_row.policy_digest = contract.policy_digest
       and authorization_row.commitment_amount_minor
             = contract.commitment_amount_minor
       and authorization_row.currency = contract.currency
       and authorization_row.settlement_mode = contract.settlement_mode
       and authorization_row.adapter_kind = 'processor_neutral_fake'
       and authorization_row.adapter_version = 'local-fake-v1'
       and octet_length(authorization_row.authorization_digest) = 32
       and octet_length(authorization_row.create_request_digest) = 32
    from t_fake_contracts fixture
    join public.solo_contracts contract
      on contract.id = fixture.contract_id
    join app.solo_authorizations authorization_row
      on authorization_row.id = fixture.authorization_id
    where fixture.label = 'success'
  )
  and (
    select count(*) = 1
       and bool_and(event.sequence_number = 1)
       and bool_and(event.event_kind = 'authorized')
       and bool_and(
         event.source_operation
           = 'create_solo_contract_with_fake_authorization_v2'
       )
    from app.solo_authorization_events event
    where event.authorization_id = (
      select authorization_id from t_fake_contracts where label = 'success'
    )
  ),
  'one transaction persists the complete immutable link and one initial event'
);

select is(
  public.set_solo_beta_eligibility_v1(
    'd7100000-0000-0000-0000-000000000002',
    'd7111111-1111-1111-1111-111111111111',
    false
  ),
  false,
  'the service disables the success owner after the committed response'
);

select is(
  public.set_solo_contract_runtime_v1(
    'd7100000-0000-0000-0000-000000000003',
    false,
    'solo-test-v1'
  ),
  false,
  'the service disables creation after the committed response'
);

select is(
  pg_temp.create_fake_authorized(
    'd7111111-1111-1111-1111-111111111111',
    'd7100000-0000-0000-0000-000000000001',
    '2098-01-01',
    1000
  ),
  (select result from t_fake_success_result),
  'an exact committed v2 retry recovers before both mutable gates'
);

select throws_ok(
  $$ select pg_temp.create_fake_authorized(
       'd7111111-1111-1111-1111-111111111111',
       'd7100000-0000-0000-0000-000000000001',
       '2098-01-01',
       1100
     ) $$,
  '22023',
  null,
  'a committed v2 request UUID rejects changed amount before mutable gates'
);

select is(
  (
    select count(*)
    from app.solo_authorizations
    where owner_id = 'd7111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'exact and conflicting retries leave one authorization linkage'
);

select public.set_solo_beta_eligibility_v1(
  'd7100000-0000-0000-0000-000000000004',
  'd7111111-1111-1111-1111-111111111111',
  true
);
select public.set_solo_contract_runtime_v1(
  'd7100000-0000-0000-0000-000000000005',
  true,
  'solo-test-v1'
);

-- ---------------------------------------------------------------------------
-- Deterministic refusal, retry, and injected transactional failure
-- ---------------------------------------------------------------------------

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7222222-2222-2222-2222-222222222222"}',
  true
);

create temporary table t_fake_refusal as
select app.create_solo_contract_with_fake_authorization_at_v2(
  'd7200000-0000-0000-0000-000000000001',
  'solo-test-v1',
  'daily',
  10000,
  2000,
  'UTC',
  '2098-02-01',
  1::smallint,
  'refuse'
) as result;

select ok(
  (
    select result = pg_catalog.jsonb_build_object(
      'adapter_version', 'local-fake-v1',
      'outcome', 'refused'
    )
    from t_fake_refusal
  )
  and not exists (
    select 1 from public.solo_contracts
    where owner_id = 'd7222222-2222-2222-2222-222222222222'
  )
  and not exists (
    select 1 from app.solo_authorizations
    where owner_id = 'd7222222-2222-2222-2222-222222222222'
  )
  and not exists (
    select 1 from app.solo_authorization_events
    where owner_id = 'd7222222-2222-2222-2222-222222222222'
  ),
  'deterministic refusal commits only a safe exact-request result and no half-link'
);

select public.set_solo_beta_eligibility_v1(
  'd7200000-0000-0000-0000-000000000002',
  'd7222222-2222-2222-2222-222222222222',
  false
);
select public.set_solo_contract_runtime_v1(
  'd7200000-0000-0000-0000-000000000003',
  false,
  'solo-test-v1'
);

select is(
  app.create_solo_contract_with_fake_authorization_at_v2(
    'd7200000-0000-0000-0000-000000000001',
    'solo-test-v1',
    'daily',
    10000,
    2000,
    'UTC',
    '2098-02-01',
    1::smallint,
    'refuse'
  ),
  (select result from t_fake_refusal),
  'an exact committed refusal retry also recovers before mutable gates'
);

select throws_ok(
  $$ select app.create_solo_contract_with_fake_authorization_at_v2(
       'd7200000-0000-0000-0000-000000000001',
       'solo-test-v1',
       'daily',
       10000,
       2001,
       'UTC',
       '2098-02-01',
       1::smallint,
       'refuse'
     ) $$,
  '22023',
  null,
  'a committed refusal request rejects a changed typed payload'
);

select public.set_solo_beta_eligibility_v1(
  'd7200000-0000-0000-0000-000000000004',
  'd7222222-2222-2222-2222-222222222222',
  true
);
select public.set_solo_contract_runtime_v1(
  'd7200000-0000-0000-0000-000000000005',
  true,
  'solo-test-v1'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7333333-3333-3333-3333-333333333333"}',
  true
);

create temporary table t_fake_retryable as
select app.create_solo_contract_with_fake_authorization_at_v2(
  'd7300000-0000-0000-0000-000000000001',
  'solo-test-v1',
  'daily',
  10000,
  3000,
  'UTC',
  '2098-03-01',
  1::smallint,
  'retryable'
) as result;

select ok(
  (
    select result ->> 'outcome' = 'retryable'
       and not (result ? 'contract_id')
       and not (result ? 'authorization_id')
    from t_fake_retryable
  )
  and not exists (
    select 1 from public.solo_contracts
    where owner_id = 'd7333333-3333-3333-3333-333333333333'
  ),
  'a retryable fake result persists no candidate contract or identifier'
);

select is(
  app.create_solo_contract_with_fake_authorization_at_v2(
    'd7300000-0000-0000-0000-000000000001',
    'solo-test-v1',
    'daily',
    10000,
    3000,
    'UTC',
    '2098-03-01',
    1::smallint,
    'retryable'
  ),
  (select result from t_fake_retryable),
  'the same retryable request returns the exact committed retry result'
);

create temporary table t_fake_retry_success as
select app.create_solo_contract_with_fake_authorization_at_v2(
  'd7300000-0000-0000-0000-000000000002',
  'solo-test-v1',
  'daily',
  10000,
  3000,
  'UTC',
  '2098-03-01',
  1::smallint,
  'authorize'
) as result;

insert into t_fake_contracts (label, owner_id, contract_id, authorization_id)
select 'retry_success',
       'd7333333-3333-3333-3333-333333333333',
       (result ->> 'contract_id')::uuid,
       (result ->> 'authorization_id')::uuid
from t_fake_retry_success;

select ok(
  (
    select result ->> 'outcome' = 'authorized'
    from t_fake_retry_success
  )
  and (
    select count(*) = 1
    from app.solo_authorizations
    where owner_id = 'd7333333-3333-3333-3333-333333333333'
  ),
  'a fresh request after a retryable result creates one atomic authorization'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7444444-4444-4444-4444-444444444444"}',
  true
);

select throws_ok(
  $$ select app.create_solo_contract_with_fake_authorization_at_v2(
       'd7400000-0000-0000-0000-000000000001',
       'solo-test-v1',
       'daily',
       10000,
       4000,
       'UTC',
       '2098-04-01',
       1::smallint,
       'injected_failure'
     ) $$,
  'P2B02',
  'deterministic local fake authorization failure',
  'the deterministic injected failure occurs after candidate creation'
);

select ok(
  not exists (
    select 1 from public.solo_contracts
    where owner_id = 'd7444444-4444-4444-4444-444444444444'
  )
  and not exists (
    select 1 from app.solo_authorizations
    where owner_id = 'd7444444-4444-4444-4444-444444444444'
  )
  and not exists (
    select 1 from app.solo_authorization_events
    where owner_id = 'd7444444-4444-4444-4444-444444444444'
  )
  and not exists (
    select 1
    from app.solo_rpc_requests request
    where request.request_scope = 'd7444444-4444-4444-4444-444444444444'
      and request.request_id = 'd7400000-0000-0000-0000-000000000001'
      and request.operation in (
        'create_solo_contract_v1',
        'create_solo_contract_with_fake_authorization_v2'
      )
  ),
  'injected failure rolls back contract, authorization, events, and both request ledgers'
);

-- ---------------------------------------------------------------------------
-- Pre-start cancellation is one fake cancellation, never money movement
-- ---------------------------------------------------------------------------

create temporary table t_fake_cancel_result as
select pg_temp.create_fake_authorized(
  'd7555555-5555-5555-5555-555555555555',
  'd7500000-0000-0000-0000-000000000001',
  '2098-05-01',
  5000
) as result;

insert into t_fake_contracts (label, owner_id, contract_id, authorization_id)
select 'cancel',
       'd7555555-5555-5555-5555-555555555555',
       (result ->> 'contract_id')::uuid,
       (result ->> 'authorization_id')::uuid
from t_fake_cancel_result;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7555555-5555-5555-5555-555555555555"}',
  true
);

select is(
  app.cancel_solo_contract_at_v1(
    (select contract_id from t_fake_contracts where label = 'cancel'),
    'd7500000-0000-0000-0000-000000000002',
    (
      select starts_at - interval '1 microsecond'
      from public.solo_contracts
      where id = (
        select contract_id from t_fake_contracts where label = 'cancel'
      )
    )
  ),
  (select contract_id from t_fake_contracts where label = 'cancel'),
  'pre-start cancellation resolves contract and fake authorization atomically'
);

select ok(
  (
    select count(*) = 2
       and count(*) filter (
         where event.sequence_number = 2
           and event.event_kind = 'cancelled'
           and event.source_operation = 'cancel_solo_contract_v1'
       ) = 1
    from app.solo_authorization_events event
    where event.authorization_id = (
      select authorization_id from t_fake_contracts where label = 'cancel'
    )
  )
  and (
    select terminal.event_at = contract.cancelled_at
       and contract.settlement_disposition = 'cancelled'
    from t_fake_contracts fixture
    join public.solo_contracts contract on contract.id = fixture.contract_id
    join app.solo_authorization_events terminal
      on terminal.authorization_id = fixture.authorization_id
     and terminal.sequence_number = 2
    where fixture.label = 'cancel'
  ),
  'fake cancellation records one exact logical outcome at the contract timestamp'
);

select is(
  app.cancel_solo_contract_at_v1(
    (select contract_id from t_fake_contracts where label = 'cancel'),
    'd7500000-0000-0000-0000-000000000002',
    '2099-01-01T00:00:00Z'
  ),
  (select contract_id from t_fake_contracts where label = 'cancel'),
  'an exact cancellation retry remains recoverable after the start boundary'
);

select is(
  (
    select count(*)
    from app.solo_authorization_events event
    where event.authorization_id = (
      select authorization_id from t_fake_contracts where label = 'cancel'
    )
      and event.sequence_number = 2
  ),
  1::bigint,
  'an exact cancellation retry cannot double-resolve the fake authorization'
);

-- ---------------------------------------------------------------------------
-- Evaluation, appeal, and every logical settlement mapping
-- ---------------------------------------------------------------------------

insert into t_fake_contracts (label, owner_id, contract_id, authorization_id)
select fixture.label,
       fixture.owner_id,
       (created.result ->> 'contract_id')::uuid,
       (created.result ->> 'authorization_id')::uuid
from (
  values
    ('pass', 'd7666666-6666-6666-6666-666666666666'::uuid, 'd7600000-0000-0000-0000-000000000001'::uuid, '2098-06-01'::date, 1000),
    ('inconclusive', 'd7777777-7777-7777-7777-777777777777'::uuid, 'd7700000-0000-0000-0000-000000000001'::uuid, '2098-07-01'::date, 2000),
    ('failure', 'd7888888-8888-8888-8888-888888888888'::uuid, 'd7800000-0000-0000-0000-000000000001'::uuid, '2098-08-01'::date, 3000),
    ('appeal_upheld', 'd7999999-9999-9999-9999-999999999999'::uuid, 'd7900000-0000-0000-0000-000000000001'::uuid, '2098-09-01'::date, 4000),
    ('appeal_denied', 'd7aaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'd7a00000-0000-0000-0000-000000000001'::uuid, '2098-10-01'::date, 5000),
    ('appeal_waived', 'd7bbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'd7b00000-0000-0000-0000-000000000001'::uuid, '2098-11-01'::date, 1000)
) fixture(label, owner_id, request_id, start_date, amount)
cross join lateral (
  select pg_temp.create_fake_authorized(
    fixture.owner_id,
    fixture.request_id,
    fixture.start_date,
    fixture.amount
  ) as result
) created;

select pg_temp.advance_fake_to_evaluation(fixture.contract_id)
from t_fake_contracts fixture
where fixture.label in (
  'pass',
  'inconclusive',
  'failure',
  'appeal_upheld',
  'appeal_denied',
  'appeal_waived'
)
order by fixture.label;

select ok(
  (
    select bool_and(event_count = 1)
    from (
      select fixture.label, count(event.*) as event_count
      from t_fake_contracts fixture
      join app.solo_authorization_events event
        on event.authorization_id = fixture.authorization_id
      where fixture.label in (
        'pass',
        'inconclusive',
        'failure',
        'appeal_upheld',
        'appeal_denied',
        'appeal_waived'
      )
      group by fixture.label
    ) counts
  ),
  'activation and evidence close do not resolve a fake authorization'
);

insert into t_fake_evaluations (label, evaluation_id)
select fixture.label,
       pg_temp.evaluate_fake(
         fixture.contract_id,
         case fixture.label
           when 'pass' then 'passed'::public.solo_evaluation_outcome
           when 'inconclusive' then 'inconclusive'::public.solo_evaluation_outcome
           else 'failed'::public.solo_evaluation_outcome
         end
       )
from t_fake_contracts fixture
where fixture.label in (
  'pass',
  'inconclusive',
  'failure',
  'appeal_upheld',
  'appeal_denied',
  'appeal_waived'
)
order by fixture.label;

select ok(
  (
    select bool_and(event_count = 1)
    from (
      select fixture.label, count(event.*) as event_count
      from t_fake_contracts fixture
      join app.solo_authorization_events event
        on event.authorization_id = fixture.authorization_id
      where fixture.label in (
        'pass',
        'inconclusive',
        'failure',
        'appeal_upheld',
        'appeal_denied',
        'appeal_waived'
      )
      group by fixture.label
    ) counts
  ),
  'preliminary evaluation alone does not resolve a fake authorization'
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'pass'),
  'd7600000-0000-0000-0000-000000000002',
  (
    select evaluated_at + interval '1 second'
    from public.solo_evaluations
    where id = (select evaluation_id from t_fake_evaluations where label = 'pass')
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'inconclusive'),
  'd7700000-0000-0000-0000-000000000002',
  (
    select evaluated_at + interval '1 second'
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'inconclusive'
    )
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'failure'),
  'd7800000-0000-0000-0000-000000000002',
  (
    select appeal_deadline
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'failure'
    )
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7999999-9999-9999-9999-999999999999"}',
  true
);
insert into t_fake_appeals (label, appeal_id)
values (
  'appeal_upheld',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_fake_contracts where label = 'appeal_upheld'),
    (select evaluation_id from t_fake_evaluations where label = 'appeal_upheld'),
    'd7900000-0000-0000-0000-000000000002',
    'The completed evidence should be reviewed.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id from t_fake_evaluations where label = 'appeal_upheld'
      )
    )
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7aaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}',
  true
);
insert into t_fake_appeals (label, appeal_id)
values (
  'appeal_denied',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_fake_contracts where label = 'appeal_denied'),
    (select evaluation_id from t_fake_evaluations where label = 'appeal_denied'),
    'd7a00000-0000-0000-0000-000000000002',
    'The preliminary result should be reviewed.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id from t_fake_evaluations where label = 'appeal_denied'
      )
    )
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7bbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}',
  true
);
insert into t_fake_appeals (label, appeal_id)
values (
  'appeal_waived',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_fake_contracts where label = 'appeal_waived'),
    (select evaluation_id from t_fake_evaluations where label = 'appeal_waived'),
    'd7b00000-0000-0000-0000-000000000002',
    'The inconclusive source condition should waive the result.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id from t_fake_evaluations where label = 'appeal_waived'
      )
    )
  )
);

select ok(
  not exists (
    select 1
    from app.solo_authorization_events event
    join t_fake_contracts fixture
      on fixture.authorization_id = event.authorization_id
    where fixture.label in ('appeal_upheld', 'appeal_denied', 'appeal_waived')
      and event.sequence_number = 2
  ),
  'filing an appeal leaves the fake authorization pending'
);

select app.decide_solo_appeal_at_v1(
  (select appeal_id from t_fake_appeals where label = 'appeal_upheld'),
  'd7900000-0000-0000-0000-000000000003',
  'upheld',
  'evidence_verified',
  'solo-fake-reviewer-v1',
  extensions.digest(pg_catalog.convert_to('upheld', 'UTF8'), 'sha256'),
  (
    select evaluated_at + interval '2 days'
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'appeal_upheld'
    )
  )
);

select app.decide_solo_appeal_at_v1(
  (select appeal_id from t_fake_appeals where label = 'appeal_denied'),
  'd7a00000-0000-0000-0000-000000000003',
  'denied',
  'evidence_unchanged',
  'solo-fake-reviewer-v1',
  extensions.digest(pg_catalog.convert_to('denied', 'UTF8'), 'sha256'),
  (
    select evaluated_at + interval '2 days'
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'appeal_denied'
    )
  )
);

select app.decide_solo_appeal_at_v1(
  (select appeal_id from t_fake_appeals where label = 'appeal_waived'),
  'd7b00000-0000-0000-0000-000000000003',
  'waived',
  'source_unavailable',
  'solo-fake-reviewer-v1',
  extensions.digest(pg_catalog.convert_to('waived', 'UTF8'), 'sha256'),
  (
    select evaluated_at + interval '2 days'
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'appeal_waived'
    )
  )
);

select ok(
  not exists (
    select 1
    from app.solo_authorization_events event
    join t_fake_contracts fixture
      on fixture.authorization_id = event.authorization_id
    where fixture.label in ('appeal_upheld', 'appeal_denied', 'appeal_waived')
      and event.sequence_number = 2
  ),
  'an appeal decision still waits for the explicit logical settlement RPC'
);

select app.settle_solo_contract_at_v1(
  fixture.contract_id,
  gen_random_uuid(),
  evaluation.evaluated_at + interval '3 days'
)
from t_fake_contracts fixture
join t_fake_evaluations evaluation_fixture
  on evaluation_fixture.label = fixture.label
join public.solo_evaluations evaluation
  on evaluation.id = evaluation_fixture.evaluation_id
where fixture.label in ('appeal_upheld', 'appeal_denied', 'appeal_waived')
order by fixture.label;

select ok(
  not exists (
    select 1
    from (
      values
        ('pass', 'released'),
        ('inconclusive', 'waived'),
        ('failure', 'forfeited'),
        ('appeal_upheld', 'released'),
        ('appeal_denied', 'forfeited'),
        ('appeal_waived', 'waived')
    ) expected(label, event_kind)
    join t_fake_contracts fixture on fixture.label = expected.label
    left join app.solo_authorization_events terminal
      on terminal.authorization_id = fixture.authorization_id
     and terminal.sequence_number = 2
     and terminal.event_kind::text = expected.event_kind
    left join public.solo_contracts contract
      on contract.id = fixture.contract_id
    where terminal.id is null
       or contract.status <> 'settled'
       or contract.settlement_disposition::text <> expected.event_kind
       or terminal.event_at is distinct from contract.settled_at
       or terminal.source_operation <> 'settle_solo_contract_v1'
  ),
  'pass, inconclusive, failure, and every appeal decision map to one deterministic fake outcome'
);

select ok(
  not exists (
    select 1
    from t_fake_contracts fixture
    join app.solo_authorization_events event
      on event.authorization_id = fixture.authorization_id
    where fixture.label in (
      'pass',
      'inconclusive',
      'failure',
      'appeal_upheld',
      'appeal_denied',
      'appeal_waived'
    )
    group by fixture.authorization_id
    having count(*) <> 2
       or count(*) filter (where event.sequence_number = 2) <> 1
  ),
  'every settled fake authorization has one initial and exactly one terminal event'
);

-- ---------------------------------------------------------------------------
-- D109 deletion resolves only pre-start authorization; post-start is retained
-- ---------------------------------------------------------------------------

create temporary table t_fake_delete_pre as
select pg_temp.create_fake_authorized(
  'd7cccccc-cccc-cccc-cccc-cccccccccccc',
  'd7c00000-0000-0000-0000-000000000001',
  '2098-12-01',
  2000
) as result;

insert into t_fake_contracts (label, owner_id, contract_id, authorization_id)
select 'delete_pre',
       'd7cccccc-cccc-cccc-cccc-cccccccccccc',
       (result ->> 'contract_id')::uuid,
       (result ->> 'authorization_id')::uuid
from t_fake_delete_pre;

create temporary table t_fake_deletions (
  owner_id uuid primary key,
  result jsonb not null
);
grant insert on t_fake_deletions to service_role;

reset role;
set local role service_role;
insert into t_fake_deletions (owner_id, result)
values (
  'd7cccccc-cccc-cccc-cccc-cccccccccccc',
  public.delete_account('d7cccccc-cccc-cccc-cccc-cccccccccccc')
);
reset role;

select ok(
  (
    select contract.status = 'cancelled'
       and contract.cancellation_reason = 'account_deleted'
       and terminal.event_kind = 'cancelled'
       and terminal.source_operation = 'delete_account'
       and terminal.event_at = contract.cancelled_at
       and terminal.event_at = profile.deleted_at
    from t_fake_contracts fixture
    join public.solo_contracts contract on contract.id = fixture.contract_id
    join public.profiles profile on profile.id = fixture.owner_id
    join app.solo_authorization_events terminal
      on terminal.authorization_id = fixture.authorization_id
     and terminal.sequence_number = 2
    where fixture.label = 'delete_pre'
  )
  and not (
    select eligible
    from app.solo_beta_eligibility
    where owner_id = 'd7cccccc-cccc-cccc-cccc-cccccccccccc'
  ),
  'pre-start deletion cancels contract and fake authorization in the D81 transaction'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7cccccc-cccc-cccc-cccc-cccccccccccc"}',
  true
);

select is(
  (select count(*) from public.solo_contracts),
  0::bigint,
  'a deleted pre-start owner stale JWT reads no Solo contract'
);

select throws_ok(
  $$ select * from app.solo_authorizations $$,
  '42501',
  null,
  'a stale owner token has no private authorization-table access'
);

select throws_ok(
  $$ select public.cancel_solo_contract_v1(
       (
         select contract_id from t_fake_contracts where label = 'delete_pre'
       ),
       'd7c00000-0000-0000-0000-000000000002'
     ) $$,
  '42501',
  null,
  'a deleted pre-start owner stale JWT cannot mutate the contract'
);
reset role;

create temporary table t_fake_delete_post as
select pg_temp.create_fake_authorized(
  'd7dddddd-dddd-dddd-dddd-dddddddddddd',
  'd7d00000-0000-0000-0000-000000000001',
  '2099-01-01',
  3000
) as result;

insert into t_fake_contracts (label, owner_id, contract_id, authorization_id)
select 'delete_post',
       'd7dddddd-dddd-dddd-dddd-dddddddddddd',
       (result ->> 'contract_id')::uuid,
       (result ->> 'authorization_id')::uuid
from t_fake_delete_post;

select app.advance_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'delete_post'),
  'd7d00000-0000-0000-0000-000000000002',
  'active',
  (
    select starts_at
    from public.solo_contracts
    where id = (
      select contract_id from t_fake_contracts where label = 'delete_post'
    )
  )
);

set local role service_role;
insert into t_fake_deletions (owner_id, result)
values (
  'd7dddddd-dddd-dddd-dddd-dddddddddddd',
  public.delete_account('d7dddddd-dddd-dddd-dddd-dddddddddddd')
);
reset role;

select ok(
  (
    select contract.status = 'active'
       and contract.closed_at is null
       and count(event.*) = 1
       and bool_and(event.event_kind = 'authorized')
    from t_fake_contracts fixture
    join public.solo_contracts contract on contract.id = fixture.contract_id
    join app.solo_authorization_events event
      on event.authorization_id = fixture.authorization_id
    where fixture.label = 'delete_post'
    group by contract.id
  )
  and not (
    select eligible
    from app.solo_beta_eligibility
    where owner_id = 'd7dddddd-dddd-dddd-dddd-dddddddddddd'
  ),
  'post-start deletion retains contract and unresolved fake authorization for service finality'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d7dddddd-dddd-dddd-dddd-dddddddddddd"}',
  true
);
select is(
  (select count(*) from public.solo_contracts),
  0::bigint,
  'a deleted post-start owner stale JWT cannot read retained facts'
);
select throws_ok(
  $$ select public.create_solo_contract_with_fake_authorization_v2(
       'd7d00000-0000-0000-0000-000000000003',
       'solo-test-v1',
       'daily',
       10000,
       3000,
       'UTC',
       '2099-02-01',
       1::smallint
     ) $$,
  '42501',
  null,
  'a deleted post-start owner stale JWT cannot invoke v2 creation'
);
reset role;
select pg_catalog.set_config('request.jwt.claims', '{}', true);

select app.advance_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'delete_post'),
  'd7d00000-0000-0000-0000-000000000004',
  'awaiting_evaluation',
  (
    select evidence_cutoff
    from public.solo_contracts
    where id = (
      select contract_id from t_fake_contracts where label = 'delete_post'
    )
  )
);

insert into t_fake_evaluations (label, evaluation_id)
values (
  'delete_post',
  pg_temp.evaluate_fake(
    (select contract_id from t_fake_contracts where label = 'delete_post'),
    'passed'
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_fake_contracts where label = 'delete_post'),
  'd7d00000-0000-0000-0000-000000000005',
  (
    select evaluated_at + interval '1 second'
    from public.solo_evaluations
    where id = (
      select evaluation_id from t_fake_evaluations where label = 'delete_post'
    )
  )
);

select ok(
  (
    select contract.status = 'settled'
       and contract.settlement_disposition = 'released'
       and terminal.event_kind = 'released'
       and terminal.event_at = contract.settled_at
    from t_fake_contracts fixture
    join public.solo_contracts contract on contract.id = fixture.contract_id
    join app.solo_authorization_events terminal
      on terminal.authorization_id = fixture.authorization_id
     and terminal.sequence_number = 2
    where fixture.label = 'delete_post'
  ),
  'the service finishes retained post-start facts with one logical fake resolution'
);

select * from finish();
rollback;
