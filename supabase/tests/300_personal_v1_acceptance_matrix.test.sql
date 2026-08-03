-- Personal V1 scoring/evidence acceptance matrix plus late grace-period sync.

begin;
select plan(17);

insert into auth.users (id) values
  ('f0111111-1111-1111-1111-111111111111'),
  ('f0222222-2222-2222-2222-222222222222'),
  ('f0333333-3333-3333-3333-333333333333'),
  ('f0444444-4444-4444-4444-444444444444'),
  ('f0555555-5555-5555-5555-555555555555'),
  ('f0666666-6666-6666-6666-666666666666'),
  ('f0777777-7777-7777-7777-777777777777'),
  ('f0888888-8888-8888-8888-888888888888'),
  ('f0999999-9999-9999-9999-999999999999');

insert into public.profiles (id, handle, display_name, timezone) values
  ('f0111111-1111-1111-1111-111111111111', 'p1dailyyes', 'Daily Yes', 'UTC'),
  ('f0222222-2222-2222-2222-222222222222', 'p1dailyno', 'Daily No', 'UTC'),
  ('f0333333-3333-3333-3333-333333333333', 'p1cumulativeyes', 'Cumulative Yes', 'UTC'),
  ('f0444444-4444-4444-4444-444444444444', 'p1cumulativeno', 'Cumulative No', 'UTC'),
  ('f0555555-5555-5555-5555-555555555555', 'p1missing', 'Missing', 'UTC'),
  ('f0666666-6666-6666-6666-666666666666', 'p1quarantined', 'Quarantined', 'UTC'),
  ('f0777777-7777-7777-7777-777777777777', 'p1conflicting', 'Conflicting', 'UTC'),
  ('f0888888-8888-8888-8888-888888888888', 'p1unresolved', 'Unresolved', 'UTC'),
  ('f0999999-9999-9999-9999-999999999999', 'p1late', 'Late Sync', 'UTC');

create function pg_temp.make_personal(
  p_challenge_id uuid,
  p_user_id uuid,
  p_cadence public.contest_cadence,
  p_target integer,
  p_first_date date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_start timestamptz := p_first_date::timestamp at time zone 'UTC';
  v_end timestamptz := (p_first_date + 7)::timestamp at time zone 'UTC';
begin
  insert into public.contests (
    id, title, created_by, challenge_model, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  ) values (
    p_challenge_id, 'Acceptance matrix', p_user_id,
    'personal_accountability', 'steps', p_cadence, p_target,
    1000, 'void', v_start, v_end, 1
  );

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  ) values (p_challenge_id, p_user_id, 'accepted', 'UTC', null);

  insert into public.personal_challenge_terms (
    challenge_id, user_id, cadence, target_steps,
    commitment_amount_minor, timezone, agreed_at, evidence_cutoff
  ) values (
    p_challenge_id, p_user_id, p_cadence, p_target,
    1000, 'UTC', v_start - interval '1 day', v_end + interval '24 hours'
  );
end;
$$;

alter table public.contests disable trigger contests_assert_future_window;

select pg_temp.make_personal('f0000000-0000-0000-0000-000000000001', 'f0111111-1111-1111-1111-111111111111', 'daily', 100, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000002', 'f0222222-2222-2222-2222-222222222222', 'daily', 100, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000003', 'f0333333-3333-3333-3333-333333333333', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000004', 'f0444444-4444-4444-4444-444444444444', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000005', 'f0555555-5555-5555-5555-555555555555', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000006', 'f0666666-6666-6666-6666-666666666666', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000007', 'f0777777-7777-7777-7777-777777777777', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal('f0000000-0000-0000-0000-000000000008', 'f0888888-8888-8888-8888-888888888888', 'cumulative', 700, '2026-07-20');
select pg_temp.make_personal(
  'f0000000-0000-0000-0000-000000000009',
  'f0999999-9999-9999-9999-999999999999',
  'cumulative', 700,
  (clock_timestamp() at time zone 'UTC')::date - 7
);

alter table public.contests enable trigger contests_assert_future_window;

create temporary table t_activation as
select * from app.activate_due_contests(clock_timestamp());

select is(
  (
    select count(*) from t_activation
    where outcome = 'active'
      and contest_id::text like 'f0000000-0000-0000-0000-00000000000%'
  ),
  9::bigint,
  'all matrix fixtures activate with one owner'
);

create temporary table t_keys as
select
  ('\x04' || repeat('a1', 64))::bytea as k1,
  extensions.digest(('\x04' || repeat('a1', 64))::bytea, 'sha256') as k1id,
  ('\x04' || repeat('a2', 64))::bytea as k2,
  extensions.digest(('\x04' || repeat('a2', 64))::bytea, 'sha256') as k2id,
  ('\x04' || repeat('a3', 64))::bytea as k3,
  extensions.digest(('\x04' || repeat('a3', 64))::bytea, 'sha256') as k3id,
  ('\x04' || repeat('a4', 64))::bytea as k4,
  extensions.digest(('\x04' || repeat('a4', 64))::bytea, 'sha256') as k4id,
  ('\x04' || repeat('a9', 64))::bytea as k9,
  extensions.digest(('\x04' || repeat('a9', 64))::bytea, 'sha256') as k9id;

insert into public.device_attestations (key_id, user_id, public_key, environment)
select k1id, 'f0111111-1111-1111-1111-111111111111'::uuid, k1, 'production'::public.attestation_environment from t_keys
union all
select k2id, 'f0222222-2222-2222-2222-222222222222'::uuid, k2, 'production'::public.attestation_environment from t_keys
union all
select k3id, 'f0333333-3333-3333-3333-333333333333'::uuid, k3, 'production'::public.attestation_environment from t_keys
union all
select k4id, 'f0444444-4444-4444-4444-444444444444'::uuid, k4, 'production'::public.attestation_environment from t_keys;

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
  v_end timestamptz;
begin
  select contest.ends_at into v_end
  from public.contests contest where contest.id = p_challenge_id;
  select count(*)::integer into v_count
  from app.personal_expected_coverage_buckets_v1(p_challenge_id, 'infinity');

  insert into public.personal_sync_coverage_batches (
    id, challenge_id, user_id, client_coverage_id, key_id, sign_count,
    payload_digest, observed_at, covered_bucket_count
  ) values (
    p_batch_id, p_challenge_id, p_user_id, p_batch_id, p_key_id, 1,
    extensions.digest(p_batch_id::text, 'sha256'), v_end, v_count
  );

  insert into public.personal_sync_coverage_buckets (
    coverage_batch_id, challenge_id, user_id, bucket_start
  )
  select p_batch_id, p_challenge_id, p_user_id, expected.bucket_start
  from app.personal_expected_coverage_buckets_v1(p_challenge_id, 'infinity') expected;
end;
$$;

select pg_temp.cover_all('f0000000-0000-0000-0000-000000000001', 'f0111111-1111-1111-1111-111111111111', (select k1id from t_keys), 'f0100000-0000-0000-0000-000000000001');
select pg_temp.cover_all('f0000000-0000-0000-0000-000000000002', 'f0222222-2222-2222-2222-222222222222', (select k2id from t_keys), 'f0200000-0000-0000-0000-000000000001');
select pg_temp.cover_all('f0000000-0000-0000-0000-000000000003', 'f0333333-3333-3333-3333-333333333333', (select k3id from t_keys), 'f0300000-0000-0000-0000-000000000001');
select pg_temp.cover_all('f0000000-0000-0000-0000-000000000004', 'f0444444-4444-4444-4444-444444444444', (select k4id from t_keys), 'f0400000-0000-0000-0000-000000000001');

insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, key_id, sign_count, attested,
  payload_digest, observation_count, observed_at, recorded_at
) values
  ('f0100000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', 'f0111111-1111-1111-1111-111111111111', 'f0100000-0000-0000-0000-000000000002', (select k1id from t_keys), 1, true, extensions.digest('daily-success', 'sha256'), 7, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'),
  ('f0200000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000002', 'f0222222-2222-2222-2222-222222222222', 'f0200000-0000-0000-0000-000000000002', (select k2id from t_keys), 1, true, extensions.digest('daily-miss', 'sha256'), 7, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'),
  ('f0300000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000003', 'f0333333-3333-3333-3333-333333333333', 'f0300000-0000-0000-0000-000000000002', (select k3id from t_keys), 1, true, extensions.digest('cumulative-success', 'sha256'), 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'),
  ('f0400000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000004', 'f0444444-4444-4444-4444-444444444444', 'f0400000-0000-0000-0000-000000000002', (select k4id from t_keys), 1, true, extensions.digest('cumulative-miss', 'sha256'), 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z');

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, observed_at, recorded_at
)
select
  'f0100000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000001',
  'f0111111-1111-1111-1111-111111111111',
  'steps', contest.starts_at + day_index * interval '1 day',
  (contest.starts_at at time zone 'UTC')::date + day_index,
  0, 100, 'device', 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
from public.contests contest
cross join generate_series(0, 6) day_index
where contest.id = 'f0000000-0000-0000-0000-000000000001';

insert into public.metric_snapshots (
  batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, observed_at, recorded_at
)
select
  'f0200000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000002',
  'f0222222-2222-2222-2222-222222222222',
  'steps', contest.starts_at + day_index * interval '1 day',
  (contest.starts_at at time zone 'UTC')::date + day_index,
  0, case when day_index = 6 then 99 else 100 end,
  'device', 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
from public.contests contest
cross join generate_series(0, 6) day_index
where contest.id = 'f0000000-0000-0000-0000-000000000002';

insert into public.metric_snapshots (
  batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, observed_at, recorded_at
)
select
  'f0300000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000003',
  'f0333333-3333-3333-3333-333333333333',
  'steps', contest.starts_at, (contest.starts_at at time zone 'UTC')::date,
  0, 700, 'device', 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
from public.contests contest
where contest.id = 'f0000000-0000-0000-0000-000000000003';

insert into public.metric_snapshots (
  batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, observed_at, recorded_at
)
select
  'f0400000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000004',
  'f0444444-4444-4444-4444-444444444444',
  'steps', contest.starts_at, (contest.starts_at at time zone 'UTC')::date,
  0, 699, 'device', 1, '2026-07-27T00:00:00Z', '2026-07-27T12:00:00Z'
from public.contests contest
where contest.id = 'f0000000-0000-0000-0000-000000000004';

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

create function pg_temp.assess_and_publish(
  p_challenge_id uuid,
  p_request_id uuid,
  p_state public.personal_evidence_state,
  p_digest_seed text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_assessment uuid;
begin
  v_assessment := public.record_personal_assessment_v1(
    p_challenge_id, p_request_id, p_state, 'personal-v1',
    extensions.digest(p_digest_seed, 'sha256'), null
  );
  return public.publish_personal_result_v1(p_challenge_id, v_assessment);
end;
$$;

select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000001', 'f0100000-0000-0000-0000-000000000003', 'complete', 'daily-success-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000002', 'f0200000-0000-0000-0000-000000000003', 'complete', 'daily-miss-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000003', 'f0300000-0000-0000-0000-000000000003', 'complete', 'cumulative-success-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000004', 'f0400000-0000-0000-0000-000000000003', 'complete', 'cumulative-miss-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000005', 'f0500000-0000-0000-0000-000000000003', 'missing', 'missing-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000006', 'f0600000-0000-0000-0000-000000000003', 'quarantined', 'quarantined-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000007', 'f0700000-0000-0000-0000-000000000003', 'conflicting', 'conflicting-assessment');
select pg_temp.assess_and_publish('f0000000-0000-0000-0000-000000000008', 'f0800000-0000-0000-0000-000000000003', 'unresolved', 'unresolved-assessment');

select ok(
  (select outcome = 'met_goal' and reason = 'target_reached' and not commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000001'),
  'daily succeeds only when all seven trusted days meet target'
);

select ok(
  (select outcome = 'missed_goal' and reason = 'target_missed' and not commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000002'),
  'one verified missed day makes a complete daily challenge miss'
);

select is(
  (
    select count(*)
    from jsonb_array_elements(
      (select daily_totals from public.personal_challenge_results
       where challenge_id = 'f0000000-0000-0000-0000-000000000002')
    ) day
    where (day ->> 'total_steps')::numeric < 100
  ),
  1::bigint,
  'the daily miss fixture contains exactly one sub-target day'
);

select ok(
  (select outcome = 'met_goal' and reason = 'target_reached' and total_steps = 700
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000003'),
  'cumulative succeeds at the exact seven-day target'
);

select ok(
  (select outcome = 'missed_goal' and reason = 'target_missed' and total_steps = 699
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000004'),
  'cumulative misses below the seven-day target'
);

select ok(
  (select outcome = 'inconclusive' and reason = 'missing_coverage' and commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000005'),
  'missing coverage is inconclusive and waived'
);

select ok(
  (select outcome = 'inconclusive' and reason = 'quarantined_evidence' and commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000006'),
  'quarantined evidence is inconclusive and waived'
);

select ok(
  (select outcome = 'inconclusive' and reason = 'conflicting_evidence' and commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000007'),
  'conflicting evidence is inconclusive and waived'
);

select ok(
  (select outcome = 'inconclusive' and reason = 'unresolved_evidence' and commitment_waived
   from public.personal_challenge_results where challenge_id = 'f0000000-0000-0000-0000-000000000008'),
  'unresolved evidence is inconclusive and waived'
);

select is(
  (
    select count(*) from public.personal_eligibility_holds
    where challenge_id in (
      'f0000000-0000-0000-0000-000000000005',
      'f0000000-0000-0000-0000-000000000006',
      'f0000000-0000-0000-0000-000000000007',
      'f0000000-0000-0000-0000-000000000008'
    )
  ),
  0::bigint,
  'non-device inconclusive outcomes never place an eligibility hold'
);

-- Late evidence and zero-valued coverage are accepted through the 24-hour
-- grace period while the challenge remains active.
select public.register_device_key(
  'f0999999-9999-9999-9999-999999999999',
  (select k9id from t_keys), (select k9 from t_keys),
  '\x6c6174652d72656365697074', 'production'
);
select public.mark_device_receipt_verified(
  (select k9id from t_keys),
  extensions.digest('\x6c6174652d72656365697074'::bytea, 'sha256')
);

create temporary table t_late_bucket as
select ends_at - interval '1 hour' as bucket_start
from public.contests
where id = 'f0000000-0000-0000-0000-000000000009';

grant select on t_late_bucket to service_role;

set local role service_role;

create temporary table t_late_metric as
select * from public.record_metric_batch(
  'f0999999-9999-9999-9999-999999999999',
  'f0000000-0000-0000-0000-000000000009',
  'f0900000-0000-0000-0000-000000000001',
  extensions.digest('late-metric', 'sha256'),
  clock_timestamp(),
  jsonb_build_array(jsonb_build_object(
    'metric', 'steps',
    'bucket_start', (select bucket_start from t_late_bucket),
    'value', 50,
    'provenance', 'device',
    'sample_count', 2,
    'source_bundle_id', 'com.apple.health',
    'device_model', 'iPhone'
  )),
  extensions.digest(('\x04' || repeat('a9', 64))::bytea, 'sha256'),
  1
);

create temporary table t_late_coverage as
select * from public.record_personal_sync_coverage_v1(
  'f0999999-9999-9999-9999-999999999999',
  'f0000000-0000-0000-0000-000000000009',
  'f0900000-0000-0000-0000-000000000002',
  extensions.digest('late-coverage', 'sha256'),
  clock_timestamp(),
  jsonb_build_array((select bucket_start from t_late_bucket)),
  extensions.digest(('\x04' || repeat('a9', 64))::bytea, 'sha256'),
  2
);

select ok(
  (select observation_count = 1 and not replayed from t_late_metric)
  and (select not replayed from t_late_coverage),
  'trusted metric and coverage backfill both land after day seven within grace'
);

select throws_ok(
  $$ select public.record_personal_assessment_v1(
       'f0000000-0000-0000-0000-000000000009',
       'f0900000-0000-0000-0000-000000000003',
       'missing', 'personal-v1',
       extensions.digest('too-early-assessment', 'sha256'), null
     ) $$,
  '23001',
  null,
  'final assessment cannot run before the full 24-hour grace expires'
);

select throws_ok(
  $$ select * from public.record_trusted_personal_diagnostic_v1(
       'f0999999-9999-9999-9999-999999999999',
       'f0900000-0000-0000-0000-000000000004',
       extensions.digest('oversized-diagnostic', 'sha256'),
       clock_timestamp(), clock_timestamp() - interval '1 hour',
       clock_timestamp() - interval '1 minute', 100001,
       extensions.digest(('\x04' || repeat('a9', 64))::bytea, 'sha256'),
       3
     ) $$,
  '22023',
  null,
  'the database matches the Edge cap of 100000 diagnostic samples'
);

reset role;

select is(
  (
    select total_steps
    from app.personal_challenge_cards_v1(
      'f0999999-9999-9999-9999-999999999999',
      'f0000000-0000-0000-0000-000000000009'
    )
  ),
  50::numeric,
  'late trusted backfill appears in owner progress before final assessment'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f0999999-9999-9999-9999-999999999999"}', true
);

select ok(
  (select count(*) from public.personal_sync_coverage_batches
   where challenge_id = 'f0000000-0000-0000-0000-000000000009') = 1
  and
  (select count(*) from public.personal_sync_coverage_buckets
   where challenge_id = 'f0000000-0000-0000-0000-000000000009') = 1,
  'the owner can read their own coverage batch and interval'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0555555-5555-5555-5555-555555555555"}', true
);

select ok(
  (select count(*) from public.personal_sync_coverage_batches
   where challenge_id = 'f0000000-0000-0000-0000-000000000009') = 0
  and
  (select count(*) from public.personal_sync_coverage_buckets
   where challenge_id = 'f0000000-0000-0000-0000-000000000009') = 0,
  'two-user RLS hides both another owner coverage batch and its intervals'
);

select * from finish();
rollback;
