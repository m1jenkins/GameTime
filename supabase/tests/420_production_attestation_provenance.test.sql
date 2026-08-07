-- Production App Attest provenance: durable snapshots, exact-key retries, and
-- fail-closed Personal V1 complete assessment.

begin;
select plan(32);

insert into auth.users (id)
values ('fa111111-1111-1111-1111-111111111111');

insert into public.profiles (id, handle, display_name, timezone)
values (
  'fa111111-1111-1111-1111-111111111111',
  'provenancefixture',
  'Provenance Fixture',
  'UTC'
);

create temporary table t_keys as
select
  ('\x04' || repeat('a1', 64))::bytea as production_public_key,
  extensions.digest(
    ('\x04' || repeat('a1', 64))::bytea,
    'sha256'
  ) as production_key_id,
  ('\x04' || repeat('d1', 64))::bytea as development_public_key,
  extensions.digest(
    ('\x04' || repeat('d1', 64))::bytea,
    'sha256'
  ) as development_key_id,
  extensions.digest('missing historical key', 'sha256') as unknown_key_id;

-- Register both keys the way a device does, receipt and all. This file tests
-- what the App Attest environment is allowed to do, so neither key may be
-- refused earlier for an unrelated reason: a key with no verified receipt is
-- rejected by app.consume_trusted_personal_assertion before provenance is ever
-- consulted, which would make every guard below look like it was holding.
select public.register_device_key(
  'fa111111-1111-1111-1111-111111111111',
  (select production_key_id from t_keys),
  (select production_public_key from t_keys),
  '\x70726f64756374696f6e2d72656365697074',
  'production'
);
select public.mark_device_receipt_verified(
  (select production_key_id from t_keys),
  extensions.digest(
    '\x70726f64756374696f6e2d72656365697074'::bytea,
    'sha256'
  )
);

select public.register_device_key(
  'fa111111-1111-1111-1111-111111111111',
  (select development_key_id from t_keys),
  (select development_public_key from t_keys),
  '\x646576656c6f706d656e742d72656365697074',
  'development'
);
select public.mark_device_receipt_verified(
  (select development_key_id from t_keys),
  extensions.digest(
    '\x646576656c6f706d656e742d72656365697074'::bytea,
    'sha256'
  )
);

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
  'Production provenance fixture',
  'fa111111-1111-1111-1111-111111111111'::uuid,
  'personal_accountability'::public.challenge_model,
  'steps'::public.contest_metric,
  'cumulative'::public.contest_cadence,
  100,
  1000,
  'void'::public.contest_tie_break,
  '2026-07-01T00:00:00Z'::timestamptz,
  '2026-07-08T00:00:00Z'::timestamptz,
  1,
  'finalized'::public.contest_status
from unnest(array[
  'fa000000-0000-0000-0000-000000000001'::uuid,
  'fa000000-0000-0000-0000-000000000002'::uuid,
  'fa000000-0000-0000-0000-000000000003'::uuid,
  'fa000000-0000-0000-0000-000000000004'::uuid,
  'fa000000-0000-0000-0000-000000000005'::uuid,
  'fa000000-0000-0000-0000-000000000006'::uuid,
  'fa000000-0000-0000-0000-000000000007'::uuid
]) as fixture(challenge_id);

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
  'fa111111-1111-1111-1111-111111111111'::uuid,
  'accepted'::public.contest_participant_status,
  'UTC',
  null,
  '2026-06-30T00:00:00Z'::timestamptz
from unnest(array[
  'fa000000-0000-0000-0000-000000000001'::uuid,
  'fa000000-0000-0000-0000-000000000002'::uuid,
  'fa000000-0000-0000-0000-000000000003'::uuid,
  'fa000000-0000-0000-0000-000000000004'::uuid,
  'fa000000-0000-0000-0000-000000000005'::uuid,
  'fa000000-0000-0000-0000-000000000006'::uuid,
  'fa000000-0000-0000-0000-000000000007'::uuid
]) as fixture(challenge_id);

alter table public.contest_participants
  enable trigger contest_participants_apply_transition;

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
values
  (
    'fa100000-0000-0000-0000-000000000001',
    'fa000000-0000-0000-0000-000000000001',
    'fa111111-1111-1111-1111-111111111111',
    'fa100000-0000-0000-0000-000000000001',
    (select production_key_id from t_keys),
    1,
    true,
    extensions.digest('production metric', 'sha256'),
    1,
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa100000-0000-0000-0000-000000000002',
    'fa000000-0000-0000-0000-000000000002',
    'fa111111-1111-1111-1111-111111111111',
    'fa100000-0000-0000-0000-000000000002',
    (select development_key_id from t_keys),
    1,
    true,
    extensions.digest('development metric', 'sha256'),
    1,
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa100000-0000-0000-0000-000000000003',
    'fa000000-0000-0000-0000-000000000003',
    'fa111111-1111-1111-1111-111111111111',
    'fa100000-0000-0000-0000-000000000003',
    null,
    null,
    false,
    extensions.digest('unknown metric', 'sha256'),
    1,
    '2026-07-02T01:00:00Z'
  );

select is(
  (
    select attestation_environment
    from public.ingest_batches
    where id = 'fa100000-0000-0000-0000-000000000001'
  ),
  'production'::public.attestation_environment,
  'a production metric batch snapshots production provenance'
);

select is(
  (
    select attestation_environment
    from public.ingest_batches
    where id = 'fa100000-0000-0000-0000-000000000002'
  ),
  'development'::public.attestation_environment,
  'a development metric batch snapshots development provenance'
);

select is(
  (
    select attestation_environment is null
    from public.ingest_batches
    where id = 'fa100000-0000-0000-0000-000000000003'
  ),
  true,
  'an unattested metric batch retains unknown provenance'
);

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
  observed_at
)
values
  (
    'fa100000-0000-0000-0000-000000000001',
    'fa000000-0000-0000-0000-000000000001',
    'fa111111-1111-1111-1111-111111111111',
    'steps',
    '2026-07-02T01:00:00Z',
    '2026-07-02',
    1,
    100,
    'device',
    1,
    'com.apple.health',
    'iPhone',
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa100000-0000-0000-0000-000000000002',
    'fa000000-0000-0000-0000-000000000002',
    'fa111111-1111-1111-1111-111111111111',
    'steps',
    '2026-07-02T01:00:00Z',
    '2026-07-02',
    1,
    100,
    'device',
    1,
    'com.apple.health',
    'iPhone',
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa100000-0000-0000-0000-000000000003',
    'fa000000-0000-0000-0000-000000000003',
    'fa111111-1111-1111-1111-111111111111',
    'steps',
    '2026-07-02T01:00:00Z',
    '2026-07-02',
    1,
    100,
    'device',
    1,
    'com.apple.health',
    'iPhone',
    '2026-07-02T01:00:00Z'
  );

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

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
values
  (
    'fa200000-0000-0000-0000-000000000001',
    'fa000000-0000-0000-0000-000000000001',
    'fa111111-1111-1111-1111-111111111111',
    'fa200000-0000-0000-0000-000000000001',
    (select production_key_id from t_keys),
    1,
    extensions.digest('production coverage', 'sha256'),
    '2026-07-02T01:00:00Z',
    1
  ),
  (
    'fa200000-0000-0000-0000-000000000002',
    'fa000000-0000-0000-0000-000000000004',
    'fa111111-1111-1111-1111-111111111111',
    'fa200000-0000-0000-0000-000000000002',
    (select development_key_id from t_keys),
    1,
    extensions.digest('development coverage', 'sha256'),
    '2026-07-02T01:00:00Z',
    1
  ),
  (
    'fa200000-0000-0000-0000-000000000003',
    'fa000000-0000-0000-0000-000000000005',
    'fa111111-1111-1111-1111-111111111111',
    'fa200000-0000-0000-0000-000000000003',
    (select unknown_key_id from t_keys),
    1,
    extensions.digest('unknown coverage', 'sha256'),
    '2026-07-02T01:00:00Z',
    1
  );

insert into public.personal_sync_coverage_buckets (
  coverage_batch_id,
  challenge_id,
  user_id,
  bucket_start
)
values
  (
    'fa200000-0000-0000-0000-000000000001',
    'fa000000-0000-0000-0000-000000000001',
    'fa111111-1111-1111-1111-111111111111',
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa200000-0000-0000-0000-000000000002',
    'fa000000-0000-0000-0000-000000000004',
    'fa111111-1111-1111-1111-111111111111',
    '2026-07-02T01:00:00Z'
  ),
  (
    'fa200000-0000-0000-0000-000000000003',
    'fa000000-0000-0000-0000-000000000005',
    'fa111111-1111-1111-1111-111111111111',
    '2026-07-02T01:00:00Z'
  );

select is(
  (
    select attestation_environment
    from public.personal_sync_coverage_batches
    where id = 'fa200000-0000-0000-0000-000000000001'
  ),
  'production'::public.attestation_environment,
  'a production coverage batch snapshots production provenance'
);

select is(
  (
    select attestation_environment
    from public.personal_sync_coverage_batches
    where id = 'fa200000-0000-0000-0000-000000000002'
  ),
  'development'::public.attestation_environment,
  'a development coverage batch snapshots development provenance'
);

select is(
  (
    select attestation_environment is null
    from public.personal_sync_coverage_batches
    where id = 'fa200000-0000-0000-0000-000000000003'
  ),
  true,
  'coverage with a missing historical key retains unknown provenance'
);

insert into public.personal_trusted_diagnostics (
  id,
  user_id,
  client_diagnostic_id,
  key_id,
  sign_count,
  payload_digest,
  observed_at,
  query_started_at,
  query_ended_at,
  trusted_device_sample_count
)
values
  (
    'fa300000-0000-0000-0000-000000000001',
    'fa111111-1111-1111-1111-111111111111',
    'fa300000-0000-0000-0000-000000000001',
    (select production_key_id from t_keys),
    1,
    extensions.digest('production diagnostic', 'sha256'),
    clock_timestamp(),
    clock_timestamp() - interval '2 minutes',
    clock_timestamp() - interval '1 minute',
    1
  ),
  (
    'fa300000-0000-0000-0000-000000000002',
    'fa111111-1111-1111-1111-111111111111',
    'fa300000-0000-0000-0000-000000000002',
    (select development_key_id from t_keys),
    1,
    extensions.digest('development diagnostic', 'sha256'),
    clock_timestamp(),
    clock_timestamp() - interval '2 minutes',
    clock_timestamp() - interval '1 minute',
    1
  ),
  (
    'fa300000-0000-0000-0000-000000000003',
    'fa111111-1111-1111-1111-111111111111',
    'fa300000-0000-0000-0000-000000000003',
    (select unknown_key_id from t_keys),
    1,
    extensions.digest('unknown diagnostic', 'sha256'),
    clock_timestamp(),
    clock_timestamp() - interval '2 minutes',
    clock_timestamp() - interval '1 minute',
    1
  );

select is(
  (
    select attestation_environment
    from public.personal_trusted_diagnostics
    where id = 'fa300000-0000-0000-0000-000000000001'
  ),
  'production'::public.attestation_environment,
  'a production diagnostic snapshots production provenance'
);

select is(
  (
    select attestation_environment
    from public.personal_trusted_diagnostics
    where id = 'fa300000-0000-0000-0000-000000000002'
  ),
  'development'::public.attestation_environment,
  'a development diagnostic snapshots development provenance'
);

select is(
  (
    select attestation_environment is null
    from public.personal_trusted_diagnostics
    where id = 'fa300000-0000-0000-0000-000000000003'
  ),
  true,
  'a diagnostic with a missing historical key retains unknown provenance'
);

select is(
  (
    select replayed
    from public.record_metric_batch(
      'fa111111-1111-1111-1111-111111111111',
      'fa000000-0000-0000-0000-000000000002',
      'fa100000-0000-0000-0000-000000000002',
      extensions.digest('development metric', 'sha256'),
      '2026-07-02T01:00:00Z',
      '[{}]'::jsonb,
      (select development_key_id from t_keys),
      1
    )
  ),
  true,
  'an exact metric retry with the original key remains idempotent'
);

select throws_ok(
  $$ select * from public.record_metric_batch(
       'fa111111-1111-1111-1111-111111111111',
       'fa000000-0000-0000-0000-000000000002',
       'fa100000-0000-0000-0000-000000000002',
       extensions.digest('development metric', 'sha256'),
       '2026-07-02T01:00:00Z',
       '[{}]'::jsonb,
       (select production_key_id from t_keys),
       1
     ) $$,
  '23505',
  null,
  'a production key cannot adopt a development metric retry'
);

select is(
  (
    select replayed
    from public.record_personal_sync_coverage_v1(
      'fa111111-1111-1111-1111-111111111111',
      'fa000000-0000-0000-0000-000000000004',
      'fa200000-0000-0000-0000-000000000002',
      extensions.digest('development coverage', 'sha256'),
      '2026-07-02T01:00:00Z',
      '[]'::jsonb,
      (select development_key_id from t_keys),
      1
    )
  ),
  true,
  'an exact coverage retry with the original key remains idempotent'
);

select throws_ok(
  $$ select * from public.record_personal_sync_coverage_v1(
       'fa111111-1111-1111-1111-111111111111',
       'fa000000-0000-0000-0000-000000000004',
       'fa200000-0000-0000-0000-000000000002',
       extensions.digest('development coverage', 'sha256'),
       '2026-07-02T01:00:00Z',
       '[]'::jsonb,
       (select production_key_id from t_keys),
       1
     ) $$,
  '23505',
  null,
  'a production key cannot adopt a development coverage retry'
);

select is(
  (
    select replayed
    from public.record_trusted_personal_diagnostic_v1(
      'fa111111-1111-1111-1111-111111111111',
      'fa300000-0000-0000-0000-000000000002',
      extensions.digest('development diagnostic', 'sha256'),
      clock_timestamp(),
      clock_timestamp() - interval '2 minutes',
      clock_timestamp() - interval '1 minute',
      1,
      (select development_key_id from t_keys),
      1
    )
  ),
  true,
  'an exact diagnostic retry with the original key remains idempotent'
);

select throws_ok(
  $$ select * from public.record_trusted_personal_diagnostic_v1(
       'fa111111-1111-1111-1111-111111111111',
       'fa300000-0000-0000-0000-000000000002',
       extensions.digest('development diagnostic', 'sha256'),
       clock_timestamp(),
       clock_timestamp() - interval '2 minutes',
       clock_timestamp() - interval '1 minute',
       1,
       (select production_key_id from t_keys),
       1
     ) $$,
  '23505',
  null,
  'a production key cannot adopt a development diagnostic retry'
);

select is(
  (
    select sign_count
    from public.device_attestations
    where key_id = (select production_key_id from t_keys)
  ),
  0::bigint,
  'rejected cross-key retries do not consume the production assertion counter'
);

create function pg_temp.insert_complete_assessment(
  p_challenge_id uuid,
  p_request_id uuid,
  p_evidence_state public.personal_evidence_state default 'complete'
)
returns void
language sql
set search_path = ''
as $$
  insert into app.personal_evidence_assessments (
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
    outage_reference
  )
  values (
    p_challenge_id,
    'fa111111-1111-1111-1111-111111111111',
    p_request_id,
    p_evidence_state,
    '2026-07-09T00:00:00Z',
    'personal-v1',
    extensions.digest(p_request_id::text, 'sha256'),
    1,
    1,
    100,
    '[0, 0, 0, 0, 0, 0, 0]'::jsonb,
    case
      when p_evidence_state = 'gametime_outage'
        then 'provenance-test-outage'
      else null
    end
  );
$$;

select throws_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000002',
       'fa400000-0000-0000-0000-000000000002'
     ) $$,
  '23001',
  'complete personal evidence requires production-origin metric batches',
  'development-origin metric evidence cannot enter a complete assessment'
);

select throws_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000003',
       'fa400000-0000-0000-0000-000000000003'
     ) $$,
  '23001',
  'complete personal evidence requires production-origin metric batches',
  'unknown-origin metric evidence cannot enter a complete assessment'
);

select throws_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000004',
       'fa400000-0000-0000-0000-000000000004'
     ) $$,
  '23001',
  'complete personal evidence requires production-origin coverage batches',
  'development-origin coverage cannot enter a complete assessment'
);

select throws_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000005',
       'fa400000-0000-0000-0000-000000000005'
     ) $$,
  '23001',
  'complete personal evidence requires production-origin coverage batches',
  'unknown-origin coverage cannot enter a complete assessment'
);

-- D81 prunes the raw snapshots but deliberately retains the batch audit row.
-- Settlement must continue to fail closed from that durable provenance.
alter table public.metric_snapshots
  disable trigger metric_snapshots_guard_delete;

delete from public.metric_snapshots
where batch_id = 'fa100000-0000-0000-0000-000000000002';

alter table public.metric_snapshots
  enable trigger metric_snapshots_guard_delete;

alter table app.personal_evidence_assessments
  disable trigger personal_assessments_require_production_evidence;

select pg_temp.insert_complete_assessment(
  'fa000000-0000-0000-0000-000000000002',
  'fa400000-0000-0000-0000-000000000007'
);

alter table app.personal_evidence_assessments
  enable trigger personal_assessments_require_production_evidence;

select throws_ok(
  $$ select public.record_personal_assessment_v1(
       'fa000000-0000-0000-0000-000000000002',
       'fa400000-0000-0000-0000-000000000007',
       'complete',
       'personal-v1',
       extensions.digest(
         'fa400000-0000-0000-0000-000000000007',
         'sha256'
       ),
       null
     ) $$,
  '23001',
  'complete personal evidence requires production-origin metric batches',
  'an exact legacy assessment retry cannot bypass the provenance guard'
);

select throws_ok(
  $$ insert into public.personal_challenge_results (
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
     select
       'fa500000-0000-0000-0000-000000000002',
       assessment.challenge_id,
       assessment.user_id,
       assessment.id,
       'missed_goal',
       'target_missed',
       'complete',
       assessment.evidence_cutoff,
       assessment.total_steps,
       assessment.daily_totals,
       false,
       assessment.evidence_cutoff + interval '1 hour'
     from app.personal_evidence_assessments assessment
     where assessment.challenge_id =
       'fa000000-0000-0000-0000-000000000002' $$,
  '23001',
  'complete personal evidence requires production-origin metric batches',
  'a legacy development assessment cannot be published as a result'
);

select lives_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000001',
       'fa400000-0000-0000-0000-000000000001'
     ) $$,
  'production-only evidence may enter a complete assessment'
);

select lives_ok(
  $$ select pg_temp.insert_complete_assessment(
       'fa000000-0000-0000-0000-000000000006',
       'fa400000-0000-0000-0000-000000000006',
       'gametime_outage'
     ) $$,
  'non-complete fail-closed assessments remain available'
);

select pg_temp.insert_complete_assessment(
  'fa000000-0000-0000-0000-000000000007',
  'fa400000-0000-0000-0000-000000000008',
  'gametime_outage'
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
select
  'fa500000-0000-0000-0000-000000000007',
  assessment.challenge_id,
  assessment.user_id,
  assessment.id,
  'inconclusive',
  'gametime_outage',
  assessment.evidence_state,
  assessment.evidence_cutoff,
  assessment.total_steps,
  assessment.daily_totals,
  true,
  assessment.evidence_cutoff + interval '1 hour'
from app.personal_evidence_assessments assessment
where assessment.challenge_id =
  'fa000000-0000-0000-0000-000000000007';

insert into public.personal_eligibility_holds (
  id,
  user_id,
  challenge_id,
  result_id,
  reason,
  placed_at
)
values (
  'fa600000-0000-0000-0000-000000000007',
  'fa111111-1111-1111-1111-111111111111',
  'fa000000-0000-0000-0000-000000000007',
  'fa500000-0000-0000-0000-000000000007',
  'user_device_sync_failure',
  clock_timestamp() - interval '5 minutes'
);

grant select on t_keys to service_role;

set local role service_role;

select throws_ok(
  $$ select * from public.record_trusted_personal_diagnostic_v1(
       'fa111111-1111-1111-1111-111111111111',
       'fa300000-0000-0000-0000-000000000004',
       extensions.digest('development hold clearance', 'sha256'),
       clock_timestamp(),
       clock_timestamp() - interval '2 minutes',
       clock_timestamp() - interval '1 minute',
       1,
       (select development_key_id from t_keys),
       1
     ) $$,
  '23001',
  'only a production-origin trusted diagnostic may clear Personal eligibility',
  'a development diagnostic cannot clear a Personal eligibility hold'
);

reset role;

select ok(
  (
    select cleared_at is null
    from public.personal_eligibility_holds
    where id = 'fa600000-0000-0000-0000-000000000007'
  )
  and not exists (
    select 1
    from public.personal_trusted_diagnostics
    where client_diagnostic_id =
      'fa300000-0000-0000-0000-000000000004'
  )
  and (
    select sign_count = 0
    from public.device_attestations
    where key_id = (select development_key_id from t_keys)
  ),
  'a rejected development clearance rolls back its diagnostic and assertion counter'
);

set local role service_role;

select is(
  (
    select cleared_hold
    from public.record_trusted_personal_diagnostic_v1(
      'fa111111-1111-1111-1111-111111111111',
      'fa300000-0000-0000-0000-000000000005',
      extensions.digest('production hold clearance', 'sha256'),
      clock_timestamp(),
      clock_timestamp() - interval '2 minutes',
      clock_timestamp() - interval '1 minute',
      1,
      (select production_key_id from t_keys),
      1
    )
  ),
  true,
  'a production diagnostic may clear a Personal eligibility hold'
);

reset role;

select ok(
  (
    select hold.cleared_at is not null
       and diagnostic.attestation_environment = 'production'
    from public.personal_eligibility_holds hold
    join public.personal_trusted_diagnostics diagnostic
      on diagnostic.id = hold.cleared_by_diagnostic_id
    where hold.id = 'fa600000-0000-0000-0000-000000000007'
  ),
  'the cleared hold retains durable production diagnostic provenance'
);

set local role service_role;

select is(
  has_function_privilege(
    'service_role',
    'app.record_personal_sync_coverage_v1_unchecked(uuid,uuid,uuid,bytea,timestamptz,jsonb,bytea,bigint)',
    'EXECUTE'
  ),
  false,
  'service_role cannot bypass the public coverage retry guard'
);

select is(
  has_function_privilege(
    'service_role',
    'app.record_trusted_personal_diagnostic_v1_unchecked(uuid,uuid,bytea,timestamptz,timestamptz,timestamptz,integer,bytea,bigint)',
    'EXECUTE'
  ),
  false,
  'service_role cannot bypass the public diagnostic retry guard'
);

select is(
  has_function_privilege(
    'service_role',
    'app.record_personal_assessment_v1_unchecked(uuid,uuid,public.personal_evidence_state,text,bytea,text)',
    'EXECUTE'
  ),
  false,
  'service_role cannot bypass the public assessment retry guard'
);

select is(
  has_function_privilege(
    'service_role',
    'app.assert_production_personal_evidence_v1(uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'service_role cannot call the private provenance assertion directly'
);

reset role;

select * from finish();
rollback;
