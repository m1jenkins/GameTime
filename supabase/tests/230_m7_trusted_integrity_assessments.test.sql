-- M7: the trusted loader reads every authoritative sidecar after grace, and
-- the service-only recorder atomically materializes required quarantines
-- before one immutable versioned assessment can enable final publication.

begin;
select plan(62);

-- ---------------------------------------------------------------------------
-- Shape, privilege, and append-only boundaries
-- ---------------------------------------------------------------------------

select has_table(
  'app',
  'contest_integrity_assessments',
  'complete integrity assessments persist outside the exposed API schema'
);

select has_column(
  'public',
  'contest_results',
  'integrity_assessment_id',
  'every new result can bind to its exact completed assessment'
);

select has_function(
  'public',
  'load_contest_integrity_input_v1',
  array['uuid'],
  'M7 exposes one service-only complete trusted loader'
);

select has_function(
  'public',
  'record_contest_integrity_assessment_v1',
  array[
    'uuid',
    'timestamp with time zone',
    'text',
    'text',
    'bytea',
    'bytea',
    'jsonb',
    'jsonb'
  ],
  'M7 exposes one service-only atomic assessment recorder'
);

select ok(
  (select bool_and(routine.prosecdef)
   from pg_proc routine
   where routine.oid in (
     'public.load_contest_integrity_input_v1(uuid)'::regprocedure,
     'public.record_contest_integrity_assessment_v1(uuid,timestamptz,text,text,bytea,bytea,jsonb,jsonb)'::regprocedure
   )),
  'trusted loader and recorder intentionally cross private RLS boundaries'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.load_contest_integrity_input_v1(uuid)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.record_contest_integrity_assessment_v1(uuid,timestamptz,text,text,bytea,bytea,jsonb,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.load_contest_integrity_input_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.load_contest_integrity_input_v1(uuid)',
    'execute'
  ),
  'only service_role can load or record complete integrity evidence'
);

select ok(
  not has_table_privilege(
    'service_role',
    'app.contest_integrity_assessments',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'app.contest_integrity_assessments',
    'insert'
  )
  and not has_table_privilege(
    'authenticated',
    'app.contest_integrity_assessments',
    'select'
  ),
  'even service_role must use the narrow recorder rather than the private table'
);

select ok(
  (select relrowsecurity
   from pg_class
   where oid = 'app.contest_integrity_assessments'::regclass),
  'the private assessment ledger also has RLS enabled as defense in depth'
);

select is(
  (select count(*)
   from pg_trigger
   where tgrelid = 'app.contest_integrity_assessments'::regclass
     and tgname = 'contest_integrity_assessments_forbid_mutation'
     and not tgisinternal),
  1::bigint,
  'assessment facts have an append-only mutation trigger'
);

select is(
  (select count(*)
   from pg_constraint
   where conrelid = 'public.contest_results'::regclass
     and conname = 'contest_results_integrity_assessment_fkey'
     and contype = 'f'),
  1::bigint,
  'results reference an assessment from the same contest'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.contest_results'::regclass
      and tgname = 'contest_results_bind_integrity_assessment'
      and not tgisinternal
  )
  and exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.contest_standing_entries'::regclass
      and tgname =
        'contest_standing_entries_assert_integrity_assessment'
      and not tgisinternal
  ),
  'both result identity and every final standing are assessment-gated'
);

-- ---------------------------------------------------------------------------
-- Four contests: all inputs, genuinely clean, pre-grace, and unauthorized
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('a7111111-1111-1111-1111-111111111111'),
  ('a7222222-2222-2222-2222-222222222222'),
  ('a7333333-3333-3333-3333-333333333333');

insert into public.profiles (id, handle, display_name) values
  (
    'a7111111-1111-1111-1111-111111111111',
    'm7trustedalice',
    'M7 Alice'
  ),
  (
    'a7222222-2222-2222-2222-222222222222',
    'm7trustedbob',
    'M7 Bob'
  ),
  (
    'a7333333-3333-3333-3333-333333333333',
    'm7staletoken',
    'M7 Deleted'
  );

insert into public.charities (id, name, ein, slug) values (
  'a7c00001-0000-0000-0000-000000000001',
  'M7 Evidence Fund',
  '97-0000001',
  'm7-evidence-fund'
);

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id,
  title,
  created_by,
  metric,
  cadence,
  target_value,
  stake_amount_cents,
  tie_break,
  starts_at,
  ends_at,
  max_participants
) values
  (
    'a7000001-0000-0000-0000-000000000001',
    'M7 every evidence input',
    'a7111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    100,
    'integrity_score',
    date_trunc('hour', now()) - interval '10 days',
    date_trunc('hour', now()) - interval '7 hours',
    2
  ),
  (
    'a7000002-0000-0000-0000-000000000002',
    'M7 genuinely clean',
    'a7111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    100,
    'void',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '7 hours',
    2
  ),
  (
    'a7000003-0000-0000-0000-000000000003',
    'M7 still in grace',
    'a7111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    100,
    'void',
    date_trunc('hour', now()) - interval '1 day',
    date_trunc('hour', now()) - interval '1 hour',
    2
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  timezone,
  charity_id
)
select
  contest.id,
  'a7111111-1111-1111-1111-111111111111',
  'accepted',
  'UTC',
  'a7c00001-0000-0000-0000-000000000001'::uuid
from public.contests contest
where contest.id in (
  'a7000001-0000-0000-0000-000000000001',
  'a7000002-0000-0000-0000-000000000002',
  'a7000003-0000-0000-0000-000000000003'
)
order by contest.id;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by
)
select
  contest.id,
  'a7222222-2222-2222-2222-222222222222',
  'invited',
  'a7111111-1111-1111-1111-111111111111'
from public.contests contest
where contest.id in (
  'a7000001-0000-0000-0000-000000000001',
  'a7000002-0000-0000-0000-000000000002',
  'a7000003-0000-0000-0000-000000000003'
)
order by contest.id;

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = 'a7c00001-0000-0000-0000-000000000001'
where user_id = 'a7222222-2222-2222-2222-222222222222'
  and contest_id in (
    'a7000001-0000-0000-0000-000000000001',
    'a7000002-0000-0000-0000-000000000002',
    'a7000003-0000-0000-0000-000000000003'
  );

insert into public.contest_geofences (
  id,
  contest_id,
  name,
  center_latitude,
  center_longitude,
  radius_meters,
  max_accuracy_meters,
  minimum_dwell_seconds,
  maximum_sample_gap_seconds,
  minimum_workout_overlap_seconds
) values (
  'a7f00001-0000-0000-0000-000000000001',
  'a7000001-0000-0000-0000-000000000001',
  'M7 Trusted Gym',
  41.8781,
  -87.6298,
  200,
  20,
  60,
  60,
  30
);

update public.contests
set status = 'active',
    activated_at = clock_timestamp()
where id in (
  'a7000001-0000-0000-0000-000000000001',
  'a7000002-0000-0000-0000-000000000002',
  'a7000003-0000-0000-0000-000000000003'
);

-- One historical timezone epoch, strictly inside the contest window.
insert into public.timezone_change_requests (
  id,
  contest_id,
  user_id,
  from_timezone,
  to_timezone,
  requested_at,
  required_reviewer_count
) values (
  'a7e00001-0000-0000-0000-000000000001',
  'a7000001-0000-0000-0000-000000000001',
  'a7222222-2222-2222-2222-222222222222',
  'UTC',
  'America/Chicago',
  date_trunc('hour', now()) - interval '3 days',
  1
);

insert into public.timezone_change_applied_events (
  id,
  request_id,
  contest_id,
  user_id,
  from_timezone,
  to_timezone,
  effective_at
) values (
  'a7e10001-0000-0000-0000-000000000001',
  'a7e00001-0000-0000-0000-000000000001',
  'a7000001-0000-0000-0000-000000000001',
  'a7222222-2222-2222-2222-222222222222',
  'UTC',
  'America/Chicago',
  date_trunc('hour', now()) - interval '2 days'
);

create temporary table t_m7_fixture as
select
  'a7b00001-0000-0000-0000-000000000001'::uuid as batch_id,
  'a7d00001-0000-0000-0000-000000000001'::uuid as snapshot_id,
  date_trunc('hour', now()) - interval '5 days' as bucket_start,
  ('\x04' || repeat('71', 64))::bytea as public_key;

alter table t_m7_fixture add column key_id bytea;
update t_m7_fixture
set key_id = extensions.digest(public_key, 'sha256');

insert into public.device_attestations (
  key_id,
  user_id,
  public_key,
  environment
) select
  key_id,
  'a7111111-1111-1111-1111-111111111111',
  public_key,
  'production'
from t_m7_fixture;

insert into public.ingest_batches (
  id,
  contest_id,
  user_id,
  client_batch_id,
  attested,
  payload_digest,
  observation_count,
  observed_at,
  recorded_at
) values (
  (select batch_id from t_m7_fixture),
  'a7000001-0000-0000-0000-000000000001',
  'a7111111-1111-1111-1111-111111111111',
  'a7b10001-0000-0000-0000-000000000001',
  false,
  extensions.digest('m7 late batch', 'sha256'),
  1,
  date_trunc('hour', now()) - interval '8 hours',
  date_trunc('hour', now()) - interval '8 hours'
);

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  id,
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
  observed_at,
  recorded_at
) select
  snapshot_id,
  batch_id,
  'a7000001-0000-0000-0000-000000000001',
  'a7111111-1111-1111-1111-111111111111',
  'steps',
  bucket_start,
  (bucket_start at time zone 'UTC')::date,
  extract(hour from bucket_start at time zone 'UTC')::smallint,
  12000,
  'third_party',
  12,
  'com.example.unreviewed',
  date_trunc('hour', now()) - interval '8 hours',
  date_trunc('hour', now()) - interval '8 hours'
from t_m7_fixture;

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

-- The historical version proves quarantine state is a real loaded input. The
-- current m6-v1 quarantine remains absent until the new recorder runs.
select public.record_evidence_quarantine(
  (select snapshot_id from t_m7_fixture),
  'm5-v3',
  'historical:' || (select bucket_start::text from t_m7_fixture),
  (3 * 86400000)::bigint,
  '{"historical":true}'::jsonb
);

alter table public.geofence_checkins
  disable trigger geofence_checkins_assert_window_open;

insert into public.geofence_checkins (
  id,
  contest_id,
  geofence_id,
  user_id,
  client_checkin_id,
  key_id,
  sign_count,
  attested,
  payload_digest,
  started_at,
  ended_at,
  workout_id,
  workout_started_at,
  workout_ended_at,
  workout_activity_type,
  workout_source_bundle_id,
  workout_provenance,
  location_count,
  inside_location_count,
  dwell_seconds,
  workout_overlap_seconds,
  outcome,
  rule_version,
  recorded_at
) select
  'a7a00001-0000-0000-0000-000000000001',
  'a7000001-0000-0000-0000-000000000001',
  'a7f00001-0000-0000-0000-000000000001',
  'a7111111-1111-1111-1111-111111111111',
  'a7a10001-0000-0000-0000-000000000001',
  key_id,
  1,
  true,
  extensions.digest('m7 trusted checkin', 'sha256'),
  date_trunc('hour', now()) - interval '2 days',
  date_trunc('hour', now()) - interval '2 days' + interval '2 minutes',
  'a7a20001-0000-0000-0000-000000000001',
  date_trunc('hour', now()) - interval '2 days',
  date_trunc('hour', now()) - interval '2 days' + interval '30 minutes',
  'running',
  'com.apple.health',
  'device',
  2,
  2,
  120,
  120,
  'accepted',
  'm6-v1',
  date_trunc('hour', now()) - interval '1 day'
from t_m7_fixture;

alter table public.geofence_checkins
  enable trigger geofence_checkins_assert_window_open;

insert into public.geofence_location_observations (
  id,
  checkin_id,
  contest_id,
  user_id,
  sample_index,
  observed_at,
  latitude,
  longitude,
  accuracy_meters,
  is_simulated,
  is_produced_by_accessory,
  distance_meters,
  outcome
) values
  (
    'a7a30001-0000-0000-0000-000000000001',
    'a7a00001-0000-0000-0000-000000000001',
    'a7000001-0000-0000-0000-000000000001',
    'a7111111-1111-1111-1111-111111111111',
    1,
    date_trunc('hour', now()) - interval '2 days',
    41.8781,
    -87.6298,
    5,
    false,
    false,
    0,
    'inside'
  ),
  (
    'a7a30002-0000-0000-0000-000000000002',
    'a7a00001-0000-0000-0000-000000000001',
    'a7000001-0000-0000-0000-000000000001',
    'a7111111-1111-1111-1111-111111111111',
    2,
    date_trunc('hour', now()) - interval '2 days' + interval '2 minutes',
    41.8781,
    -87.6298,
    5,
    false,
    false,
    0,
    'inside'
  );

-- This profile is gone while a previously issued JWT may still name it.
do $$
begin
  perform public.delete_account(
    'a7333333-3333-3333-3333-333333333333'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grace is a hard prerequisite for both load and record
-- ---------------------------------------------------------------------------

set local role service_role;

select throws_ok(
  $$ select public.load_contest_integrity_input_v1(
       'a7000003-0000-0000-0000-000000000003'
     ) $$,
  '23001',
  null,
  'the trusted loader refuses to snapshot evidence before grace closes'
);

select throws_ok(
  $$ select public.record_contest_integrity_assessment_v1(
       'a7000003-0000-0000-0000-000000000003',
       date_trunc('hour', now()) + interval '5 hours',
       'm4-v1',
       'm6-v1',
       decode(repeat('00', 32), 'hex'),
       decode(repeat('11', 32), 'hex'),
       '{}'::jsonb,
       '[]'::jsonb
     ) $$,
  '23001',
  null,
  'the recorder also refuses to enable assessment before grace closes'
);

reset role;

select is(
  (select count(*)
   from app.contest_integrity_assessments
   where contest_id = 'a7000003-0000-0000-0000-000000000003'),
  0::bigint,
  'a pre-grace attempt persists no partial assessment'
);

-- ---------------------------------------------------------------------------
-- The trusted load includes all six inputs and an exact quarantine candidate
-- ---------------------------------------------------------------------------

create temporary table t_full_load as
select public.load_contest_integrity_input_v1(
  'a7000001-0000-0000-0000-000000000001'
) as document;

select is(
  (select document ->> 'schemaVersion' from t_full_load),
  'm7-integrity-input-v1',
  'the complete input document is explicitly schema-versioned'
);

select is(
  (select (document ->> 'evidenceCutoff')::timestamptz from t_full_load),
  (
    select ends_at + app.ingest_grace_period()
    from public.contests
    where id = 'a7000001-0000-0000-0000-000000000001'
  ),
  'the evidence cutoff is the one server-owned ingest-grace boundary'
);

select ok(
  (select document -> 'input' ?& array[
     'contest',
     'roster',
     'evidence',
     'timezoneChanges',
     'sourceEvidence',
     'quarantineState',
     'checkIns',
     'locations'
   ]
   from t_full_load),
  'the loader can never omit a required evidence sidecar'
);

select is(
  (select jsonb_array_length(document #> '{input,evidence}')
   from t_full_load),
  1,
  'contest_evidence is loaded'
);

select is(
  (select jsonb_array_length(document #> '{input,sourceEvidence}')
   from t_full_load),
  1,
  'source reputation evidence is loaded'
);

select is(
  (select jsonb_array_length(document #> '{input,timezoneChanges}')
   from t_full_load),
  1,
  'applied timezone events are loaded'
);

select is(
  (select jsonb_array_length(document #> '{input,quarantineState}')
   from t_full_load),
  1,
  'existing quarantine state is loaded before current materialization'
);

select is(
  (select jsonb_array_length(document #> '{input,checkIns}')
   from t_full_load),
  1,
  'check-in integrity outcomes are loaded'
);

select is(
  (select jsonb_array_length(document #> '{input,locations}')
   from t_full_load),
  2,
  'only trusted accepted attested location observations are loaded'
);

select is(
  (select document #>> '{input,sourceEvidence,0,sourceBundleId}'
   from t_full_load),
  'com.example.unreviewed',
  'the in-memory pipeline receives the exact source reputation input'
);

select is(
  (select document #>> '{input,timezoneChanges,0,toTimezone}'
   from t_full_load),
  'America/Chicago',
  'the in-memory pipeline receives the applied timezone epoch'
);

select ok(
  (select
     document #>> '{input,checkIns,0,outcome}' = 'accepted'
     and document #>> '{input,checkIns,0,ruleVersion}' = 'm6-v1'
   from t_full_load),
  'check-in disposition and its validation version stay paired'
);

select ok(
  (select
     (document #>> '{input,locations,0,latitude}')::numeric = 41.8781
     and (document #>> '{input,locations,0,longitude}')::numeric = -87.6298
   from t_full_load),
  'raw trusted coordinates exist only in the ephemeral service load'
);

select ok(
  (select
     jsonb_array_length(document -> 'quarantineCandidates') = 1
     and (
       document #>> '{quarantineCandidates,0,reportingLagMs}'
     )::bigint >= 3 * 86400000
   from t_full_load),
  'the late aggregate maps to one exact snapshot with server-derived lag'
);

select is(
  (select char_length(document ->> 'evidenceDigest') from t_full_load),
  64,
  'the frozen evidence identity is a full SHA-256 digest'
);

select isnt(
  (select document ->> 'evidenceDigest' from t_full_load),
  (select document ->> 'inputDigest' from t_full_load),
  'the full input digest separately commits to observed quarantine state'
);

-- ---------------------------------------------------------------------------
-- Active and stale authenticated JWTs are equally unauthorized
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a7111111-1111-1111-1111-111111111111"}',
  true
);

select throws_ok(
  $$ select public.load_contest_integrity_input_v1(
       'a7000001-0000-0000-0000-000000000001'
     ) $$,
  '42501',
  null,
  'an active participant JWT cannot invoke the trusted loader'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a7333333-3333-3333-3333-333333333333"}',
  true
);

select throws_ok(
  $$ select public.load_contest_integrity_input_v1(
       'a7000001-0000-0000-0000-000000000001'
     ) $$,
  '42501',
  null,
  'a stale JWT for a deleted account cannot invoke the trusted loader'
);

select throws_ok(
  $$ select * from app.contest_integrity_assessments $$,
  '42501',
  null,
  'a stale JWT cannot bypass the RPC through the private base table'
);

reset role;
set local role anon;

select throws_ok(
  $$ select public.load_contest_integrity_input_v1(
       'a7000001-0000-0000-0000-000000000001'
     ) $$,
  '42501',
  null,
  'anon cannot invoke the trusted loader'
);

reset role;

-- ---------------------------------------------------------------------------
-- Build privacy-minimized assessment envelopes shaped like TypeScript output
-- ---------------------------------------------------------------------------

create or replace function pg_temp.m7_standings(
  p_alice_total numeric,
  p_bob_total numeric
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'participant_id', 'a7111111-1111-1111-1111-111111111111',
      'display_order', 1,
      'rank', 1,
      'qualified', p_alice_total >= 10000,
      'total', p_alice_total,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at',
        case when p_alice_total >= 10000
          then date_trunc('hour', now()) - interval '2 days'
          else null
        end,
      'integrity_score', 100,
      'integrity_flags', '[]'::jsonb,
      'rationale', jsonb_build_array(jsonb_build_object(
        'code', 'clean_evidence',
        'summary', 'No scored integrity deductions.',
        'points', 0
      ))
    ),
    jsonb_build_object(
      'participant_id', 'a7222222-2222-2222-2222-222222222222',
      'display_order', 2,
      'rank', case when p_alice_total = p_bob_total then 1 else 2 end,
      'qualified', p_bob_total >= 10000,
      'total', p_bob_total,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at',
        case when p_bob_total >= 10000
          then date_trunc('hour', now()) - interval '1 day'
          else null
        end,
      'integrity_score', 100,
      'integrity_flags', '[]'::jsonb,
      'rationale', jsonb_build_array(jsonb_build_object(
        'code', 'clean_evidence',
        'summary', 'No scored integrity deductions.',
        'points', 0
      ))
    )
  );
$$;

create or replace function pg_temp.m7_document(
  p_loaded jsonb,
  p_standings jsonb,
  p_outcome jsonb,
  p_required_count integer
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'schema_version', 'm7-integrity-assessment-v1',
    'contest_id', p_loaded #>> '{input,contest,id}',
    'evidence_cutoff', p_loaded ->> 'evidenceCutoff',
    'scoring_version', 'm4-v1',
    'integrity_configuration_version', 'm6-v1',
    'evidence_digest', p_loaded ->> 'evidenceDigest',
    'input_digest', p_loaded ->> 'inputDigest',
    'input_counts', jsonb_build_object(
      'roster', jsonb_array_length(p_loaded #> '{input,roster}'),
      'contest_evidence',
        jsonb_array_length(p_loaded #> '{input,evidence}'),
      'source_reputation',
        jsonb_array_length(p_loaded #> '{input,sourceEvidence}'),
      'timezone_events',
        jsonb_array_length(p_loaded #> '{input,timezoneChanges}'),
      'quarantine_state',
        jsonb_array_length(p_loaded #> '{input,quarantineState}'),
      'checkin_integrity',
        jsonb_array_length(p_loaded #> '{input,checkIns}'),
      'trusted_locations',
        jsonb_array_length(p_loaded #> '{input,locations}')
    ),
    'quarantine_observation', jsonb_build_object(
      'total', jsonb_array_length(p_loaded #> '{input,quarantineState}'),
      'pending', (
        select count(*)
        from jsonb_array_elements(
          p_loaded #> '{input,quarantineState}'
        ) quarantine
        where quarantine ->> 'state' = 'pending'
      ),
      'approved', (
        select count(*)
        from jsonb_array_elements(
          p_loaded #> '{input,quarantineState}'
        ) quarantine
        where quarantine ->> 'state' = 'approved'
      ),
      'rejected', (
        select count(*)
        from jsonb_array_elements(
          p_loaded #> '{input,quarantineState}'
        ) quarantine
        where quarantine ->> 'state' = 'rejected'
      )
    ),
    'required_quarantine_count', p_required_count,
    'clean_zero_quarantines',
      p_required_count = 0
      and jsonb_array_length(
        p_loaded #> '{input,quarantineState}'
      ) = 0,
    'standings', p_standings,
    'outcome', p_outcome,
    'integrity', (
      select jsonb_agg(jsonb_build_object(
        'participant_id', standing ->> 'participant_id',
        'score', standing -> 'integrity_score',
        'total_penalty', 0,
        'penalties', '{}'::jsonb,
        'flags', '[]'::jsonb
      ) order by (standing ->> 'display_order')::integer)
      from jsonb_array_elements(p_standings) standing
    )
  );
$$;

create temporary table t_full_args as
select
  document,
  pg_temp.m7_standings(12000, 0) as standings,
  jsonb_build_object(
    'kind', 'winner',
    'reason', 'sole_qualifier',
    'participant_id', 'a7111111-1111-1111-1111-111111111111'
  ) as outcome,
  jsonb_build_array(jsonb_build_object(
    'snapshot_id',
      document #>> '{quarantineCandidates,0,snapshotId}',
    'rule_version', 'm6-v1',
    'signal_key',
      'steps:' || (document #>> '{input,evidence,0,bucketStart}'),
    'threshold_ms', 3 * 86400000,
    'details', jsonb_build_object(
      'assessment_schema_version', 'm7-integrity-assessment-v1',
      'reporting_lag_ms',
        (document #>> '{quarantineCandidates,0,reportingLagMs}')::bigint,
      'quarantine_after_ms', 3 * 86400000,
      'evidence_still_scores', true
    )
  )) as required
from t_full_load;

alter table t_full_args add column assessment_document jsonb;
update t_full_args
set assessment_document = pg_temp.m7_document(
  document,
  standings,
  outcome,
  1
);
grant select on t_full_args to service_role;

set local role service_role;

select throws_ok(
  $$ select public.record_contest_integrity_assessment_v1(
       'a7000001-0000-0000-0000-000000000001',
       (select (document ->> 'evidenceCutoff')::timestamptz
        from pg_temp.t_full_args),
       'm4-v1',
       'm6-v1',
       (select decode(document ->> 'evidenceDigest', 'hex')
        from pg_temp.t_full_args),
       (select decode(document ->> 'inputDigest', 'hex')
        from pg_temp.t_full_args),
       (select assessment_document - 'integrity'
        from pg_temp.t_full_args),
       (select required from pg_temp.t_full_args)
     ) $$,
  '22023',
  null,
  'an incomplete assessment document is refused after trusted loading'
);

select is(
  (select count(*)
   from public.evidence_quarantines
   where contest_id = 'a7000001-0000-0000-0000-000000000001'
     and rule_version = 'm6-v1'),
  0::bigint,
  'an incomplete assessment materializes no partial quarantine'
);

select lives_ok(
  $$ select public.record_contest_integrity_assessment_v1(
       'a7000001-0000-0000-0000-000000000001',
       (select (document ->> 'evidenceCutoff')::timestamptz
        from pg_temp.t_full_args),
       'm4-v1',
       'm6-v1',
       (select decode(document ->> 'evidenceDigest', 'hex')
        from pg_temp.t_full_args),
       (select decode(document ->> 'inputDigest', 'hex')
        from pg_temp.t_full_args),
       (select assessment_document from pg_temp.t_full_args),
       (select required from pg_temp.t_full_args)
     ) $$,
  'service_role records the complete assessment atomically'
);

reset role;

create temporary table t_full_id as
select id
from app.contest_integrity_assessments
where contest_id = 'a7000001-0000-0000-0000-000000000001';
grant select on t_full_id to service_role;

select is(
  (select count(*) from t_full_id),
  1::bigint,
  'one immutable assessment exists for the version tuple'
);

select is(
  (select count(*)
   from public.evidence_quarantines
   where contest_id = 'a7000001-0000-0000-0000-000000000001'
     and rule_version = 'm6-v1'),
  1::bigint,
  'the required current-version quarantine was materialized'
);

select is(
  (select count(*)
   from public.evidence_quarantines
   where contest_id = 'a7000001-0000-0000-0000-000000000001'),
  2::bigint,
  'materialization appends without rewriting the historical quarantine'
);

select is(
  (select materialized_quarantine_ids[1]
   from app.contest_integrity_assessments
   where id = (select id from t_full_id)),
  (
    select id
    from public.evidence_quarantines
    where contest_id = 'a7000001-0000-0000-0000-000000000001'
      and rule_version = 'm6-v1'
  ),
  'the assessment names the exact durable quarantine row it completed'
);

select ok(
  (select
     required_quarantine_count = 1
     and cardinality(materialized_quarantine_ids) = 1
   from app.contest_integrity_assessments
   where id = (select id from t_full_id)),
  'required and materialized quarantine counts cannot diverge'
);

select ok(
  (select
     assessment_document::text not like '%com.example.unreviewed%'
     and assessment_document::text not like '%41.8781%'
     and assessment_document::text not like '%-87.6298%'
   from app.contest_integrity_assessments
   where id = (select id from t_full_id)),
  'the durable assessment does not copy raw source ids or coordinates'
);

set local role service_role;

select is(
  public.record_contest_integrity_assessment_v1(
    'a7000001-0000-0000-0000-000000000001',
    (select (document ->> 'evidenceCutoff')::timestamptz
     from pg_temp.t_full_args),
    'm4-v1',
    'm6-v1',
    (select decode(document ->> 'evidenceDigest', 'hex')
     from pg_temp.t_full_args),
    (select decode(document ->> 'inputDigest', 'hex')
     from pg_temp.t_full_args),
    (select assessment_document from pg_temp.t_full_args),
    (select required from pg_temp.t_full_args)
  ),
  (select id from pg_temp.t_full_id),
  'an exact lost-response retry returns the original assessment id'
);

reset role;

select is(
  (select count(*)
   from app.contest_integrity_assessments
   where contest_id = 'a7000001-0000-0000-0000-000000000001'),
  1::bigint,
  'an idempotent retry creates no duplicate assessment'
);

set local role service_role;

select throws_ok(
  $$ select public.record_contest_integrity_assessment_v1(
       'a7000001-0000-0000-0000-000000000001',
       (select (document ->> 'evidenceCutoff')::timestamptz
        from pg_temp.t_full_args),
       'm4-v1',
       'm6-v1',
       decode(repeat('ff', 32), 'hex'),
       (select decode(document ->> 'inputDigest', 'hex')
        from pg_temp.t_full_args),
       (select assessment_document from pg_temp.t_full_args),
       (select required from pg_temp.t_full_args)
     ) $$,
  '23001',
  null,
  'a stale or substituted frozen-evidence digest is refused'
);

reset role;

-- ---------------------------------------------------------------------------
-- Once assessed, late ingest and timezone epochs cannot change the digest
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.metric_snapshots (
       id, batch_id, contest_id, user_id, metric, bucket_start,
       local_day, local_hour, value, provenance, sample_count,
       observed_at, recorded_at
     ) values (
       'a7d00002-0000-0000-0000-000000000002',
       'a7b00001-0000-0000-0000-000000000001',
       'a7000001-0000-0000-0000-000000000001',
       'a7111111-1111-1111-1111-111111111111',
       'distance_meters',
       date_trunc('hour', now()) - interval '5 days',
       (date_trunc('hour', now()) - interval '5 days')::date,
       0,
       1000,
       'device',
       1,
       now(),
       now()
     ) $$,
  '23001',
  null,
  'a post-grace metric ingest cannot race or stale the assessment'
);

select throws_ok(
  $$ insert into public.geofence_checkins (
       id, contest_id, geofence_id, user_id, client_checkin_id,
       attested, payload_digest, started_at, ended_at,
       workout_id, workout_started_at, workout_ended_at,
       workout_activity_type, workout_provenance,
       location_count, inside_location_count, dwell_seconds,
       workout_overlap_seconds, outcome
     ) values (
       'a7a00002-0000-0000-0000-000000000002',
       'a7000001-0000-0000-0000-000000000001',
       'a7f00001-0000-0000-0000-000000000001',
       'a7222222-2222-2222-2222-222222222222',
       'a7a10002-0000-0000-0000-000000000002',
       false,
       extensions.digest('too late', 'sha256'),
       now() - interval '2 days',
       now() - interval '2 days' + interval '2 minutes',
       'a7a20002-0000-0000-0000-000000000002',
       now() - interval '2 days',
       now() - interval '2 days' + interval '30 minutes',
       'running',
       'device',
       2,
       2,
       120,
       120,
       'accepted'
     ) $$,
  '23001',
  null,
  'a post-grace check-in cannot race or stale the assessment'
);

insert into public.timezone_change_requests (
  id,
  contest_id,
  user_id,
  from_timezone,
  to_timezone,
  requested_at,
  required_reviewer_count
) values (
  'a7e00002-0000-0000-0000-000000000002',
  'a7000001-0000-0000-0000-000000000001',
  'a7222222-2222-2222-2222-222222222222',
  'America/Chicago',
  'America/New_York',
  date_trunc('hour', now()) - interval '1 day',
  1
);

select throws_ok(
  $$ insert into public.timezone_change_applied_events (
       id, request_id, contest_id, user_id,
       from_timezone, to_timezone, effective_at
     ) values (
       'a7e10002-0000-0000-0000-000000000002',
       'a7e00002-0000-0000-0000-000000000002',
       'a7000001-0000-0000-0000-000000000001',
       'a7222222-2222-2222-2222-222222222222',
       'America/Chicago',
       'America/New_York',
       date_trunc('hour', now()) - interval '1 day'
     ) $$,
  '23001',
  null,
  'an applied timezone epoch cannot be appended after evidence freezes'
);

select throws_ok(
  $$ update app.contest_integrity_assessments
     set scoring_version = 'changed'
     where id = (select id from t_full_id) $$,
  '23001',
  null,
  'an assessment cannot be rewritten'
);

select throws_ok(
  $$ delete from app.contest_integrity_assessments
     where id = (select id from t_full_id) $$,
  '23001',
  null,
  'an assessment cannot be deleted'
);

-- ---------------------------------------------------------------------------
-- Zero quarantines mean clean only after a complete recorded assessment
-- ---------------------------------------------------------------------------

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       'a7000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm6-v1',
       pg_temp.m7_standings(0, 0),
       jsonb_build_object(
         'kind', 'void',
         'reason', 'no_qualifying_participant'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '23001',
  null,
  'zero quarantine rows alone cannot enable finalization'
);

reset role;

create temporary table t_clean_load as
select public.load_contest_integrity_input_v1(
  'a7000002-0000-0000-0000-000000000002'
) as document;

select ok(
  (select
     document #> '{input,evidence}' = '[]'::jsonb
     and document #> '{input,sourceEvidence}' = '[]'::jsonb
     and document #> '{input,timezoneChanges}' = '[]'::jsonb
     and document #> '{input,quarantineState}' = '[]'::jsonb
     and document #> '{input,checkIns}' = '[]'::jsonb
     and document #> '{input,locations}' = '[]'::jsonb
   from t_clean_load),
  'a genuinely empty sidecar is represented by six explicit arrays'
);

create temporary table t_clean_args as
select
  document,
  pg_temp.m7_standings(0, 0) as standings,
  jsonb_build_object(
    'kind', 'void',
    'reason', 'no_qualifying_participant'
  ) as outcome
from t_clean_load;

alter table t_clean_args add column assessment_document jsonb;
update t_clean_args
set assessment_document = pg_temp.m7_document(
  document,
  standings,
  outcome,
  0
);
grant select on t_clean_args to service_role;

set local role service_role;

select lives_ok(
  $$ select public.record_contest_integrity_assessment_v1(
       'a7000002-0000-0000-0000-000000000002',
       (select (document ->> 'evidenceCutoff')::timestamptz
        from pg_temp.t_clean_args),
       'm4-v1',
       'm6-v1',
       (select decode(document ->> 'evidenceDigest', 'hex')
        from pg_temp.t_clean_args),
       (select decode(document ->> 'inputDigest', 'hex')
        from pg_temp.t_clean_args),
       (select assessment_document from pg_temp.t_clean_args),
       '[]'::jsonb
     ) $$,
  'a complete genuinely clean zero-quarantine assessment records'
);

reset role;

create temporary table t_clean_id as
select id
from app.contest_integrity_assessments
where contest_id = 'a7000002-0000-0000-0000-000000000002';

select is(
  (select required_quarantine_count
   from app.contest_integrity_assessments
   where id = (select id from t_clean_id)),
  0,
  'the clean assessment explicitly requires zero quarantines'
);

select is(
  (select cardinality(materialized_quarantine_ids)
   from app.contest_integrity_assessments
   where id = (select id from t_clean_id)),
  0,
  'the clean assessment explicitly materializes zero quarantines'
);

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       'a7000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm6-v1',
       jsonb_set(
         pg_temp.m7_standings(0, 0),
         '{0,integrity_score}',
         '99'::jsonb
       ),
       jsonb_build_object(
         'kind', 'void',
         'reason', 'no_qualifying_participant'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '22023',
  null,
  'final standings cannot differ from the completed assessment'
);

select lives_ok(
  $$ select public.publish_contest_standings_v1(
       'a7000002-0000-0000-0000-000000000002',
       now(),
       'm4-v1',
       'm6-v1',
       pg_temp.m7_standings(0, 0),
       jsonb_build_object(
         'kind', 'void',
         'reason', 'no_qualifying_participant'
       ),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  'the exact clean completed assessment can enable the existing final boundary'
);

reset role;

select is(
  (select integrity_assessment_id
   from public.contest_results
   where contest_id = 'a7000002-0000-0000-0000-000000000002'),
  (select id from t_clean_id),
  'the immutable result records the exact assessment it used'
);

select is(
  (select status::text
   from public.contests
   where id = 'a7000002-0000-0000-0000-000000000002'),
  'finalized',
  'the existing final publisher changes lifecycle only after the assessment gate'
);

set local role service_role;

select throws_ok(
  $$ select public.publish_contest_standings_v1(
       'a7000001-0000-0000-0000-000000000001',
       now(),
       'm4-v1',
       'm6-v1',
       (select standings from pg_temp.t_full_args),
       (select outcome from pg_temp.t_full_args),
       date_trunc('hour', now()) - interval '1 hour'
     ) $$,
  '23001',
  null,
  'a materialized pending quarantine still requires adjudication'
);

reset role;

select is(
  (select count(*)
   from public.contest_results
   where contest_id = 'a7000001-0000-0000-0000-000000000001'),
  0::bigint,
  'an unresolved review leaves no partial result'
);

select * from finish();
rollback;
