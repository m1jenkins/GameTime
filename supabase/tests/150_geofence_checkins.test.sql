-- M6: attested geofence attempts are immutable audit facts. The server
-- classifies every raw sample, computes capped adjacent dwell and exact workout
-- overlap in absolute time, and stores failures rather than laundering them
-- into missing evidence.

begin;
select plan(58);

-- Exercise the RPC outside UTC. JSON samples below are also deliberately sent
-- out of order so acceptance proves the server sorts absolute timestamptz
-- instants rather than trusting payload order or deriving a local day.
set local timezone = 'America/Chicago';

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), -- alice, check-in owner
  ('22222222-2222-2222-2222-222222222222'), -- bob, active rival
  ('33333333-3333-3333-3333-333333333333'); -- carol, unrelated

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001',
   'Trail Fund', '12-3456789', 'trail-fund');

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values
  (
    'a0000001-0000-0000-0000-000000000001',
    'Geofence Validation',
    '11111111-1111-1111-1111-111111111111',
    'exercise_minutes', 'cumulative', 60, 2500,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) + interval '2 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    'Stalled After Grace',
    '11111111-1111-1111-1111-111111111111',
    'exercise_minutes', 'cumulative', 60, 2500,
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) - interval '1 day',
    2
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id, user_id, status, invited_by, timezone, charity_id
) values
  (
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'accepted', null, 'UTC',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222',
    'invited', '11111111-1111-1111-1111-111111111111', null, null
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'accepted', null, 'UTC',
    'c0000001-0000-0000-0000-000000000001'
  );

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = 'a0000001-0000-0000-0000-000000000001'
  and user_id = '22222222-2222-2222-2222-222222222222';

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
) values
  (
    'f0000001-0000-0000-0000-000000000001',
    'a0000001-0000-0000-0000-000000000001',
    'Test Gym',
    0, 0, 200, 20, 60, 60, 30
  ),
  (
    'f0000001-0000-0000-0000-000000000002',
    'a0000001-0000-0000-0000-000000000002',
    'Closed Gym',
    0, 0, 200, 20, 60, 60, 30
  );

update public.contests
set status = 'active', activated_at = now()
where id in (
  'a0000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000002'
);

select throws_ok(
  $$ insert into public.contest_geofences (
       id, contest_id, name, center_latitude, center_longitude,
       radius_meters, max_accuracy_meters, minimum_dwell_seconds,
       maximum_sample_gap_seconds, minimum_workout_overlap_seconds
     ) values (
       'f0000001-0000-0000-0000-000000000003',
       'a0000001-0000-0000-0000-000000000001',
       'Late Venue', 0, 0, 200, 20, 60, 60, 30
     ) $$,
  '23001',
  null,
  'the service cannot append new geofence terms after activation'
);

create temporary table t_fixture as
select
  date_trunc('hour', now()) - interval '20 hours' as t0,
  date_trunc('hour', now()) - interval '3 days' as window_start,
  date_trunc('hour', now()) + interval '2 days' as window_end,
  ('\x04' || repeat('a1', 64))::bytea as public_key;

alter table t_fixture add column key_id bytea;
update t_fixture
set key_id = extensions.digest(public_key, 'sha256');

select public.register_device_key(
  '11111111-1111-1111-1111-111111111111',
  (select key_id from t_fixture),
  (select public_key from t_fixture),
  'production'
);

create or replace function pg_temp.samples(
  p_start       timestamptz,
  p_latitude    numeric default 0,
  p_longitude   numeric default 0,
  p_accuracy    numeric default 5,
  p_simulated   boolean default false,
  p_step_seconds integer default 30
)
returns jsonb
language sql
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'observed_at', p_start + make_interval(secs => p_step_seconds * 2),
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy_meters', p_accuracy,
      'is_simulated', p_simulated,
      'is_produced_by_accessory', false
    ),
    jsonb_build_object(
      'observed_at', p_start,
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy_meters', p_accuracy,
      'is_simulated', p_simulated,
      'is_produced_by_accessory', false
    ),
    jsonb_build_object(
      'observed_at', p_start + make_interval(secs => p_step_seconds),
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy_meters', p_accuracy,
      'is_simulated', p_simulated,
      'is_produced_by_accessory', false
    )
  );
$$;

create or replace function pg_temp.submit(
  p_client_id       uuid,
  p_payload         text,
  p_locations       jsonb,
  p_workout_id      uuid,
  p_workout_start   timestamptz,
  p_workout_end     timestamptz,
  p_provenance      public.metric_provenance default 'device',
  p_key_id          bytea default null,
  p_sign_count      bigint default null
)
returns table (
  checkin_id uuid,
  outcome public.geofence_checkin_outcome,
  dwell_seconds numeric,
  workout_overlap_seconds numeric,
  replayed boolean
)
language sql
as $$
  select * from public.record_geofence_checkin(
    '11111111-1111-1111-1111-111111111111',
    'a0000001-0000-0000-0000-000000000001',
    'f0000001-0000-0000-0000-000000000001',
    p_client_id,
    extensions.digest(p_payload, 'sha256'),
    p_locations,
    p_workout_id,
    p_workout_start,
    p_workout_end,
    'running',
    'com.apple.health',
    p_provenance,
    p_key_id,
    p_sign_count
  );
$$;

-- ---------------------------------------------------------------------------
-- Shape, GiST backstops, RLS, and least privilege
-- ---------------------------------------------------------------------------

select has_table(
  'public', 'contest_geofences',
  'contest geofences are durable service-managed definitions'
);
select has_table(
  'public', 'geofence_checkins',
  'check-in attempts have an append-only audit table'
);
select has_table(
  'public', 'geofence_location_observations',
  'raw samples have a separate append-only audit table'
);
select has_view(
  'public', 'contest_checkin_integrity',
  'M6 exposes an integrity sidecar without changing scoring evidence'
);
select has_view(
  'public', 'contest_location_observations',
  'accepted attested inside samples feed M5 location observations'
);
select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.contest_geofences'::regclass,
     'public.geofence_checkins'::regclass,
     'public.geofence_location_observations'::regclass
   )),
  'all three M6 tables have RLS enabled'
);
select is(
  (select count(*)
   from pg_constraint
   where conrelid = 'public.geofence_checkins'::regclass
     and contype = 'x'),
  2::bigint,
  'accepted visit and workout ranges both have exclusion constraints'
);
select ok(
  (select indexdef like 'CREATE UNIQUE INDEX%'
          and indexdef like '%WHERE (outcome = %accepted%'
   from pg_indexes
   where schemaname = 'public'
     and indexname = 'geofence_checkins_accepted_workout_id_idx'),
  'accepted workout UUID reuse has a partial unique-index backstop'
);
select ok(
  (select 'security_invoker=true' = any(reloptions)
   from pg_class
   where oid = 'public.contest_checkin_integrity'::regclass)
  and
  (select 'security_invoker=true' = any(reloptions)
   from pg_class
   where oid = 'public.contest_location_observations'::regclass),
  'both M6 views invoke the base-table RLS policies'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.geofence_checkins', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.geofence_checkins', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.geofence_checkins', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.geofence_checkins', 'delete'
  ),
  'authenticated can read visible check-ins but cannot forge or mutate them'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.contest_geofences', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.contest_geofences', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.contest_geofences', 'delete'
  )
  and has_table_privilege(
    'service_role', 'public.contest_geofences', 'select'
  )
  and has_table_privilege(
    'service_role', 'public.contest_geofences', 'insert'
  )
  and not has_table_privilege(
    'service_role', 'public.contest_geofences', 'update'
  )
  and not has_table_privilege(
    'service_role', 'public.contest_geofences', 'delete'
  ),
  'service_role can create immutable geofences while clients cannot'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_geofence_checkin(uuid,uuid,uuid,uuid,bytea,jsonb,uuid,timestamptz,timestamptz,text,text,public.metric_provenance,bytea,bigint)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.record_geofence_checkin(uuid,uuid,uuid,uuid,bytea,jsonb,uuid,timestamptz,timestamptz,text,text,public.metric_provenance,bytea,bigint)',
    'execute'
  ),
  'only service_role can call the attested check-in RPC'
);

-- ---------------------------------------------------------------------------
-- Exact dwell/overlap boundaries and attested idempotency
-- ---------------------------------------------------------------------------

create temporary table t_first as
select * from pg_temp.submit(
  'b0000001-0000-0000-0000-000000000001',
  'accepted-payload',
  pg_temp.samples((select t0 from t_fixture)),
  'd0000001-0000-0000-0000-000000000001',
  (select t0 + interval '15 seconds' from t_fixture),
  (select t0 + interval '45 seconds' from t_fixture),
  'device',
  (select key_id from t_fixture),
  1
);

select is(
  (select outcome from t_first),
  'accepted'::public.geofence_checkin_outcome,
  'the exact configured dwell and workout-overlap boundaries are accepted'
);
select is(
  (select dwell_seconds from t_first),
  60.000::numeric,
  'adjacent inside segments sum to exactly 60 seconds of dwell'
);
select is(
  (select workout_overlap_seconds from t_first),
  30.000::numeric,
  'workout overlap is the exact intersection with credited segments'
);
select is(
  (select location_count from public.geofence_checkins
   where id = (select checkin_id from t_first)),
  3::smallint,
  'the check-in records its raw sample count'
);
select is(
  (select count(*) from public.geofence_location_observations
   where checkin_id = (select checkin_id from t_first)
     and outcome = 'inside'
     and distance_meters = 0),
  3::bigint,
  'the server reclassifies all center-point samples as inside at zero distance'
);
select ok(
  (select bool_and(not is_produced_by_accessory)
   from public.geofence_location_observations
   where checkin_id = (select checkin_id from t_first)),
  'the raw CoreLocation accessory signal is persisted for audit'
);
select ok(
  (select lower_inc(visit_range) and not upper_inc(visit_range)
   from public.geofence_checkins
   where id = (select checkin_id from t_first)),
  'visit ranges are half-open'
);
select is(
  (select sign_count from public.device_attestations
   where key_id = (select key_id from t_fixture)),
  1::bigint,
  'an accepted attested check-in consumes the shared device counter'
);

create temporary table t_retry as
select * from pg_temp.submit(
  'b0000001-0000-0000-0000-000000000001',
  'accepted-payload',
  pg_temp.samples((select t0 from t_fixture)),
  'd0000001-0000-0000-0000-000000000001',
  (select t0 + interval '15 seconds' from t_fixture),
  (select t0 + interval '45 seconds' from t_fixture),
  'device',
  (select key_id from t_fixture),
  1
);

select is((select replayed from t_retry), true,
  'an identical retry is returned before checking its spent counter');
select is(
  (select checkin_id from t_retry),
  (select checkin_id from t_first),
  'the retry returns the original immutable attempt'
);
select is(
  (select count(*) from public.geofence_checkins
   where client_checkin_id = 'b0000001-0000-0000-0000-000000000001'),
  1::bigint,
  'the retry creates neither a second attempt nor duplicate location rows'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000001-0000-0000-0000-000000000001',
       'different-payload',
       pg_temp.samples((select t0 from t_fixture)),
       'd0000001-0000-0000-0000-000000000001',
       (select t0 + interval '15 seconds' from t_fixture),
       (select t0 + interval '45 seconds' from t_fixture),
       'device', (select key_id from t_fixture), 2) $$,
  '23505',
  null,
  'the same client id with a different digest is rejected'
);

-- A well-formed failed validation is still attested, consumes the counter, and
-- remains in the ledger.
create temporary table t_simulated as
select * from pg_temp.submit(
  'b0000002-0000-0000-0000-000000000002',
  'simulated-payload',
  pg_temp.samples(
    (select t0 + interval '1000 seconds' from t_fixture),
    0, 0, 5, true
  ),
  'd0000002-0000-0000-0000-000000000002',
  (select t0 + interval '1015 seconds' from t_fixture),
  (select t0 + interval '1045 seconds' from t_fixture),
  'device',
  (select key_id from t_fixture),
  2
);

select is(
  (select outcome from t_simulated),
  'simulated_location'::public.geofence_checkin_outcome,
  'a simulated CoreLocation sample produces an explicit failed outcome'
);
select is(
  (select sign_count from public.device_attestations
   where key_id = (select key_id from t_fixture)),
  2::bigint,
  'the auditable simulated attempt still consumes its valid assertion'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000003-0000-0000-0000-000000000003',
       'spent-counter',
       pg_temp.samples((select t0 + interval '1200 seconds' from t_fixture)),
       'd0000003-0000-0000-0000-000000000003',
       (select t0 + interval '1215 seconds' from t_fixture),
       (select t0 + interval '1245 seconds' from t_fixture),
       'device', (select key_id from t_fixture), 2) $$,
  '23001',
  null,
  'a fresh request cannot replay the spent shared counter'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000011-0000-0000-0000-000000000011',
       'zero-accuracy',
       pg_temp.samples(
         (select t0 + interval '1250 seconds' from t_fixture),
         0, 0, 0
       ),
       'd0000011-0000-0000-0000-000000000011',
       (select t0 + interval '1265 seconds' from t_fixture),
       (select t0 + interval '1295 seconds' from t_fixture)) $$,
  '22023',
  null,
  'zero accuracy is malformed and rejected before attestation consumption'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000012-0000-0000-0000-000000000012',
       'duplicate-times',
       pg_temp.samples(
         (select t0 + interval '1300 seconds' from t_fixture),
         0, 0, 5, false, 0
       ),
       'd0000012-0000-0000-0000-000000000012',
       (select t0 + interval '1315 seconds' from t_fixture),
       (select t0 + interval '1345 seconds' from t_fixture)) $$,
  '22023',
  null,
  'duplicate absolute sample timestamps are rejected'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000013-0000-0000-0000-000000000013',
       'oversized-span',
       pg_temp.samples(
         (select t0 + interval '1350 seconds' from t_fixture),
         0, 0, 5, false, 14401
       ),
       'd0000013-0000-0000-0000-000000000013',
       (select t0 + interval '1365 seconds' from t_fixture),
       (select t0 + interval '1395 seconds' from t_fixture)) $$,
  '22023',
  null,
  'a location envelope longer than eight hours is rejected'
);
select throws_ok(
  $$ select * from pg_temp.submit(
       'b0000014-0000-0000-0000-000000000014',
       'one-sample',
       jsonb_build_array(jsonb_build_object(
         'observed_at', (select t0 + interval '1375 seconds' from t_fixture),
         'latitude', 0,
         'longitude', 0,
         'accuracy_meters', 5,
         'is_simulated', false,
         'is_produced_by_accessory', false
       )),
       'd0000014-0000-0000-0000-000000000014',
       (select t0 + interval '1390 seconds' from t_fixture),
       (select t0 + interval '1420 seconds' from t_fixture)) $$,
  '22023',
  null,
  'a single sample cannot establish a visit interval'
);
select throws_ok(
  $$ select * from public.record_geofence_checkin(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000002',
       'f0000001-0000-0000-0000-000000000002',
       'b0000015-0000-0000-0000-000000000015',
       extensions.digest('closed-ingest', 'sha256'),
       pg_temp.samples(date_trunc('hour', now()) - interval '36 hours'),
       'd0000015-0000-0000-0000-000000000015',
       date_trunc('hour', now()) - interval '36 hours' + interval '15 seconds',
       date_trunc('hour', now()) - interval '36 hours' + interval '45 seconds',
       'running',
       'com.apple.health',
       'device',
       null::bytea,
       null::bigint) $$,
  '23001',
  null,
  'an active row cannot accept check-ins after its ingest grace period'
);

-- ---------------------------------------------------------------------------
-- Geofence, clock, provenance, dwell, and overlap outcomes
-- ---------------------------------------------------------------------------

select is(
  (select outcome from pg_temp.submit(
    'b0000004-0000-0000-0000-000000000004',
    'low-accuracy',
    pg_temp.samples(
      (select t0 + interval '1400 seconds' from t_fixture),
      0, 0, 20.01, false
    ),
    'd0000004-0000-0000-0000-000000000004',
    (select t0 + interval '1415 seconds' from t_fixture),
    (select t0 + interval '1445 seconds' from t_fixture)
  )),
  'low_accuracy'::public.geofence_checkin_outcome,
  'accuracy just above the configured inclusive maximum is explicit'
);
select is(
  (
    select count(*)
    from public.geofence_location_observations observation
    join public.geofence_checkins checkin on checkin.id = observation.checkin_id
    where checkin.client_checkin_id =
      'b0000004-0000-0000-0000-000000000004'
      and observation.outcome = 'low_accuracy'
  ),
  3::bigint,
  'the parent outcome and full-precision per-sample boundary classifications agree'
);
select is(
  (select outcome from pg_temp.submit(
    'b0000005-0000-0000-0000-000000000005',
    'outside',
    pg_temp.samples(
      (select t0 + interval '1600 seconds' from t_fixture),
      0.01, 0, 5, false
    ),
    'd0000005-0000-0000-0000-000000000005',
    (select t0 + interval '1615 seconds' from t_fixture),
    (select t0 + interval '1645 seconds' from t_fixture)
  )),
  'outside_geofence'::public.geofence_checkin_outcome,
  'a location materially outside the configured radius is stored as such'
);
select is(
  (select outcome from pg_temp.submit(
    'b0000006-0000-0000-0000-000000000006',
    'short-dwell',
    pg_temp.samples(
      (select t0 + interval '1800 seconds' from t_fixture),
      0, 0, 5, false, 29
    ),
    'd0000006-0000-0000-0000-000000000006',
    (select t0 + interval '1814 seconds' from t_fixture),
    (select t0 + interval '1844 seconds' from t_fixture)
  )),
  'insufficient_dwell'::public.geofence_checkin_outcome,
  '58 seconds is explicitly below the 60-second dwell threshold'
);
select is(
  (select outcome from pg_temp.submit(
    'b0000007-0000-0000-0000-000000000007',
    'sample-gap',
    pg_temp.samples(
      (select t0 + interval '2000 seconds' from t_fixture),
      0, 0, 5, false, 61
    ),
    'd0000007-0000-0000-0000-000000000007',
    (select t0 + interval '2015 seconds' from t_fixture),
    (select t0 + interval '2045 seconds' from t_fixture)
  )),
  'insufficient_dwell'::public.geofence_checkin_outcome,
  'inside samples beyond the maximum gap do not manufacture dwell'
);
select is(
  (select outcome from pg_temp.submit(
    'b0000008-0000-0000-0000-000000000008',
    'short-overlap',
    pg_temp.samples((select t0 + interval '2300 seconds' from t_fixture)),
    'd0000008-0000-0000-0000-000000000008',
    (select t0 + interval '2315 seconds' from t_fixture),
    (select t0 + interval '2344 seconds' from t_fixture)
  )),
  'insufficient_workout_overlap'::public.geofence_checkin_outcome,
  '29 seconds is explicitly below the 30-second workout-overlap threshold'
);
select is(
  (select outcome from pg_temp.submit(
    'b0000009-0000-0000-0000-000000000009',
    'manual-workout',
    pg_temp.samples((select t0 + interval '2500 seconds' from t_fixture)),
    'd0000009-0000-0000-0000-000000000009',
    (select t0 + interval '2515 seconds' from t_fixture),
    (select t0 + interval '2545 seconds' from t_fixture),
    'manual'
  )),
  'untrusted_workout'::public.geofence_checkin_outcome,
  'a manual HealthKit workout stays visible but is not trusted'
);
select is(
  (select outcome from pg_temp.submit(
    'b000000a-0000-0000-0000-00000000000a',
    'outside-window',
    pg_temp.samples((select window_start - interval '1 hour' from t_fixture)),
    'd000000a-0000-0000-0000-00000000000a',
    (select window_start - interval '1 hour' + interval '15 seconds'
     from t_fixture),
    (select window_start - interval '1 hour' + interval '45 seconds'
     from t_fixture)
  )),
  'outside_contest_window'::public.geofence_checkin_outcome,
  'past evidence outside the agreed contest window is retained and labelled'
);
select is(
  (select outcome from pg_temp.submit(
    'b000000b-0000-0000-0000-00000000000b',
    'future',
    pg_temp.samples(date_trunc('minute', now()) + interval '10 minutes'),
    'd000000b-0000-0000-0000-00000000000b',
    date_trunc('minute', now()) + interval '10 minutes 15 seconds',
    date_trunc('minute', now()) + interval '10 minutes 45 seconds'
  )),
  'future_evidence'::public.geofence_checkin_outcome,
  'inside-window evidence from the future has its own auditable outcome'
);
select is(
  (select count(*) from public.geofence_checkins
   where outcome <> 'accepted'),
  9::bigint,
  'all nine well-formed validation failures remain in the audit ledger'
);

-- ---------------------------------------------------------------------------
-- Global half-open visit/workout conflict validation
-- ---------------------------------------------------------------------------

select is(
  (select outcome from pg_temp.submit(
    'b000000c-0000-0000-0000-00000000000c',
    'overlapping-visit',
    pg_temp.samples((select t0 + interval '30 seconds' from t_fixture)),
    'd000000c-0000-0000-0000-00000000000c',
    (select t0 + interval '45 seconds' from t_fixture),
    (select t0 + interval '75 seconds' from t_fixture)
  )),
  'overlapping_checkin'::public.geofence_checkin_outcome,
  'an otherwise valid visit overlapping an accepted visit is recorded, not inserted as accepted'
);

create temporary table t_adjacent as
select * from pg_temp.submit(
  'b000000d-0000-0000-0000-00000000000d',
  'adjacent-visit',
  pg_temp.samples((select t0 + interval '60 seconds' from t_fixture)),
  'd000000d-0000-0000-0000-00000000000d',
  (select t0 + interval '75 seconds' from t_fixture),
  (select t0 + interval '105 seconds' from t_fixture)
);

select is(
  (select outcome from t_adjacent),
  'accepted'::public.geofence_checkin_outcome,
  'a visit beginning exactly at the prior half-open upper bound is accepted'
);
select is(
  (select count(*) from public.geofence_checkins
   where outcome = 'accepted'),
  2::bigint,
  'the two boundary-touching accepted visits coexist'
);
select is(
  (select outcome from pg_temp.submit(
    'b000000e-0000-0000-0000-00000000000e',
    'reused-workout',
    pg_temp.samples((select t0 + interval '180 seconds' from t_fixture)),
    'd0000001-0000-0000-0000-000000000001',
    (select t0 + interval '195 seconds' from t_fixture),
    (select t0 + interval '225 seconds' from t_fixture)
  )),
  'reused_workout'::public.geofence_checkin_outcome,
  'a HealthKit workout UUID already accepted for this user cannot be reused'
);
select is(
  (select outcome from pg_temp.submit(
    'b000000f-0000-0000-0000-00000000000f',
    'overlapping-workout',
    pg_temp.samples((select t0 + interval '600 seconds' from t_fixture)),
    'd000000f-0000-0000-0000-00000000000f',
    (select t0 + interval '30 seconds' from t_fixture),
    (select t0 + interval '630 seconds' from t_fixture)
  )),
  'overlapping_workout'::public.geofence_checkin_outcome,
  'a distinct workout range overlapping accepted workout evidence is explicit'
);

-- ---------------------------------------------------------------------------
-- Append-only enforcement and trusted-location views
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update public.contest_geofences set radius_meters = 999 $$,
  '23001',
  null,
  'a privileged writer cannot rewrite geofence terms'
);
select throws_ok(
  $$ update public.geofence_checkins set outcome = 'accepted'
     where outcome = 'outside_geofence' $$,
  '23001',
  null,
  'a privileged writer cannot relabel a failed check-in'
);
select throws_ok(
  $$ update public.geofence_location_observations
     set latitude = 0 where outcome = 'outside' $$,
  '23001',
  null,
  'a privileged writer cannot move a raw location sample'
);
select is(
  (select count(*) from public.contest_checkin_integrity
   where checkin_id = (select checkin_id from t_first)),
  1::bigint,
  'the accepted attempt is visible through the unchanged integrity sidecar'
);
select is(
  (select count(*) from public.contest_location_observations),
  3::bigint,
  'only the three inside samples from the accepted attested attempt are trusted locations'
);
select is(
  (select count(*) from public.contest_location_observations
   where checkin_id = (select checkin_id from t_adjacent)),
  0::bigint,
  'an accepted development-bypass check-in never enters the trusted location feed'
);

update public.contests
set status = 'finalized'
where id = 'a0000001-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- RLS: owner and same retained roster, never an unrelated account
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
select ok(
  (select count(*) > 0 from public.geofence_checkins)
  and (select count(*) > 0 from public.geofence_location_observations)
  and (select count(*) > 0 from public.contest_location_observations),
  'the owner can read all of their M6 audit facts'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select ok(
  (select count(*) > 0 from public.contest_geofences)
  and (select count(*) > 0 from public.geofence_checkins)
  and (select count(*) > 0 from public.contest_checkin_integrity)
  and (select count(*) = 0 from public.geofence_location_observations)
  and (select count(*) = 0 from public.contest_location_observations),
  'a finalized rival sees shared outcomes but not another user''s exact coordinates'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select ok(
  (select count(*) = 0 from public.contest_geofences)
  and (select count(*) = 0 from public.geofence_checkins)
  and (select count(*) = 0 from public.geofence_location_observations)
  and (select count(*) = 0 from public.contest_checkin_integrity)
  and (select count(*) = 0 from public.contest_location_observations),
  'an unrelated signed-in account cannot enumerate venue or location evidence'
);
select throws_ok(
  $$ insert into public.geofence_checkins (
       contest_id, geofence_id, user_id, client_checkin_id,
       attested, payload_digest, started_at, ended_at,
       workout_id, workout_started_at, workout_ended_at,
       workout_activity_type, workout_provenance,
       location_count, inside_location_count, dwell_seconds,
       workout_overlap_seconds, outcome
     ) values (
       'a0000001-0000-0000-0000-000000000001',
       'f0000001-0000-0000-0000-000000000001',
       '33333333-3333-3333-3333-333333333333',
       gen_random_uuid(), false, extensions.digest('forged', 'sha256'),
       now() - interval '1 hour', now(),
       gen_random_uuid(), now() - interval '1 hour', now(),
       'running', 'device', 2, 2, 3600, 3600, 'accepted'
     ) $$,
  '42501',
  null,
  'authenticated cannot bypass the service-only RPC with a direct insert'
);
reset role;

select * from finish();
rollback;
