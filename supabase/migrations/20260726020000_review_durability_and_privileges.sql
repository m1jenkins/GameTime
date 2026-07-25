-- Post-M6 audit hardening.
--
-- Review outcomes must not be rewritten by a later roster or account change.
-- Snapshot the eligible-reviewer denominator when the durable fact is created,
-- retain reviewer UUIDs as pseudonymous audit identities after account
-- deletion, and derive state only from those immutable facts.

-- Supabase applies migration statements individually unless the file opens an
-- explicit transaction. The locks and invariant audits below must cover the
-- entire upgrade, not just one statement.
begin;

-- Establish one migration-wide linearization point for review votes and the
-- roster denominators they were created against. Account-deletion cascades and
-- ordinary roster/review writes wait until both reviewer FKs are gone and both
-- denominator backfills are fixed; reads remain available.
lock table public.contest_participants,
           public.timezone_change_reviews,
           public.evidence_quarantine_reviews
  in share row exclusive mode;

-- ===========================================================================
-- SECTION 1 — Timezone review durability and epoch boundaries
-- ===========================================================================

-- Drop the cascading reviewer link first. ALTER TABLE retains its write-
-- conflicting lock to commit, so account deletion cannot erase a vote between
-- the denominator backfill and this durability change.
alter table public.timezone_change_reviews
  drop constraint if exists
    timezone_change_reviews_reviewer_user_id_fkey;

comment on column public.timezone_change_reviews.reviewer_user_id is
  'Pseudonymous historical reviewer identity retained after account deletion.';

alter table public.timezone_change_requests
  add column required_reviewer_count smallint;

alter table public.timezone_change_requests
  disable trigger timezone_change_requests_forbid_mutation;

update public.timezone_change_requests request
set required_reviewer_count = (
  select count(*)::smallint
  from public.contest_participants participant
  where participant.contest_id = request.contest_id
    and participant.status = 'accepted'
    and participant.user_id <> request.user_id
);

alter table public.timezone_change_requests
  enable trigger timezone_change_requests_forbid_mutation;

alter table public.timezone_change_requests
  alter column required_reviewer_count set not null,
  add constraint timezone_change_requests_reviewer_count_range
    check (required_reviewer_count between 0 and 19);

comment on column public.timezone_change_requests.required_reviewer_count is
  'Immutable count of other accepted participants when the request was created.';

create or replace view public.timezone_change_request_status
with (security_invoker = true)
as
select
  request.id,
  request.contest_id,
  request.user_id,
  request.from_timezone,
  request.to_timezone,
  request.requested_at,
  request.required_reviewer_count::integer as reviewer_count,
  votes.approval_count,
  votes.rejection_count,
  case
    when votes.rejection_count > 0
      then 'rejected'::public.timezone_change_state
    when request.required_reviewer_count > 0
         and votes.approval_count = request.required_reviewer_count
      then 'approved'::public.timezone_change_state
    else 'pending'::public.timezone_change_state
  end as state
from public.timezone_change_requests request
cross join lateral (
  select
    count(*) filter (where review.approved)::integer as approval_count,
    count(*) filter (where not review.approved)::integer as rejection_count
  from public.timezone_change_reviews review
  where review.request_id = request.id
    and review.reviewer_user_id <> request.user_id
) votes;

comment on view public.timezone_change_request_status is
  'Unanimous consent state derived from retained votes and the request-time reviewer snapshot.';

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
  v_uid                     uuid := (select auth.uid());
  v_participant_status      public.contest_participant_status;
  v_initial_timezone        text;
  v_from_timezone           text;
  v_contest_status          public.contest_status;
  v_ends_at                 timestamptz;
  v_existing_id             uuid;
  v_existing_timezone       text;
  v_required_reviewer_count smallint;
  v_request_id              uuid;
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

  -- The eligibility read is the denominator's linearization point. Do not lock
  -- every other participant after locking the requester: two participants
  -- requesting at once would otherwise each wait on the other's row.
  select count(*)::smallint
    into v_required_reviewer_count
  from public.contest_participants reviewer
  where reviewer.contest_id = p_contest_id
    and reviewer.status = 'accepted'
    and reviewer.user_id <> v_uid;

  if v_required_reviewer_count = 0 then
    raise exception 'a timezone change requires at least one other accepted participant'
      using errcode = 'restrict_violation';
  end if;

  insert into public.timezone_change_requests (
    contest_id,
    user_id,
    from_timezone,
    to_timezone,
    required_reviewer_count
  )
  values (
    p_contest_id,
    v_uid,
    v_from_timezone,
    p_timezone,
    v_required_reviewer_count
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

comment on function public.request_timezone_change(uuid, text) is
  'Creates one request with an immutable reviewer snapshot; identical pending retries are idempotent.';

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
  v_starts_at           timestamptz;
  v_ends_at             timestamptz;
  v_existing_vote       boolean;
  v_approval_count      integer;
  v_effective_at        timestamptz;
begin
  if v_uid is null then
    raise exception 'sign in before reviewing a timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  if p_request_id is null or p_approved is null then
    raise exception 'request id and review decision are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select request.contest_id, request.user_id
    into v_identity
  from public.timezone_change_requests request
  where request.id = p_request_id;

  if v_identity.contest_id is null then
    raise exception 'timezone request not found'
      using errcode = 'insufficient_privilege';
  end if;

  select participant.status,
         contest.status,
         contest.starts_at,
         contest.ends_at
    into v_requester_status,
         v_contest_status,
         v_starts_at,
         v_ends_at
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

  if v_request.user_id = v_uid then
    raise exception 'a participant cannot review their own timezone change'
      using errcode = 'insufficient_privilege';
  end if;

  -- Same-decision retries remain idempotent even if the contest has since
  -- ended or finalized.
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

  select count(*) filter (where approval.approved)::integer
    into v_approval_count
  from public.timezone_change_reviews approval
  where approval.request_id = p_request_id
    and approval.reviewer_user_id <> v_request.user_id;

  if v_request.required_reviewer_count > 0
     and v_approval_count = v_request.required_reviewer_count
  then
    -- Use one shared-precision instant for both validation and persistence.
    -- If truncation puts it on either boundary, the vote is rolled back with
    -- the rejected application rather than creating an unscoreable epoch.
    v_effective_at := date_trunc('milliseconds', clock_timestamp());

    if v_effective_at <= v_starts_at or v_effective_at >= v_ends_at then
      raise exception
        'timezone epoch % must be strictly inside contest window (%, %)',
        v_effective_at, v_starts_at, v_ends_at
        using errcode = 'restrict_violation';
    end if;

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
      v_effective_at
    )
    on conflict (request_id) do nothing;
  end if;
end;
$$;

comment on function public.review_timezone_change(uuid, boolean) is
  'Records one retained vote and applies unanimous consent at a strictly in-window epoch.';

create or replace function app.assert_timezone_event_within_contest_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_starts_at timestamptz;
  v_ends_at   timestamptz;
begin
  select contest.starts_at, contest.ends_at
    into v_starts_at, v_ends_at
  from public.contests contest
  where contest.id = new.contest_id;

  if v_starts_at is null then
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if new.effective_at <= v_starts_at or new.effective_at >= v_ends_at then
    raise exception
      'timezone epoch % must be strictly inside contest window (%, %)',
      new.effective_at, v_starts_at, v_ends_at
      using errcode = 'check_violation';
  end if;

  if new.effective_at <> date_trunc('milliseconds', new.effective_at) then
    raise exception 'timezone epoch % must use millisecond precision',
      new.effective_at
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger timezone_change_applied_events_assert_window
  before insert or update on public.timezone_change_applied_events
  for each row
  execute function app.assert_timezone_event_within_contest_window();

-- CREATE TRIGGER's table lock is retained until this migration commits, so no
-- legacy privileged writer can insert between this audit and enforcement.
do $$
declare
  v_invalid_count bigint;
begin
  select count(*)
    into v_invalid_count
  from public.timezone_change_applied_events applied
  join public.contests contest on contest.id = applied.contest_id
  where applied.effective_at <= contest.starts_at
     or applied.effective_at >= contest.ends_at
     or applied.effective_at <>
        date_trunc('milliseconds', applied.effective_at);

  if v_invalid_count > 0 then
    raise exception
      'cannot enforce timezone epoch invariant: % existing event(s) are outside the contest window or use sub-millisecond precision',
      v_invalid_count
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_timezone_event_within_contest_window() is
  'Rejects timezone epochs on or outside their contest boundaries.';

-- ===========================================================================
-- SECTION 2 — Quarantine review durability and serialization
-- ===========================================================================

-- As above, remove the deletion cascade before taking the immutable snapshot.
alter table public.evidence_quarantine_reviews
  drop constraint if exists evidence_quarantine_reviews_reviewer_id_fkey;

comment on column public.evidence_quarantine_reviews.reviewer_id is
  'Pseudonymous historical reviewer identity retained after account deletion.';

alter table public.evidence_quarantines
  add column required_reviewer_count smallint;

create or replace function app.prepare_evidence_quarantine()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_snapshot public.metric_snapshots;
begin
  select * into v_snapshot
  from public.metric_snapshots
  where id = new.snapshot_id;

  if v_snapshot.id is null then
    raise exception 'snapshot % does not exist', new.snapshot_id
      using errcode = 'foreign_key_violation';
  end if;

  if not v_snapshot.is_admissible then
    raise exception 'only admissible evidence can require retroactive review'
      using errcode = 'invalid_parameter_value';
  end if;

  new.contest_id   := v_snapshot.contest_id;
  new.user_id      := v_snapshot.user_id;
  new.metric       := v_snapshot.metric;
  new.bucket_start := v_snapshot.bucket_start;
  new.reporting_lag_ms := greatest(
    0,
    floor(extract(epoch from (
      v_snapshot.recorded_at - (v_snapshot.bucket_start + interval '1 hour')
    )) * 1000)::bigint
  );

  if new.reporting_lag_ms < new.threshold_ms then
    raise exception
      'snapshot reporting lag % ms does not meet quarantine threshold % ms',
      new.reporting_lag_ms, new.threshold_ms
      using errcode = 'invalid_parameter_value';
  end if;

  -- This read is the immutable denominator's linearization point. Retained
  -- votes and the snapshot make participant-row locks unnecessary.
  select count(*)::smallint
    into new.required_reviewer_count
  from public.contest_participants reviewer
  where reviewer.contest_id = new.contest_id
    and reviewer.status = 'accepted'
    and reviewer.user_id <> new.user_id;

  return new;
end;
$$;

comment on function app.prepare_evidence_quarantine() is
  'Copies snapshot identity, derives lag, and snapshots the eligible reviewer count.';

alter table public.evidence_quarantines
  disable trigger evidence_quarantines_forbid_update;

update public.evidence_quarantines quarantine
set required_reviewer_count = (
  select count(*)::smallint
  from public.contest_participants participant
  where participant.contest_id = quarantine.contest_id
    and participant.status = 'accepted'
    and participant.user_id <> quarantine.user_id
);

alter table public.evidence_quarantines
  enable trigger evidence_quarantines_forbid_update;

alter table public.evidence_quarantines
  alter column required_reviewer_count set not null,
  add constraint evidence_quarantines_reviewer_count_range
    check (required_reviewer_count between 0 and 19);

comment on column public.evidence_quarantines.required_reviewer_count is
  'Immutable count of other accepted participants when quarantine was created.';

create or replace view public.evidence_quarantine_status
with (security_invoker = true)
as
select
  q.id,
  q.snapshot_id,
  q.contest_id,
  q.user_id,
  q.metric,
  q.bucket_start,
  q.rule_version,
  q.signal_key,
  q.threshold_ms,
  q.reporting_lag_ms,
  q.details,
  q.created_at,
  q.required_reviewer_count::integer as reviewer_count,
  (q.required_reviewer_count / 2 + 1)::integer as approvals_required,
  votes.approval_count,
  votes.rejection_count,
  case
    when q.required_reviewer_count = 0
      then 'pending'::public.evidence_quarantine_state
    when votes.approval_count >= (q.required_reviewer_count / 2 + 1)
      then 'approved'::public.evidence_quarantine_state
    when votes.rejection_count >
         q.required_reviewer_count - (q.required_reviewer_count / 2 + 1)
      then 'rejected'::public.evidence_quarantine_state
    else 'pending'::public.evidence_quarantine_state
  end as state
from public.evidence_quarantines q
cross join lateral (
  select
    count(*) filter (where review.approved)::integer as approval_count,
    count(*) filter (where not review.approved)::integer as rejection_count
  from public.evidence_quarantine_reviews review
  where review.quarantine_id = q.id
    and review.reviewer_id <> q.user_id
) votes;

comment on view public.evidence_quarantine_status is
  'Review state derived from retained votes and the quarantine-time reviewer snapshot.';

create or replace function public.review_evidence_quarantine(
  p_quarantine_id uuid,
  p_approved      boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_record   record;
  v_existing boolean;
begin
  if v_uid is null then
    raise exception 'sign in before reviewing evidence'
      using errcode = 'insufficient_privilege';
  end if;

  if p_quarantine_id is null or p_approved is null then
    raise exception 'quarantine id and review decision are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The quarantine row serializes concurrent retries from the same reviewer.
  select q.user_id, q.contest_id, c.status
    into v_record
  from public.evidence_quarantines q
  join public.contests c on c.id = q.contest_id
  where q.id = p_quarantine_id
  for update of q;

  if v_record.contest_id is null then
    raise exception 'quarantine not found'
      using errcode = 'insufficient_privilege';
  end if;

  if v_record.user_id = v_uid then
    raise exception 'a participant cannot review their own evidence'
      using errcode = 'insufficient_privilege';
  end if;

  select review.approved
    into v_existing
  from public.evidence_quarantine_reviews review
  where review.quarantine_id = p_quarantine_id
    and review.reviewer_id = v_uid;

  if found then
    if v_existing = p_approved then
      return;
    end if;

    raise exception 'a quarantine review cannot be changed'
      using errcode = 'restrict_violation';
  end if;

  if v_record.status <> 'active' then
    raise exception 'only an active contest may review evidence'
      using errcode = 'restrict_violation';
  end if;

  if not exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = v_record.contest_id
      and participant.user_id = v_uid
      and participant.status = 'accepted'
  ) then
    raise exception 'only another accepted participant may review this evidence'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.evidence_quarantine_reviews (
    quarantine_id, reviewer_id, approved
  )
  values (p_quarantine_id, v_uid, p_approved);
end;
$$;

comment on function public.review_evidence_quarantine(uuid, boolean) is
  'Serializes and records one retained vote by another accepted participant.';

-- ===========================================================================
-- SECTION 3 — Geofence history visibility and lookup
-- ===========================================================================

create index geofence_location_observations_user_contest_time_idx
  on public.geofence_location_observations (
    user_id, contest_id, observed_at
  );

create or replace function app.is_invited_or_accepted_contest_participant(
  p_contest_id uuid,
  p_user_id    uuid
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
    where participant.contest_id = p_contest_id
      and participant.user_id = p_user_id
      and participant.status in ('invited', 'accepted')
  );
$$;

drop policy contest_geofences_select_roster
  on public.contest_geofences;

create policy contest_geofences_select_invited_or_accepted
  on public.contest_geofences
  for select to authenticated
  using (
    app.is_invited_or_accepted_contest_participant(
      contest_id, (select auth.uid())
    )
  );

comment on function app.is_invited_or_accepted_contest_participant(uuid, uuid) is
  'True only while a user is invited to or accepted into the contest.';

-- ===========================================================================
-- SECTION 4 — Explicit service-role least privilege
-- ===========================================================================

revoke all on public.timezone_change_requests,
              public.timezone_change_reviews,
              public.timezone_change_applied_events,
              public.timezone_change_request_status
  from service_role;

grant select on public.timezone_change_requests,
                public.timezone_change_reviews,
                public.timezone_change_applied_events,
                public.timezone_change_request_status
  to service_role;

revoke all on function public.request_timezone_change(uuid, text)
  from service_role;
revoke all on function public.review_timezone_change(uuid, boolean)
  from service_role;

revoke all on public.evidence_quarantines,
              public.evidence_quarantine_reviews,
              public.evidence_quarantine_status
  from service_role;

grant select on public.evidence_quarantines,
                public.evidence_quarantine_reviews,
                public.evidence_quarantine_status
  to service_role;

revoke all on function public.review_evidence_quarantine(uuid, boolean)
  from service_role;

revoke all on public.contest_geofences,
              public.geofence_checkins,
              public.geofence_location_observations,
              public.contest_checkin_integrity,
              public.contest_location_observations
  from service_role;

grant select, insert on public.contest_geofences to service_role;
grant select on public.geofence_checkins,
                public.geofence_location_observations,
                public.contest_checkin_integrity,
                public.contest_location_observations
  to service_role;

revoke all on function
  app.assert_timezone_event_within_contest_window()
  from public, anon, authenticated, service_role;

revoke all on function
  app.is_invited_or_accepted_contest_participant(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  app.is_invited_or_accepted_contest_participant(uuid, uuid)
  to authenticated;

commit;
