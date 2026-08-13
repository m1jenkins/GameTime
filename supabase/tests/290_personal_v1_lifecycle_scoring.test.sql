-- Personal V1 lifecycle and scoring: calendar-derived windows, fail-closed
-- evidence, generic outcomes, diagnostic holds, and owner isolation.

begin;
select plan(34);

insert into auth.users (id) values
  ('e9111111-1111-1111-1111-111111111111'), -- one-hour DST
  ('e9222222-2222-2222-2222-222222222222'), -- Lord Howe overlap
  ('e9333333-3333-3333-3333-333333333333'), -- diagnostic hold
  ('e9444444-4444-4444-4444-444444444444'), -- cumulative met
  ('e9555555-5555-5555-5555-555555555555'), -- live coverage boundary
  ('e9666666-6666-6666-6666-666666666666'); -- two-hour DST

insert into public.profiles (id, handle, display_name, timezone) values
  ('e9111111-1111-1111-1111-111111111111', 'p1chicago', 'P1 Chicago', 'America/Chicago'),
  ('e9222222-2222-2222-2222-222222222222', 'p1lordhowe', 'P1 Lord Howe', 'Australia/Lord_Howe'),
  ('e9333333-3333-3333-3333-333333333333', 'p1hold', 'P1 Hold', 'UTC'),
  ('e9444444-4444-4444-4444-444444444444', 'p1met', 'P1 Met', 'UTC'),
  ('e9555555-5555-5555-5555-555555555555', 'p1coverage', 'P1 Coverage', 'UTC'),
  ('e9666666-6666-6666-6666-666666666666', 'p1troll', 'P1 Troll', 'Antarctica/Troll');

create function pg_temp.make_personal_fixture(
  p_challenge_id uuid,
  p_user_id uuid,
  p_cadence public.contest_cadence,
  p_target integer,
  p_timezone text,
  p_first_local_date date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_starts_at timestamptz := p_first_local_date::timestamp at time zone p_timezone;
  v_ends_at timestamptz := (p_first_local_date + 7)::timestamp at time zone p_timezone;
begin
  insert into public.contests (
    id, title, created_by, challenge_model, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  ) values (
    p_challenge_id, 'Personal lifecycle fixture', p_user_id,
    'personal_accountability', 'steps', p_cadence, p_target,
    1000, 'void', v_starts_at, v_ends_at, 1
  );

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  ) values (
    p_challenge_id, p_user_id, 'accepted', p_timezone, null
  );

  insert into public.personal_challenge_terms (
    challenge_id, user_id, cadence, target_steps,
    commitment_amount_minor, currency, settlement_mode, terms_version,
    timezone, agreed_at, evidence_cutoff
  ) values (
    p_challenge_id, p_user_id, p_cadence, p_target,
    1000, 'USD', 'test_only', 'personal-v1',
    p_timezone, v_starts_at - interval '1 day',
    v_ends_at + interval '24 hours'
  );
end;
$$;

alter table public.contests disable trigger contests_assert_future_window;

select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000001',
  'e9111111-1111-1111-1111-111111111111',
  'daily', 1, 'America/Chicago', '2026-03-07'
);
select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000002',
  'e9222222-2222-2222-2222-222222222222',
  'cumulative', 100, 'Australia/Lord_Howe', '2026-04-03'
);
select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000003',
  'e9333333-3333-3333-3333-333333333333',
  'cumulative', 100, 'UTC', '2026-07-20'
);
select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000004',
  'e9444444-4444-4444-4444-444444444444',
  'cumulative', 100, 'UTC', '2026-07-20'
);
select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000005',
  'e9555555-5555-5555-5555-555555555555',
  'cumulative', 100,
  'UTC', (clock_timestamp() at time zone 'UTC')::date - 1
);
select pg_temp.make_personal_fixture(
  'e9000000-0000-0000-0000-000000000006',
  'e9666666-6666-6666-6666-666666666666',
  'cumulative', 100, 'Antarctica/Troll', '2026-03-27'
);

alter table public.contests enable trigger contests_assert_future_window;

create temporary table t_activation as
select * from app.activate_due_contests(clock_timestamp());

select is(
  (
    select count(*)
    from t_activation
    where outcome = 'active'
      and contest_id::text like 'e9000000-0000-0000-0000-00000000000%'
  ),
  6::bigint,
  'model-dispatched activation accepts one owner for every personal fixture'
);

select is(
  (
    select count(*)
    from app.personal_expected_coverage_buckets_v1(
      'e9000000-0000-0000-0000-000000000001', 'infinity'
    )
  ),
  167::bigint,
  'a Chicago spring-forward week has 167 authoritative hourly intervals'
);

select is(
  app.personal_has_overlapping_coverage_v1(
    'e9000000-0000-0000-0000-000000000001'
  ),
  false,
  'ordinary one-hour DST remains non-overlapping and scoreable'
);

select is(
  (
    select count(*)
    from app.personal_expected_coverage_buckets_v1(
      'e9000000-0000-0000-0000-000000000002', 'infinity'
    )
  ),
  169::bigint,
  'a Lord Howe fall-back week preserves its half-hour Calendar interval keys'
);

select is(
  app.personal_has_overlapping_coverage_v1(
    'e9000000-0000-0000-0000-000000000002'
  ),
  true,
  'Lord Howe exposes the overlapping HealthKit query interval risk'
);

select is(
  (
    select count(*)
    from app.personal_expected_coverage_buckets_v1(
      'e9000000-0000-0000-0000-000000000006', 'infinity'
    )
  ),
  166::bigint,
  'a Troll two-hour spring transition derives 166 intervals without magic counts'
);

select is(
  app.personal_has_overlapping_coverage_v1(
    'e9000000-0000-0000-0000-000000000006'
  ),
  false,
  'the two-hour transition stays scoreable when its intervals do not overlap'
);

-- Device rows support trusted fixture batches. The Lord Howe challenge does
-- not receive one: complete assessment must fail before missing coverage can
-- be mistaken for the root cause.
create temporary table t_keys as
select
  ('\x04' || repeat('91', 64))::bytea as chicago_key,
  extensions.digest(('\x04' || repeat('91', 64))::bytea, 'sha256') as chicago_key_id,
  ('\x04' || repeat('93', 64))::bytea as hold_key,
  extensions.digest(('\x04' || repeat('93', 64))::bytea, 'sha256') as hold_key_id,
  ('\x04' || repeat('94', 64))::bytea as met_key,
  extensions.digest(('\x04' || repeat('94', 64))::bytea, 'sha256') as met_key_id,
  ('\x04' || repeat('95', 64))::bytea as live_key,
  extensions.digest(('\x04' || repeat('95', 64))::bytea, 'sha256') as live_key_id;

insert into public.device_attestations (
  key_id, user_id, public_key, environment
)
select chicago_key_id, 'e9111111-1111-1111-1111-111111111111'::uuid, chicago_key, 'production'::public.attestation_environment
from t_keys
union all
select met_key_id, 'e9444444-4444-4444-4444-444444444444'::uuid, met_key, 'production'::public.attestation_environment
from t_keys;

select public.register_device_key(
  'e9333333-3333-3333-3333-333333333333',
  (select hold_key_id from t_keys),
  (select hold_key from t_keys),
  '\x686f6c642d72656365697074',
  'production'
);
select public.mark_device_receipt_verified(
  (select hold_key_id from t_keys),
  extensions.digest('\x686f6c642d72656365697074'::bytea, 'sha256')
);

select public.register_device_key(
  'e9555555-5555-5555-5555-555555555555',
  (select live_key_id from t_keys),
  (select live_key from t_keys),
  '\x6c6976652d72656365697074',
  'production'
);
select public.mark_device_receipt_verified(
  (select live_key_id from t_keys),
  extensions.digest('\x6c6976652d72656365697074'::bytea, 'sha256')
);

create function pg_temp.cover_all(
  p_challenge_id uuid,
  p_user_id uuid,
  p_key_id bytea,
  p_batch_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
  v_ends_at timestamptz;
begin
  select contest.ends_at into v_ends_at
  from public.contests contest where contest.id = p_challenge_id;

  select count(*)::integer into v_count
  from app.personal_expected_coverage_buckets_v1(
    p_challenge_id, 'infinity'
  );

  insert into public.personal_sync_coverage_batches (
    id, challenge_id, user_id, client_coverage_id, key_id, sign_count,
    payload_digest, observed_at, covered_bucket_count
  ) values (
    p_batch_id, p_challenge_id, p_user_id, p_batch_id, p_key_id, 1,
    extensions.digest(p_batch_id::text, 'sha256'), v_ends_at, v_count
  );

  insert into public.personal_sync_coverage_buckets (
    coverage_batch_id, challenge_id, user_id, bucket_start
  )
  select p_batch_id, p_challenge_id, p_user_id, expected.bucket_start
  from app.personal_expected_coverage_buckets_v1(
    p_challenge_id, 'infinity'
  ) expected;
end;
$$;

select pg_temp.cover_all(
  'e9000000-0000-0000-0000-000000000001',
  'e9111111-1111-1111-1111-111111111111',
  (select chicago_key_id from t_keys),
  'e9100000-0000-0000-0000-000000000001'
);

select pg_temp.cover_all(
  'e9000000-0000-0000-0000-000000000004',
  'e9444444-4444-4444-4444-444444444444',
  (select met_key_id from t_keys),
  'e9400000-0000-0000-0000-000000000001'
);

-- One attested historical evidence row makes the cumulative fixture meet its
-- target. The normal trigger forbids post-cutoff insertion, so the test writes
-- a valid pre-cutoff audit row while that trigger alone is suspended.
insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, key_id, sign_count, attested,
  payload_digest, observation_count, observed_at, recorded_at
) values (
  'e9400000-0000-0000-0000-000000000002',
  'e9000000-0000-0000-0000-000000000004',
  'e9444444-4444-4444-4444-444444444444',
  'e9400000-0000-0000-0000-000000000002',
  (select met_key_id from t_keys), 1, true,
  extensions.digest('met-evidence', 'sha256'), 1,
  '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
);

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  batch_id, contest_id, user_id, metric, bucket_start,
  local_day, local_hour, value, provenance, sample_count,
  source_bundle_id, device_model, observed_at, recorded_at
)
select
  'e9400000-0000-0000-0000-000000000002',
  'e9000000-0000-0000-0000-000000000004',
  'e9444444-4444-4444-4444-444444444444',
  'steps', expected.bucket_start, expected.local_day, expected.local_hour,
  100, 'device', 1, 'com.apple.health', 'iPhone',
  '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
from app.personal_expected_coverage_buckets_v1(
  'e9000000-0000-0000-0000-000000000004', 'infinity'
) expected
order by expected.bucket_start
limit 1;

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

create temporary table t_chicago_assessment as
select public.record_personal_assessment_v1(
  'e9000000-0000-0000-0000-000000000001',
  'e9100000-0000-0000-0000-000000000002',
  'complete', 'personal-v1',
  extensions.digest('chicago-complete', 'sha256'), null
) as id;

create temporary table t_chicago_result as
select public.publish_personal_result_v1(
  'e9000000-0000-0000-0000-000000000001',
  (select id from t_chicago_assessment)
) as id;

select ok(
  (
    select outcome = 'missed_goal'
       and reason = 'target_missed'
       and evidence_state = 'complete'
       and not commitment_waived
    from public.personal_challenge_results
    where id = (select id from t_chicago_result)
  ),
  'complete one-hour-DST evidence publishes a generic target-missed result'
);

select throws_ok(
  $$ select public.record_personal_assessment_v1(
       'e9000000-0000-0000-0000-000000000002',
       'e9200000-0000-0000-0000-000000000001',
       'complete', 'personal-v1',
       extensions.digest('lord-howe-complete', 'sha256'), null
     ) $$,
  '23001',
  null,
  'Lord Howe overlapping intervals cannot be assessed as complete'
);

create temporary table t_lord_assessment as
select public.record_personal_assessment_v1(
  'e9000000-0000-0000-0000-000000000002',
  'e9200000-0000-0000-0000-000000000002',
  'gametime_outage', 'personal-v1',
  extensions.digest('lord-howe-waiver', 'sha256'),
  'calendar-overlap-personal-v1'
) as id;

create temporary table t_lord_result as
select public.publish_personal_result_v1(
  'e9000000-0000-0000-0000-000000000002',
  (select id from t_lord_assessment)
) as id;

select ok(
  (
    select outcome = 'inconclusive'
       and reason = 'gametime_outage'
       and commitment_waived
    from public.personal_challenge_results
    where id = (select id from t_lord_result)
  ),
  'the fail-closed Lord Howe result is an outage waiver'
);

select is(
  (
    select count(*)
    from public.personal_eligibility_holds
    where challenge_id = 'e9000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'a GameTime calendar limitation never penalizes or blocks the owner'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      app.personal_daily_progress_v1(
        'e9000000-0000-0000-0000-000000000002',
        'e9222222-2222-2222-2222-222222222222',
        clock_timestamp()
      )
    ) day
    where day ->> 'evidence_state' = 'unresolved'
  ),
  'the transition day is never presented as complete in progress'
);

create temporary table t_met_assessment as
select public.record_personal_assessment_v1(
  'e9000000-0000-0000-0000-000000000004',
  'e9400000-0000-0000-0000-000000000003',
  'complete', 'personal-v1',
  extensions.digest('cumulative-met', 'sha256'), null
) as id;

create temporary table t_met_result as
select public.publish_personal_result_v1(
  'e9000000-0000-0000-0000-000000000004',
  (select id from t_met_assessment)
) as id;

select ok(
  (
    select outcome = 'met_goal'
       and reason = 'target_reached'
       and total_steps = 100
       and not commitment_waived
    from public.personal_challenge_results
    where id = (select id from t_met_result)
  ),
  'complete cumulative evidence publishes the generic target-reached result'
);

select is(
  public.publish_personal_result_v1(
    'e9000000-0000-0000-0000-000000000004',
    (select id from t_met_assessment)
  ),
  (select id from t_met_result),
  'result publication is an exact immutable retry'
);

select ok(
  (
    select contest.status = 'finalized'
       and terms.closed_at is not null
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.id = 'e9000000-0000-0000-0000-000000000004'
  ),
  'result publication finalizes the challenge and closes its frozen terms'
);

select is(
  (
    select count(*)
    from public.contest_results legacy
    where legacy.contest_id in (
      'e9000000-0000-0000-0000-000000000001',
      'e9000000-0000-0000-0000-000000000002',
      'e9000000-0000-0000-0000-000000000004'
    )
  ),
  0::bigint,
  'personal results never enter the legacy winner/result table'
);

-- A user/device failure waives, places one hold, and blocks creation until a
-- trusted diagnostic whose query itself began after the hold.
create temporary table t_hold_assessment as
select public.record_personal_assessment_v1(
  'e9000000-0000-0000-0000-000000000003',
  'e9300000-0000-0000-0000-000000000001',
  'user_device_sync_failure', 'personal-v1',
  extensions.digest('device-sync-failure', 'sha256'), null
) as id;

create temporary table t_hold_result as
select public.publish_personal_result_v1(
  'e9000000-0000-0000-0000-000000000003',
  (select id from t_hold_assessment)
) as id;

select ok(
  (
    select result.outcome = 'inconclusive'
       and result.reason = 'user_device_sync_failure'
       and result.commitment_waived
       and hold.cleared_at is null
    from public.personal_challenge_results result
    join public.personal_eligibility_holds hold
      on hold.result_id = result.id
    where result.id = (select id from t_hold_result)
  ),
  'a user/device failure waives and places one unresolved eligibility hold'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e9333333-3333-3333-3333-333333333333"}',
  true
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'e9300000-0000-0000-0000-000000000002',
       'cumulative', 70000, 1000, 'UTC'
     ) $$,
  '23001',
  null,
  'an active eligibility hold blocks another personal challenge'
);

reset role;

create temporary table t_hold_clock as
select placed_at from public.personal_eligibility_holds
where result_id = (select id from t_hold_result);

grant select on t_hold_clock to service_role;

set local role service_role;

select is(
  (
    select cleared_hold
    from public.record_trusted_personal_diagnostic_v1(
      'e9333333-3333-3333-3333-333333333333',
      'e9300000-0000-0000-0000-000000000003',
      extensions.digest('stale-query-diagnostic', 'sha256'),
      clock_timestamp(),
      (select placed_at - interval '1 hour' from t_hold_clock),
      (select placed_at + interval '1 microsecond' from t_hold_clock),
      3,
      extensions.digest(('\x04' || repeat('93', 64))::bytea, 'sha256'),
      1
    )
  ),
  false,
  'a diagnostic whose HealthKit query began before the hold cannot clear it'
);

select is(
  (
    select cleared_hold
    from public.record_trusted_personal_diagnostic_v1(
      'e9333333-3333-3333-3333-333333333333',
      'e9300000-0000-0000-0000-000000000004',
      extensions.digest('fresh-query-diagnostic', 'sha256'),
      clock_timestamp(),
      (select placed_at + interval '1 microsecond' from t_hold_clock),
      (select placed_at + interval '2 microseconds' from t_hold_clock),
      7,
      extensions.digest(('\x04' || repeat('93', 64))::bytea, 'sha256'),
      2
    )
  ),
  true,
  'a fresh post-hold trusted diagnostic clears the hold atomically'
);

reset role;

select ok(
  (
    select cleared_at is not null
       and cleared_by_diagnostic_id is not null
    from public.personal_eligibility_holds
    where result_id = (select id from t_hold_result)
  ),
  'the durable hold retains its clearing diagnostic audit link'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e9333333-3333-3333-3333-333333333333"}',
  true
);

select ok(
  (
    select eligible
       and hold_id is null
       and latest_diagnostic_id is not null
       and latest_diagnostic_observed_at is not null
       and latest_diagnostic_recorded_at is not null
       and latest_diagnostic_trusted_device_sample_count = 7
       and latest_diagnostic_cleared_hold
    from public.get_my_personal_eligibility_v1()
  ),
  'eligibility reload restores the latest trusted diagnostic and cleared state'
);

create temporary table t_recovered as
select public.create_personal_challenge_v1(
  'e9300000-0000-0000-0000-000000000005',
  'cumulative', 70000, 1000, 'UTC'
) as id;

select is(
  public.cancel_personal_challenge_v1(
    (select id from t_recovered),
    'e9300000-0000-0000-0000-000000000006'
  ),
  (select id from t_recovered),
  'the owner can cancel before the next-midnight start'
);

select is(
  public.cancel_personal_challenge_v1(
    (select id from t_recovered),
    'e9300000-0000-0000-0000-000000000006'
  ),
  (select id from t_recovered),
  'an exact cancellation retry returns the same challenge'
);

select ok(
  (
    select contest.status = 'cancelled'
       and terms.closed_at is not null
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.id = (select id from t_recovered)
  ),
  'pre-start cancellation closes terms and releases the open slot'
);

select ok(
  public.create_personal_challenge_v1(
    'e9300000-0000-0000-0000-000000000007',
    'daily', 10000, 2000, 'UTC'
  ) is not null,
  'a cancelled challenge no longer occupies the one-open slot'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e9666666-6666-6666-6666-666666666666"}',
  true
);

select throws_ok(
  $$ select public.cancel_personal_challenge_v1(
       'e9000000-0000-0000-0000-000000000006',
       'e9600000-0000-0000-0000-000000000001'
     ) $$,
  '23001',
  null,
  'an ended internal challenge awaiting its result is no longer active-cancellable'
);

-- Signed coverage may never claim an hour later than its signed observation
-- time, even when that hour has completed by the server clock.
reset role;
create temporary table t_live_bucket as
select expected.bucket_start
from app.personal_expected_coverage_buckets_v1(
  'e9000000-0000-0000-0000-000000000005',
  date_trunc('hour', clock_timestamp())
) expected
order by expected.bucket_start desc
limit 1;

create temporary table t_live_unfinished_bucket as
select expected.bucket_start
from app.personal_expected_coverage_buckets_v1(
  'e9000000-0000-0000-0000-000000000005',
  'infinity'
) expected
where expected.bucket_start <= clock_timestamp()
  and expected.bucket_start + interval '1 hour' > clock_timestamp()
order by expected.bucket_start desc
limit 1;

grant select on t_live_bucket, t_live_unfinished_bucket to service_role;

set local role service_role;

select throws_ok(
  $$ select * from public.record_personal_sync_coverage_v1(
       'e9555555-5555-5555-5555-555555555555',
       'e9000000-0000-0000-0000-000000000005',
       'e9500000-0000-0000-0000-000000000000',
       extensions.digest('future-clock-skew', 'sha256'),
       clock_timestamp() + interval '1 minute',
       jsonb_build_array((select bucket_start from t_live_unfinished_bucket)),
       extensions.digest(('\x04' || repeat('95', 64))::bytea, 'sha256'),
       1
     ) $$,
  '22023',
  null,
  'client clock-skew tolerance cannot certify an unfinished server interval'
);

select throws_ok(
  $$ select * from public.record_personal_sync_coverage_v1(
       'e9555555-5555-5555-5555-555555555555',
       'e9000000-0000-0000-0000-000000000005',
       'e9500000-0000-0000-0000-000000000001',
       extensions.digest('signed-too-early', 'sha256'),
       (select bucket_start + interval '30 minutes' from t_live_bucket),
       jsonb_build_array((select bucket_start from t_live_bucket)),
       extensions.digest(('\x04' || repeat('95', 64))::bytea, 'sha256'),
       1
     ) $$,
  '22023',
  null,
  'coverage cannot claim a bucket unfinished at signed observation time'
);

select is(
  (
    select replayed
    from public.record_personal_sync_coverage_v1(
      'e9555555-5555-5555-5555-555555555555',
      'e9000000-0000-0000-0000-000000000005',
      'e9500000-0000-0000-0000-000000000002',
      extensions.digest('signed-complete', 'sha256'),
      (select bucket_start + interval '1 hour' from t_live_bucket),
      jsonb_build_array((select bucket_start from t_live_bucket)),
      extensions.digest(('\x04' || repeat('95', 64))::bytea, 'sha256'),
      1
    )
  ),
  false,
  'the same completed bucket is accepted at its signed end time'
);

select is(
  (
    select replayed
    from public.record_personal_sync_coverage_v1(
      'e9555555-5555-5555-5555-555555555555',
      'e9000000-0000-0000-0000-000000000005',
      'e9500000-0000-0000-0000-000000000002',
      extensions.digest('signed-complete', 'sha256'),
      (select bucket_start + interval '1 hour' from t_live_bucket),
      jsonb_build_array((select bucket_start from t_live_bucket)),
      extensions.digest(('\x04' || repeat('95', 64))::bytea, 'sha256'),
      1
    )
  ),
  true,
  'an exact coverage retry succeeds after its App Attest counter was consumed'
);

reset role;

select is(
  (
    select count(*)
    from public.personal_sync_coverage_batches
    where user_id = 'e9555555-5555-5555-5555-555555555555'
      and client_coverage_id = 'e9500000-0000-0000-0000-000000000002'
  ),
  1::bigint,
  'coverage idempotency persists one batch'
);

-- A second active user cannot read any private artifact of the hold owner.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e9555555-5555-5555-5555-555555555555"}',
  true
);

select ok(
  (select count(*) from public.personal_challenge_terms
   where user_id = 'e9333333-3333-3333-3333-333333333333') = 0
  and
  (select count(*) from public.personal_trusted_diagnostics
   where user_id = 'e9333333-3333-3333-3333-333333333333') = 0
  and
  (select count(*) from public.personal_challenge_results
   where user_id = 'e9333333-3333-3333-3333-333333333333') = 0
  and
  (select count(*) from public.personal_eligibility_holds
   where user_id = 'e9333333-3333-3333-3333-333333333333') = 0,
  'two-user RLS hides terms, diagnostic state, result, and eligibility hold'
);

select ok(
  not has_table_privilege(
    'service_role', 'app.personal_evidence_assessments', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'app.personal_evidence_assessments', 'select'
  ),
  'the evidence assessment ledger is reachable only through service RPCs'
);

select * from finish();
rollback;
