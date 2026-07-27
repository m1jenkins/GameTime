-- D77 / P0 -- close cross-contest health-evidence disclosure.
--
-- The original table policies authorized a pair of users whenever they shared
-- any opened contest. They did not bind that relationship to the evidence
-- row's contest_id, so one shared contest exposed the subject's batches,
-- hourly timeline, source metadata, and quarantines from every other contest.
--
-- Raw audit relations are subject-only (review rows are reviewer-only) after
-- this migration. The only rival-facing evidence API is the bounded,
-- contest-scoped quarantine claim D77 permits an eligible reviewer to judge.
-- Full live/final standings remain M7 work: there is no persisted result or
-- integrity assessment in the current schema from which to serve them.

-- ===========================================================================
-- SECTION 1 -- Raw audit relations are owner-only
-- ===========================================================================

drop policy if exists ingest_batches_select_own_or_rival
  on public.ingest_batches;

create policy ingest_batches_select_own
  on public.ingest_batches
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists metric_snapshots_select_own_or_rival
  on public.metric_snapshots;

create policy metric_snapshots_select_own
  on public.metric_snapshots
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists evidence_quarantines_select_own_or_rival
  on public.evidence_quarantines;

create policy evidence_quarantines_select_own
  on public.evidence_quarantines
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists evidence_quarantine_reviews_select_visible
  on public.evidence_quarantine_reviews;

create policy evidence_quarantine_reviews_select_own
  on public.evidence_quarantine_reviews
  for select
  to authenticated
  using ((select auth.uid()) = reviewer_id);

-- Existing table-level SELECT grants stay in place. RLS now supplies the
-- object-level ownership predicate; D81's restrictive active_actor_only policy
-- continues to reject a tombstoned caller independently.
create index metric_snapshots_user_contest_bucket_idx
  on public.metric_snapshots (user_id, contest_id, bucket_start);

create index evidence_quarantines_user_contest_created_idx
  on public.evidence_quarantines (user_id, contest_id, created_at);

create index evidence_quarantine_reviews_reviewer_quarantine_idx
  on public.evidence_quarantine_reviews (reviewer_id, quarantine_id);

-- This invoker view cannot remain a client surface after reviews become
-- reviewer-only: its vote aggregates would otherwise be caller-relative and
-- therefore false. Trusted notification/finalization code retains service-role
-- access; clients use the explicitly authorized functions below.
revoke all on public.evidence_quarantine_status
  from public, anon, authenticated;

-- ===========================================================================
-- SECTION 2 -- Subject-scoped quarantine state
-- ===========================================================================

-- The evidence subject may inspect their complete retained quarantine facts,
-- together with aggregate state but never reviewer identities. Explicit
-- contest_id and user_id predicates make this safe even though the function
-- needs definer rights to compute counts over reviewer-only vote rows.
create function public.list_my_evidence_quarantines(p_contest_id uuid)
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
    status.state,
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
  'D77 subject surface: full retained quarantine facts and aggregate state for one exact contest.';

-- ===========================================================================
-- SECTION 3 -- Bounded peer-review claims
-- ===========================================================================

-- A pending claim is visible only to another accepted participant in this
-- exact contest, only while that contest remains active, and only until this
-- caller has cast their immutable vote. Finalized/resolved claims and pruned
-- raw snapshots fail closed by producing no row.
create function public.list_contest_quarantine_reviews(p_contest_id uuid)
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
   and status.state = 'pending'
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
  'D77 reviewer inbox: pending redacted quarantine claims for one exact accepted contest.';

-- The revision surface repeats only the bounded claim context needed to judge
-- an observation. It deliberately omits batch/snapshot IDs, assertion/key
-- material, source bundle and device identifiers, observed_at, sample counts,
-- arbitrary details, signal keys, reviewer identities, and votes.
create function public.get_quarantine_revision_history(p_quarantine_id uuid)
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
        revision.recorded_at - (revision.bucket_start + interval '1 hour')
      )) * 1000)::bigint
    ),
    revision.id = quarantine.snapshot_id
  from public.evidence_quarantines quarantine
  join public.evidence_quarantine_status status
    on status.id = quarantine.id
   and status.state = 'pending'
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
  'D77 reviewer evidence: redacted revision history for one pending, exactly authorized quarantine.';

-- Serialize the visibility window and the write window on the same quarantine
-- row. The earlier implementation correctly bound a reviewer to q.contest_id,
-- but it still accepted a new group-member vote after enough earlier votes had
-- already made the state approved or rejected. Identical retries retain their
-- original idempotency semantics; only a caller with no existing vote is
-- subject to the pending-state check.
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
    -- Preserve the existing not-found/error contract in the checked worker.
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

  -- Do not let an unrelated caller use the pending-state error as a claim
  -- existence/resolution oracle. The checked worker retains the canonical
  -- owner, exact-contest participant, and active-contest errors.
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
      and status.state = 'pending'
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
  'Records one immutable exact-contest vote while peer review is pending; identical retries remain idempotent.';

-- Functions are public API only through these explicit grants. SECURITY
-- DEFINER is intentional and bounded: owner-only base RLS cannot itself expose
-- a rival claim, so every function repeats exact contest and caller predicates.
revoke all on function public.list_my_evidence_quarantines(uuid),
                       public.list_contest_quarantine_reviews(uuid),
                       public.get_quarantine_revision_history(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.list_my_evidence_quarantines(uuid),
                          public.list_contest_quarantine_reviews(uuid),
                          public.get_quarantine_revision_history(uuid)
  to authenticated;
