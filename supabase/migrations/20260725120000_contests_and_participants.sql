-- M2 — Contests, invitations, and the participant state machine.
--
-- What a contest is, in one sentence: two or more friends declare a metric, a
-- target, a window, and a donation amount, and whoever loses donates that
-- amount to a charity the winner nominated. Nothing here moves money. A
-- settlement is a pledge and M7 tracks whether it was honoured.
--
-- Four things arrive:
--
--   charities             curated reference data. No client write path at all.
--   contests              the terms. Immutable once anyone has agreed to them.
--   contest_participants  the roster, and the invitation lifecycle
--   two state machines    declared whole, enforced by triggers
--
-- ---------------------------------------------------------------------------
-- Why almost every mutation here is a function rather than a table write
-- ---------------------------------------------------------------------------
-- M1 hit this once, with join_group_by_code: RLS answers "may this caller read
-- or write this row", and some preconditions are not properties of a row.
-- M2 hits it repeatedly, and for three distinct reasons worth separating:
--
--   * Multi-row atomicity. Creating a contest also creates the creator's
--     participant row. A contest that exists without its creator in it is a
--     state no reader should ever observe.
--   * Cross-row eligibility. "Is this invitee a friend / a co-member / blocked
--     by anyone already in this contest" reads rows other than the one being
--     written, which a WITH CHECK cannot do without leaking the answer.
--   * Serialization. max_participants is a bound on a COUNT, and two people
--     accepting the last slot concurrently both pass a naive check. The cap is
--     only real if acceptance takes a lock, which means a function body.
--
-- So contests and contest_participants grant SELECT to clients and little else.
-- The withheld verbs are revoked as well as unpoliced, per DECISIONS.md D21.
--
-- ---------------------------------------------------------------------------
-- Ordering
-- ---------------------------------------------------------------------------
-- Same constraint as M1: `language sql` helpers are parsed at creation time, so
-- every predicate follows every table it reads. Enums, tables, triggers, then
-- the access model as one piece.

-- ===========================================================================
-- SECTION 1 — Enumerated domains
-- ===========================================================================

create type public.contest_kind as enum ('duel', 'group');

comment on type public.contest_kind is
  'A duel is the N=2 case of a group contest; both settle identically (D4).';

-- The full lifecycle, declared here even though M2 only drives part of it.
-- A state machine is only reviewable as a whole — a later milestone adding
-- states would be changing the machine, not extending it. What M2 implements is
-- open → active and open → cancelled; the transitions out of active belong to
-- M7 and are listed as legal by app.assert_contest_transition() so that the
-- machine's shape is settled now and M7 adds only the code that walks it.
create type public.contest_status as enum (
  'open',        -- accepting participants; terms still editable, conditionally
  'active',      -- running. Terms frozen, evidence being ingested
  'finalizing',  -- window closed, scoring and the dispute window     (M7)
  'settled',     -- scored, settlements issued                        (M7)
  'cancelled',   -- never started: creator pulled it, or too few accepted
  'voided'       -- started but produced no winner                    (M7)
);

comment on type public.contest_status is
  'Contest lifecycle. Legal transitions are enforced by app.assert_contest_transition().';

create type public.contest_cadence as enum ('total', 'daily');

comment on type public.contest_cadence is
  'total: target across the whole window. daily: target every day, scored in '
  'each participant''s frozen timezone (D5).';

-- The metric a contest is fought over. M3 reuses this on metric_snapshots, so
-- the evidence ledger and the contest terms cannot disagree about what was
-- being measured.
create type public.metric_kind as enum (
  'steps',
  'distance_meters',
  'active_energy_kcal',
  'exercise_minutes'
);

comment on type public.metric_kind is
  'Measurable quantities. Shared with M3''s metric_snapshots so terms and evidence agree.';

create type public.tie_break_rule as enum (
  'integrity_score',     -- cleanest data wins. The default, on purpose
  'earliest_to_target',  -- first to cross the line; total cadence only
  'both_donate',         -- everyone tied pays
  'void'                 -- nobody pays
);

comment on type public.tie_break_rule is
  'Declared at creation, never chosen after a result is known. Resolution is M4''s.';

create type public.participant_status as enum (
  'invited',    -- asked, has not answered
  'accepted',   -- in, and has agreed to the terms as they stood
  'declined',   -- said no. Terminal: there is no re-invitation (D25)
  'withdrawn',  -- accepted, then pulled out before the contest started
  'lapsed',     -- never answered, and the contest started or was cancelled
  'forfeited'   -- pulled out after the start. A loss, settled by M7
);

comment on type public.participant_status is
  'Invitation and participation lifecycle. Enforced by app.assert_participant_transition().';

-- ===========================================================================
-- SECTION 2 — Tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- charities
-- ---------------------------------------------------------------------------
-- Reference data, not user content. Clients read it to populate a picker and
-- have no write path whatsoever — not a policy they fail, a grant they do not
-- hold. A user-writable charity list would let a participant nominate a
-- destination of their own invention, which turns a charitable pledge into a
-- payment to an arbitrary payee and is the one failure mode this product cannot
-- have.
create table public.charities (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  ein            text not null unique,
  donation_slug  text not null unique,
  mission        text,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint charities_name_length check (char_length(name) between 1 and 120),

  -- US Employer Identification Number, NN-NNNNNNN. Stored formatted because
  -- that is how it is printed on an acknowledgement letter, and a donor
  -- comparing a receipt to the app should see the same string.
  constraint charities_ein_format check (ein ~ '^[0-9]{2}-[0-9]{7}$'),

  -- The stable identifier a donation link is built from. Lowercase and
  -- hyphenated so it survives being embedded in a URL untouched.
  constraint charities_donation_slug_format
    check (donation_slug ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'),

  constraint charities_mission_length
    check (mission is null or char_length(mission) between 1 and 500)
);

comment on table public.charities is
  'Curated donation destinations. Read-only to clients; maintained out of band.';
comment on column public.charities.ein is
  'US EIN, formatted NN-NNNNNNN. Unique, so the same org cannot be listed twice.';
comment on column public.charities.donation_slug is
  'Stable URL component for the donation link. Not a full URL.';
comment on column public.charities.is_active is
  'False retires a charity from new nominations. Existing contests keep theirs.';

-- ---------------------------------------------------------------------------
-- contests
-- ---------------------------------------------------------------------------
-- The terms. Every column below is something a participant agreed to when they
-- accepted, which is why the whole row freezes on the first acceptance by
-- somebody other than the creator (D24).
create table public.contests (
  id                  uuid primary key default gen_random_uuid(),
  kind                public.contest_kind not null,
  status              public.contest_status not null default 'open',

  -- Where the contest came from, not what it is. Nulls out if the group is
  -- reaped mid-contest by M1's last-one-out rule (D17) — the contest and its
  -- pledges have to outlive the group, and the roster is stored, not derived.
  group_id            uuid references public.groups (id) on delete set null,
  created_by          uuid references public.profiles (id) on delete set null,

  title               text not null,
  metric              public.metric_kind not null,
  cadence             public.contest_cadence not null,
  target_value        numeric(12, 2) not null,

  starts_at           timestamptz not null,
  ends_at             timestamptz not null,

  stake_amount_cents  integer not null,
  stake_currency      text not null default 'USD',
  tie_break           public.tie_break_rule not null default 'integrity_score',
  max_participants    smallint not null,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  activated_at        timestamptz,
  ended_at            timestamptz,

  constraint contests_title_length check (char_length(title) between 1 and 80),
  constraint contests_target_positive check (target_value > 0),

  -- A duel has no group. A group contest usually has one, but may have lost it
  -- to the cascade above, so the implication only runs one way.
  constraint contests_duel_has_no_group
    check (kind <> 'duel' or group_id is null),

  -- A duel is exactly two people. Group size is capped at creation rather than
  -- on the group itself, because the group is not the thing being staked: a
  -- winner-takes-all contest among n produces n-1 donation obligations (D4), so
  -- this number bounds how much exposure one contest can create.
  constraint contests_max_participants_range
    check (max_participants between 2 and 20),
  constraint contests_duel_is_a_pair
    check (kind <> 'duel' or max_participants = 2),

  -- A window shorter than a day cannot be scored on a daily cadence and gives
  -- an ingest pipeline no time to see anything, which makes it a fraud surface
  -- rather than a contest. A year is the far end: a pledge nobody remembers
  -- making is not collectable.
  constraint contests_window_duration
    check (ends_at >= starts_at + interval '1 day'
       and ends_at <= starts_at + interval '365 days'),

  -- $1 to $1,000. The floor keeps a contest from being a joke with no stake;
  -- the ceiling is a typo guard, and it matters because a group of 20 turns one
  -- creator's mistake into 19 obligations.
  constraint contests_stake_range
    check (stake_amount_cents between 100 and 100000),

  -- One currency in v1. Widening this is a constraint change rather than a
  -- backfill, which is the only reason the column exists this early.
  constraint contests_stake_currency check (stake_currency = 'USD'),

  -- "First to reach the target" has no meaning when the target resets every
  -- day, so the pairing is refused rather than left for M4 to interpret.
  constraint contests_tie_break_matches_cadence
    check (tie_break <> 'earliest_to_target' or cadence = 'total'),

  constraint contests_activated_at_matches_status
    check ((status in ('open', 'cancelled')) = (activated_at is null))
);

comment on table public.contests is
  'Contest terms. Frozen once a second participant accepts; creation goes through public.create_contest().';
comment on column public.contests.group_id is
  'Provenance only. Nulls out if the group is reaped; the roster lives in contest_participants.';
comment on column public.contests.target_value is
  'Whole-window target for total cadence, per-day target for daily cadence.';
comment on column public.contests.stake_amount_cents is
  'What the loser pledges to donate. Never held, never transferred by this system.';
comment on column public.contests.max_participants is
  'Declared cap. Bounds the n-1 settlements a winner-takes-all result can create.';
comment on column public.contests.ended_at is
  'When the window actually closed. Set by M7 on the way out of active.';

create index contests_status_starts_at_idx
  on public.contests (status, starts_at);
create index contests_group_idx
  on public.contests (group_id) where group_id is not null;

-- ---------------------------------------------------------------------------
-- contest_participants
-- ---------------------------------------------------------------------------
-- The roster and the invitation lifecycle in one table. Two columns are the
-- participant's own terms rather than the contest's, and both are captured when
-- they accept:
--
--   timezone    day boundaries for a daily cadence are computed in it (D5)
--   charity_id  where the loser donates if this participant wins
create table public.contest_participants (
  contest_id    uuid not null references public.contests (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  status        public.participant_status not null default 'invited',

  -- RESTRICT, not CASCADE or SET NULL: a nomination is part of the agreed terms,
  -- so a charity that any contest points at cannot be deleted out from under it.
  -- Retiring one is is_active = false, which stops new nominations only.
  charity_id    uuid references public.charities (id) on delete restrict,
  timezone      text,

  invited_at    timestamptz not null default now(),
  responded_at  timestamptz,
  updated_at    timestamptz not null default now(),

  primary key (contest_id, user_id),

  -- Both are chosen in the same act, so neither can be present alone.
  constraint contest_participants_choices_paired
    check ((charity_id is null) = (timezone is null)),

  -- Accepting means having chosen. Withdrawing or forfeiting later keeps the
  -- choices on the row, which is what lets M7 settle a forfeit.
  constraint contest_participants_accepted_has_choices
    check (status <> 'accepted' or charity_id is not null),

  -- An unanswered invitation cannot have chosen anything yet, which also makes
  -- 'lapsed' distinguishable from 'withdrawn' by shape and not just by name.
  constraint contest_participants_invited_has_no_choices
    check (status <> 'invited' or charity_id is null),

  constraint contest_participants_responded_at_matches_status
    check ((status = 'invited') = (responded_at is null))
);

comment on table public.contest_participants is
  'Roster and invitation lifecycle. All mutation goes through the functions in section 6.';
comment on column public.contest_participants.timezone is
  'IANA zone frozen at acceptance. Day boundaries for daily cadence are computed in it (D5).';
comment on column public.contest_participants.charity_id is
  'This participant''s nomination: where the loser donates if this participant wins.';
comment on column public.contest_participants.status is
  'declined and lapsed are terminal. There is no re-invitation (D25).';

create index contest_participants_user_idx
  on public.contest_participants (user_id, status);

-- ===========================================================================
-- SECTION 3 — State machines
-- ===========================================================================
-- Both are allow-lists. A transition absent from the list is refused, so adding
-- a state later means editing the machine rather than discovering that the new
-- state was silently reachable from everywhere.

create or replace function app.assert_contest_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- M2 drives the first two. The rest are M7's to walk, and are listed now so
  -- the machine is settled in one place rather than grown a state at a time.
  if not (
       (old.status = 'open'       and new.status in ('active', 'cancelled'))
    or (old.status = 'active'     and new.status in ('finalizing', 'voided'))
    or (old.status = 'finalizing' and new.status in ('settled', 'voided'))
  ) then
    raise exception 'illegal contest transition: % -> %', old.status, new.status
      using errcode = 'restrict_violation';
  end if;

  if new.status = 'active' then
    new.activated_at := coalesce(new.activated_at, now());
  end if;

  return new;
end;
$$;

comment on function app.assert_contest_transition() is
  'BEFORE UPDATE on contests. Allow-lists status changes and stamps activated_at.';

create or replace function app.assert_participant_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- Note what is absent: nothing leaves declined, lapsed, withdrawn, or
  -- forfeited. Declining is terminal by design (D25) — a re-invitation path
  -- would be a way to pester somebody who already said no, and the mechanism
  -- for not being asked again should be a block, visibly, not a state machine
  -- quirk. The other three are terminal because the contest moved on.
  if not (
       (old.status = 'invited'  and new.status in ('accepted', 'declined', 'lapsed'))
    or (old.status = 'accepted' and new.status in ('withdrawn', 'forfeited'))
  ) then
    raise exception 'illegal participant transition: % -> %', old.status, new.status
      using errcode = 'restrict_violation';
  end if;

  if old.status = 'invited' then
    new.responded_at := coalesce(new.responded_at, now());
  end if;

  return new;
end;
$$;

comment on function app.assert_participant_transition() is
  'BEFORE UPDATE on contest_participants. Allow-lists status changes and stamps responded_at.';

-- ---------------------------------------------------------------------------
-- Terms immutability
-- ---------------------------------------------------------------------------
-- The client-facing half of this is a narrow UPDATE policy plus column-level
-- grants (sections 5 and 7). This trigger is the other half, and it exists
-- because the policy only constrains clients: a service_role query, a future
-- Edge Function, or a migration script would otherwise be able to rewrite the
-- target of a running contest. Two independent mechanisms, the pattern D21
-- earned in M1.
create or replace function app.forbid_locked_terms_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  terms constant text[] := array[
    'kind', 'group_id', 'title', 'metric', 'cadence', 'target_value',
    'starts_at', 'ends_at', 'stake_amount_cents', 'stake_currency',
    'tie_break', 'max_participants'
  ];
  col text;
  before_row jsonb := to_jsonb(old);
  after_row  jsonb := to_jsonb(new);
  changed boolean := false;
begin
  foreach col in array terms loop
    if (before_row -> col) is distinct from (after_row -> col) then
      changed := true;
      exit;
    end if;
  end loop;

  if not changed then
    return new;
  end if;

  if old.status <> 'open' then
    raise exception 'contest % terms are frozen: status is %', old.id, old.status
      using errcode = 'restrict_violation';
  end if;

  -- The moment somebody other than the creator has accepted, the terms are what
  -- they accepted. Before that, an invitation is an offer nobody has taken up.
  if exists (
    select 1
    from public.contest_participants p
    where p.contest_id = old.id
      and p.status = 'accepted'
      and p.user_id is distinct from old.created_by
  ) then
    raise exception 'contest % terms are frozen: another participant has accepted', old.id
      using errcode = 'restrict_violation';
  end if;

  -- An open contest whose start has already passed is about to be resolved by
  -- app.activate_due_contests(); letting the window be edited at that point
  -- means editing a contest that is arguably already running.
  if new.starts_at <= now() then
    raise exception 'contest % must start in the future', old.id
      using errcode = 'invalid_parameter_value';
  end if;

  -- Shrinking the cap below the roster would leave invitations that cannot be
  -- accepted by construction: invitation counts against the cap, so an invitee
  -- would tap accept and be told the contest is full. Refusing the shrink keeps
  -- "you were invited" and "you may accept" from disagreeing.
  if new.max_participants < old.max_participants
     and (
       select count(*)
       from public.contest_participants p
       where p.contest_id = old.id
         and p.status in ('invited', 'accepted')
     ) > new.max_participants
  then
    raise exception
      'contest % already has more participants than a cap of %', old.id,
      new.max_participants
      using errcode = 'invalid_parameter_value';
  end if;

  return new;
end;
$$;

comment on function app.forbid_locked_terms_change() is
  'BEFORE UPDATE on contests. Terms may only change while open and unaccepted by others.';

-- Freezes a participant's own two terms once the contest is under way. Before
-- the start, changing your mind about a charity harms nobody. After it, D5's
-- concern is live: a movable day boundary lets somebody roll their day back to
-- reopen a day they had already lost, and a movable charity turns a nomination
-- into a bait-and-switch once the result is visible.
-- Definer, like M1's cross-table triggers: it reads public.contests, and a
-- trigger that consults another table's rows must not have that read narrowed
-- by the caller's own policies.
create or replace function app.freeze_participant_choices()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.contest_status;
begin
  if new.charity_id is not distinct from old.charity_id
     and new.timezone is not distinct from old.timezone then
    return new;
  end if;

  select status into v_status from public.contests where id = old.contest_id;

  if v_status <> 'open' then
    raise exception
      'participant choices are frozen once the contest leaves open (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.freeze_participant_choices() is
  'BEFORE UPDATE on contest_participants. timezone and charity_id freeze when the contest starts.';

-- ===========================================================================
-- SECTION 4 — Triggers
-- ===========================================================================

create trigger charities_set_updated_at
  before update on public.charities
  for each row execute function app.set_updated_at();

create trigger contests_set_updated_at
  before update on public.contests
  for each row execute function app.set_updated_at();

-- created_at and the identity columns are never anybody's to rewrite. kind is
-- in the terms list too, but it is frozen here unconditionally: a duel that
-- becomes a group contest changes how many settlements a result can produce.
create trigger contests_freeze_columns
  before update on public.contests
  for each row execute function
    app.forbid_column_change('id', 'kind', 'created_by', 'created_at');

create trigger contests_assert_transition
  before update on public.contests
  for each row execute function app.assert_contest_transition();

create trigger contests_forbid_locked_terms
  before update on public.contests
  for each row execute function app.forbid_locked_terms_change();

create trigger contest_participants_set_updated_at
  before update on public.contest_participants
  for each row execute function app.set_updated_at();

create trigger contest_participants_freeze_columns
  before update on public.contest_participants
  for each row execute function
    app.forbid_column_change('contest_id', 'user_id', 'invited_at');

create trigger contest_participants_assert_transition
  before update on public.contest_participants
  for each row execute function app.assert_participant_transition();

create trigger contest_participants_freeze_choices
  before update on public.contest_participants
  for each row execute function app.freeze_participant_choices();

-- Reuses M1's validator, which was written for exactly this column (D5).
create trigger contest_participants_validate_timezone
  before insert or update on public.contest_participants
  for each row execute function app.assert_valid_timezone('timezone');

-- ===========================================================================
-- SECTION 5 — RLS predicates and policies
-- ===========================================================================
-- Definer rights again, and for the same reason as M1: a policy on
-- contest_participants that reads contest_participants would re-enter its own
-- policy and recurse.

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
  'True for any roster row, invitations included — an invitee must be able to read the terms.';

-- Co-participation, for the profiles read policy. Excludes the two statuses
-- that mean "not in this contest": a declined invitation and a lapsed one buy
-- no visibility, but a forfeit does, because M7 still has to settle it.
create or replace function app.shares_contest(a uuid, b uuid)
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
    where pa.user_id = a
      and pb.user_id = b
      and pa.status in ('invited', 'accepted', 'forfeited')
      and pb.status in ('invited', 'accepted', 'forfeited')
  );
$$;

comment on function app.shares_contest(uuid, uuid) is
  'True if both users hold a live roster row in one contest. Declined and lapsed do not count.';

alter table public.charities enable row level security;
alter table public.contests enable row level security;
alter table public.contest_participants enable row level security;

-- ---------------------------------------------------------------------------
-- charities
-- ---------------------------------------------------------------------------
-- Everything, including retired entries: a contest that nominated a charity
-- before it was retired still has to render its name. Filtering on is_active
-- is the picker's job, not the policy's.
create policy charities_select_all on public.charities
  for select to authenticated
  using (true);

-- No insert, update, or delete policy, and no grant either (section 7).

-- ---------------------------------------------------------------------------
-- contests
-- ---------------------------------------------------------------------------
-- Participants only, invitees included. Deliberately not "anyone in the group":
-- a group contest among four members of an eight-person group is visible to the
-- four with something at stake, and the other four are not told it happened.
create policy contests_select_participant on public.contests
  for select to authenticated
  using (app.is_contest_participant(id, (select auth.uid())));

-- No insert policy. Creation is public.create_contest(), which also seeds the
-- creator's roster row in the same transaction.

-- The creator may still edit terms while the offer stands. What "still stands"
-- means is enforced by app.forbid_locked_terms_change(); this policy only
-- decides which rows are reachable, and the column grants in section 7 decide
-- which columns. status is not among them — transitions are functions.
create policy contests_update_creator on public.contests
  for update to authenticated
  using (
    created_by = (select auth.uid())
    and status = 'open'
  )
  with check (
    created_by = (select auth.uid())
    and status = 'open'
  );

-- No delete policy. A contest is the record of an agreement, and cancelling is
-- a status, not an erasure — otherwise a losing creator could delete the
-- evidence that they agreed to donate.

-- ---------------------------------------------------------------------------
-- contest_participants
-- ---------------------------------------------------------------------------
create policy contest_participants_select_co on public.contest_participants
  for select to authenticated
  using (app.is_contest_participant(contest_id, (select auth.uid())));

-- No insert, update, or delete policy. Invitations, responses, and withdrawal
-- all need cross-row checks or a lock; see section 6.

-- ---------------------------------------------------------------------------
-- profiles: the third route to visibility
-- ---------------------------------------------------------------------------
-- M1 left a note that this is where it would be needed, and it is: a duel
-- between two people who are not friends and share no group still has to render
-- an opponent.
--
-- The contest route sits *outside* the block check, unlike the friend and group
-- routes, and that is the deliberate part. A block cannot create this situation
-- — nobody blocked can be invited, and nobody blocked can already be on the
-- roster (section 6) — so the only way to reach it is a block placed after the
-- invitation. At that point hiding the profile would replace a live opponent
-- with an unknown user in the blocked party's app, which announces the block to
-- exactly the person D19 went out of its way not to tell. The contest keeps
-- running either way; the pledge does not care how they feel about each other.
alter policy profiles_select_visible on public.profiles
  using (
    id = (select auth.uid())
    or (
      not app.is_blocked_either_way(id, (select auth.uid()))
      and (
        app.is_friend(id, (select auth.uid()))
        or app.shares_group(id, (select auth.uid()))
      )
    )
    or app.shares_contest(id, (select auth.uid()))
  );

-- ===========================================================================
-- SECTION 6 — Callable API
-- ===========================================================================

-- Creating a contest is one transaction that writes two tables: the terms, and
-- the creator's own acceptance of them. Splitting it would leave a window in
-- which a contest exists with an empty roster, and the last-one-out reasoning
-- from M1's groups applies here too — a contest nobody is in has no owner and
-- no way to be cleaned up.
create or replace function public.create_contest(
  p_kind                public.contest_kind,
  p_title               text,
  p_metric              public.metric_kind,
  p_cadence             public.contest_cadence,
  p_target_value        numeric,
  p_starts_at           timestamptz,
  p_ends_at             timestamptz,
  p_stake_amount_cents  integer,
  p_charity_id          uuid,
  p_timezone            text,
  p_group_id            uuid default null,
  p_tie_break           public.tie_break_rule default 'integrity_score',
  p_max_participants    smallint default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_contest_id uuid;
  v_max smallint;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'complete onboarding before creating a contest'
      using errcode = 'insufficient_privilege';
  end if;

  -- Only checkable at creation. It cannot be a CHECK constraint: now() is not
  -- immutable, and a constraint carrying it would re-evaluate on every later
  -- UPDATE and start rejecting rows for having begun.
  if p_starts_at <= now() then
    raise exception 'a contest must start in the future'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_kind = 'duel' then
    if p_group_id is not null then
      raise exception 'a duel is not attached to a group'
        using errcode = 'invalid_parameter_value';
    end if;
    v_max := 2;
  else
    if p_group_id is null then
      raise exception 'a group contest requires a group'
        using errcode = 'invalid_parameter_value';
    end if;
    -- Membership, not merely existence. Same error for both so this does not
    -- become a probe for whether a given group id is real.
    if not app.is_group_member(p_group_id, v_uid) then
      raise exception 'not a member of that group'
        using errcode = 'insufficient_privilege';
    end if;
    v_max := coalesce(p_max_participants, 20::smallint);
  end if;

  if not exists (
    select 1 from public.charities where id = p_charity_id and is_active
  ) then
    raise exception 'charity is unknown or no longer accepting nominations'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.contests (
    kind, status, group_id, created_by, title, metric, cadence, target_value,
    starts_at, ends_at, stake_amount_cents, tie_break, max_participants
  )
  values (
    p_kind, 'open', p_group_id, v_uid, p_title, p_metric, p_cadence,
    p_target_value, p_starts_at, p_ends_at, p_stake_amount_cents, p_tie_break,
    v_max
  )
  returning id into v_contest_id;

  -- The creator wrote the terms, so they are accepted by definition. Their
  -- timezone and charity are captured here for the same reason everyone
  -- else's are captured on acceptance.
  insert into public.contest_participants (
    contest_id, user_id, status, charity_id, timezone, responded_at
  )
  values (v_contest_id, v_uid, 'accepted', p_charity_id, p_timezone, now());

  return v_contest_id;
end;
$$;

comment on function public.create_contest is
  'Create a contest and enrol the creator as an accepted participant. Returns the contest id.';

-- Invitation eligibility is three questions about rows other than the one being
-- written, which is why this is a function and not a WITH CHECK.
create or replace function public.invite_to_contest(
  p_contest_id uuid,
  p_user_id    uuid
)
returns public.participant_status
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_contest public.contests;
  v_existing public.participant_status;
  v_roster int;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- Locked for the same reason acceptance locks: max_participants bounds a
  -- count, and two concurrent invitations to the last slot must not both pass.
  select * into v_contest
  from public.contests
  where id = p_contest_id
  for update;

  -- Non-existent and not-yours are the same error. A distinguishable "no such
  -- contest" would let anyone probe for valid contest ids.
  if v_contest.id is null or v_contest.created_by is distinct from v_uid then
    raise exception 'not the creator of that contest'
      using errcode = 'insufficient_privilege';
  end if;

  if v_contest.status <> 'open' then
    raise exception 'contest is no longer accepting participants (status %)',
      v_contest.status
      using errcode = 'restrict_violation';
  end if;

  if p_user_id = v_uid then
    raise exception 'the creator is already a participant'
      using errcode = 'invalid_parameter_value';
  end if;

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'that user has not completed onboarding'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Idempotent, because the mobile client will retry this on a flaky
  -- connection. Returning the status it found lets the caller tell "already
  -- invited" from "they said no" without a second read.
  select status into v_existing
  from public.contest_participants
  where contest_id = p_contest_id and user_id = p_user_id;

  if v_existing is not null then
    return v_existing;
  end if;

  -- Who you may invite depends on the kind, and both routes mirror the two
  -- routes to profile visibility M1 established: a duel is between friends, a
  -- group contest is among the group.
  if v_contest.kind = 'duel' then
    if not app.is_friend(v_contest.created_by, p_user_id) then
      raise exception 'a duel invitation must go to a friend'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if v_contest.group_id is null
       or not app.is_group_member(v_contest.group_id, p_user_id) then
      raise exception 'a group contest invitation must go to a member of its group'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- This is where a block earns its keep, and it is checked against every
  -- person already on the roster rather than against the creator alone. M1 left
  -- the tension recorded: blocking does not eject either party from a shared
  -- group, so without this check a group contest would be a way to put two
  -- people who have blocked each other into a mutual donation obligation.
  -- Blocking still removes nobody from anything — it only refuses the pairing.
  if exists (
    select 1
    from public.contest_participants p
    where p.contest_id = p_contest_id
      and p.status in ('invited', 'accepted')
      and app.is_blocked_either_way(p.user_id, p_user_id)
  ) then
    raise exception 'cannot invite a user blocked by or blocking a participant'
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_roster
  from public.contest_participants
  where contest_id = p_contest_id
    and status in ('invited', 'accepted');

  -- Outstanding invitations count against the cap. Otherwise a creator could
  -- invite thirty people to a contest capped at four and let the race decide,
  -- which is a worse experience than being told the contest is full.
  if v_roster >= v_contest.max_participants then
    raise exception 'contest is full (% of %)', v_roster, v_contest.max_participants
      using errcode = 'restrict_violation';
  end if;

  insert into public.contest_participants (contest_id, user_id, status)
  values (p_contest_id, p_user_id, 'invited');

  return 'invited'::public.participant_status;
end;
$$;

comment on function public.invite_to_contest(uuid, uuid) is
  'Invite a friend (duel) or co-member (group) to a contest. Idempotent; refuses across a block.';

-- Acceptance is the one place the cap has to be genuinely serialized: the check
-- is on a COUNT, and two people taking the last slot at the same instant both
-- pass it unless the contest row is locked first.
create or replace function public.accept_contest_invitation(
  p_contest_id uuid,
  p_charity_id uuid,
  p_timezone   text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_contest public.contests;
  v_status public.participant_status;
  v_accepted int;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_contest
  from public.contests
  where id = p_contest_id
  for update;

  select status into v_status
  from public.contest_participants
  where contest_id = p_contest_id and user_id = v_uid;

  -- No invitation and no such contest are the same error, again so this cannot
  -- be used to discover that a contest exists.
  if v_status is null then
    raise exception 'no invitation to that contest'
      using errcode = 'no_data_found';
  end if;

  if v_status = 'accepted' then
    return;  -- Idempotent: a retried accept is not an error.
  end if;

  if v_status <> 'invited' then
    raise exception 'invitation is no longer open (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  if v_contest.status <> 'open' then
    raise exception 'contest is no longer accepting participants (status %)',
      v_contest.status
      using errcode = 'restrict_violation';
  end if;

  if not exists (
    select 1 from public.charities where id = p_charity_id and is_active
  ) then
    raise exception 'charity is unknown or no longer accepting nominations'
      using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_accepted
  from public.contest_participants
  where contest_id = p_contest_id and status = 'accepted';

  if v_accepted >= v_contest.max_participants then
    raise exception 'contest is full (% of %)',
      v_accepted, v_contest.max_participants
      using errcode = 'restrict_violation';
  end if;

  update public.contest_participants
  set status     = 'accepted',
      charity_id = p_charity_id,
      timezone   = p_timezone
  where contest_id = p_contest_id and user_id = v_uid;
end;
$$;

comment on function public.accept_contest_invitation(uuid, uuid, text) is
  'Accept an invitation, nominating a charity and freezing a timezone. Idempotent; enforces the cap under a lock.';

create or replace function public.decline_contest_invitation(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_status public.participant_status;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  select status into v_status
  from public.contest_participants
  where contest_id = p_contest_id and user_id = v_uid;

  if v_status is null then
    raise exception 'no invitation to that contest'
      using errcode = 'no_data_found';
  end if;

  if v_status = 'declined' then
    return;
  end if;

  if v_status <> 'invited' then
    raise exception 'invitation is no longer open (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  update public.contest_participants
  set status = 'declined'
  where contest_id = p_contest_id and user_id = v_uid;
end;
$$;

comment on function public.decline_contest_invitation(uuid) is
  'Decline an invitation. Terminal: the contest cannot re-invite you (D25).';

-- Leaving before the start. After the start this is a forfeit, which is a loss
-- with a settlement attached and therefore M7's, not a withdrawal.
create or replace function public.withdraw_from_contest(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_contest public.contests;
  v_status public.participant_status;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_contest
  from public.contests
  where id = p_contest_id
  for update;

  select status into v_status
  from public.contest_participants
  where contest_id = p_contest_id and user_id = v_uid;

  if v_status is null then
    raise exception 'not a participant in that contest'
      using errcode = 'no_data_found';
  end if;

  if v_status = 'withdrawn' then
    return;
  end if;

  if v_status <> 'accepted' then
    raise exception 'only an accepted participant can withdraw (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  if v_contest.status <> 'open' then
    raise exception 'the contest has already started; withdrawal is no longer possible'
      using errcode = 'restrict_violation';
  end if;

  -- The creator leaving would strand a contest with terms nobody can edit and
  -- an owner who is not in it. Cancelling is the honest action, and it tells
  -- the invitees something rather than silently emptying the roster.
  if v_contest.created_by = v_uid then
    raise exception 'the creator cancels a contest rather than withdrawing from it'
      using errcode = 'restrict_violation';
  end if;

  update public.contest_participants
  set status = 'withdrawn'
  where contest_id = p_contest_id and user_id = v_uid;
end;
$$;

comment on function public.withdraw_from_contest(uuid) is
  'Withdraw before the contest starts. Not available to the creator, and not after the start.';

create or replace function public.cancel_contest(p_contest_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_contest public.contests;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_contest
  from public.contests
  where id = p_contest_id
  for update;

  if v_contest.id is null or v_contest.created_by is distinct from v_uid then
    raise exception 'not the creator of that contest'
      using errcode = 'insufficient_privilege';
  end if;

  if v_contest.status = 'cancelled' then
    return;
  end if;

  -- Only before the start. Once a contest is active there are stakes on the
  -- table, and letting the creator delete it would be a way for a losing
  -- creator to escape a pledge. An active contest ends by being scored.
  if v_contest.status <> 'open' then
    raise exception 'only an open contest can be cancelled (status %)', v_contest.status
      using errcode = 'restrict_violation';
  end if;

  update public.contests set status = 'cancelled' where id = p_contest_id;

  update public.contest_participants
  set status = 'lapsed'
  where contest_id = p_contest_id and status = 'invited';
end;
$$;

comment on function public.cancel_contest(uuid) is
  'Cancel an open contest. Unanswered invitations lapse; the row survives as a record.';

-- The state machine's driver. Not a client function: it acts on every contest
-- that has come due, not on one the caller has any particular claim to, so it
-- is granted to service_role only. The scheduler that calls it hourly arrives
-- with the rest of the cron work in M7; keeping it callable now is what makes
-- the open → active edge testable rather than aspirational, and it is what M3
-- needs in order to have an active contest to ingest against.
create or replace function app.activate_due_contests()
returns table (contest_id uuid, new_status public.contest_status)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_accepted int;
  v_next public.contest_status;
begin
  for r in
    select id
    from public.contests
    where status = 'open'
      and starts_at <= now()
    order by id
    for update
  loop
    select count(*) into v_accepted
    from public.contest_participants
    where contest_participants.contest_id = r.id
      and status = 'accepted';

    -- A contest needs two people to be a contest. One acceptance means the
    -- invitations went unanswered or were declined, and the honest outcome is
    -- a cancellation rather than a contest somebody wins by default.
    v_next := case when v_accepted >= 2 then 'active' else 'cancelled' end;

    update public.contests set status = v_next where id = r.id;

    -- An invitation that was never answered does not survive the start. It is
    -- 'lapsed' rather than 'declined' because they never said no, and the
    -- distinction is visible in the data: a lapsed row has no charity and no
    -- timezone, having never chosen either.
    update public.contest_participants
    set status = 'lapsed'
    where contest_participants.contest_id = r.id
      and status = 'invited';

    contest_id := r.id;
    new_status := v_next;
    return next;
  end loop;
end;
$$;

comment on function app.activate_due_contests() is
  'Resolve every open contest whose start has passed: active with 2+ accepted, else cancelled.';

-- ===========================================================================
-- SECTION 7 — Privileges
-- ===========================================================================
-- As in M1: RLS decides which rows, grants decide which verbs, and Supabase's
-- default privileges hand out ALL on new public tables unless revoked. The
-- withheld list below is long because most mutation here is a function.

revoke all on public.charities, public.contests, public.contest_participants
  from anon, authenticated;

grant select on public.charities to authenticated;
grant select on public.contests to authenticated;
grant select on public.contest_participants to authenticated;

-- Column-level. These are the terms a creator may still revise while the offer
-- stands; app.forbid_locked_terms_change() decides when that is. status is
-- absent on purpose — every transition is a function, so there is no path by
-- which a client writes a status directly.
grant update (
  title, metric, cadence, target_value, starts_at, ends_at,
  stake_amount_cents, tie_break, max_participants
) on public.contests to authenticated;

-- Deliberately withheld, each backed by a missing grant as well as a missing
-- policy (D21):
--   charities             ALL but SELECT — reference data, maintained out of band
--   contests              INSERT         — create_contest() owns this
--   contests              DELETE         — a contest is a record; cancel is a status
--   contests              UPDATE status  — the state machine owns transitions
--   contests              UPDATE kind, group_id, created_by — identity, not terms
--   contest_participants  INSERT         — invite_to_contest() owns this
--   contest_participants  UPDATE         — accept/decline/withdraw own this
--   contest_participants  DELETE         — leaving is a status, so it stays visible

revoke all on function public.create_contest(
  public.contest_kind, text, public.metric_kind, public.contest_cadence,
  numeric, timestamptz, timestamptz, integer, uuid, text, uuid,
  public.tie_break_rule, smallint
) from public, anon;
revoke all on function public.invite_to_contest(uuid, uuid) from public, anon;
revoke all on function public.accept_contest_invitation(uuid, uuid, text) from public, anon;
revoke all on function public.decline_contest_invitation(uuid) from public, anon;
revoke all on function public.withdraw_from_contest(uuid) from public, anon;
revoke all on function public.cancel_contest(uuid) from public, anon;

grant execute on function public.create_contest(
  public.contest_kind, text, public.metric_kind, public.contest_cadence,
  numeric, timestamptz, timestamptz, integer, uuid, text, uuid,
  public.tie_break_rule, smallint
) to authenticated;
grant execute on function public.invite_to_contest(uuid, uuid) to authenticated;
grant execute on function public.accept_contest_invitation(uuid, uuid, text) to authenticated;
grant execute on function public.decline_contest_invitation(uuid) to authenticated;
grant execute on function public.withdraw_from_contest(uuid) to authenticated;
grant execute on function public.cancel_contest(uuid) to authenticated;

-- Not a client function. It sweeps every due contest, so no client has a claim
-- to it; the M7 scheduler runs as service_role.
revoke all on function app.activate_due_contests() from public, anon, authenticated;
grant execute on function app.activate_due_contests() to service_role;
