-- M7.2a — transactional notification intents and real contest activation.
--
-- Business transitions write generic, recipient-scoped intents in the same
-- transaction. M8 will add delivery attempts, APNs tokens, and presentation;
-- none of those best-effort concerns belong on this append-only business
-- ledger. The first scheduled worker opens due contests every minute.

-- Supabase applies migration statements independently unless the file opens an
-- explicit transaction. The outbox, its transition triggers, and the cron job
-- must appear together or not at all.
begin;

-- ===========================================================================
-- SECTION 1 — Generic append-only outbox
-- ===========================================================================

create type public.notification_event_type as enum (
  'contest_invitation',
  'contest_activated',
  'contest_cancelled',
  'contest_finalized',
  'quarantine_review_requested',
  'quarantine_review_reminder',
  'quarantine_review_escalated',
  'quarantine_review_resolved',
  'timezone_consent_requested',
  'timezone_consent_reminder',
  'timezone_consent_resolved',
  'obligation_created',
  'obligation_actionable',
  'obligation_due_reminder',
  'obligation_released',
  'obligation_reinstated',
  'obligation_defaulted',
  'pledge_claim_submitted',
  'pledge_claim_challenge_deadline',
  'pledge_claim_expired',
  'pledge_claim_acknowledged',
  'pledge_claim_disputed',
  'pledge_claim_confirmed',
  'dispute_filed',
  'dispute_adjudication_reminder',
  'dispute_status_changed',
  'dispute_resolved',
  'dispute_timed_out'
);

create table public.notification_intents (
  id                 bigint generated always as identity primary key,

  -- Deliberately no profile FK. D81 preserves the event after authentication
  -- deletion, while the current profile cascade must not erase the outbox or
  -- make account deletion fail.
  recipient_user_id  uuid not null,
  event_type         public.notification_event_type not null,

  -- The type says what the opaque id names. There is no arbitrary payload:
  -- clients fetch authorized domain detail after opening the app, so health,
  -- location, receipt, and dispute facts never land in a lock-screen envelope.
  entity_id          uuid not null,
  reminder_stage     smallint not null default 0,
  not_before         timestamptz not null default now(),
  created_at         timestamptz not null default now(),

  constraint notification_intents_reminder_stage_nonnegative
    check (reminder_stage >= 0),

  -- One business event produces at most one intent for a recipient and reminder
  -- stage. INSERT ... ON CONFLICT makes retries and concurrent workers safe.
  constraint notification_intents_semantic_key
    unique (event_type, entity_id, recipient_user_id, reminder_stage)
);

comment on table public.notification_intents is
  'Append-only transactional notification outbox. M8 owns delivery state in separate ledgers.';
comment on column public.notification_intents.recipient_user_id is
  'Opaque durable actor UUID; intentionally has no profile FK so account deletion cannot erase the intent.';
comment on column public.notification_intents.entity_id is
  'Opaque domain identifier interpreted only together with event_type; never a sensitive payload.';
comment on column public.notification_intents.not_before is
  'Server timestamp before which delivery should not be attempted; business deadlines never depend on delivery.';

-- The RLS predicate and inbox ordering share one index. Equality comes first,
-- followed by the descending range/order columns.
create index notification_intents_recipient_created_idx
  on public.notification_intents (recipient_user_id, created_at desc, id desc);

create trigger notification_intents_forbid_mutation
  before update or delete on public.notification_intents
  for each row execute function app.forbid_mutation();

create trigger notification_intents_forbid_truncate
  before truncate on public.notification_intents
  for each statement execute function app.forbid_mutation();

alter table public.notification_intents enable row level security;

create policy notification_intents_select_own
  on public.notification_intents
  for select to authenticated
  using (
    recipient_user_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles profile
      where profile.id = (select auth.uid())
    )
  );

comment on policy notification_intents_select_own
  on public.notification_intents is
  'Recipient-only while the authenticated profile is active. D81 will extend the profile check to deleted_at is null when tombstones replace today''s cascade.';

-- No client INSERT/UPDATE/DELETE policy exists. Trusted transition triggers are
-- the only writers, and M8 receives read-only service access for delivery.
revoke all on table public.notification_intents
  from public, anon, authenticated, service_role;
grant select on table public.notification_intents
  to authenticated, service_role;

revoke all on sequence public.notification_intents_id_seq
  from public, anon, authenticated, service_role;

create function app.emit_notification_intent(
  p_recipient_user_id uuid,
  p_event_type        public.notification_event_type,
  p_entity_id         uuid,
  p_reminder_stage    smallint default 0,
  p_not_before        timestamptz default now()
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_recipient_user_id is null
     or p_event_type is null
     or p_entity_id is null
     or p_reminder_stage is null
     or p_not_before is null
  then
    raise exception 'notification recipient, type, entity, stage, and time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_reminder_stage < 0 then
    raise exception 'notification reminder stage must be nonnegative'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.notification_intents (
    recipient_user_id,
    event_type,
    entity_id,
    reminder_stage,
    not_before
  )
  values (
    p_recipient_user_id,
    p_event_type,
    p_entity_id,
    p_reminder_stage,
    p_not_before
  )
  on conflict on constraint notification_intents_semantic_key do nothing;
end;
$$;

comment on function app.emit_notification_intent(
  uuid, public.notification_event_type, uuid, smallint, timestamptz
) is
  'Trusted idempotent writer for the generic notification outbox; never client-callable.';

revoke all on function app.emit_notification_intent(
  uuid, public.notification_event_type, uuid, smallint, timestamptz
) from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 2 — Existing transition emitters
-- ===========================================================================

create function app.emit_contest_invitation_intent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.emit_notification_intent(
    new.user_id,
    'contest_invitation'::public.notification_event_type,
    new.contest_id
  );
  return new;
end;
$$;

create trigger contest_participants_emit_invitation_intent
  after insert on public.contest_participants
  for each row
  when (new.status = 'invited')
  execute function app.emit_contest_invitation_intent();

create function app.emit_contest_status_intents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  if new.status = 'active' then
    for v_recipient in
      select participant.user_id
      from public.contest_participants participant
      where participant.contest_id = new.id
        and participant.status = 'accepted'
      order by participant.user_id
    loop
      perform app.emit_notification_intent(
        v_recipient,
        'contest_activated'::public.notification_event_type,
        new.id
      );
    end loop;
  elsif new.status = 'cancelled' then
    -- Both accepted participants and unanswered invitees whose rows were
    -- atomically lapsed need to know the pending contest will not happen.
    for v_recipient in
      select participant.user_id
      from public.contest_participants participant
      where participant.contest_id = new.id
        and participant.status in ('accepted', 'lapsed')
      order by participant.user_id
    loop
      perform app.emit_notification_intent(
        v_recipient,
        'contest_cancelled'::public.notification_event_type,
        new.id
      );
    end loop;
  end if;

  return new;
end;
$$;

create trigger contests_emit_status_intents
  after update of status on public.contests
  for each row
  when (
    old.status is distinct from new.status
    and new.status in ('active', 'cancelled')
  )
  execute function app.emit_contest_status_intents();

create function app.emit_timezone_change_request_intents()
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
      and participant.user_id <> new.user_id
    order by participant.user_id
  loop
    perform app.emit_notification_intent(
      v_recipient,
      'timezone_consent_requested'::public.notification_event_type,
      new.id
    );
  end loop;

  return new;
end;
$$;

create trigger timezone_change_requests_emit_intents
  after insert on public.timezone_change_requests
  for each row execute function app.emit_timezone_change_request_intents();

create function app.emit_timezone_change_rejection_intent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  select request.user_id
    into v_recipient
  from public.timezone_change_requests request
  where request.id = new.request_id;

  perform app.emit_notification_intent(
    v_recipient,
    'timezone_consent_resolved'::public.notification_event_type,
    new.request_id
  );

  return new;
end;
$$;

create trigger timezone_change_reviews_emit_rejection_intent
  after insert on public.timezone_change_reviews
  for each row
  when (not new.approved)
  execute function app.emit_timezone_change_rejection_intent();

create function app.emit_timezone_change_approval_intent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.emit_notification_intent(
    new.user_id,
    'timezone_consent_resolved'::public.notification_event_type,
    new.request_id
  );
  return new;
end;
$$;

create trigger timezone_change_applied_events_emit_intent
  after insert on public.timezone_change_applied_events
  for each row execute function app.emit_timezone_change_approval_intent();

create function app.emit_evidence_quarantine_request_intents()
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
      and participant.user_id <> new.user_id
    order by participant.user_id
  loop
    perform app.emit_notification_intent(
      v_recipient,
      'quarantine_review_requested'::public.notification_event_type,
      new.id
    );
  end loop;

  return new;
end;
$$;

create trigger evidence_quarantines_emit_request_intents
  after insert on public.evidence_quarantines
  for each row execute function app.emit_evidence_quarantine_request_intents();

-- The normal review RPC already locks this parent. Making the lock a table
-- invariant as well prevents a privileged bulk writer from racing two final
-- approval votes: every AFTER trigger must observe all earlier committed votes
-- before deciding whether the derived state just became approved.
create function app.serialize_evidence_quarantine_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.evidence_quarantines quarantine
  where quarantine.id = new.quarantine_id
  for update;

  if not found then
    raise exception 'quarantine % does not exist', new.quarantine_id
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$$;

create trigger evidence_quarantine_reviews_serialize_intent
  before insert on public.evidence_quarantine_reviews
  for each row execute function app.serialize_evidence_quarantine_review();

create function app.emit_evidence_quarantine_resolution_intent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_state     public.evidence_quarantine_state;
begin
  select quarantine.user_id, status.state
    into v_recipient, v_state
  from public.evidence_quarantines quarantine
  join public.evidence_quarantine_status status
    on status.id = quarantine.id
  where quarantine.id = new.quarantine_id;

  if v_state = 'approved' then
    perform app.emit_notification_intent(
      v_recipient,
      'quarantine_review_resolved'::public.notification_event_type,
      new.quarantine_id
    );
  end if;

  -- Rejection is not resolution under D76. The adjudication slice will append
  -- the escalation request and its operator intent atomically; this trigger
  -- must not claim an escalation exists before that durable workflow does.
  return new;
end;
$$;

create trigger evidence_quarantine_reviews_emit_resolution_intent
  after insert on public.evidence_quarantine_reviews
  for each row execute function app.emit_evidence_quarantine_resolution_intent();

revoke all on function app.emit_contest_invitation_intent(),
                       app.emit_contest_status_intents(),
                       app.emit_timezone_change_request_intents(),
                       app.emit_timezone_change_rejection_intent(),
                       app.emit_timezone_change_approval_intent(),
                       app.emit_evidence_quarantine_request_intents(),
                       app.serialize_evidence_quarantine_review(),
                       app.emit_evidence_quarantine_resolution_intent()
  from public, anon, authenticated, service_role;

-- Existing rows are history, not newly actionable transitions. No backfill is
-- performed; doing so would manufacture notifications for old invitations and
-- already-completed reviews.

-- ===========================================================================
-- SECTION 3 — Scheduled activation
-- ===========================================================================

-- pg_cron owns its `cron` schema, so it is the deliberate exception to the
-- repository convention that ordinary extensions live in `extensions`.
create extension if not exists pg_cron;

-- A one-minute cadence bounds ordinary activation lag to less than a minute.
-- The named job is the durable registry entry and calls the already-revoked
-- server-only function directly inside Postgres.
select cron.schedule(
  'gametime-activate-due-contests',
  '* * * * *',
  'select app.activate_due_contests();'
);

comment on function app.activate_due_contests(timestamptz) is
  'One-minute cron entry point. Opens due contests with quorum 2, cancels the rest, and lapses unanswered invitations.';

-- Application roles neither inspect nor mutate scheduler metadata. The job
-- runs as its migration owner; service_role remains able to invoke the worker
-- explicitly for guarded operational recovery and tests.
revoke all on schema cron
  from public, anon, authenticated, service_role;
revoke all on all functions in schema cron
  from public, anon, authenticated, service_role;
revoke all on all tables in schema cron
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema cron
  from public, anon, authenticated, service_role;

commit;
