-- M6 — Attested geofence check-ins and workout-overlap validation.
--
-- Check-ins are an integrity sidecar. They never rewrite metric_snapshots,
-- contest_evidence, or a scoring total. Every well-formed, attested attempt is
-- retained with an explicit outcome, including attempts that were outside the
-- geofence or conflicted with earlier accepted evidence.
--
-- All time arithmetic below uses absolute timestamptz instants and half-open
-- ranges. A timezone is neither read nor inferred.

-- ===========================================================================
-- SECTION 1 — Closed validation vocabularies
-- ===========================================================================

create type public.geofence_location_outcome as enum (
  'inside',
  'outside',
  'low_accuracy',
  'simulated'
);

create type public.geofence_checkin_outcome as enum (
  'accepted',
  'outside_contest_window',
  'future_evidence',
  'simulated_location',
  'low_accuracy',
  'outside_geofence',
  'insufficient_dwell',
  'insufficient_workout_overlap',
  'untrusted_workout',
  'overlapping_checkin',
  'reused_workout',
  'overlapping_workout'
);

-- ===========================================================================
-- SECTION 2 — Immutable geofence definitions
-- ===========================================================================

create table public.contest_geofences (
  id                              uuid primary key default gen_random_uuid(),
  contest_id                      uuid not null
    references public.contests (id) on delete cascade,
  name                            text not null,
  center_latitude                 numeric(10, 7) not null,
  center_longitude                numeric(10, 7) not null,
  radius_meters                   numeric(10, 2) not null,
  max_accuracy_meters             numeric(10, 2) not null,
  minimum_dwell_seconds           integer not null,
  maximum_sample_gap_seconds      integer not null,
  minimum_workout_overlap_seconds integer not null,
  created_at                      timestamptz not null default clock_timestamp(),

  constraint contest_geofences_identity_unique
    unique (id, contest_id),
  constraint contest_geofences_name_length
    check (char_length(name) between 1 and 120),
  constraint contest_geofences_latitude_range
    check (center_latitude between -90 and 90),
  constraint contest_geofences_longitude_range
    check (center_longitude between -180 and 180),
  constraint contest_geofences_radius_range
    check (radius_meters > 0 and radius_meters <= 100000),
  constraint contest_geofences_accuracy_range
    check (max_accuracy_meters > 0 and max_accuracy_meters <= 100000),
  constraint contest_geofences_minimum_dwell_range
    check (minimum_dwell_seconds between 1 and 28800),
  constraint contest_geofences_maximum_gap_range
    check (maximum_sample_gap_seconds between 1 and 3600),
  constraint contest_geofences_minimum_overlap_range
    check (minimum_workout_overlap_seconds between 1 and 28800)
);

comment on table public.contest_geofences is
  'Immutable, service-managed contest venue definitions and M6 validation thresholds.';
comment on column public.contest_geofences.maximum_sample_gap_seconds is
  'Maximum gap credited between two consecutive inside observations.';

create index contest_geofences_contest_idx
  on public.contest_geofences (contest_id, created_at);

create or replace function app.assert_geofence_before_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.contest_status;
begin
  select status into v_status
  from public.contests
  where id = new.contest_id
  for update;

  if v_status is null then
    -- The foreign key remains the final authority; this gives the trigger a
    -- deterministic answer without treating a missing contest as pending.
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_status <> 'pending' then
    raise exception
      'geofences must be provisioned before contest activation (status %)',
      v_status
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger contest_geofences_assert_pending_insert
  before insert on public.contest_geofences
  for each row execute function app.assert_geofence_before_activation();

create trigger contest_geofences_forbid_update
  before update on public.contest_geofences
  for each row execute function app.forbid_mutation();

-- ===========================================================================
-- SECTION 3 — Append-only check-in and per-sample audit ledgers
-- ===========================================================================

create table public.geofence_checkins (
  id                       uuid primary key default gen_random_uuid(),
  contest_id               uuid not null,
  geofence_id               uuid not null,
  user_id                   uuid not null,
  client_checkin_id         uuid not null,

  key_id                    bytea
    references public.device_attestations (key_id) on delete cascade,
  sign_count                bigint,
  attested                  boolean not null,
  payload_digest            bytea not null,

  started_at                timestamptz not null,
  ended_at                  timestamptz not null,
  visit_range               tstzrange not null
    generated always as (tstzrange(started_at, ended_at, '[)')) stored,

  workout_id                uuid not null,
  workout_started_at        timestamptz not null,
  workout_ended_at          timestamptz not null,
  workout_range             tstzrange not null
    generated always as (
      tstzrange(workout_started_at, workout_ended_at, '[)')
    ) stored,
  workout_activity_type     text not null,
  workout_source_bundle_id  text,
  workout_provenance        public.metric_provenance not null,

  location_count            smallint not null,
  inside_location_count     smallint not null,
  dwell_seconds             numeric(12, 3) not null,
  workout_overlap_seconds   numeric(12, 3) not null,
  outcome                    public.geofence_checkin_outcome not null,
  rule_version               text not null default 'm6-v1',
  recorded_at                timestamptz not null default clock_timestamp(),

  constraint geofence_checkins_client_id_unique
    unique (user_id, client_checkin_id),
  constraint geofence_checkins_identity_unique
    unique (id, contest_id, user_id),
  constraint geofence_checkins_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete cascade,
  constraint geofence_checkins_geofence_fkey
    foreign key (geofence_id, contest_id)
    references public.contest_geofences (id, contest_id)
    on delete cascade,
  constraint geofence_checkins_payload_digest_sha256
    check (octet_length(payload_digest) = 32),
  constraint geofence_checkins_attestation_fields_match
    check (attested = (key_id is not null and sign_count is not null)),
  constraint geofence_checkins_sign_count_non_negative
    check (sign_count is null or sign_count >= 0),
  constraint geofence_checkins_visit_ordered
    check (ended_at > started_at),
  constraint geofence_checkins_visit_bounded
    check (ended_at <= started_at + interval '8 hours'),
  constraint geofence_checkins_workout_ordered
    check (workout_ended_at > workout_started_at),
  constraint geofence_checkins_workout_bounded
    check (workout_ended_at <= workout_started_at + interval '24 hours'),
  constraint geofence_checkins_location_counts
    check (
      location_count between 2 and 256
      and inside_location_count between 0 and location_count
    ),
  constraint geofence_checkins_dwell_non_negative
    check (dwell_seconds >= 0),
  constraint geofence_checkins_overlap_non_negative
    check (
      workout_overlap_seconds >= 0
      and workout_overlap_seconds <= dwell_seconds
    ),
  constraint geofence_checkins_activity_type_length
    check (char_length(workout_activity_type) between 1 and 100),
  constraint geofence_checkins_source_bundle_length
    check (
      workout_source_bundle_id is null
      or char_length(workout_source_bundle_id) between 1 and 200
    ),
  constraint geofence_checkins_rule_version_length
    check (char_length(rule_version) between 1 and 80),

  -- Only successful evidence reserves time. Failed attempts remain auditable
  -- but cannot block a corrected retry.
  constraint geofence_checkins_no_accepted_visit_overlap
    exclude using gist (
      user_id extensions.gist_uuid_ops with =,
      visit_range with &&
    )
    where (outcome = 'accepted'),

  constraint geofence_checkins_no_accepted_workout_overlap
    exclude using gist (
      user_id extensions.gist_uuid_ops with =,
      workout_range with &&
    )
    where (outcome = 'accepted')
);

comment on table public.geofence_checkins is
  'Append-only attested check-in attempts with explicit server-derived validation outcomes.';
comment on column public.geofence_checkins.visit_range is
  'Server-derived half-open [first location, last location) visit envelope.';
comment on column public.geofence_checkins.workout_overlap_seconds is
  'Exact overlap of the workout with credited inside-to-inside dwell segments.';
comment on column public.geofence_checkins.outcome is
  'Validation result. Only accepted rows reserve visit/workout ranges or feed trusted locations.';

create unique index geofence_checkins_accepted_workout_id_idx
  on public.geofence_checkins (user_id, workout_id)
  where outcome = 'accepted';

create index geofence_checkins_contest_user_idx
  on public.geofence_checkins (contest_id, user_id, recorded_at desc);

create index geofence_checkins_geofence_idx
  on public.geofence_checkins (geofence_id, recorded_at desc);

create index geofence_checkins_key_idx
  on public.geofence_checkins (key_id)
  where key_id is not null;

create table public.geofence_location_observations (
  id               uuid primary key default gen_random_uuid(),
  checkin_id       uuid not null,
  contest_id       uuid not null,
  user_id          uuid not null,
  sample_index     smallint not null,
  observed_at      timestamptz not null,
  -- Keep the raw finite IEEE-754 values received from JSON. Rounding these
  -- before the child trigger reclassifies them can put the parent outcome and
  -- the immutable sample audit row on opposite sides of a boundary.
  latitude         double precision not null,
  longitude        double precision not null,
  accuracy_meters  double precision not null,
  is_simulated     boolean not null,
  is_produced_by_accessory boolean not null,
  distance_meters  double precision not null,
  outcome          public.geofence_location_outcome not null,
  created_at       timestamptz not null default clock_timestamp(),

  constraint geofence_location_observations_checkin_fkey
    foreign key (checkin_id, contest_id, user_id)
    references public.geofence_checkins (id, contest_id, user_id)
    on delete cascade,
  constraint geofence_location_observations_timestamp_unique
    unique (checkin_id, observed_at),
  constraint geofence_location_observations_index_unique
    unique (checkin_id, sample_index),
  constraint geofence_location_observations_sample_index
    check (sample_index between 1 and 256),
  constraint geofence_location_observations_latitude_range
    check (latitude between -90 and 90),
  constraint geofence_location_observations_longitude_range
    check (longitude between -180 and 180),
  constraint geofence_location_observations_accuracy_range
    check (accuracy_meters > 0 and accuracy_meters <= 100000),
  constraint geofence_location_observations_distance_range
    check (distance_meters >= 0 and distance_meters <= 20050000)
);

comment on table public.geofence_location_observations is
  'Append-only raw location samples with server-derived distance and classification.';

create index geofence_location_observations_contest_user_time_idx
  on public.geofence_location_observations (
    contest_id, user_id, observed_at
  );

create trigger geofence_checkins_forbid_update
  before update on public.geofence_checkins
  for each row execute function app.forbid_mutation();

create trigger geofence_location_observations_forbid_update
  before update on public.geofence_location_observations
  for each row execute function app.forbid_mutation();

-- DELETE remains absent from every client grant and policy, but is not blocked
-- by a trigger because account and contest deletion still use cascades (D44).

-- ===========================================================================
-- SECTION 4 — Server-derived geospatial facts
-- ===========================================================================

create or replace function app.haversine_distance_meters(
  p_latitude_a double precision,
  p_longitude_a double precision,
  p_latitude_b double precision,
  p_longitude_b double precision
)
returns double precision
language sql
immutable
strict
set search_path = ''
as $$
  select 2.0 * 6371008.8 * asin(
    least(
      1.0,
      sqrt(
        power(
          sin(radians(p_latitude_b - p_latitude_a) / 2.0),
          2
        )
        + cos(radians(p_latitude_a))
        * cos(radians(p_latitude_b))
        * power(
          sin(radians(p_longitude_b - p_longitude_a) / 2.0),
          2
        )
      )
    )
  );
$$;

comment on function app.haversine_distance_meters(
  double precision, double precision, double precision, double precision
) is
  'Great-circle distance in meters, stored at full calculation precision beside each raw sample.';

create or replace function app.prepare_geofence_location_observation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkin  public.geofence_checkins;
  v_geofence public.contest_geofences;
  v_distance double precision;
begin
  select * into v_checkin
  from public.geofence_checkins
  where id = new.checkin_id;

  if v_checkin.id is null then
    raise exception 'check-in % does not exist', new.checkin_id
      using errcode = 'foreign_key_violation';
  end if;

  select * into v_geofence
  from public.contest_geofences
  where id = v_checkin.geofence_id
    and contest_id = v_checkin.contest_id;

  new.contest_id := v_checkin.contest_id;
  new.user_id := v_checkin.user_id;
  v_distance := app.haversine_distance_meters(
    new.latitude,
    new.longitude,
    v_geofence.center_latitude,
    v_geofence.center_longitude
  );
  new.distance_meters := v_distance;

  new.outcome := case
    when new.is_simulated
      then 'simulated'::public.geofence_location_outcome
    when new.accuracy_meters > v_geofence.max_accuracy_meters
      then 'low_accuracy'::public.geofence_location_outcome
    when v_distance <= v_geofence.radius_meters
      then 'inside'::public.geofence_location_outcome
    else 'outside'::public.geofence_location_outcome
  end;

  return new;
end;
$$;

create trigger geofence_location_observations_prepare
  before insert on public.geofence_location_observations
  for each row execute function app.prepare_geofence_location_observation();

-- ===========================================================================
-- SECTION 5 — RLS predicates and access model
-- ===========================================================================

create or replace function app.is_accepted_active_contest_participant(
  p_contest_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.contest_participants participant
    join public.contests contest on contest.id = participant.contest_id
    where participant.contest_id = p_contest_id
      and participant.user_id = p_user_id
      and participant.status = 'accepted'
      and contest.status in ('active', 'finalized')
  );
$$;

alter table public.contest_geofences enable row level security;
alter table public.geofence_checkins enable row level security;
alter table public.geofence_location_observations enable row level security;

create policy contest_geofences_select_roster
  on public.contest_geofences
  for select to authenticated
  using (
    app.is_contest_participant(contest_id, (select auth.uid()))
  );

create policy geofence_checkins_select_own_or_active_rival
  on public.geofence_checkins
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or app.is_accepted_active_contest_participant(
      contest_id, (select auth.uid())
    )
  );

-- Exact coordinates are materially more sensitive than the validation result.
-- Rivals can audit the check-in sidecar, but only the owner (and the
-- service-role integrity assessor, which bypasses RLS) can read raw or trusted
-- location rows.
create policy geofence_location_observations_select_own
  on public.geofence_location_observations
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ===========================================================================
-- SECTION 6 — Integrity sidecar views
-- ===========================================================================

create view public.contest_checkin_integrity
with (security_invoker = true)
as
select
  checkin.id as checkin_id,
  checkin.contest_id,
  checkin.geofence_id,
  checkin.user_id,
  checkin.client_checkin_id,
  checkin.attested,
  checkin.started_at,
  checkin.ended_at,
  checkin.visit_range,
  checkin.workout_id,
  checkin.workout_started_at,
  checkin.workout_ended_at,
  checkin.workout_range,
  checkin.workout_activity_type,
  checkin.workout_source_bundle_id,
  checkin.workout_provenance,
  checkin.location_count,
  checkin.inside_location_count,
  checkin.dwell_seconds,
  checkin.workout_overlap_seconds,
  checkin.outcome,
  checkin.rule_version,
  checkin.recorded_at
from public.geofence_checkins checkin;

comment on view public.contest_checkin_integrity is
  'M6 outcome sidecar. Never filters or rewrites contest evidence or scoring.';

create view public.contest_location_observations
with (security_invoker = true)
as
select
  observation.id,
  observation.checkin_id,
  observation.contest_id,
  observation.user_id,
  observation.observed_at,
  observation.latitude,
  observation.longitude,
  observation.accuracy_meters,
  observation.is_produced_by_accessory
from public.geofence_location_observations observation
join public.geofence_checkins checkin
  on checkin.id = observation.checkin_id
 and checkin.contest_id = observation.contest_id
 and checkin.user_id = observation.user_id
where checkin.outcome = 'accepted'
  and checkin.attested
  and observation.outcome = 'inside';

comment on view public.contest_location_observations is
  'Trusted M5 LocationObservation feed: inside samples from accepted, attested M6 check-ins.';

-- ===========================================================================
-- SECTION 7 — The attested check-in RPC
-- ===========================================================================

create or replace function public.record_geofence_checkin(
  p_user_id                  uuid,
  p_contest_id               uuid,
  p_geofence_id              uuid,
  p_client_checkin_id        uuid,
  p_payload_digest           bytea,
  p_locations                jsonb,
  p_workout_id               uuid,
  p_workout_started_at       timestamptz,
  p_workout_ended_at         timestamptz,
  p_workout_activity_type    text,
  p_workout_source_bundle_id text,
  p_workout_provenance       public.metric_provenance,
  p_key_id                   bytea default null,
  p_sign_count               bigint default null
)
returns table (
  checkin_id              uuid,
  outcome                 public.geofence_checkin_outcome,
  dwell_seconds           numeric,
  workout_overlap_seconds numeric,
  replayed                boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing       public.geofence_checkins;
  v_key            public.device_attestations;
  v_geofence       public.contest_geofences;
  v_contest_status public.contest_status;
  v_starts_at      timestamptz;
  v_ends_at        timestamptz;
  v_count          integer;
  v_unique_count   integer;
  v_started_at     timestamptz;
  v_ended_at       timestamptz;
  v_inside_count   integer;
  v_outside_count  integer;
  v_low_count      integer;
  v_simulated_count integer;
  v_dwell_seconds  numeric := 0;
  v_overlap_seconds numeric := 0;
  v_visit_range    tstzrange;
  v_workout_range  tstzrange;
  v_outcome        public.geofence_checkin_outcome;
  v_checkin_id     uuid;
  v_now            timestamptz := clock_timestamp();
begin
  if p_user_id is null
     or p_contest_id is null
     or p_geofence_id is null
     or p_client_checkin_id is null
     or p_workout_id is null
  then
    raise exception
      'user, contest, geofence, client check-in, and workout ids are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_payload_digest is null or octet_length(p_payload_digest) <> 32 then
    raise exception 'payload digest must be SHA-256'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Idempotency is deliberately before the shared App Attest counter. A retry
  -- carries the already-consumed assertion and must return the first result.
  select * into v_existing
  from public.geofence_checkins
  where user_id = p_user_id
    and client_checkin_id = p_client_checkin_id;

  if v_existing.id is not null then
    if v_existing.payload_digest <> p_payload_digest then
      raise exception
        'check-in % was already recorded with a different payload',
        p_client_checkin_id
        using errcode = 'unique_violation';
    end if;

    return query select
      v_existing.id,
      v_existing.outcome,
      v_existing.dwell_seconds,
      v_existing.workout_overlap_seconds,
      true;
    return;
  end if;

  if jsonb_typeof(p_locations) <> 'array' then
    raise exception 'locations must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  v_count := jsonb_array_length(p_locations);
  if v_count < 2 or v_count > 256 then
    raise exception 'a check-in needs between 2 and 256 locations, got %', v_count
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_locations) sample
    where jsonb_typeof(sample) <> 'object'
       or not (sample ? 'observed_at')
       or not (sample ? 'latitude')
       or not (sample ? 'longitude')
       or not (sample ? 'accuracy_meters')
       or not (sample ? 'is_simulated')
       or not (sample ? 'is_produced_by_accessory')
  ) then
    raise exception 'every location must contain the complete sample shape'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Cast once here so malformed timestamps and numbers fail before the replay
  -- counter is consumed.
  with samples as (
    select
      (sample ->> 'observed_at')::timestamptz as observed_at,
      (sample ->> 'latitude')::double precision as latitude,
      (sample ->> 'longitude')::double precision as longitude,
      (sample ->> 'accuracy_meters')::double precision as accuracy_meters,
      (sample ->> 'is_simulated')::boolean as is_simulated,
      (sample ->> 'is_produced_by_accessory')::boolean
        as is_produced_by_accessory
    from jsonb_array_elements(p_locations) sample
  )
  select
    count(*),
    count(distinct observed_at),
    min(observed_at),
    max(observed_at)
  into v_count, v_unique_count, v_started_at, v_ended_at
  from samples
  where observed_at is not null
    and latitude between -90 and 90
    and longitude between -180 and 180
    and accuracy_meters > 0
    and accuracy_meters <= 100000
    and is_simulated is not null
    and is_produced_by_accessory is not null;

  if v_count <> jsonb_array_length(p_locations)
     or v_unique_count <> v_count
  then
    raise exception
      'locations need valid coordinates and unique absolute timestamps'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_ended_at <= v_started_at
     or v_ended_at > v_started_at + interval '8 hours'
  then
    raise exception 'the observed location span must be positive and at most 8 hours'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_workout_started_at is null
     or p_workout_ended_at is null
     or p_workout_ended_at <= p_workout_started_at
     or p_workout_ended_at > p_workout_started_at + interval '24 hours'
  then
    raise exception 'the workout range must be positive and at most 24 hours'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_workout_provenance is null then
    raise exception 'workout provenance is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_workout_activity_type is null
     or char_length(p_workout_activity_type) not between 1 and 100
     or (
       p_workout_source_bundle_id is not null
       and char_length(p_workout_source_bundle_id) not between 1 and 200
     )
  then
    raise exception 'workout activity or source metadata is invalid'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A profile-row lock serializes accepted ranges across every contest and
  -- every device key owned by one user. It also closes the concurrent
  -- identical-idempotency race, so repeat the lookup after acquiring it.
  perform 1
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'complete onboarding before recording a check-in'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing
  from public.geofence_checkins
  where user_id = p_user_id
    and client_checkin_id = p_client_checkin_id;

  if v_existing.id is not null then
    if v_existing.payload_digest <> p_payload_digest then
      raise exception
        'check-in % was already recorded with a different payload',
        p_client_checkin_id
        using errcode = 'unique_violation';
    end if;

    return query select
      v_existing.id,
      v_existing.outcome,
      v_existing.dwell_seconds,
      v_existing.workout_overlap_seconds,
      true;
    return;
  end if;

  select contest.status, contest.starts_at, contest.ends_at
    into v_contest_status, v_starts_at, v_ends_at
  from public.contest_participants participant
  join public.contests contest on contest.id = participant.contest_id
  where participant.contest_id = p_contest_id
    and participant.user_id = p_user_id
    and participant.status = 'accepted';

  if not found or v_contest_status <> 'active' then
    raise exception 'only an accepted participant in an active contest may check in'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_geofence
  from public.contest_geofences
  where id = p_geofence_id
    and contest_id = p_contest_id;

  if v_geofence.id is null then
    raise exception 'geofence is not configured for this contest'
      using errcode = 'insufficient_privilege';
  end if;

  -- Status alone is not a clock. A stalled finalizer must not turn an old
  -- active row into an indefinitely open check-in endpoint.
  if v_now >= v_ends_at + app.ingest_grace_period() then
    raise exception
      'the check-in ingest window for contest % closed at %',
      p_contest_id, v_ends_at + app.ingest_grace_period()
      using errcode = 'restrict_violation';
  end if;

  if p_key_id is null and p_sign_count is not null then
    raise exception 'an assertion counter requires a device key'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_key_id is not null then
    if p_sign_count is null then
      raise exception 'an attested check-in must carry an assertion counter'
        using errcode = 'invalid_parameter_value';
    end if;

    select * into v_key
    from public.device_attestations
    where key_id = p_key_id
    for update;

    if v_key.key_id is null or v_key.user_id <> p_user_id then
      raise exception 'unknown attestation key'
        using errcode = 'insufficient_privilege';
    end if;

    if v_key.revoked_at is not null then
      raise exception 'this device key was revoked at %', v_key.revoked_at
        using errcode = 'insufficient_privilege';
    end if;

    if p_sign_count <= v_key.sign_count then
      raise exception
        'assertion counter % is not ahead of the recorded %',
        p_sign_count, v_key.sign_count
        using errcode = 'restrict_violation';
    end if;

    update public.device_attestations
    set sign_count = p_sign_count,
        last_asserted_at = v_now
    where key_id = p_key_id;
  end if;

  -- Classify every sample from the immutable geofence definition. JSON input
  -- order is irrelevant; window functions sort the absolute timestamps.
  with samples as (
    select
      (sample ->> 'observed_at')::timestamptz as observed_at,
      (sample ->> 'latitude')::double precision as latitude,
      (sample ->> 'longitude')::double precision as longitude,
      (sample ->> 'accuracy_meters')::double precision as accuracy_meters,
      (sample ->> 'is_simulated')::boolean as is_simulated,
      (sample ->> 'is_produced_by_accessory')::boolean
        as is_produced_by_accessory
    from jsonb_array_elements(p_locations) sample
  ),
  classified as (
    select
      samples.*,
      app.haversine_distance_meters(
        latitude,
        longitude,
        v_geofence.center_latitude,
        v_geofence.center_longitude
      ) as distance_meters,
      case
        when is_simulated
          then 'simulated'::public.geofence_location_outcome
        when accuracy_meters > v_geofence.max_accuracy_meters
          then 'low_accuracy'::public.geofence_location_outcome
        when app.haversine_distance_meters(
          latitude,
          longitude,
          v_geofence.center_latitude,
          v_geofence.center_longitude
        ) <= v_geofence.radius_meters
          then 'inside'::public.geofence_location_outcome
        else 'outside'::public.geofence_location_outcome
      end as sample_outcome
    from samples
  )
  select
    count(*) filter (where sample_outcome = 'inside'),
    count(*) filter (where sample_outcome = 'outside'),
    count(*) filter (where sample_outcome = 'low_accuracy'),
    count(*) filter (where sample_outcome = 'simulated')
  into
    v_inside_count,
    v_outside_count,
    v_low_count,
    v_simulated_count
  from classified;

  -- Credited dwell consists only of adjacent inside -> inside intervals whose
  -- gap is no larger than the immutable geofence threshold. Workout overlap is
  -- the sum of intersections with exactly those segments, not with the visit
  -- envelope (which may contain unobserved gaps).
  with samples as (
    select
      (sample ->> 'observed_at')::timestamptz as observed_at,
      (sample ->> 'latitude')::double precision as latitude,
      (sample ->> 'longitude')::double precision as longitude,
      (sample ->> 'accuracy_meters')::double precision as accuracy_meters,
      (sample ->> 'is_simulated')::boolean as is_simulated,
      (sample ->> 'is_produced_by_accessory')::boolean
        as is_produced_by_accessory
    from jsonb_array_elements(p_locations) sample
  ),
  classified as (
    select
      samples.*,
      case
        when is_simulated
          then 'simulated'::public.geofence_location_outcome
        when accuracy_meters > v_geofence.max_accuracy_meters
          then 'low_accuracy'::public.geofence_location_outcome
        when app.haversine_distance_meters(
          latitude,
          longitude,
          v_geofence.center_latitude,
          v_geofence.center_longitude
        ) <= v_geofence.radius_meters
          then 'inside'::public.geofence_location_outcome
        else 'outside'::public.geofence_location_outcome
      end as sample_outcome
    from samples
  ),
  ordered as (
    select
      observed_at,
      sample_outcome,
      lag(observed_at) over (order by observed_at) as previous_at,
      lag(sample_outcome) over (order by observed_at) as previous_outcome
    from classified
  ),
  segments as (
    select previous_at as segment_start, observed_at as segment_end
    from ordered
    where previous_outcome = 'inside'
      and sample_outcome = 'inside'
      and observed_at - previous_at
          <= make_interval(secs => v_geofence.maximum_sample_gap_seconds)
  )
  select
    coalesce(
      sum(extract(epoch from segment_end - segment_start)),
      0
    ),
    coalesce(
      sum(
        greatest(
          0::numeric,
          extract(epoch from (
            least(segment_end, p_workout_ended_at)
            - greatest(segment_start, p_workout_started_at)
          ))
        )
      ),
      0
    )
  into v_dwell_seconds, v_overlap_seconds
  from segments;

  v_visit_range := tstzrange(v_started_at, v_ended_at, '[)');
  v_workout_range := tstzrange(
    p_workout_started_at, p_workout_ended_at, '[)'
  );

  -- Deterministic precedence. Each raw fact remains on the row and in the
  -- per-sample ledger even when an earlier outcome wins this primary label.
  if v_started_at < v_starts_at
     or v_ended_at > v_ends_at
     or p_workout_started_at < v_starts_at
     or p_workout_ended_at > v_ends_at
  then
    v_outcome := 'outside_contest_window';
  elsif v_ended_at > v_now
     or p_workout_ended_at > v_now
  then
    v_outcome := 'future_evidence';
  elsif v_simulated_count > 0 then
    v_outcome := 'simulated_location';
  elsif v_inside_count = 0 and v_low_count > 0 and v_outside_count = 0 then
    v_outcome := 'low_accuracy';
  elsif v_inside_count = 0 then
    v_outcome := 'outside_geofence';
  elsif v_dwell_seconds < v_geofence.minimum_dwell_seconds then
    v_outcome := 'insufficient_dwell';
  elsif p_workout_provenance in ('manual', 'unknown') then
    v_outcome := 'untrusted_workout';
  elsif v_overlap_seconds < v_geofence.minimum_workout_overlap_seconds then
    v_outcome := 'insufficient_workout_overlap';
  elsif exists (
    select 1
    from public.geofence_checkins existing
    where existing.user_id = p_user_id
      and existing.outcome = 'accepted'
      and existing.visit_range && v_visit_range
  ) then
    v_outcome := 'overlapping_checkin';
  elsif exists (
    select 1
    from public.geofence_checkins existing
    where existing.user_id = p_user_id
      and existing.outcome = 'accepted'
      and existing.workout_id = p_workout_id
  ) then
    v_outcome := 'reused_workout';
  elsif exists (
    select 1
    from public.geofence_checkins existing
    where existing.user_id = p_user_id
      and existing.outcome = 'accepted'
      and existing.workout_range && v_workout_range
  ) then
    v_outcome := 'overlapping_workout';
  else
    v_outcome := 'accepted';
  end if;

  insert into public.geofence_checkins (
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
    outcome
  )
  values (
    p_contest_id,
    p_geofence_id,
    p_user_id,
    p_client_checkin_id,
    p_key_id,
    p_sign_count,
    p_key_id is not null,
    p_payload_digest,
    v_started_at,
    v_ended_at,
    p_workout_id,
    p_workout_started_at,
    p_workout_ended_at,
    p_workout_activity_type,
    p_workout_source_bundle_id,
    p_workout_provenance,
    v_count,
    v_inside_count,
    round(v_dwell_seconds, 3),
    round(v_overlap_seconds, 3),
    v_outcome
  )
  returning id into v_checkin_id;

  insert into public.geofence_location_observations (
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
    -- Recomputed by the trigger.
    distance_meters,
    outcome
  )
  select
    v_checkin_id,
    p_contest_id,
    p_user_id,
    row_number() over (
      order by (sample ->> 'observed_at')::timestamptz
    )::smallint,
    (sample ->> 'observed_at')::timestamptz,
    (sample ->> 'latitude')::double precision,
    (sample ->> 'longitude')::double precision,
    (sample ->> 'accuracy_meters')::double precision,
    (sample ->> 'is_simulated')::boolean,
    (sample ->> 'is_produced_by_accessory')::boolean,
    0,
    'outside'
  from jsonb_array_elements(p_locations) sample;

  return query select
    v_checkin_id,
    v_outcome,
    round(v_dwell_seconds, 3),
    round(v_overlap_seconds, 3),
    false;
end;
$$;

comment on function public.record_geofence_checkin(
  uuid, uuid, uuid, uuid, bytea, jsonb, uuid, timestamptz, timestamptz,
  text, text, public.metric_provenance, bytea, bigint
) is
  'Attested M6 ingest. Idempotent before counter consumption; stores every well-formed validation outcome.';

-- ===========================================================================
-- SECTION 8 — Least privilege
-- ===========================================================================

revoke all on public.contest_geofences,
              public.geofence_checkins,
              public.geofence_location_observations,
              public.contest_checkin_integrity,
              public.contest_location_observations
  from public, anon, authenticated;

grant select on public.contest_geofences,
                public.geofence_checkins,
                public.geofence_location_observations,
                public.contest_checkin_integrity,
                public.contest_location_observations
  to authenticated;

revoke update, delete on public.contest_geofences from service_role;
grant select, insert on public.contest_geofences to service_role;
grant select on public.geofence_checkins,
                public.geofence_location_observations,
                public.contest_checkin_integrity,
                public.contest_location_observations
  to service_role;

revoke all on function app.haversine_distance_meters(
  double precision, double precision, double precision, double precision
) from public, anon, authenticated;

revoke all on function app.prepare_geofence_location_observation()
  from public, anon, authenticated;

revoke all on function app.assert_geofence_before_activation()
  from public, anon, authenticated;

revoke all on function public.record_geofence_checkin(
  uuid, uuid, uuid, uuid, bytea, jsonb, uuid, timestamptz, timestamptz,
  text, text, public.metric_provenance, bytea, bigint
) from public, anon, authenticated;

grant execute on function public.record_geofence_checkin(
  uuid, uuid, uuid, uuid, bytea, jsonb, uuid, timestamptz, timestamptz,
  text, text, public.metric_provenance, bytea, bigint
) to service_role;
