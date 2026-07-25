-- M5 — Consent-backed timezone changes.
--
-- contest_participants.timezone remains the immutable zone accepted with the
-- original contest terms. A genuine move is represented by three append-only
-- ledgers instead: a request, the other participants' votes, and the applied
-- change that starts a new timezone epoch. Ingest resolves the epoch that was
-- effective for the hour being written, so a late revision never rewrites the
-- local day of evidence from an older epoch.

-- ===========================================================================
-- SECTION 1 — Append-only consent ledgers
-- ===========================================================================

create type public.timezone_change_state as enum (
  'pending',
  'approved',
  'rejected'
);

create table public.timezone_change_requests (
  id             uuid primary key default gen_random_uuid(),
  contest_id     uuid not null,
  user_id        uuid not null,
  from_timezone  text not null,
  to_timezone    text not null,
  requested_at   timestamptz not null default clock_timestamp(),

  constraint timezone_change_requests_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete cascade,

  -- Lets an applied event prove that every copied identity field came from one
  -- immutable request rather than trusting denormalised caller input.
  constraint timezone_change_requests_applied_identity_unique
    unique (id, contest_id, user_id, from_timezone, to_timezone),

  constraint timezone_change_requests_different_zone
    check (from_timezone <> to_timezone)
);

comment on table public.timezone_change_requests is
  'Append-only requests to start a new timezone epoch in one active contest.';
comment on column public.timezone_change_requests.from_timezone is
  'Server-resolved zone effective when the request was created.';

create index timezone_change_requests_participant_idx
  on public.timezone_change_requests (contest_id, user_id, requested_at);

create table public.timezone_change_reviews (
  request_id       uuid not null
    references public.timezone_change_requests (id) on delete cascade,
  reviewer_user_id uuid not null
    references public.profiles (id) on delete cascade,
  approved         boolean not null,
  reviewed_at      timestamptz not null default clock_timestamp(),

  primary key (request_id, reviewer_user_id)
);

comment on table public.timezone_change_reviews is
  'Append-only votes by the other accepted participants on a timezone request.';

create index timezone_change_reviews_reviewer_idx
  on public.timezone_change_reviews (reviewer_user_id);

create table public.timezone_change_applied_events (
  id             uuid primary key default gen_random_uuid(),
  request_id     uuid not null unique,
  contest_id     uuid not null,
  user_id        uuid not null,
  from_timezone  text not null,
  to_timezone    text not null,

  -- The review function supplies the server clock, truncated to the precision
  -- shared with JavaScript and Swift. There is deliberately no effective-time
  -- argument in the authenticated API. A migration owner may still insert a
  -- controlled historical fixture for ingest regression tests.
  -- JavaScript and Swift consumers preserve milliseconds, not PostgreSQL's
  -- finer microseconds. Truncating at the authority keeps every layer on the
  -- exact same epoch boundary.
  effective_at   timestamptz not null
    default date_trunc('milliseconds', clock_timestamp()),

  constraint timezone_change_applied_events_request_fkey
    foreign key (
      request_id, contest_id, user_id, from_timezone, to_timezone
    )
    references public.timezone_change_requests (
      id, contest_id, user_id, from_timezone, to_timezone
    )
    on delete cascade,

  constraint timezone_change_applied_events_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete cascade,

  constraint timezone_change_applied_events_different_zone
    check (from_timezone <> to_timezone)
);

comment on table public.timezone_change_applied_events is
  'Immutable timezone epochs created exactly once after unanimous consent.';
comment on column public.timezone_change_applied_events.effective_at is
  'Server-controlled instant at which to_timezone begins governing new buckets.';

create unique index timezone_change_applied_events_epoch_idx
  on public.timezone_change_applied_events (
    contest_id, user_id, effective_at desc
  );

create trigger timezone_change_requests_validate_from_timezone
  before insert or update on public.timezone_change_requests
  for each row execute function app.assert_valid_timezone('from_timezone');

create trigger timezone_change_requests_validate_to_timezone
  before insert or update on public.timezone_change_requests
  for each row execute function app.assert_valid_timezone('to_timezone');

create trigger timezone_change_applied_events_validate_from_timezone
  before insert or update on public.timezone_change_applied_events
  for each row execute function app.assert_valid_timezone('from_timezone');

create trigger timezone_change_applied_events_validate_to_timezone
  before insert or update on public.timezone_change_applied_events
  for each row execute function app.assert_valid_timezone('to_timezone');

create trigger timezone_change_requests_forbid_mutation
  before update on public.timezone_change_requests
  for each row execute function app.forbid_mutation();

create trigger timezone_change_reviews_forbid_mutation
  before update on public.timezone_change_reviews
  for each row execute function app.forbid_mutation();

create trigger timezone_change_applied_events_forbid_mutation
  before update on public.timezone_change_applied_events
  for each row execute function app.forbid_mutation();

-- DELETE is still absent from every client grant and policy. It is not guarded
-- by a trigger because privileged account/contest deletion must be able to
-- follow the ON DELETE CASCADE foreign keys, matching the existing evidence
-- and quarantine ledgers.

-- ===========================================================================
-- SECTION 2 — Computed request status
-- ===========================================================================

-- Every other accepted participant must approve. One rejection is terminal,
-- while any missing vote remains pending forever; silence is never consent.
create view public.timezone_change_request_status
with (security_invoker = true)
as
select
  request.id,
  request.contest_id,
  request.user_id,
  request.from_timezone,
  request.to_timezone,
  request.requested_at,
  eligible.reviewer_count,
  votes.approval_count,
  votes.rejection_count,
  case
    when votes.rejection_count > 0
      then 'rejected'::public.timezone_change_state
    when eligible.reviewer_count > 0
         and votes.approval_count = eligible.reviewer_count
      then 'approved'::public.timezone_change_state
    else 'pending'::public.timezone_change_state
  end as state
from public.timezone_change_requests request
cross join lateral (
  select count(*)::integer as reviewer_count
  from public.contest_participants participant
  where participant.contest_id = request.contest_id
    and participant.status = 'accepted'
    and participant.user_id <> request.user_id
) eligible
cross join lateral (
  select
    count(*) filter (where review.approved)::integer as approval_count,
    count(*) filter (where not review.approved)::integer as rejection_count
  from public.timezone_change_reviews review
  join public.contest_participants participant
    on participant.contest_id = request.contest_id
   and participant.user_id = review.reviewer_user_id
   and participant.status = 'accepted'
  where review.request_id = request.id
    and review.reviewer_user_id <> request.user_id
) votes;

comment on view public.timezone_change_request_status is
  'Unanimous consent state derived from immutable votes by the other accepted contest participants.';

-- ===========================================================================
-- SECTION 3 — Callable consent API
-- ===========================================================================

create or replace function public.request_timezone_change(
  p_contest_id uuid,
  p_timezone   text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid                 uuid := (select auth.uid());
  v_participant_status  public.contest_participant_status;
  v_initial_timezone    text;
  v_from_timezone       text;
  v_contest_status      public.contest_status;
  v_ends_at             timestamptz;
  v_existing_id         uuid;
  v_existing_timezone   text;
  v_request_id          uuid;
begin
  if v_uid is null then
    raise exception 'sign in before requesting a timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  if p_contest_id is null then
    raise exception 'contest id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- This participant row is the serialization point for request, review,
  -- apply, and ingest. Every path takes it before a request-row lock.
  select participant.status,
         participant.timezone,
         contest.status,
         contest.ends_at
    into v_participant_status,
         v_initial_timezone,
         v_contest_status,
         v_ends_at
  from public.contest_participants participant
  join public.contests contest on contest.id = participant.contest_id
  where participant.contest_id = p_contest_id
    and participant.user_id = v_uid
  for update of participant;

  if not found then
    raise exception 'only a contest participant may request a timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  if v_participant_status <> 'accepted' then
    raise exception
      'only an accepted participant may request a timezone change (status %)',
      v_participant_status
      using errcode = 'restrict_violation';
  end if;

  if v_contest_status <> 'active' then
    raise exception
      'only an active contest may request a timezone change (status %)',
      v_contest_status
      using errcode = 'restrict_violation';
  end if;

  if clock_timestamp() >= v_ends_at then
    raise exception 'the contest ended at %', v_ends_at
      using errcode = 'restrict_violation';
  end if;

  if p_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names
       where name = p_timezone
     )
  then
    raise exception 'invalid IANA timezone: %', p_timezone
      using errcode = 'invalid_parameter_value';
  end if;

  select coalesce((
    select applied.to_timezone
    from public.timezone_change_applied_events applied
    where applied.contest_id = p_contest_id
      and applied.user_id = v_uid
      and applied.effective_at <= clock_timestamp()
    order by applied.effective_at desc, applied.id desc
    limit 1
  ), v_initial_timezone)
    into v_from_timezone;

  if p_timezone = v_from_timezone then
    raise exception 'timezone % is already effective for this contest', p_timezone
      using errcode = 'invalid_parameter_value';
  end if;

  -- The participant lock makes this scan race-free. Lock the unresolved
  -- request second so every path has the same lock order.
  select request.id, request.to_timezone
    into v_existing_id, v_existing_timezone
  from public.timezone_change_requests request
  where request.contest_id = p_contest_id
    and request.user_id = v_uid
    and not exists (
      select 1
      from public.timezone_change_reviews rejection
      where rejection.request_id = request.id
        and not rejection.approved
    )
    and not exists (
      select 1
      from public.timezone_change_applied_events applied
      where applied.request_id = request.id
    )
  order by request.requested_at, request.id
  limit 1
  for update of request;

  if found then
    if v_existing_timezone = p_timezone then
      return v_existing_id;
    end if;

    raise exception
      'participant already has an unresolved timezone request to %',
      v_existing_timezone
      using errcode = 'unique_violation';
  end if;

  insert into public.timezone_change_requests (
    contest_id, user_id, from_timezone, to_timezone
  )
  values (
    p_contest_id, v_uid, v_from_timezone, p_timezone
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

comment on function public.request_timezone_change(uuid, text) is
  'Creates one pending timezone request for the caller in an active contest; identical pending retries are idempotent.';

create or replace function public.review_timezone_change(
  p_request_id uuid,
  p_approved   boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid                 uuid := (select auth.uid());
  v_identity            record;
  v_request             public.timezone_change_requests;
  v_requester_status    public.contest_participant_status;
  v_contest_status      public.contest_status;
  v_ends_at             timestamptz;
  v_existing_vote       boolean;
  v_reviewer_count      integer;
  v_approval_count      integer;
begin
  if v_uid is null then
    raise exception 'sign in before reviewing a timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  if p_request_id is null or p_approved is null then
    raise exception 'request id and review decision are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Read immutable identity first only to find the participant lock. The
  -- request is re-read under lock after the participant serialization point.
  select request.contest_id, request.user_id
    into v_identity
  from public.timezone_change_requests request
  where request.id = p_request_id;

  if v_identity.contest_id is null then
    raise exception 'timezone request not found'
      using errcode = 'insufficient_privilege';
  end if;

  select participant.status, contest.status, contest.ends_at
    into v_requester_status, v_contest_status, v_ends_at
  from public.contest_participants participant
  join public.contests contest on contest.id = participant.contest_id
  where participant.contest_id = v_identity.contest_id
    and participant.user_id = v_identity.user_id
  for update of participant;

  if not found then
    raise exception 'timezone request participant no longer exists'
      using errcode = 'foreign_key_violation';
  end if;

  select request.*
    into v_request
  from public.timezone_change_requests request
  where request.id = p_request_id
  for update of request;

  if v_request.id is null then
    raise exception 'timezone request not found'
      using errcode = 'insufficient_privilege';
  end if;

  if v_requester_status <> 'accepted' then
    raise exception
      'timezone requester is not an accepted participant (status %)',
      v_requester_status
      using errcode = 'restrict_violation';
  end if;

  if v_contest_status <> 'active' then
    raise exception
      'only an active contest may review a timezone change (status %)',
      v_contest_status
      using errcode = 'restrict_violation';
  end if;

  if clock_timestamp() >= v_ends_at then
    raise exception 'the contest ended at %', v_ends_at
      using errcode = 'restrict_violation';
  end if;

  if v_request.user_id = v_uid then
    raise exception 'a participant cannot review their own timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  select review.approved
    into v_existing_vote
  from public.timezone_change_reviews review
  where review.request_id = p_request_id
    and review.reviewer_user_id = v_uid;

  if found then
    if v_existing_vote = p_approved then
      return;
    end if;

    raise exception 'a timezone change review cannot be changed'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from public.timezone_change_applied_events applied
    where applied.request_id = p_request_id
  ) or exists (
    select 1
    from public.timezone_change_reviews rejection
    where rejection.request_id = p_request_id
      and not rejection.approved
  ) then
    raise exception 'timezone request is already terminal'
      using errcode = 'restrict_violation';
  end if;

  if not exists (
    select 1
    from public.contest_participants reviewer
    where reviewer.contest_id = v_request.contest_id
      and reviewer.user_id = v_uid
      and reviewer.status = 'accepted'
  ) then
    raise exception
      'only another accepted participant may review this timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.timezone_change_reviews (
    request_id, reviewer_user_id, approved
  )
  values (p_request_id, v_uid, p_approved);

  select
    count(*)::integer,
    count(*) filter (
      where exists (
        select 1
        from public.timezone_change_reviews approval
        where approval.request_id = p_request_id
          and approval.reviewer_user_id = participant.user_id
          and approval.approved
      )
    )::integer
    into v_reviewer_count, v_approval_count
  from public.contest_participants participant
  where participant.contest_id = v_request.contest_id
    and participant.status = 'accepted'
    and participant.user_id <> v_request.user_id;

  if v_reviewer_count > 0 and v_approval_count = v_reviewer_count then
    insert into public.timezone_change_applied_events (
      request_id,
      contest_id,
      user_id,
      from_timezone,
      to_timezone,
      effective_at
    )
    values (
      v_request.id,
      v_request.contest_id,
      v_request.user_id,
      v_request.from_timezone,
      v_request.to_timezone,
      date_trunc('milliseconds', clock_timestamp())
    )
    on conflict (request_id) do nothing;
  end if;
end;
$$;

comment on function public.review_timezone_change(uuid, boolean) is
  'Records one immutable vote by another accepted participant and applies the change after unanimous approval.';

-- ===========================================================================
-- SECTION 4 — RLS and least privilege
-- ===========================================================================

alter table public.timezone_change_requests enable row level security;
alter table public.timezone_change_reviews enable row level security;
alter table public.timezone_change_applied_events enable row level security;

create policy timezone_change_requests_select_roster
  on public.timezone_change_requests
  for select to authenticated
  using (
    app.is_contest_participant(contest_id, (select auth.uid()))
  );

create policy timezone_change_reviews_select_roster
  on public.timezone_change_reviews
  for select to authenticated
  using (
    exists (
      select 1
      from public.timezone_change_requests request
      where request.id = request_id
        and app.is_contest_participant(
          request.contest_id, (select auth.uid())
        )
    )
  );

create policy timezone_change_applied_events_select_roster
  on public.timezone_change_applied_events
  for select to authenticated
  using (
    app.is_contest_participant(contest_id, (select auth.uid()))
  );

-- There are no INSERT, UPDATE, or DELETE policies. All authenticated writes
-- flow through the two functions above.
revoke all on public.timezone_change_requests,
              public.timezone_change_reviews,
              public.timezone_change_applied_events,
              public.timezone_change_request_status
  from anon, authenticated;

grant select on public.timezone_change_requests,
                public.timezone_change_reviews,
                public.timezone_change_applied_events,
                public.timezone_change_request_status
  to authenticated;

revoke all on function public.request_timezone_change(uuid, text)
  from public, anon, authenticated;
grant execute on function public.request_timezone_change(uuid, text)
  to authenticated;

revoke all on function public.review_timezone_change(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.review_timezone_change(uuid, boolean)
  to authenticated;

-- ===========================================================================
-- SECTION 5 — Effective-time ingest
-- ===========================================================================

create or replace function app.prepare_metric_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status          public.contest_participant_status;
  v_initial_timezone text;
  v_timezone        text;
  v_contest_status  public.contest_status;
  v_starts_at       timestamptz;
  v_ends_at         timestamptz;
  v_local           timestamp;
  v_highest         numeric(12, 2);
begin
  -- KEY SHARE makes an ingest race wait for review/apply, whose participant
  -- UPDATE lock is taken before its request lock. The bucket therefore observes
  -- either the complete old epoch or the complete new one.
  select p.status, p.timezone, c.status, c.starts_at, c.ends_at
    into v_status, v_initial_timezone,
         v_contest_status, v_starts_at, v_ends_at
  from public.contest_participants p
  join public.contests c on c.id = p.contest_id
  where p.contest_id = new.contest_id
    and p.user_id = new.user_id
  for key share of p;

  if v_status is null then
    raise exception 'no roster row for user % on contest %', new.user_id, new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  -- Evidence from someone who is not running in the contest measures nothing.
  -- An invitation is not participation, and a withdrawal ends it.
  if v_status <> 'accepted' then
    raise exception
      'only an accepted participant may record evidence (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  -- The contest must be open. Not pending: there is nothing to measure before
  -- the window exists. Not cancelled or finalized: a settled contest is
  -- closed evidence, which is the finalized-contest immutability D6 asks for.
  if v_contest_status <> 'active' then
    raise exception
      'contest % is not accepting evidence (status %)', new.contest_id, v_contest_status
      using errcode = 'restrict_violation';
  end if;

  -- The grace window. `status = active` alone would let a contest whose cron
  -- finalisation never ran accept evidence indefinitely, which is a stalled
  -- job turning into an exploit.
  if now() >= v_ends_at + app.ingest_grace_period() then
    raise exception
      'the ingest window for contest % closed at %',
      new.contest_id, v_ends_at + app.ingest_grace_period()
      using errcode = 'restrict_violation';
  end if;

  -- The bucket must lie wholly inside the agreed window.
  --
  -- This is the other half of D25. That rule stops a contest naming a window
  -- already in the past; this one stops evidence being tendered for hours
  -- outside the window it named. Either one alone leaves the exploit open from
  -- the other end, and neither is expensive.
  --
  -- "Wholly inside" rather than "starts inside" on purpose: a bucket that
  -- began before the last hour of the window would carry activity from after
  -- the contest ended. A window that is not itself hour-aligned therefore has
  -- an unusable partial hour at each end, which is the conservative direction
  -- to fail in.
  if new.bucket_start < v_starts_at
     or new.bucket_start + interval '1 hour' > v_ends_at
  then
    raise exception
      'bucket % is outside the window of contest % (% to %)',
      new.bucket_start, new.contest_id, v_starts_at, v_ends_at
      using errcode = 'invalid_parameter_value';
  end if;

  -- An hour that has not finished cannot have been measured. Without this,
  -- every contest with a window still open would accept a complete set of
  -- winning figures for the rest of it, in advance, from a client that simply
  -- made them up — and the window rule above would happily allow it, because
  -- those hours are inside the agreed window.
  --
  -- No tolerance for clock skew, for D25's reason: a grace period here is
  -- exactly the amount of the future it lets you report. A client that is a
  -- second early retries a second later, which costs it nothing.
  if new.bucket_start + interval '1 hour' > now() then
    raise exception 'bucket % has not finished yet (now %)', new.bucket_start, now()
      using errcode = 'invalid_parameter_value';
  end if;

  select applied.to_timezone
    into v_timezone
  from public.timezone_change_applied_events applied
  where applied.contest_id = new.contest_id
    and applied.user_id = new.user_id
    and applied.effective_at <= new.bucket_start
  order by applied.effective_at desc, applied.id desc
  limit 1;

  v_timezone := coalesce(v_timezone, v_initial_timezone);

  -- A timezone transition can change the alignment and local-day owner of an
  -- hour. Refuse an hour containing the transition rather than attribute its
  -- two halves to either epoch.
  if exists (
    select 1
    from public.timezone_change_applied_events applied
    where applied.contest_id = new.contest_id
      and applied.user_id = new.user_id
      and applied.effective_at > new.bucket_start
      and applied.effective_at < new.bucket_start + interval '1 hour'
  ) then
    raise exception 'bucket % straddles a timezone change', new.bucket_start
      using errcode = 'invalid_parameter_value';
  end if;

  -- Alignment, and then the local day, both read from the zone effective for
  -- this bucket. A participant who has accepted always has an initial one.
  v_local := new.bucket_start at time zone v_timezone;

  if v_local <> date_trunc('hour', v_local) then
    raise exception
      'bucket % is not aligned to a whole hour in % (local %)',
      new.bucket_start, v_timezone, v_local
      using errcode = 'invalid_parameter_value';
  end if;

  new.local_day  := v_local::date;
  new.local_hour := extract(hour from v_local)::smallint;

  -- Monotonicity. The figure for a bucket may be revised upward as late
  -- samples arrive; it may not be walked back.
  --
  -- This is not framed as anti-cheat, and it would be dishonest to: only the
  -- participant may write their own rows, so a downward revision harms nobody
  -- but its author. What it buys is that "the value for this bucket" is
  -- single-valued — the latest observation and the largest observation are the
  -- same number — so the scoring engine, the standings, and any later audit
  -- cannot arrive at different totals from the same ledger. It also makes a
  -- genuine deletion in the Health app surface as a dispute for M7 rather than
  -- as a quiet rewrite of banked evidence.
  --
  -- Keyed on provenance as well, because that is the grain a value has: each
  -- source's contribution to an hour grows on its own, and comparing a watch's
  -- figure against a running app's would refuse perfectly ordinary data.
  --
  -- Rows inserted earlier in the same statement are visible here, so a batch
  -- cannot smuggle a decrease past this by ordering.
  select max(value) into v_highest
  from public.metric_snapshots
  where contest_id = new.contest_id
    and user_id = new.user_id
    and metric = new.metric
    and bucket_start = new.bucket_start
    and provenance = new.provenance;

  if v_highest is not null and new.value < v_highest then
    raise exception
      'bucket % of % from % already stands at %; a figure cannot be revised down to %',
      new.bucket_start, new.metric, new.provenance, v_highest, new.value
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.prepare_metric_snapshot() is
  'BEFORE INSERT on metric_snapshots. Window, effective-timezone alignment, local-day stamping, and monotonicity.';
