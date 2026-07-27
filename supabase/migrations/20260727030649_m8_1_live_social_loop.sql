-- M8.1 -- bounded social cards and atomic, idempotent contest creation.
--
-- The app schema owns request-id bookkeeping. Clients receive only two
-- explicitly granted RPCs; neither the private table nor its payload hashes are
-- part of the Data API.

-- ===========================================================================
-- SECTION 1 -- Private contest-creation idempotency ledger
-- ===========================================================================

create table app.contest_creation_requests (
  actor_id     uuid not null
    references public.profiles (id) on delete cascade,
  request_id   uuid not null,
  payload_hash bytea not null,
  contest_id   uuid not null unique
    references public.contests (id) on delete cascade,
  created_at   timestamptz not null default now(),

  primary key (actor_id, request_id),
  constraint contest_creation_requests_hash_is_sha256
    check (octet_length(payload_hash) = 32)
);

comment on table app.contest_creation_requests is
  'Private M8.1 idempotency ledger. A caller/request UUID names exactly one immutable contest payload.';

revoke all on app.contest_creation_requests
  from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 2 -- Caller-bounded friendship cards
-- ===========================================================================

create function public.list_my_friendship_cards()
returns table (
  other_user_id uuid,
  handle        extensions.citext,
  display_name  text,
  status        public.friendship_status,
  requested_by  uuid,
  created_at    timestamptz,
  updated_at    timestamptz,
  accepted_at   timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid;
begin
  -- The lock is intentional even though this is a read. It closes the stale
  -- JWT race with account deletion before any relationship is disclosed.
  v_caller_id := app.require_active_caller();

  return query
  select
    other_profile.id,
    other_profile.handle,
    other_profile.display_name,
    friendship.status,
    friendship.requested_by,
    friendship.created_at,
    friendship.updated_at,
    friendship.accepted_at
  from public.friendships friendship
  join public.profiles other_profile
    on other_profile.id = case
      when friendship.user_a = v_caller_id then friendship.user_b
      else friendship.user_a
    end
  where v_caller_id in (friendship.user_a, friendship.user_b)
    and other_profile.deleted_at is null
    and app.is_active_actor(other_profile.id)
    and not app.is_blocked_either_way(v_caller_id, other_profile.id)
  order by
    case friendship.status
      when 'pending' then 0
      else 1
    end,
    friendship.created_at,
    other_profile.id;
end;
$$;

comment on function public.list_my_friendship_cards() is
  'Returns only the active caller''s pending and accepted relationships with the minimum other-profile card.';

-- ===========================================================================
-- SECTION 3 -- Atomic contest plus invitations
-- ===========================================================================

create function public.create_contest_with_invites_v1(
  p_request_id        uuid,
  p_title             text,
  p_metric            public.contest_metric,
  p_cadence           public.contest_cadence,
  p_target_value      numeric,
  p_stake_cents       integer,
  p_starts_at         timestamptz,
  p_ends_at           timestamptz,
  p_timezone          text,
  p_charity_id        uuid,
  p_invitee_ids       uuid[],
  p_max_participants  smallint default 2,
  p_tie_break         public.contest_tie_break default 'integrity_score',
  p_group_id          uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
        'charity_id', p_charity_id,
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
    p_charity_id,
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
$$;

comment on function public.create_contest_with_invites_v1(
  uuid,
  text,
  public.contest_metric,
  public.contest_cadence,
  numeric,
  integer,
  timestamptz,
  timestamptz,
  text,
  uuid,
  uuid[],
  smallint,
  public.contest_tie_break,
  uuid
) is
  'Atomically creates immutable contest terms, enrols the author, and invites an initial roster under a caller-scoped idempotency UUID.';

revoke all on function public.list_my_friendship_cards(),
                       public.create_contest_with_invites_v1(
                         uuid,
                         text,
                         public.contest_metric,
                         public.contest_cadence,
                         numeric,
                         integer,
                         timestamptz,
                         timestamptz,
                         text,
                         uuid,
                         uuid[],
                         smallint,
                         public.contest_tie_break,
                         uuid
                       )
  from public, anon, authenticated, service_role;

grant execute on function public.list_my_friendship_cards(),
                          public.create_contest_with_invites_v1(
                            uuid,
                            text,
                            public.contest_metric,
                            public.contest_cadence,
                            numeric,
                            integer,
                            timestamptz,
                            timestamptz,
                            text,
                            uuid,
                            uuid[],
                            smallint,
                            public.contest_tie_break,
                            uuid
                          )
  to authenticated;
