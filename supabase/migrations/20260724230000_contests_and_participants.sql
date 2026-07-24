-- M2 — Contests, invitations, and the participant state machine.
--
-- What a contest is, in this schema: a set of terms authored by one person, a
-- roster of people who individually agreed to those terms, and a window. The
-- terms are frozen at creation, the roster freezes when the window opens, and
-- nothing after that can rewrite either. Everything below exists to make those
-- three sentences true at a layer no client can route around.
--
--   charities             curated reference data; the donation destinations
--   contests              the terms and the window
--   contest_participants  the roster and the invitation lifecycle, one table
--
-- Conventions inherited: extensions in `extensions`, RLS helpers in the private
-- `app` schema, every function with an explicit search_path, citext compared as
-- lower(col::text) (DECISIONS.md D14).
--
-- ---------------------------------------------------------------------------
-- Three things that are deliberately absent
-- ---------------------------------------------------------------------------
-- * No `kind` column distinguishing a duel from a group contest. D4 settled
--   that a duel is the N=2 case of the same structure, so the distinction is
--   `max_participants = 2` and nothing else. A separate enum would be a second
--   source of truth for a fact already stored.
-- * No DELETE anywhere. A contest that happened is evidence, and a participant
--   who withdrew is a fact about the roster. Withdrawal is a status.
-- * No client UPDATE on contests at all. The terms are immutable and the status
--   moves only through the functions in section 6, so there is no column left
--   for a client to write.
--
-- ---------------------------------------------------------------------------
-- Why invitations are not their own table
-- ---------------------------------------------------------------------------
-- An invitation and a participation are the same row at different points in its
-- life, exactly as a friend request and a friendship are (D15). Two tables
-- would mean two RLS surfaces, a promotion step, and a window in which a person
-- exists in both — and the roster query, which is the one every later milestone
-- runs, would have to union them.

-- ===========================================================================
-- SECTION 1 — Enumerations
-- ===========================================================================

-- The measurable quantities. These map onto HealthKit sample types, which M3
-- ingests; the names here are the domain's, not HealthKit's, so the mapping
-- lives in one place in the client rather than leaking Apple's identifiers into
-- the schema.
create type public.contest_metric as enum (
  'steps',
  'distance_meters',
  'active_energy_kcal',
  'exercise_minutes'
);

-- 'daily' means hit the target on each day of the window, evaluated in the
-- participant's own frozen timezone (D5). 'cumulative' means hit it once across
-- the whole window, where timezone only matters at the two boundaries.
create type public.contest_cadence as enum ('daily', 'cumulative');

-- The tie-break, declared at creation and never chosen after the fact — which
-- is the whole point of putting it here. Order of the options as reasoned in
-- DECISIONS.md; 'integrity_score' is the default because it makes clean data
-- the thing that wins a tie.
create type public.contest_tie_break as enum (
  'integrity_score',
  'earliest_to_target',
  'both_donate',
  'void'
);

-- Lifecycle. Forward-only, with two terminal states; 'finalized' is listed here
-- so M2 can enforce that a finalized contest is frozen, but M7 owns the
-- transition into it along with settlement.
create type public.contest_status as enum (
  'pending',
  'active',
  'cancelled',
  'finalized'
);

create type public.contest_cancellation_reason as enum (
  'creator_cancelled',
  'insufficient_participants'
);

-- The participant state machine. 'declined' and 'lapsed' are kept apart on
-- purpose: one is an answer and the other is silence, and M7's reliability
-- score has reason to tell them apart. Note this is the opposite call from
-- friendships, where a decline deletes the row (D16) — a friendship decline is
-- a social rejection worth forgetting, whereas a contest is a financial
-- agreement whose roster is the record of who agreed to what.
create type public.contest_participant_status as enum (
  'invited',
  'accepted',
  'declined',
  'withdrawn',
  'lapsed'
);

-- ===========================================================================
-- SECTION 2 — Tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- charities
-- ---------------------------------------------------------------------------
-- Curated reference data, not user content. A small hand-maintained list with
-- an EIN and a donation slug, per the deferred decision: no IRS Pub 78 import
-- in v1, because a 1.3M-row import buys nothing until users ask for a charity
-- that is not on the list.
--
-- Clients hold SELECT and nothing else (section 7). A charity is the
-- destination of a real donation obligation, so "who may add one" is not a
-- question the Data API should be able to answer at all.
create table public.charities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  ein         text not null unique,
  slug        extensions.citext not null unique,
  url         text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint charities_name_length check (char_length(name) between 1 and 120),

  -- US Employer Identification Number, NN-NNNNNNN. Stored formatted rather than
  -- as digits so it round-trips to what a donor sees on a receipt.
  constraint charities_ein_format check (ein ~ '^[0-9]{2}-[0-9]{7}$'),

  constraint charities_slug_format
    check (slug::text ~ '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'),

  constraint charities_url_scheme check (url is null or url ~ '^https://')
);

comment on table public.charities is
  'Curated donation destinations. Read-only to clients; maintained out of band.';
comment on column public.charities.ein is
  'US EIN, formatted NN-NNNNNNN as it appears on a donation receipt.';
comment on column public.charities.is_active is
  'False retires a charity from new nominations without invalidating existing ones.';

-- ---------------------------------------------------------------------------
-- contests
-- ---------------------------------------------------------------------------
-- The terms. Every column between `group_id` and `max_participants` is frozen
-- by a trigger the moment the row exists, because these are the terms each
-- participant individually agreed to and there is no honest reason to rewrite
-- them afterwards. Fixing a typo means cancelling and creating another.
create table public.contests (
  id                   uuid primary key default gen_random_uuid(),
  title                text not null,

  -- Optional home. A contest scoped to a group may invite that group's members;
  -- one with no group may invite the creator's friends. The group is not the
  -- thing being staked, so it confers nothing else — and it is not what makes a
  -- contest a "group contest", which is purely max_participants > 2.
  group_id             uuid references public.groups (id) on delete set null,

  -- Nullable and SET NULL for the same reason as groups.created_by: a contest
  -- is financial history and must outlive the account that authored it. Unlike
  -- groups (D17), this column *does* confer privilege while it is set — see the
  -- note on the invite policy in section 5.
  created_by           uuid references public.profiles (id) on delete set null,

  metric               public.contest_metric not null,
  cadence              public.contest_cadence not null,
  target_value         numeric(12, 2) not null,
  stake_amount_cents   integer not null,
  tie_break            public.contest_tie_break not null default 'integrity_score',

  starts_at            timestamptz not null,
  ends_at              timestamptz not null,

  -- A winner-takes-all contest of n produces n-1 donation obligations (D4), so
  -- this number is what bounds how much one contest can cost the group. It is
  -- also the disclosure that makes it fair for the creator to keep inviting
  -- after others have accepted: an invitee agrees to a roster of at most this
  -- size, so a later invitation cannot change the exposure they consented to.
  max_participants     smallint not null default 8,

  status               public.contest_status not null default 'pending',
  cancellation_reason  public.contest_cancellation_reason,
  activated_at         timestamptz,
  cancelled_at         timestamptz,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint contests_title_length check (char_length(title) between 1 and 80),
  constraint contests_target_positive check (target_value > 0),

  -- $1 floor, $10,000 ceiling. The ceiling is not a technical limit; it is a
  -- fat-finger guard on a field that creates a real donation obligation, where
  -- a stray zero is a plausible mistake and an expensive one.
  constraint contests_stake_range
    check (stake_amount_cents between 100 and 1000000),

  constraint contests_window_ordered check (ends_at > starts_at),

  -- A year is already far longer than any plausible contest and it bounds how
  -- long a pledge can stay open before settlement.
  constraint contests_window_bounded
    check (ends_at <= starts_at + interval '366 days'),

  -- A daily-cadence contest over a window shorter than a day has no days to
  -- evaluate. Cadence-specific rules beyond this belong to M4's scoring.
  constraint contests_daily_needs_a_day
    check (cadence <> 'daily' or ends_at >= starts_at + interval '1 day'),

  -- Two is a duel (D4). Twenty is the ceiling on donation obligations one
  -- contest can create.
  constraint contests_participant_range
    check (max_participants between 2 and 20),

  -- Terminal-state bookkeeping, kept honest declaratively rather than by
  -- convention so a definer path cannot leave a half-cancelled row behind.
  constraint contests_cancellation_fields_match_status
    check (
      (status = 'cancelled')
        = (cancellation_reason is not null and cancelled_at is not null)
    ),
  constraint contests_activated_at_requires_activation
    check (activated_at is null or status in ('active', 'finalized'))
);

comment on table public.contests is
  'Contest terms and window. Terms are frozen at creation; status is forward-only.';
comment on column public.contests.group_id is
  'Optional scope for who may be invited. Confers nothing else.';
comment on column public.contests.created_by is
  'The author of the terms. Unlike groups.created_by this confers privilege: invite and cancel.';
comment on column public.contests.max_participants is
  'Roster ceiling, disclosed to every invitee. 2 is a duel.';
comment on column public.contests.stake_amount_cents is
  'Per-loser donation obligation, in USD cents. Every loser owes this once (D4).';

create index contests_group_idx on public.contests (group_id)
  where group_id is not null;

-- The activation scan: pending contests whose window has opened. Partial, so it
-- stays small as finished contests accumulate.
create index contests_pending_start_idx on public.contests (starts_at)
  where status = 'pending';

-- ---------------------------------------------------------------------------
-- contest_participants
-- ---------------------------------------------------------------------------
-- One row per person per contest, from invitation through to whatever became of
-- them. The pair as primary key is what makes a duplicate invitation impossible
-- rather than merely unusual, and it makes re-inviting idempotent at the
-- database rather than in the client.
create table public.contest_participants (
  contest_id   uuid not null references public.contests (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,

  status       public.contest_participant_status not null default 'invited',

  -- Null for the creator, who enrolled themselves. Otherwise whoever invited
  -- them, which the insert policy pins to the contest's author.
  invited_by   uuid references public.profiles (id) on delete set null,

  -- Frozen at accept and never rewritten (D5). A live timezone would let a
  -- participant fly their day boundary backwards to reopen a day they had
  -- already lost, which defeats daily cadence outright. D5's consent-plus-flag
  -- path for a genuine relocation is M5's, once there is an integrity flag to
  -- raise; until then this is simply immutable.
  timezone     text,

  -- The charity that receives the donations if *this* participant wins (D4).
  -- Required to accept, so that everyone can see every possible destination
  -- before agreeing to pledge — which is the point of asking upfront rather
  -- than letting the winner choose at settlement.
  charity_id   uuid references public.charities (id) on delete restrict,

  invited_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  updated_at   timestamptz not null default now(),

  primary key (contest_id, user_id),

  -- One-directional on purpose: accepting requires both, but a participant who
  -- later withdraws keeps the timezone and charity they had, because those are
  -- part of the record of what they agreed to.
  constraint contest_participants_accepted_is_complete
    check (
      status <> 'accepted'
      or (timezone is not null and charity_id is not null)
    ),

  constraint contest_participants_accepted_at_matches_status
    check ((status = 'accepted') = (accepted_at is not null))
);

comment on table public.contest_participants is
  'Roster and invitation lifecycle in one table. Rows are never deleted; withdrawal is a status.';
comment on column public.contest_participants.timezone is
  'IANA zone frozen at accept. Day boundaries for daily cadence are computed in it (D5).';
comment on column public.contest_participants.charity_id is
  'This participant''s nominated destination, used if they win. Required to accept.';

-- "My contests", the client's home screen query.
create index contest_participants_user_idx
  on public.contest_participants (user_id, status);

-- ===========================================================================
-- SECTION 3 — Trigger functions
-- ===========================================================================

-- Permits a frozen reference to be cleared, but never repointed.
--
-- This exists because of a collision found while building M2, which turned out
-- to affect M1 as well. `app.forbid_column_change()` cannot be used on a
-- nullable column carrying `on delete set null`, because the referential action
-- is itself an UPDATE: deleting the referenced row makes Postgres run
-- `update ... set created_by = null`, the trigger refuses it, and the DELETE
-- fails. The effect on M1 was that no account which had ever created a group
-- could be deleted at all — which silently contradicts D20's "account deletion
-- goes through auth.users and cascades", and would have been three more of the
-- same bug once M2 added contests.created_by, contests.group_id and
-- contest_participants.invited_by.
--
-- What the freeze is actually protecting is *reassignment*: nobody may become
-- the author of someone else's contest, or move a contest into a different
-- group. Clearing the column is not reassignment — it is the documented
-- behaviour when the referenced row goes away — so this variant forbids every
-- change except one to NULL. Repointing still raises, and M1's assertion that
-- created_by is immutable even to a privileged writer still holds.
create or replace function app.forbid_column_reassignment()
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
    -- A cleared column reads as JSON null here, not SQL NULL, which is what
    -- distinguishes "was set to nothing" from "is absent from the row".
    if (before_row -> col) is distinct from (after_row -> col)
       and (after_row -> col) is distinct from 'null'::jsonb
    then
      raise exception 'column %.%.% may be cleared but not repointed',
        tg_table_schema, tg_table_name, col
        using errcode = 'restrict_violation';
    end if;
  end loop;
  return new;
end;
$$;

comment on function app.forbid_column_reassignment() is
  'BEFORE UPDATE trigger. Like forbid_column_change, but tolerates the NULL an '
  '`on delete set null` referential action writes.';

-- Refuses a contest whose window has already opened.
--
-- This is anti-cheat, not validation. A creator who already knows they walked
-- 20,000 steps yesterday and can name yesterday as the window has a contest
-- they cannot lose, and no amount of provenance checking on the samples
-- themselves would notice — the samples are genuine. The only place to stop it
-- is at creation. A CHECK constraint cannot: now() is not immutable.
create or replace function app.assert_contest_window_is_future()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.starts_at < now() then
    raise exception 'a contest window cannot open in the past (starts_at %, now %)',
      new.starts_at, now()
      using errcode = 'invalid_parameter_value';
  end if;
  return new;
end;
$$;

comment on function app.assert_contest_window_is_future() is
  'BEFORE INSERT on contests. Refuses a backdated window, which would be an unlosable contest.';

-- Status is forward-only, and each transition has exactly one legal successor
-- set. Written as an explicit table rather than a pair of inequalities so that
-- adding M7's transition is an edit to one place with the rule visible.
create or replace function app.enforce_contest_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'pending' and new.status in ('active', 'cancelled'))
    -- M7 drives this one, alongside settlement.
    or (old.status = 'active' and new.status = 'finalized')
  ) then
    raise exception 'contest status cannot move from % to %', old.status, new.status
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.enforce_contest_status_transition() is
  'BEFORE UPDATE on contests. Forward-only lifecycle; cancelled and finalized are terminal.';

-- The participant state machine, and the fields each state requires.
--
-- Two rules here carry more weight than the rest:
--
-- Once the contest is active the roster is closed — no new rows, no status
-- changes at all. That is what makes a stake binding, and it is why blocking an
-- opponent mid-contest cannot be an exit: a block hides a profile and refuses a
-- new invitation, but there is no transition out of 'accepted' once the window
-- has opened, so the obligation survives it. Anything weaker would make
-- "block your opponent" the cheapest way to escape a contest you are losing.
--
-- The creator cannot withdraw. They authored the terms and are enrolled from
-- the first instant; the way out of a contest you started is to cancel it,
-- which is a decision about the whole contest rather than a quiet exit from it.
create or replace function app.enforce_contest_participant_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
    -- status, not the charity, not anything: this is the freeze.
    --
    -- Two columns are excluded from the comparison rather than being writable.
    -- `updated_at` is stamped by a later trigger. `invited_by` carries
    -- `on delete set null`, so leaving it in would make deleting the inviter's
    -- account fail against every contest they ever started that has since
    -- opened — the same collision app.forbid_column_reassignment() exists for.
    -- Neither is reachable by a client: the column grant covers exactly
    -- (status, timezone, charity_id), and repointing invited_by still raises
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
$$;

comment on function app.enforce_contest_participant_transition() is
  'BEFORE INSERT OR UPDATE on contest_participants. The state machine, and the roster freeze.';

-- The roster ceiling, enforced under a lock on the contest row.
--
-- A plain count would race: two participants accepting concurrently each see
-- one accepted row, each conclude there is space, and a max_participants of 2
-- ends up with 3. Locking the contest row serialises acceptances for that
-- contest, which is the cheapest correct answer at this volume and does not
-- block anything else.
--
-- Note what this deliberately does not bound: invitations. Only acceptances
-- count against the ceiling, so an author may invite more people than the
-- contest can hold and the places go to whoever answers first. Capping
-- invitations instead would mean a single decline permanently shrinks a
-- contest, since nothing reclaims the slot — and "invite five, first two in
-- get the duel" is both the more robust behaviour and the one a group chat
-- actually produces.
create or replace function app.enforce_contest_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max      smallint;
  v_accepted integer;
begin
  if new.status <> 'accepted' then
    return new;
  end if;

  select max_participants into v_max
  from public.contests
  where id = new.contest_id
  for update;

  select count(*) into v_accepted
  from public.contest_participants
  where contest_id = new.contest_id
    and status = 'accepted'
    and user_id <> new.user_id;

  if v_accepted + 1 > v_max then
    raise exception 'contest is full (% of % accepted)', v_accepted, v_max
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.enforce_contest_capacity() is
  'BEFORE INSERT OR UPDATE on contest_participants. Enforces max_participants under a row lock.';

-- 'lapsed' is the system's word for an invitation that went unanswered, so a
-- client must not be able to write it: an invitee who could would be filing
-- their own refusal as silence, and 'declined' would stop meaning anything M7's
-- reliability score can read.
--
-- This has to be its own trigger, and specifically an invoker-rights one. The
-- two paths that legitimately set 'lapsed' — cancel_contest() and
-- activate_due_contests() — are SECURITY DEFINER, and inside a definer function
-- `current_user` is the function's owner, not the role that called it. So the
-- same check placed in the definer trigger above would compare the owner
-- against the owner and pass for everybody. Under invoker rights `current_user`
-- is whatever was in effect at the call site: the owner when a definer function
-- is doing the writing, and `authenticated` when PostgREST is.
--
-- The owner is read from the catalog rather than hardcoded, because it is
-- `postgres` on Supabase and whichever role ran the migrations elsewhere.
create or replace function app.forbid_client_lapse()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner name;
begin
  if new.status <> 'lapsed'
     or (tg_op = 'UPDATE' and old.status = 'lapsed')
  then
    return new;
  end if;

  select r.rolname into v_owner
  from pg_catalog.pg_class c
  join pg_catalog.pg_roles r on r.oid = c.relowner
  where c.oid = tg_relid;

  if current_user <> v_owner then
    raise exception 'an invitation lapses on its own; decline it instead'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

comment on function app.forbid_client_lapse() is
  'BEFORE INSERT OR UPDATE on contest_participants. Invoker rights on purpose: only the '
  'table owner, meaning a definer function, may record an invitation as lapsed.';

-- A retired charity may not be nominated afresh, but one already nominated on a
-- live contest stays valid — retiring a charity must not be able to invalidate
-- an agreement people already made.
create or replace function app.assert_charity_is_nominable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.charity_id is null
     or (tg_op = 'UPDATE' and new.charity_id = old.charity_id)
  then
    return new;
  end if;

  if not exists (
    select 1 from public.charities where id = new.charity_id and is_active
  ) then
    raise exception 'charity % is not accepting new nominations', new.charity_id
      using errcode = 'invalid_parameter_value';
  end if;

  return new;
end;
$$;

comment on function app.assert_charity_is_nominable() is
  'BEFORE INSERT OR UPDATE on contest_participants. Only an active charity may be newly nominated.';

-- ===========================================================================
-- SECTION 4 — Triggers
-- ===========================================================================

create trigger charities_set_updated_at
  before update on public.charities
  for each row execute function app.set_updated_at();

create trigger contests_assert_future_window
  before insert on public.contests
  for each row execute function app.assert_contest_window_is_future();

create trigger contests_set_updated_at
  before update on public.contests
  for each row execute function app.set_updated_at();

-- Everything a participant agreed to. `status` and the three lifecycle stamps
-- are the only columns not listed, and the transition trigger governs those.
create trigger contests_freeze_terms
  before update on public.contests
  for each row execute function app.forbid_column_change(
    'id', 'title', 'metric', 'cadence',
    'target_value', 'stake_amount_cents', 'tie_break',
    'starts_at', 'ends_at', 'max_participants', 'created_at'
  );

-- The two term columns that are references with `on delete set null`, and so
-- need the variant that tolerates being cleared.
create trigger contests_freeze_references
  before update on public.contests
  for each row execute function app.forbid_column_reassignment(
    'created_by', 'group_id'
  );

-- ---------------------------------------------------------------------------
-- Retrofit: the same collision in M1
-- ---------------------------------------------------------------------------
-- groups.created_by has carried `on delete set null` and a strict freeze since
-- M1, which means deleting an account that created a group has never actually
-- worked. Fixed here rather than left for a reader to rediscover, since M2 is
-- what made the pattern visible. Behaviour a client can observe is unchanged:
-- repointing created_by still raises, which is what 030_groups.test.sql asserts.
drop trigger groups_freeze_columns on public.groups;

create trigger groups_freeze_columns
  before update on public.groups
  for each row execute function app.forbid_column_change('id', 'created_at');

create trigger groups_freeze_authorship
  before update on public.groups
  for each row execute function app.forbid_column_reassignment('created_by');

create trigger contests_enforce_status_transition
  before update on public.contests
  for each row execute function app.enforce_contest_status_transition();

-- Eight triggers on one table, and Postgres fires same-event triggers in
-- alphabetical order by name. That is load-bearing for error precedence rather
-- than for correctness, and the names below are chosen so the order comes out
-- right: `apply_transition` first, so that a write to a frozen roster or an
-- illegal transition reports itself as such instead of surfacing whichever
-- other check happened to run first. None of the later ones rewrites `status`,
-- so the capacity check sees the settled value wherever it runs.
--
--   apply_transition    the state machine and the roster freeze
--   assert_charity      only an active charity may be newly nominated
--   authorize_lapse     only a definer path may record a lapse
--   enforce_capacity    max_participants, under a lock on the contest row
--   freeze_columns      the columns a participant never rewrites
--   freeze_references   invited_by may be cleared, never repointed (D34)
--   set_updated_at
--   validate_timezone   a zone Postgres knows
create trigger contest_participants_apply_transition
  before insert or update on public.contest_participants
  for each row execute function app.enforce_contest_participant_transition();

create trigger contest_participants_assert_charity
  before insert or update on public.contest_participants
  for each row execute function app.assert_charity_is_nominable();

create trigger contest_participants_authorize_lapse
  before insert or update on public.contest_participants
  for each row execute function app.forbid_client_lapse();

create trigger contest_participants_enforce_capacity
  before insert or update on public.contest_participants
  for each row execute function app.enforce_contest_capacity();

create trigger contest_participants_freeze_columns
  before update on public.contest_participants
  for each row execute function app.forbid_column_change(
    'contest_id', 'user_id', 'invited_at'
  );

create trigger contest_participants_freeze_references
  before update on public.contest_participants
  for each row execute function app.forbid_column_reassignment('invited_by');

create trigger contest_participants_set_updated_at
  before update on public.contest_participants
  for each row execute function app.set_updated_at();

create trigger contest_participants_validate_timezone
  before insert or update on public.contest_participants
  for each row execute function app.assert_valid_timezone('timezone');

-- ===========================================================================
-- SECTION 5 — Access model
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------

create or replace function app.is_contest_participant(cid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.contest_participants
    where contest_id = cid and user_id = uid
  );
$$;

comment on function app.is_contest_participant(uuid, uuid) is
  'True for any roster row, including invited and withdrawn. Definer rights break policy recursion.';

-- Deliberately narrower than "shares any contest": both must have *accepted*
-- and the contest must have actually opened.
--
-- The narrowing is what stops this being a way around a block. This predicate
-- sits outside the block check in the profiles policy below, because two people
-- in a live contest have to be able to see each other — one of them may end up
-- owing the other's charity money, and a settlement screen that cannot render
-- the counterparty is not acceptable. If a merely *invited* person counted,
-- then inviting someone and waiting for them to block you would buy permanent
-- visibility of a profile they had withdrawn from you, which is exactly the
-- circumvention blocks exist to prevent. An invitation can only be sent across
-- a route that already grants visibility (friend or group co-member), so
-- nothing is lost by leaving the pending case to those.
create or replace function app.shares_active_contest(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.contest_participants pa
    join public.contest_participants pb on pb.contest_id = pa.contest_id
    join public.contests c on c.id = pa.contest_id
    where pa.user_id = a
      and pb.user_id = b
      and pa.status = 'accepted'
      and pb.status = 'accepted'
      and c.status in ('active', 'finalized')
  );
$$;

comment on function app.shares_active_contest(uuid, uuid) is
  'True if both accepted the same contest and it has opened. Survives a later block.';

-- Whether this caller may put that person on this contest's roster.
--
-- A contest invitation carries a money pledge, so its reach has to be no wider
-- than the social graph already allows. M1 made profiles non-enumerable
-- precisely so that knowing a handle does not let you reach a stranger
-- (find_profile_by_handle is exact-match and non-enumerable for that reason);
-- an invitation sendable to any handle would hand that back and
-- turn the invite path into a scam vector aimed at people who never opted into
-- contact. So: a friend, or a member of the group this contest is scoped to,
-- and never across a block in either direction.
create or replace function app.may_invite_to_contest(cid uuid, inviter uuid, invitee uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select inviter is not null
     and invitee is not null
     and inviter <> invitee
     and not app.is_blocked_either_way(inviter, invitee)
     and exists (
       select 1
       from public.contests c
       where c.id = cid
         and c.status = 'pending'
         and c.created_by = inviter
         and (
           app.is_friend(inviter, invitee)
           or (c.group_id is not null
               and app.is_group_member(c.group_id, invitee)
               and app.is_group_member(c.group_id, inviter))
         )
     );
$$;

comment on function app.may_invite_to_contest(uuid, uuid, uuid) is
  'Invite reach: the author only, into a pending contest, to a friend or a co-member of its group.';

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.charities enable row level security;
alter table public.contests enable row level security;
alter table public.contest_participants enable row level security;

-- Public reference data, but still authenticated-only: this app grants `anon`
-- nothing anywhere, and a charity list is not the place to start.
create policy charities_select_all on public.charities
  for select to authenticated
  using (true);

-- No insert, update, or delete policy. The list is curated out of band.

-- Participants only — including invited, who need to read the terms to decide,
-- and withdrawn, who are entitled to their own history.
--
-- Deliberately *not* "any member of the contest's group". A group contest's
-- stake and roster are a financial arrangement between the people in it, and
-- surfacing them to the rest of the group would publish who pledged what to
-- whom. A group feed, if it is ever wanted, should be a narrowed view rather
-- than a widening of this policy.
create policy contests_select_participant on public.contests
  for select to authenticated
  using (app.is_contest_participant(id, (select auth.uid())));

-- No insert policy: creation writes two tables atomically and needs the
-- author's own timezone and charity, neither of which is a column on this one.
-- That is public.create_contest().
--
-- No update policy and no update grant: the terms are frozen and the status
-- moves only through section 6.
--
-- No delete policy: a contest that happened is evidence.

create policy contest_participants_select_roster on public.contest_participants
  for select to authenticated
  using (app.is_contest_participant(contest_id, (select auth.uid())));

-- Inviting. Unlike a group, where flat membership means every member
-- administers (D17), only the author invites — and that divergence is the point
-- of the column comment on contests.created_by. A group is a container with no
-- terms; a contest is an agreement someone wrote. Growing the roster changes
-- the odds for everyone already in it, so it stays with the person whose terms
-- they are, bounded by the max_participants they were shown.
create policy contest_participants_insert_invite on public.contest_participants
  for insert to authenticated
  with check (
    invited_by = (select auth.uid())
    and status = 'invited'
    and app.may_invite_to_contest(contest_id, (select auth.uid()), user_id)
  );

-- Your own row, and only while the contest can still change. The legal
-- transitions, the roster freeze, and the frozen timezone are the trigger's
-- job; this decides whose row it is. The column-level grant in section 7 is
-- what stops this reaching invited_by or invited_at.
create policy contest_participants_update_own on public.contest_participants
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- No delete policy. Withdrawal is a status; erasing the row would erase the
-- fact that someone agreed.

-- ---------------------------------------------------------------------------
-- profiles: the third visibility route
-- ---------------------------------------------------------------------------
-- M1 left this at friends-and-group-co-members and noted that M2 is where
-- contest co-participation joins them. It is added *outside* the block check,
-- unlike the other two: see app.shares_active_contest() for why that is safe
-- and why it is restricted to contests that actually opened.
alter policy profiles_select_visible on public.profiles
  using (
    id = (select auth.uid())
    or app.shares_active_contest(id, (select auth.uid()))
    or (
      not app.is_blocked_either_way(id, (select auth.uid()))
      and (
        app.is_friend(id, (select auth.uid()))
        or app.shares_group(id, (select auth.uid()))
      )
    )
  );

-- ===========================================================================
-- SECTION 6 — Callable API
-- ===========================================================================

-- Creation is a function rather than an insert because it has to write both
-- tables or neither. A contest with no participants would be a contest with no
-- author in it, and the two-call version of this leaves exactly that behind
-- whenever the second call fails — the same "never memberless" property M1
-- gave groups with a trigger. A trigger cannot do it here: the author's row
-- needs a charity nomination, and there is no sensible default for that.
create or replace function public.create_contest(
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
    contest_id, user_id, status, timezone, charity_id
  )
  values (v_contest_id, v_uid, 'accepted', p_timezone, p_charity_id);

  return v_contest_id;
end;
$$;

comment on function public.create_contest is
  'Create a contest and enrol its author. The only way a contest row comes into being.';

-- Cancelling is the author's way out, and only before the window opens. There
-- is deliberately no path to cancel an active contest: a stake that can be
-- called off by the person losing is not a stake.
create or replace function public.cancel_contest(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_status public.contest_status;
  v_author uuid;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  select status, created_by into v_status, v_author
  from public.contests
  where id = p_contest_id
  for update;

  -- One error for "no such contest" and "not yours", so this cannot be used to
  -- probe for contest ids.
  if v_status is null or v_author is distinct from v_uid then
    raise exception 'not the author of that contest'
      using errcode = 'insufficient_privilege';
  end if;

  if v_status <> 'pending' then
    raise exception 'cannot cancel a contest with status %', v_status
      using errcode = 'restrict_violation';
  end if;

  -- Close every outstanding invitation. Nobody is owed an answer to an
  -- invitation to a contest that will not happen, and leaving them 'invited'
  -- would make "my open invitations" a query that has to join contest status.
  update public.contest_participants
  set status = 'lapsed'
  where contest_id = p_contest_id
    and status = 'invited';

  update public.contests
  set status = 'cancelled',
      cancellation_reason = 'creator_cancelled',
      cancelled_at = now()
  where id = p_contest_id;
end;
$$;

comment on function public.cancel_contest(uuid) is
  'Author-only, pending-only. Lapses outstanding invitations and voids the contest.';

-- Opens the window on every contest that has reached its start time, or voids
-- it for want of a roster. Called by cron, which M7 sets up alongside
-- settlement; until then it is exercised directly by the test suite.
--
-- Quorum is two: a contest is a comparison, and there is nothing to compare a
-- lone participant against. Everyone still holding an unanswered invitation is
-- lapsed either way — the contest moved on without them.
--
-- p_now is a parameter rather than a call to now() so the suite can drive the
-- clock. It defaults to now(), so cron calls it with no arguments.
create or replace function app.activate_due_contests(p_now timestamptz default now())
returns table (contest_id uuid, outcome public.contest_status)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest  record;
  v_accepted integer;
begin
  for v_contest in
    select id
    from public.contests
    where status = 'pending'
      and starts_at <= p_now
    order by starts_at
    for update
  loop
    update public.contest_participants
    set status = 'lapsed'
    where contest_participants.contest_id = v_contest.id
      and status = 'invited';

    select count(*) into v_accepted
    from public.contest_participants
    where contest_participants.contest_id = v_contest.id
      and status = 'accepted';

    if v_accepted >= 2 then
      update public.contests
      set status = 'active', activated_at = p_now
      where id = v_contest.id;

      return query select v_contest.id, 'active'::public.contest_status;
    else
      update public.contests
      set status = 'cancelled',
          cancellation_reason = 'insufficient_participants',
          cancelled_at = p_now
      where id = v_contest.id;

      return query select v_contest.id, 'cancelled'::public.contest_status;
    end if;
  end loop;
end;
$$;

comment on function app.activate_due_contests(timestamptz) is
  'Cron entry point. Opens due contests with a quorum of 2, voids the rest, lapses unanswered invitations.';

-- ===========================================================================
-- SECTION 7 — Privileges
-- ===========================================================================
-- As in M1: revoke Supabase's default ALL, then grant back only the verbs that
-- have a matching policy (D21).

revoke all on public.charities, public.contests, public.contest_participants
  from anon, authenticated;

grant select on public.charities to authenticated;
grant select on public.contests to authenticated;
grant select, insert on public.contest_participants to authenticated;

-- Column-level. A participant answers an invitation and nominates a charity;
-- they do not rewrite who invited them or when.
grant update (status, timezone, charity_id)
  on public.contest_participants to authenticated;

-- Deliberately withheld, each by a missing grant as well as a missing policy:
--   charities             INSERT/UPDATE/DELETE — curated out of band
--   contests              INSERT   — create_contest() owns it
--   contests              UPDATE   — terms are frozen, status moves in section 6
--   contests              DELETE   — a contest that happened is evidence
--   contest_participants  DELETE   — withdrawal is a status, not an erasure
--   contest_participants  UPDATE (invited_by, invited_at, accepted_at, …)
--                                  — not the participant's to rewrite

revoke all on function public.create_contest(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid, smallint, public.contest_tie_break, uuid
) from public, anon;
revoke all on function public.cancel_contest(uuid) from public, anon;

grant execute on function public.create_contest(
  text, public.contest_metric, public.contest_cadence, numeric, integer,
  timestamptz, timestamptz, text, uuid, smallint, public.contest_tie_break, uuid
) to authenticated;
grant execute on function public.cancel_contest(uuid) to authenticated;

-- This one is different from every function M1 granted, and the difference
-- matters. Postgres grants EXECUTE on a new function to PUBLIC by default, and
-- the baseline migration gives `authenticated` USAGE on the `app` schema so
-- that RLS policies can call the predicates in it. Those two together mean a
-- security-definer function in `app` is callable by any signed-in user unless
-- it is explicitly revoked — and this one opens contest windows and voids
-- contests for want of a quorum. Left as created, a client could open a
-- contest early or void one out from under its participants.
--
-- The predicates above do not need this treatment: a policy expression is
-- evaluated with the privileges of the querying role, so revoking EXECUTE from
-- `authenticated` on app.is_friend() and friends would break the very policies
-- they exist to serve. The distinction is "called by a policy" versus "called
-- by nobody but cron".
revoke all on function app.activate_due_contests(timestamptz)
  from public, anon, authenticated;
grant execute on function app.activate_due_contests(timestamptz) to service_role;
