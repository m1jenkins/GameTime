-- Retire charity (D143).
--
-- The owner dropped charity from GameTime. The legacy social contest model
-- named a charity per accepted participant and published donation obligations
-- from its results. Nothing in production ever used it: the curated charity
-- list was never populated, so no legacy contest could be accepted there, and
-- the app keeps the legacy social runtime switched off.
--
-- This removes the charity list, the per-participant nomination, donation
-- obligations and every function path that read or wrote them. Legacy contest
-- creation keeps its terms minus the nomination, and the legacy model is
-- renamed legacy_social_contest. Applied migrations stay untouched.
--
-- Donation obligations are recorded promises to pay, so this refuses to run
-- if any exist rather than delete one.

do $$
begin
  if exists (select 1 from public.donation_obligations) then
    raise exception 'retire charity: donation obligations exist; settle or export them first'
      using errcode = 'restrict_violation';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Creation paths without a nomination. The signatures change, so the old
-- functions are dropped and the new ones re-granted exactly as before.
-- ---------------------------------------------------------------------------
drop function public.create_contest_with_invites_v1(
  uuid, text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid, uuid[], smallint,
  public.contest_tie_break, uuid
);
drop function public.create_contest(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid, smallint, public.contest_tie_break, uuid
);
drop function app.create_contest_unchecked(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid, smallint, public.contest_tie_break, uuid
);

CREATE FUNCTION app.create_contest_unchecked(p_title text, p_metric contest_metric, p_cadence contest_cadence, p_target_value numeric, p_stake_cents integer, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_timezone text, p_max_participants smallint DEFAULT 8, p_tie_break contest_tie_break DEFAULT 'integrity_score'::contest_tie_break, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_contest_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'complete onboarding before creating a contest'
      using errcode = 'insufficient_privilege';
  end if;

  -- Scoping a contest to a group you are not in would let you name a roster you
  -- have no reach into. Same error either way, so this does not reveal whether
  -- the group exists.
  if p_group_id is not null
     and not app.is_group_member(p_group_id, v_uid)
  then
    raise exception 'not a member of that group'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.contests (
    title, group_id, created_by, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  )
  values (
    p_title, p_group_id, v_uid, p_metric, p_cadence, p_target_value,
    p_stake_cents, p_tie_break, p_starts_at, p_ends_at, p_max_participants
  )
  returning id into v_contest_id;

  -- The author is enrolled as accepted from the first instant: they wrote the
  -- terms, so there is nothing for them to agree to afterwards.
  insert into public.contest_participants (
    contest_id, user_id, status, timezone
  )
  values (v_contest_id, v_uid, 'accepted', p_timezone);

  return v_contest_id;
end;
$function$;
CREATE FUNCTION public.create_contest(p_title text, p_metric contest_metric, p_cadence contest_cadence, p_target_value numeric, p_stake_cents integer, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_timezone text, p_max_participants smallint DEFAULT 8, p_tie_break contest_tie_break DEFAULT 'integrity_score'::contest_tie_break, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform app.require_active_caller();
  return app.create_contest_unchecked(
    p_title,
    p_metric,
    p_cadence,
    p_target_value,
    p_stake_cents,
    p_starts_at,
    p_ends_at,
    p_timezone,
    p_max_participants,
    p_tie_break,
    p_group_id
  );
end;
$function$;
CREATE FUNCTION public.create_contest_with_invites_v1(p_request_id uuid, p_title text, p_metric contest_metric, p_cadence contest_cadence, p_target_value numeric, p_stake_cents integer, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_timezone text, p_invitee_ids uuid[], p_max_participants smallint DEFAULT 2, p_tie_break contest_tie_break DEFAULT 'integrity_score'::contest_tie_break, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id        uuid := (select auth.uid());
  v_contest_id       uuid;
  v_existing_hash    bytea;
  v_payload_hash     bytea;
  v_invitee_ids      uuid[];
  v_supplied_count   integer;
  v_request_exists   boolean;
begin
  if v_caller_id is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_request_id is null then
    raise exception 'request UUID is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_invitee_ids is null or cardinality(p_invitee_ids) = 0 then
    raise exception 'at least one invitee is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if array_position(p_invitee_ids, null) is not null then
    raise exception 'invitee IDs cannot contain null'
      using errcode = 'invalid_parameter_value';
  end if;

  v_supplied_count := cardinality(p_invitee_ids);

  select array_agg(distinct invitee_id order by invitee_id)
    into v_invitee_ids
  from pg_catalog.unnest(p_invitee_ids) invitee_id;

  if cardinality(v_invitee_ids) <> v_supplied_count then
    raise exception 'invitee IDs must be unique'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_caller_id = any(v_invitee_ids) then
    raise exception 'the contest author cannot be invited'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_max_participants is null
     or p_max_participants < cardinality(v_invitee_ids) + 1
  then
    raise exception 'max participants is smaller than the initial roster'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Hash the values that become immutable contest terms. Timestamps use epoch
  -- values and target_value uses the stored scale, so equivalent payloads hash
  -- identically regardless of connection timezone or numeric spelling.
  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'title', p_title,
        'metric', p_metric::text,
        'cadence', p_cadence::text,
        'target_value', p_target_value::numeric(12, 2),
        'stake_cents', p_stake_cents,
        'starts_epoch', extract(epoch from p_starts_at),
        'ends_epoch', extract(epoch from p_ends_at),
        'timezone', p_timezone,
        'invitee_ids', pg_catalog.to_jsonb(v_invitee_ids),
        'max_participants', p_max_participants,
        'tie_break', p_tie_break::text,
        'group_id', p_group_id
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- A committed request is already authoritative. Check it before revalidating
  -- invitees so a manual retry still returns the original contest if an
  -- invitee was blocked or tombstoned after the first commit. The caller must
  -- still be active; require_active_caller locks against account deletion.
  select exists (
    select 1
    from app.contest_creation_requests request
    where request.actor_id = v_caller_id
      and request.request_id = p_request_id
  )
    into v_request_exists;

  if v_request_exists then
    perform app.require_active_caller();

    select request.payload_hash, request.contest_id
      into v_existing_hash, v_contest_id
    from app.contest_creation_requests request
    where request.actor_id = v_caller_id
      and request.request_id = p_request_id;

    if not found then
      raise exception 'contest request changed during retry'
        using errcode = 'serialization_failure';
    end if;

    if v_existing_hash <> v_payload_hash then
      raise exception
        'request UUID already used with different contest terms'
        using errcode = 'invalid_parameter_value';
    end if;

    return v_contest_id;
  end if;

  -- New requests lock the complete actor set in one deterministic order. This
  -- rejects stale callers/invitees, serializes concurrent duplicate UUIDs, and
  -- avoids a cross-invitation deadlock when two friends create duels together.
  perform app.lock_active_actors(
    pg_catalog.array_append(v_invitee_ids, v_caller_id)
  );

  -- A concurrent copy may have committed while this request waited on the
  -- actor locks. Recheck under the now-serialized actor set.
  select request.payload_hash, request.contest_id
    into v_existing_hash, v_contest_id
  from app.contest_creation_requests request
  where request.actor_id = v_caller_id
    and request.request_id = p_request_id;

  if found then
    if v_existing_hash <> v_payload_hash then
      raise exception
        'request UUID already used with different contest terms'
        using errcode = 'invalid_parameter_value';
    end if;

    return v_contest_id;
  end if;

  -- The existing private creator remains the single owner of contest-term
  -- validation and author enrolment. Everything below is in this transaction,
  -- so any invitation failure rolls back the contest and the request ledger.
  v_contest_id := app.create_contest_unchecked(
    p_title,
    p_metric,
    p_cadence,
    p_target_value,
    p_stake_cents,
    p_starts_at,
    p_ends_at,
    p_timezone,
    p_max_participants,
    p_tie_break,
    p_group_id
  );

  if exists (
    select 1
    from pg_catalog.unnest(v_invitee_ids) invitee_id
    where not app.may_invite_to_contest(
      v_contest_id,
      v_caller_id,
      invitee_id
    )
  ) then
    raise exception 'one or more invitees are not eligible'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.contest_participants (
    contest_id,
    user_id,
    status,
    invited_by
  )
  select
    v_contest_id,
    invitee_id,
    'invited'::public.contest_participant_status,
    v_caller_id
  from pg_catalog.unnest(v_invitee_ids) invitee_id;

  insert into app.contest_creation_requests (
    actor_id,
    request_id,
    payload_hash,
    contest_id
  )
  values (
    v_caller_id,
    p_request_id,
    v_payload_hash,
    v_contest_id
  );

  return v_contest_id;
end;
$function$;

comment on function app.create_contest_unchecked(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, smallint, public.contest_tie_break, uuid
) is
  'Create a contest and enrol its author. The only way a contest row comes into being.';
comment on function public.create_contest_with_invites_v1(
  uuid, text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid[], smallint, public.contest_tie_break, uuid
) is
  'Atomically creates immutable contest terms, enrols the author, and invites an initial roster under a caller-scoped idempotency UUID.';

revoke all on function app.create_contest_unchecked(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, smallint, public.contest_tie_break, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.create_contest(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, smallint, public.contest_tie_break, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.create_contest_with_invites_v1(
  uuid, text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid[], smallint, public.contest_tie_break, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.create_contest(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, smallint, public.contest_tie_break, uuid
) to authenticated;
grant execute on function public.create_contest_with_invites_v1(
  uuid, text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid[], smallint, public.contest_tie_break, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- Existing functions that read or wrote a nomination or an obligation. Each
-- body is the current definition with only the charity path removed.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.assert_participant_matches_challenge_model()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_model      public.challenge_model;
  v_created_by uuid;
begin
  select contest.challenge_model, contest.created_by
    into v_model, v_created_by
  from public.contests contest
  where contest.id = new.contest_id;

  if v_model is null then
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_model = 'personal_accountability' then
    if v_created_by is null or new.user_id <> v_created_by then
      raise exception 'a personal challenge may contain only its owner'
        using errcode = 'restrict_violation';
    end if;
    if new.status <> 'accepted' then
      raise exception 'a personal challenge owner is enrolled as accepted'
        using errcode = 'restrict_violation';
    end if;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION app.build_contest_integrity_input_v1(p_contest_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
            'timezone', participant.timezone
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
$function$;
CREATE OR REPLACE FUNCTION public.create_personal_challenge_v1(request_id uuid, cadence contest_cadence, target_steps integer, commitment_amount_minor integer, timezone text, requested_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_id               uuid := $1;
  v_cadence                  public.contest_cadence := $2;
  v_target_steps             integer := $3;
  v_commitment_amount_minor  integer := $4;
  v_timezone                 text := $5;
  v_requested_starts_at      timestamptz := $6;
  v_actor_id                 uuid;
  v_payload_hash             bytea;
  v_existing                 app.personal_challenge_creation_requests;
  v_challenge_id             uuid;
  v_now                      timestamptz;
  v_local_now                timestamp;
  v_local_start              timestamp;
  v_start_date               date;
  v_starts_at                timestamptz;
  v_ends_at                  timestamptz;
  v_starts_now               boolean := false;
  v_previous_start_timezone  text;
begin
  v_actor_id := app.require_active_caller();
  v_now := clock_timestamp();

  if v_request_id is null then
    raise exception 'request UUID is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_cadence is null then
    raise exception 'cadence is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_target_steps is null or v_target_steps not between 1 and 1000000 then
    raise exception 'target steps must be a whole number from 1 through 1000000'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_commitment_amount_minor not in (1000, 2000, 3000, 4000, 5000) then
    raise exception 'commitment must be one of the five Stage A presets'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names zone
       where zone.name = v_timezone
     )
  then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_local_now := v_now at time zone v_timezone;

  if v_requested_starts_at is not null then
    if not pg_catalog.isfinite(v_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := v_requested_starts_at at time zone v_timezone;
    v_starts_now :=
      v_local_start::date = v_local_now::date
      and v_requested_starts_at <= v_now
      and extract(second from v_local_start) = 0;

    if not v_starts_now then
      if extract(minute from v_local_start) <> 0
         or extract(second from v_local_start) <> 0
      then
        raise exception
          'a chosen start must be start-now on the current local date or a whole local hour'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_requested_starts_at <= v_now then
        raise exception 'a chosen start must be in the future'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_requested_starts_at > v_now + interval '90 days' then
        raise exception 'a chosen start must be within 90 days'
          using errcode = 'invalid_parameter_value';
      end if;
    end if;
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      (
        pg_catalog.jsonb_build_object(
          'kind', 'personal_accountability_v1',
          'cadence', v_cadence::text,
          'target_steps', v_target_steps,
          'commitment_amount_minor', v_commitment_amount_minor,
          'currency', 'USD',
          'settlement_mode', 'test_only',
          'terms_version', 'personal-v1',
          'timezone', v_timezone
        )
        || case
             when v_requested_starts_at is null then '{}'::jsonb
             else pg_catalog.jsonb_build_object(
               'requested_starts_at',
               extract(epoch from v_requested_starts_at)::bigint
             )
           end
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select request.* into v_existing
  from app.personal_challenge_creation_requests request
  where request.actor_id = v_actor_id
    and request.request_id = v_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception 'request UUID already used with different personal terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  if exists (
    select 1
    from public.personal_eligibility_holds hold
    where hold.user_id = v_actor_id
      and hold.cleared_at is null
  ) then
    raise exception 'a fresh trusted diagnostic is required before another challenge'
      using errcode = 'restrict_violation';
  end if;

  if v_requested_starts_at is null then
    v_start_date := v_local_now::date + 1;
    v_starts_at := v_start_date::timestamp at time zone v_timezone;
  elsif v_starts_now then
    v_start_date := v_local_now::date;
    v_starts_at := v_start_date::timestamp at time zone v_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := v_requested_starts_at;
  end if;

  v_ends_at := (v_start_date + 7)::timestamp at time zone v_timezone;

  if v_starts_now then
    v_previous_start_timezone := pg_catalog.current_setting(
      'app.personal_start_now_timezone',
      true
    );
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      v_timezone,
      true
    );
  end if;

  insert into public.contests (
    title, group_id, created_by, challenge_model, metric, cadence,
    target_value, stake_amount_cents, tie_break, starts_at, ends_at,
    max_participants
  )
  values (
    '7-Day Personal Accountability', null, v_actor_id,
    'personal_accountability', 'steps', v_cadence, v_target_steps,
    v_commitment_amount_minor, 'void', v_starts_at, v_ends_at, 1
  )
  returning id into v_challenge_id;

  if v_starts_now then
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      coalesce(v_previous_start_timezone, ''),
      true
    );
  end if;

  insert into public.contest_participants (
    contest_id, user_id, status, timezone
  )
  values (v_challenge_id, v_actor_id, 'accepted', v_timezone);

  insert into public.personal_challenge_terms (
    challenge_id, user_id, cadence, target_steps,
    commitment_amount_minor, currency, settlement_mode, terms_version,
    timezone, agreed_at, evidence_cutoff
  )
  values (
    v_challenge_id, v_actor_id, v_cadence, v_target_steps,
    v_commitment_amount_minor, 'USD', 'test_only', 'personal-v1',
    v_timezone, v_now, v_ends_at + interval '24 hours'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id, request_id, payload_hash, challenge_id
  )
  values (v_actor_id, v_request_id, v_payload_hash, v_challenge_id);

  if v_starts_now then
    update public.contests contest
    set status = 'active', activated_at = v_now
    where contest.id = v_challenge_id;
  end if;

  return v_challenge_id;
end;
$function$;
CREATE OR REPLACE FUNCTION app.create_personal_challenge_v2_unchecked(p_actor_id uuid, p_request_id uuid, p_cadence contest_cadence, p_target_steps integer, p_commitment_amount_minor integer, p_timezone text, p_requested_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload_hash bytea;
  v_legacy_payload_hash bytea;
  v_existing app.personal_challenge_creation_requests;
  v_challenge_id uuid;
  v_now timestamptz;
  v_local_now timestamp;
  v_local_start timestamp;
  v_start_date date;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_starts_now boolean := false;
  v_previous_start_timezone text;
begin
  if p_actor_id is null then
    raise exception 'an active owner is required'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_actor_id]);
  v_now := clock_timestamp();

  if p_request_id is null then
    raise exception 'request UUID is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_cadence is null then
    raise exception 'cadence is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_target_steps is null or p_target_steps not between 1 and 1000000 then
    raise exception 'target steps must be a whole number from 1 through 1000000'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_commitment_amount_minor not in (1000, 2000, 3000, 4000, 5000) then
    raise exception 'commitment must be one of the five test presets'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names zone
       where zone.name = p_timezone
     )
  then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_local_now := v_now at time zone p_timezone;

  if p_requested_starts_at is not null then
    if not pg_catalog.isfinite(p_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := p_requested_starts_at at time zone p_timezone;
    v_starts_now :=
      v_local_start::date = v_local_now::date
      and p_requested_starts_at <= v_now
      and extract(second from v_local_start) = 0;

    if not v_starts_now then
      if extract(minute from v_local_start) <> 0
         or extract(second from v_local_start) <> 0
      then
        raise exception
          'a chosen start must be start-now on the current local date or a whole local hour'
          using errcode = 'invalid_parameter_value';
      end if;
      if p_requested_starts_at <= v_now
         or p_requested_starts_at > v_now + interval '90 days'
      then
        raise exception 'a chosen start must be in the future and within 90 days'
          using errcode = 'invalid_parameter_value';
      end if;
    end if;
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_accountability_v2',
        'cadence', p_cadence::text,
        'target_steps', p_target_steps,
        'commitment_amount_minor', p_commitment_amount_minor,
        'currency', 'USD',
        'settlement_mode', 'test_only',
        'terms_version', 'personal-v2',
        'timezone', p_timezone,
        'requested_starts_at_epoch', case
          when p_requested_starts_at is null then null
          else extract(epoch from p_requested_starts_at)::bigint
        end,
        'step_data_policy', 'healthkit_nonmanual_daily_v1'
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- A mandatory v2 build may retry the exact request that originally created
  -- a now-cut-over v1 challenge. Reconstruct the historical request identity
  -- so that lost-response retry remains idempotent without accepting changed
  -- terms. The frozen row below must still match every caller input.
  v_legacy_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      (
        pg_catalog.jsonb_build_object(
          'kind', 'personal_accountability_v1',
          'cadence', p_cadence::text,
          'target_steps', p_target_steps,
          'commitment_amount_minor', p_commitment_amount_minor,
          'currency', 'USD',
          'settlement_mode', 'test_only',
          'terms_version', 'personal-v1',
          'timezone', p_timezone
        )
        || case
             when p_requested_starts_at is null then '{}'::jsonb
             else pg_catalog.jsonb_build_object(
               'requested_starts_at',
               extract(epoch from p_requested_starts_at)::bigint
             )
           end
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select request.* into v_existing
  from app.personal_challenge_creation_requests request
  where request.actor_id = p_actor_id
    and request.request_id = p_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash not in (v_payload_hash, v_legacy_payload_hash)
       or not exists (
         select 1
         from public.personal_challenge_terms terms
         join public.contests contest
           on contest.id = terms.challenge_id
         where terms.challenge_id = v_existing.challenge_id
           and terms.user_id = p_actor_id
           and terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
           and terms.cadence = p_cadence
           and terms.target_steps = p_target_steps
           and terms.commitment_amount_minor = p_commitment_amount_minor
           and terms.currency = 'USD'
           and terms.settlement_mode = 'test_only'
           and terms.timezone = p_timezone
           and (
             (p_requested_starts_at is null and contest.starts_at is not null)
             or (
               v_starts_now
               and contest.starts_at = (
                 v_local_now::date::timestamp at time zone p_timezone
               )
             )
             or (
               not v_starts_now
               and contest.starts_at = p_requested_starts_at
             )
           )
       )
    then
      raise exception 'request UUID already used with different personal terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  perform app.retire_personal_eligibility_holds_v2(p_actor_id, v_now);

  if p_requested_starts_at is null then
    v_start_date := v_local_now::date + 1;
    v_starts_at := v_start_date::timestamp at time zone p_timezone;
  elsif v_starts_now then
    v_start_date := v_local_now::date;
    v_starts_at := v_start_date::timestamp at time zone p_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := p_requested_starts_at;
  end if;
  v_ends_at := (v_start_date + 7)::timestamp at time zone p_timezone;

  if v_starts_now then
    v_previous_start_timezone := pg_catalog.current_setting(
      'app.personal_start_now_timezone',
      true
    );
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      p_timezone,
      true
    );
  end if;

  insert into public.contests (
    title,
    group_id,
    created_by,
    challenge_model,
    metric,
    cadence,
    target_value,
    stake_amount_cents,
    tie_break,
    starts_at,
    ends_at,
    max_participants
  )
  values (
    '7-Day Personal Accountability',
    null,
    p_actor_id,
    'personal_accountability',
    'steps',
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    'void',
    v_starts_at,
    v_ends_at,
    1
  )
  returning id into v_challenge_id;

  if v_starts_now then
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      coalesce(v_previous_start_timezone, ''),
      true
    );
  end if;

  insert into public.contest_participants (
    contest_id, user_id, status, timezone
  )
  values (
    v_challenge_id, p_actor_id, 'accepted', p_timezone
  );

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
    step_data_policy
  )
  values (
    v_challenge_id,
    p_actor_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    'USD',
    'test_only',
    'personal-v2',
    p_timezone,
    v_now,
    v_ends_at + interval '24 hours',
    'healthkit_nonmanual_daily_v1'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id, request_id, payload_hash, challenge_id
  )
  values (
    p_actor_id, p_request_id, v_payload_hash, v_challenge_id
  );

  if v_starts_now then
    update public.contests contest
    set status = 'active', activated_at = v_now
    where contest.id = v_challenge_id;
  end if;

  return v_challenge_id;
end;
$function$;
CREATE OR REPLACE FUNCTION app.enforce_contest_participant_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contest      record;
  v_is_creator   boolean;
begin
  -- Definer rights matter twice over: this reads contests regardless of the
  -- acting user's RLS visibility, and the capacity trigger's count below would
  -- otherwise be silently narrowed to rows the caller can see.
  select status, created_by, starts_at
    into v_contest
  from public.contests
  where id = new.contest_id;

  if v_contest is null then
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  v_is_creator := v_contest.created_by is not null
                  and v_contest.created_by = new.user_id;

  -- ---------------------------------------------------------------------
  -- Insert: only into a pending contest, and only as 'invited' unless this
  -- is the author enrolling themselves through create_contest().
  -- ---------------------------------------------------------------------
  if tg_op = 'INSERT' then
    if v_contest.status <> 'pending' then
      raise exception
        'cannot add a participant to a contest with status %; the roster closed when it left pending',
        v_contest.status
        using errcode = 'restrict_violation';
    end if;

    if new.status = 'accepted' then
      if not v_is_creator then
        raise exception 'a participant joins as invited and accepts afterwards'
          using errcode = 'restrict_violation';
      end if;
    elsif new.status <> 'invited' then
      raise exception 'a new participant row must be invited, not %', new.status
        using errcode = 'restrict_violation';
    end if;

    if new.status = 'accepted' then
      new.accepted_at := coalesce(new.accepted_at, now());
    end if;

    return new;
  end if;

  -- ---------------------------------------------------------------------
  -- Update
  -- ---------------------------------------------------------------------
  if v_contest.status <> 'pending' then
    -- Nothing about a roster is writable once the window has opened. Not the
    -- status, not the timezone, not anything: this is the freeze.
    --
    -- Two columns are excluded from the comparison rather than being writable.
    -- `updated_at` is stamped by a later trigger. `invited_by` carries
    -- `on delete set null`, so leaving it in would make deleting the inviter's
    -- account fail against every contest they ever started that has since
    -- opened — the same collision app.forbid_column_reassignment() exists for.
    -- Neither is reachable by a client: the column grant covers exactly
    -- (status, timezone), and repointing invited_by still raises
    -- from the reassignment trigger.
    if to_jsonb(new) - 'updated_at' - 'invited_by'
         is distinct from to_jsonb(old) - 'updated_at' - 'invited_by'
    then
      raise exception
        'the roster of this contest is frozen (contest status %)', v_contest.status
        using errcode = 'restrict_violation';
    end if;
    return new;
  end if;

  -- Frozen at accept. Checked before the transition rules so that a caller
  -- cannot slip a new zone in alongside a legal status change.
  if old.timezone is not null and new.timezone is distinct from old.timezone then
    raise exception 'contest_participants.timezone is frozen at accept'
      using errcode = 'restrict_violation';
  end if;

  if new.status <> old.status then
    if not (
      -- 'lapsed' is in this list for the system's benefit, not the client's;
      -- see the ownership check below.
      (old.status = 'invited' and new.status in ('accepted', 'declined', 'lapsed'))
      -- Before the window opens nothing is at stake yet, so an accepted
      -- participant may still step out — except the author.
      or (old.status = 'accepted' and new.status = 'withdrawn')
    ) then
      raise exception 'participant status cannot move from % to %',
        old.status, new.status
        using errcode = 'restrict_violation';
    end if;

    -- Whether the *caller* is allowed to write 'lapsed' cannot be decided here;
    -- see app.forbid_client_lapse() for why it needs its own invoker-rights
    -- trigger.
    if new.status = 'withdrawn' and v_is_creator then
      raise exception
        'the author of a contest cannot withdraw from it; cancel the contest instead'
        using errcode = 'restrict_violation';
    end if;

    if new.status = 'accepted' then
      new.accepted_at := coalesce(new.accepted_at, now());
    else
      new.accepted_at := null;
    end if;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION app.validate_personal_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contest public.contests;
begin
  select contest.* into v_contest
  from public.contests contest
  where contest.id = new.challenge_id;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from new.user_id
     or v_contest.metric <> 'steps'
     or v_contest.cadence <> new.cadence
     or v_contest.target_value <> new.target_steps
     or v_contest.stake_amount_cents <> new.commitment_amount_minor
     or v_contest.max_participants <> 1
     or v_contest.group_id is not null
     or v_contest.tie_break <> 'void'
  then
    raise exception 'personal terms do not match the immutable challenge row'
      using errcode = 'restrict_violation';
  end if;

  if new.evidence_cutoff <> v_contest.ends_at + interval '24 hours' then
    raise exception 'personal evidence cutoff must be exactly 24 hours after the seventh day'
      using errcode = 'invalid_parameter_value';
  end if;

  if not exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = new.challenge_id
      and participant.user_id = new.user_id
      and participant.status = 'accepted'
      and participant.timezone = new.timezone
  ) then
    raise exception 'personal terms require the accepted owner participant'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.get_contest_standings_v1(p_contest_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id  uuid;
  v_snapshot   public.contest_standing_snapshots;
  v_result     public.contest_results;
  v_standings  jsonb;
  v_result_doc jsonb;
begin
  if p_contest_id is null then
    raise exception 'contest id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_caller_id := app.require_active_caller();

  if not exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = p_contest_id
      and participant.user_id = v_caller_id
      and participant.status = 'accepted'
  ) then
    raise exception 'only an accepted participant may read standings'
      using errcode = 'insufficient_privilege';
  end if;

  select snapshot.*
    into v_snapshot
  from public.contest_standing_snapshots snapshot
  join public.contests contest on contest.id = snapshot.contest_id
  where snapshot.contest_id = p_contest_id
    and (
      (contest.status = 'finalized' and snapshot.phase = 'final')
      or (contest.status = 'active' and snapshot.phase = 'provisional')
    )
  order by
    case when snapshot.phase = 'final' then 0 else 1 end,
    snapshot.as_of desc,
    snapshot.created_at desc,
    snapshot.id desc
  limit 1;

  if v_snapshot.id is null then
    return null;
  end if;

  if v_snapshot.result_id is not null then
    select result.*
      into v_result
    from public.contest_results result
    where result.id = v_snapshot.result_id
      and result.contest_id = p_contest_id;

    v_result_doc := jsonb_strip_nulls(
      jsonb_build_object(
        'id', v_result.id,
        'kind', v_result.kind,
        'reason', v_result.reason,
        'winner_participant_id', v_result.winner_participant_id,
        'evidence_cutoff', v_result.evidence_cutoff,
        'finalized_at', v_result.finalized_at
      )
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'participant_id', entry.participant_id,
          'display_name',
            case
              when profile.deleted_at is not null then 'Former participant'
              else coalesce(nullif(profile.display_name, ''), 'Participant')
            end,
          'handle',
            case
              when profile.deleted_at is not null then null
              else profile.handle::text
            end,
          'display_order', entry.display_order,
          'rank', entry.rank,
          'qualified', entry.qualified,
          'total', entry.total,
          'qualifying_days', entry.qualifying_days,
          'scoreable_days', entry.scoreable_days,
          'day_rate', entry.day_rate,
          'reached_target_at', entry.reached_target_at,
          'integrity_score',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.integrity_score
              else null
            end,
          'integrity_flags',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.integrity_flags
              else null
            end,
          'rationale',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.rationale
              else null
            end
        )
      )
      order by entry.display_order
    ),
    '[]'::jsonb
  )
    into v_standings
  from public.contest_standing_entries entry
  join public.profiles profile on profile.id = entry.participant_id
  where entry.snapshot_id = v_snapshot.id
    and entry.contest_id = p_contest_id;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'contest_id', p_contest_id,
      'snapshot_id', v_snapshot.id,
      'phase', v_snapshot.phase,
      'reason', v_snapshot.reason,
      'as_of', v_snapshot.as_of,
      'scoring_version', v_snapshot.scoring_version,
      'integrity_configuration_version',
        v_snapshot.integrity_configuration_version,
      'result', v_result_doc,
      'standings', v_standings
    )
  );
end;
$function$;
CREATE OR REPLACE FUNCTION public.publish_contest_standings_v1(p_contest_id uuid, p_as_of timestamp with time zone, p_scoring_version text, p_integrity_configuration_version text, p_standings jsonb, p_outcome jsonb DEFAULT NULL::jsonb, p_evidence_cutoff timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contest              public.contests;
  v_phase                public.contest_standings_phase;
  v_reason               public.contest_standings_reason;
  v_accepted_ids         uuid[];
  v_supplied_ids         uuid[];
  v_outcome_ids          uuid[];
  v_accepted_count       integer;
  v_supplied_count       integer;
  v_distinct_count       integer;
  v_qualified_count      integer;
  v_canonical_standings  jsonb;
  v_canonical_outcome    jsonb;
  v_input_digest         bytea;
  v_existing_snapshot_id uuid;
  v_snapshot_id          uuid;
  v_result_id            uuid;
  v_result_kind          public.contest_result_kind;
  v_result_reason        public.contest_result_reason;
  v_winner_id            uuid;
  v_grace_close          timestamptz;
  v_finalized_at         timestamptz;
begin
  if p_contest_id is null
     or p_as_of is null
     or p_scoring_version is null
     or p_integrity_configuration_version is null
     or p_standings is null
  then
    raise exception
      'contest, as-of, scoring version, integrity version, and standings are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if not pg_catalog.isfinite(p_as_of)
     or p_as_of > clock_timestamp() + interval '1 second'
  then
    raise exception 'standings as-of must be a finite server-present instant'
      using errcode = 'invalid_parameter_value';
  end if;

  if char_length(p_scoring_version) not between 1 and 80
     or char_length(p_integrity_configuration_version) not between 1 and 80
  then
    raise exception 'scoring and integrity versions must contain 1 to 80 characters'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_typeof(p_standings) <> 'array'
     or jsonb_array_length(p_standings) not between 2 and 20
  then
    raise exception 'standings must be a complete array of 2 to 20 participants'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    where jsonb_typeof(item) <> 'object'
       or not (
         item ?& array[
           'participant_id',
           'display_order',
           'rank',
           'qualified',
           'total',
           'qualifying_days',
           'scoreable_days',
           'day_rate',
           'reached_target_at',
           'integrity_score',
           'integrity_flags',
           'rationale'
         ]
       )
       or item - array[
         'participant_id',
         'display_order',
         'rank',
         'qualified',
         'total',
         'qualifying_days',
         'scoreable_days',
         'day_rate',
         'reached_target_at',
         'integrity_score',
         'integrity_flags',
         'rationale'
       ]::text[] <> '{}'::jsonb
       or jsonb_typeof(item -> 'integrity_flags') <> 'array'
       or jsonb_typeof(item -> 'rationale') <> 'array'
  ) then
    raise exception 'every standing must use the exact version-1 field set'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    cross join lateral jsonb_array_elements(item -> 'integrity_flags') flag
    where jsonb_typeof(flag) <> 'string'
       or char_length(flag #>> '{}') not between 1 and 80
  ) then
    raise exception 'integrity flags must be bounded rule-code strings'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    cross join lateral jsonb_array_elements(item -> 'rationale') rationale
    where jsonb_typeof(rationale) <> 'object'
       or not (rationale ?& array['code', 'summary', 'points'])
       or rationale - array['code', 'summary', 'points']::text[] <> '{}'::jsonb
       or jsonb_typeof(rationale -> 'code') <> 'string'
       or char_length(rationale ->> 'code') not between 1 and 80
       or jsonb_typeof(rationale -> 'summary') <> 'string'
       or char_length(rationale ->> 'summary') not between 1 and 240
       or jsonb_typeof(rationale -> 'points') <> 'number'
       or (rationale ->> 'points')::numeric not between -100 and 100
  ) then
    raise exception
      'rationale may contain only bounded code, summary, and points fields'
      using errcode = 'invalid_parameter_value';
  end if;

  select jsonb_agg(item order by (item ->> 'display_order')::integer)
    into v_canonical_standings
  from jsonb_array_elements(p_standings) item;

  -- Finalization's table locks linearize against every INSERT already in
  -- progress and every INSERT that begins before the contest status flips.
  if p_outcome is not null then
    lock table public.metric_snapshots,
               public.geofence_checkins
      in share row exclusive mode;
  end if;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = p_contest_id
  for update;

  if v_contest.id is null then
    raise exception 'contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  select
    array_agg(participant.user_id order by participant.user_id),
    count(*)::integer
    into v_accepted_ids, v_accepted_count
  from public.contest_participants participant
  where participant.contest_id = p_contest_id
    and participant.status = 'accepted';

  with supplied as (
    select *
    from jsonb_to_recordset(v_canonical_standings) as entry (
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
  )
  select
    array_agg(participant_id order by participant_id),
    count(*)::integer,
    count(distinct participant_id)::integer,
    count(*) filter (where qualified)::integer
    into
      v_supplied_ids,
      v_supplied_count,
      v_distinct_count,
      v_qualified_count
  from supplied;

  if v_accepted_count not between 2 and 20
     or v_supplied_count <> v_accepted_count
     or v_distinct_count <> v_supplied_count
     or v_supplied_ids is distinct from v_accepted_ids
  then
    raise exception 'standings must exactly match the complete accepted roster'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(v_canonical_standings) as entry (
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
    where participant_id is null
       or display_order not between 1 and v_accepted_count
       or rank not between 1 and v_accepted_count
       or qualified is null
       or total is null
       or total < 0
       or qualifying_days not between 0 and 366
       or scoreable_days not between 0 and 366
       or qualifying_days > scoreable_days
       or day_rate not between 0 and 1
       or reached_target_at is not null
          and (
            not pg_catalog.isfinite(reached_target_at)
            or reached_target_at < v_contest.starts_at
            or reached_target_at > v_contest.ends_at
          )
       or integrity_score not between 0 and 100
  ) then
    raise exception 'standing values are outside the version-1 domain'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    with supplied as (
      select *
      from jsonb_to_recordset(v_canonical_standings) as entry (
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
    ),
    expected as (
      select
        participant_id,
        display_order,
        rank,
        case
          when v_contest.cadence = 'daily'
            then rank() over (order by day_rate desc, total desc)
          else rank() over (order by total desc)
        end as expected_rank,
        case
          when v_contest.cadence = 'daily'
            then row_number() over (
              order by
                day_rate desc,
                total desc,
                reached_target_at asc nulls last,
                participant_id
            )
          else row_number() over (
            order by
              total desc,
              reached_target_at asc nulls last,
              participant_id
          )
        end as expected_order
      from supplied
    )
    select 1
    from expected
    where rank <> expected_rank
       or display_order <> expected_order
  ) then
    raise exception 'display order or competition rank contradicts the scoring output'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_contest.cadence = 'cumulative'
     and exists (
       select 1
       from jsonb_to_recordset(v_canonical_standings) as entry (
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
       where qualifying_days <> 0
          or scoreable_days <> 0
          or day_rate <> 0
     )
  then
    raise exception 'cumulative standings cannot carry daily-rate fields'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_outcome is null then
    v_phase := 'provisional';
    v_reason := case
      when p_as_of < v_contest.ends_at
        then 'live'::public.contest_standings_reason
      when p_as_of < v_contest.ends_at + app.ingest_grace_period()
        then 'awaiting_ingest'::public.contest_standings_reason
      else 'under_review'::public.contest_standings_reason
    end;

    if p_evidence_cutoff is not null then
      raise exception 'provisional standings cannot claim a frozen evidence cutoff'
        using errcode = 'invalid_parameter_value';
    end if;

    if v_contest.status <> 'active' then
      raise exception 'only an active contest may publish provisional standings'
        using errcode = 'restrict_violation';
    end if;

    v_canonical_outcome := null;
  else
    v_phase := 'final';
    v_reason := 'final';
    v_grace_close := v_contest.ends_at + app.ingest_grace_period();

    if p_evidence_cutoff is null
       or not pg_catalog.isfinite(p_evidence_cutoff)
       or p_evidence_cutoff <> v_grace_close
    then
      raise exception 'final evidence cutoff must equal the server ingest-grace close'
        using errcode = 'invalid_parameter_value';
    end if;

    if clock_timestamp() < v_grace_close or p_as_of < v_grace_close then
      raise exception 'a contest cannot finalize before ingest grace closes'
        using errcode = 'restrict_violation';
    end if;

    if jsonb_typeof(p_outcome) <> 'object'
       or jsonb_typeof(p_outcome -> 'kind') <> 'string'
       or jsonb_typeof(p_outcome -> 'reason') <> 'string'
    then
      raise exception 'final outcome must name one kind and reason'
        using errcode = 'invalid_parameter_value';
    end if;

    v_result_kind := (p_outcome ->> 'kind')::public.contest_result_kind;
    v_result_reason := (p_outcome ->> 'reason')::public.contest_result_reason;

    if v_result_kind = 'winner' then
      if not (p_outcome ?& array['kind', 'reason', 'participant_id'])
         or p_outcome - array['kind', 'reason', 'participant_id']::text[]
            <> '{}'::jsonb
      then
        raise exception 'winner outcome must use kind, reason, and participant_id'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := (p_outcome ->> 'participant_id')::uuid;

      if not (v_winner_id = any(v_accepted_ids))
         or not exists (
           select 1
           from jsonb_to_recordset(v_canonical_standings) as entry (
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
           where participant_id = v_winner_id
             and qualified
         )
      then
        raise exception 'winner must be one qualified accepted participant'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_result_reason = 'sole_qualifier' then
        if v_qualified_count <> 1 then
          raise exception 'sole-qualifier result requires exactly one qualifier'
            using errcode = 'invalid_parameter_value';
        end if;
      elsif v_result_reason = 'earliest_to_target' then
        if v_contest.tie_break <> 'earliest_to_target'
           or v_qualified_count < 2
        then
          raise exception 'earliest winner contradicts the agreed tie-break'
            using errcode = 'invalid_parameter_value';
        end if;

        if not exists (
          with qualified as (
            select
              participant_id,
              qualified,
              reached_target_at
            from jsonb_to_recordset(v_canonical_standings) as entry (
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
          )
          select 1
          from qualified candidate
          where candidate.participant_id = v_winner_id
            and candidate.qualified
            and candidate.reached_target_at is not null
            and not exists (
              select 1
              from qualified rival
              where rival.qualified
                and rival.participant_id <> candidate.participant_id
                and rival.reached_target_at is not null
                and rival.reached_target_at <= candidate.reached_target_at
            )
        ) then
          raise exception
            'earliest winner must be the unique earliest qualified participant'
            using errcode = 'invalid_parameter_value';
        end if;
      elsif v_result_reason = 'integrity_score' then
        if v_contest.tie_break <> 'integrity_score'
           or v_qualified_count < 2
        then
          raise exception 'integrity winner contradicts the agreed tie-break'
            using errcode = 'invalid_parameter_value';
        end if;

        if not exists (
          with qualified as (
            select
              participant_id,
              qualified,
              integrity_score
            from jsonb_to_recordset(v_canonical_standings) as entry (
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
          )
          select 1
          from qualified candidate
          where candidate.participant_id = v_winner_id
            and candidate.qualified
            and not exists (
              select 1
              from qualified rival
              where rival.qualified
                and rival.participant_id <> candidate.participant_id
                and rival.integrity_score >= candidate.integrity_score
            )
        ) then
          raise exception
            'integrity winner must have the unique highest qualified score'
            using errcode = 'invalid_parameter_value';
        end if;
      else
        raise exception 'winner result reason is invalid'
          using errcode = 'invalid_parameter_value';
      end if;

      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason,
        'participant_id', v_winner_id
      );
    elsif v_result_kind = 'all_donate' then
      if not (p_outcome ?& array['kind', 'reason', 'participant_ids'])
         or p_outcome - array['kind', 'reason', 'participant_ids']::text[]
            <> '{}'::jsonb
         or jsonb_typeof(p_outcome -> 'participant_ids') <> 'array'
      then
        raise exception
          'all-donate outcome must use kind, reason, and participant_ids'
          using errcode = 'invalid_parameter_value';
      end if;

      select array_agg((item #>> '{}')::uuid order by (item #>> '{}')::uuid)
        into v_outcome_ids
      from jsonb_array_elements(p_outcome -> 'participant_ids') item;

      if v_result_reason <> 'both_donate'
         or v_contest.tie_break <> 'both_donate'
         or v_qualified_count < 2
         or v_outcome_ids is distinct from v_accepted_ids
      then
        raise exception
          'all-donate must name the complete accepted roster and agreed tie-break'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason,
        'participant_ids', to_jsonb(v_accepted_ids)
      );
    elsif v_result_kind = 'void' then
      if not (p_outcome ?& array['kind', 'reason'])
         or p_outcome - array['kind', 'reason']::text[] <> '{}'::jsonb
         or not (
           (
             v_result_reason = 'no_qualifying_participant'
             and v_qualified_count = 0
           )
           or (
             v_result_reason = 'tie_break_void'
             and v_contest.tie_break = 'void'
             and v_qualified_count >= 2
           )
         )
      then
        raise exception 'void result contradicts qualification or the agreed tie-break'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason
      );
    elsif v_result_kind = 'inconclusive' then
      if not (p_outcome ?& array['kind', 'reason'])
         or p_outcome - array['kind', 'reason']::text[] <> '{}'::jsonb
         or v_result_reason <> 'tie_break_inconclusive'
         or v_contest.tie_break not in ('earliest_to_target', 'integrity_score')
         or v_qualified_count < 2
      then
        raise exception
          'M8.3c only accepts a deterministic tie-break inconclusive result'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_contest.tie_break = 'earliest_to_target'
         and exists (
           with qualified as (
             select
               participant_id,
               qualified,
               reached_target_at
             from jsonb_to_recordset(v_canonical_standings) as entry (
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
           )
           select 1
           from qualified candidate
           where candidate.qualified
             and candidate.reached_target_at is not null
             and not exists (
               select 1
               from qualified rival
               where rival.qualified
                 and rival.participant_id <> candidate.participant_id
                 and rival.reached_target_at is not null
                 and rival.reached_target_at <= candidate.reached_target_at
             )
         )
      then
        raise exception
          'inconclusive result contradicts a unique earliest qualifier'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_contest.tie_break = 'integrity_score'
         and exists (
           with qualified as (
             select
               participant_id,
               qualified,
               integrity_score
             from jsonb_to_recordset(v_canonical_standings) as entry (
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
           )
           select 1
           from qualified candidate
           where candidate.qualified
             and not exists (
               select 1
               from qualified rival
               where rival.qualified
                 and rival.participant_id <> candidate.participant_id
                 and rival.integrity_score >= candidate.integrity_score
             )
         )
      then
        raise exception
          'inconclusive result contradicts a unique integrity-score winner'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason
      );
    end if;

    if exists (
      select 1
      from public.evidence_quarantine_status quarantine
      where quarantine.contest_id = p_contest_id
        and quarantine.state <> 'approved'
    ) then
      raise exception 'evidence review is unresolved'
        using errcode = 'restrict_violation';
    end if;
  end if;

  v_input_digest := extensions.digest(
    jsonb_build_object(
      'contest_id', p_contest_id,
      'phase', v_phase,
      'as_of', p_as_of,
      'scoring_version', p_scoring_version,
      'integrity_configuration_version',
        p_integrity_configuration_version,
      'evidence_cutoff', p_evidence_cutoff,
      'standings', v_canonical_standings,
      'outcome', v_canonical_outcome
    )::text,
    'sha256'
  );

  select snapshot.id
    into v_existing_snapshot_id
  from public.contest_standing_snapshots snapshot
  where snapshot.contest_id = p_contest_id
    and snapshot.input_digest = v_input_digest;

  if found then
    return v_existing_snapshot_id;
  end if;

  if v_phase = 'final' and v_contest.status = 'finalized' then
    raise exception 'contest already has a different immutable result'
      using errcode = 'unique_violation';
  end if;

  if v_phase = 'final' and v_contest.status <> 'active' then
    raise exception 'only an active contest may finalize'
      using errcode = 'restrict_violation';
  end if;

  if v_phase = 'final' then
    v_finalized_at := clock_timestamp();

    insert into public.contest_results (
      contest_id,
      version,
      kind,
      reason,
      winner_participant_id,
      evidence_cutoff,
      scoring_version,
      integrity_configuration_version,
      input_digest,
      finalized_at
    )
    values (
      p_contest_id,
      1,
      v_result_kind,
      v_result_reason,
      v_winner_id,
      p_evidence_cutoff,
      p_scoring_version,
      p_integrity_configuration_version,
      v_input_digest,
      v_finalized_at
    )
    returning id into v_result_id;
  end if;

  insert into public.contest_standing_snapshots (
    contest_id,
    phase,
    reason,
    as_of,
    scoring_version,
    integrity_configuration_version,
    evidence_cutoff,
    result_id,
    input_digest
  )
  values (
    p_contest_id,
    v_phase,
    v_reason,
    p_as_of,
    p_scoring_version,
    p_integrity_configuration_version,
    p_evidence_cutoff,
    v_result_id,
    v_input_digest
  )
  returning id into v_snapshot_id;

  insert into public.contest_standing_entries (
    snapshot_id,
    contest_id,
    participant_id,
    display_order,
    rank,
    qualified,
    total,
    qualifying_days,
    scoreable_days,
    day_rate,
    reached_target_at,
    integrity_score,
    integrity_flags,
    rationale
  )
  select
    v_snapshot_id,
    p_contest_id,
    entry.participant_id,
    entry.display_order,
    entry.rank,
    entry.qualified,
    entry.total,
    entry.qualifying_days,
    entry.scoreable_days,
    entry.day_rate,
    entry.reached_target_at,
    entry.integrity_score,
    entry.integrity_flags,
    entry.rationale
  from jsonb_to_recordset(v_canonical_standings) as entry (
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
  order by entry.display_order;

  if v_phase = 'final' then
    update public.contests
    set status = 'finalized'
    where id = p_contest_id;

    perform app.ensure_contest_workflow_scope(p_contest_id);
  end if;

  return v_snapshot_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_challenge_summaries_v1()
 RETURNS TABLE(contest_id uuid, title text, created_by uuid, metric contest_metric, cadence contest_cadence, target_value numeric, stake_amount_cents integer, tie_break contest_tie_break, starts_at timestamp with time zone, ends_at timestamp with time zone, contest_status contest_status, max_participants smallint, caller_status contest_participant_status, caller_timezone text, accepted_count bigint, invited_count bigint, declined_count bigint, withdrawn_count bigint, lapsed_count bigint, author_profile jsonb, accepted_profiles jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid;
begin
  v_caller_id := app.require_active_caller();

  return query
  select
    contest.id,
    contest.title,
    contest.created_by,
    contest.metric,
    contest.cadence,
    contest.target_value,
    contest.stake_amount_cents,
    contest.tie_break,
    contest.starts_at,
    contest.ends_at,
    contest.status,
    contest.max_participants,
    caller_participant.status,
    caller_participant.timezone,
    participant_counts.accepted_count,
    participant_counts.invited_count,
    participant_counts.declined_count,
    participant_counts.withdrawn_count,
    participant_counts.lapsed_count,
    case
      when author.id is null then null
      when caller_participant.status = 'accepted'
        or author.id = v_caller_id
      then pg_catalog.jsonb_build_object(
        'id', author.id,
        'handle', case
          when author.deleted_at is null then author.handle::text
          else null
        end,
        'display_name', case
          when author.deleted_at is null then author.display_name
          else 'Deleted member'
        end,
        'is_deleted', author.deleted_at is not null
      )
      when app.is_active_actor(author.id)
        and not app.is_blocked_either_way(v_caller_id, author.id)
        and (
          app.is_friend(v_caller_id, author.id)
          or app.shares_group(v_caller_id, author.id)
        )
      then pg_catalog.jsonb_build_object(
        'id', author.id,
        'handle', author.handle::text,
        'display_name', author.display_name,
        'is_deleted', false
      )
      else null
    end,
    case
      when caller_participant.status <> 'accepted' then '[]'::jsonb
      else coalesce(
        (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'id', accepted_profile.id,
              'handle', case
                when accepted_profile.deleted_at is null
                  then accepted_profile.handle::text
                else null
              end,
              'display_name', case
                when accepted_profile.deleted_at is null
                  then accepted_profile.display_name
                else 'Deleted member'
              end,
              'is_deleted', accepted_profile.deleted_at is not null
            )
            order by
              case
                when accepted_participant.user_id = contest.created_by then 0
                else 1
              end,
              accepted_participant.accepted_at,
              accepted_participant.user_id
          )
          from public.contest_participants accepted_participant
          join public.profiles accepted_profile
            on accepted_profile.id = accepted_participant.user_id
          where accepted_participant.contest_id = contest.id
            and accepted_participant.status = 'accepted'
        ),
        '[]'::jsonb
      )
    end
  from public.contest_participants caller_participant
  join public.contests contest
    on contest.id = caller_participant.contest_id
  left join public.profiles author
    on author.id = contest.created_by
  cross join lateral (
    select
      pg_catalog.count(*) filter (
        where participant.status = 'accepted'
      ) as accepted_count,
      pg_catalog.count(*) filter (
        where participant.status = 'invited'
      ) as invited_count,
      pg_catalog.count(*) filter (
        where participant.status = 'declined'
      ) as declined_count,
      pg_catalog.count(*) filter (
        where participant.status = 'withdrawn'
      ) as withdrawn_count,
      pg_catalog.count(*) filter (
        where participant.status = 'lapsed'
      ) as lapsed_count
    from public.contest_participants participant
    where participant.contest_id = contest.id
  ) participant_counts
  where caller_participant.user_id = v_caller_id
    and contest.challenge_model in (
      'legacy_social_contest',
      'social_accountability'
    )
  order by contest.starts_at, contest.id;
end;
$function$;

comment on function app.assert_participant_matches_challenge_model() is
  'Keeps participant cardinality compatible with the immutable challenge model.';
comment on function public.publish_personal_result_v1(uuid, uuid) is
  'service_role-only personal result publisher. It creates no standings, winner, payout, or obligation.';

-- ---------------------------------------------------------------------------
-- The charity schema itself.
-- ---------------------------------------------------------------------------
drop table public.donation_obligations;
drop type public.donation_obligation_kind;

drop trigger contest_participants_assert_charity on public.contest_participants;
drop function app.assert_charity_is_nominable();
alter table public.contest_participants drop column charity_id;

drop table public.charities;

-- ---------------------------------------------------------------------------
-- The legacy model no longer names a charity. Renaming the label keeps every
-- existing row, default and typed reference pointing at the same value.
-- ---------------------------------------------------------------------------
alter type public.challenge_model
  rename value 'legacy_charity_contest' to 'legacy_social_contest';

comment on column public.contests.challenge_model is
  'Immutable dispatcher. Existing and legacy-created rows are legacy_social_contest; personal_accountability has isolated terms and results; social_accountability is reserved for V2.';
comment on column public.contests.stake_amount_cents is
  'Per-loser stake of a legacy social contest, in USD cents (D4, D143).';
