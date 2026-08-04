-- Personal Accountability V1 -- a chosen start day and hour.
--
-- Creation derived the window as the next local midnight plus seven local
-- dates. That remains the default and remains exactly what an omitted start
-- means, but an owner may now name any future whole local hour instead --
-- including one later today, which is what makes the active path reachable
-- without waiting for a midnight to pass.
--
-- The chosen instant must land on a whole hour **in the frozen timezone**.
-- That is not cosmetic. `bucket_start` is a whole local hour, and
-- `app.personal_expected_coverage_buckets_v1` discards the partial hour a
-- 15:40 start would open, so the evidence for those twenty minutes could never
-- be delivered and the window would begin with a silently unscorable gap.
-- Aligning to the hour puts `starts_at` exactly on the ledger grid, which is
-- also why the client sends an instant rather than a local date and hour: a
-- timestamptz is unambiguous across a fall-back transition, where one local
-- wall-clock hour names two different instants.
--
-- `ends_at` stays the local midnight after the seventh local date, so the
-- seven dates `app.personal_daily_progress_v1` generates still cover every
-- expected bucket and the aggregate count cannot drift from the per-day
-- counts. The consequence is deliberate and visible: a challenge opening at
-- 15:00 has a first day that runs 15:00 to midnight. On a daily cadence that
-- is a shorter day to meet the same target. It is a frozen term like any
-- other, and the client states it before anyone confirms.
--
-- Nothing about admissibility, coverage, scoring, or settlement moves here.
-- The only behavioural change is which instant the window opens on.

drop function public.create_personal_challenge_v1(
  uuid,
  public.contest_cadence,
  integer,
  integer,
  text
);

create function public.create_personal_challenge_v1(
  request_id                uuid,
  cadence                   public.contest_cadence,
  target_steps              integer,
  commitment_amount_minor   integer,
  timezone                  text,
  requested_starts_at       timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_local_start              timestamp;
  v_start_date               date;
  v_starts_at                timestamptz;
  v_ends_at                  timestamptz;
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

  -- The chosen start is validated against the frozen timezone, before any
  -- other mutable state is read, so a refusal costs nothing and says why.
  if v_requested_starts_at is not null then
    if not pg_catalog.isfinite(v_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := v_requested_starts_at at time zone v_timezone;

    if extract(minute from v_local_start) <> 0
       or extract(second from v_local_start) <> 0
    then
      raise exception
        'a chosen start must land on a whole hour in the frozen timezone'
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

  -- An omitted start hashes exactly as it did before this migration, so a
  -- retry record written by an earlier client still matches byte for byte.
  -- The client-supplied value is hashed, never the resolved one: resolving
  -- the default twice either side of a local midnight would yield two
  -- different instants for one unchanged request.
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

  -- Exact committed retry precedes mutable eligibility/open-slot checks. The
  -- active-caller lock above still prevents a stale JWT replay after deletion.
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
    v_start_date := (v_now at time zone v_timezone)::date + 1;
    v_starts_at := v_start_date::timestamp at time zone v_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := v_requested_starts_at;
  end if;

  v_ends_at := (v_start_date + 7)::timestamp at time zone v_timezone;

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
    v_actor_id,
    'personal_accountability',
    'steps',
    v_cadence,
    v_target_steps,
    v_commitment_amount_minor,
    'void',
    v_starts_at,
    v_ends_at,
    1
  )
  returning id into v_challenge_id;

  insert into public.contest_participants (
    contest_id,
    user_id,
    status,
    timezone,
    charity_id
  )
  values (
    v_challenge_id,
    v_actor_id,
    'accepted',
    v_timezone,
    null
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
    evidence_cutoff
  )
  values (
    v_challenge_id,
    v_actor_id,
    v_cadence,
    v_target_steps,
    v_commitment_amount_minor,
    'USD',
    'test_only',
    'personal-v1',
    v_timezone,
    v_now,
    v_ends_at + interval '24 hours'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id,
    request_id,
    payload_hash,
    challenge_id
  )
  values (
    v_actor_id,
    v_request_id,
    v_payload_hash,
    v_challenge_id
  );

  return v_challenge_id;
end;
$$;

comment on function public.create_personal_challenge_v1(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) is
  'Atomic exact-retry Personal V1 creation. Server freezes test-only terms. An omitted start still means the next local midnight; a supplied start must be a future whole local hour within 90 days, and the seventh local date still closes at local midnight.';

revoke all on function public.create_personal_challenge_v1(
                         uuid,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         timestamptz
                       )
  from public, anon, authenticated, service_role;

grant execute on function public.create_personal_challenge_v1(
                           uuid,
                           public.contest_cadence,
                           integer,
                           integer,
                           text,
                           timestamptz
                         )
  to authenticated;
