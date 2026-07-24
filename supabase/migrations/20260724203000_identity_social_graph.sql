-- M1 — Identity, friendships, groups, blocks.
--
-- The social graph every later milestone reads from. Four table families:
--
--   profiles       the app-level identity, one row per onboarded auth user
--   friendships    symmetric, one row per pair, request/accept lifecycle
--   groups         durable named crews with flat membership
--   blocks         directed, severs friendships, gates discovery
--
-- Conventions inherited from the baseline migration:
--   * extensions live in `extensions`, helpers in the private `app` schema
--   * every function declares an explicit `search_path`
--
-- ---------------------------------------------------------------------------
-- Why this file is ordered data model first, access model second
-- ---------------------------------------------------------------------------
-- Grouping each table with its own policies would read better, but it cannot be
-- done here: profile visibility depends on friendships, groups, and blocks,
-- while all three of those reference profiles. The dependency is genuinely
-- circular, and `language sql` helpers are parsed at creation time rather than
-- at first call, so every predicate must follow every table it reads. Hence:
-- tables, then triggers, then the access model as one piece. The access model
-- interlocks anyway and is better read whole.
--
-- ---------------------------------------------------------------------------
-- Two idioms used throughout
-- ---------------------------------------------------------------------------
-- 1. `(select auth.uid())` rather than bare `auth.uid()`. The subquery form is
--    hoisted into an InitPlan and evaluated once per statement instead of once
--    per row. On a friends-of-friends read that is one call, not thousands.
--
-- 2. citext comparisons are written `lower(col::text) = lower($1)`, never
--    `col = $1`. The citext `=` operator lives in the `extensions` schema, so
--    under `search_path = ''` it is not visible; the planner then falls back to
--    `text = text` through citext's implicit cast and the comparison silently
--    becomes case-sensitive. The unique *index* on a citext column is
--    unaffected — its operator class is resolved at DDL time and stored in the
--    catalog — which is why handles stay case-insensitively unique regardless.
--    See DECISIONS.md D14.

-- ===========================================================================
-- SECTION 1 — Generic trigger helpers
-- ===========================================================================
-- No table references, so these may precede the tables. Both are written for
-- reuse by later milestones.

-- Rejects an UPDATE that changes any column named in the trigger arguments.
-- Complements app.forbid_mutation(): that one freezes a whole table, this one
-- freezes specific columns on a table that is otherwise mutable.
create or replace function app.forbid_column_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  col text;
  before_row jsonb := to_jsonb(old);
  after_row  jsonb := to_jsonb(new);
begin
  foreach col in array tg_argv loop
    if (before_row -> col) is distinct from (after_row -> col) then
      raise exception 'column %.%.% is immutable',
        tg_table_schema, tg_table_name, col
        using errcode = 'restrict_violation';
    end if;
  end loop;
  return new;
end;
$$;

comment on function app.forbid_column_change() is
  'BEFORE UPDATE trigger. Rejects changes to the columns named in TG_ARGV.';

-- Validates an IANA timezone name against the zones Postgres itself accepts.
-- A CHECK constraint cannot do this: pg_timezone_names is a view and the lookup
-- is not immutable. M2 reuses this for contest_participants.timezone, where a
-- frozen-at-join zone is load-bearing for daily cadence (DECISIONS.md D5).
create or replace function app.assert_valid_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  col text := tg_argv[0];
  tz  text := to_jsonb(new) ->> col;
begin
  if tz is not null
     and not exists (select 1 from pg_catalog.pg_timezone_names where name = tz)
  then
    raise exception 'invalid IANA timezone %.%.%: %',
      tg_table_schema, tg_table_name, col, tz
      using errcode = 'invalid_parameter_value';
  end if;
  return new;
end;
$$;

comment on function app.assert_valid_timezone() is
  'BEFORE INSERT OR UPDATE trigger. Asserts TG_ARGV[0] holds a zone Postgres knows.';

-- A join code is a capability: anyone holding one can join the group. So it is
-- drawn from a CSPRNG, not random(), which is seeded and predictable.
--
-- The alphabet is 32 characters — digits 2-9 plus A-Z without I or O. Two
-- properties fall out of that size: 256 is an exact multiple of 32, so the
-- modulo below introduces no bias, and 8 characters carry a full 40 bits.
--
-- plpgsql, so the reference to public.groups resolves at call time and this can
-- be created before that table exists — which it must be, being its DEFAULT.
create or replace function app.generate_join_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  code  text;
  bytes bytea;
begin
  for _attempt in 1..20 loop
    code  := '';
    bytes := extensions.gen_random_bytes(8);

    for i in 0..7 loop
      code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
    end loop;

    if not exists (
      select 1 from public.groups where lower(join_code::text) = lower(code)
    ) then
      return code;
    end if;
  end loop;

  -- Unreachable short of the CSPRNG failing: at 40 bits, twenty consecutive
  -- collisions is not a thing that happens. Raise rather than return a dup.
  raise exception 'could not generate a unique group join code';
end;
$$;

comment on function app.generate_join_code() is
  'Unguessable 8-character group join code, checked for uniqueness before return.';

-- ===========================================================================
-- SECTION 2 — Tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- One row per *onboarded* user. A row in auth.users without one here is a user
-- mid-signup who has not yet picked a handle — a legitimate state, not a broken
-- one, which is why no trigger auto-creates profiles. "A profile exists" is the
-- app's definition of "onboarding finished".
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  handle        extensions.citext not null unique,
  display_name  text not null,
  avatar_path   text,
  timezone      text not null default 'UTC',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- 3-30 chars, leading letter, ASCII only. The ASCII restriction is what makes
  -- `lower(handle::text)` and citext's own case folding provably agree, so the
  -- unique index and every lookup in this file mean the same thing by "equal".
  constraint profiles_handle_format
    check (handle::text ~ '^[A-Za-z][A-Za-z0-9_]{2,29}$'),

  -- Names the app itself would answer to. An @support that messages you about a
  -- settlement is a phishing surface, and this is a money-pledge app.
  constraint profiles_handle_not_reserved
    check (lower(handle::text) <> all (array[
      'admin', 'administrator', 'gametime', 'help', 'support',
      'root', 'system', 'moderator', 'security', 'billing'
    ])),

  constraint profiles_display_name_length
    check (char_length(display_name) between 1 and 50)
);

comment on table public.profiles is
  'App-level identity. Existence of a row means onboarding completed.';
comment on column public.profiles.handle is
  'Case-preserving, case-insensitively unique. Compare via lower(handle::text).';
comment on column public.profiles.avatar_path is
  'Object path within the avatars Storage bucket. Not a URL.';
comment on column public.profiles.timezone is
  'Default zone offered when joining a contest. The contest freezes its own copy.';

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------
-- Symmetric, so stored once per pair under a canonical ordering rather than as
-- two mirrored directed rows. `user_a < user_b` plus the primary key is what
-- makes "at most one friendship per pair" a database invariant instead of an
-- application convention — no pair of concurrent requests can produce two rows,
-- in either order. Direction, which still matters for who may accept, is
-- carried by requested_by.
create type public.friendship_status as enum ('pending', 'accepted');

create table public.friendships (
  user_a        uuid not null references public.profiles (id) on delete cascade,
  user_b        uuid not null references public.profiles (id) on delete cascade,
  requested_by  uuid not null references public.profiles (id) on delete cascade,
  status        public.friendship_status not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  accepted_at   timestamptz,

  primary key (user_a, user_b),

  constraint friendships_canonical_order check (user_a < user_b),
  constraint friendships_requester_is_party check (requested_by in (user_a, user_b)),
  constraint friendships_accepted_at_matches_status
    check ((status = 'accepted') = (accepted_at is not null))
);

comment on table public.friendships is
  'One row per pair, canonically ordered user_a < user_b. Declining deletes the row.';
comment on column public.friendships.requested_by is
  'Who asked. The other party is the only one who may accept.';

-- The reverse-direction lookup. The primary key already indexes user_a.
create index friendships_user_b_idx on public.friendships (user_b);

-- ---------------------------------------------------------------------------
-- groups and group_members
-- ---------------------------------------------------------------------------
-- Durable crews, flat membership: no owner, no admin, no roles. created_by is
-- informational and nulls out if that account is deleted, so a group outlives
-- whoever happened to start it.
--
-- Two consequences of flat membership worth stating outright, because both are
-- deliberate rather than missing:
--   * nobody can remove anyone else. You can only leave.
--   * nobody can delete the group. It disappears when the last member leaves,
--     which is the only rule that cannot be used by one member to destroy
--     shared history the others still want.
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  join_code   extensions.citext not null unique default app.generate_join_code(),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint groups_name_length check (char_length(name) between 1 and 50),

  -- Shape of what app.generate_join_code() produces. A backstop, not the real
  -- control: UPDATE on this column is not granted to clients at all (section 7),
  -- because a member allowed to choose the code could choose a guessable one.
  constraint groups_join_code_format
    check (join_code::text ~ '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$')
);

comment on table public.groups is
  'A durable crew. Flat membership: no roles, no owner, no removal of others.';
comment on column public.groups.join_code is
  'Bearer capability. Anyone holding it may join, subject to blocks.';
comment on column public.groups.created_by is
  'Informational only. Confers no privilege and nulls out on account deletion.';

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),

  primary key (group_id, user_id)
);

comment on table public.group_members is
  'Group roster. Joins go through public.join_group_by_code(); leaves are direct deletes.';

create index group_members_user_idx on public.group_members (user_id);

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------
-- Directed: A blocking B says nothing about B blocking A. Visibility, though,
-- is deliberately one-sided — there is no policy under which the blocked user
-- can read the row, so being blocked is not observable through the Data API.
create table public.blocks (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),

  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

comment on table public.blocks is
  'Directed blocks. Readable only by the blocker; blocking severs any friendship.';

create index blocks_blocked_idx on public.blocks (blocked_id);

-- ===========================================================================
-- SECTION 3 — Triggers
-- ===========================================================================

-- Keeps accepted_at consistent with status so callers only ever set status, and
-- the check constraint above cannot be tripped by an honest client.
create or replace function app.stamp_friendship_accepted()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'accepted' then
    new.accepted_at := coalesce(new.accepted_at, now());
  else
    new.accepted_at := null;
  end if;
  return new;
end;
$$;

comment on function app.stamp_friendship_accepted() is
  'BEFORE INSERT OR UPDATE on friendships. Derives accepted_at from status.';

-- The creator becomes the first member. Doing this in a trigger rather than an
-- RPC keeps `insert into groups` working as a plain PostgREST call while making
-- "a group always has at least one member" true from the first instant, which
-- is what the last-one-out rule relies on.
create or replace function app.add_group_creator_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is not null then
    insert into public.group_members (group_id, user_id)
    values (new.id, new.created_by)
    on conflict do nothing;
  end if;
  return null;
end;
$$;

comment on function app.add_group_creator_as_member() is
  'AFTER INSERT on groups. Seeds the roster so a group is never memberless.';

-- Last one out deletes the group. Terminates when reached via the cascade from
-- `delete from groups`: the parent row is already gone, so the inner DELETE
-- matches nothing and the trigger does not re-fire.
create or replace function app.delete_group_when_empty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.group_members where group_id = old.group_id
  ) then
    delete from public.groups where id = old.group_id;
  end if;
  return null;
end;
$$;

comment on function app.delete_group_when_empty() is
  'AFTER DELETE on group_members. Reaps a group once its last member leaves.';

-- Blocking severs an existing friendship. Definer rights matter: the row goes
-- whether or not the blocker could have deleted it under their own policy.
create or replace function app.sever_friendship_on_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.friendships
  where user_a = least(new.blocker_id, new.blocked_id)
    and user_b = greatest(new.blocker_id, new.blocked_id);
  return null;
end;
$$;

comment on function app.sever_friendship_on_block() is
  'AFTER INSERT on blocks. Drops any friendship between the pair.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function app.set_updated_at();

create trigger profiles_freeze_columns
  before update on public.profiles
  for each row execute function app.forbid_column_change('id', 'created_at');

create trigger profiles_validate_timezone
  before insert or update on public.profiles
  for each row execute function app.assert_valid_timezone('timezone');

create trigger friendships_stamp_accepted
  before insert or update on public.friendships
  for each row execute function app.stamp_friendship_accepted();

create trigger friendships_set_updated_at
  before update on public.friendships
  for each row execute function app.set_updated_at();

create trigger friendships_freeze_columns
  before update on public.friendships
  for each row execute function
    app.forbid_column_change('user_a', 'user_b', 'requested_by', 'created_at');

create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function app.set_updated_at();

create trigger groups_freeze_columns
  before update on public.groups
  for each row execute function
    app.forbid_column_change('id', 'created_by', 'created_at');

create trigger groups_seed_membership
  after insert on public.groups
  for each row execute function app.add_group_creator_as_member();

create trigger group_members_reap_empty_group
  after delete on public.group_members
  for each row execute function app.delete_group_when_empty();

create trigger blocks_sever_friendship
  after insert on public.blocks
  for each row execute function app.sever_friendship_on_block();

-- ===========================================================================
-- SECTION 4 — RLS predicates
-- ===========================================================================
-- All SECURITY DEFINER, all STABLE. Definer rights are what stop a policy that
-- reads a table from re-entering that table's own policy and recursing.

create or replace function app.is_blocked_either_way(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

comment on function app.is_blocked_either_way(uuid, uuid) is
  'True if either user has blocked the other. Blocks are directed; visibility is not.';

create or replace function app.is_friend(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.friendships
    where status = 'accepted'
      and user_a = least(a, b)
      and user_b = greatest(a, b)
  );
$$;

comment on function app.is_friend(uuid, uuid) is
  'True if an accepted friendship exists. Pending requests do not count.';

create or replace function app.is_group_member(gid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = uid
  );
$$;

comment on function app.is_group_member(uuid, uuid) is
  'True if uid belongs to gid. Definer rights break group_members policy recursion.';

create or replace function app.shares_group(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members ma
    join public.group_members mb on mb.group_id = ma.group_id
    where ma.user_id = a and mb.user_id = b
  );
$$;

comment on function app.shares_group(uuid, uuid) is
  'True if both users belong to at least one group in common.';

-- ===========================================================================
-- SECTION 5 — Row level security
-- ===========================================================================

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.blocks enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- Read: yourself always; otherwise a friend or someone you share a group with,
-- and never across a block. M2 adds contest co-participants to this list.
create policy profiles_select_visible on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (
      not app.is_blocked_either_way(id, (select auth.uid()))
      and (
        app.is_friend(id, (select auth.uid()))
        or app.shares_group(id, (select auth.uid()))
      )
    )
  );

create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No delete policy, deliberately. A profile is referenced by contest history
-- and settlement obligations; letting a client delete one would let a losing
-- participant erase a pledge. Account deletion goes through auth.users and
-- cascades, which is an out-of-band operation with its own audit trail.

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------
create policy friendships_select_own on public.friendships
  for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

-- Send a request: you must be a party to it, you must be the requester, it
-- starts pending, and a block in either direction stops it.
create policy friendships_insert_request on public.friendships
  for insert to authenticated
  with check (
    requested_by = (select auth.uid())
    and (select auth.uid()) in (user_a, user_b)
    and status = 'pending'
    and not app.is_blocked_either_way(user_a, user_b)
  );

-- The only legal update is the recipient accepting a pending request. Note
-- `auth.uid() <> requested_by`: the requester cannot accept their own request.
-- The WITH CHECK pins the destination state, so an accepted friendship cannot
-- be walked back to pending to reset the clock.
create policy friendships_update_accept on public.friendships
  for update to authenticated
  using (
    (select auth.uid()) in (user_a, user_b)
    and (select auth.uid()) <> requested_by
    and status = 'pending'
  )
  with check (status = 'accepted');

-- One policy covers cancel, decline, and unfriend — all three are "either party
-- removes the row", and which one it reads as depends only on who acts and on
-- the current status.
create policy friendships_delete_own on public.friendships
  for delete to authenticated
  using ((select auth.uid()) in (user_a, user_b));

-- ---------------------------------------------------------------------------
-- groups
-- ---------------------------------------------------------------------------
create policy groups_select_member on public.groups
  for select to authenticated
  using (app.is_group_member(id, (select auth.uid())));

create policy groups_insert_self on public.groups
  for insert to authenticated
  with check (created_by = (select auth.uid()));

-- Any member may administer the group, which under flat membership means
-- renaming it and rotating its code. The policy authorises the row; the
-- column-level grant in section 7 is what limits this to `name`, with rotation
-- going through public.rotate_group_join_code() so the new code stays generated
-- rather than chosen.
create policy groups_update_member on public.groups
  for update to authenticated
  using (app.is_group_member(id, (select auth.uid())))
  with check (app.is_group_member(id, (select auth.uid())));

-- No delete policy: see the last-one-out trigger in section 3.

create policy group_members_select_comembers on public.group_members
  for select to authenticated
  using (app.is_group_member(group_id, (select auth.uid())));

-- No insert policy. Joining requires knowing the code, which is not a property
-- of a row, so it cannot be expressed as a policy — it is join_group_by_code().

create policy group_members_delete_self on public.group_members
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------
-- Every policy is blocker-only, including SELECT. That asymmetry is the point:
-- the blocked party cannot discover the block through the Data API.
create policy blocks_select_own on public.blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy blocks_insert_own on public.blocks
  for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy blocks_delete_own on public.blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- No update policy. A block carries no mutable state; unblocking is a delete.

-- ===========================================================================
-- SECTION 6 — Callable API
-- ===========================================================================

-- Discovery cannot be a row policy. RLS answers "may this caller read this
-- row", not "did this caller already know the handle" — and a policy permissive
-- enough to allow lookup is permissive enough to allow enumerating every user.
--
-- So the base table stays friends-and-groups-only and discovery is this
-- function: exact match, no prefix, no fuzzy, no listing. Knowing the handle is
-- the capability. Blocks are honoured in both directions, and the four columns
-- returned are the minimum needed to render "add @handle?".
create or replace function public.find_profile_by_handle(p_handle text)
returns table (
  id            uuid,
  handle        extensions.citext,
  display_name  text,
  avatar_path   text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.handle, p.display_name, p.avatar_path
  from public.profiles p
  where (select auth.uid()) is not null
    and lower(p.handle::text) = lower(p_handle)
    and not app.is_blocked_either_way(p.id, (select auth.uid()));
$$;

comment on function public.find_profile_by_handle(text) is
  'Resolve one exact handle to a minimal profile card. Exact match only: the '
  'profiles table is not enumerable and this is not a search.';

create or replace function public.join_group_by_code(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'complete onboarding before joining a group'
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_group_id
  from public.groups
  where lower(join_code::text) = lower(p_code);

  -- Same error whether the code is malformed or simply not in use. Telling the
  -- two apart would turn this function into an oracle for probing valid codes.
  if v_group_id is null then
    raise exception 'no group matches that join code'
      using errcode = 'no_data_found';
  end if;

  -- A block has to mean something here, or it is trivially routed around by
  -- joining a group the blocked party is in. Checked in both directions.
  if exists (
    select 1
    from public.group_members m
    where m.group_id = v_group_id
      and app.is_blocked_either_way(m.user_id, v_uid)
  ) then
    raise exception 'cannot join a group containing a blocked user'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.group_members (group_id, user_id)
  values (v_group_id, v_uid)
  on conflict (group_id, user_id) do nothing;

  return v_group_id;
end;
$$;

comment on function public.join_group_by_code(text) is
  'Join the group holding this code. Idempotent; refuses across a block.';

-- Rotation exists so a code can be retired after it leaks — a group chat with a
-- join link in it outlives the people who should be in the group. The new code
-- is generated, never supplied: a member who could name it could pick something
-- guessable, which is why UPDATE on groups.join_code is withheld from clients.
create or replace function public.rotate_group_join_code(p_group_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_code text;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- Membership is the only credential; flat membership means every member
  -- administers. Non-members get the same error either way, so this does not
  -- reveal whether the group exists.
  if not app.is_group_member(p_group_id, v_uid) then
    raise exception 'not a member of that group'
      using errcode = 'insufficient_privilege';
  end if;

  v_code := app.generate_join_code();

  update public.groups set join_code = v_code where id = p_group_id;

  return v_code;
end;
$$;

comment on function public.rotate_group_join_code(uuid) is
  'Issue a fresh join code for a group. Any member may call it; the code is generated.';

-- ===========================================================================
-- SECTION 7 — Privileges
-- ===========================================================================
-- RLS decides which rows; these grants decide which verbs, and the two are
-- independent. Supabase ships default privileges that hand anon and
-- authenticated ALL on new tables in `public`, so the revoke below is not
-- belt-and-braces — without it, anon holds DELETE on every table above and is
-- stopped only by the absence of a policy.

revoke all on public.profiles, public.friendships, public.groups,
              public.group_members, public.blocks
  from anon, authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert on public.groups to authenticated;
grant select, delete on public.group_members to authenticated;
grant select, insert, delete on public.blocks to authenticated;

-- Column-level, not table-level. `name` is the only thing on a group a client
-- may rewrite directly; join_code is a capability and goes through
-- rotate_group_join_code() so it stays generated rather than chosen.
grant update (name) on public.groups to authenticated;

-- Deliberately withheld, each enforced by a missing grant rather than only by a
-- missing policy:
--   profiles       DELETE          — accounts are removed through auth.users
--   groups         DELETE          — the last-one-out trigger owns this
--   groups         UPDATE join_code — rotate_group_join_code() owns this
--   group_members  INSERT          — join_group_by_code() owns this
--   group_members  UPDATE          — joined_at is not the client's to rewrite
--   blocks         UPDATE          — unblocking is a delete

revoke all on function public.find_profile_by_handle(text) from public, anon;
revoke all on function public.join_group_by_code(text) from public, anon;
revoke all on function public.rotate_group_join_code(uuid) from public, anon;
grant execute on function public.find_profile_by_handle(text) to authenticated;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.rotate_group_join_code(uuid) to authenticated;
