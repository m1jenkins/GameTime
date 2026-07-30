-- M7: trusted evidence loading and complete, immutable integrity assessments.
--
-- Postgres owns the transaction boundary and authoritative reads. The sole
-- TypeScript scoring/integrity pipeline owns interpretation. No scheduled or
-- hosted caller is installed by this migration.

-- ===========================================================================
-- SECTION 1 -- Private append-only assessment facts
-- ===========================================================================

create table app.contest_integrity_assessments (
  id                              uuid primary key default gen_random_uuid(),
  contest_id                      uuid not null
    references public.contests (id) on delete restrict,
  evidence_cutoff                 timestamptz not null,
  scoring_version                 text not null,
  integrity_configuration_version text not null,
  evidence_digest                 bytea not null,
  input_digest                    bytea not null,
  assessment_digest               bytea not null,
  assessment_document             jsonb not null,
  required_quarantine_count       integer not null,
  materialized_quarantine_ids     uuid[] not null default '{}'::uuid[],
  assessed_at                     timestamptz not null default clock_timestamp(),

  constraint contest_integrity_assessments_identity_unique
    unique (id, contest_id),
  constraint contest_integrity_assessments_version_unique
    unique (
      contest_id,
      scoring_version,
      integrity_configuration_version
    ),
  constraint contest_integrity_assessments_versions_bounded
    check (
      char_length(scoring_version) between 1 and 80
      and char_length(integrity_configuration_version) between 1 and 80
    ),
  constraint contest_integrity_assessments_digests_sha256
    check (
      octet_length(evidence_digest) = 32
      and octet_length(input_digest) = 32
      and octet_length(assessment_digest) = 32
    ),
  constraint contest_integrity_assessments_document_object
    check (jsonb_typeof(assessment_document) = 'object'),
  constraint contest_integrity_assessments_quarantines_complete
    check (
      required_quarantine_count >= 0
      and required_quarantine_count =
        cardinality(materialized_quarantine_ids)
    ),
  constraint contest_integrity_assessments_times_finite
    check (
      pg_catalog.isfinite(evidence_cutoff)
      and pg_catalog.isfinite(assessed_at)
      and assessed_at >= evidence_cutoff
    )
);

comment on table app.contest_integrity_assessments is
  'Private immutable M7 assessments over one frozen evidence digest. Raw coordinates and source identifiers are never copied here.';
comment on column app.contest_integrity_assessments.input_digest is
  'Digest of all six loaded sidecars, including the quarantine state observed before materialization.';
comment on column app.contest_integrity_assessments.evidence_digest is
  'Stable digest of frozen scoring evidence and sidecars; excludes mutable quarantine review state.';
comment on column app.contest_integrity_assessments.materialized_quarantine_ids is
  'Exact durable quarantine rows created or confirmed before this assessment became complete.';

alter table app.contest_integrity_assessments enable row level security;

create trigger contest_integrity_assessments_forbid_mutation
  before update or delete or truncate
  on app.contest_integrity_assessments
  for each statement execute function app.forbid_mutation();

-- ===========================================================================
-- SECTION 2 -- Canonical authoritative input document
-- ===========================================================================

create function app.build_contest_integrity_input_v1(p_contest_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input                 jsonb;
  v_quarantine_candidates jsonb;
begin
  select jsonb_build_object(
    'contest',
      jsonb_build_object(
        'id', contest.id,
        'metric', contest.metric,
        'cadence', contest.cadence,
        'targetValue', contest.target_value,
        'tieBreak', contest.tie_break,
        'startsAt', contest.starts_at,
        'endsAt', contest.ends_at
      ),
    'roster',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', participant.user_id,
            'status', participant.status,
            'timezone', participant.timezone,
            'charityId', participant.charity_id
          )
          order by participant.user_id
        )
        from public.contest_participants participant
        where participant.contest_id = contest.id
          and participant.status = 'accepted'
      ), '[]'::jsonb),
    'evidence',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', evidence.user_id,
            'metric', evidence.metric,
            'bucketStart', evidence.bucket_start,
            'localDay', evidence.local_day,
            'localHour', evidence.local_hour,
            'value', evidence.value,
            'sampleCount', evidence.sample_count,
            'observationCount', evidence.observation_count,
            'firstRecordedAt', evidence.first_recorded_at,
            'lastRecordedAt', evidence.last_recorded_at
          )
          order by
            evidence.user_id,
            evidence.bucket_start,
            evidence.metric
        )
        from public.contest_evidence evidence
        where evidence.contest_id = contest.id
      ), '[]'::jsonb),
    'timezoneChanges',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', applied.user_id,
            'fromTimezone', applied.from_timezone,
            'toTimezone', applied.to_timezone,
            'effectiveAt', applied.effective_at
          )
          order by applied.user_id, applied.effective_at, applied.id
        )
        from public.timezone_change_applied_events applied
        where applied.contest_id = contest.id
      ), '[]'::jsonb),
    'sourceEvidence',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', source.user_id,
            'metric', source.metric,
            'bucketStart', source.bucket_start,
            'provenance', source.provenance,
            'sourceBundleId', source.source_bundle_id
          )
          order by
            source.user_id,
            source.bucket_start,
            source.metric,
            source.provenance,
            source.source_bundle_id nulls first
        )
        from public.contest_evidence_sources source
        where source.contest_id = contest.id
      ), '[]'::jsonb),
    'quarantineState',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', quarantine.id,
            'snapshotId', quarantine.snapshot_id,
            'userId', quarantine.user_id,
            'metric', quarantine.metric,
            'bucketStart', quarantine.bucket_start,
            'ruleVersion', quarantine.rule_version,
            'signalKey', quarantine.signal_key,
            'thresholdMs', quarantine.threshold_ms,
            'reportingLagMs', quarantine.reporting_lag_ms,
            'reviewerCount', quarantine.reviewer_count,
            'approvalsRequired', quarantine.approvals_required,
            'approvalCount', quarantine.approval_count,
            'rejectionCount', quarantine.rejection_count,
            'state', quarantine.state
          )
          order by quarantine.id
        )
        from public.evidence_quarantine_status quarantine
        where quarantine.contest_id = contest.id
      ), '[]'::jsonb),
    'checkIns',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', checkin.user_id,
            'checkInId', checkin.checkin_id,
            'geofenceId', checkin.geofence_id,
            'startedAt', checkin.started_at,
            'endedAt', checkin.ended_at,
            'outcome', checkin.outcome,
            'dwellSeconds', checkin.dwell_seconds,
            'workoutOverlapSeconds', checkin.workout_overlap_seconds,
            'attested', checkin.attested,
            'ruleVersion', checkin.rule_version
          )
          order by checkin.user_id, checkin.started_at, checkin.checkin_id
        )
        from public.contest_checkin_integrity checkin
        where checkin.contest_id = contest.id
      ), '[]'::jsonb),
    'locations',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'userId', observation.user_id,
            'observedAt', observation.observed_at,
            'latitude', observation.latitude,
            'longitude', observation.longitude,
            'accuracyMeters', observation.accuracy_meters
          )
          order by
            observation.user_id,
            observation.observed_at,
            observation.id
        )
        from public.contest_location_observations observation
        where observation.contest_id = contest.id
      ), '[]'::jsonb)
  )
    into v_input
  from public.contests contest
  where contest.id = p_contest_id;

  if v_input is null then
    raise exception 'contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  -- One exact current snapshot backs each aggregate bucket's last-recorded
  -- timestamp. The TypeScript rule decides whether that bucket is late enough;
  -- this mapping lets the recorder materialize the corresponding durable row.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'snapshotId', candidate.id,
      'userId', evidence.user_id,
      'metric', evidence.metric,
      'bucketStart', evidence.bucket_start,
      'recordedAt', candidate.recorded_at,
      'reportingLagMs', greatest(
        0,
        floor(extract(epoch from (
          candidate.recorded_at -
            (evidence.bucket_start + interval '1 hour')
        )) * 1000)::bigint
      )
    )
    order by evidence.user_id, evidence.bucket_start, evidence.metric
  ), '[]'::jsonb)
    into v_quarantine_candidates
  from public.contest_evidence evidence
  cross join lateral (
    select snapshot.id, snapshot.recorded_at
    from public.metric_snapshots snapshot
    where snapshot.contest_id = evidence.contest_id
      and snapshot.user_id = evidence.user_id
      and snapshot.metric = evidence.metric
      and snapshot.bucket_start = evidence.bucket_start
      and snapshot.local_day = evidence.local_day
      and snapshot.local_hour = evidence.local_hour
      and snapshot.is_admissible
      and snapshot.recorded_at = evidence.last_recorded_at
    order by snapshot.id
    limit 1
  ) candidate
  where evidence.contest_id = p_contest_id;

  return jsonb_build_object(
    'input', v_input,
    'quarantineCandidates', v_quarantine_candidates
  );
end;
$$;

comment on function app.build_contest_integrity_input_v1(uuid) is
  'Builds the one canonical M7 input from contest_evidence and all required integrity sidecars.';

create function app.contest_integrity_evidence_digest_v1(p_contest_id uuid)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.digest(
    jsonb_build_object(
      'schemaVersion', 'm7-integrity-input-v1',
      'input',
        (loaded -> 'input') - 'quarantineState',
      'quarantineCandidates', loaded -> 'quarantineCandidates'
    )::text,
    'sha256'
  )
  from (
    select app.build_contest_integrity_input_v1(p_contest_id) as loaded
  ) source;
$$;

comment on function app.contest_integrity_evidence_digest_v1(uuid) is
  'Stable SHA-256 over frozen scoring inputs; mutable quarantine review state is intentionally excluded.';

create function public.load_contest_integrity_input_v1(p_contest_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest        public.contests;
  v_evidence_cutoff timestamptz;
  v_loaded_at      timestamptz;
  v_loaded         jsonb;
  v_core           jsonb;
begin
  if p_contest_id is null then
    raise exception 'contest id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Fixed lock order shared with the recorder. The first two tables match the
  -- existing final publisher, draining any ingest transaction already in
  -- progress before the post-grace snapshot is read.
  lock table public.metric_snapshots,
             public.geofence_checkins,
             public.geofence_location_observations,
             public.timezone_change_applied_events,
             public.contest_participants,
             public.evidence_quarantines,
             public.evidence_quarantine_reviews
    in share row exclusive mode;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = p_contest_id
  for update;

  if v_contest.id is null then
    raise exception 'contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  v_evidence_cutoff := v_contest.ends_at + app.ingest_grace_period();
  v_loaded_at := clock_timestamp();

  if v_contest.status <> 'active' then
    raise exception 'only an active contest may be assessed'
      using errcode = 'restrict_violation';
  end if;

  if v_loaded_at < v_evidence_cutoff then
    raise exception 'contest ingest grace has not closed'
      using errcode = 'restrict_violation';
  end if;

  v_loaded := app.build_contest_integrity_input_v1(p_contest_id);
  v_core := jsonb_build_object(
    'schemaVersion', 'm7-integrity-input-v1',
    'input', (v_loaded -> 'input') - 'quarantineState',
    'quarantineCandidates', v_loaded -> 'quarantineCandidates'
  );

  return jsonb_build_object(
    'schemaVersion', 'm7-integrity-input-v1',
    'evidenceCutoff', v_evidence_cutoff,
    'loadedAt', v_loaded_at,
    'evidenceDigest',
      encode(extensions.digest(v_core::text, 'sha256'), 'hex'),
    'inputDigest',
      encode(extensions.digest(
        jsonb_build_object(
          'schemaVersion', 'm7-integrity-input-v1',
          'input', v_loaded -> 'input',
          'quarantineCandidates', v_loaded -> 'quarantineCandidates'
        )::text,
        'sha256'
      ), 'hex'),
    'input', v_loaded -> 'input',
    'quarantineCandidates', v_loaded -> 'quarantineCandidates'
  );
end;
$$;

comment on function public.load_contest_integrity_input_v1(uuid) is
  'service_role-only complete M7 load. It cannot return before the six-hour ingest grace closes.';

-- ===========================================================================
-- SECTION 3 -- Atomic idempotent assessment and quarantine materialization
-- ===========================================================================

create function public.record_contest_integrity_assessment_v1(
  p_contest_id                       uuid,
  p_evidence_cutoff                  timestamptz,
  p_scoring_version                  text,
  p_integrity_configuration_version  text,
  p_evidence_digest                  bytea,
  p_input_digest                     bytea,
  p_assessment_document              jsonb,
  p_required_quarantines             jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest                    public.contests;
  v_expected_cutoff            timestamptz;
  v_loaded                     jsonb;
  v_current_evidence_digest    bytea;
  v_current_input_digest       bytea;
  v_existing                   app.contest_integrity_assessments;
  v_required_count             integer;
  v_materialized_ids           uuid[] := '{}'::uuid[];
  v_required                   jsonb;
  v_quarantine_id              uuid;
  v_assessment_id              uuid;
  v_accepted_ids               uuid[];
  v_document_ids               uuid[];
begin
  if p_contest_id is null
     or p_evidence_cutoff is null
     or p_scoring_version is null
     or p_integrity_configuration_version is null
     or p_evidence_digest is null
     or p_input_digest is null
     or p_assessment_document is null
     or p_required_quarantines is null
  then
    raise exception 'all integrity assessment fields are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if char_length(p_scoring_version) not between 1 and 80
     or char_length(p_integrity_configuration_version) not between 1 and 80
     or octet_length(p_evidence_digest) <> 32
     or octet_length(p_input_digest) <> 32
  then
    raise exception 'integrity versions or digests are invalid'
      using errcode = 'invalid_parameter_value';
  end if;

  lock table public.metric_snapshots,
             public.geofence_checkins,
             public.geofence_location_observations,
             public.timezone_change_applied_events,
             public.contest_participants,
             public.evidence_quarantines,
             public.evidence_quarantine_reviews
    in share row exclusive mode;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = p_contest_id
  for update;

  if v_contest.id is null then
    raise exception 'contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  v_expected_cutoff := v_contest.ends_at + app.ingest_grace_period();

  if v_contest.status <> 'active' then
    raise exception 'only an active contest may be assessed'
      using errcode = 'restrict_violation';
  end if;

  if clock_timestamp() < v_expected_cutoff then
    raise exception 'contest ingest grace has not closed'
      using errcode = 'restrict_violation';
  end if;

  if not pg_catalog.isfinite(p_evidence_cutoff)
     or p_evidence_cutoff <> v_expected_cutoff
  then
    raise exception 'assessment cutoff must equal the server ingest-grace close'
      using errcode = 'invalid_parameter_value';
  end if;

  v_loaded := app.build_contest_integrity_input_v1(p_contest_id);
  v_current_evidence_digest := extensions.digest(
    jsonb_build_object(
      'schemaVersion', 'm7-integrity-input-v1',
      'input', (v_loaded -> 'input') - 'quarantineState',
      'quarantineCandidates', v_loaded -> 'quarantineCandidates'
    )::text,
    'sha256'
  );

  if v_current_evidence_digest <> p_evidence_digest then
    raise exception 'assessment evidence digest is stale'
      using errcode = 'restrict_violation';
  end if;

  -- The contest row serializes competing assessors. A retry after this
  -- assessment materialized quarantines sees a different full-input digest,
  -- but the same frozen evidence digest and must receive the original id.
  select assessment.*
    into v_existing
  from app.contest_integrity_assessments assessment
  where assessment.contest_id = p_contest_id
    and assessment.scoring_version = p_scoring_version
    and assessment.integrity_configuration_version =
      p_integrity_configuration_version;

  if found then
    if v_existing.evidence_cutoff = p_evidence_cutoff
       and v_existing.evidence_digest = p_evidence_digest
    then
      return v_existing.id;
    end if;

    raise exception 'contest already has a different assessment for these versions'
      using errcode = 'unique_violation';
  end if;

  v_current_input_digest := extensions.digest(
    jsonb_build_object(
      'schemaVersion', 'm7-integrity-input-v1',
      'input', v_loaded -> 'input',
      'quarantineCandidates', v_loaded -> 'quarantineCandidates'
    )::text,
    'sha256'
  );

  if v_current_input_digest <> p_input_digest then
    raise exception 'assessment input digest is stale'
      using errcode = 'restrict_violation';
  end if;

  if jsonb_typeof(p_assessment_document) <> 'object'
     or not (
       p_assessment_document ?& array[
         'schema_version',
         'contest_id',
         'evidence_cutoff',
         'scoring_version',
         'integrity_configuration_version',
         'evidence_digest',
         'input_digest',
         'input_counts',
         'quarantine_observation',
         'required_quarantine_count',
         'clean_zero_quarantines',
         'standings',
         'outcome',
         'integrity'
       ]
     )
     or p_assessment_document - array[
       'schema_version',
       'contest_id',
       'evidence_cutoff',
       'scoring_version',
       'integrity_configuration_version',
       'evidence_digest',
       'input_digest',
       'input_counts',
       'quarantine_observation',
       'required_quarantine_count',
       'clean_zero_quarantines',
       'standings',
       'outcome',
       'integrity'
     ]::text[] <> '{}'::jsonb
  then
    raise exception 'assessment document is incomplete'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_assessment_document ->> 'schema_version' <>
       'm7-integrity-assessment-v1'
     or (p_assessment_document ->> 'contest_id')::uuid <> p_contest_id
     or (p_assessment_document ->> 'evidence_cutoff')::timestamptz <>
       p_evidence_cutoff
     or p_assessment_document ->> 'scoring_version' <> p_scoring_version
     or p_assessment_document ->> 'integrity_configuration_version' <>
       p_integrity_configuration_version
     or p_assessment_document ->> 'evidence_digest' <>
       encode(p_evidence_digest, 'hex')
     or p_assessment_document ->> 'input_digest' <>
       encode(p_input_digest, 'hex')
  then
    raise exception 'assessment document identity does not match its envelope'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_typeof(p_assessment_document -> 'input_counts') <> 'object'
     or not (
       p_assessment_document -> 'input_counts' ?& array[
         'roster',
         'contest_evidence',
         'source_reputation',
         'timezone_events',
         'quarantine_state',
         'checkin_integrity',
         'trusted_locations'
       ]
     )
     or (p_assessment_document -> 'input_counts') - array[
       'roster',
       'contest_evidence',
       'source_reputation',
       'timezone_events',
       'quarantine_state',
       'checkin_integrity',
       'trusted_locations'
     ]::text[] <> '{}'::jsonb
     or exists (
       select 1
       from jsonb_each(p_assessment_document -> 'input_counts') count_entry
       where jsonb_typeof(count_entry.value) <> 'number'
          or (count_entry.value #>> '{}')::numeric < 0
          or trunc((count_entry.value #>> '{}')::numeric) <>
             (count_entry.value #>> '{}')::numeric
     )
  then
    raise exception 'assessment input counts are incomplete or invalid'
      using errcode = 'invalid_parameter_value';
  end if;

  if (p_assessment_document #>> '{input_counts,roster}')::integer <>
       jsonb_array_length(v_loaded #> '{input,roster}')
     or (p_assessment_document #>> '{input_counts,contest_evidence}')::integer <>
       jsonb_array_length(v_loaded #> '{input,evidence}')
     or (p_assessment_document #>> '{input_counts,source_reputation}')::integer <>
       jsonb_array_length(v_loaded #> '{input,sourceEvidence}')
     or (p_assessment_document #>> '{input_counts,timezone_events}')::integer <>
       jsonb_array_length(v_loaded #> '{input,timezoneChanges}')
     or (p_assessment_document #>> '{input_counts,quarantine_state}')::integer <>
       jsonb_array_length(v_loaded #> '{input,quarantineState}')
     or (p_assessment_document #>> '{input_counts,checkin_integrity}')::integer <>
       jsonb_array_length(v_loaded #> '{input,checkIns}')
     or (p_assessment_document #>> '{input_counts,trusted_locations}')::integer <>
       jsonb_array_length(v_loaded #> '{input,locations}')
  then
    raise exception 'assessment input counts do not match the trusted load'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_typeof(p_assessment_document -> 'standings') <> 'array'
     or jsonb_typeof(p_assessment_document -> 'integrity') <> 'array'
     or jsonb_typeof(p_assessment_document -> 'outcome') <> 'object'
     or jsonb_typeof(p_assessment_document -> 'quarantine_observation') <>
       'object'
     or jsonb_typeof(p_required_quarantines) <> 'array'
  then
    raise exception 'assessment collections are incomplete'
      using errcode = 'invalid_parameter_value';
  end if;

  select array_agg(participant.user_id order by participant.user_id)
    into v_accepted_ids
  from public.contest_participants participant
  where participant.contest_id = p_contest_id
    and participant.status = 'accepted';

  select array_agg(
    (entry ->> 'participant_id')::uuid
    order by (entry ->> 'participant_id')::uuid
  )
    into v_document_ids
  from jsonb_array_elements(p_assessment_document -> 'standings') entry;

  if v_accepted_ids is null
     or cardinality(v_accepted_ids) not between 2 and 20
     or v_document_ids is distinct from v_accepted_ids
     or jsonb_array_length(p_assessment_document -> 'integrity') <>
       cardinality(v_accepted_ids)
  then
    raise exception 'assessment must cover the complete accepted roster'
      using errcode = 'invalid_parameter_value';
  end if;

  v_required_count :=
    (p_assessment_document ->> 'required_quarantine_count')::integer;

  if v_required_count < 0
     or v_required_count <> jsonb_array_length(p_required_quarantines)
     or (
       (p_assessment_document ->> 'clean_zero_quarantines')::boolean
       is distinct from (
         v_required_count = 0
         and jsonb_array_length(v_loaded #> '{input,quarantineState}') = 0
       )
     )
  then
    raise exception 'assessment quarantine completeness is inconsistent'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_required_quarantines) required
    where jsonb_typeof(required) <> 'object'
       or not (
         required ?& array[
           'snapshot_id',
           'rule_version',
           'signal_key',
           'threshold_ms',
           'details'
         ]
       )
       or required - array[
         'snapshot_id',
         'rule_version',
         'signal_key',
         'threshold_ms',
         'details'
       ]::text[] <> '{}'::jsonb
       or jsonb_typeof(required -> 'details') <> 'object'
       or char_length(required ->> 'rule_version') not between 1 and 80
       or required ->> 'rule_version' <>
          p_integrity_configuration_version
       or char_length(required ->> 'signal_key') not between 1 and 300
       or (required ->> 'threshold_ms')::bigint <= 0
  ) then
    raise exception 'required quarantine document is invalid'
      using errcode = 'invalid_parameter_value';
  end if;

  if (
    select count(*)
    from jsonb_array_elements(p_required_quarantines)
  ) <> (
    select count(distinct (required ->> 'snapshot_id')::uuid)
    from jsonb_array_elements(p_required_quarantines) required
  ) then
    raise exception 'required quarantines repeat a snapshot'
      using errcode = 'invalid_parameter_value';
  end if;

  for v_required in
    select required
    from jsonb_array_elements(p_required_quarantines) required
    order by required ->> 'snapshot_id'
  loop
    if not exists (
      select 1
      from public.metric_snapshots snapshot
      where snapshot.id = (v_required ->> 'snapshot_id')::uuid
        and snapshot.contest_id = p_contest_id
    ) then
      raise exception 'required quarantine snapshot is not in this contest'
        using errcode = 'invalid_parameter_value';
    end if;

    v_quarantine_id := public.record_evidence_quarantine(
      (v_required ->> 'snapshot_id')::uuid,
      v_required ->> 'rule_version',
      v_required ->> 'signal_key',
      (v_required ->> 'threshold_ms')::bigint,
      v_required -> 'details'
    );
    v_materialized_ids := array_append(
      v_materialized_ids,
      v_quarantine_id
    );
  end loop;

  if cardinality(v_materialized_ids) <> v_required_count
     or exists (
       select 1
       from unnest(v_materialized_ids) materialized_id
       where not exists (
         select 1
         from public.evidence_quarantines quarantine
         where quarantine.id = materialized_id
           and quarantine.contest_id = p_contest_id
       )
     )
  then
    raise exception 'not every required quarantine was materialized'
      using errcode = 'check_violation';
  end if;

  insert into app.contest_integrity_assessments (
    contest_id,
    evidence_cutoff,
    scoring_version,
    integrity_configuration_version,
    evidence_digest,
    input_digest,
    assessment_digest,
    assessment_document,
    required_quarantine_count,
    materialized_quarantine_ids
  )
  values (
    p_contest_id,
    p_evidence_cutoff,
    p_scoring_version,
    p_integrity_configuration_version,
    p_evidence_digest,
    p_input_digest,
    extensions.digest(p_assessment_document::text, 'sha256'),
    p_assessment_document,
    v_required_count,
    v_materialized_ids
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$$;

comment on function public.record_contest_integrity_assessment_v1(
  uuid, timestamptz, text, text, bytea, bytea, jsonb, jsonb
) is
  'service_role-only atomic M7 recorder. Materializes every required quarantine before one complete immutable assessment.';

-- An applied timezone epoch is part of the frozen evidence digest. The normal
-- consent path already refuses changes after contest end; this trigger also
-- protects the invariant from later privileged maintenance.
create function app.assert_integrity_assessment_not_frozen()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from app.contest_integrity_assessments assessment
    where assessment.contest_id = new.contest_id
  ) then
    raise exception 'contest integrity evidence is already frozen'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger timezone_change_applied_events_assert_not_assessed
  before insert on public.timezone_change_applied_events
  for each row execute function app.assert_integrity_assessment_not_frozen();

-- ===========================================================================
-- SECTION 4 -- Final results must use the completed canonical assessment
-- ===========================================================================

alter table public.contest_results
  add column integrity_assessment_id uuid,
  add constraint contest_results_integrity_assessment_fkey
    foreign key (integrity_assessment_id, contest_id)
    references app.contest_integrity_assessments (id, contest_id)
    on delete restrict;

comment on column public.contest_results.integrity_assessment_id is
  'Required for every post-M7 result. NULL is reserved only for a historical pre-migration row.';

create function app.bind_contest_result_integrity_assessment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment app.contest_integrity_assessments;
  v_outcome    jsonb;
begin
  select assessment.*
    into v_assessment
  from app.contest_integrity_assessments assessment
  where assessment.contest_id = new.contest_id
    and assessment.evidence_cutoff = new.evidence_cutoff
    and assessment.scoring_version = new.scoring_version
    and assessment.integrity_configuration_version =
      new.integrity_configuration_version;

  if v_assessment.id is null then
    raise exception 'a complete matching integrity assessment is required'
      using errcode = 'restrict_violation';
  end if;

  if app.contest_integrity_evidence_digest_v1(new.contest_id) <>
       v_assessment.evidence_digest
  then
    raise exception 'integrity assessment evidence is stale'
      using errcode = 'restrict_violation';
  end if;

  v_outcome := v_assessment.assessment_document -> 'outcome';
  if v_outcome ->> 'kind' <> new.kind::text
     or v_outcome ->> 'reason' <> new.reason::text
     or (
       new.kind = 'winner'
       and (v_outcome ->> 'participant_id')::uuid is distinct from
         new.winner_participant_id
     )
     or (
       new.kind <> 'winner'
       and new.winner_participant_id is not null
     )
  then
    raise exception 'final result contradicts the canonical integrity assessment'
      using errcode = 'invalid_parameter_value';
  end if;

  new.integrity_assessment_id := v_assessment.id;
  return new;
end;
$$;

create trigger contest_results_bind_integrity_assessment
  before insert on public.contest_results
  for each row execute function app.bind_contest_result_integrity_assessment();

create function app.assert_final_standings_match_integrity_assessment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_snapshot   record;
  v_expected_count integer;
  v_actual_count   integer;
begin
  for v_snapshot in
    select distinct
      snapshot.id,
      assessment.assessment_document -> 'standings' as expected
    from new_integrity_entries inserted
    join public.contest_standing_snapshots snapshot
      on snapshot.id = inserted.snapshot_id
     and snapshot.contest_id = inserted.contest_id
     and snapshot.phase = 'final'
    join public.contest_results result
      on result.id = snapshot.result_id
     and result.contest_id = snapshot.contest_id
    join app.contest_integrity_assessments assessment
      on assessment.id = result.integrity_assessment_id
     and assessment.contest_id = result.contest_id
  loop
    select count(*)::integer
      into v_actual_count
    from new_integrity_entries inserted
    where inserted.snapshot_id = v_snapshot.id;

    v_expected_count := jsonb_array_length(v_snapshot.expected);

    if v_actual_count <> v_expected_count
       or exists (
         select 1
         from jsonb_to_recordset(v_snapshot.expected) expected (
           participant_id uuid,
           display_order smallint,
           rank smallint,
           qualified boolean,
           total numeric,
           qualifying_days smallint,
           scoreable_days smallint,
           day_rate numeric,
           reached_target_at timestamptz,
           integrity_score numeric,
           integrity_flags jsonb,
           rationale jsonb
         )
         full join new_integrity_entries actual
           on actual.snapshot_id = v_snapshot.id
          and actual.participant_id = expected.participant_id
         where expected.participant_id is null
            or actual.participant_id is null
            or actual.display_order is distinct from expected.display_order
            or actual.rank is distinct from expected.rank
            or actual.qualified is distinct from expected.qualified
            or actual.total is distinct from expected.total
            or actual.qualifying_days is distinct from expected.qualifying_days
            or actual.scoreable_days is distinct from expected.scoreable_days
            or actual.day_rate is distinct from expected.day_rate
            or actual.reached_target_at is distinct from
               expected.reached_target_at
            or actual.integrity_score is distinct from
               expected.integrity_score
            or actual.integrity_flags is distinct from
               expected.integrity_flags
            or actual.rationale is distinct from expected.rationale
       )
    then
      raise exception 'final standings contradict the canonical integrity assessment'
        using errcode = 'invalid_parameter_value';
    end if;
  end loop;

  return null;
end;
$$;

create trigger contest_standing_entries_assert_integrity_assessment
  after insert on public.contest_standing_entries
  referencing new table as new_integrity_entries
  for each statement
  execute function app.assert_final_standings_match_integrity_assessment();

-- ===========================================================================
-- SECTION 5 -- Explicit least privilege
-- ===========================================================================

revoke all on table app.contest_integrity_assessments
  from public, anon, authenticated, service_role;

revoke all on function app.build_contest_integrity_input_v1(uuid),
  app.contest_integrity_evidence_digest_v1(uuid),
  app.assert_integrity_assessment_not_frozen(),
  app.bind_contest_result_integrity_assessment(),
  app.assert_final_standings_match_integrity_assessment()
  from public, anon, authenticated, service_role;

revoke all on function public.load_contest_integrity_input_v1(uuid),
  public.record_contest_integrity_assessment_v1(
    uuid, timestamptz, text, text, bytea, bytea, jsonb, jsonb
  )
  from public, anon, authenticated;

grant execute on function public.load_contest_integrity_input_v1(uuid),
  public.record_contest_integrity_assessment_v1(
    uuid, timestamptz, text, text, bytea, bytea, jsonb, jsonb
  )
  to service_role;
