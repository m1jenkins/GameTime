-- Automatic Apple Health Personal snapshots: private storage, clean contracts,
-- exact whole-snapshot replacement, policy-dispatched publication, and cutover.

begin;
select no_plan();
set local timezone = 'UTC';

insert into auth.users (id) values
  ('da111111-1111-1111-1111-111111111111'),
  ('da222222-2222-2222-2222-222222222222'),
  ('da333333-3333-3333-3333-333333333333'),
  ('da444444-4444-4444-4444-444444444444'),
  ('da555555-5555-5555-5555-555555555555'),
  ('da666666-6666-6666-6666-666666666666');

insert into public.profiles (id, handle, display_name, timezone) values
  ('da111111-1111-1111-1111-111111111111', 'healthopen', 'Health Open', 'UTC'),
  ('da222222-2222-2222-2222-222222222222', 'healthlower', 'Health Lower', 'UTC'),
  ('da333333-3333-3333-3333-333333333333', 'healthmiss', 'Health Miss', 'UTC'),
  ('da444444-4444-4444-4444-444444444444', 'healthpartial', 'Health Partial', 'UTC'),
  ('da555555-5555-5555-5555-555555555555', 'healthmissing', 'Health Missing', 'UTC'),
  ('da666666-6666-6666-6666-666666666666', 'healthother', 'Health Other', 'UTC');

create function pg_temp.utc_date()
returns date
language sql
stable
as $$ select (clock_timestamp() at time zone 'UTC')::date $$;

create function pg_temp.utc_at(p_date date, p_hour integer default 0)
returns timestamptz
language sql
stable
as $$
  select (p_date::timestamp + p_hour * interval '1 hour') at time zone 'UTC'
$$;

-- -------------------------------------------------------------------------
-- Contract and least privilege
-- -------------------------------------------------------------------------

select has_function(
  'public',
  'upsert_my_personal_health_snapshot_v2',
  array['uuid', 'text', 'timestamp with time zone', 'timestamp with time zone', 'jsonb'],
  'the ordinary-authenticated whole-snapshot RPC has the frozen v2 shape'
);

select has_function(
  'public',
  'create_personal_challenge_v2',
  array['uuid', 'public.contest_cadence', 'integer', 'integer', 'text', 'timestamp with time zone'],
  'new challenges have an explicit v2 constructor'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.upsert_my_personal_health_snapshot_v2(uuid,text,timestamptz,timestamptz,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.upsert_my_personal_health_snapshot_v2(uuid,text,timestamptz,timestamptz,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.upsert_my_personal_health_snapshot_v2(uuid,text,timestamptz,timestamptz,jsonb)',
    'execute'
  ),
  'only authenticated callers may execute the owner-derived snapshot boundary'
);

select ok(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app'
      and relation.relname = 'personal_health_snapshots_v2'
  )
  and not exists (
    select 1
    from (values ('public'), ('anon'), ('authenticated'), ('service_role')) actor(role_name)
    cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate')) operation(privilege_name)
    where has_table_privilege(
      actor.role_name,
      'app.personal_health_snapshots_v2',
      operation.privilege_name
    )
  ),
  'the mutable snapshot table has RLS and no direct API-role privileges'
);

select is(
  (
    select array_agg(attribute.attname order by attribute.attnum)
    from pg_catalog.pg_type type_def
    join pg_catalog.pg_class relation on relation.oid = type_def.typrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    join pg_catalog.pg_attribute attribute on attribute.attrelid = relation.oid
    where namespace.nspname = 'public'
      and type_def.typname = 'personal_challenge_card_v2'
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'challenge_id', 'status', 'cadence', 'target_steps',
    'commitment_amount_minor', 'currency', 'settlement_mode',
    'terms_version', 'timezone', 'agreed_at', 'starts_at', 'ends_at',
    'evidence_cutoff', 'closed_at', 'step_data_policy',
    'terms_fingerprint', 'total_steps', 'daily_progress',
    'health_observed_at', 'health_query_through', 'snapshot_updated_at',
    'outcome', 'outcome_reason', 'commitment_waived',
    'result_published_at'
  ]::name[],
  'clean cards expose policy, plain totals, explicit Health completeness, update time, and terminal fields'
);

select is(
  (
    select column_def.column_default
    from information_schema.columns column_def
    where column_def.table_schema = 'public'
      and column_def.table_name = 'personal_challenge_terms'
      and column_def.column_name = 'step_data_policy'
  ),
  '''attested_hourly_v1''::personal_step_data_policy',
  'legacy fixture inserts continue to default to the v1 policy'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.commit_personal_stripe_sandbox_challenge_service_v2(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.commit_personal_stripe_sandbox_challenge_service_v2(uuid,uuid,uuid,public.contest_cadence,integer,integer,text,text,timestamptz,text,text)',
    'execute'
  ),
  'the policy-marked Stripe v2 constructor is a separate service-only boundary'
);

-- -------------------------------------------------------------------------
-- Explicit v2 creation and idempotent whole-snapshot upload
-- -------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_open as
select public.create_personal_challenge_v2(
  'da100000-0000-0000-0000-000000000001',
  'daily',
  100,
  1000,
  'UTC',
  pg_temp.utc_at(pg_temp.utc_date() + 1, 15)
) as challenge_id;

reset role;
select is(
  (
    select terms.step_data_policy::text || ':' || terms.terms_version
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select challenge_id from t_open)
  ),
  'healthkit_nonmanual_daily_v1:personal-v2',
  'the explicit constructor freezes v2 terms and the automatic Health policy'
);

select matches(
  app.personal_terms_fingerprint_v2((select challenge_id from t_open)),
  '^[0-9a-f]{64}$',
  'the server returns an opaque lowercase SHA-256 terms fingerprint'
);

-- One captured instant models a completed query. Independent wall-clock reads
-- can put query_through a microsecond after observed_at and fail intermittently.
create temporary table t_open_input as
with observation_clock as materialized (select clock_timestamp() as instant)
select
  open_challenge.challenge_id,
  app.personal_terms_fingerprint_v2(open_challenge.challenge_id) as fingerprint,
  observation_clock.instant as observed_at,
  observation_clock.instant as query_through,
  app.personal_zero_daily_progress_v2(open_challenge.challenge_id) as daily_progress
from t_open open_challenge cross join observation_clock;

grant select on t_open, t_open_input to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_first_upload as
select *
from public.upsert_my_personal_health_snapshot_v2(
  (select challenge_id from t_open_input),
  (select fingerprint from t_open_input),
  (select observed_at from t_open_input),
  (select query_through from t_open_input),
  (select daily_progress from t_open_input)
);

create temporary table t_equal_replay as
select *
from public.upsert_my_personal_health_snapshot_v2(
  (select challenge_id from t_open_input),
  (select fingerprint from t_open_input),
  (select observed_at from t_open_input),
  (select query_through from t_open_input),
  (select daily_progress from t_open_input)
);

reset role;

select ok(
  (select not replayed and not ignored_as_stale from t_first_upload)
  and (select replayed and not ignored_as_stale from t_equal_replay)
  and (
    select first_upload.snapshot_updated_at = replay.snapshot_updated_at
    from t_first_upload first_upload
    cross join t_equal_replay replay
  ),
  'an exact replay succeeds without changing the server update timestamp'
);

select is(
  (
    select array[
      snapshot.observed_at = input.observed_at,
      snapshot.query_through = input.query_through,
      snapshot.daily_progress = input.daily_progress,
      snapshot.total_steps = 0
    ]
    from app.personal_health_snapshots_v2 snapshot
    join t_open_input input using (challenge_id)
  ),
  array[true, true, true, true],
  'the private row is one exact canonical whole-window snapshot'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_stale_upload as
select *
from public.upsert_my_personal_health_snapshot_v2(
  (select challenge_id from t_open_input),
  (select fingerprint from t_open_input),
  (
    select terms.agreed_at
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select challenge_id from t_open_input)
  ),
  (
    select terms.agreed_at
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select challenge_id from t_open_input)
  ),
  (select daily_progress from t_open_input)
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       (select fingerprint from t_open_input),
       (select observed_at from t_open_input),
       (select query_through - interval '1 second' from t_open_input),
       (select daily_progress from t_open_input)
     ) $$,
  '23505',
  null,
  'an equal observation with different contents is rejected'
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       (select fingerprint from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       jsonb_set(
         (select daily_progress from t_open_input),
         '{0,total_steps}',
         '1'::jsonb
       )
     ) $$,
  '22023',
  null,
  'a nonzero first day before a custom-hour challenge starts is rejected'
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       (select fingerprint from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       jsonb_set(
         (select daily_progress from t_open_input),
         '{0,total_steps}',
         '10000001'::jsonb
       )
     ) $$,
  '22023',
  null,
  'a daily total above ten million is rejected'
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       (select fingerprint from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select jsonb_agg(day.value - 'total_steps' order by day.ordinality)
        from jsonb_array_elements(
          (select daily_progress from t_open_input)
        ) with ordinality day(value, ordinality))
     ) $$,
  '22023',
  null,
  'a seven-day payload with a missing required total is rejected'
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       upper((select fingerprint from t_open_input)),
       (select observed_at + interval '1 second' from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select daily_progress from t_open_input)
     ) $$,
  '22023',
  null,
  'a client cannot substitute or normalize the opaque fingerprint'
);

reset role;

select ok(
  (select replayed and ignored_as_stale from t_stale_upload)
  and (
    select stale.snapshot_updated_at = first_upload.snapshot_updated_at
    from t_stale_upload stale
    cross join t_first_upload first_upload
  ),
  'an older observation succeeds as an ignored replay without mutation'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da666666-6666-6666-6666-666666666666"}',
  true
);

select throws_ok(
  $$ select * from public.upsert_my_personal_health_snapshot_v2(
       (select challenge_id from t_open_input),
       (select fingerprint from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select observed_at + interval '1 second' from t_open_input),
       (select daily_progress from t_open_input)
     ) $$,
  '42501',
  null,
  'another account cannot upload an owner snapshot'
);

select is(
  (select count(*) from public.list_my_accountability_challenges_v2()),
  0::bigint,
  'another account cannot list the owner challenge'
);

reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (
    select card.total_steps = 0
      and card.health_observed_at = input.observed_at
      and card.health_query_through = input.query_through
      and card.snapshot_updated_at = upload.snapshot_updated_at
      and card.daily_progress -> 0 ? 'total_steps'
      and not (card.daily_progress -> 0 ? 'trusted_steps')
    from public.get_my_accountability_challenge_v2(
      (select challenge_id from t_open_input)
    ) card
    cross join t_open_input input
    cross join t_first_upload upload
  ),
  'the clean owner detail exposes plain daily totals and explicit snapshot times'
);

reset role;

-- The policy marker selects a separate Stripe service constructor. The
-- existing unmarked v1 service is exercised in 410 and must remain unchanged.
set local role service_role;

select public.set_personal_stripe_sandbox_runtime_v1(
  'df000000-0000-0000-0000-000000000001',
  true
);

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  'df000000-0000-0000-0000-000000000002',
  'da666666-6666-6666-6666-666666666666',
  true
);

create temporary table t_stripe_v2_setup as
select public.begin_personal_stripe_sandbox_setup_service_v1(
  'da666666-6666-6666-6666-666666666666',
  'df100000-0000-0000-0000-000000000001',
  'daily',
  777,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select public.record_personal_stripe_sandbox_customer_v1(
  'da666666-6666-6666-6666-666666666666',
  'cus_DA666666666666666666666666666666'
);

select public.record_personal_stripe_sandbox_setup_v1(
  'da666666-6666-6666-6666-666666666666',
  (select (value ->> 'setup_id')::uuid from t_stripe_v2_setup),
  'cus_DA666666666666666666666666666666',
  'seti_DA66666666666666666666666666666',
  'pm_DA666666666666666666666666666666',
  'succeeded'
);

create temporary table t_stripe_v2_challenge as
select public.commit_personal_stripe_sandbox_challenge_service_v2(
  'da666666-6666-6666-6666-666666666666',
  'df100000-0000-0000-0000-000000000001',
  (select (value ->> 'setup_id')::uuid from t_stripe_v2_setup),
  'daily',
  777,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

grant select on t_stripe_v2_challenge to authenticated;

select is(
  (
    public.commit_personal_stripe_sandbox_challenge_service_v2(
      'da666666-6666-6666-6666-666666666666',
      'df100000-0000-0000-0000-000000000001',
      (select (value ->> 'setup_id')::uuid from t_stripe_v2_setup),
      'daily',
      777,
      1000,
      'USD',
      'UTC',
      null,
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1'
    ) ->> 'replayed'
  ),
  'true',
  'the policy-marked Stripe v2 commit exactly replays'
);

select throws_ok(
  $$ select public.commit_personal_stripe_sandbox_challenge_service_v1(
       'da666666-6666-6666-6666-666666666666',
       'df100000-0000-0000-0000-000000000001',
       (select (value ->> 'setup_id')::uuid from t_stripe_v2_setup),
       'daily', 777, 1000, 'USD', 'UTC', null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '22023',
  null,
  'a markerless retry cannot acknowledge a Health-policy Stripe challenge'
);

reset role;

select ok(
  exists (
    select 1
    from public.personal_challenge_terms terms
    join app.personal_stripe_sandbox_agreements agreement
      on agreement.challenge_id = terms.challenge_id
     and agreement.user_id = terms.user_id
    where terms.challenge_id =
      (select (value ->> 'challenge_id')::uuid from t_stripe_v2_challenge)
      and terms.terms_version = 'personal-v2'
      and terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
      and terms.settlement_mode = 'test_only'
      and agreement.agreement_version = 'personal-stripe-sandbox-v1'
      and agreement.consent_version = 'personal-stripe-sandbox-consent-v1'
  ),
  'the policy-marked Stripe constructor freezes Health v2 terms without changing the consent contract'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da666666-6666-6666-6666-666666666666"}',
  true
);
select is(
  (
    select card.settlement_mode
    from public.get_my_accountability_challenge_v2(
      (select (value ->> 'challenge_id')::uuid from t_stripe_v2_challenge)
    ) card
  ),
  'stripe_sandbox',
  'clean reads identify an agreement-backed challenge for Stripe review UI'
);
reset role;

-- -------------------------------------------------------------------------
-- Terminal policy dispatch freezes complete or waived-inconclusive history
-- -------------------------------------------------------------------------

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, challenge_model, metric, cadence, target_value,
  stake_amount_cents, tie_break, starts_at, ends_at, max_participants, status
)
values
  (
    'db000000-0000-0000-0000-000000000002', 'Health complete meet',
    'da222222-2222-2222-2222-222222222222', 'personal_accountability',
    'steps', 'cumulative', 699, 1000, 'void',
    '2026-07-01T00:00:00Z', '2026-07-08T00:00:00Z', 1, 'active'
  ),
  (
    'db000000-0000-0000-0000-000000000003', 'Health complete miss',
    'da333333-3333-3333-3333-333333333333', 'personal_accountability',
    'steps', 'cumulative', 701, 1000, 'void',
    '2026-07-01T00:00:00Z', '2026-07-08T00:00:00Z', 1, 'active'
  ),
  (
    'db000000-0000-0000-0000-000000000004', 'Health incomplete',
    'da444444-4444-4444-4444-444444444444', 'personal_accountability',
    'steps', 'cumulative', 1, 1000, 'void',
    '2026-07-01T00:00:00Z', '2026-07-08T00:00:00Z', 1, 'active'
  ),
  (
    'db000000-0000-0000-0000-000000000005', 'Health absent',
    'da555555-5555-5555-5555-555555555555', 'personal_accountability',
    'steps', 'cumulative', 1, 1000, 'void',
    '2026-07-01T00:00:00Z', '2026-07-08T00:00:00Z', 1, 'active'
  );

alter table public.contests enable trigger contests_assert_future_window;

alter table public.contest_participants
  disable trigger contest_participants_apply_transition;

insert into public.contest_participants (
  contest_id, user_id, status, timezone, charity_id, accepted_at
)
values
  ('db000000-0000-0000-0000-000000000002', 'da222222-2222-2222-2222-222222222222', 'accepted', 'UTC', null, '2026-06-30T00:00:00Z'),
  ('db000000-0000-0000-0000-000000000003', 'da333333-3333-3333-3333-333333333333', 'accepted', 'UTC', null, '2026-06-30T00:00:00Z'),
  ('db000000-0000-0000-0000-000000000004', 'da444444-4444-4444-4444-444444444444', 'accepted', 'UTC', null, '2026-06-30T00:00:00Z'),
  ('db000000-0000-0000-0000-000000000005', 'da555555-5555-5555-5555-555555555555', 'accepted', 'UTC', null, '2026-06-30T00:00:00Z');

alter table public.contest_participants
  enable trigger contest_participants_apply_transition;

insert into public.personal_challenge_terms (
  challenge_id, user_id, cadence, target_steps, commitment_amount_minor,
  terms_version, timezone, agreed_at, evidence_cutoff, step_data_policy
)
values
  ('db000000-0000-0000-0000-000000000002', 'da222222-2222-2222-2222-222222222222', 'cumulative', 699, 1000, 'personal-v2', 'UTC', '2026-06-30T00:00:00Z', '2026-07-09T00:00:00Z', 'healthkit_nonmanual_daily_v1'),
  ('db000000-0000-0000-0000-000000000003', 'da333333-3333-3333-3333-333333333333', 'cumulative', 701, 1000, 'personal-v2', 'UTC', '2026-06-30T00:00:00Z', '2026-07-09T00:00:00Z', 'healthkit_nonmanual_daily_v1'),
  ('db000000-0000-0000-0000-000000000004', 'da444444-4444-4444-4444-444444444444', 'cumulative', 1, 1000, 'personal-v2', 'UTC', '2026-06-30T00:00:00Z', '2026-07-09T00:00:00Z', 'healthkit_nonmanual_daily_v1'),
  ('db000000-0000-0000-0000-000000000005', 'da555555-5555-5555-5555-555555555555', 'cumulative', 1, 1000, 'personal-v2', 'UTC', '2026-06-30T00:00:00Z', '2026-07-09T00:00:00Z', 'healthkit_nonmanual_daily_v1');

-- Give the meet, miss, and partial cases real frozen sandbox agreements. The
-- existing after-insert result trigger must open a review only for the complete
-- nonwaived miss, independent of source policy.
insert into app.personal_stripe_sandbox_customers (
  user_id, stripe_customer_id
)
values
  ('da222222-2222-2222-2222-222222222222', 'cus_DA222222222222222222222222222222'),
  ('da333333-3333-3333-3333-333333333333', 'cus_DA333333333333333333333333333333'),
  ('da444444-4444-4444-4444-444444444444', 'cus_DA444444444444444444444444444444');

insert into app.personal_stripe_sandbox_setups (
  id, user_id, request_id, payload_hash, cadence, target_steps,
  commitment_amount_minor, currency, timezone, agreement_version,
  consent_version, consented_at, expires_at, stripe_customer_id,
  stripe_setup_intent_id, stripe_payment_method_id, status, succeeded_at
)
values
  (
    'de000000-0000-0000-0000-000000000002',
    'da222222-2222-2222-2222-222222222222',
    'de100000-0000-0000-0000-000000000002', decode(repeat('22', 32), 'hex'),
    'cumulative', 699, 1000, 'USD', 'UTC', 'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1', '2026-06-30T00:00:00Z',
    '2026-07-01T00:00:00Z', 'cus_DA222222222222222222222222222222',
    'seti_DA22222222222222222222222222222',
    'pm_DA222222222222222222222222222222', 'succeeded', '2026-06-30T00:01:00Z'
  ),
  (
    'de000000-0000-0000-0000-000000000003',
    'da333333-3333-3333-3333-333333333333',
    'de100000-0000-0000-0000-000000000003', decode(repeat('33', 32), 'hex'),
    'cumulative', 701, 1000, 'USD', 'UTC', 'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1', '2026-06-30T00:00:00Z',
    '2026-07-01T00:00:00Z', 'cus_DA333333333333333333333333333333',
    'seti_DA33333333333333333333333333333',
    'pm_DA333333333333333333333333333333', 'succeeded', '2026-06-30T00:01:00Z'
  ),
  (
    'de000000-0000-0000-0000-000000000004',
    'da444444-4444-4444-4444-444444444444',
    'de100000-0000-0000-0000-000000000004', decode(repeat('44', 32), 'hex'),
    'cumulative', 1, 1000, 'USD', 'UTC', 'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1', '2026-06-30T00:00:00Z',
    '2026-07-01T00:00:00Z', 'cus_DA444444444444444444444444444444',
    'seti_DA44444444444444444444444444444',
    'pm_DA444444444444444444444444444444', 'succeeded', '2026-06-30T00:01:00Z'
  );

insert into app.personal_stripe_sandbox_agreements (
  challenge_id, user_id, setup_id, create_request_id,
  creation_payload_hash, setup_payload_hash, cadence, target_steps,
  commitment_amount_minor, currency, timezone, agreement_version,
  consent_version, consented_at, stripe_customer_id,
  stripe_setup_intent_id, stripe_payment_method_id
)
select
  fixture.challenge_id,
  fixture.user_id,
  fixture.setup_id,
  gen_random_uuid(),
  decode(repeat('55', 32), 'hex'),
  setup.payload_hash,
  terms.cadence,
  terms.target_steps,
  terms.commitment_amount_minor,
  terms.currency,
  terms.timezone,
  setup.agreement_version,
  setup.consent_version,
  setup.consented_at,
  setup.stripe_customer_id,
  setup.stripe_setup_intent_id,
  setup.stripe_payment_method_id
from (
  values
    ('db000000-0000-0000-0000-000000000002'::uuid, 'da222222-2222-2222-2222-222222222222'::uuid, 'de000000-0000-0000-0000-000000000002'::uuid),
    ('db000000-0000-0000-0000-000000000003'::uuid, 'da333333-3333-3333-3333-333333333333'::uuid, 'de000000-0000-0000-0000-000000000003'::uuid),
    ('db000000-0000-0000-0000-000000000004'::uuid, 'da444444-4444-4444-4444-444444444444'::uuid, 'de000000-0000-0000-0000-000000000004'::uuid)
) fixture(challenge_id, user_id, setup_id)
join app.personal_stripe_sandbox_setups setup on setup.id = fixture.setup_id
join public.personal_challenge_terms terms
  on terms.challenge_id = fixture.challenge_id
 and terms.user_id = fixture.user_id;

create function pg_temp.days(p_total integer)
returns jsonb
language sql
immutable
as $$
  select jsonb_agg(
    jsonb_build_object(
      'local_date', to_char('2026-07-01'::date + day_index, 'YYYY-MM-DD'),
      'total_steps', p_total
    )
    order by day_index
  )
  from generate_series(0, 6) day_index
$$;

insert into app.personal_health_snapshots_v2 (
  challenge_id, user_id, terms_fingerprint, observed_at, query_through,
  daily_progress, total_steps, updated_at
)
values
  (
    'db000000-0000-0000-0000-000000000002',
    'da222222-2222-2222-2222-222222222222',
    app.personal_terms_fingerprint_v2('db000000-0000-0000-0000-000000000002'),
    '2026-07-08T12:00:00Z', '2026-07-08T00:00:00Z',
    pg_temp.days(100), 700, '2026-07-08T12:01:00Z'
  ),
  (
    'db000000-0000-0000-0000-000000000003',
    'da333333-3333-3333-3333-333333333333',
    app.personal_terms_fingerprint_v2('db000000-0000-0000-0000-000000000003'),
    '2026-07-08T12:00:00Z', '2026-07-08T00:00:00Z',
    pg_temp.days(100), 700, '2026-07-08T12:01:00Z'
  ),
  (
    'db000000-0000-0000-0000-000000000004',
    'da444444-4444-4444-4444-444444444444',
    app.personal_terms_fingerprint_v2('db000000-0000-0000-0000-000000000004'),
    '2026-07-08T12:00:00Z', '2026-07-07T23:59:59Z',
    pg_temp.days(100), 700, '2026-07-08T12:01:00Z'
  );

create temporary table t_post_cutoff_replay_input as
select snapshot.*
from app.personal_health_snapshots_v2 snapshot
where snapshot.challenge_id = 'db000000-0000-0000-0000-000000000004';
grant select on t_post_cutoff_replay_input to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da444444-4444-4444-4444-444444444444"}',
  true
);
create temporary table t_post_cutoff_replay as
select *
from public.upsert_my_personal_health_snapshot_v2(
  (select challenge_id from t_post_cutoff_replay_input),
  (select terms_fingerprint from t_post_cutoff_replay_input),
  (select observed_at from t_post_cutoff_replay_input),
  (select query_through from t_post_cutoff_replay_input),
  (select daily_progress from t_post_cutoff_replay_input)
);
reset role;

select ok(
  (select replayed and not ignored_as_stale from t_post_cutoff_replay)
  and (
    select replay.snapshot_updated_at = input.updated_at
    from t_post_cutoff_replay replay
    cross join t_post_cutoff_replay_input input
  ),
  'an equal lost-response replay after cutoff succeeds without mutation while the challenge remains open'
);

create temporary table t_terminal_results as
select challenge_id, app.publish_due_personal_result(
  challenge_id,
  '2026-07-09T00:00:00Z'
) as result_id
from (
  values
    ('db000000-0000-0000-0000-000000000002'::uuid),
    ('db000000-0000-0000-0000-000000000003'::uuid),
    ('db000000-0000-0000-0000-000000000004'::uuid),
    ('db000000-0000-0000-0000-000000000005'::uuid)
) fixture(challenge_id);

select is(
  (
    select array_agg(
      result.outcome::text || ':' || result.reason::text || ':'
        || result.evidence_state::text || ':' || result.commitment_waived::text
      order by result.challenge_id
    )
    from public.personal_challenge_results result
    where result.challenge_id in (
      'db000000-0000-0000-0000-000000000002',
      'db000000-0000-0000-0000-000000000003',
      'db000000-0000-0000-0000-000000000004',
      'db000000-0000-0000-0000-000000000005'
    )
  ),
  array[
    'met_goal:target_reached:complete:false',
    'missed_goal:target_missed:complete:false',
    'inconclusive:missing_coverage:missing:true',
    'inconclusive:missing_coverage:missing:true'
  ],
  'complete snapshots score normally while partial or absent data is inconclusive and waived'
);

select ok(
  not exists (
    select 1
    from public.personal_challenge_results result
    where result.challenge_id in (
      'db000000-0000-0000-0000-000000000002',
      'db000000-0000-0000-0000-000000000003',
      'db000000-0000-0000-0000-000000000004',
      'db000000-0000-0000-0000-000000000005'
    )
      and (
        result.assessment_id is not null
        or result.step_data_policy <> 'healthkit_nonmanual_daily_v1'
      )
  )
  and not exists (
    select 1
    from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id in (
      'db000000-0000-0000-0000-000000000002',
      'db000000-0000-0000-0000-000000000003',
      'db000000-0000-0000-0000-000000000004'
    )
  ),
  'v2 results use no legacy assessment and publication removes mutable snapshots'
);

select is(
  app.publish_due_personal_result(
    'db000000-0000-0000-0000-000000000002',
    '2026-07-09T00:00:00Z'
  ),
  (
    select result.id
    from public.personal_challenge_results result
    where result.challenge_id = 'db000000-0000-0000-0000-000000000002'
  ),
  'terminal publication reruns return the exact immutable result'
);

select is(
  (
    select count(*)
    from public.personal_eligibility_holds hold
    where hold.challenge_id in (
      'db000000-0000-0000-0000-000000000002',
      'db000000-0000-0000-0000-000000000003',
      'db000000-0000-0000-0000-000000000004',
      'db000000-0000-0000-0000-000000000005'
    )
  ),
  0::bigint,
  'the automatic Health policy never creates a legacy sync-failure hold'
);

select is(
  (
    select array_agg(review.challenge_id order by review.challenge_id)
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id in (
      'db000000-0000-0000-0000-000000000002',
      'db000000-0000-0000-0000-000000000003',
      'db000000-0000-0000-0000-000000000004',
      'db000000-0000-0000-0000-000000000005'
    )
  ),
  array['db000000-0000-0000-0000-000000000003'::uuid],
  'only the complete nonwaived v2 miss opens Stripe sandbox review; met and inconclusive do not'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da444444-4444-4444-4444-444444444444"}',
  true
);

select is(
  (
    select card.outcome_reason
    from public.get_my_accountability_challenge_v2(
      'db000000-0000-0000-0000-000000000004'
    ) card
  ),
  'missing_health_data',
  'clean reads map the stable internal missing-coverage enum to missing-health-data'
);

reset role;

-- -------------------------------------------------------------------------
-- Cutover is explicit, service-only, exact-retry safe, and non-destructive
-- -------------------------------------------------------------------------

select ok(
  has_function_privilege(
    'service_role',
    'public.cutover_personal_health_snapshots_v2(uuid,timestamptz)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.cutover_personal_health_snapshots_v2(uuid,timestamptz)',
    'execute'
  ),
  'only service_role can invoke the dormant cutover operation'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da444444-4444-4444-4444-444444444444"}',
  true
);

create temporary table t_cutover_challenge as
select public.create_personal_challenge_v1(
  'dc100000-0000-0000-0000-000000000001',
  'cumulative', 100, 1000, 'UTC'
) as challenge_id;
reset role;

insert into public.personal_eligibility_holds (
  user_id, challenge_id, result_id, reason, placed_at
)
select
  result.user_id,
  result.challenge_id,
  result.id,
  'user_device_sync_failure',
  clock_timestamp() - interval '1 second'
from public.personal_challenge_results result
where result.challenge_id = 'db000000-0000-0000-0000-000000000004';

create temporary table t_cutover_input as
select clock_timestamp() as as_of;
grant select on t_cutover_input to service_role;

set local role service_role;
create temporary table t_cutover as
select * from public.cutover_personal_health_snapshots_v2(
  'dc000000-0000-0000-0000-000000000001',
  (select as_of from t_cutover_input)
);

create temporary table t_cutover_replay as
select * from public.cutover_personal_health_snapshots_v2(
  'dc000000-0000-0000-0000-000000000001',
  (select as_of from t_cutover_input)
);
reset role;

select ok(
  (
    select migrated_challenges >= 1
      and retired_holds >= 1
      and not replayed
    from t_cutover
  )
  and (select replayed from t_cutover_replay)
  and (
    select terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select challenge_id from t_cutover_challenge)
  )
  and (
    select hold.retired_at is not null and hold.cleared_at is null
    from public.personal_eligibility_holds hold
    where hold.challenge_id = 'db000000-0000-0000-0000-000000000004'
  ),
  'cutover migrates eligible v1 rows, retires holds non-destructively, and exactly replays its ledger'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da444444-4444-4444-4444-444444444444"}',
  true
);
select is(
  public.create_personal_challenge_v2(
    'dc100000-0000-0000-0000-000000000001',
    'cumulative', 100, 1000, 'UTC'
  ),
  (select challenge_id from t_cutover_challenge),
  'a mandatory v2 build exactly retries the request that created a cut-over v1 challenge'
);
select throws_ok(
  $$ select public.create_personal_challenge_v2(
       'dc100000-0000-0000-0000-000000000001',
       'cumulative', 101, 1000, 'UTC'
     ) $$,
  '22023',
  null,
  'a changed-terms retry of a cut-over legacy request still fails'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"da444444-4444-4444-4444-444444444444"}',
  true
);
select ok(
  (select eligibility.eligible from public.get_my_personal_eligibility_v1() eligibility),
  'legacy eligibility reads no longer treat a retired hold as active'
);
reset role;

select is(
  (
    select count(*)
    from cron.job job
    where job.jobname = 'gametime-publish-personal-results'
      and job.active
  ),
  0::bigint,
  'the support migration does not activate the result-worker schedule'
);

select * from finish();
rollback;
