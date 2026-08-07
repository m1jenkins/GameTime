-- Beta workstream 4: deterministic due-result classification, publication,
-- bounded failure visibility, and safe worker reruns.

begin;
select plan(17);

insert into auth.users (id) values
  ('fb111111-1111-1111-1111-111111111111'),
  ('fb222222-2222-2222-2222-222222222222'),
  ('fb333333-3333-3333-3333-333333333333'),
  ('fb444444-4444-4444-4444-444444444444');

insert into public.profiles (id, handle, display_name, timezone) values
  (
    'fb111111-1111-1111-1111-111111111111',
    'workercomplete',
    'Worker Complete',
    'UTC'
  ),
  (
    'fb222222-2222-2222-2222-222222222222',
    'workermissing',
    'Worker Missing',
    'UTC'
  ),
  (
    'fb333333-3333-3333-3333-333333333333',
    'workerfailure',
    'Worker Failure',
    'UTC'
  ),
  (
    'fb444444-4444-4444-4444-444444444444',
    'workerpositive',
    'Worker Positive',
    'UTC'
  );

create temporary table t_worker_keys as
select
  ('\x04' || repeat('b1', 64))::bytea as production_public_key,
  extensions.digest(
    ('\x04' || repeat('b1', 64))::bytea,
    'sha256'
  ) as production_key_id,
  ('\x04' || repeat('b2', 64))::bytea as development_public_key,
  extensions.digest(
    ('\x04' || repeat('b2', 64))::bytea,
    'sha256'
  ) as development_key_id,
  ('\x04' || repeat('b3', 64))::bytea as positive_public_key,
  extensions.digest(
    ('\x04' || repeat('b3', 64))::bytea,
    'sha256'
  ) as positive_key_id;

insert into public.device_attestations (
  key_id,
  user_id,
  public_key,
  environment
)
select
  production_key_id,
  'fb111111-1111-1111-1111-111111111111'::uuid,
  production_public_key,
  'production'::public.attestation_environment
from t_worker_keys
union all
select
  development_key_id,
  'fb333333-3333-3333-3333-333333333333'::uuid,
  development_public_key,
  'development'::public.attestation_environment
from t_worker_keys
union all
select
  positive_key_id,
  'fb444444-4444-4444-4444-444444444444'::uuid,
  positive_public_key,
  'production'::public.attestation_environment
from t_worker_keys;

alter table public.contests disable trigger contests_assert_future_window;

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
select
  challenge_id,
  'Personal result worker fixture',
  owner_id,
  'personal_accountability'::public.challenge_model,
  'steps'::public.contest_metric,
  'cumulative'::public.contest_cadence,
  1,
  1000,
  'void'::public.contest_tie_break,
  '2026-07-01T00:00:00Z'::timestamptz,
  '2026-07-08T00:00:00Z'::timestamptz,
  1,
  'active'::public.contest_status
from (
  values
    (
      'fb000000-0000-0000-0000-000000000001'::uuid,
      'fb111111-1111-1111-1111-111111111111'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000002'::uuid,
      'fb222222-2222-2222-2222-222222222222'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000003'::uuid,
      'fb333333-3333-3333-3333-333333333333'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000004'::uuid,
      'fb444444-4444-4444-4444-444444444444'::uuid
    )
) fixture(challenge_id, owner_id);

alter table public.contests enable trigger contests_assert_future_window;

alter table public.contest_participants
  disable trigger contest_participants_apply_transition;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  timezone,
  charity_id,
  accepted_at
)
select
  challenge_id,
  owner_id,
  'accepted'::public.contest_participant_status,
  'UTC',
  null,
  '2026-06-30T00:00:00Z'::timestamptz
from (
  values
    (
      'fb000000-0000-0000-0000-000000000001'::uuid,
      'fb111111-1111-1111-1111-111111111111'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000002'::uuid,
      'fb222222-2222-2222-2222-222222222222'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000003'::uuid,
      'fb333333-3333-3333-3333-333333333333'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000004'::uuid,
      'fb444444-4444-4444-4444-444444444444'::uuid
    )
) fixture(challenge_id, owner_id);

alter table public.contest_participants
  enable trigger contest_participants_apply_transition;

insert into public.personal_challenge_terms (
  challenge_id,
  user_id,
  cadence,
  target_steps,
  commitment_amount_minor,
  timezone,
  agreed_at,
  evidence_cutoff
)
select
  challenge_id,
  owner_id,
  'cumulative'::public.contest_cadence,
  1,
  1000,
  'UTC',
  '2026-06-30T00:00:00Z'::timestamptz,
  '2026-07-09T00:00:00Z'::timestamptz
from (
  values
    (
      'fb000000-0000-0000-0000-000000000001'::uuid,
      'fb111111-1111-1111-1111-111111111111'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000002'::uuid,
      'fb222222-2222-2222-2222-222222222222'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000003'::uuid,
      'fb333333-3333-3333-3333-333333333333'::uuid
    ),
    (
      'fb000000-0000-0000-0000-000000000004'::uuid,
      'fb444444-4444-4444-4444-444444444444'::uuid
    )
) fixture(challenge_id, owner_id);

insert into public.personal_sync_coverage_batches (
  id,
  challenge_id,
  user_id,
  client_coverage_id,
  key_id,
  sign_count,
  payload_digest,
  observed_at,
  covered_bucket_count
)
select
  'fb100000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000001',
  'fb111111-1111-1111-1111-111111111111',
  'fb110000-0000-0000-0000-000000000001',
  production_key_id,
  1,
  extensions.digest('worker complete coverage', 'sha256'),
  '2026-07-08T12:00:00Z',
  (
    select count(*)::integer
    from app.personal_expected_coverage_buckets_v1(
      'fb000000-0000-0000-0000-000000000001',
      'infinity'::timestamptz
    )
  )
from t_worker_keys;

insert into public.personal_sync_coverage_buckets (
  coverage_batch_id,
  challenge_id,
  user_id,
  bucket_start
)
select
  'fb100000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000001',
  'fb111111-1111-1111-1111-111111111111',
  expected.bucket_start
from app.personal_expected_coverage_buckets_v1(
  'fb000000-0000-0000-0000-000000000001',
  'infinity'::timestamptz
) expected;

insert into public.personal_sync_coverage_batches (
  id,
  challenge_id,
  user_id,
  client_coverage_id,
  key_id,
  sign_count,
  payload_digest,
  observed_at,
  covered_bucket_count
)
select
  'fb100000-0000-0000-0000-000000000004',
  'fb000000-0000-0000-0000-000000000004',
  'fb444444-4444-4444-4444-444444444444',
  'fb110000-0000-0000-0000-000000000004',
  positive_key_id,
  1,
  extensions.digest('worker positive coverage', 'sha256'),
  '2026-07-08T12:00:00Z',
  (
    select count(*)::integer
    from app.personal_expected_coverage_buckets_v1(
      'fb000000-0000-0000-0000-000000000004',
      'infinity'::timestamptz
    )
  )
from t_worker_keys;

insert into public.personal_sync_coverage_buckets (
  coverage_batch_id,
  challenge_id,
  user_id,
  bucket_start
)
select
  'fb100000-0000-0000-0000-000000000004',
  'fb000000-0000-0000-0000-000000000004',
  'fb444444-4444-4444-4444-444444444444',
  expected.bucket_start
from app.personal_expected_coverage_buckets_v1(
  'fb000000-0000-0000-0000-000000000004',
  'infinity'::timestamptz
) expected;

insert into public.ingest_batches (
  id,
  contest_id,
  user_id,
  client_batch_id,
  key_id,
  sign_count,
  attested,
  payload_digest,
  observation_count,
  observed_at
)
select
  'fb200000-0000-0000-0000-000000000004',
  'fb000000-0000-0000-0000-000000000004',
  'fb444444-4444-4444-4444-444444444444',
  'fb210000-0000-0000-0000-000000000004',
  positive_key_id,
  1,
  true,
  extensions.digest('worker positive evidence', 'sha256'),
  1,
  '2026-07-02T00:00:00Z'
from t_worker_keys;

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  batch_id,
  contest_id,
  user_id,
  metric,
  bucket_start,
  local_day,
  local_hour,
  value,
  provenance,
  sample_count,
  source_bundle_id,
  device_model,
  observed_at,
  recorded_at
)
values (
  'fb200000-0000-0000-0000-000000000004',
  'fb000000-0000-0000-0000-000000000004',
  'fb444444-4444-4444-4444-444444444444',
  'steps',
  '2026-07-01T00:00:00Z',
  '2026-07-01',
  0,
  10,
  'device',
  1,
  'com.apple.health',
  'iPhone',
  '2026-07-02T00:00:00Z',
  '2026-07-02T00:00:00Z'
);

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

-- A retained development-origin batch makes this deliberately malformed legacy
-- assessment fail the newer publication provenance guard. The worker must
-- isolate and surface that failure without blocking the other two challenges.
insert into public.ingest_batches (
  id,
  contest_id,
  user_id,
  client_batch_id,
  key_id,
  sign_count,
  attested,
  payload_digest,
  observation_count,
  observed_at
)
select
  'fb200000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000003',
  'fb333333-3333-3333-3333-333333333333',
  'fb210000-0000-0000-0000-000000000001',
  development_key_id,
  1,
  true,
  extensions.digest('legacy development evidence', 'sha256'),
  1,
  '2026-07-02T00:00:00Z'
from t_worker_keys;

alter table app.personal_evidence_assessments
  disable trigger personal_assessments_require_production_evidence;

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
  outage_reference,
  assessed_at
)
values (
  'fb300000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000003',
  'fb333333-3333-3333-3333-333333333333',
  'fb310000-0000-0000-0000-000000000001',
  'complete',
  '2026-07-09T00:00:00Z',
  'personal-v1',
  extensions.digest('legacy complete assessment', 'sha256'),
  168,
  168,
  0,
  jsonb_build_array(
    jsonb_build_object('local_date', '2026-07-01', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-02', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-03', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-04', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-05', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-06', 'total_steps', 0),
    jsonb_build_object('local_date', '2026-07-07', 'total_steps', 0)
  ),
  null,
  '2026-07-09T00:00:01Z'
);

alter table app.personal_evidence_assessments
  enable trigger personal_assessments_require_production_evidence;

select ok(
  exists (
    select 1
    from cron.job job
    where job.jobname = 'gametime-publish-personal-results'
      and job.schedule = '*/5 * * * *'
      and job.command = 'select app.run_personal_result_worker();'
      and not job.active
  ),
  'one named five-minute Personal result job is configured but dormant'
);

select ok(
  has_function_privilege(
    'service_role',
    'app.run_personal_result_worker()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'app.run_personal_result_worker()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'app.publish_due_personal_result_v1(uuid,timestamptz)',
    'EXECUTE'
  ),
  'only the bounded worker entry point is available to service_role'
);

select is(
  (
    select classified.evidence_state
    from app.classify_personal_result_evidence_v1(
      'fb000000-0000-0000-0000-000000000001'
    ) classified
  ),
  'complete'::public.personal_evidence_state,
  'exact production coverage is classified complete'
);

select is(
  (
    select classified.evidence_state
    from app.classify_personal_result_evidence_v1(
      'fb000000-0000-0000-0000-000000000002'
    ) classified
  ),
  'missing'::public.personal_evidence_state,
  'absent coverage is classified fail-closed as missing'
);

select is(
  (
    select classified.evidence_state
    from app.classify_personal_result_evidence_v1(
      'fb000000-0000-0000-0000-000000000004'
    ) classified
  ),
  'complete'::public.personal_evidence_state,
  'positive production evidence with exact coverage is complete'
);

create temporary table t_bounded_worker_run as
select *
from app.run_personal_result_worker_at(clock_timestamp(), 1);

select ok(
  (
    select
      challenges_selected = 1
      and results_published = 1
      and failures_recorded = 0
    from t_bounded_worker_run
  )
  and (
    select count(*)
    from public.personal_challenge_results result
    where result.challenge_id in (
      'fb000000-0000-0000-0000-000000000001',
      'fb000000-0000-0000-0000-000000000002',
      'fb000000-0000-0000-0000-000000000003',
      'fb000000-0000-0000-0000-000000000004'
    )
  ) = 1,
  'the injected limit bounds one sweep to exactly one due challenge'
);

create temporary table t_first_worker_run as
select *
from app.run_personal_result_worker_at(clock_timestamp(), 10);

select ok(
  (
    select
      challenges_selected = 3
      and results_published = 2
      and failures_recorded = 1
    from t_first_worker_run
  ),
  'one sweep publishes complete and incomplete results while isolating failure'
);

select ok(
  (
    select
      result.outcome = 'missed_goal'
      and result.reason = 'target_missed'
      and result.evidence_state = 'complete'
      and not result.commitment_waived
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000001'
  ),
  'complete zero-step evidence publishes one immutable target miss'
);

select ok(
  (
    select
      result.outcome = 'inconclusive'
      and result.reason = 'missing_coverage'
      and result.evidence_state = 'missing'
      and result.commitment_waived
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000002'
  ),
  'incomplete evidence publishes a waived inconclusive result'
);

select ok(
  (
    select
      result.outcome = 'met_goal'
      and result.reason = 'target_reached'
      and result.evidence_state = 'complete'
      and result.total_steps = 10
      and not result.commitment_waived
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000004'
  )
  and not exists (
    select 1
    from public.personal_eligibility_holds hold
    where hold.challenge_id =
      'fb000000-0000-0000-0000-000000000004'
  ),
  'positive complete evidence publishes a met result without creating a hold'
);

select ok(
  not exists (
    select 1
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000003'
  )
  and exists (
    select 1
    from app.personal_result_worker_attempts attempt
    where attempt.challenge_id =
      'fb000000-0000-0000-0000-000000000003'
      and attempt.last_status = 'failed'
      and attempt.last_sqlstate = '23001'
      and attempt.published_result_id is null
  ),
  'a guarded publication failure stores SQLSTATE only and no result'
);

create temporary table t_published_ids as
select result.challenge_id, result.id
from public.personal_challenge_results result
where result.challenge_id in (
  'fb000000-0000-0000-0000-000000000001',
  'fb000000-0000-0000-0000-000000000002',
  'fb000000-0000-0000-0000-000000000004'
);

create temporary table t_second_worker_run as
select *
from app.run_personal_result_worker_at(clock_timestamp(), 10);

select ok(
  (
    select
      challenges_selected = 1
      and results_published = 0
      and failures_recorded = 1
    from t_second_worker_run
  ),
  'a rerun skips both terminal results and retries only the unresolved failure'
);

select ok(
  (
    select count(*)
    from public.personal_challenge_results result
    where result.challenge_id in (
      'fb000000-0000-0000-0000-000000000001',
      'fb000000-0000-0000-0000-000000000002',
      'fb000000-0000-0000-0000-000000000004'
    )
  ) = 3
  and not exists (
    select 1
    from t_published_ids frozen
    join public.personal_challenge_results result
      on result.challenge_id = frozen.challenge_id
    where result.id <> frozen.id
  ),
  'safe rerun neither duplicates nor replaces an immutable result'
);

select ok(
  (
    select count(*)
    from app.personal_result_worker_attempts attempt
    where attempt.last_status = 'published'
      and attempt.attempt_count = 1
  ) = 3
  and (
    select attempt.attempt_count
    from app.personal_result_worker_attempts attempt
    where attempt.challenge_id =
      'fb000000-0000-0000-0000-000000000003'
  ) = 2,
  'bounded attempt state keeps one row per challenge and increments retries'
);

select ok(
  not exists (
    select 1
    from public.contest_results legacy
    where legacy.contest_id in (
      'fb000000-0000-0000-0000-000000000001',
      'fb000000-0000-0000-0000-000000000002',
      'fb000000-0000-0000-0000-000000000003',
      'fb000000-0000-0000-0000-000000000004'
    )
  )
  and not exists (
    select 1
    from public.donation_obligations obligation
    where obligation.contest_id in (
      'fb000000-0000-0000-0000-000000000001',
      'fb000000-0000-0000-0000-000000000002',
      'fb000000-0000-0000-0000-000000000003',
      'fb000000-0000-0000-0000-000000000004'
    )
  )
  and not exists (
    select 1
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id in (
      'fb000000-0000-0000-0000-000000000001',
      'fb000000-0000-0000-0000-000000000002',
      'fb000000-0000-0000-0000-000000000003',
      'fb000000-0000-0000-0000-000000000004'
    )
  ),
  'the worker creates no Social result, donation obligation, or charge command'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fb111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (
    select count(*)
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000001'
  ) = 1
  and (
    select count(*)
    from public.personal_challenge_results result
    where result.challenge_id =
      'fb000000-0000-0000-0000-000000000004'
  ) = 0,
  'an authenticated owner sees their worker result but not another account result'
);

reset role;

select ok(
  (
    select
      health.scheduler_configured
      and not health.scheduler_active
      and health.due_challenges = 1
      and health.overdue_challenges = 1
      and health.current_failures = 1
      and health.oldest_overdue_cutoff =
        '2026-07-09T00:00:00Z'::timestamptz
      and health.last_attempt_at is not null
      and health.last_failure_at is not null
      and health.last_failure_sqlstate = '23001'
    from app.personal_result_worker_health_v1(clock_timestamp()) health
  ),
  'daily health check exposes only aggregate overdue and failure signals'
);

select * from finish();
rollback;
