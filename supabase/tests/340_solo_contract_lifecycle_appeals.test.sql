-- Step 2A Solo lifecycle: deterministic transition boundaries, exact-request
-- retries, immutable adjudication ledgers, appeal finality, and D81 deletion.

begin;
select no_plan();

set local timezone = 'UTC';

-- ---------------------------------------------------------------------------
-- Isolated owners and deterministic fixture helpers
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('b4111111-1111-1111-1111-111111111111'), -- cancellation boundaries
  ('b4222222-2222-2222-2222-222222222222'), -- passed evaluation
  ('b4333333-3333-3333-3333-333333333333'), -- inconclusive evaluation
  ('b4444444-4444-4444-4444-444444444444'), -- unappealed failure
  ('b4555555-5555-5555-5555-555555555555'), -- denied appeal
  ('b4666666-6666-6666-6666-666666666666'), -- upheld appeal
  ('b4777777-7777-7777-7777-777777777777'), -- waived appeal
  ('b4888888-8888-8888-8888-888888888888'), -- pre-start deletion
  ('b4999999-9999-9999-9999-999999999999'); -- post-start deletion

insert into public.profiles (id, handle, display_name, timezone) values
  ('b4111111-1111-1111-1111-111111111111', 'solo_life_cancel', 'Solo Cancel', 'UTC'),
  ('b4222222-2222-2222-2222-222222222222', 'solo_life_pass', 'Solo Pass', 'UTC'),
  ('b4333333-3333-3333-3333-333333333333', 'solo_life_unknown', 'Solo Inconclusive', 'UTC'),
  ('b4444444-4444-4444-4444-444444444444', 'solo_life_expire', 'Solo Expired Appeal', 'UTC'),
  ('b4555555-5555-5555-5555-555555555555', 'solo_life_denied', 'Solo Denied', 'UTC'),
  ('b4666666-6666-6666-6666-666666666666', 'solo_life_upheld', 'Solo Upheld', 'UTC'),
  ('b4777777-7777-7777-7777-777777777777', 'solo_life_waived', 'Solo Waived', 'UTC'),
  ('b4888888-8888-8888-8888-888888888888', 'solo_life_delete_early', 'Solo Delete Early', 'UTC'),
  ('b4999999-9999-9999-9999-999999999999', 'solo_life_delete_live', 'Solo Delete Live', 'UTC');

select is(
  public.set_solo_contract_runtime_v1(
    'b4000000-0000-0000-0000-000000000001',
    true,
    'solo-test-v1'
  ),
  true,
  'the service enables creation against the reviewed Solo policy'
);

create temporary table t_solo_eligibility (
  owner_id uuid primary key,
  eligible boolean not null
);

insert into t_solo_eligibility (owner_id, eligible)
select fixture.owner_id,
       public.set_solo_beta_eligibility_v1(
         fixture.owner_id,
         fixture.owner_id,
         true
       )
from (
  values
    ('b4111111-1111-1111-1111-111111111111'::uuid),
    ('b4222222-2222-2222-2222-222222222222'::uuid),
    ('b4333333-3333-3333-3333-333333333333'::uuid),
    ('b4444444-4444-4444-4444-444444444444'::uuid),
    ('b4555555-5555-5555-5555-555555555555'::uuid),
    ('b4666666-6666-6666-6666-666666666666'::uuid),
    ('b4777777-7777-7777-7777-777777777777'::uuid),
    ('b4888888-8888-8888-8888-888888888888'::uuid),
    ('b4999999-9999-9999-9999-999999999999'::uuid)
) fixture(owner_id);

select is(
  (select count(*) from t_solo_eligibility where eligible),
  9::bigint,
  'every lifecycle fixture is explicitly beta eligible'
);

create function pg_temp.make_solo_contract(
  p_owner_id uuid,
  p_request_id uuid,
  p_start_date date,
  p_commitment_amount_minor integer default 1000,
  p_duration_days smallint default 1
)
returns uuid
language plpgsql
set search_path = ''
as $$
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', p_owner_id)::text,
    true
  );

  return public.create_solo_contract_v1(
    p_request_id,
    'solo-test-v1',
    'daily',
    10000,
    p_commitment_amount_minor,
    'UTC',
    p_start_date,
    p_duration_days
  );
end;
$$;

create function pg_temp.advance_solo_to_evaluation(
  p_contract_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_starts_at       timestamptz;
  v_evidence_cutoff timestamptz;
begin
  select contract.starts_at, contract.evidence_cutoff
  into strict v_starts_at, v_evidence_cutoff
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  perform app.advance_solo_contract_at_v1(
    p_contract_id,
    'b4a00000-0000-0000-0000-000000000001',
    'active',
    v_starts_at
  );
  perform app.advance_solo_contract_at_v1(
    p_contract_id,
    'b4a00000-0000-0000-0000-000000000002',
    'awaiting_evaluation',
    v_evidence_cutoff
  );
end;
$$;

create function pg_temp.evaluate_solo_at_cutoff(
  p_contract_id uuid,
  p_outcome public.solo_evaluation_outcome
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_evidence_cutoff timestamptz;
begin
  select contract.evidence_cutoff
  into strict v_evidence_cutoff
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  return app.record_solo_evaluation_at_v1(
    p_contract_id,
    'b4e00000-0000-0000-0000-000000000001',
    p_outcome,
    p_outcome::text || '_evidence',
    'solo-evaluator-v1',
    extensions.digest(
      pg_catalog.convert_to(p_contract_id::text, 'UTF8'),
      'sha256'
    ),
    v_evidence_cutoff
  );
end;
$$;

create temporary table t_solo_contracts (
  label text primary key,
  owner_id uuid not null,
  contract_id uuid not null unique
);

create temporary table t_solo_evaluations (
  label text primary key,
  evaluation_id uuid not null unique
);

create temporary table t_solo_appeals (
  label text primary key,
  appeal_id uuid not null unique
);

create temporary table t_solo_decisions (
  label text primary key,
  decision_id uuid not null unique
);

-- ---------------------------------------------------------------------------
-- Cancellation is pre-start only, but an exact retry remains recoverable
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'cancel_before_start',
  'b4111111-1111-1111-1111-111111111111',
  pg_temp.make_solo_contract(
    'b4111111-1111-1111-1111-111111111111',
    'b4c00000-0000-0000-0000-000000000001',
    '2098-01-01'
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  app.cancel_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'cancel_before_start'),
    'b4ca0000-0000-0000-0000-000000000001',
    (
      select starts_at - interval '1 microsecond'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'cancel_before_start'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'cancel_before_start'),
  'an owner can cancel one microsecond before the locked start'
);

select ok(
  (
    select contract.status = 'cancelled'
       and contract.cancellation_reason = 'owner_cancelled'
       and contract.settlement_disposition = 'cancelled'
       and contract.cancelled_at = contract.closed_at
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'cancel_before_start'
    )
  ),
  'pre-start cancellation closes the slot with the complete cancellation shape'
);

select is(
  app.cancel_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'cancel_before_start'),
    'b4ca0000-0000-0000-0000-000000000001',
    (
      select starts_at + interval '1 day'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'cancel_before_start'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'cancel_before_start'),
  'the exact cancellation retry resolves after the start boundary'
);

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'cancel_at_start',
  'b4111111-1111-1111-1111-111111111111',
  pg_temp.make_solo_contract(
    'b4111111-1111-1111-1111-111111111111',
    'b4c00000-0000-0000-0000-000000000002',
    '2098-01-03'
  )
);

select throws_ok(
  $$ select app.cancel_solo_contract_at_v1(
       (
         select contract_id
         from t_solo_contracts
         where label = 'cancel_at_start'
       ),
       'b4ca0000-0000-0000-0000-000000000001',
       (
         select starts_at - interval '1 day'
         from public.solo_contracts
         where id = (
           select contract_id
           from t_solo_contracts
           where label = 'cancel_at_start'
         )
       )
     ) $$,
  '22023',
  null,
  'a cancellation request UUID cannot be reused for another contract'
);

select throws_ok(
  $$ select app.cancel_solo_contract_at_v1(
       (
         select contract_id
         from t_solo_contracts
         where label = 'cancel_at_start'
       ),
       'b4ca0000-0000-0000-0000-000000000002',
       (
         select starts_at
         from public.solo_contracts
         where id = (
           select contract_id
           from t_solo_contracts
           where label = 'cancel_at_start'
         )
       )
     ) $$,
  '23001',
  null,
  'cancellation is rejected exactly at the locked start'
);

select is(
  (
    select status
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'cancel_at_start'
    )
  ),
  'scheduled'::public.solo_contract_status,
  'a rejected boundary cancellation leaves the contract scheduled'
);

select is(
  app.cancel_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'cancel_at_start'),
    'b4ca0000-0000-0000-0000-000000000003',
    (
      select starts_at - interval '1 microsecond'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'cancel_at_start'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'cancel_at_start'),
  'a fresh request can still cancel before the start after a rejected boundary try'
);

-- ---------------------------------------------------------------------------
-- Allowed transitions, forbidden transitions, passed evaluation, and release
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'passed',
  'b4222222-2222-2222-2222-222222222222',
  pg_temp.make_solo_contract(
    'b4222222-2222-2222-2222-222222222222',
    'b4c00000-0000-0000-0000-000000000003',
    '2098-02-01'
  )
);

select throws_ok(
  $$ select app.advance_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4a10000-0000-0000-0000-000000000001',
       'ready_to_settle',
       (select starts_at from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '22023',
  null,
  'the lifecycle RPC rejects targets outside its two explicit advances'
);

select throws_ok(
  $$ select app.advance_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4a10000-0000-0000-0000-000000000002',
       'awaiting_evaluation',
       (select evidence_cutoff from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '23001',
  null,
  'a scheduled contract cannot skip directly to evaluation'
);

select throws_ok(
  $$ select app.advance_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4a10000-0000-0000-0000-000000000003',
       'active',
       (select starts_at - interval '1 microsecond'
        from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '23001',
  null,
  'activation is rejected one microsecond before the locked start'
);

select is(
  app.advance_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4a10000-0000-0000-0000-000000000004',
    'active',
    (
      select starts_at
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'passed'),
  'activation succeeds exactly at the locked start'
);

select is(
  app.advance_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4a10000-0000-0000-0000-000000000004',
    'active',
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'passed'),
  'an exact activation retry returns the committed contract'
);

select throws_ok(
  $$ select app.advance_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4a10000-0000-0000-0000-000000000004',
       'awaiting_evaluation',
       (select evidence_cutoff from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '22023',
  null,
  'an advance request UUID cannot change its target state'
);

select throws_ok(
  $$ select app.record_solo_evaluation_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4e10000-0000-0000-0000-000000000001',
       'passed',
       'steps_met',
       'solo-evaluator-v1',
       extensions.digest(pg_catalog.convert_to('pass', 'UTF8'), 'sha256'),
       (select evidence_cutoff from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '23001',
  null,
  'evaluation cannot be recorded while the contract is still active'
);

select throws_ok(
  $$ select app.advance_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4a10000-0000-0000-0000-000000000005',
       'awaiting_evaluation',
       (select evidence_cutoff - interval '1 microsecond'
        from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '23001',
  null,
  'the evidence window cannot close one microsecond early'
);

select is(
  app.advance_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4a10000-0000-0000-0000-000000000005',
    'awaiting_evaluation',
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'passed'),
  'the evidence window closes exactly at its locked cutoff'
);

insert into t_solo_evaluations (label, evaluation_id)
values (
  'passed',
  app.record_solo_evaluation_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4e10000-0000-0000-0000-000000000002',
    'passed',
    'steps_met',
    'solo-evaluator-v1',
    extensions.digest(pg_catalog.convert_to('pass', 'UTF8'), 'sha256'),
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  )
);

select is(
  app.record_solo_evaluation_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4e10000-0000-0000-0000-000000000002',
    'passed',
    'steps_met',
    'solo-evaluator-v1',
    extensions.digest(pg_catalog.convert_to('pass', 'UTF8'), 'sha256'),
    (
      select evidence_cutoff + interval '30 days'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select evaluation_id from t_solo_evaluations where label = 'passed'),
  'an exact evaluation retry returns the original immutable evaluation'
);

select throws_ok(
  $$ select app.record_solo_evaluation_at_v1(
       (select contract_id from t_solo_contracts where label = 'passed'),
       'b4e10000-0000-0000-0000-000000000002',
       'inconclusive',
       'steps_met',
       'solo-evaluator-v1',
       extensions.digest(pg_catalog.convert_to('pass', 'UTF8'), 'sha256'),
       (select evidence_cutoff from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'passed'
       ))
     ) $$,
  '22023',
  null,
  'an evaluation request UUID cannot change the recorded outcome'
);

select throws_ok(
  $$ update public.solo_evaluations
     set reason_code = 'rewritten'
     where id = (
       select evaluation_id
       from t_solo_evaluations
       where label = 'passed'
     ) $$,
  '23001',
  null,
  'preliminary evaluations cannot be updated'
);

select throws_ok(
  $$ delete from public.solo_evaluations
     where id = (
       select evaluation_id
       from t_solo_evaluations
       where label = 'passed'
     ) $$,
  '23001',
  null,
  'preliminary evaluations cannot be deleted'
);

select pg_catalog.set_config('app.solo_write_path', 'evaluate_v1', true);
select throws_ok(
  $$ update public.solo_contracts
     set target_steps = target_steps + 1
     where id = (
       select contract_id
       from t_solo_contracts
       where label = 'passed'
     ) $$,
  '23001',
  null,
  'locked contract terms stay immutable even through an allowed internal path'
);

select pg_catalog.set_config('app.solo_write_path', 'advance_v1', true);
select throws_ok(
  $$ update public.solo_contracts
     set status = 'active',
         state_changed_at = state_changed_at + interval '1 second'
     where id = (
       select contract_id
       from t_solo_contracts
       where label = 'passed'
     ) $$,
  '23001',
  null,
  'the lifecycle trigger rejects a backward ready-to-settle transition'
);

select is(
  app.settle_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4500000-0000-0000-0000-000000000001',
    (
      select evidence_cutoff + interval '1 second'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'passed'),
  'a passed evaluation settles through the service boundary'
);

select is(
  app.settle_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'passed'),
    'b4500000-0000-0000-0000-000000000001',
    (
      select evidence_cutoff + interval '90 days'
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'passed'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'passed'),
  'an exact settlement retry returns the already-settled contract'
);

select ok(
  (
    select contract.status = 'settled'
       and contract.settlement_disposition = 'released'
       and contract.settled_at = contract.closed_at
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'passed'
    )
  ),
  'a passed preliminary evaluation deterministically derives release'
);

-- ---------------------------------------------------------------------------
-- Inconclusive evaluation waives, and settlement detects ledger conflicts
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'inconclusive',
  'b4333333-3333-3333-3333-333333333333',
  pg_temp.make_solo_contract(
    'b4333333-3333-3333-3333-333333333333',
    'b4c00000-0000-0000-0000-000000000004',
    '2098-03-01'
  )
);

select pg_temp.advance_solo_to_evaluation(
  (select contract_id from t_solo_contracts where label = 'inconclusive')
);

insert into t_solo_evaluations (label, evaluation_id)
values (
  'inconclusive',
  pg_temp.evaluate_solo_at_cutoff(
    (select contract_id from t_solo_contracts where label = 'inconclusive'),
    'inconclusive'
  )
);

insert into app.solo_rpc_requests (
  operation,
  request_scope,
  request_id,
  payload_hash,
  result
)
values (
  'settle_solo_contract_v1',
  (select contract_id from t_solo_contracts where label = 'inconclusive'),
  'b4500000-0000-0000-0000-000000000002',
  extensions.digest(
    pg_catalog.convert_to('different settlement payload', 'UTF8'),
    'sha256'
  ),
  pg_catalog.jsonb_build_object(
    'contract_id',
    (select contract_id from t_solo_contracts where label = 'inconclusive')
  )
);

select throws_ok(
  $$ select app.settle_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'inconclusive'),
       'b4500000-0000-0000-0000-000000000002',
       (select evidence_cutoff from public.solo_contracts where id = (
          select contract_id from t_solo_contracts where label = 'inconclusive'
       ))
     ) $$,
  '22023',
  null,
  'settlement refuses a request UUID whose exact ledger payload differs'
);

select is(
  app.settle_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'inconclusive'),
    'b4500000-0000-0000-0000-000000000003',
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'inconclusive'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'inconclusive'),
  'a fresh settlement request resolves after a rejected ledger conflict'
);

select is(
  (
    select settlement_disposition
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'inconclusive'
    )
  ),
  'waived'::public.solo_settlement_disposition,
  'an inconclusive preliminary evaluation deterministically derives waiver'
);

-- ---------------------------------------------------------------------------
-- At the appeal deadline, filing loses the boundary and settlement wins it
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'failure_expired',
  'b4444444-4444-4444-4444-444444444444',
  pg_temp.make_solo_contract(
    'b4444444-4444-4444-4444-444444444444',
    'b4c00000-0000-0000-0000-000000000005',
    '2098-04-01'
  )
);

select pg_temp.advance_solo_to_evaluation(
  (select contract_id from t_solo_contracts where label = 'failure_expired')
);

insert into t_solo_evaluations (label, evaluation_id)
values (
  'failure_expired',
  pg_temp.evaluate_solo_at_cutoff(
    (select contract_id from t_solo_contracts where label = 'failure_expired'),
    'failed'
  )
);

select throws_ok(
  $$ select app.settle_solo_contract_at_v1(
       (select contract_id from t_solo_contracts where label = 'failure_expired'),
       'b4500000-0000-0000-0000-000000000004',
       (select appeal_deadline - interval '1 microsecond'
        from public.solo_evaluations where id = (
          select evaluation_id
          from t_solo_evaluations
          where label = 'failure_expired'
       ))
     ) $$,
  '23001',
  null,
  'an unappealed preliminary failure cannot settle one microsecond early'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4444444-4444-4444-4444-444444444444"}',
  true
);

select throws_ok(
  $$ select app.file_solo_appeal_at_v1(
       (select contract_id from t_solo_contracts where label = 'failure_expired'),
       (
         select evaluation_id
         from t_solo_evaluations
         where label = 'failure_expired'
       ),
       'b4f00000-0000-0000-0000-000000000001',
       'This filing is exactly at the deadline.',
       (select appeal_deadline from public.solo_evaluations where id = (
          select evaluation_id
          from t_solo_evaluations
          where label = 'failure_expired'
       ))
     ) $$,
  '23001',
  null,
  'an appeal cannot be filed exactly at its locked deadline'
);

select is(
  app.settle_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'failure_expired'),
    'b4500000-0000-0000-0000-000000000004',
    (
      select appeal_deadline
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'failure_expired'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'failure_expired'),
  'an unappealed failure settles exactly at the appeal deadline'
);

select ok(
  (
    select contract.status = 'settled'
       and contract.settlement_disposition = 'forfeited'
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'failure_expired'
    )
  )
  and not exists (
    select 1
    from public.solo_appeals appeal
    where appeal.preliminary_evaluation_id = (
      select evaluation_id
      from t_solo_evaluations
      where label = 'failure_expired'
    )
  ),
  'the shared deadline boundary produces one forfeiture and no appeal'
);

-- ---------------------------------------------------------------------------
-- One filed appeal, one immutable decision, exact retries, and denial
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'appeal_denied',
  'b4555555-5555-5555-5555-555555555555',
  pg_temp.make_solo_contract(
    'b4555555-5555-5555-5555-555555555555',
    'b4c00000-0000-0000-0000-000000000006',
    '2098-05-01'
  )
);

select pg_temp.advance_solo_to_evaluation(
  (select contract_id from t_solo_contracts where label = 'appeal_denied')
);

insert into t_solo_evaluations (label, evaluation_id)
values (
  'appeal_denied',
  pg_temp.evaluate_solo_at_cutoff(
    (select contract_id from t_solo_contracts where label = 'appeal_denied'),
    'failed'
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4555555-5555-5555-5555-555555555555"}',
  true
);

insert into t_solo_appeals (label, appeal_id)
values (
  'appeal_denied',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_solo_contracts where label = 'appeal_denied'),
    (
      select evaluation_id
      from t_solo_evaluations
      where label = 'appeal_denied'
    ),
    'b4f10000-0000-0000-0000-000000000001',
    'The evidence window omitted a valid final sample.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_denied'
      )
    )
  )
);

select is(
  app.file_solo_appeal_at_v1(
    (select contract_id from t_solo_contracts where label = 'appeal_denied'),
    (select evaluation_id from t_solo_evaluations where label = 'appeal_denied'),
    'b4f10000-0000-0000-0000-000000000001',
    'The evidence window omitted a valid final sample.',
    (
      select appeal_deadline + interval '30 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_denied'
      )
    )
  ),
  (select appeal_id from t_solo_appeals where label = 'appeal_denied'),
  'an exact appeal retry recovers even after the filing deadline'
);

select throws_ok(
  $$ select app.file_solo_appeal_at_v1(
       (select contract_id from t_solo_contracts where label = 'appeal_denied'),
       (select evaluation_id from t_solo_evaluations where label = 'appeal_denied'),
       'b4f10000-0000-0000-0000-000000000001',
       'A changed appeal statement.',
       (select evaluated_at + interval '1 day'
        from public.solo_evaluations where id = (
          select evaluation_id from t_solo_evaluations where label = 'appeal_denied'
       ))
     ) $$,
  '22023',
  null,
  'an appeal request UUID cannot change its statement'
);

select throws_ok(
  $$ select app.file_solo_appeal_at_v1(
       (select contract_id from t_solo_contracts where label = 'appeal_denied'),
       (select evaluation_id from t_solo_evaluations where label = 'appeal_denied'),
       'b4f10000-0000-0000-0000-000000000002',
       'A duplicate filing for the same failure.',
       (select evaluated_at + interval '2 days'
        from public.solo_evaluations where id = (
          select evaluation_id from t_solo_evaluations where label = 'appeal_denied'
       ))
     ) $$,
  '23001',
  null,
  'a preliminary failure cannot accept a second appeal filing'
);

select is(
  (
    select count(*)
    from public.solo_appeals
    where preliminary_evaluation_id = (
      select evaluation_id
      from t_solo_evaluations
      where label = 'appeal_denied'
    )
      and event_kind = 'filed'
  ),
  1::bigint,
  'exact retries and rejected filings leave one appeal per failure'
);

insert into t_solo_decisions (label, decision_id)
values (
  'appeal_denied',
  app.decide_solo_appeal_at_v1(
    (select appeal_id from t_solo_appeals where label = 'appeal_denied'),
    'b4d10000-0000-0000-0000-000000000001',
    'denied',
    'evidence_unchanged',
    'solo-reviewer-v1',
    extensions.digest(pg_catalog.convert_to('denied', 'UTF8'), 'sha256'),
    (
      select evaluated_at + interval '2 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_denied'
      )
    )
  )
);

select is(
  app.decide_solo_appeal_at_v1(
    (select appeal_id from t_solo_appeals where label = 'appeal_denied'),
    'b4d10000-0000-0000-0000-000000000001',
    'denied',
    'evidence_unchanged',
    'solo-reviewer-v1',
    extensions.digest(pg_catalog.convert_to('denied', 'UTF8'), 'sha256'),
    (
      select evaluated_at + interval '60 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_denied'
      )
    )
  ),
  (select decision_id from t_solo_decisions where label = 'appeal_denied'),
  'an exact appeal-decision retry returns the immutable decision'
);

select throws_ok(
  $$ select app.decide_solo_appeal_at_v1(
       (select appeal_id from t_solo_appeals where label = 'appeal_denied'),
       'b4d10000-0000-0000-0000-000000000001',
       'upheld',
       'evidence_unchanged',
       'solo-reviewer-v1',
       extensions.digest(pg_catalog.convert_to('denied', 'UTF8'), 'sha256'),
       (select evaluated_at + interval '2 days'
        from public.solo_evaluations where id = (
          select evaluation_id from t_solo_evaluations where label = 'appeal_denied'
       ))
     ) $$,
  '22023',
  null,
  'an appeal-decision request UUID cannot change its decision'
);

select throws_ok(
  $$ select app.decide_solo_appeal_at_v1(
       (select appeal_id from t_solo_appeals where label = 'appeal_denied'),
       'b4d10000-0000-0000-0000-000000000002',
       'denied',
       'second_review',
       'solo-reviewer-v1',
       extensions.digest(pg_catalog.convert_to('second', 'UTF8'), 'sha256'),
       (select evaluated_at + interval '3 days'
        from public.solo_evaluations where id = (
          select evaluation_id from t_solo_evaluations where label = 'appeal_denied'
       ))
     ) $$,
  '23001',
  null,
  'an appeal filing cannot receive a second decision'
);

select is(
  (
    select count(*)
    from public.solo_appeals
    where filing_id = (
      select appeal_id
      from t_solo_appeals
      where label = 'appeal_denied'
    )
      and event_kind = 'decided'
  ),
  1::bigint,
  'exact retries and rejected reviews leave one decision per filing'
);

select throws_ok(
  $$ update public.solo_appeals
     set statement = 'Rewritten'
     where id = (
       select appeal_id
       from t_solo_appeals
       where label = 'appeal_denied'
     ) $$,
  '23001',
  null,
  'appeal filings cannot be updated'
);

select throws_ok(
  $$ delete from public.solo_appeals
     where id = (
       select decision_id
       from t_solo_decisions
       where label = 'appeal_denied'
     ) $$,
  '23001',
  null,
  'appeal decisions cannot be deleted'
);

select is(
  app.settle_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'appeal_denied'),
    'b4500000-0000-0000-0000-000000000005',
    (
      select evaluated_at + interval '3 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_denied'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'appeal_denied'),
  'a decided appeal becomes eligible for logical settlement'
);

select is(
  (
    select settlement_disposition
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'appeal_denied'
    )
  ),
  'forfeited'::public.solo_settlement_disposition,
  'a denied appeal deterministically derives forfeiture'
);

-- ---------------------------------------------------------------------------
-- Upheld and waived decisions derive the remaining settlement dispositions
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values
  (
    'appeal_upheld',
    'b4666666-6666-6666-6666-666666666666',
    pg_temp.make_solo_contract(
      'b4666666-6666-6666-6666-666666666666',
      'b4c00000-0000-0000-0000-000000000007',
      '2098-06-01'
    )
  ),
  (
    'appeal_waived',
    'b4777777-7777-7777-7777-777777777777',
    pg_temp.make_solo_contract(
      'b4777777-7777-7777-7777-777777777777',
      'b4c00000-0000-0000-0000-000000000008',
      '2098-07-01'
    )
  );

select pg_temp.advance_solo_to_evaluation(contract_id)
from t_solo_contracts
where label in ('appeal_upheld', 'appeal_waived')
order by label;

insert into t_solo_evaluations (label, evaluation_id)
select contract.label,
       pg_temp.evaluate_solo_at_cutoff(contract.contract_id, 'failed')
from t_solo_contracts contract
where contract.label in ('appeal_upheld', 'appeal_waived')
order by contract.label;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4666666-6666-6666-6666-666666666666"}',
  true
);
insert into t_solo_appeals (label, appeal_id)
values (
  'appeal_upheld',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_solo_contracts where label = 'appeal_upheld'),
    (select evaluation_id from t_solo_evaluations where label = 'appeal_upheld'),
    'b4f20000-0000-0000-0000-000000000001',
    'The final evidence sample proves completion.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_upheld'
      )
    )
  )
);

insert into t_solo_decisions (label, decision_id)
values (
  'appeal_upheld',
  app.decide_solo_appeal_at_v1(
    (select appeal_id from t_solo_appeals where label = 'appeal_upheld'),
    'b4d20000-0000-0000-0000-000000000001',
    'upheld',
    'late_sample_verified',
    'solo-reviewer-v1',
    extensions.digest(pg_catalog.convert_to('upheld', 'UTF8'), 'sha256'),
    (
      select evaluated_at + interval '2 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_upheld'
      )
    )
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_solo_contracts where label = 'appeal_upheld'),
  'b4500000-0000-0000-0000-000000000006',
  (
    select evaluated_at + interval '3 days'
    from public.solo_evaluations
    where id = (
      select evaluation_id
      from t_solo_evaluations
      where label = 'appeal_upheld'
    )
  )
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4777777-7777-7777-7777-777777777777"}',
  true
);
insert into t_solo_appeals (label, appeal_id)
values (
  'appeal_waived',
  app.file_solo_appeal_at_v1(
    (select contract_id from t_solo_contracts where label = 'appeal_waived'),
    (select evaluation_id from t_solo_evaluations where label = 'appeal_waived'),
    'b4f20000-0000-0000-0000-000000000002',
    'The evidence source was unavailable during review.',
    (
      select evaluated_at + interval '1 day'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_waived'
      )
    )
  )
);

insert into t_solo_decisions (label, decision_id)
values (
  'appeal_waived',
  app.decide_solo_appeal_at_v1(
    (select appeal_id from t_solo_appeals where label = 'appeal_waived'),
    'b4d20000-0000-0000-0000-000000000002',
    'waived',
    'source_unavailable',
    'solo-reviewer-v1',
    extensions.digest(pg_catalog.convert_to('waived', 'UTF8'), 'sha256'),
    (
      select evaluated_at + interval '2 days'
      from public.solo_evaluations
      where id = (
        select evaluation_id
        from t_solo_evaluations
        where label = 'appeal_waived'
      )
    )
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_solo_contracts where label = 'appeal_waived'),
  'b4500000-0000-0000-0000-000000000007',
  (
    select evaluated_at + interval '3 days'
    from public.solo_evaluations
    where id = (
      select evaluation_id
      from t_solo_evaluations
      where label = 'appeal_waived'
    )
  )
);

select ok(
  (
    select settlement_disposition = 'released'
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'appeal_upheld'
    )
  )
  and (
    select settlement_disposition = 'waived'
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'appeal_waived'
    )
  ),
  'upheld and waived appeal decisions derive release and waiver respectively'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4555555-5555-5555-5555-555555555555"}',
  true
);

select ok(
  (
    select count(*) = 1
       and bool_and(owner_id = 'b4555555-5555-5555-5555-555555555555')
    from public.solo_contracts
  )
  and (
    select count(*) = 1
       and bool_and(owner_id = 'b4555555-5555-5555-5555-555555555555')
    from public.solo_evaluations
  )
  and (
    select count(*) = 2
       and bool_and(owner_id = 'b4555555-5555-5555-5555-555555555555')
    from public.solo_appeals
  ),
  'an active owner reads only their contract, evaluation, filing, and decision'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4666666-6666-6666-6666-666666666666"}',
  true
);

select ok(
  (
    select count(*) = 1
       and bool_and(owner_id = 'b4666666-6666-6666-6666-666666666666')
    from public.solo_contracts
  )
  and (
    select count(*) = 1
       and bool_and(owner_id = 'b4666666-6666-6666-6666-666666666666')
    from public.solo_evaluations
  )
  and (
    select count(*) = 2
       and bool_and(owner_id = 'b4666666-6666-6666-6666-666666666666')
    from public.solo_appeals
  ),
  'a second active owner cannot read the first owner adjudication records'
);

reset role;

-- ---------------------------------------------------------------------------
-- D81 deletion: pre-start work cancels; post-start facts finish server-side
-- ---------------------------------------------------------------------------

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'delete_pre_start',
  'b4888888-8888-8888-8888-888888888888',
  pg_temp.make_solo_contract(
    'b4888888-8888-8888-8888-888888888888',
    'b4c00000-0000-0000-0000-000000000009',
    '2098-08-01'
  )
);

create temporary table t_solo_deletions (
  owner_id uuid primary key,
  result jsonb not null
);
grant insert on t_solo_deletions to service_role;

reset role;
set local role service_role;
insert into t_solo_deletions (owner_id, result)
values (
  'b4888888-8888-8888-8888-888888888888',
  public.delete_account('b4888888-8888-8888-8888-888888888888')
);
reset role;

select ok(
  (
    select contract.status = 'cancelled'
       and contract.cancellation_reason = 'account_deleted'
       and contract.settlement_disposition = 'cancelled'
       and contract.closed_at = contract.cancelled_at
       and contract.cancelled_at = (
         select profile.deleted_at
         from public.profiles profile
         where profile.id = contract.owner_id
       )
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_pre_start'
    )
  )
  and not (
    select eligible
    from app.solo_beta_eligibility
    where owner_id = 'b4888888-8888-8888-8888-888888888888'
  )
  and (
    select beta.updated_at = profile.deleted_at
    from app.solo_beta_eligibility beta
    join public.profiles profile on profile.id = beta.owner_id
    where beta.owner_id = 'b4888888-8888-8888-8888-888888888888'
  )
  and not exists (
    select 1
    from auth.users
    where id = 'b4888888-8888-8888-8888-888888888888'
  )
  and (
    select deleted_at is not null
    from public.profiles
    where id = 'b4888888-8888-8888-8888-888888888888'
  ),
  'account deletion cancels only the pre-start contract and revokes eligibility'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4888888-8888-8888-8888-888888888888"}',
  true
);

select is(
  (select count(*) from public.solo_contracts)
  + (select count(*) from public.solo_evaluations)
  + (select count(*) from public.solo_appeals),
  0::bigint,
  'the deleted pre-start owner stale JWT reads no Solo records'
);

select throws_ok(
  $$ select public.cancel_solo_contract_v1(
       (
         select contract_id
         from t_solo_contracts
         where label = 'delete_pre_start'
       ),
       'b4ca0000-0000-0000-0000-000000000004'
     ) $$,
  '42501',
  null,
  'the deleted pre-start owner stale JWT cannot invoke an owner mutation'
);
reset role;

insert into t_solo_contracts (label, owner_id, contract_id)
values (
  'delete_post_start',
  'b4999999-9999-9999-9999-999999999999',
  pg_temp.make_solo_contract(
    'b4999999-9999-9999-9999-999999999999',
    'b4c00000-0000-0000-0000-000000000010',
    '2098-09-01'
  )
);

select app.advance_solo_contract_at_v1(
  (select contract_id from t_solo_contracts where label = 'delete_post_start'),
  'b4a30000-0000-0000-0000-000000000001',
  'active',
  (
    select starts_at
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_post_start'
    )
  )
);

set local role service_role;
insert into t_solo_deletions (owner_id, result)
values (
  'b4999999-9999-9999-9999-999999999999',
  public.delete_account('b4999999-9999-9999-9999-999999999999')
);
reset role;

select ok(
  (
    select contract.status = 'active'
       and contract.closed_at is null
       and contract.cancellation_reason is null
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_post_start'
    )
  )
  and not (
    select eligible
    from app.solo_beta_eligibility
    where owner_id = 'b4999999-9999-9999-9999-999999999999'
  ),
  'account deletion preserves post-start facts for service-owned finality'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"b4999999-9999-9999-9999-999999999999"}',
  true
);

select is(
  (select count(*) from public.solo_contracts),
  0::bigint,
  'the deleted post-start owner stale JWT cannot read its preserved contract'
);

select throws_ok(
  $$ select public.cancel_solo_contract_v1(
       (
         select contract_id
         from t_solo_contracts
         where label = 'delete_post_start'
       ),
       'b4ca0000-0000-0000-0000-000000000005'
     ) $$,
  '42501',
  null,
  'the deleted post-start owner stale JWT cannot cancel preserved work'
);
reset role;
select pg_catalog.set_config('request.jwt.claims', '{}', true);

select is(
  app.advance_solo_contract_at_v1(
    (select contract_id from t_solo_contracts where label = 'delete_post_start'),
    'b4a30000-0000-0000-0000-000000000002',
    'awaiting_evaluation',
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'delete_post_start'
      )
    )
  ),
  (select contract_id from t_solo_contracts where label = 'delete_post_start'),
  'the service can close the evidence window after owner deletion'
);

insert into t_solo_evaluations (label, evaluation_id)
values (
  'delete_post_start',
  app.record_solo_evaluation_at_v1(
    (select contract_id from t_solo_contracts where label = 'delete_post_start'),
    'b4e30000-0000-0000-0000-000000000001',
    'passed',
    'steps_met',
    'solo-evaluator-v1',
    extensions.digest(
      pg_catalog.convert_to('deleted-owner-pass', 'UTF8'),
      'sha256'
    ),
    (
      select evidence_cutoff
      from public.solo_contracts
      where id = (
        select contract_id
        from t_solo_contracts
        where label = 'delete_post_start'
      )
    )
  )
);

select app.settle_solo_contract_at_v1(
  (select contract_id from t_solo_contracts where label = 'delete_post_start'),
  'b4500000-0000-0000-0000-000000000008',
  (
    select evidence_cutoff + interval '1 second'
    from public.solo_contracts
    where id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_post_start'
    )
  )
);

select ok(
  (
    select contract.status = 'settled'
       and contract.settlement_disposition = 'released'
       and contract.closed_at = contract.settled_at
    from public.solo_contracts contract
    where contract.id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_post_start'
    )
  )
  and (
    select count(*) = 1
    from public.solo_evaluations evaluation
    where evaluation.contract_id = (
      select contract_id
      from t_solo_contracts
      where label = 'delete_post_start'
    )
  ),
  'post-start deletion preserves an append-only evaluation and final settlement'
);

select * from finish();
rollback;
