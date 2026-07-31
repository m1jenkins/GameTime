-- M8 -- lead-loss push delivery and a lightweight standings reaction.
--
-- A complete provisional standings publish is the only authority that can say
-- somebody lost first place. That transition appends the existing generic
-- notification intent in the same transaction. The best-effort device and APNs
-- delivery state remains separate, and no contest clock depends on it.

alter type public.notification_event_type
  add value if not exists 'contest_lead_lost';

begin;

create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- ===========================================================================
-- SECTION 1 -- Detect the first-place transition
-- ===========================================================================

create function app.emit_contest_lead_loss_intents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loss record;
begin
  for v_loss in
    with touched_snapshots as (
      select distinct inserted.snapshot_id
      from inserted_standing_entries inserted
    ),
    current_snapshots as (
      select snapshot.*
      from public.contest_standing_snapshots snapshot
      join touched_snapshots touched on touched.snapshot_id = snapshot.id
      join public.contests contest on contest.id = snapshot.contest_id
      where snapshot.phase = 'provisional'
        and contest.status = 'active'
    ),
    prior_snapshots as (
      select
        current_snapshot.id as current_snapshot_id,
        current_snapshot.contest_id,
        prior_snapshot.id as prior_snapshot_id
      from current_snapshots current_snapshot
      cross join lateral (
        select candidate.id
        from public.contest_standing_snapshots candidate
        where candidate.contest_id = current_snapshot.contest_id
          and candidate.phase = 'provisional'
          and candidate.id <> current_snapshot.id
          and (
            candidate.as_of,
            candidate.created_at,
            candidate.id
          ) < (
            current_snapshot.as_of,
            current_snapshot.created_at,
            current_snapshot.id
          )
        order by
          candidate.as_of desc,
          candidate.created_at desc,
          candidate.id desc
        limit 1
      ) prior_snapshot
    )
    select
      prior.current_snapshot_id as snapshot_id,
      participant.user_id as recipient_user_id
    from prior_snapshots prior
    join public.contest_standing_entries old_leader
      on old_leader.snapshot_id = prior.prior_snapshot_id
     and old_leader.rank = 1
    join public.contest_standing_entries current_standing
      on current_standing.snapshot_id = prior.current_snapshot_id
     and current_standing.participant_id = old_leader.participant_id
     and current_standing.rank > 1
    join public.contest_participants participant
      on participant.contest_id = prior.contest_id
     and participant.user_id = old_leader.participant_id
     and participant.status = 'accepted'
    order by participant.user_id
  loop
    -- The snapshot is the semantic event id. It permits a later regain/loss
    -- transition without weakening outbox idempotency.
    perform app.emit_notification_intent(
      v_loss.recipient_user_id,
      'contest_lead_lost'::public.notification_event_type,
      v_loss.snapshot_id
    );
  end loop;

  return null;
end;
$$;

create trigger contest_standing_entries_emit_lead_loss_intents
  after insert on public.contest_standing_entries
  referencing new table as inserted_standing_entries
  for each statement execute function app.emit_contest_lead_loss_intents();

revoke all on function app.emit_contest_lead_loss_intents()
  from public, anon, authenticated, service_role;

comment on function app.emit_contest_lead_loss_intents() is
  'Emits one generic intent when a previously first-ranked accepted participant falls below rank one in a new complete provisional snapshot.';

-- ===========================================================================
-- SECTION 2 -- One idempotent comeback reaction per provisional snapshot
-- ===========================================================================

create table public.contest_standings_reactions (
  id             uuid primary key default gen_random_uuid(),
  contest_id     uuid not null,
  snapshot_id    uuid not null,
  actor_user_id  uuid not null,
  reaction       text not null,
  created_at     timestamptz not null default now(),

  constraint contest_standings_reactions_snapshot_fkey
    foreign key (snapshot_id, contest_id)
    references public.contest_standing_snapshots (id, contest_id)
    on delete restrict,
  constraint contest_standings_reactions_participant_fkey
    foreign key (contest_id, actor_user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint contest_standings_reactions_kind
    check (reaction = 'comeback'),
  constraint contest_standings_reactions_once
    unique (snapshot_id, actor_user_id, reaction)
);

create index contest_standings_reactions_contest_created_idx
  on public.contest_standings_reactions (contest_id, created_at desc);

create trigger contest_standings_reactions_forbid_mutation
  before update or delete on public.contest_standings_reactions
  for each row execute function app.forbid_mutation();

create trigger contest_standings_reactions_forbid_truncate
  before truncate on public.contest_standings_reactions
  for each statement execute function app.forbid_mutation();

alter table public.contest_standings_reactions enable row level security;

revoke all on table public.contest_standings_reactions
  from public, anon, authenticated, service_role;

create function public.send_comeback_reaction_v1(
  p_contest_id  uuid,
  p_snapshot_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id          uuid;
  v_latest_snapshot_id uuid;
  v_reaction_id        uuid;
begin
  if p_contest_id is null or p_snapshot_id is null then
    raise exception 'contest and snapshot ids are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_caller_id := app.require_active_caller();

  if not exists (
    select 1
    from public.contest_participants participant
    join public.contests contest on contest.id = participant.contest_id
    where participant.contest_id = p_contest_id
      and participant.user_id = v_caller_id
      and participant.status = 'accepted'
      and contest.status = 'active'
  ) then
    raise exception 'only an accepted participant in an active contest may react'
      using errcode = 'insufficient_privilege';
  end if;

  select snapshot.id
    into v_latest_snapshot_id
  from public.contest_standing_snapshots snapshot
  where snapshot.contest_id = p_contest_id
    and snapshot.phase = 'provisional'
  order by snapshot.as_of desc, snapshot.created_at desc, snapshot.id desc
  limit 1;

  if v_latest_snapshot_id is distinct from p_snapshot_id then
    raise exception 'reactions must target the latest provisional standings'
      using errcode = 'restrict_violation';
  end if;

  if not exists (
    select 1
    from public.contest_standing_entries standing
    where standing.snapshot_id = p_snapshot_id
      and standing.participant_id = v_caller_id
      and standing.rank > 1
  ) then
    raise exception 'a comeback reaction requires the caller to be behind'
      using errcode = 'restrict_violation';
  end if;

  insert into public.contest_standings_reactions (
    contest_id,
    snapshot_id,
    actor_user_id,
    reaction
  )
  values (
    p_contest_id,
    p_snapshot_id,
    v_caller_id,
    'comeback'
  )
  on conflict on constraint contest_standings_reactions_once do nothing
  returning id into v_reaction_id;

  if v_reaction_id is null then
    select reaction.id
      into v_reaction_id
    from public.contest_standings_reactions reaction
    where reaction.snapshot_id = p_snapshot_id
      and reaction.actor_user_id = v_caller_id
      and reaction.reaction = 'comeback';
  end if;

  return v_reaction_id;
end;
$$;

comment on function public.send_comeback_reaction_v1(uuid, uuid) is
  'Authenticated, accepted-participant-only idempotent comeback reaction for the latest provisional standings snapshot.';

revoke all on function public.send_comeback_reaction_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.send_comeback_reaction_v1(uuid, uuid)
  to authenticated;

-- ===========================================================================
-- SECTION 3 -- APNs device addresses
-- ===========================================================================

create type public.push_token_environment as enum (
  'development',
  'production'
);

create table public.push_device_tokens (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null
    references public.profiles (id) on delete restrict,
  device_token    text not null,
  environment     public.push_token_environment not null,
  bundle_id       text not null,
  -- A newly registered or rebound address must not receive outbox events that
  -- predate that binding.
  eligible_after_intent_id bigint not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  invalidated_at  timestamptz,

  constraint push_device_tokens_address_unique
    unique (device_token, environment, bundle_id),
  constraint push_device_tokens_intent_floor_nonnegative
    check (eligible_after_intent_id >= 0),
  constraint push_device_tokens_hex
    check (
      char_length(device_token) between 64 and 400
      and device_token ~ '^[0-9a-f]+$'
    ),
  constraint push_device_tokens_bundle
    check (
      (bundle_id = 'com.mjenkins.gametime.staging'
        and environment = 'development')
      or
      (bundle_id = 'com.mjenkins.gametime'
        and environment in ('development', 'production'))
    )
);

create index push_device_tokens_user_active_idx
  on public.push_device_tokens (user_id, updated_at desc)
  where invalidated_at is null;

alter table public.push_device_tokens enable row level security;

revoke all on table public.push_device_tokens
  from public, anon, authenticated, service_role;

create function public.register_push_device_v1(
  p_device_token text,
  p_environment  public.push_token_environment,
  p_bundle_id    text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id       uuid;
  v_latest_intent_id bigint;
  v_token_id        uuid;
begin
  if p_device_token is null
     or p_environment is null
     or p_bundle_id is null
  then
    raise exception 'device token, environment, and bundle id are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_caller_id := app.require_active_caller();
  select coalesce(max(intent.id), 0)
    into v_latest_intent_id
  from public.notification_intents intent;

  insert into public.push_device_tokens (
    user_id,
    device_token,
    environment,
    bundle_id,
    eligible_after_intent_id
  )
  values (
    v_caller_id,
    lower(p_device_token),
    p_environment,
    p_bundle_id,
    v_latest_intent_id
  )
  on conflict on constraint push_device_tokens_address_unique
  do update set
    user_id = excluded.user_id,
    eligible_after_intent_id = case
      when push_device_tokens.user_id is distinct from excluded.user_id
        or push_device_tokens.invalidated_at is not null
      then excluded.eligible_after_intent_id
      else push_device_tokens.eligible_after_intent_id
    end,
    updated_at = clock_timestamp(),
    invalidated_at = null
  returning id into v_token_id;

  return v_token_id;
end;
$$;

create function public.unregister_push_device_v1(
  p_device_token text,
  p_environment  public.push_token_environment,
  p_bundle_id    text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid;
begin
  if p_device_token is null
     or p_environment is null
     or p_bundle_id is null
  then
    raise exception 'device token, environment, and bundle id are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_caller_id := app.require_active_caller();

  update public.push_device_tokens token
  set
    invalidated_at = coalesce(token.invalidated_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where token.user_id = v_caller_id
    and token.device_token = lower(p_device_token)
    and token.environment = p_environment
    and token.bundle_id = p_bundle_id
    and token.invalidated_at is null;

  return found;
end;
$$;

revoke all on function public.register_push_device_v1(
  text, public.push_token_environment, text
) from public, anon, authenticated, service_role;
grant execute on function public.register_push_device_v1(
  text, public.push_token_environment, text
) to authenticated;

revoke all on function public.unregister_push_device_v1(
  text, public.push_token_environment, text
) from public, anon, authenticated, service_role;
grant execute on function public.unregister_push_device_v1(
  text, public.push_token_environment, text
) to authenticated;

create function app.invalidate_deleted_profile_push_tokens()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.push_device_tokens token
  set
    invalidated_at = coalesce(token.invalidated_at, new.deleted_at),
    updated_at = clock_timestamp()
  where token.user_id = new.id
    and token.invalidated_at is null;

  return new;
end;
$$;

create trigger profiles_invalidate_push_tokens
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function app.invalidate_deleted_profile_push_tokens();

revoke all on function app.invalidate_deleted_profile_push_tokens()
  from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 4 -- Leased, retryable APNs delivery state
-- ===========================================================================

create table public.push_notification_deliveries (
  id                    uuid primary key default gen_random_uuid(),
  -- Deliberately not an FK: notification_intents has its own TRUNCATE guard,
  -- whose tested 23001 refusal must run before Postgres dependency checks.
  -- The outbox is append-only, and the claim RPC is the only creator here.
  notification_intent_id bigint not null,
  push_device_token_id  uuid not null
    references public.push_device_tokens (id) on delete restrict,
  attempt_count         smallint not null default 0,
  next_attempt_at       timestamptz not null default now(),
  lease_owner           uuid,
  lease_expires_at      timestamptz,
  delivered_at          timestamptz,
  permanently_failed_at timestamptz,
  last_status_code      integer,
  last_reason           text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint push_notification_deliveries_once
    unique (notification_intent_id, push_device_token_id),
  constraint push_notification_deliveries_attempts
    check (attempt_count between 0 and 8),
  constraint push_notification_deliveries_lease_shape
    check ((lease_owner is null) = (lease_expires_at is null)),
  constraint push_notification_deliveries_terminal_shape
    check (not (
      delivered_at is not null
      and permanently_failed_at is not null
    )),
  constraint push_notification_deliveries_reason_bounded
    check (last_reason is null or char_length(last_reason) between 1 and 120)
);

create index push_notification_deliveries_due_idx
  on public.push_notification_deliveries (
    next_attempt_at,
    notification_intent_id
  )
  where delivered_at is null and permanently_failed_at is null;

alter table public.push_notification_deliveries enable row level security;

revoke all on table public.push_notification_deliveries
  from public, anon, authenticated, service_role;

create function public.claim_push_deliveries_v1(
  p_lease_owner uuid,
  p_limit       integer default 25
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_claims jsonb;
begin
  if p_lease_owner is null or p_limit not between 1 and 100 then
    raise exception 'lease owner and a limit from 1 to 100 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Retire abandoned work after a token is invalidated or rebound. Active
  -- leases are allowed to finish; an expired lease is terminalized on the next
  -- worker tick instead of remaining silently non-claimable.
  update public.push_notification_deliveries delivery
  set
    permanently_failed_at = clock_timestamp(),
    lease_owner = null,
    lease_expires_at = null,
    last_reason = case
      when token.invalidated_at is not null then 'TokenInvalidated'
      else 'TokenBindingChanged'
    end,
    updated_at = clock_timestamp()
  from public.push_device_tokens token,
       public.notification_intents intent
  where token.id = delivery.push_device_token_id
    and intent.id = delivery.notification_intent_id
    and delivery.delivered_at is null
    and delivery.permanently_failed_at is null
    and (
      delivery.lease_expires_at is null
      or delivery.lease_expires_at <= clock_timestamp()
    )
    and (
      token.invalidated_at is not null
      or token.user_id is distinct from intent.recipient_user_id
      or token.eligible_after_intent_id >= intent.id
    );

  insert into public.push_notification_deliveries (
    notification_intent_id,
    push_device_token_id
  )
  select intent.id, token.id
  from public.notification_intents intent
  join public.contest_standing_snapshots snapshot
    on snapshot.id = intent.entity_id
  join public.profiles profile
    on profile.id = intent.recipient_user_id
   and profile.deleted_at is null
  join public.push_device_tokens token
    on token.user_id = intent.recipient_user_id
   and token.invalidated_at is null
   and token.eligible_after_intent_id < intent.id
  where intent.event_type = 'contest_lead_lost'
    and intent.not_before <= clock_timestamp()
  on conflict on constraint push_notification_deliveries_once do nothing;

  with due as (
    select delivery.id
    from public.push_notification_deliveries delivery
    join public.notification_intents intent
      on intent.id = delivery.notification_intent_id
    join public.push_device_tokens token
     on token.id = delivery.push_device_token_id
     and token.user_id = intent.recipient_user_id
     and token.invalidated_at is null
     and token.eligible_after_intent_id < intent.id
    where delivery.delivered_at is null
      and delivery.permanently_failed_at is null
      and delivery.attempt_count < 8
      and delivery.next_attempt_at <= clock_timestamp()
      and (
        delivery.lease_expires_at is null
        or delivery.lease_expires_at <= clock_timestamp()
      )
      and intent.not_before <= clock_timestamp()
    order by intent.id, delivery.id
    for update of delivery skip locked
    limit p_limit
  ),
  claimed as (
    update public.push_notification_deliveries delivery
    set
      attempt_count = delivery.attempt_count + 1,
      lease_owner = p_lease_owner,
      lease_expires_at = clock_timestamp() + interval '2 minutes',
      updated_at = clock_timestamp()
    from due
    where delivery.id = due.id
    returning delivery.*
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'delivery_id', claimed.id,
        'intent_id', intent.id,
        'attempt_count', claimed.attempt_count,
        'device_token', token.device_token,
        'environment', token.environment,
        'bundle_id', token.bundle_id,
        'contest_id', snapshot.contest_id,
        'snapshot_id', snapshot.id,
        'event_type', intent.event_type
      )
      order by intent.id, claimed.id
    ),
    '[]'::jsonb
  )
    into v_claims
  from claimed
  join public.notification_intents intent
    on intent.id = claimed.notification_intent_id
  join public.push_device_tokens token
    on token.id = claimed.push_device_token_id
  join public.contest_standing_snapshots snapshot
    on snapshot.id = intent.entity_id;

  return v_claims;
end;
$$;

create function public.record_push_delivery_v1(
  p_delivery_id uuid,
  p_lease_owner uuid,
  p_outcome      text,
  p_status_code  integer default null,
  p_reason       text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_delivery public.push_notification_deliveries;
begin
  if p_delivery_id is null
     or p_lease_owner is null
     or p_outcome not in ('delivered', 'retry', 'permanent_failure')
     or (p_reason is not null and char_length(p_reason) not between 1 and 120)
  then
    raise exception 'a valid delivery result is required'
      using errcode = 'invalid_parameter_value';
  end if;

  select delivery.*
    into v_delivery
  from public.push_notification_deliveries delivery
  where delivery.id = p_delivery_id
  for update;

  if v_delivery.id is null
     or v_delivery.lease_owner is distinct from p_lease_owner
     or v_delivery.lease_expires_at <= clock_timestamp()
     or v_delivery.delivered_at is not null
     or v_delivery.permanently_failed_at is not null
  then
    raise exception 'the push delivery lease is unavailable'
      using errcode = 'restrict_violation';
  end if;

  update public.push_notification_deliveries delivery
  set
    delivered_at = case
      when p_outcome = 'delivered' then clock_timestamp()
      else null
    end,
    permanently_failed_at = case
      when p_outcome = 'permanent_failure'
        or (p_outcome = 'retry' and v_delivery.attempt_count >= 8)
      then clock_timestamp()
      else null
    end,
    next_attempt_at = case
      when p_outcome = 'retry' and v_delivery.attempt_count < 8
      then clock_timestamp()
        + least(
          interval '1 hour',
          interval '15 seconds'
            * power(2::numeric, greatest(v_delivery.attempt_count - 1, 0))
        )
      else delivery.next_attempt_at
    end,
    lease_owner = null,
    lease_expires_at = null,
    last_status_code = p_status_code,
    last_reason = case
      when p_outcome = 'retry' and v_delivery.attempt_count >= 8
      then 'RetryLimitExceeded'
      else p_reason
    end,
    updated_at = clock_timestamp()
  where delivery.id = p_delivery_id;

  if p_outcome = 'permanent_failure'
     and p_reason in (
       'BadDeviceToken',
       'DeviceTokenNotForTopic',
       'Unregistered'
     )
  then
    update public.push_device_tokens token
    set
      invalidated_at = coalesce(token.invalidated_at, clock_timestamp()),
      updated_at = clock_timestamp()
    where token.id = v_delivery.push_device_token_id;
  end if;
end;
$$;

revoke all on function public.claim_push_deliveries_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_push_deliveries_v1(uuid, integer)
  to service_role;

revoke all on function public.record_push_delivery_v1(
  uuid, uuid, text, integer, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_push_delivery_v1(
  uuid, uuid, text, integer, text
) to service_role;

-- The scheduled call is inert until an operator installs both named Vault
-- secrets. The URL points at /functions/v1/deliver-push; the shared secret is
-- sent only in a header. Missing deployment configuration never blocks a
-- standings transaction.
create function app.dispatch_due_push_notifications()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url        text;
  v_secret     text;
  v_request_id bigint;
begin
  select secret.decrypted_secret
    into v_url
  from vault.decrypted_secrets secret
  where secret.name = 'gametime_push_dispatch_url';

  select secret.decrypted_secret
    into v_secret
  from vault.decrypted_secrets secret
  where secret.name = 'gametime_push_dispatch_secret';

  if v_url is null or v_secret is null then
    return null;
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-GameTime-Dispatch-Secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  )
    into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function app.dispatch_due_push_notifications()
  from public, anon, authenticated, service_role;

select cron.schedule(
  'gametime-dispatch-push',
  '* * * * *',
  'select app.dispatch_due_push_notifications();'
);

commit;
