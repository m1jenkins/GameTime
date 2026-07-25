-- M5 — Explicit integrity flags and retroactive-evidence review.
--
-- The TypeScript evaluator owns thresholds and score weights (D6). This
-- migration owns the durable workflow created by one of those flags:
-- `retroactive_evidence_quarantine`.
--
-- "Quarantine" does not mean rewriting the evidence ledger. A flagged snapshot
-- remains append-only, keeps its generated `is_admissible` value, and remains
-- visible through `contest_evidence`. The quarantine is a second, equally
-- auditable fact: this observation arrived late enough that settlement must
-- wait for review. M7 will refuse to finalize while one is pending or rejected;
-- it must not invent a second definition of admissibility by filtering the M4
-- view.
--
-- Thresholds travel with each row, together with a rule version. Retuning M5 is
-- therefore a TypeScript/configuration change rather than a migration, and a
-- later dispute can still say exactly which rule raised a flag.

-- ===========================================================================
-- SECTION 1 — Durable review state
-- ===========================================================================

create type public.evidence_quarantine_state as enum (
  'pending',
  'approved',
  'rejected'
);

create table public.evidence_quarantines (
  id                  uuid primary key default gen_random_uuid(),
  snapshot_id         uuid not null
    references public.metric_snapshots (id) on delete cascade,

  -- Copied from the snapshot by a BEFORE trigger. Keeping them on the row makes
  -- RLS and settlement queries indexable; the trigger makes the copy a fact,
  -- not caller-supplied denormalisation.
  contest_id          uuid not null,
  user_id             uuid not null,
  metric              public.contest_metric not null,
  bucket_start        timestamptz not null,

  rule_version        text not null,
  signal_key          text not null,
  threshold_ms        bigint not null,

  -- Server-derived from metric_snapshots.recorded_at and the bucket close.
  reporting_lag_ms    bigint not null,

  details             jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),

  constraint evidence_quarantines_participant_fkey
    foreign key (contest_id, user_id)
    references public.contest_participants (contest_id, user_id) on delete cascade,

  -- One evaluation version cannot quarantine the same physical observation
  -- twice. A retry returns this row; a new rule version leaves a new audit fact.
  constraint evidence_quarantines_snapshot_version_unique
    unique (snapshot_id, rule_version),

  constraint evidence_quarantines_signal_unique
    unique (contest_id, user_id, rule_version, signal_key),

  constraint evidence_quarantines_rule_version_length
    check (char_length(rule_version) between 1 and 80),
  constraint evidence_quarantines_signal_key_length
    check (char_length(signal_key) between 1 and 300),
  constraint evidence_quarantines_threshold_positive
    check (threshold_ms > 0),
  constraint evidence_quarantines_lag_meets_threshold
    check (reporting_lag_ms >= threshold_ms),
  constraint evidence_quarantines_details_object
    check (jsonb_typeof(details) = 'object')
);

comment on table public.evidence_quarantines is
  'Review-required retroactive observations. Does not alter admissibility or filter contest_evidence.';
comment on column public.evidence_quarantines.rule_version is
  'Version of the TypeScript thresholds and weights that raised the flag.';
comment on column public.evidence_quarantines.reporting_lag_ms is
  'Server-derived gap from the end of the covered hour to snapshot.recorded_at.';

create index evidence_quarantines_contest_state_idx
  on public.evidence_quarantines (contest_id, user_id, created_at);

-- Votes are an append-only ledger too. A reviewer cannot change "reject" to
-- "approve" after seeing how everybody else voted; retrying the same answer is
-- idempotent, and a conflicting answer is refused by the callable function.
create table public.evidence_quarantine_reviews (
  quarantine_id      uuid not null
    references public.evidence_quarantines (id) on delete cascade,
  reviewer_id        uuid not null
    references public.profiles (id) on delete cascade,
  approved           boolean not null,
  created_at         timestamptz not null default now(),

  primary key (quarantine_id, reviewer_id)
);

comment on table public.evidence_quarantine_reviews is
  'Append-only participant votes on one retroactive-evidence quarantine.';

-- ===========================================================================
-- SECTION 2 — Server-derived quarantine facts
-- ===========================================================================

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

  -- Manual and unknown rows are already visible-but-inadmissible facts. Holding
  -- one for review cannot change a settlement and would misdescribe the reason
  -- it does not score.
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

  return new;
end;
$$;

comment on function app.prepare_evidence_quarantine() is
  'Copies immutable snapshot identity and derives reporting lag for a quarantine row.';

create trigger evidence_quarantines_prepare
  before insert on public.evidence_quarantines
  for each row execute function app.prepare_evidence_quarantine();

create trigger evidence_quarantines_forbid_update
  before update on public.evidence_quarantines
  for each row execute function app.forbid_mutation();

create trigger evidence_quarantine_reviews_forbid_update
  before update on public.evidence_quarantine_reviews
  for each row execute function app.forbid_mutation();

-- Account deletion still cascades through the M3 ledger (D35's known deferral),
-- so DELETE cannot be prohibited on either child without recreating that bug.
-- Clients have no DELETE grant or policy; a privileged cascade is the only
-- supported deletion path.

-- ===========================================================================
-- SECTION 3 — Computed state
-- ===========================================================================

-- A duel needs its one opponent. A group needs a strict majority of *other*
-- accepted participants. Silence stays pending; enough no votes to make a
-- majority impossible is rejected. There is no timeout that turns silence into
-- approval.
create view public.evidence_quarantine_status
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
  eligible.reviewer_count,
  (eligible.reviewer_count / 2 + 1)::integer as approvals_required,
  votes.approval_count,
  votes.rejection_count,
  case
    when eligible.reviewer_count = 0
      then 'pending'::public.evidence_quarantine_state
    when votes.approval_count >= (eligible.reviewer_count / 2 + 1)
      then 'approved'::public.evidence_quarantine_state
    when votes.rejection_count >
         eligible.reviewer_count - (eligible.reviewer_count / 2 + 1)
      then 'rejected'::public.evidence_quarantine_state
    else 'pending'::public.evidence_quarantine_state
  end as state
from public.evidence_quarantines q
cross join lateral (
  select count(*)::integer as reviewer_count
  from public.contest_participants p
  where p.contest_id = q.contest_id
    and p.status = 'accepted'
    and p.user_id <> q.user_id
) eligible
cross join lateral (
  select
    count(*) filter (where r.approved)::integer as approval_count,
    count(*) filter (where not r.approved)::integer as rejection_count
  from public.evidence_quarantine_reviews r
  join public.contest_participants p
    on p.contest_id = q.contest_id
   and p.user_id = r.reviewer_id
   and p.status = 'accepted'
  where r.quarantine_id = q.id
    and r.reviewer_id <> q.user_id
) votes;

comment on view public.evidence_quarantine_status is
  'Review state derived from append-only votes. Pending never changes evidence admissibility.';

-- ===========================================================================
-- SECTION 4 — Access model
-- ===========================================================================

alter table public.evidence_quarantines enable row level security;
alter table public.evidence_quarantine_reviews enable row level security;

create policy evidence_quarantines_select_own_or_rival
  on public.evidence_quarantines
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or app.shares_active_contest(user_id, (select auth.uid()))
  );

create policy evidence_quarantine_reviews_select_visible
  on public.evidence_quarantine_reviews
  for select to authenticated
  using (
    exists (
      select 1
      from public.evidence_quarantines q
      where q.id = quarantine_id
        and (
          q.user_id = (select auth.uid())
          or app.shares_active_contest(q.user_id, (select auth.uid()))
        )
    )
  );

-- No INSERT/UPDATE/DELETE policies. Creation comes from the trusted M5 worker,
-- and voting goes through the function below so eligibility and idempotency are
-- checked in one transaction.

-- ===========================================================================
-- SECTION 5 — Callable API
-- ===========================================================================

create or replace function public.record_evidence_quarantine(
  p_snapshot_id    uuid,
  p_rule_version   text,
  p_signal_key     text,
  p_threshold_ms   bigint,
  p_details        jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id       uuid;
  v_existing public.evidence_quarantines;
begin
  if p_snapshot_id is null then
    raise exception 'snapshot id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.evidence_quarantines (
    snapshot_id, rule_version, signal_key, threshold_ms, details
  )
  values (
    p_snapshot_id, p_rule_version, p_signal_key, p_threshold_ms, p_details
  )
  on conflict (snapshot_id, rule_version) do nothing
  returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  -- The conflict path also covers two evaluator workers racing on the same
  -- observation. An identical request is a retry; a different request wearing
  -- the same rule version is a collision and must not inherit the first id.
  select * into v_existing
  from public.evidence_quarantines
  where snapshot_id = p_snapshot_id
    and rule_version = p_rule_version;

  if v_existing.signal_key is distinct from p_signal_key
     or v_existing.threshold_ms is distinct from p_threshold_ms
     or v_existing.details is distinct from p_details
  then
    raise exception
      'snapshot % already has a different quarantine for rule version %',
      p_snapshot_id, p_rule_version
      using errcode = 'unique_violation';
  end if;

  return v_existing.id;
end;
$$;

comment on function public.record_evidence_quarantine(uuid, text, text, bigint, jsonb) is
  'Records a TypeScript retroactive-evidence flag. service_role only and idempotent.';

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

  select q.user_id, q.contest_id, c.status
    into v_record
  from public.evidence_quarantines q
  join public.contests c on c.id = q.contest_id
  where q.id = p_quarantine_id;

  if v_record.contest_id is null then
    raise exception 'quarantine not found'
      using errcode = 'insufficient_privilege';
  end if;

  if v_record.status <> 'active' then
    raise exception 'only an active contest may review evidence'
      using errcode = 'restrict_violation';
  end if;

  if v_record.user_id = v_uid then
    raise exception 'a participant cannot review their own evidence'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
    from public.contest_participants p
    where p.contest_id = v_record.contest_id
      and p.user_id = v_uid
      and p.status = 'accepted'
  ) then
    raise exception 'only another accepted participant may review this evidence'
      using errcode = 'insufficient_privilege';
  end if;

  select approved into v_existing
  from public.evidence_quarantine_reviews
  where quarantine_id = p_quarantine_id
    and reviewer_id = v_uid;

  if found then
    if v_existing = p_approved then
      return;
    end if;
    raise exception 'a quarantine review cannot be changed'
      using errcode = 'restrict_violation';
  end if;

  insert into public.evidence_quarantine_reviews (
    quarantine_id, reviewer_id, approved
  )
  values (p_quarantine_id, v_uid, p_approved);
end;
$$;

comment on function public.review_evidence_quarantine(uuid, boolean) is
  'Records one immutable vote by another accepted participant.';

-- ===========================================================================
-- SECTION 6 — Privileges
-- ===========================================================================

revoke all on public.evidence_quarantines,
              public.evidence_quarantine_reviews,
              public.evidence_quarantine_status
  from anon, authenticated;

grant select on public.evidence_quarantines,
                public.evidence_quarantine_reviews,
                public.evidence_quarantine_status
  to authenticated;

revoke all on function app.prepare_evidence_quarantine()
  from public, anon, authenticated;

revoke all on function public.record_evidence_quarantine(
  uuid, text, text, bigint, jsonb
) from public, anon, authenticated;
grant execute on function public.record_evidence_quarantine(
  uuid, text, text, bigint, jsonb
) to service_role;

revoke all on function public.review_evidence_quarantine(uuid, boolean)
  from public, anon;
grant execute on function public.review_evidence_quarantine(uuid, boolean)
  to authenticated;
