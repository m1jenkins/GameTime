-- Stripe sandbox beta controls: default-off runtime, exact database allowlist,
-- direct-RPC enforcement, controls-era retry provenance, safe shutdown, and
-- reconciliation/no-charge continuity.

begin;
select no_plan();
set local timezone = 'UTC';

insert into auth.users (id) values
  ('ca111111-1111-1111-1111-111111111111'),
  ('ca222222-2222-2222-2222-222222222222'),
  ('ca333333-3333-3333-3333-333333333333'),
  ('ca444444-4444-4444-4444-444444444444'),
  ('ca555555-5555-5555-5555-555555555555'),
  ('ca666666-6666-6666-6666-666666666666');

insert into public.profiles (id, handle, display_name, timezone) values
  ('ca111111-1111-1111-1111-111111111111', 'controlsa', 'Controls A', 'UTC'),
  ('ca222222-2222-2222-2222-222222222222', 'controlsb', 'Controls B', 'UTC'),
  ('ca333333-3333-3333-3333-333333333333', 'controlsc', 'Controls C', 'UTC'),
  ('ca444444-4444-4444-4444-444444444444', 'controlsd', 'Controls D', 'UTC'),
  ('ca555555-5555-5555-5555-555555555555', 'controlse', 'Controls E', 'UTC'),
  ('ca666666-6666-6666-6666-666666666666', 'controlsf', 'Controls F', 'UTC');

-- ---------------------------------------------------------------------------
-- Private shape, least privilege, and fail-closed defaults
-- ---------------------------------------------------------------------------

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app'
      and relation.relname in (
        'personal_stripe_sandbox_runtime',
        'personal_stripe_sandbox_beta_eligibility',
        'personal_stripe_sandbox_control_requests'
      )
      and relation.relkind = 'r'
  ),
  3::bigint,
  'three private tables own runtime, exact eligibility, and control requests'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app'
      and relation.relname in (
        'personal_stripe_sandbox_runtime',
        'personal_stripe_sandbox_beta_eligibility',
        'personal_stripe_sandbox_control_requests'
      )
      and relation.relrowsecurity
  ),
  3::bigint,
  'RLS is enabled on all private Stripe beta control tables'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'app'
      and policy.tablename in (
        'personal_stripe_sandbox_runtime',
        'personal_stripe_sandbox_beta_eligibility',
        'personal_stripe_sandbox_control_requests'
      )
  ),
  0::bigint,
  'private Stripe beta control tables expose no RLS policy'
);

select ok(
  not exists (
    select 1
    from (
      values ('public'), ('anon'), ('authenticated'), ('service_role')
    ) actor(role_name)
    cross join (
      values
        ('app.personal_stripe_sandbox_runtime'),
        ('app.personal_stripe_sandbox_beta_eligibility'),
        ('app.personal_stripe_sandbox_control_requests')
    ) relation(relation_name)
    cross join (
      values ('select'), ('insert'), ('update'), ('delete'), ('truncate')
    ) operation(privilege_name)
    where has_table_privilege(
      actor.role_name,
      relation.relation_name,
      operation.privilege_name
    )
  ),
  'API roles have no direct Stripe beta control-table privileges'
);

select is(
  (
    select runtime.payment_activity_enabled
    from app.personal_stripe_sandbox_runtime runtime
    where runtime.singleton
  ),
  false,
  'the global Stripe sandbox payment switch starts disabled'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_beta_eligibility
  ),
  0::bigint,
  'the exact tester allowlist starts empty'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_control_requests
  ),
  0::bigint,
  'the control request ledger starts empty'
);

select has_function(
  'public',
  'set_personal_stripe_sandbox_runtime_v1',
  array['uuid', 'boolean'],
  'the kill switch has one versioned service boundary'
);

select has_function(
  'public',
  'set_personal_stripe_sandbox_beta_eligibility_v1',
  array['uuid', 'uuid', 'boolean'],
  'the exact tester allowlist has one versioned service boundary'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.set_personal_stripe_sandbox_runtime_v1(uuid,boolean)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.set_personal_stripe_sandbox_beta_eligibility_v1(uuid,uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_personal_stripe_sandbox_runtime_v1(uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_personal_stripe_sandbox_beta_eligibility_v1(uuid,uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.set_personal_stripe_sandbox_runtime_v1(uuid,boolean)',
    'execute'
  ),
  'only service_role can change the switch or exact tester allowlist'
);

select ok(
  not has_function_privilege(
    'service_role',
    'app.require_personal_stripe_sandbox_beta_admission_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'app.lock_personal_stripe_sandbox_control_v1(boolean)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.require_personal_stripe_sandbox_beta_admission_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.lock_personal_stripe_sandbox_control_v1(boolean)',
    'execute'
  ),
  'the common admission and control-lock helpers remain private'
);

select is(
  (
    select count(*)
    from information_schema.columns column_def
    where column_def.table_schema = 'app'
      and column_def.table_name in (
        'personal_stripe_sandbox_setups',
        'personal_stripe_sandbox_agreements'
      )
      and column_def.column_name in (
        'beta_authorization_version',
        'beta_authorized_at'
      )
  ),
  4::bigint,
  'setups and agreements persist frozen beta-authorization provenance'
);

set local role service_role;

select throws_ok(
  $$ update app.personal_stripe_sandbox_runtime
     set payment_activity_enabled = true
     where singleton $$,
  '42501',
  null,
  'service_role cannot bypass the versioned kill-switch RPC'
);

select throws_ok(
  $$ insert into app.personal_stripe_sandbox_beta_eligibility (
       owner_id, eligible
     )
     values ('ca222222-2222-2222-2222-222222222222', true) $$,
  '42501',
  null,
  'service_role cannot bypass the versioned allowlist RPC'
);

reset role;

-- ---------------------------------------------------------------------------
-- Exact control requests and direct database admission
-- ---------------------------------------------------------------------------

set local role service_role;

select is(
  public.set_personal_stripe_sandbox_beta_eligibility_v1(
    'ca900000-0000-0000-0000-000000000001',
    'ca111111-1111-1111-1111-111111111111',
    true
  ),
  true,
  'service_role can add one exact active tester'
);

select is(
  public.set_personal_stripe_sandbox_beta_eligibility_v1(
    'ca900000-0000-0000-0000-000000000001',
    'ca111111-1111-1111-1111-111111111111',
    true
  ),
  true,
  'an identical allowlist request is an exact replay'
);

select throws_ok(
  $$ select public.set_personal_stripe_sandbox_beta_eligibility_v1(
       'ca900000-0000-0000-0000-000000000001',
       'ca111111-1111-1111-1111-111111111111',
       false
     ) $$,
  '22023',
  null,
  'an allowlist request UUID cannot be reused with another value'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_v1(
       'ca100000-0000-0000-0000-000000000001',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'allowlisting alone cannot bypass the default-off runtime switch'
);

reset role;
set local role service_role;

select is(
  public.set_personal_stripe_sandbox_runtime_v1(
    'ca900000-0000-0000-0000-000000000002',
    true
  ),
  true,
  'service_role can enable local sandbox payment activity'
);

select is(
  public.set_personal_stripe_sandbox_runtime_v1(
    'ca900000-0000-0000-0000-000000000002',
    true
  ),
  true,
  'an identical runtime request is an exact replay'
);

select throws_ok(
  $$ select public.set_personal_stripe_sandbox_runtime_v1(
       'ca900000-0000-0000-0000-000000000002',
       false
     ) $$,
  '22023',
  null,
  'a runtime request UUID cannot be reused with another value'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca222222-2222-2222-2222-222222222222","user_metadata":{"personal_stripe_sandbox_beta":true}}',
  true
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_v1(
       'ca200000-0000-0000-0000-000000000001',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'forged JWT metadata cannot manufacture database beta eligibility'
);

reset role;
set local role service_role;

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_service_v1(
       'ca222222-2222-2222-2222-222222222222',
       'ca200000-0000-0000-0000-000000000002',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'the service setup path cannot bypass the exact tester allowlist'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_controls_setup_a as
select public.begin_personal_stripe_sandbox_setup_v1(
  'ca100000-0000-0000-0000-000000000001',
  'daily',
  10000,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select is(
  (select value ->> 'replayed' from t_controls_setup_a),
  'false',
  'runtime-on plus the exact allowlist admits a direct setup mutation'
);

reset role;
grant select on t_controls_setup_a to service_role;
set local role service_role;

select public.record_personal_stripe_sandbox_customer_v1(
  'ca111111-1111-1111-1111-111111111111',
  'cus_ca111111111111111111111111111111'
);

select public.record_personal_stripe_sandbox_setup_v1(
  'ca111111-1111-1111-1111-111111111111',
  (select (value ->> 'setup_id')::uuid from t_controls_setup_a),
  'cus_ca111111111111111111111111111111',
  'seti_ca11111111111111111111111111111',
  'pm_ca111111111111111111111111111111',
  'succeeded'
);

create temporary table t_controls_challenge_a as
select public.commit_personal_stripe_sandbox_challenge_service_v1(
  'ca111111-1111-1111-1111-111111111111',
  'ca100000-0000-0000-0000-000000000001',
  (select (value ->> 'setup_id')::uuid from t_controls_setup_a),
  'daily',
  10000,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

grant select on t_controls_challenge_a to authenticated;

reset role;

select ok(
  exists (
    select 1
    from app.personal_stripe_sandbox_setups setup
    where setup.id =
      (select (value ->> 'setup_id')::uuid from t_controls_setup_a)
      and setup.beta_authorization_version =
        'personal-stripe-sandbox-beta-v1'
      and setup.beta_authorized_at is not null
  ),
  'a newly admitted setup freezes its control authorization'
);

select ok(
  exists (
    select 1
    from app.personal_stripe_sandbox_agreements agreement
    where agreement.challenge_id =
      (select (value ->> 'challenge_id')::uuid from t_controls_challenge_a)
      and agreement.beta_authorization_version =
        'personal-stripe-sandbox-beta-v1'
      and agreement.beta_authorized_at is not null
  ),
  'a newly admitted commitment freezes its control authorization'
);

set local role service_role;

create temporary table t_controls_unused_setup_a as
select public.begin_personal_stripe_sandbox_setup_service_v1(
  'ca111111-1111-1111-1111-111111111111',
  'ca100000-0000-0000-0000-000000000002',
  'daily',
  10000,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select public.record_personal_stripe_sandbox_setup_v1(
  'ca111111-1111-1111-1111-111111111111',
  (select (value ->> 'setup_id')::uuid from t_controls_unused_setup_a),
  'cus_ca111111111111111111111111111111',
  'seti_ca11111111111111111111111111112',
  'pm_ca111111111111111111111111111112',
  'succeeded'
);

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'ca900000-0000-0000-0000-000000000003',
  'ca222222-2222-2222-2222-222222222222',
  true
);

select throws_ok(
  $$ select public.commit_personal_stripe_sandbox_challenge_service_v1(
       'ca222222-2222-2222-2222-222222222222',
       'ca100000-0000-0000-0000-000000000002',
       (select (value ->> 'setup_id')::uuid
        from t_controls_unused_setup_a),
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '23001',
  null,
  'an allowlisted second owner still cannot consume another owner setup'
);

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'ca900000-0000-0000-0000-000000000004',
  'ca222222-2222-2222-2222-222222222222',
  false
);

-- A stale authenticated identity and an explicit service owner both fail at
-- the shared active-actor boundary.
select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'ca900000-0000-0000-0000-000000000005',
  'ca333333-3333-3333-3333-333333333333',
  true
);

select public.delete_account(
  'ca333333-3333-3333-3333-333333333333'
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_service_v1(
       'ca333333-3333-3333-3333-333333333333',
       'ca300000-0000-0000-0000-000000000001',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'a deleted explicit service owner cannot start a Stripe setup'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca333333-3333-3333-3333-333333333333"}',
  true
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_v1(
       'ca300000-0000-0000-0000-000000000002',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'a stale JWT cannot start a Stripe setup after account deletion'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_setups setup
    where setup.user_id = 'ca333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'stale actor refusals leave no Stripe setup row'
);

-- ---------------------------------------------------------------------------
-- Charge-capable fixtures for allowlist filtering and shutdown continuity
-- ---------------------------------------------------------------------------

create function pg_temp.make_controls_paid_fixture(p_user_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_challenge      uuid := gen_random_uuid();
  v_setup          uuid := gen_random_uuid();
  v_customer       text := 'cus_' || replace(p_user_id::text, '-', '');
  v_setup_intent   text := 'seti_' || replace(v_setup::text, '-', '');
  v_payment_method text := 'pm_' || replace(gen_random_uuid()::text, '-', '');
  v_now            timestamptz := clock_timestamp();
  v_starts_at      timestamptz := v_now - interval '9 days';
  v_ends_at        timestamptz := v_now - interval '2 days';
  v_cutoff         timestamptz := v_now - interval '1 day';
begin
  insert into public.contests (
    id,
    title,
    created_by,
    challenge_model,
    metric,
    cadence,
    target_value,
    stake_amount_cents,
    tie_break,
    starts_at,
    ends_at,
    max_participants,
    status
  )
  values (
    v_challenge,
    'Stripe controls fixture',
    p_user_id,
    'personal_accountability',
    'steps',
    'daily',
    10000,
    1000,
    'void',
    v_starts_at,
    v_ends_at,
    1,
    'pending'
  );

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  )
  values (v_challenge, p_user_id, 'accepted', 'UTC', null);

  insert into public.personal_challenge_terms (
    challenge_id,
    user_id,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    settlement_mode,
    terms_version,
    timezone,
    agreed_at,
    evidence_cutoff,
    closed_at
  )
  values (
    v_challenge,
    p_user_id,
    'daily',
    10000,
    1000,
    'USD',
    'test_only',
    'personal-v1',
    'UTC',
    v_starts_at - interval '1 day',
    v_cutoff,
    null
  );

  insert into app.personal_stripe_sandbox_customers (
    user_id, stripe_customer_id
  )
  values (p_user_id, v_customer)
  on conflict (user_id) do nothing;

  select customer.stripe_customer_id
  into v_customer
  from app.personal_stripe_sandbox_customers customer
  where customer.user_id = p_user_id;

  insert into app.personal_stripe_sandbox_setups (
    id,
    user_id,
    request_id,
    payload_hash,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    timezone,
    agreement_version,
    consent_version,
    consented_at,
    expires_at,
    stripe_customer_id,
    stripe_setup_intent_id,
    stripe_payment_method_id,
    status,
    succeeded_at,
    beta_authorization_version,
    beta_authorized_at
  )
  values (
    v_setup,
    p_user_id,
    gen_random_uuid(),
    decode(repeat('11', 32), 'hex'),
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1',
    v_now - interval '1 hour',
    v_now + interval '23 hours',
    v_customer,
    v_setup_intent,
    v_payment_method,
    'succeeded',
    v_now - interval '30 minutes',
    'personal-stripe-sandbox-beta-v1',
    v_now - interval '1 hour'
  );

  insert into app.personal_stripe_sandbox_agreements (
    challenge_id,
    user_id,
    setup_id,
    create_request_id,
    creation_payload_hash,
    setup_payload_hash,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    timezone,
    agreement_version,
    consent_version,
    consented_at,
    stripe_customer_id,
    stripe_setup_intent_id,
    stripe_payment_method_id,
    beta_authorization_version,
    beta_authorized_at
  )
  values (
    v_challenge,
    p_user_id,
    v_setup,
    gen_random_uuid(),
    decode(repeat('22', 32), 'hex'),
    decode(repeat('11', 32), 'hex'),
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1',
    v_now - interval '1 hour',
    v_customer,
    v_setup_intent,
    v_payment_method,
    'personal-stripe-sandbox-beta-v1',
    v_now - interval '30 minutes'
  );

  update app.personal_stripe_sandbox_setups setup
  set
    consumed_at = v_now - interval '10 minutes',
    consumed_challenge_id = v_challenge
  where setup.id = v_setup;

  return v_challenge;
end;
$$;

create function pg_temp.add_controls_missed_result(p_challenge_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_user_id    uuid;
  v_cutoff     timestamptz;
  v_assessment uuid := gen_random_uuid();
  v_result     uuid := gen_random_uuid();
  v_days       jsonb := jsonb_build_array(
    jsonb_build_object('local_date', '2099-01-01', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-02', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-03', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-04', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-05', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-06', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-07', 'total_steps', 0)
  );
begin
  select terms.user_id, terms.evidence_cutoff
  into v_user_id, v_cutoff
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  insert into app.personal_evidence_assessments (
    id,
    challenge_id,
    user_id,
    request_id,
    evidence_state,
    evidence_cutoff,
    assessment_version,
    evidence_digest,
    full_expected_buckets,
    covered_buckets,
    total_steps,
    daily_totals,
    assessed_at
  )
  values (
    v_assessment,
    p_challenge_id,
    v_user_id,
    gen_random_uuid(),
    'complete',
    v_cutoff,
    'personal-v1',
    decode(repeat('33', 32), 'hex'),
    168,
    168,
    0,
    v_days,
    v_cutoff + interval '30 minutes'
  );

  insert into public.personal_challenge_results (
    id,
    challenge_id,
    user_id,
    assessment_id,
    outcome,
    reason,
    evidence_state,
    evidence_cutoff,
    total_steps,
    daily_totals,
    commitment_waived,
    published_at
  )
  values (
    v_result,
    p_challenge_id,
    v_user_id,
    v_assessment,
    'missed_goal',
    'target_missed',
    'complete',
    v_cutoff,
    0,
    v_days,
    false,
    v_cutoff + interval '1 hour'
  );

  return v_result;
end;
$$;

alter table public.contests
  disable trigger contests_enforce_status_transition;
update public.contests contest
set
  status = 'cancelled',
  cancellation_reason = 'creator_cancelled',
  cancelled_at = clock_timestamp()
where contest.id =
  (select (value ->> 'challenge_id')::uuid from t_controls_challenge_a);
alter table public.contests
  enable trigger contests_enforce_status_transition;

alter table public.contests
  disable trigger contests_assert_future_window;

create temporary table t_controls_charge_a as
select pg_temp.make_controls_paid_fixture(
  'ca111111-1111-1111-1111-111111111111'
) as challenge_id;

create temporary table t_controls_skipped_d as
select pg_temp.make_controls_paid_fixture(
  'ca444444-4444-4444-4444-444444444444'
) as challenge_id;

create temporary table t_controls_review_e as
select pg_temp.make_controls_paid_fixture(
  'ca555555-5555-5555-5555-555555555555'
) as challenge_id;

create temporary table t_controls_waiver_f as
select pg_temp.make_controls_paid_fixture(
  'ca666666-6666-6666-6666-666666666666'
) as challenge_id;

alter table public.contests
  enable trigger contests_assert_future_window;

alter table public.contests
  disable trigger contests_enforce_status_transition;

update public.contests contest
set
  status = 'finalized',
  activated_at = clock_timestamp()
where contest.id in (
  (select challenge_id from t_controls_charge_a),
  (select challenge_id from t_controls_skipped_d),
  (select challenge_id from t_controls_review_e),
  (select challenge_id from t_controls_waiver_f)
);

alter table public.contests
  enable trigger contests_enforce_status_transition;

select pg_temp.add_controls_missed_result(
  (select challenge_id from t_controls_charge_a)
);
select pg_temp.add_controls_missed_result(
  (select challenge_id from t_controls_skipped_d)
);
select pg_temp.add_controls_missed_result(
  (select challenge_id from t_controls_review_e)
);
select pg_temp.add_controls_missed_result(
  (select challenge_id from t_controls_waiver_f)
);

update app.personal_stripe_sandbox_payment_reviews review
set
  opened_at = statement_timestamp() - interval '8 days',
  review_deadline = statement_timestamp() - interval '1 day'
where review.challenge_id in (
  (select challenge_id from t_controls_charge_a),
  (select challenge_id from t_controls_skipped_d)
);

create temporary table t_controls_review_ids as
select review.challenge_id, review.id as review_id
from app.personal_stripe_sandbox_payment_reviews review
where review.challenge_id in (
  (select challenge_id from t_controls_charge_a),
  (select challenge_id from t_controls_skipped_d),
  (select challenge_id from t_controls_review_e),
  (select challenge_id from t_controls_waiver_f)
);

grant select on t_controls_charge_a,
                t_controls_skipped_d,
                t_controls_review_e,
                t_controls_waiver_f,
                t_controls_review_ids
  to service_role;
grant select on t_controls_charge_a to authenticated;

set local role service_role;

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'ca900000-0000-0000-0000-000000000006',
  'ca555555-5555-5555-5555-555555555555',
  true
);

create temporary table t_controls_claims as
select public.claim_personal_stripe_sandbox_charges_v1(
  'ca900000-0000-0000-0000-000000000101',
  10
) as value;

reset role;

select is(
  jsonb_array_length((select value from t_controls_claims)),
  1,
  'the enabled worker claims only the exact allowlisted owner'
);

select is(
  (
    select review.state
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id =
      (select challenge_id from t_controls_charge_a)
  ),
  'confirmed_miss',
  'an allowlisted controls-era miss may become charge-authorized'
);

select is(
  (
    select review.state
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id =
      (select challenge_id from t_controls_skipped_d)
  ),
  'review_open',
  'a nonallowlisted expired miss remains provisional'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id =
      (select challenge_id from t_controls_skipped_d)
  ),
  0::bigint,
  'a nonallowlisted owner receives no simulated charge command'
);

select is(
  (
    select command.attempt_count
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id =
      (select challenge_id from t_controls_charge_a)
  ),
  1::smallint,
  'the admitted command is leased for exactly one provider attempt'
);

-- ---------------------------------------------------------------------------
-- Switch-off: block new authority/dispatch, preserve exact recovery and waiver
-- ---------------------------------------------------------------------------

set local role service_role;

select public.set_personal_stripe_sandbox_runtime_v1(
  'ca900000-0000-0000-0000-000000000007',
  false
);

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'ca900000-0000-0000-0000-000000000008',
  'ca111111-1111-1111-1111-111111111111',
  false
);

select is(
  (
    public.begin_personal_stripe_sandbox_setup_service_v1(
      'ca111111-1111-1111-1111-111111111111',
      'ca100000-0000-0000-0000-000000000001',
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      null,
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1'
    ) ->> 'replayed'
  ),
  'true',
  'an exact controls-era setup retry survives switch-off and revocation'
);

select is(
  (
    public.commit_personal_stripe_sandbox_challenge_service_v1(
      'ca111111-1111-1111-1111-111111111111',
      'ca100000-0000-0000-0000-000000000001',
      (select (value ->> 'setup_id')::uuid from t_controls_setup_a),
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      null,
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1'
    ) ->> 'replayed'
  ),
  'true',
  'an exact controls-era commitment retry survives switch-off and revocation'
);

select is(
  (
    public.settle_personal_stripe_sandbox_review_v1(
      (
        select review.review_id
        from t_controls_review_ids review
        where review.challenge_id =
          (select challenge_id from t_controls_charge_a)
      ),
      'confirm_miss',
      'review_window_expired',
      null
    ) ->> 'replayed'
  ),
  'true',
  'an exact terminal settlement retry survives switch-off and revocation'
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_service_v1(
       'ca111111-1111-1111-1111-111111111111',
       'ca100000-0000-0000-0000-000000000001',
       'daily',
       11000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '22023',
  null,
  'a changed setup retry remains rejected while controls are off'
);

select throws_ok(
  $$ select public.commit_personal_stripe_sandbox_challenge_service_v1(
       'ca111111-1111-1111-1111-111111111111',
       'ca100000-0000-0000-0000-000000000001',
       (select (value ->> 'setup_id')::uuid from t_controls_setup_a),
       'daily',
       11000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '22023',
  null,
  'a changed commitment retry remains rejected while controls are off'
);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_service_v1(
       'ca111111-1111-1111-1111-111111111111',
       'ca100000-0000-0000-0000-000000000003',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'switch-off refuses a new service setup'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.create_personal_challenge_with_stripe_sandbox_v2(
       'ca100000-0000-0000-0000-000000000002',
       (select (value ->> 'setup_id')::uuid
        from t_controls_unused_setup_a),
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'switch-off refuses the authenticated commitment wrapper'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

select is(
  (
    select setup.consumed_at
    from app.personal_stripe_sandbox_setups setup
    where setup.id =
      (select (value ->> 'setup_id')::uuid from t_controls_unused_setup_a)
  ),
  null::timestamptz,
  'a blocked commitment leaves the admitted setup unused'
);

-- Null provenance models a row that predates these controls. It must never
-- acquire the exact-retry exemption retroactively.
savepoint controls_legacy_setup_marker;
alter table app.personal_stripe_sandbox_setups
  disable trigger personal_stripe_setups_freeze_beta_authorization;
update app.personal_stripe_sandbox_setups setup
set
  beta_authorization_version = null,
  beta_authorized_at = null
where setup.id =
  (select (value ->> 'setup_id')::uuid from t_controls_setup_a);

select throws_ok(
  $$ select public.begin_personal_stripe_sandbox_setup_service_v1(
       'ca111111-1111-1111-1111-111111111111',
       'ca100000-0000-0000-0000-000000000001',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'a pre-controls setup row cannot claim the exact-retry exemption'
);
rollback to savepoint controls_legacy_setup_marker;
release savepoint controls_legacy_setup_marker;

savepoint controls_legacy_agreement_marker;
alter table app.personal_stripe_sandbox_agreements
  disable trigger personal_stripe_agreements_freeze_beta_authorization;
update app.personal_stripe_sandbox_agreements agreement
set
  beta_authorization_version = null,
  beta_authorized_at = null
where agreement.challenge_id =
  (select (value ->> 'challenge_id')::uuid from t_controls_challenge_a);

select throws_ok(
  $$ select public.commit_personal_stripe_sandbox_challenge_service_v1(
       'ca111111-1111-1111-1111-111111111111',
       'ca100000-0000-0000-0000-000000000001',
       (select (value ->> 'setup_id')::uuid from t_controls_setup_a),
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '42501',
  null,
  'a pre-controls agreement row cannot claim the exact-retry exemption'
);
rollback to savepoint controls_legacy_agreement_marker;
release savepoint controls_legacy_agreement_marker;

set local role service_role;

select is(
  (
    public.request_personal_stripe_sandbox_review_service_v1(
      'ca555555-5555-5555-5555-555555555555',
      (select challenge_id from t_controls_review_e),
      'injury_attestation',
      'case-e'
    ) ->> 'review_state'
  ),
  'under_review',
  'review filing remains available while payment activity is off'
);

select throws_ok(
  format(
    'select public.settle_personal_stripe_sandbox_review_v1(%L, %L, %L, %L)',
    (
      select review.review_id
      from t_controls_review_ids review
      where review.challenge_id =
        (select challenge_id from t_controls_review_e)
    ),
    'confirm_miss',
    'review_upheld',
    'case-e'
  ),
  '42501',
  null,
  'switch-off refuses a new charge-authorizing review decision'
);

select is(
  (
    public.settle_personal_stripe_sandbox_review_v1(
      (
        select review.review_id
        from t_controls_review_ids review
        where review.challenge_id =
          (select challenge_id from t_controls_review_e)
      ),
      'waive',
      'founder_waiver',
      'case-e'
    ) ->> 'state'
  ),
  'waived',
  'an audited no-charge waiver remains available while off'
);

reset role;

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id =
      (select challenge_id from t_controls_review_e)
  ),
  0::bigint,
  'the off-state waiver creates no charge command'
);

update app.personal_stripe_sandbox_payment_reviews review
set
  opened_at = statement_timestamp() - interval '8 days',
  review_deadline = statement_timestamp() - interval '1 day',
  state = 'under_review',
  review_started_at = statement_timestamp() - interval '7 days',
  review_reason_code = 'injury_attestation',
  review_reference = 'case-f',
  updated_at = statement_timestamp()
where review.challenge_id =
  (select challenge_id from t_controls_waiver_f);

set local role service_role;

create temporary table t_controls_off_claims as
select public.claim_personal_stripe_sandbox_charges_v1(
  'ca900000-0000-0000-0000-000000000102',
  10
) as value;

reset role;

select is(
  jsonb_array_length((select value from t_controls_off_claims)),
  0,
  'switch-off returns no charge work to the dispatcher'
);

select is(
  (
    select review.state
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id =
      (select challenge_id from t_controls_waiver_f)
  ),
  'waived',
  'the off-state worker still closes an overdue filed review with no charge'
);

select is(
  (
    select command.attempt_count
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id =
      (select challenge_id from t_controls_charge_a)
  ),
  1::smallint,
  'switch-off does not lease an existing command for another dispatch'
);

-- Provider facts for an already-leased command remain authoritative while off.
set local role service_role;

select is(
  (
    public.apply_personal_stripe_sandbox_webhook_v1(
      'evt_CA11111111111111111111111111111',
      decode(repeat('44', 32), 'hex'),
      'payment_intent.succeeded',
      'pi_CA111111111111111111111111111111',
      '2026-02-25.clover',
      clock_timestamp(),
      'applied',
      'payment',
      'succeeded',
      false,
      ((select value from t_controls_claims) -> 0)
        ->> 'stripe_customer_id',
      ((select value from t_controls_claims) -> 0)
        ->> 'stripe_payment_method_id',
      1000,
      'USD',
      null,
      (((select value from t_controls_claims) -> 0) ->> 'command_id')::uuid
    ) ->> 'replayed'
  ),
  'false',
  'normalized webhook reconciliation remains operational while off'
);

select is(
  (
    public.apply_personal_stripe_sandbox_webhook_v1(
      'evt_CA11111111111111111111111111111',
      decode(repeat('44', 32), 'hex'),
      'payment_intent.succeeded',
      'pi_CA111111111111111111111111111111',
      '2026-02-25.clover',
      clock_timestamp(),
      'applied',
      'payment',
      'succeeded',
      false,
      ((select value from t_controls_claims) -> 0)
        ->> 'stripe_customer_id',
      ((select value from t_controls_claims) -> 0)
        ->> 'stripe_payment_method_id',
      1000,
      'USD',
      null,
      (((select value from t_controls_claims) -> 0) ->> 'command_id')::uuid
    ) ->> 'replayed'
  ),
  'true',
  'the identical off-state webhook is an idempotent replay'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ca111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (
    public.get_my_personal_stripe_sandbox_status_v1(
      (select challenge_id from t_controls_charge_a)
    ) ->> 'payment_state'
  ),
  'charged',
  'the owner can read authoritative charged status while controls are off'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ca222222-2222-2222-2222-222222222222"}',
  true
);

select throws_ok(
  $$ select public.get_my_personal_stripe_sandbox_status_v1(
       (select challenge_id from t_controls_charge_a)
     ) $$,
  '22023',
  null,
  'another authenticated owner cannot discover Stripe status while off'
);

reset role;

select * from finish();
rollback;
