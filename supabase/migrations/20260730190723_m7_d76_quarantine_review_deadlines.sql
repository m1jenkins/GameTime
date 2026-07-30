-- M7 / D76 -- bounded peer review, adjudication escalation, and fail-closed
-- review timeout.
--
-- A quarantine never changes evidence admissibility. This migration adds the
-- independent clocks and append-only decisions that determine whether the
-- already-frozen assessment may cross the existing first-result boundary.
-- Peer silence and adjudicator silence both fail closed; neither is approval.
--
-- Operator identity, assignment, case notes, queues, alerts, staffing, and
-- runbooks remain the next review-gated operated-adjudicator slice. The only
-- mutation seam added here is service_role-only and request-idempotent.

begin;

-- ===========================================================================
-- SECTION 1 -- Named server durations and immutable peer deadlines
-- ===========================================================================

create function app.evidence_quarantine_peer_review_period()
returns interval
language sql
immutable
parallel safe
set search_path = ''
as $$
  select interval '72 hours';
$$;

create function app.evidence_quarantine_adjudication_period()
returns interval
language sql
immutable
parallel safe
set search_path = ''
as $$
  select interval '7 days';
$$;

comment on function app.evidence_quarantine_peer_review_period() is
  'D76 named peer-review duration. The anchor is never earlier than ingest-grace close.';
comment on function app.evidence_quarantine_adjudication_period() is
  'D76 named operator duration, measured from the later of grace close and escalation.';

alter table public.evidence_quarantines
  add column review_deadline timestamptz;

update public.evidence_quarantines quarantine
set review_deadline =
  greatest(
    quarantine.created_at,
    contest.ends_at + app.ingest_grace_period()
  ) + app.evidence_quarantine_peer_review_period()
from public.contests contest
where contest.id = quarantine.contest_id;

alter table public.evidence_quarantines
  alter column review_deadline set not null,
  add constraint evidence_quarantines_review_deadline_finite
    check (
      pg_catalog.isfinite(created_at)
      and pg_catalog.isfinite(review_deadline)
      and review_deadline > created_at
    );

comment on column public.evidence_quarantines.review_deadline is
  'Immutable D76 peer deadline: 72 hours after the later of quarantine creation and ingest-grace close.';

create index evidence_quarantines_review_deadline_idx
  on public.evidence_quarantines (review_deadline, id);

create function app.set_evidence_quarantine_review_deadline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ends_at timestamptz;
begin
  select contest.ends_at
    into v_ends_at
  from public.metric_snapshots snapshot
  join public.contests contest on contest.id = snapshot.contest_id
  where snapshot.id = new.snapshot_id;

  if v_ends_at is null then
    raise exception 'snapshot % does not belong to a contest', new.snapshot_id
      using errcode = 'foreign_key_violation';
  end if;

  new.review_deadline :=
    greatest(
      new.created_at,
      v_ends_at + app.ingest_grace_period()
    ) + app.evidence_quarantine_peer_review_period();

  return new;
end;
$$;

-- This trigger derives the deadline from snapshot/contest facts directly, so
-- it does not depend on ordering relative to evidence_quarantines_prepare.
create trigger evidence_quarantines_set_review_deadline
  before insert on public.evidence_quarantines
  for each row execute function app.set_evidence_quarantine_review_deadline();

-- ===========================================================================
-- SECTION 2 -- Private append-only adjudication history
-- ===========================================================================

create type app.evidence_quarantine_escalation_reason as enum (
  'early_rejection',
  'peer_review_timeout'
);

create type app.evidence_quarantine_adjudication_resolution as enum (
  'cleared',
  'review_timeout',
  'contest_inconclusive'
);

create table app.evidence_quarantine_adjudications (
  id                     uuid primary key default gen_random_uuid(),
  quarantine_id          uuid not null
    references public.evidence_quarantines (id) on delete restrict,
  contest_id             uuid not null,
  subject_user_id        uuid not null,
  escalation_reason      app.evidence_quarantine_escalation_reason not null,
  escalated_at           timestamptz not null,
  adjudication_deadline  timestamptz not null,
  created_at             timestamptz not null default clock_timestamp(),

  constraint evidence_quarantine_adjudications_quarantine_unique
    unique (quarantine_id),
  constraint evidence_quarantine_adjudications_identity_unique
    unique (id, quarantine_id, contest_id),
  constraint evidence_quarantine_adjudications_subject_fkey
    foreign key (contest_id, subject_user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint evidence_quarantine_adjudications_times_finite
    check (
      pg_catalog.isfinite(escalated_at)
      and pg_catalog.isfinite(adjudication_deadline)
      and pg_catalog.isfinite(created_at)
      and adjudication_deadline > escalated_at
    )
);

comment on table app.evidence_quarantine_adjudications is
  'One immutable D76 escalation per quarantine. This is core state, not an operated assignment queue.';
comment on column app.evidence_quarantine_adjudications.adjudication_deadline is
  'Seven days after the later of ingest-grace close and escalation.';

create index evidence_quarantine_adjudications_due_idx
  on app.evidence_quarantine_adjudications (
    adjudication_deadline,
    contest_id,
    id
  );

create table app.evidence_quarantine_adjudication_events (
  id               uuid primary key default gen_random_uuid(),
  adjudication_id  uuid not null,
  quarantine_id    uuid not null,
  contest_id       uuid not null,
  resolution       app.evidence_quarantine_adjudication_resolution not null,
  request_id       uuid,
  recorded_at      timestamptz not null default clock_timestamp(),

  constraint evidence_quarantine_adjudication_events_adjudication_fkey
    foreign key (adjudication_id, quarantine_id, contest_id)
    references app.evidence_quarantine_adjudications (
      id,
      quarantine_id,
      contest_id
    )
    on delete restrict,
  constraint evidence_quarantine_adjudication_events_terminal_unique
    unique (adjudication_id),
  constraint evidence_quarantine_adjudication_events_request_unique
    unique (request_id),
  constraint evidence_quarantine_adjudication_events_request_shape
    check (
      (resolution = 'cleared' and request_id is not null)
      or (resolution <> 'cleared' and request_id is null)
    ),
  constraint evidence_quarantine_adjudication_events_recorded_finite
    check (pg_catalog.isfinite(recorded_at))
);

comment on table app.evidence_quarantine_adjudication_events is
  'Append-only terminal D76 decisions. Same-request clearance retries return the first event; timers have no caller request UUID.';
comment on column app.evidence_quarantine_adjudication_events.resolution is
  'cleared explicitly opens the gate; review_timeout fails one due gate closed; contest_inconclusive closes sibling gates after another timeout.';

create index evidence_quarantine_adjudication_events_contest_idx
  on app.evidence_quarantine_adjudication_events (
    contest_id,
    recorded_at,
    id
  );

create trigger evidence_quarantine_adjudications_forbid_mutation
  before update or delete or truncate
  on app.evidence_quarantine_adjudications
  for each statement execute function app.forbid_mutation();

create trigger evidence_quarantine_adjudication_events_forbid_mutation
  before update or delete or truncate
  on app.evidence_quarantine_adjudication_events
  for each statement execute function app.forbid_mutation();

alter table app.evidence_quarantine_adjudications enable row level security;
alter table app.evidence_quarantine_adjudication_events enable row level security;

revoke all on table app.evidence_quarantine_adjudications,
                    app.evidence_quarantine_adjudication_events
  from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 3 -- Computed peer/gate state without rewriting votes
-- ===========================================================================

create or replace view public.evidence_quarantine_status
with (security_invoker = true)
as
select
  quarantine.id,
  quarantine.snapshot_id,
  quarantine.contest_id,
  quarantine.user_id,
  quarantine.metric,
  quarantine.bucket_start,
  quarantine.rule_version,
  quarantine.signal_key,
  quarantine.threshold_ms,
  quarantine.reporting_lag_ms,
  quarantine.details,
  quarantine.created_at,
  quarantine.required_reviewer_count::integer as reviewer_count,
  (quarantine.required_reviewer_count / 2 + 1)::integer
    as approvals_required,
  votes.approval_count,
  votes.rejection_count,
  case
    when terminal.resolution = 'cleared'
      then 'approved'::public.evidence_quarantine_state
    else peer.state
  end as state,
  quarantine.review_deadline,
  peer.state as peer_state,
  adjudication.id as adjudication_id,
  adjudication.escalation_reason::text as escalation_reason,
  adjudication.escalated_at,
  adjudication.adjudication_deadline,
  terminal.resolution::text as adjudication_resolution,
  terminal.recorded_at as adjudication_resolved_at
from public.evidence_quarantines quarantine
cross join lateral (
  select
    count(*) filter (where review.approved)::integer as approval_count,
    count(*) filter (where not review.approved)::integer as rejection_count
  from public.evidence_quarantine_reviews review
  where review.quarantine_id = quarantine.id
    and review.reviewer_id <> quarantine.user_id
) votes
cross join lateral (
  select case
    when quarantine.required_reviewer_count = 0
      then 'pending'::public.evidence_quarantine_state
    when votes.approval_count >=
         (quarantine.required_reviewer_count / 2 + 1)
      then 'approved'::public.evidence_quarantine_state
    when votes.rejection_count >
         quarantine.required_reviewer_count -
           (quarantine.required_reviewer_count / 2 + 1)
      then 'rejected'::public.evidence_quarantine_state
    else 'pending'::public.evidence_quarantine_state
  end as state
) peer
left join app.evidence_quarantine_adjudications adjudication
  on adjudication.quarantine_id = quarantine.id
left join app.evidence_quarantine_adjudication_events terminal
  on terminal.adjudication_id = adjudication.id;

comment on view public.evidence_quarantine_status is
  'D76 gate state. state is effective for trusted finalization; peer_state always preserves the immutable vote result and clearance remains explicit.';

-- ===========================================================================
-- SECTION 4 -- Idempotent escalation and payload-free transition intents
-- ===========================================================================

create function app.ensure_evidence_quarantine_adjudication(
  p_quarantine_id      uuid,
  p_escalation_reason  app.evidence_quarantine_escalation_reason,
  p_escalated_at       timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quarantine     public.evidence_quarantines;
  v_contest        public.contests;
  v_peer_state     public.evidence_quarantine_state;
  v_existing       app.evidence_quarantine_adjudications;
  v_adjudication_id uuid;
begin
  if p_quarantine_id is null
     or p_escalation_reason is null
     or p_escalated_at is null
     or not pg_catalog.isfinite(p_escalated_at)
  then
    raise exception 'quarantine, escalation reason, and finite time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select quarantine.*
    into v_quarantine
  from public.evidence_quarantines quarantine
  where quarantine.id = p_quarantine_id
  for update;

  if v_quarantine.id is null then
    raise exception 'quarantine not found'
      using errcode = 'foreign_key_violation';
  end if;

  select adjudication.*
    into v_existing
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.quarantine_id = p_quarantine_id;

  if found then
    return v_existing.id;
  end if;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = v_quarantine.contest_id;

  if v_contest.id is null then
    raise exception 'quarantine contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  if v_contest.status <> 'active' then
    raise exception 'only an active contest may escalate evidence review'
      using errcode = 'restrict_violation';
  end if;

  if p_escalated_at < v_quarantine.created_at then
    raise exception 'escalation cannot predate the quarantine'
      using errcode = 'invalid_parameter_value';
  end if;

  select status.peer_state
    into v_peer_state
  from public.evidence_quarantine_status status
  where status.id = p_quarantine_id;

  if p_escalation_reason = 'early_rejection' then
    if v_peer_state <> 'rejected' then
      raise exception 'early escalation requires a rejected peer review'
        using errcode = 'restrict_violation';
    end if;
  elsif p_escalation_reason = 'peer_review_timeout' then
    if v_peer_state <> 'pending'
       or p_escalated_at < v_quarantine.review_deadline
    then
      raise exception 'peer-timeout escalation is not due'
        using errcode = 'restrict_violation';
    end if;
  end if;

  insert into app.evidence_quarantine_adjudications (
    quarantine_id,
    contest_id,
    subject_user_id,
    escalation_reason,
    escalated_at,
    adjudication_deadline
  )
  values (
    v_quarantine.id,
    v_quarantine.contest_id,
    v_quarantine.user_id,
    p_escalation_reason,
    p_escalated_at,
    greatest(
      v_contest.ends_at + app.ingest_grace_period(),
      p_escalated_at
    ) + app.evidence_quarantine_adjudication_period()
  )
  on conflict on constraint
    evidence_quarantine_adjudications_quarantine_unique
  do nothing
  returning id into v_adjudication_id;

  if v_adjudication_id is not null then
    return v_adjudication_id;
  end if;

  select adjudication.id
    into v_adjudication_id
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.quarantine_id = p_quarantine_id;

  return v_adjudication_id;
end;
$$;

comment on function app.ensure_evidence_quarantine_adjudication(
  uuid,
  app.evidence_quarantine_escalation_reason,
  timestamptz
) is
  'Serialized idempotent D76 escalation. Rejection is immediate; pending review escalates at its inclusive deadline.';

create function app.emit_quarantine_adjudication_requested_intents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  for v_recipient in
    select participant.user_id
    from public.contest_participants participant
    where participant.contest_id = new.contest_id
      and participant.status = 'accepted'
    order by participant.user_id
  loop
    perform app.emit_notification_intent(
      v_recipient,
      'quarantine_review_escalated'::public.notification_event_type,
      new.quarantine_id
    );
  end loop;

  return new;
end;
$$;

create trigger evidence_quarantine_adjudications_emit_intents
  after insert on app.evidence_quarantine_adjudications
  for each row
  execute function app.emit_quarantine_adjudication_requested_intents();

create function app.emit_quarantine_adjudication_resolution_intents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  for v_recipient in
    select participant.user_id
    from public.contest_participants participant
    where participant.contest_id = new.contest_id
      and participant.status = 'accepted'
    order by participant.user_id
  loop
    perform app.emit_notification_intent(
      v_recipient,
      'quarantine_review_resolved'::public.notification_event_type,
      new.quarantine_id
    );
  end loop;

  return new;
end;
$$;

create trigger evidence_quarantine_adjudication_events_emit_intents
  after insert on app.evidence_quarantine_adjudication_events
  for each row
  execute function app.emit_quarantine_adjudication_resolution_intents();

create function app.escalate_rejected_evidence_quarantine()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.evidence_quarantine_status status
    where status.id = new.quarantine_id
      and status.peer_state = 'rejected'
  ) then
    perform app.ensure_evidence_quarantine_adjudication(
      new.quarantine_id,
      'early_rejection',
      new.created_at
    );
  end if;

  return new;
end;
$$;

create trigger evidence_quarantine_reviews_escalate_rejection
  after insert on public.evidence_quarantine_reviews
  for each row execute function app.escalate_rejected_evidence_quarantine();

-- ===========================================================================
-- SECTION 5 -- Review-window enforcement and D77-bounded disclosure
-- ===========================================================================

create or replace function app.serialize_evidence_quarantine_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review_deadline timestamptz;
begin
  select quarantine.review_deadline
    into v_review_deadline
  from public.evidence_quarantines quarantine
  where quarantine.id = new.quarantine_id
  for update;

  if not found then
    raise exception 'quarantine % does not exist', new.quarantine_id
      using errcode = 'foreign_key_violation';
  end if;

  if clock_timestamp() >= v_review_deadline
     or exists (
       select 1
       from app.evidence_quarantine_adjudications adjudication
       where adjudication.quarantine_id = new.quarantine_id
     )
  then
    raise exception 'quarantine peer-review window is closed'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.serialize_evidence_quarantine_review() is
  'Locks the parent and rejects every new peer vote at/after its D76 deadline or after escalation.';

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
  v_uid uuid;
begin
  v_uid := app.require_active_caller();

  if p_quarantine_id is null or p_approved is null then
    perform app.review_evidence_quarantine_unchecked(
      p_quarantine_id,
      p_approved
    );
    return;
  end if;

  perform 1
  from public.evidence_quarantines quarantine
  where quarantine.id = p_quarantine_id
  for update;

  if not found then
    perform app.review_evidence_quarantine_unchecked(
      p_quarantine_id,
      p_approved
    );
    return;
  end if;

  if exists (
    select 1
    from public.evidence_quarantine_reviews own_review
    where own_review.quarantine_id = p_quarantine_id
      and own_review.reviewer_id = v_uid
  ) then
    perform app.review_evidence_quarantine_unchecked(
      p_quarantine_id,
      p_approved
    );
    return;
  end if;

  if not exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest
      on contest.id = quarantine.contest_id
     and contest.status = 'active'
    join public.contest_participants reviewer
      on reviewer.contest_id = quarantine.contest_id
     and reviewer.user_id = v_uid
     and reviewer.status = 'accepted'
    where quarantine.id = p_quarantine_id
      and quarantine.user_id <> v_uid
  ) then
    perform app.review_evidence_quarantine_unchecked(
      p_quarantine_id,
      p_approved
    );
    return;
  end if;

  if not exists (
    select 1
    from public.evidence_quarantine_status status
    where status.id = p_quarantine_id
      and status.peer_state = 'pending'
      and clock_timestamp() < status.review_deadline
      and status.adjudication_id is null
  ) then
    raise exception 'quarantine review is no longer pending'
      using errcode = 'restrict_violation';
  end if;

  perform app.review_evidence_quarantine_unchecked(
    p_quarantine_id,
    p_approved
  );
end;
$$;

comment on function public.review_evidence_quarantine(uuid, boolean) is
  'Records one immutable exact-contest vote strictly before the peer deadline; identical same-decision retries remain idempotent.';

create or replace function public.list_my_evidence_quarantines(
  p_contest_id uuid
)
returns table (
  quarantine_id       uuid,
  snapshot_id         uuid,
  contest_id          uuid,
  participant_id      uuid,
  metric              public.contest_metric,
  bucket_start        timestamptz,
  rule_version        text,
  signal_key          text,
  threshold_ms        bigint,
  reporting_lag_ms    bigint,
  details             jsonb,
  created_at          timestamptz,
  reviewer_count      integer,
  approvals_required  integer,
  approval_count      integer,
  rejection_count     integer,
  state               public.evidence_quarantine_state,
  phase               text
)
language sql
stable
security definer
set search_path = ''
as $$
  with caller as (
    select (select auth.uid()) as user_id
  )
  select
    status.id,
    status.snapshot_id,
    status.contest_id,
    status.user_id,
    status.metric,
    status.bucket_start,
    status.rule_version,
    status.signal_key,
    status.threshold_ms,
    status.reporting_lag_ms,
    status.details,
    status.created_at,
    status.reviewer_count,
    status.approvals_required,
    status.approval_count,
    status.rejection_count,
    status.peer_state,
    case
      when contest.status = 'finalized' then 'final'
      when now() < contest.ends_at then 'live'
      when now() < contest.ends_at + app.ingest_grace_period()
        then 'awaiting_ingest'
      else 'under_review'
    end
  from public.evidence_quarantine_status status
  join public.contests contest
    on contest.id = status.contest_id
  cross join caller
  where status.contest_id = p_contest_id
    and status.user_id = caller.user_id
    and app.is_active_actor(caller.user_id)
  order by status.created_at, status.id;
$$;

comment on function public.list_my_evidence_quarantines(uuid) is
  'D77 subject surface. Preserves peer_state; explicit D76 clearance is disclosed by get_evidence_quarantine_resolution_v1.';

create or replace function public.list_contest_quarantine_reviews(
  p_contest_id uuid
)
returns table (
  quarantine_id       uuid,
  contest_id          uuid,
  participant_id      uuid,
  metric              public.contest_metric,
  bucket_start        timestamptz,
  value               numeric,
  provenance          public.metric_provenance,
  recorded_at         timestamptz,
  reporting_lag_ms    bigint,
  rule_code           text,
  rule_version        text,
  threshold_ms        bigint,
  phase               text,
  revision_count      integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with caller as (
    select (select auth.uid()) as user_id
  )
  select
    quarantine.id,
    quarantine.contest_id,
    quarantine.user_id,
    quarantine.metric,
    quarantine.bucket_start,
    flagged.value,
    flagged.provenance,
    flagged.recorded_at,
    quarantine.reporting_lag_ms,
    'retroactive_evidence_quarantine'::text,
    quarantine.rule_version,
    quarantine.threshold_ms,
    case
      when now() < contest.ends_at then 'live'
      when now() < contest.ends_at + app.ingest_grace_period()
        then 'awaiting_ingest'
      else 'under_review'
    end,
    revisions.revision_count
  from public.evidence_quarantines quarantine
  join public.evidence_quarantine_status status
    on status.id = quarantine.id
   and status.peer_state = 'pending'
   and status.adjudication_id is null
   and clock_timestamp() < status.review_deadline
  join public.metric_snapshots flagged
    on flagged.id = quarantine.snapshot_id
   and flagged.contest_id = quarantine.contest_id
   and flagged.user_id = quarantine.user_id
  join public.contests contest
    on contest.id = quarantine.contest_id
   and contest.status = 'active'
  join public.contest_participants reviewer
    on reviewer.contest_id = quarantine.contest_id
   and reviewer.status = 'accepted'
  cross join caller
  cross join lateral (
    select count(*)::integer as revision_count
    from public.metric_snapshots revision
    where revision.contest_id = quarantine.contest_id
      and revision.user_id = quarantine.user_id
      and revision.metric = quarantine.metric
      and revision.bucket_start = quarantine.bucket_start
      and revision.provenance = flagged.provenance
  ) revisions
  where quarantine.contest_id = p_contest_id
    and reviewer.user_id = caller.user_id
    and quarantine.user_id <> caller.user_id
    and app.is_active_actor(caller.user_id)
    and not exists (
      select 1
      from public.evidence_quarantine_reviews own_review
      where own_review.quarantine_id = quarantine.id
        and own_review.reviewer_id = caller.user_id
    )
  order by quarantine.created_at, quarantine.id;
$$;

comment on function public.list_contest_quarantine_reviews(uuid) is
  'D77 reviewer inbox: redacted exact-contest claims only while peer review is pending and before escalation.';

create or replace function public.get_quarantine_revision_history(
  p_quarantine_id uuid
)
returns table (
  quarantine_id           uuid,
  contest_id              uuid,
  participant_id          uuid,
  metric                  public.contest_metric,
  bucket_start            timestamptz,
  rule_code               text,
  rule_version            text,
  threshold_ms            bigint,
  phase                   text,
  revision_number         integer,
  value                   numeric,
  provenance              public.metric_provenance,
  recorded_at             timestamptz,
  reporting_lag_ms        bigint,
  is_quarantined_revision boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with caller as (
    select (select auth.uid()) as user_id
  )
  select
    quarantine.id,
    quarantine.contest_id,
    quarantine.user_id,
    quarantine.metric,
    quarantine.bucket_start,
    'retroactive_evidence_quarantine'::text,
    quarantine.rule_version,
    quarantine.threshold_ms,
    case
      when now() < contest.ends_at then 'live'
      when now() < contest.ends_at + app.ingest_grace_period()
        then 'awaiting_ingest'
      else 'under_review'
    end,
    (row_number() over (
      partition by quarantine.id
      order by revision.recorded_at, revision.id
    ))::integer,
    revision.value,
    revision.provenance,
    revision.recorded_at,
    greatest(
      0,
      floor(extract(epoch from (
        revision.recorded_at -
          (revision.bucket_start + interval '1 hour')
      )) * 1000)::bigint
    ),
    revision.id = quarantine.snapshot_id
  from public.evidence_quarantines quarantine
  join public.evidence_quarantine_status status
    on status.id = quarantine.id
   and status.peer_state = 'pending'
   and status.adjudication_id is null
   and clock_timestamp() < status.review_deadline
  join public.metric_snapshots flagged
    on flagged.id = quarantine.snapshot_id
   and flagged.contest_id = quarantine.contest_id
   and flagged.user_id = quarantine.user_id
  join public.metric_snapshots revision
    on revision.contest_id = quarantine.contest_id
   and revision.user_id = quarantine.user_id
   and revision.metric = quarantine.metric
   and revision.bucket_start = quarantine.bucket_start
   and revision.provenance = flagged.provenance
  join public.contests contest
    on contest.id = quarantine.contest_id
   and contest.status = 'active'
  join public.contest_participants reviewer
    on reviewer.contest_id = quarantine.contest_id
   and reviewer.status = 'accepted'
  cross join caller
  where quarantine.id = p_quarantine_id
    and reviewer.user_id = caller.user_id
    and quarantine.user_id <> caller.user_id
    and app.is_active_actor(caller.user_id)
    and not exists (
      select 1
      from public.evidence_quarantine_reviews own_review
      where own_review.quarantine_id = quarantine.id
        and own_review.reviewer_id = caller.user_id
    )
  order by revision.recorded_at, revision.id;
$$;

comment on function public.get_quarantine_revision_history(uuid) is
  'D77 reviewer evidence: redacted history only while that caller can still act before the D76 deadline.';

create function public.get_evidence_quarantine_resolution_v1(
  p_quarantine_id uuid
)
returns table (
  quarantine_id          uuid,
  contest_id             uuid,
  review_deadline        timestamptz,
  peer_state             public.evidence_quarantine_state,
  gate_state             text,
  escalated_at           timestamptz,
  adjudication_deadline  timestamptz,
  resolved_at            timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  v_uid := app.require_active_caller();

  return query
  select
    status.id,
    status.contest_id,
    status.review_deadline,
    status.peer_state,
    case
      when status.adjudication_resolution = 'cleared'
        then 'cleared'
      when status.adjudication_resolution = 'review_timeout'
        then 'review_timeout'
      when status.adjudication_resolution = 'contest_inconclusive'
        then 'contest_inconclusive'
      when status.adjudication_id is not null
        then 'adjudication_pending'
      when status.peer_state = 'approved'
        then 'peer_approved'
      when status.peer_state = 'rejected'
        then 'peer_rejected'
      when clock_timestamp() >= status.review_deadline
        then 'peer_deadline_elapsed'
      else 'peer_pending'
    end,
    status.escalated_at,
    status.adjudication_deadline,
    status.adjudication_resolved_at
  from public.evidence_quarantine_status status
  join public.contest_participants participant
    on participant.contest_id = status.contest_id
   and participant.user_id = v_uid
   and participant.status = 'accepted'
  where status.id = p_quarantine_id;
end;
$$;

comment on function public.get_evidence_quarantine_resolution_v1(uuid) is
  'D77-bounded D76 disclosure: exact contest, peer state, generic escalation/deadline, and explicit terminal source; no evidence payload or operator note.';

-- ===========================================================================
-- SECTION 6 -- Explicit service-only, same-request clearance
-- ===========================================================================

create function app.clear_evidence_quarantine_adjudication_at(
  p_request_id     uuid,
  p_quarantine_id  uuid,
  p_recorded_at    timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing      app.evidence_quarantine_adjudication_events;
  v_adjudication  app.evidence_quarantine_adjudications;
  v_contest       public.contests;
  v_event_id      uuid;
begin
  if p_request_id is null
     or p_quarantine_id is null
     or p_recorded_at is null
     or not pg_catalog.isfinite(p_recorded_at)
  then
    raise exception 'request, quarantine, and finite resolution time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select terminal.*
    into v_existing
  from app.evidence_quarantine_adjudication_events terminal
  where terminal.request_id = p_request_id;

  if found then
    if v_existing.quarantine_id = p_quarantine_id
       and v_existing.resolution = 'cleared'
    then
      return v_existing.id;
    end if;

    raise exception 'request id already names a different adjudication action'
      using errcode = 'unique_violation';
  end if;

  select adjudication.*
    into v_adjudication
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.quarantine_id = p_quarantine_id;

  if v_adjudication.id is null then
    raise exception 'quarantine has not escalated to adjudication'
      using errcode = 'restrict_violation';
  end if;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = v_adjudication.contest_id
  for update;

  perform 1
  from public.evidence_quarantines quarantine
  where quarantine.id = p_quarantine_id
  for update;

  select adjudication.*
    into v_adjudication
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.id = v_adjudication.id
  for update;

  select terminal.*
    into v_existing
  from app.evidence_quarantine_adjudication_events terminal
  where terminal.request_id = p_request_id;

  if found then
    if v_existing.quarantine_id = p_quarantine_id
       and v_existing.resolution = 'cleared'
    then
      return v_existing.id;
    end if;

    raise exception 'request id already names a different adjudication action'
      using errcode = 'unique_violation';
  end if;

  if v_contest.status <> 'active' then
    raise exception 'contest review is already terminal'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from app.evidence_quarantine_adjudication_events terminal
    where terminal.adjudication_id = v_adjudication.id
  ) then
    raise exception 'quarantine adjudication is already terminal'
      using errcode = 'restrict_violation';
  end if;

  if p_recorded_at >= v_adjudication.adjudication_deadline then
    raise exception 'quarantine adjudication deadline has passed'
      using errcode = 'restrict_violation';
  end if;

  -- Requiring the complete assessment before clearance preserves the frozen
  -- peer-state input. Clearance can open a gate; it cannot create or substitute
  -- the assessment that final publication must use.
  if not exists (
    select 1
    from app.contest_integrity_assessments assessment
    where assessment.contest_id = v_adjudication.contest_id
  ) then
    raise exception 'a complete integrity assessment is required before clearance'
      using errcode = 'restrict_violation';
  end if;

  insert into app.evidence_quarantine_adjudication_events (
    adjudication_id,
    quarantine_id,
    contest_id,
    resolution,
    request_id,
    recorded_at
  )
  values (
    v_adjudication.id,
    v_adjudication.quarantine_id,
    v_adjudication.contest_id,
    'cleared',
    p_request_id,
    p_recorded_at
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

create function public.clear_evidence_quarantine_v1(
  p_request_id     uuid,
  p_quarantine_id  uuid
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.clear_evidence_quarantine_adjudication_at(
    p_request_id,
    p_quarantine_id,
    clock_timestamp()
  );
$$;

comment on function public.clear_evidence_quarantine_v1(uuid, uuid) is
  'service_role-only D76 clearance. Same request/quarantine retries return the first append-only event; changed payloads fail.';

-- ===========================================================================
-- SECTION 7 -- Terminal review_timeout through the frozen first-result seam
-- ===========================================================================

create or replace function app.bind_contest_result_integrity_assessment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment app.contest_integrity_assessments;
  v_outcome    jsonb;
begin
  select assessment.*
    into v_assessment
  from app.contest_integrity_assessments assessment
  where assessment.contest_id = new.contest_id
    and assessment.evidence_cutoff = new.evidence_cutoff
    and assessment.scoring_version = new.scoring_version
    and assessment.integrity_configuration_version =
      new.integrity_configuration_version;

  if v_assessment.id is null then
    raise exception 'a complete matching integrity assessment is required'
      using errcode = 'restrict_violation';
  end if;

  if app.contest_integrity_evidence_digest_v1(new.contest_id) <>
       v_assessment.evidence_digest
  then
    raise exception 'integrity assessment evidence is stale'
      using errcode = 'restrict_violation';
  end if;

  if new.kind = 'inconclusive'
     and new.reason = 'review_timeout'
  then
    if not exists (
      select 1
      from app.evidence_quarantine_adjudication_events terminal
      where terminal.contest_id = new.contest_id
        and terminal.resolution = 'review_timeout'
    ) then
      raise exception 'review_timeout requires a terminal D76 deadline event'
        using errcode = 'restrict_violation';
    end if;
  else
    v_outcome := v_assessment.assessment_document -> 'outcome';

    if v_outcome ->> 'kind' <> new.kind::text
       or v_outcome ->> 'reason' <> new.reason::text
       or (
         new.kind = 'winner'
         and (v_outcome ->> 'participant_id')::uuid is distinct from
           new.winner_participant_id
       )
       or (
         new.kind <> 'winner'
         and new.winner_participant_id is not null
       )
    then
      raise exception 'final result contradicts the canonical integrity assessment'
        using errcode = 'invalid_parameter_value';
    end if;
  end if;

  new.integrity_assessment_id := v_assessment.id;
  return new;
end;
$$;

comment on function app.bind_contest_result_integrity_assessment() is
  'Binds every result to a matching frozen assessment. review_timeout is the sole D76 fail-closed override and requires its append-only deadline event.';

create function app.finalize_contest_review_timeout_at(
  p_adjudication_id uuid,
  p_finalized_at    timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest_id             uuid;
  v_contest                public.contests;
  v_adjudication           app.evidence_quarantine_adjudications;
  v_existing_result_id     uuid;
  v_assessment             app.contest_integrity_assessments;
  v_input_digest           bytea;
  v_result_id              uuid;
  v_snapshot_id            uuid;
  v_timed_out_ids          uuid[];
begin
  if p_adjudication_id is null
     or p_finalized_at is null
     or not pg_catalog.isfinite(p_finalized_at)
  then
    raise exception 'adjudication and finite finalization time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select adjudication.contest_id
    into v_contest_id
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.id = p_adjudication_id;

  if v_contest_id is null then
    raise exception 'adjudication not found'
      using errcode = 'foreign_key_violation';
  end if;

  -- Match the existing assessment/publication lock order. A timeout cannot
  -- overtake an in-flight evidence write, assessment, clearance, or first
  -- result.
  lock table public.metric_snapshots,
             public.geofence_checkins
    in share row exclusive mode;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = v_contest_id
  for update;

  if v_contest.id is null then
    raise exception 'adjudication contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  perform 1
  from public.evidence_quarantines quarantine
  where quarantine.contest_id = v_contest_id
  order by quarantine.id
  for update;

  perform 1
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.contest_id = v_contest_id
  order by adjudication.id
  for update;

  select adjudication.*
    into v_adjudication
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.id = p_adjudication_id;

  select result.id
    into v_existing_result_id
  from public.contest_results result
  where result.contest_id = v_contest_id
    and result.version = 1;

  if v_existing_result_id is not null then
    -- A first result that committed while this timer was waiting owns the
    -- boundary. The scheduled retry is a deterministic no-op regardless of
    -- which valid immutable result won.
    return null;
  end if;

  if v_contest.status <> 'active' then
    raise exception 'only an active contest may time out review'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from app.evidence_quarantine_adjudication_events terminal
    where terminal.adjudication_id = v_adjudication.id
  ) then
    -- Clearance (or another timeout worker) may have committed while this
    -- worker waited for the contest lock. Treat that race as a no-op.
    return null;
  end if;

  if p_finalized_at < v_adjudication.adjudication_deadline then
    raise exception 'adjudication timeout is not due'
      using errcode = 'restrict_violation';
  end if;

  select assessment.*
    into v_assessment
  from app.contest_integrity_assessments assessment
  where assessment.contest_id = v_contest_id
  order by assessment.assessed_at desc, assessment.id desc
  limit 1;

  if v_assessment.id is null then
    raise exception 'a complete integrity assessment is required before timeout finality'
      using errcode = 'restrict_violation';
  end if;

  if app.contest_integrity_evidence_digest_v1(v_contest_id) <>
       v_assessment.evidence_digest
  then
    raise exception 'integrity assessment evidence is stale'
      using errcode = 'restrict_violation';
  end if;

  insert into app.evidence_quarantine_adjudication_events (
    adjudication_id,
    quarantine_id,
    contest_id,
    resolution,
    request_id,
    recorded_at
  )
  select
    adjudication.id,
    adjudication.quarantine_id,
    adjudication.contest_id,
    case
      when adjudication.adjudication_deadline <= p_finalized_at
        then 'review_timeout'
          ::app.evidence_quarantine_adjudication_resolution
      else 'contest_inconclusive'
          ::app.evidence_quarantine_adjudication_resolution
    end,
    null,
    p_finalized_at
  from app.evidence_quarantine_adjudications adjudication
  where adjudication.contest_id = v_contest_id
    and not exists (
      select 1
      from app.evidence_quarantine_adjudication_events terminal
      where terminal.adjudication_id = adjudication.id
    )
  order by adjudication.id
  on conflict on constraint
    evidence_quarantine_adjudication_events_terminal_unique
  do nothing;

  select array_agg(
           terminal.adjudication_id
           order by terminal.adjudication_id
         )
    into v_timed_out_ids
  from app.evidence_quarantine_adjudication_events terminal
  where terminal.contest_id = v_contest_id
    and terminal.resolution = 'review_timeout';

  if v_timed_out_ids is null
     or not (p_adjudication_id = any(v_timed_out_ids))
  then
    raise exception 'the due adjudication did not become review_timeout'
      using errcode = 'check_violation';
  end if;

  v_input_digest := extensions.digest(
    jsonb_build_object(
      'schema_version', 'm7-d76-review-timeout-v1',
      'contest_id', v_contest_id,
      'assessment_id', v_assessment.id,
      'assessment_digest', encode(v_assessment.assessment_digest, 'hex'),
      'result_kind', 'inconclusive',
      'result_reason', 'review_timeout',
      'timed_out_adjudication_ids', to_jsonb(v_timed_out_ids)
    )::text,
    'sha256'
  );

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
    v_contest_id,
    1,
    'inconclusive',
    'review_timeout',
    null,
    v_assessment.evidence_cutoff,
    v_assessment.scoring_version,
    v_assessment.integrity_configuration_version,
    v_input_digest,
    p_finalized_at
  )
  returning id into v_result_id;

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
    v_contest_id,
    'final',
    'final',
    p_finalized_at,
    v_assessment.scoring_version,
    v_assessment.integrity_configuration_version,
    v_assessment.evidence_cutoff,
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
    v_contest_id,
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
  from jsonb_to_recordset(
    v_assessment.assessment_document -> 'standings'
  ) as entry (
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

  update public.contests
  set status = 'finalized'
  where id = v_contest_id;

  perform app.ensure_contest_workflow_scope(v_contest_id);

  return v_result_id;
end;
$$;

comment on function app.finalize_contest_review_timeout_at(uuid, timestamptz) is
  'Internal D76 terminalizer. Uses the latest serialized frozen assessment, appends timeout audit, publishes exact assessment standings, creates no obligation, and returns null when another terminal transition wins the lock race.';

-- ===========================================================================
-- SECTION 8 -- Idempotent named deadline worker
-- ===========================================================================

create function app.process_evidence_quarantine_deadlines_at(
  p_now    timestamptz,
  p_limit  integer
)
returns table (
  quarantines_escalated  integer,
  contests_timed_out     integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quarantine    record;
  v_adjudication  record;
  v_result_id     uuid;
begin
  if p_now is null
     or not pg_catalog.isfinite(p_now)
     or p_limit is null
     or p_limit not between 1 and 1000
  then
    raise exception 'finite worker time and limit 1 to 1000 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  quarantines_escalated := 0;
  contests_timed_out := 0;

  for v_quarantine in
    select
      quarantine.id,
      status.peer_state,
      quarantine.review_deadline
    from public.evidence_quarantines quarantine
    join public.evidence_quarantine_status status
      on status.id = quarantine.id
    join public.contests contest
      on contest.id = quarantine.contest_id
     and contest.status = 'active'
    where status.adjudication_id is null
      and (
        status.peer_state = 'rejected'
        or (
          status.peer_state = 'pending'
          and quarantine.review_deadline <= p_now
        )
      )
    order by
      case when status.peer_state = 'rejected' then 0 else 1 end,
      quarantine.review_deadline,
      quarantine.id
    limit p_limit
    for update of quarantine skip locked
  loop
    perform app.ensure_evidence_quarantine_adjudication(
      v_quarantine.id,
      case
        when v_quarantine.peer_state = 'rejected'
          then 'early_rejection'
            ::app.evidence_quarantine_escalation_reason
        else 'peer_review_timeout'
            ::app.evidence_quarantine_escalation_reason
      end,
      p_now
    );
    quarantines_escalated := quarantines_escalated + 1;
  end loop;

  -- Do not pre-lock adjudication rows here. The terminalizer follows the
  -- global table -> contest -> quarantine/adjudication order and rechecks every
  -- condition after obtaining those locks. Select only the earliest due gate
  -- per contest so one sweep cannot count the same contest more than once when
  -- several quarantines share its terminal review-timeout result.
  for v_adjudication in
    with ranked_due as (
      select
        adjudication.id,
        adjudication.adjudication_deadline,
        pg_catalog.row_number() over (
          partition by adjudication.contest_id
          order by adjudication.adjudication_deadline, adjudication.id
        ) as contest_rank
      from app.evidence_quarantine_adjudications adjudication
      join public.contests contest
        on contest.id = adjudication.contest_id
       and contest.status = 'active'
      where adjudication.adjudication_deadline <= p_now
        and not exists (
          select 1
          from app.evidence_quarantine_adjudication_events terminal
          where terminal.adjudication_id = adjudication.id
        )
        and exists (
          select 1
          from app.contest_integrity_assessments assessment
          where assessment.contest_id = adjudication.contest_id
        )
    )
    select ranked_due.id
    from ranked_due
    where ranked_due.contest_rank = 1
    order by ranked_due.adjudication_deadline, ranked_due.id
    limit p_limit
  loop
    v_result_id := app.finalize_contest_review_timeout_at(
      v_adjudication.id,
      p_now
    );
    if v_result_id is not null then
      contests_timed_out := contests_timed_out + 1;
    end if;
  end loop;

  return next;
end;
$$;

create function app.process_evidence_quarantine_deadlines()
returns table (
  quarantines_escalated  integer,
  contests_timed_out     integer
)
language sql
volatile
security definer
set search_path = ''
as $$
  select *
  from app.process_evidence_quarantine_deadlines_at(
    clock_timestamp(),
    100
  );
$$;

comment on function app.process_evidence_quarantine_deadlines() is
  'One-minute D76 worker. Escalates rejected/due pending peer review and publishes assessment-bound inconclusive review_timeout results.';

-- One stable registry entry follows D82's database-only timer convention.
select cron.schedule(
  'gametime-process-quarantine-review-deadlines',
  '* * * * *',
  'select app.process_evidence_quarantine_deadlines();'
);

-- ===========================================================================
-- SECTION 9 -- Explicit least privilege
-- ===========================================================================

revoke all on function app.evidence_quarantine_peer_review_period(),
                       app.evidence_quarantine_adjudication_period(),
                       app.set_evidence_quarantine_review_deadline(),
                       app.ensure_evidence_quarantine_adjudication(
                         uuid,
                         app.evidence_quarantine_escalation_reason,
                         timestamptz
                       ),
                       app.emit_quarantine_adjudication_requested_intents(),
                       app.emit_quarantine_adjudication_resolution_intents(),
                       app.escalate_rejected_evidence_quarantine(),
                       app.clear_evidence_quarantine_adjudication_at(
                         uuid,
                         uuid,
                         timestamptz
                       ),
                       app.finalize_contest_review_timeout_at(
                         uuid,
                         timestamptz
                       ),
                       app.process_evidence_quarantine_deadlines_at(
                         timestamptz,
                         integer
                       )
  from public, anon, authenticated, service_role;

revoke all on function app.process_evidence_quarantine_deadlines()
  from public, anon, authenticated, service_role;
grant execute on function app.process_evidence_quarantine_deadlines()
  to service_role;

revoke all on function public.clear_evidence_quarantine_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.clear_evidence_quarantine_v1(uuid, uuid)
  to service_role;

revoke all on function public.get_evidence_quarantine_resolution_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_evidence_quarantine_resolution_v1(uuid)
  to authenticated;

-- Reassert the existing guarded review/read grants after replacement.
revoke all on function public.review_evidence_quarantine(uuid, boolean),
                       public.list_my_evidence_quarantines(uuid),
                       public.list_contest_quarantine_reviews(uuid),
                       public.get_quarantine_revision_history(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.review_evidence_quarantine(uuid, boolean),
                          public.list_my_evidence_quarantines(uuid),
                          public.list_contest_quarantine_reviews(uuid),
                          public.get_quarantine_revision_history(uuid)
  to authenticated;

-- Application roles cannot inspect or mutate the timer registry.
revoke all on schema cron
  from public, anon, authenticated, service_role;
revoke all on all functions in schema cron
  from public, anon, authenticated, service_role;
revoke all on all tables in schema cron
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema cron
  from public, anon, authenticated, service_role;

commit;
