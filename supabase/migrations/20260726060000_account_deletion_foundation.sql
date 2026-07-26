-- M7 / D81 -- durable actors and atomic account deletion.
--
-- Authentication identity and contest identity have different lifetimes.
-- Deleting an account therefore tombstones the stable profile, resolves only
-- transitionable pending work, revokes operational device keys, and removes
-- auth.users without cascading through agreements or evidence.
begin;

-- This upgrade changes every path that could otherwise race the removal of the
-- auth/profile and device/evidence cascades. Keep one migration-wide write
-- barrier so no account can cross the old and new models halfway.
lock table auth.users,
           public.profiles,
           public.friendships,
           public.groups,
           public.group_members,
           public.blocks,
           public.contests,
           public.contest_participants,
           public.device_attestations,
           public.ingest_batches,
           public.metric_snapshots,
           public.evidence_quarantines,
           public.evidence_quarantine_reviews,
           public.timezone_change_requests,
           public.timezone_change_reviews,
           public.timezone_change_applied_events,
           public.geofence_checkins,
           public.geofence_location_observations,
           public.notification_intents,
           app.device_attestation_receipts
  in share row exclusive mode;

-- ===========================================================================
-- SECTION 1 -- Stable tombstone identity and private handle reservation
-- ===========================================================================

alter table public.profiles
  add column deleted_at timestamptz;

-- The hyphenated internal namespace was impossible under the old public-handle
-- grammar, so this upgrade cannot collide with a previously valid live handle.
alter table public.profiles
  drop constraint profiles_handle_format,
  add constraint profiles_handle_format
    check (
      (
        deleted_at is null
        and handle::text ~ '^[A-Za-z][A-Za-z0-9_]{2,29}$'
      )
      or (
        deleted_at is not null
        and lower(handle::text) ~ '^deleted-[0-9a-f]{20}$'
      )
    );

-- A deleted profile has one and only one valid public shape, so a privileged
-- partial update cannot leave old personal fields behind.
alter table public.profiles
  add constraint profiles_deletion_shape
  check (
    (
      deleted_at is null
    )
    or
    (
      deleted_at is not null
      and lower(handle::text) ~ '^deleted-[0-9a-f]{20}$'
      and display_name = 'Deleted member'
      and avatar_path is null
      and timezone = 'UTC'
    )
  );

comment on column public.profiles.deleted_at is
  'D81 tombstone time. Non-null profiles retain durable contest identity but cannot authenticate.';

create table app.account_deletion_secrets (
  singleton        boolean primary key default true
    check (singleton),
  handle_hmac_key  bytea not null
    default extensions.gen_random_bytes(32)
    check (octet_length(handle_hmac_key) = 32),
  created_at       timestamptz not null default now()
);

insert into app.account_deletion_secrets (singleton)
values (true);

comment on table app.account_deletion_secrets is
  'Private server key material for non-enumerable deleted-handle reservations.';

revoke all on table app.account_deletion_secrets
  from public, anon, authenticated, service_role;

create trigger account_deletion_secrets_forbid_mutation
  before update or delete or truncate on app.account_deletion_secrets
  for each statement execute function app.forbid_mutation();

-- A custom GUC is useful for trigger routing but can be pre-set by any role
-- with a direct SQL connection. Pair it with an owner-only transaction marker
-- so no other SECURITY DEFINER workflow can impersonate account deletion.
create table app.account_deletion_transactions (
  transaction_id  bigint primary key,
  backend_pid     integer not null,
  actor_id        uuid not null,
  started_at      timestamptz not null default clock_timestamp()
);

revoke all on table app.account_deletion_transactions
  from public, anon, authenticated, service_role;

create function app.is_account_deletion_transaction(p_actor_id uuid)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select p_actor_id is not null
     and exists (
       select 1
       from app.account_deletion_transactions deletion
       where deletion.transaction_id = pg_catalog.txid_current()
         and deletion.backend_pid = pg_catalog.pg_backend_pid()
         and deletion.actor_id = p_actor_id
     );
$$;

revoke all on function app.is_account_deletion_transaction(uuid)
  from public, anon, authenticated, service_role;

create table app.profile_handle_claims (
  actor_id       uuid primary key
    references public.profiles (id) on delete restrict,
  handle_digest  bytea not null unique
    check (octet_length(handle_digest) = 32),
  claimed_at     timestamptz not null default now(),
  retained_at    timestamptz,

  constraint profile_handle_claims_retention_order
    check (retained_at is null or retained_at >= claimed_at)
);

comment on table app.profile_handle_claims is
  'Private HMAC claims for every current handle. A deleted actor keeps the claim permanently without retaining plaintext.';

revoke all on table app.profile_handle_claims
  from public, anon, authenticated, service_role;

create trigger profile_handle_claims_forbid_delete
  before delete or truncate on app.profile_handle_claims
  for each statement execute function app.forbid_mutation();

create function app.deleted_handle_digest(p_handle text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.hmac(
    pg_catalog.convert_to(lower(p_handle), 'UTF8'),
    secret.handle_hmac_key,
    'sha256'
  )
  from app.account_deletion_secrets secret
  where secret.singleton;
$$;

comment on function app.deleted_handle_digest(text) is
  'Private HMAC of the normalized ASCII handle used to prevent post-deletion impersonation.';

revoke all on function app.deleted_handle_digest(text)
  from public, anon, authenticated, service_role;

create function app.generate_tombstone_handle()
returns extensions.citext
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_handle text;
begin
  for _attempt in 1..20 loop
    -- Ten random bytes produce twenty lowercase hex characters. The value is
    -- deliberately independent of the actor UUID.
    v_handle := 'deleted-' || pg_catalog.encode(
      extensions.gen_random_bytes(10),
      'hex'
    );

    if not exists (
      select 1
      from public.profiles profile
      where lower(profile.handle::text) = v_handle
    ) then
      return v_handle::extensions.citext;
    end if;
  end loop;

  raise exception 'could not generate a unique account tombstone';
end;
$$;

comment on function app.generate_tombstone_handle() is
  'Generates a random, UUID-independent internal profile handle for D81 tombstones.';

revoke all on function app.generate_tombstone_handle()
  from public, anon, authenticated, service_role;

create function app.reject_reserved_profile_handle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is null
     and exists (
       select 1
       from app.profile_handle_claims claim
       where claim.handle_digest =
             app.deleted_handle_digest(new.handle::text)
         and claim.actor_id <> new.id
     )
  then
    -- Match ordinary handle uniqueness so callers do not gain a deleted-handle
    -- existence oracle.
    raise unique_violation using message = 'handle is not available';
  end if;

  return new;
end;
$$;

create function app.sync_profile_handle_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null then
    update app.profile_handle_claims claim
    set retained_at = coalesce(claim.retained_at, new.deleted_at)
    where claim.actor_id = new.id;

    if not found then
      raise exception 'profile handle claim is missing'
        using errcode = 'integrity_constraint_violation';
    end if;

    return new;
  end if;

  insert into app.profile_handle_claims (
    actor_id,
    handle_digest,
    claimed_at
  )
  values (
    new.id,
    app.deleted_handle_digest(new.handle::text),
    clock_timestamp()
  )
  on conflict (actor_id) do update
  set handle_digest = excluded.handle_digest,
      claimed_at = excluded.claimed_at,
      retained_at = null;

  return new;
end;
$$;

insert into app.profile_handle_claims (
  actor_id,
  handle_digest,
  claimed_at
)
select
  profile.id,
  app.deleted_handle_digest(profile.handle::text),
  profile.created_at
from public.profiles profile;

create trigger profiles_reject_reserved_handle
  before insert or update of handle on public.profiles
  for each row execute function app.reject_reserved_profile_handle();

create trigger profiles_sync_handle_claim
  after insert or update of handle, deleted_at on public.profiles
  for each row execute function app.sync_profile_handle_claim();

create function app.enforce_profile_tombstone()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner name;
begin
  if old.deleted_at is not null then
    raise exception 'a deleted profile tombstone is immutable'
      using errcode = 'restrict_violation';
  end if;

  if new.deleted_at is distinct from old.deleted_at then
    select role.rolname
      into v_owner
    from pg_catalog.pg_class relation
    join pg_catalog.pg_roles role on role.oid = relation.relowner
    where relation.oid = tg_relid;

    if coalesce(
         pg_catalog.current_setting('app.account_deletion_actor', true),
         ''
       ) <> old.id::text
       or current_user <> v_owner
       or not app.is_account_deletion_transaction(old.id)
    then
      raise exception 'only the account deletion transaction may tombstone a profile'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

create trigger profiles_enforce_tombstone
  before update on public.profiles
  for each row execute function app.enforce_profile_tombstone();

create trigger profiles_forbid_delete
  before delete on public.profiles
  for each row execute function app.forbid_mutation();

create trigger profiles_forbid_truncate
  before truncate on public.profiles
  for each statement execute function app.forbid_mutation();

revoke all on function app.reject_reserved_profile_handle(),
                       app.sync_profile_handle_claim(),
                       app.enforce_profile_tombstone()
  from public, anon, authenticated, service_role;

-- This private binding replaces the lifetime coupling formerly encoded by the
-- profiles -> auth.users FK. Its auth FK still serializes onboarding with
-- deletion, while public.delete_account() can remove the binding and retain the
-- profile tombstone before deleting the authentication principal.
create table app.active_profile_auth_bindings (
  actor_id uuid primary key,
  bound_at timestamptz not null default clock_timestamp(),

  constraint active_profile_auth_bindings_profile_fkey
    foreign key (actor_id)
    references public.profiles (id) on delete restrict,
  constraint active_profile_auth_bindings_auth_fkey
    foreign key (actor_id)
    references auth.users (id) on delete cascade
);

insert into app.active_profile_auth_bindings (actor_id, bound_at)
select profile.id, profile.created_at
from public.profiles profile
join auth.users auth_user on auth_user.id = profile.id;

revoke all on table app.active_profile_auth_bindings
  from public, anon, authenticated, service_role;

create function app.bind_profile_auth_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into app.active_profile_auth_bindings (actor_id)
  values (new.id);
  return new;
end;
$$;

create function app.guard_active_profile_binding_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(
       pg_catalog.current_setting('app.account_deletion_actor', true),
       ''
     ) <> old.actor_id::text
     or not app.is_account_deletion_transaction(old.actor_id)
  then
    raise exception 'active profile authentication bindings are deletion-RPC managed'
      using errcode = 'restrict_violation';
  end if;

  return old;
end;
$$;

create trigger profiles_bind_auth_actor
  after insert on public.profiles
  for each row execute function app.bind_profile_auth_actor();

create trigger active_profile_auth_bindings_guard_delete
  before delete on app.active_profile_auth_bindings
  for each row execute function app.guard_active_profile_binding_delete();

create trigger active_profile_auth_bindings_forbid_truncate
  before truncate on app.active_profile_auth_bindings
  for each statement execute function app.forbid_mutation();

revoke all on function app.bind_profile_auth_actor(),
                       app.guard_active_profile_binding_delete()
  from public, anon, authenticated, service_role;

-- Direct Auth dashboard/admin deletion is no longer the account-deletion API.
-- A user who never completed onboarding still has no durable actor and may be
-- removed normally. An onboarded actor must first be a valid tombstone, which
-- only public.delete_account() can create.
create function app.guard_auth_user_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from app.active_profile_auth_bindings binding
    where binding.actor_id = old.id
  )
     or exists (
       select 1
       from public.profiles profile
       where profile.id = old.id
         and profile.deleted_at is null
     )
  then
    raise exception 'delete onboarded accounts through public.delete_account()'
      using errcode = 'restrict_violation';
  end if;

  return old;
end;
$$;

create function app.guard_auth_user_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_at timestamptz;
begin
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception 'authentication actor ids are immutable'
      using errcode = 'restrict_violation';
  end if;

  select profile.deleted_at
    into v_deleted_at
  from public.profiles profile
  where profile.id = new.id
  for update;

  if found
     and (
       v_deleted_at is not null
       or not exists (
         select 1
         from auth.users auth_user
         where auth_user.id = new.id
       )
     )
  then
    raise exception 'this authentication actor id is permanently reserved'
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

create trigger auth_users_guard_account_delete
  before delete on auth.users
  for each row execute function app.guard_auth_user_delete();

create trigger auth_users_guard_actor_reuse
  before insert on auth.users
  for each row execute function app.guard_auth_user_insert();

create trigger auth_users_forbid_actor_id_change
  before update of id on auth.users
  for each row execute function app.guard_auth_user_insert();

create trigger auth_users_forbid_truncate
  before truncate on auth.users
  for each statement execute function app.forbid_mutation();

revoke all on function app.guard_auth_user_delete(),
                       app.guard_auth_user_insert()
  from public, anon, authenticated, service_role;

-- The durable actor now outlives auth.users. Every domain FK continues to
-- target profiles.id, so the UUID can never be reassigned or silently orphaned.
alter table public.profiles
  drop constraint profiles_id_fkey;

-- Authorship now resolves to the retained tombstone rather than SET NULL.
alter table public.groups
  drop constraint groups_created_by_fkey,
  add constraint groups_created_by_fkey
    foreign key (created_by)
    references public.profiles (id) on delete restrict;

alter table public.contests
  drop constraint contests_created_by_fkey,
  add constraint contests_created_by_fkey
    foreign key (created_by)
    references public.profiles (id) on delete restrict;

alter table public.contest_participants
  drop constraint contest_participants_user_id_fkey,
  add constraint contest_participants_user_id_fkey
    foreign key (user_id)
    references public.profiles (id) on delete restrict,
  drop constraint contest_participants_invited_by_fkey,
  add constraint contest_participants_invited_by_fkey
    foreign key (invited_by)
    references public.profiles (id) on delete restrict;

create index groups_created_by_idx
  on public.groups (created_by)
  where created_by is not null;

create index contests_created_by_idx
  on public.contests (created_by)
  where created_by is not null;

create index contest_participants_invited_by_idx
  on public.contest_participants (invited_by)
  where invited_by is not null;

-- ===========================================================================
-- SECTION 2 -- Active-actor authorization and mutation serialization
-- ===========================================================================

create function app.auth_actor_exists(p_actor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
     and exists (
       select 1
       from auth.users auth_user
       where auth_user.id = p_actor_id
     );
$$;

create function app.is_active_actor(p_actor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
     and exists (
       select 1
       from public.profiles profile
       join app.active_profile_auth_bindings binding
         on binding.actor_id = profile.id
       join auth.users auth_user on auth_user.id = profile.id
       where profile.id = p_actor_id
         and profile.deleted_at is null
     );
$$;

comment on function app.is_active_actor(uuid) is
  'True only while both the authentication principal and non-tombstoned profile exist.';

-- Locks all named actors in UUID order. The lock is the deletion/write
-- serialization point; the active check after waiting closes stale-JWT races.
create function app.lock_active_actors(p_actor_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
begin
  for v_actor_id in
    select distinct actor_id
    from pg_catalog.unnest(p_actor_ids) actor_id
    where actor_id is not null
    order by actor_id
  loop
    perform 1
    from public.profiles profile
    join app.active_profile_auth_bindings binding
      on binding.actor_id = profile.id
    join auth.users auth_user on auth_user.id = profile.id
    where profile.id = v_actor_id
      and profile.deleted_at is null
    for update of profile;

    if not found then
      raise exception 'account is not active'
        using errcode = 'insufficient_privilege';
    end if;
  end loop;
end;
$$;

create function app.require_active_caller()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
begin
  if v_actor_id is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[v_actor_id]);
  return v_actor_id;
end;
$$;

revoke all on function app.auth_actor_exists(uuid),
                       app.is_active_actor(uuid),
                       app.lock_active_actors(uuid[]),
                       app.require_active_caller()
  from public, anon, authenticated, service_role;

-- Policies may invoke this one internal predicate, but the app schema remains
-- absent from the Data API's exposed schemas.
grant execute on function app.is_active_actor(uuid),
                          app.auth_actor_exists(uuid),
                          app.lock_active_actors(uuid[])
  to authenticated;

grant execute on function app.lock_active_actors(uuid[])
  to service_role;

-- One restrictive policy composes with every existing feature policy. Profile
-- insertion is the single exception: an auth principal has no profile yet
-- while onboarding creates it.
create policy profiles_active_actor_only
  on public.profiles
  as restrictive
  for all
  to authenticated
  using (app.is_active_actor((select auth.uid())))
  with check (
    app.is_active_actor((select auth.uid()))
    or (
      id = (select auth.uid())
      and deleted_at is null
      and app.auth_actor_exists((select auth.uid()))
    )
  );

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'friendships',
    'groups',
    'group_members',
    'blocks',
    'charities',
    'contests',
    'contest_participants',
    'device_attestations',
    'ingest_batches',
    'metric_snapshots',
    'evidence_quarantines',
    'evidence_quarantine_reviews',
    'timezone_change_requests',
    'timezone_change_reviews',
    'timezone_change_applied_events',
    'contest_geofences',
    'geofence_checkins',
    'geofence_location_observations',
    'notification_intents'
  ]
  loop
    execute pg_catalog.format(
      'create policy active_actor_only on public.%I '
      'as restrictive for all to authenticated '
      'using (app.is_active_actor((select auth.uid()))) '
      'with check (app.is_active_actor((select auth.uid())))',
      v_table
    );
  end loop;
end;
$$;

comment on policy notification_intents_select_own
  on public.notification_intents is
  'Recipient-only inbox. D81''s restrictive active_actor_only policy rejects a tombstoned stale JWT.';

-- Adding deleted_at to a table-level grant would otherwise make it directly
-- writable. Keep onboarding/profile edits column-scoped.
revoke insert, update on public.profiles from authenticated;
revoke insert, update, delete, truncate on public.profiles from service_role;
grant insert (id, handle, display_name, avatar_path, timezone)
  on public.profiles to authenticated;
grant update (handle, display_name, avatar_path, timezone)
  on public.profiles to authenticated;

revoke truncate on table auth.users,
                         public.contests,
                         public.contest_participants,
                         public.ingest_batches,
                         public.metric_snapshots,
                         public.evidence_quarantines,
                         public.evidence_quarantine_reviews,
                         public.timezone_change_requests,
                         public.timezone_change_reviews,
                         public.timezone_change_applied_events,
                         public.geofence_checkins,
                         public.geofence_location_observations,
                         public.device_attestations,
                         app.device_attestation_receipts
  from public, anon, authenticated, service_role;

-- Direct RLS writes need the same row lock as RPCs. Security-definer RPCs keep
-- the request JWT GUC, so this also protects their mutation path.
create function app.lock_authenticated_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner    name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if coalesce(
       pg_catalog.current_setting('app.system_actor_lock_bypass', true),
       ''
     ) = 'on'
     and current_user = v_owner
  then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_actor_id is not null then
    perform app.lock_active_actors(array[v_actor_id]);
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function app.lock_authenticated_statement()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner    name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if coalesce(
       pg_catalog.current_setting('app.system_actor_lock_bypass', true),
       ''
     ) = 'on'
     and current_user = v_owner
  then
    return null;
  end if;

  if v_actor_id is not null then
    perform app.lock_active_actors(array[v_actor_id]);
  end if;

  return null;
end;
$$;

-- Accepting an invitation eventually takes a contest row lock in the original
-- capacity trigger. Acquire every pending contest for the caller before the
-- UPDATE can lock a participant tuple, matching deletion and activation's
-- contest-first order and preventing creator-deletion/acceptance deadlocks.
create function app.lock_caller_pending_contests()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
begin
  if v_actor_id is null then
    return;
  end if;

  perform contest.id
  from public.contests contest
  join public.contest_participants participant
    on participant.contest_id = contest.id
  where participant.user_id = v_actor_id
    and contest.status = 'pending'
  order by contest.starts_at, contest.id
  for update of contest;
end;
$$;

create function app.lock_participant_pending_contests()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner    name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if coalesce(
       pg_catalog.current_setting('app.system_actor_lock_bypass', true),
       ''
     ) = 'on'
     and current_user = v_owner
  then
    return null;
  end if;

  if v_actor_id is not null then
    perform app.lock_caller_pending_contests();
  end if;

  return null;
end;
$$;

create function app.lock_profile_reference_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_row       jsonb;
  v_column    text;
  v_actor_ids uuid[] := array[]::uuid[];
  v_caller_id uuid := (select auth.uid());
  v_owner     name;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  if v_caller_id is not null then
    v_actor_ids := pg_catalog.array_append(v_actor_ids, v_caller_id);
  end if;

  foreach v_column in array tg_argv loop
    if v_row ->> v_column is not null then
      v_actor_ids := pg_catalog.array_append(
        v_actor_ids,
        (v_row ->> v_column)::uuid
      );
    end if;
  end loop;

  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if coalesce(
       pg_catalog.current_setting('app.system_actor_lock_bypass', true),
       ''
     ) = 'on'
     and current_user = v_owner
  then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  perform app.lock_active_actors(v_actor_ids);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function app.lock_authenticated_mutation(),
                       app.lock_authenticated_statement(),
                       app.lock_caller_pending_contests(),
                       app.lock_participant_pending_contests(),
                       app.lock_profile_reference_columns()
  from public, anon, authenticated, service_role;

grant execute on function app.lock_caller_pending_contests()
  to authenticated, service_role;

create trigger friendships_00_lock_caller_statement
  before update or delete on public.friendships
  for each statement execute function app.lock_authenticated_statement();
create trigger friendships_00_lock_authenticated_actor
  before delete on public.friendships
  for each row execute function app.lock_authenticated_mutation();
create trigger friendships_00_lock_referenced_actors
  before insert on public.friendships
  for each row execute function
    app.lock_profile_reference_columns('user_a', 'user_b');

create trigger groups_00_lock_caller_statement
  before update or delete on public.groups
  for each statement execute function app.lock_authenticated_statement();
create trigger groups_00_lock_authenticated_actor
  before insert or update on public.groups
  for each row execute function app.lock_authenticated_mutation();

create trigger group_members_00_lock_caller_statement
  before delete on public.group_members
  for each statement execute function app.lock_authenticated_statement();
create trigger group_members_00_lock_authenticated_actor
  before insert or delete on public.group_members
  for each row execute function app.lock_authenticated_mutation();

create trigger blocks_00_lock_caller_statement
  before delete on public.blocks
  for each statement execute function app.lock_authenticated_statement();
create trigger blocks_00_lock_authenticated_actor
  before delete on public.blocks
  for each row execute function app.lock_authenticated_mutation();
create trigger blocks_00_lock_referenced_actors
  before insert on public.blocks
  for each row execute function
    app.lock_profile_reference_columns('blocker_id', 'blocked_id');

create trigger contest_participants_00_lock_caller_statement
  before update on public.contest_participants
  for each statement execute function app.lock_authenticated_statement();
create trigger contest_participants_01_lock_pending_contests
  before update on public.contest_participants
  for each statement execute function app.lock_participant_pending_contests();
create trigger contest_participants_00_lock_active_actors
  before insert on public.contest_participants
  for each row execute function
    app.lock_profile_reference_columns('user_id', 'invited_by');

-- An invitation cannot target a tombstone, even if a concurrent deletion
-- happens after the policy's first visibility read.
create or replace function app.may_invite_to_contest(
  cid uuid,
  inviter uuid,
  invitee uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_active_actor(inviter)
     and app.is_active_actor(invitee)
     and inviter <> invitee
     and not app.is_blocked_either_way(inviter, invitee)
     and exists (
       select 1
       from public.contests contest
       where contest.id = cid
         and contest.status = 'pending'
         and contest.created_by = inviter
         and (
           app.is_friend(inviter, invitee)
           or (
             contest.group_id is not null
             and app.is_group_member(contest.group_id, invitee)
             and app.is_group_member(contest.group_id, inviter)
           )
         )
     );
$$;

-- Activation owns each contest row before making its system-only participant
-- transitions. Bypass recursive actor locks for those transitions so its lock
-- order stays contest-first, while account deletion serializes on the same
-- contest rows. The UUID tiebreaker makes multi-contest locking deterministic.
create or replace function app.activate_due_contests(
  p_now timestamptz default now()
)
returns table (contest_id uuid, outcome public.contest_status)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest             record;
  v_accepted            integer;
  v_previous_lock_bypass text :=
    pg_catalog.current_setting('app.system_actor_lock_bypass', true);
begin
  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    'on',
    true
  );

  begin
    for v_contest in
      select contest.id
      from public.contests contest
      where contest.status = 'pending'
        and contest.starts_at <= p_now
      order by contest.starts_at, contest.id
      for update
    loop
      update public.contest_participants participant
      set status = 'lapsed'
      where participant.contest_id = v_contest.id
        and participant.status = 'invited';

      select count(*)
        into v_accepted
      from public.contest_participants participant
      where participant.contest_id = v_contest.id
        and participant.status = 'accepted';

      if v_accepted >= 2 then
        update public.contests contest
        set status = 'active',
            activated_at = p_now
        where contest.id = v_contest.id;

        return query
        select v_contest.id, 'active'::public.contest_status;
      else
        update public.contests contest
        set status = 'cancelled',
            cancellation_reason = 'insufficient_participants',
            cancelled_at = p_now
        where contest.id = v_contest.id;

        return query
        select v_contest.id, 'cancelled'::public.contest_status;
      end if;
    end loop;
  exception
    when others then
      perform pg_catalog.set_config(
        'app.system_actor_lock_bypass',
        coalesce(v_previous_lock_bypass, 'off'),
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    coalesce(v_previous_lock_bypass, 'off'),
    true
  );
end;
$$;

-- ===========================================================================
-- SECTION 3 -- Remove evidence-erasing cascades and protect durable facts
-- ===========================================================================

alter table public.device_attestations
  drop constraint device_attestations_user_id_fkey,
  add constraint device_attestations_user_id_fkey
    foreign key (user_id)
    references public.profiles (id) on delete restrict;

-- key_id already is SHA-256(public_key). Retaining the value without a live FK
-- makes it the non-reversible historical fingerprint D81 requires.
alter table public.ingest_batches
  drop constraint ingest_batches_key_id_fkey,
  drop constraint ingest_batches_participant_fkey,
  add constraint ingest_batches_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict;

comment on column public.ingest_batches.key_id is
  'Non-reversible App Attest key fingerprint. It deliberately outlives the operational device row.';

alter table public.geofence_checkins
  drop constraint geofence_checkins_key_id_fkey,
  drop constraint geofence_checkins_participant_fkey,
  add constraint geofence_checkins_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict;

comment on column public.geofence_checkins.key_id is
  'Non-reversible App Attest key fingerprint retained after device revocation or pruning.';

-- Raw receipts are independently retained and pruned; removing the operational
-- key must never be their accidental retention policy.
alter table app.device_attestation_receipts
  drop constraint device_attestation_receipts_key_id_fkey;

comment on column app.device_attestation_receipts.key_id is
  'Historical SHA-256 key fingerprint, not a cascading operational-device FK.';

-- A quarantine is the adjudicated fact that a raw hourly value required
-- review. The raw snapshot may age out without erasing this row.
alter table public.evidence_quarantines
  drop constraint evidence_quarantines_snapshot_id_fkey,
  drop constraint evidence_quarantines_participant_fkey,
  add constraint evidence_quarantines_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict;

comment on column public.evidence_quarantines.snapshot_id is
  'Immutable historical snapshot UUID. No FK: D81 raw-value pruning must not erase the quarantine.';

alter table public.timezone_change_requests
  drop constraint timezone_change_requests_participant_fkey,
  add constraint timezone_change_requests_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict;

alter table public.timezone_change_applied_events
  drop constraint timezone_change_applied_events_participant_fkey,
  add constraint timezone_change_applied_events_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict;

-- Once the account/profile cascade is gone, these ledgers can enforce the
-- "rows are never deleted" rule at the table boundary rather than by grants
-- alone.
create trigger contests_forbid_delete
  before delete on public.contests
  for each row execute function app.forbid_mutation();
create trigger contest_participants_forbid_delete
  before delete on public.contest_participants
  for each row execute function app.forbid_mutation();
create trigger ingest_batches_forbid_delete
  before delete on public.ingest_batches
  for each row execute function app.forbid_mutation();
create trigger geofence_checkins_forbid_delete
  before delete on public.geofence_checkins
  for each row execute function app.forbid_mutation();
create trigger evidence_quarantines_forbid_delete
  before delete on public.evidence_quarantines
  for each row execute function app.forbid_mutation();
create trigger evidence_quarantine_reviews_forbid_delete
  before delete on public.evidence_quarantine_reviews
  for each row execute function app.forbid_mutation();
create trigger timezone_change_requests_forbid_delete
  before delete on public.timezone_change_requests
  for each row execute function app.forbid_mutation();
create trigger timezone_change_reviews_forbid_delete
  before delete on public.timezone_change_reviews
  for each row execute function app.forbid_mutation();
create trigger timezone_change_applied_events_forbid_delete
  before delete on public.timezone_change_applied_events
  for each row execute function app.forbid_mutation();

create trigger contests_forbid_truncate
  before truncate on public.contests
  for each statement execute function app.forbid_mutation();
create trigger contest_participants_forbid_truncate
  before truncate on public.contest_participants
  for each statement execute function app.forbid_mutation();
create trigger ingest_batches_forbid_truncate
  before truncate on public.ingest_batches
  for each statement execute function app.forbid_mutation();
create trigger geofence_checkins_forbid_truncate
  before truncate on public.geofence_checkins
  for each statement execute function app.forbid_mutation();
create trigger evidence_quarantines_forbid_truncate
  before truncate on public.evidence_quarantines
  for each statement execute function app.forbid_mutation();
create trigger evidence_quarantine_reviews_forbid_truncate
  before truncate on public.evidence_quarantine_reviews
  for each statement execute function app.forbid_mutation();
create trigger timezone_change_requests_forbid_truncate
  before truncate on public.timezone_change_requests
  for each statement execute function app.forbid_mutation();
create trigger timezone_change_reviews_forbid_truncate
  before truncate on public.timezone_change_reviews
  for each statement execute function app.forbid_mutation();
create trigger timezone_change_applied_events_forbid_truncate
  before truncate on public.timezone_change_applied_events
  for each statement execute function app.forbid_mutation();

-- A participant departure from somebody else's pending contest is a lifecycle
-- event in its own right. Give D80 an addressable immutable entity so multiple
-- departures from the same contest cannot collapse under the outbox semantic
-- key.
create table app.account_deletion_participant_events (
  id            uuid primary key default gen_random_uuid(),
  contest_id    uuid not null,
  actor_id      uuid not null,
  from_status   public.contest_participant_status not null,
  to_status     public.contest_participant_status not null,
  occurred_at   timestamptz not null,
  reason        text not null default 'account_deleted'
    check (reason = 'account_deleted'),

  constraint account_deletion_participant_events_participant_fkey
    foreign key (contest_id, actor_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint account_deletion_participant_events_transition
    check (
      (from_status = 'accepted' and to_status = 'withdrawn')
      or (from_status = 'invited' and to_status = 'lapsed')
    )
);

create index account_deletion_participant_events_actor_idx
  on app.account_deletion_participant_events (actor_id, occurred_at);

create trigger account_deletion_participant_events_forbid_mutation
  before update or delete or truncate
  on app.account_deletion_participant_events
  for each statement execute function app.forbid_mutation();

revoke all on table app.account_deletion_participant_events
  from public, anon, authenticated, service_role;

create function app.emit_account_deletion_participant_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_event_id  uuid;
  v_recipient uuid;
  v_owner     name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  -- Normal authenticated participant transitions must not evaluate the
  -- private transaction marker helper. PostgreSQL may reorder boolean
  -- expressions, so keep this privilege boundary in its own statement.
  if current_user <> v_owner then
    return new;
  end if;

  if not app.is_account_deletion_transaction(new.user_id)
     or coalesce(
       pg_catalog.current_setting('app.account_deletion_actor', true),
       ''
     ) <> new.user_id::text
     or old.status = new.status
     or not (
       (old.status = 'accepted' and new.status = 'withdrawn')
       or (old.status = 'invited' and new.status = 'lapsed')
     )
  then
    return new;
  end if;

  select contest.created_by
    into v_recipient
  from public.contests contest
  where contest.id = new.contest_id;

  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;

  insert into app.account_deletion_participant_events (
    contest_id,
    actor_id,
    from_status,
    to_status,
    occurred_at
  )
  values (
    new.contest_id,
    new.user_id,
    old.status,
    new.status,
    clock_timestamp()
  )
  returning id into v_event_id;

  perform app.emit_notification_intent(
    v_recipient,
    'contest_participation_changed'::public.notification_event_type,
    v_event_id
  );

  return new;
end;
$$;

create trigger contest_participants_emit_account_deletion_event
  after update of status on public.contest_participants
  for each row execute function app.emit_account_deletion_participant_event();

create function public.get_account_deletion_participant_event(p_event_id uuid)
returns table (
  event_id      uuid,
  contest_id    uuid,
  actor_id      uuid,
  from_status   public.contest_participant_status,
  to_status     public.contest_participant_status,
  occurred_at   timestamptz,
  reason        text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid;
begin
  v_caller_id := app.require_active_caller();

  return query
  select
    participant_event.id,
    participant_event.contest_id,
    participant_event.actor_id,
    participant_event.from_status,
    participant_event.to_status,
    participant_event.occurred_at,
    participant_event.reason
  from app.account_deletion_participant_events participant_event
  join public.contests contest
    on contest.id = participant_event.contest_id
  where participant_event.id = p_event_id
    and contest.created_by = v_caller_id;
end;
$$;

comment on function public.get_account_deletion_participant_event(uuid) is
  'Exact-ID D80 resolver for the active contest creator who received an account-deletion participation intent.';

revoke all on function app.emit_account_deletion_participant_event()
  from public, anon, authenticated, service_role;

revoke all on function public.get_account_deletion_participant_event(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_account_deletion_participant_event(uuid)
  to authenticated;

-- ===========================================================================
-- SECTION 4 -- Versioned workflow scopes, cutoffs, holds, and capabilities
-- ===========================================================================

create type public.account_capability_scope_kind as enum (
  'contest_lineage',
  'case'
);

create table app.retention_policy_versions (
  version      text primary key,
  created_at   timestamptz not null default now(),
  description  text not null
);

create table app.raw_evidence_retention_rules (
  policy_version  text not null
    references app.retention_policy_versions (version) on delete restrict,
  evidence_kind  text not null,
  retain_for     interval not null,

  primary key (policy_version, evidence_kind),
  constraint raw_evidence_retention_rules_kind
    check (evidence_kind in (
      'exact_location',
      'metric_observation',
      'device_registration',
      'app_attest_receipt',
      'donation_receipt'
    )),
  constraint raw_evidence_retention_rules_positive
    check (
      pg_catalog.isfinite(retain_for)
      and retain_for > interval '0 seconds'
    )
);

create trigger retention_policy_versions_forbid_mutation
  before update or delete or truncate on app.retention_policy_versions
  for each statement execute function app.forbid_mutation();

create trigger raw_evidence_retention_rules_forbid_mutation
  before update or delete or truncate on app.raw_evidence_retention_rules
  for each statement execute function app.forbid_mutation();

insert into app.retention_policy_versions (version, description)
values (
  'raw-evidence-retention-v1',
  'D81 launch policy: exact locations 30 days; metrics, device raw material, and receipts 90 days.'
);

insert into app.raw_evidence_retention_rules (
  policy_version,
  evidence_kind,
  retain_for
)
values
  ('raw-evidence-retention-v1', 'exact_location',       interval '30 days'),
  ('raw-evidence-retention-v1', 'metric_observation',  interval '90 days'),
  ('raw-evidence-retention-v1', 'device_registration', interval '90 days'),
  ('raw-evidence-retention-v1', 'app_attest_receipt',  interval '90 days'),
  ('raw-evidence-retention-v1', 'donation_receipt',    interval '90 days');

-- Each registration captures the policy in force when it is created. Future
-- policy migrations may change the default without silently rewriting existing
-- devices or their receipt-retention promise.
alter table public.device_attestations
  add column retention_policy_version text not null
    default 'raw-evidence-retention-v1'
    references app.retention_policy_versions (version) on delete restrict;

create trigger device_attestations_freeze_retention_policy
  before update on public.device_attestations
  for each row execute function app.forbid_column_change(
    'retention_policy_version'
  );

create table app.workflow_scopes (
  scope_kind                public.account_capability_scope_kind not null,
  scope_id                  uuid not null,
  contest_id                uuid
    references public.contests (id) on delete restrict,
  workflow_open             boolean not null default true,
  user_terminal_at          timestamptz,
  operator_open_until       timestamptz,
  retention_policy_version  text not null default 'raw-evidence-retention-v1'
    references app.retention_policy_versions (version) on delete restrict,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  primary key (scope_kind, scope_id),
  constraint workflow_scopes_contest_lineage_identity
    check (
      scope_kind <> 'contest_lineage'
      or (contest_id is not null and contest_id = scope_id)
    ),
  constraint workflow_scopes_cutoff_has_finality
    check (
      (user_terminal_at is null and operator_open_until is null)
      or (
        user_terminal_at is not null
        and operator_open_until is not null
        and operator_open_until >= user_terminal_at
      )
    ),
  constraint workflow_scopes_cutoffs_finite
    check (
      (user_terminal_at is null or pg_catalog.isfinite(user_terminal_at))
      and (
        operator_open_until is null
        or pg_catalog.isfinite(operator_open_until)
      )
    )
);

comment on column app.workflow_scopes.operator_open_until is
  'Persisted D78/D81 admission cutoff. Capabilities and raw evidence remain reachable through this instant.';

create trigger workflow_scopes_forbid_delete
  before delete or truncate on app.workflow_scopes
  for each statement execute function app.forbid_mutation();

create table app.workflow_scope_actors (
  scope_kind             public.account_capability_scope_kind not null,
  scope_id               uuid not null,
  actor_id               uuid not null,
  covered_by_contest_id  uuid
    references public.contests (id) on delete restrict,
  created_at             timestamptz not null default now(),

  primary key (scope_kind, scope_id, actor_id),
  constraint workflow_scope_actors_scope_fkey
    foreign key (scope_kind, scope_id)
    references app.workflow_scopes (scope_kind, scope_id)
    on delete restrict
);

-- Profiles can never be deleted after this migration, so an insert-time
-- existence assertion gives the same durable referential guarantee without an
-- FK KEY SHARE row lock. That lock would invert activation's contest-first
-- order against deletion's actor-first order.
create function app.assert_workflow_scope_actor_exists()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = new.actor_id
  ) then
    raise exception 'workflow scope actor does not exist'
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$$;

create trigger workflow_scope_actors_assert_actor
  before insert on app.workflow_scope_actors
  for each row execute function app.assert_workflow_scope_actor_exists();

create index workflow_scope_actors_actor_idx
  on app.workflow_scope_actors (actor_id, scope_kind, scope_id);

create trigger workflow_scope_actors_forbid_mutation
  before update or delete or truncate on app.workflow_scope_actors
  for each statement execute function app.forbid_mutation();

create table app.retention_holds (
  id           uuid primary key default gen_random_uuid(),
  scope_kind   public.account_capability_scope_kind not null,
  scope_id     uuid not null,
  reason       text not null,
  expires_at   timestamptz not null,
  created_at   timestamptz not null default now(),

  constraint retention_holds_scope_fkey
    foreign key (scope_kind, scope_id)
    references app.workflow_scopes (scope_kind, scope_id)
    on delete restrict,
  constraint retention_holds_reason_length
    check (char_length(reason) between 1 and 500),
  constraint retention_holds_future_expiry
    check (
      pg_catalog.isfinite(expires_at)
      and expires_at > created_at
    )
);

create index retention_holds_active_scope_idx
  on app.retention_holds (scope_kind, scope_id, expires_at);

create trigger retention_holds_forbid_mutation
  before update or delete on app.retention_holds
  for each row execute function app.forbid_mutation();

create trigger retention_holds_forbid_truncate
  before truncate on app.retention_holds
  for each statement execute function app.forbid_mutation();

create table app.raw_evidence_retention_events (
  id              bigint generated always as identity primary key,
  scope_kind      public.account_capability_scope_kind,
  scope_id        uuid,
  evidence_kind   text not null,
  target_ref      text not null,
  target_digest   bytea not null
    check (octet_length(target_digest) = 32),
  policy_version  text not null
    references app.retention_policy_versions (version) on delete restrict,
  pruned_at       timestamptz not null default clock_timestamp(),

  constraint raw_evidence_retention_events_scope_fkey
    foreign key (scope_kind, scope_id)
    references app.workflow_scopes (scope_kind, scope_id)
    on delete restrict,
  constraint raw_evidence_retention_events_scope_pair
    check ((scope_kind is null) = (scope_id is null)),
  constraint raw_evidence_retention_events_pruned_at_finite
    check (pg_catalog.isfinite(pruned_at))
);

create index raw_evidence_retention_events_scope_idx
  on app.raw_evidence_retention_events (
    scope_kind,
    scope_id,
    pruned_at
  );

create index raw_evidence_retention_events_target_idx
  on app.raw_evidence_retention_events (evidence_kind, target_ref);

create trigger raw_evidence_retention_events_forbid_mutation
  before update or delete on app.raw_evidence_retention_events
  for each row execute function app.forbid_mutation();

create trigger raw_evidence_retention_events_forbid_truncate
  before truncate on app.raw_evidence_retention_events
  for each statement execute function app.forbid_mutation();

create table app.account_capabilities (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid not null
    references public.profiles (id) on delete restrict,
  scope_kind    public.account_capability_scope_kind not null,
  scope_id      uuid not null,
  secret_hash   bytea not null unique
    check (octet_length(secret_hash) = 32),
  created_at    timestamptz not null default clock_timestamp(),
  revoked_at    timestamptz,

  constraint account_capabilities_scope_fkey
    foreign key (scope_kind, scope_id)
    references app.workflow_scopes (scope_kind, scope_id)
    on delete restrict,
  constraint account_capabilities_one_per_actor_scope
    unique (actor_id, scope_kind, scope_id),
  constraint account_capabilities_revocation_order
    check (revoked_at is null or revoked_at >= created_at)
);

create index account_capabilities_actor_idx
  on app.account_capabilities (actor_id, created_at);

create function app.guard_account_capability_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if to_jsonb(new) - 'revoked_at'
       is distinct from
     to_jsonb(old) - 'revoked_at'
     or old.revoked_at is not null
     or new.revoked_at is null
  then
    raise exception 'an account capability may only be revoked once'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger account_capabilities_guard_update
  before update on app.account_capabilities
  for each row execute function app.guard_account_capability_update();

create trigger account_capabilities_forbid_delete
  before delete or truncate on app.account_capabilities
  for each statement execute function app.forbid_mutation();

revoke all on table app.retention_policy_versions,
                    app.raw_evidence_retention_rules,
                    app.workflow_scopes,
                    app.workflow_scope_actors,
                    app.retention_holds,
                    app.raw_evidence_retention_events,
                    app.account_capabilities
  from public, anon, authenticated, service_role;

revoke all on function app.guard_account_capability_update()
  from public, anon, authenticated, service_role;

revoke all on function app.assert_workflow_scope_actor_exists()
  from public, anon, authenticated, service_role;

revoke all on sequence app.raw_evidence_retention_events_id_seq
  from public, anon, authenticated, service_role;

create function app.ensure_contest_workflow_scope(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_status public.contest_status;
begin
  select contest.status
    into v_status
  from public.contests contest
  where contest.id = p_contest_id;

  if v_status not in ('active', 'finalized') then
    return;
  end if;

  insert into app.workflow_scopes (
    scope_kind,
    scope_id,
    contest_id,
    workflow_open
  )
  values (
    'contest_lineage',
    p_contest_id,
    p_contest_id,
    true
  )
  on conflict (scope_kind, scope_id) do nothing;

  insert into app.workflow_scope_actors (
    scope_kind,
    scope_id,
    actor_id
  )
  select
    'contest_lineage'::public.account_capability_scope_kind,
    participant.contest_id,
    participant.user_id
  from public.contest_participants participant
  where participant.contest_id = p_contest_id
    and participant.status = 'accepted'
  on conflict (scope_kind, scope_id, actor_id) do nothing;
end;
$$;

create function app.ensure_contest_workflow_scope_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.ensure_contest_workflow_scope(new.id);
  return new;
end;
$$;

create trigger contests_ensure_workflow_scope
  after insert or update of status on public.contests
  for each row
  when (new.status in ('active', 'finalized'))
  execute function app.ensure_contest_workflow_scope_trigger();

select app.ensure_contest_workflow_scope(contest.id)
from public.contests contest
where contest.status in ('active', 'finalized');

create function app.issue_account_capability(
  p_actor_id   uuid,
  p_scope_kind public.account_capability_scope_kind,
  p_scope_id   uuid
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  if not exists (
    select 1
    from app.workflow_scope_actors scope_actor
    where scope_actor.scope_kind = p_scope_kind
      and scope_actor.scope_id = p_scope_id
      and scope_actor.actor_id = p_actor_id
  ) then
    raise exception 'actor is not covered by that workflow scope'
      using errcode = 'insufficient_privilege';
  end if;

  v_secret := 'gtcap1_' || pg_catalog.encode(
    extensions.gen_random_bytes(32),
    'hex'
  );

  insert into app.account_capabilities (
    actor_id,
    scope_kind,
    scope_id,
    secret_hash
  )
  values (
    p_actor_id,
    p_scope_kind,
    p_scope_id,
    extensions.digest(
      pg_catalog.convert_to(v_secret, 'UTF8'),
      'sha256'
    )
  );

  return v_secret;
end;
$$;

create function app.authorize_account_capability(
  p_secret     text,
  p_scope_kind public.account_capability_scope_kind,
  p_scope_id   uuid,
  p_at         timestamptz default clock_timestamp()
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select capability.actor_id
  from app.account_capabilities capability
  join public.profiles profile
    on profile.id = capability.actor_id
  where p_secret ~ '^gtcap1_[0-9a-f]{64}$'
    and capability.secret_hash = extensions.digest(
      pg_catalog.convert_to(p_secret, 'UTF8'),
      'sha256'
    )
    and capability.revoked_at is null
    and profile.deleted_at is not null
    and (
      (
        capability.scope_kind = p_scope_kind
        and capability.scope_id = p_scope_id
      )
      or exists (
        select 1
        from app.workflow_scope_actors requested_scope
        where capability.scope_kind = 'contest_lineage'
          and requested_scope.scope_kind = p_scope_kind
          and requested_scope.scope_id = p_scope_id
          and requested_scope.actor_id = capability.actor_id
          and requested_scope.covered_by_contest_id = capability.scope_id
      )
    )
    and exists (
      select 1
      from app.workflow_scopes horizon
      where (
        (
          horizon.scope_kind = capability.scope_kind
          and horizon.scope_id = capability.scope_id
        )
        or (
          capability.scope_kind = 'contest_lineage'
          and exists (
            select 1
            from app.workflow_scope_actors covered_scope
            where covered_scope.scope_kind = horizon.scope_kind
              and covered_scope.scope_id = horizon.scope_id
              and covered_scope.actor_id = capability.actor_id
              and covered_scope.covered_by_contest_id = capability.scope_id
          )
        )
      )
        and (
          horizon.workflow_open
          or horizon.operator_open_until > p_at
          or exists (
            select 1
            from app.retention_holds hold
            where hold.scope_kind = horizon.scope_kind
              and hold.scope_id = horizon.scope_id
              and hold.expires_at > p_at
          )
        )
    )
  limit 1;
$$;

comment on function app.authorize_account_capability(
  text,
  public.account_capability_scope_kind,
  uuid,
  timestamptz
) is
  'Resolves exact case capabilities or lineage-covered child scopes while any covered workflow/cutoff remains open.';

revoke all on function app.ensure_contest_workflow_scope(uuid),
                       app.ensure_contest_workflow_scope_trigger(),
                       app.issue_account_capability(
                         uuid,
                         public.account_capability_scope_kind,
                         uuid
                       ),
                       app.authorize_account_capability(
                         text,
                         public.account_capability_scope_kind,
                         uuid,
                         timestamptz
                       )
  from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 5 -- Active wrappers around every authenticated/service actor RPC
-- ===========================================================================

-- Preserve the established business functions unchanged behind private,
-- ungranted names. The public wrappers take the actor lock before even an
-- idempotent replay can return.
alter function public.find_profile_by_handle(text) set schema app;
alter function app.find_profile_by_handle(text)
  rename to find_profile_by_handle_unchecked;

alter function public.join_group_by_code(text) set schema app;
alter function app.join_group_by_code(text)
  rename to join_group_by_code_unchecked;

alter function public.rotate_group_join_code(uuid) set schema app;
alter function app.rotate_group_join_code(uuid)
  rename to rotate_group_join_code_unchecked;

alter function public.create_contest(
  text,
  public.contest_metric,
  public.contest_cadence,
  numeric,
  integer,
  timestamptz,
  timestamptz,
  text,
  uuid,
  smallint,
  public.contest_tie_break,
  uuid
) set schema app;
alter function app.create_contest(
  text,
  public.contest_metric,
  public.contest_cadence,
  numeric,
  integer,
  timestamptz,
  timestamptz,
  text,
  uuid,
  smallint,
  public.contest_tie_break,
  uuid
) rename to create_contest_unchecked;

alter function public.cancel_contest(uuid) set schema app;
alter function app.cancel_contest(uuid)
  rename to cancel_contest_unchecked;

alter function public.request_timezone_change(uuid, text) set schema app;
alter function app.request_timezone_change(uuid, text)
  rename to request_timezone_change_unchecked;

alter function public.review_timezone_change(uuid, boolean) set schema app;
alter function app.review_timezone_change(uuid, boolean)
  rename to review_timezone_change_unchecked;

alter function public.review_evidence_quarantine(uuid, boolean) set schema app;
alter function app.review_evidence_quarantine(uuid, boolean)
  rename to review_evidence_quarantine_unchecked;

alter function public.register_device_key(
  uuid,
  bytea,
  bytea,
  bytea,
  public.attestation_environment
) set schema app;
alter function app.register_device_key(
  uuid,
  bytea,
  bytea,
  bytea,
  public.attestation_environment
) rename to register_device_key_unchecked;

alter function public.record_metric_batch(
  uuid,
  uuid,
  uuid,
  bytea,
  timestamptz,
  jsonb,
  bytea,
  bigint
) set schema app;
alter function app.record_metric_batch(
  uuid,
  uuid,
  uuid,
  bytea,
  timestamptz,
  jsonb,
  bytea,
  bigint
) rename to record_metric_batch_unchecked;

alter function public.record_geofence_checkin(
  uuid,
  uuid,
  uuid,
  uuid,
  bytea,
  jsonb,
  uuid,
  timestamptz,
  timestamptz,
  text,
  text,
  public.metric_provenance,
  bytea,
  bigint
) set schema app;
alter function app.record_geofence_checkin(
  uuid,
  uuid,
  uuid,
  uuid,
  bytea,
  jsonb,
  uuid,
  timestamptz,
  timestamptz,
  text,
  text,
  public.metric_provenance,
  bytea,
  bigint
) rename to record_geofence_checkin_unchecked;

create function public.find_profile_by_handle(p_handle text)
returns table (
  id            uuid,
  handle        extensions.citext,
  display_name  text,
  avatar_path   text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();

  return query
  select found.id, found.handle, found.display_name, found.avatar_path
  from app.find_profile_by_handle_unchecked(p_handle) found
  join public.profiles profile on profile.id = found.id
  where profile.deleted_at is null;
end;
$$;

create function public.join_group_by_code(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();
  return app.join_group_by_code_unchecked(p_code);
end;
$$;

create function public.rotate_group_join_code(p_group_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();
  return app.rotate_group_join_code_unchecked(p_group_id);
end;
$$;

create function public.create_contest(
  p_title            text,
  p_metric           public.contest_metric,
  p_cadence          public.contest_cadence,
  p_target_value     numeric,
  p_stake_cents      integer,
  p_starts_at        timestamptz,
  p_ends_at          timestamptz,
  p_timezone         text,
  p_charity_id       uuid,
  p_max_participants smallint default 8,
  p_tie_break        public.contest_tie_break default 'integrity_score',
  p_group_id         uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
    p_charity_id,
    p_max_participants,
    p_tie_break,
    p_group_id
  );
end;
$$;

create function public.cancel_contest(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_previous_lock_bypass text :=
    pg_catalog.current_setting('app.system_actor_lock_bypass', true);
begin
  perform app.require_active_caller();
  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    'on',
    true
  );

  begin
    perform app.cancel_contest_unchecked(p_contest_id);
  exception
    when others then
      perform pg_catalog.set_config(
        'app.system_actor_lock_bypass',
        coalesce(v_previous_lock_bypass, 'off'),
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    coalesce(v_previous_lock_bypass, 'off'),
    true
  );
end;
$$;

create function public.request_timezone_change(
  p_contest_id uuid,
  p_timezone   text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();
  return app.request_timezone_change_unchecked(p_contest_id, p_timezone);
end;
$$;

create function public.review_timezone_change(
  p_request_id uuid,
  p_approved   boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();
  perform app.review_timezone_change_unchecked(p_request_id, p_approved);
end;
$$;

create function public.review_evidence_quarantine(
  p_quarantine_id uuid,
  p_approved      boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.require_active_caller();
  perform app.review_evidence_quarantine_unchecked(
    p_quarantine_id,
    p_approved
  );
end;
$$;

create function public.register_device_key(
  p_user_id             uuid,
  p_key_id              bytea,
  p_public_key          bytea,
  p_attestation_receipt bytea,
  p_environment         public.attestation_environment
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_user_id]);
  return app.register_device_key_unchecked(
    p_user_id,
    p_key_id,
    p_public_key,
    p_attestation_receipt,
    p_environment
  );
end;
$$;

create function public.record_metric_batch(
  p_user_id         uuid,
  p_contest_id      uuid,
  p_client_batch_id uuid,
  p_payload_digest  bytea,
  p_observed_at     timestamptz,
  p_observations    jsonb,
  p_key_id          bytea default null,
  p_sign_count      bigint default null
)
returns table (
  batch_id         uuid,
  observation_count integer,
  replayed         boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_user_id]);

  return query
  select result.batch_id, result.observation_count, result.replayed
  from app.record_metric_batch_unchecked(
    p_user_id,
    p_contest_id,
    p_client_batch_id,
    p_payload_digest,
    p_observed_at,
    p_observations,
    p_key_id,
    p_sign_count
  ) result;
end;
$$;

create function public.record_geofence_checkin(
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
begin
  if p_user_id is null then
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_user_id]);

  return query
  select
    result.checkin_id,
    result.outcome,
    result.dwell_seconds,
    result.workout_overlap_seconds,
    result.replayed
  from app.record_geofence_checkin_unchecked(
    p_user_id,
    p_contest_id,
    p_geofence_id,
    p_client_checkin_id,
    p_payload_digest,
    p_locations,
    p_workout_id,
    p_workout_started_at,
    p_workout_ended_at,
    p_workout_activity_type,
    p_workout_source_bundle_id,
    p_workout_provenance,
    p_key_id,
    p_sign_count
  ) result;
end;
$$;

-- The challenge endpoint uses this narrow read before minting a challenge.
-- Registration and both ingest wrappers still repeat the lock in their own
-- transaction; this read is not treated as a substitute for write atomicity.
create function public.assert_active_actor(p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_user_id]);
end;
$$;

revoke all on function app.find_profile_by_handle_unchecked(text),
                       app.join_group_by_code_unchecked(text),
                       app.rotate_group_join_code_unchecked(uuid),
                       app.create_contest_unchecked(
                         text,
                         public.contest_metric,
                         public.contest_cadence,
                         numeric,
                         integer,
                         timestamptz,
                         timestamptz,
                         text,
                         uuid,
                         smallint,
                         public.contest_tie_break,
                         uuid
                       ),
                       app.cancel_contest_unchecked(uuid),
                       app.request_timezone_change_unchecked(uuid, text),
                       app.review_timezone_change_unchecked(uuid, boolean),
                       app.review_evidence_quarantine_unchecked(uuid, boolean),
                       app.register_device_key_unchecked(
                         uuid,
                         bytea,
                         bytea,
                         bytea,
                         public.attestation_environment
                       ),
                       app.record_metric_batch_unchecked(
                         uuid,
                         uuid,
                         uuid,
                         bytea,
                         timestamptz,
                         jsonb,
                         bytea,
                         bigint
                       ),
                       app.record_geofence_checkin_unchecked(
                         uuid,
                         uuid,
                         uuid,
                         uuid,
                         bytea,
                         jsonb,
                         uuid,
                         timestamptz,
                         timestamptz,
                         text,
                         text,
                         public.metric_provenance,
                         bytea,
                         bigint
                       )
  from public, anon, authenticated, service_role;

revoke all on function public.find_profile_by_handle(text),
                       public.join_group_by_code(text),
                       public.rotate_group_join_code(uuid),
                       public.create_contest(
                         text,
                         public.contest_metric,
                         public.contest_cadence,
                         numeric,
                         integer,
                         timestamptz,
                         timestamptz,
                         text,
                         uuid,
                         smallint,
                         public.contest_tie_break,
                         uuid
                       ),
                       public.cancel_contest(uuid),
                       public.request_timezone_change(uuid, text),
                       public.review_timezone_change(uuid, boolean),
                       public.review_evidence_quarantine(uuid, boolean),
                       public.register_device_key(
                         uuid,
                         bytea,
                         bytea,
                         bytea,
                         public.attestation_environment
                       ),
                       public.record_metric_batch(
                         uuid,
                         uuid,
                         uuid,
                         bytea,
                         timestamptz,
                         jsonb,
                         bytea,
                         bigint
                       ),
                       public.record_geofence_checkin(
                         uuid,
                         uuid,
                         uuid,
                         uuid,
                         bytea,
                         jsonb,
                         uuid,
                         timestamptz,
                         timestamptz,
                         text,
                         text,
                         public.metric_provenance,
                         bytea,
                         bigint
                       ),
                       public.assert_active_actor(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.find_profile_by_handle(text),
                          public.join_group_by_code(text),
                          public.rotate_group_join_code(uuid),
                          public.create_contest(
                            text,
                            public.contest_metric,
                            public.contest_cadence,
                            numeric,
                            integer,
                            timestamptz,
                            timestamptz,
                            text,
                            uuid,
                            smallint,
                            public.contest_tie_break,
                            uuid
                          ),
                          public.cancel_contest(uuid),
                          public.request_timezone_change(uuid, text),
                          public.review_timezone_change(uuid, boolean),
                          public.review_evidence_quarantine(uuid, boolean)
  to authenticated;

grant execute on function public.register_device_key(
                            uuid,
                            bytea,
                            bytea,
                            bytea,
                            public.attestation_environment
                          ),
                          public.record_metric_batch(
                            uuid,
                            uuid,
                            uuid,
                            bytea,
                            timestamptz,
                            jsonb,
                            bytea,
                            bigint
                          ),
                          public.record_geofence_checkin(
                            uuid,
                            uuid,
                            uuid,
                            uuid,
                            bytea,
                            jsonb,
                            uuid,
                            timestamptz,
                            timestamptz,
                            text,
                            text,
                            public.metric_provenance,
                            bytea,
                            bigint
                          ),
                          public.assert_active_actor(uuid)
  to service_role;

-- ===========================================================================
-- SECTION 6 -- One atomic, service-only account deletion RPC
-- ===========================================================================

create function public.delete_account(p_actor_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_profile       public.profiles;
  v_deleted_at    timestamptz;
  v_tombstone     extensions.citext;
  v_scope         record;
  v_secret        text;
  v_capabilities  jsonb := '[]'::jsonb;
  v_previous_lock_bypass text :=
    pg_catalog.current_setting('app.system_actor_lock_bypass', true);
  v_previous_deletion_actor text :=
    pg_catalog.current_setting('app.account_deletion_actor', true);
begin
  if p_actor_id is null then
    raise exception 'actor id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  select profile.*
    into v_profile
  from public.profiles profile
  join auth.users auth_user on auth_user.id = profile.id
  where profile.id = p_actor_id
  for update of profile;

  if not found or v_profile.deleted_at is not null then
    -- Missing, never-onboarded, and already-deleted actors intentionally share
    -- one answer. A successful response is the sole plaintext-capability
    -- delivery and cannot be replayed.
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.account_deletion_transactions (
    transaction_id,
    backend_pid,
    actor_id
  )
  values (
    pg_catalog.txid_current(),
    pg_catalog.pg_backend_pid(),
    p_actor_id
  );

  -- Row triggers normally lock every authenticated or referenced actor. This
  -- transaction already owns the departing actor's profile lock and follows
  -- contest-first workflow locks below, so recursive actor locking would invert
  -- the order when two related accounts are deleted concurrently.
  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    'on',
    true
  );
  perform pg_catalog.set_config(
    'app.account_deletion_actor',
    p_actor_id::text,
    true
  );

  -- Match activation's deterministic contest order before locking participant
  -- rows. Future finalization and settlement functions use this same contest
  -- row as their first workflow serialization point.
  perform 1
  from public.contests contest
  where contest.created_by = p_actor_id
     or exists (
       select 1
       from public.contest_participants participant
       where participant.contest_id = contest.id
         and participant.user_id = p_actor_id
     )
  order by contest.starts_at, contest.id
  for update;

  perform 1
  from public.contest_participants participant
  where participant.user_id = p_actor_id
  order by participant.contest_id
  for update;

  -- Retention owns a device row before consulting any workflow scope that used
  -- it. Take every departing device in the same deterministic order before
  -- locking scopes, so deletion and retention cannot form a device/scope cycle.
  perform 1
  from public.device_attestations device
  where device.user_id = p_actor_id
  order by device.key_id
  for update;

  -- Materialize every current contest lineage before locking the complete
  -- actor-scope set. State changes and hold creation take these same scope rows,
  -- so capability delivery cannot race a cutoff extension or workflow reopen.
  for v_scope in
    select contest.id
    from public.contests contest
    join public.contest_participants participant
      on participant.contest_id = contest.id
    where participant.user_id = p_actor_id
      and participant.status = 'accepted'
      and contest.status in ('active', 'finalized')
    order by contest.id
  loop
    perform app.ensure_contest_workflow_scope(v_scope.id);
  end loop;

  perform 1
  from app.workflow_scopes scope
  join app.workflow_scope_actors scope_actor
    on scope_actor.scope_kind = scope.scope_kind
   and scope_actor.scope_id = scope.scope_id
  where scope_actor.actor_id = p_actor_id
  order by scope.scope_kind, scope.scope_id
  for update of scope;

  -- The deletion instant is the serialized workflow boundary, not the time the
  -- RPC happened to begin waiting for actor, contest, participant, or scope
  -- locks.
  v_deleted_at := clock_timestamp();

  -- A departing author cancels the whole pending agreement. The existing
  -- status trigger writes D80 cancellation intents in this transaction.
  update public.contest_participants participant
  set status = 'lapsed'
  from public.contests contest
  where contest.id = participant.contest_id
    and contest.created_by = p_actor_id
    and contest.status = 'pending'
    and participant.status = 'invited';

  update public.contests contest
  set status = 'cancelled',
      cancellation_reason = 'creator_cancelled',
      cancelled_at = v_deleted_at
  where contest.created_by = p_actor_id
    and contest.status = 'pending';

  -- In somebody else's pending contest, silence remains lapsed while a prior
  -- acceptance becomes an explicit withdrawal.
  update public.contest_participants participant
  set status = case participant.status
    when 'accepted' then 'withdrawn'::public.contest_participant_status
    when 'invited' then 'lapsed'::public.contest_participant_status
    else participant.status
  end
  from public.contests contest
  where contest.id = participant.contest_id
    and participant.user_id = p_actor_id
    and contest.created_by is distinct from p_actor_id
    and contest.status = 'pending'
    and participant.status in ('accepted', 'invited');

  -- Future result/obligation/dispute migrations add case scope actors before
  -- deletion. Any eligible covered child promotes its contest-lineage root,
  -- even when the root's own horizon has closed. That one bearer secret then
  -- reaches every lineage-covered child without issuing duplicate case tokens.
  for v_scope in
    with eligible_scope as (
      select
        scope_actor.scope_kind,
        scope_actor.scope_id,
        scope_actor.covered_by_contest_id
      from app.workflow_scope_actors scope_actor
      join app.workflow_scopes scope
        on scope.scope_kind = scope_actor.scope_kind
       and scope.scope_id = scope_actor.scope_id
      where scope_actor.actor_id = p_actor_id
        and (
          scope.workflow_open
          or scope.operator_open_until > v_deleted_at
          or exists (
            select 1
            from app.retention_holds hold
            where hold.scope_kind = scope.scope_kind
              and hold.scope_id = scope.scope_id
              and hold.expires_at > v_deleted_at
          )
        )
    )
    select distinct
      case
        when lineage.scope_id is not null
          then 'contest_lineage'::public.account_capability_scope_kind
        else eligible_scope.scope_kind
      end as scope_kind,
      coalesce(lineage.scope_id, eligible_scope.scope_id) as scope_id
    from eligible_scope
    left join app.workflow_scope_actors lineage
      on lineage.scope_kind = 'contest_lineage'
     and lineage.scope_id = eligible_scope.covered_by_contest_id
     and lineage.actor_id = p_actor_id
    order by scope_kind, scope_id
  loop
    v_secret := app.issue_account_capability(
      p_actor_id,
      v_scope.scope_kind,
      v_scope.scope_id
    );

    v_capabilities := v_capabilities || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'kind', v_scope.scope_kind,
        'scopeId', v_scope.scope_id,
        'secret', v_secret
      )
    );
  end loop;

  -- Social and delivery state has no retained-history purpose.
  delete from public.friendships friendship
  where p_actor_id in (friendship.user_a, friendship.user_b);

  delete from public.blocks block_edge
  where p_actor_id in (block_edge.blocker_id, block_edge.blocked_id);

  delete from public.group_members membership
  where membership.user_id = p_actor_id;

  -- The current public key/counter is operational state. Revoke it in place;
  -- historical batches and check-ins retain key_id as a digest fingerprint.
  update public.device_attestations device
  set revoked_at = coalesce(device.revoked_at, v_deleted_at)
  where device.user_id = p_actor_id
    and device.revoked_at is null;

  update app.profile_handle_claims claim
  set retained_at = v_deleted_at
  where claim.actor_id = p_actor_id
    and claim.handle_digest =
        app.deleted_handle_digest(v_profile.handle::text);

  if not found then
    raise exception 'profile handle claim is missing'
      using errcode = 'integrity_constraint_violation';
  end if;

  v_tombstone := app.generate_tombstone_handle();

  update public.profiles profile
  set handle = v_tombstone,
      display_name = 'Deleted member',
      avatar_path = null,
      timezone = 'UTC',
      deleted_at = v_deleted_at
  where profile.id = p_actor_id;

  delete from app.active_profile_auth_bindings binding
  where binding.actor_id = p_actor_id;

  if not found then
    raise exception 'active profile authentication binding is missing'
      using errcode = 'integrity_constraint_violation';
  end if;

  -- Auth identities, sessions, and provider metadata disappear only after
  -- every durable transition above has succeeded. The BEFORE DELETE guard sees
  -- the complete tombstone and permits this one path.
  delete from auth.users auth_user
  where auth_user.id = p_actor_id;

  if not found then
    raise exception 'account authentication identity disappeared during deletion'
      using errcode = 'serialization_failure';
  end if;

  delete from app.account_deletion_transactions deletion
  where deletion.transaction_id = pg_catalog.txid_current()
    and deletion.backend_pid = pg_catalog.pg_backend_pid()
    and deletion.actor_id = p_actor_id;

  if not found then
    raise exception 'account deletion transaction marker is missing'
      using errcode = 'serialization_failure';
  end if;

  perform pg_catalog.set_config(
    'app.system_actor_lock_bypass',
    coalesce(v_previous_lock_bypass, 'off'),
    true
  );
  perform pg_catalog.set_config(
    'app.account_deletion_actor',
    coalesce(v_previous_deletion_actor, ''),
    true
  );

  return pg_catalog.jsonb_build_object(
    'deletedAt', v_deleted_at,
    'capabilities', v_capabilities
  );
end;
$$;

comment on function public.delete_account(uuid) is
  'D81 atomic service-only deletion: pending lifecycle, capability minting, pseudonymization, device revocation, and auth removal.';

revoke all on function public.delete_account(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_account(uuid)
  to service_role;

commit;
