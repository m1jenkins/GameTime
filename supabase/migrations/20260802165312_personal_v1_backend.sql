-- Personal Accountability V1 -- frozen terms, attested coverage, diagnostics,
-- owner-only reads, lifecycle RPCs, and isolated personal outcomes.

create type public.personal_settlement_mode as enum ('test_only');

create type public.personal_challenge_outcome as enum (
  'met_goal',
  'missed_goal',
  'inconclusive'
);

create type public.personal_evidence_state as enum (
  'complete',
  'missing',
  'quarantined',
  'conflicting',
  'unresolved',
  'user_device_sync_failure',
  'gametime_outage'
);

create type public.personal_quarantine_resolution as enum (
  'cleared',
  'rejected'
);

create type public.personal_result_reason as enum (
  'target_reached',
  'target_missed',
  'missing_coverage',
  'quarantined_evidence',
  'conflicting_evidence',
  'unresolved_evidence',
  'user_device_sync_failure',
  'gametime_outage'
);

create type public.personal_eligibility_hold_reason as enum (
  'user_device_sync_failure'
);

-- ---------------------------------------------------------------------------
-- Frozen personal terms and request ledgers
-- ---------------------------------------------------------------------------

create table public.personal_challenge_terms (
  challenge_id                uuid not null
    references public.contests (id) on delete restrict,
  user_id                     uuid not null
    references public.profiles (id) on delete restrict,
  cadence                     public.contest_cadence not null,
  target_steps                integer not null,
  commitment_amount_minor     integer not null,
  currency                    text not null default 'USD',
  settlement_mode             public.personal_settlement_mode not null
    default 'test_only',
  terms_version               text not null default 'personal-v1',
  timezone                    text not null,
  agreed_at                   timestamptz not null default clock_timestamp(),
  evidence_cutoff             timestamptz not null,
  closed_at                   timestamptz,

  primary key (challenge_id, user_id),
  constraint personal_challenge_terms_one_owner unique (challenge_id),
  constraint personal_challenge_terms_target_bounded check (
    target_steps between 1 and 1000000
  ),
  constraint personal_challenge_terms_commitment_preset check (
    commitment_amount_minor in (1000, 2000, 3000, 4000, 5000)
  ),
  constraint personal_challenge_terms_currency_usd check (currency = 'USD'),
  constraint personal_challenge_terms_test_only check (
    settlement_mode = 'test_only'
  ),
  constraint personal_challenge_terms_version_bounded check (
    char_length(terms_version) between 1 and 80
  ),
  constraint personal_challenge_terms_times_finite check (
    pg_catalog.isfinite(agreed_at)
    and pg_catalog.isfinite(evidence_cutoff)
    and (closed_at is null or pg_catalog.isfinite(closed_at))
  )
);

comment on table public.personal_challenge_terms is
  'Owner-specific immutable Personal V1 terms. closed_at is the sole mutable field and closes once.';
comment on column public.personal_challenge_terms.settlement_mode is
  'Stage A is structurally test_only. There is no live-fee enum value or client parameter.';

create table app.personal_challenge_creation_requests (
  actor_id      uuid not null
    references public.profiles (id) on delete restrict,
  request_id    uuid not null,
  payload_hash  bytea not null,
  challenge_id  uuid not null unique
    references public.contests (id) on delete restrict,
  created_at    timestamptz not null default clock_timestamp(),

  primary key (actor_id, request_id),
  constraint personal_creation_request_digest check (
    octet_length(payload_hash) = 32
  )
);

create table app.personal_challenge_cancellation_requests (
  actor_id      uuid not null
    references public.profiles (id) on delete restrict,
  request_id    uuid not null,
  payload_hash  bytea not null,
  challenge_id  uuid not null
    references public.contests (id) on delete restrict,
  created_at    timestamptz not null default clock_timestamp(),

  primary key (actor_id, request_id),
  constraint personal_cancellation_request_digest check (
    octet_length(payload_hash) = 32
  )
);

-- Pending and active are the one open slot. An ended challenge remains active
-- through its 24-hour sync grace and assessment, so it continues to hold the
-- slot until result publication finalizes it.
create unique index contests_one_open_personal_per_owner_idx
  on public.contests (created_by)
  where challenge_model = 'personal_accountability'
    and status in ('pending', 'active');

-- ---------------------------------------------------------------------------
-- App-Attest-bound coverage and independent trusted diagnostics
-- ---------------------------------------------------------------------------

create table public.personal_sync_coverage_batches (
  id                  uuid primary key default gen_random_uuid(),
  challenge_id        uuid not null,
  user_id             uuid not null,
  client_coverage_id  uuid not null,
  -- Historical SHA-256 fingerprint only. The trusted RPC verifies the live
  -- registration before insert, but D81 may later prune that operational row.
  key_id              bytea not null,
  sign_count          bigint not null,
  payload_digest      bytea not null,
  observed_at         timestamptz not null,
  covered_bucket_count integer not null,
  recorded_at         timestamptz not null default clock_timestamp(),

  constraint personal_coverage_participant_fkey
    foreign key (challenge_id, user_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint personal_coverage_identity_unique
    unique (id, challenge_id, user_id),
  constraint personal_coverage_client_unique
    unique (user_id, client_coverage_id),
  constraint personal_coverage_digest_sha256 check (
    octet_length(payload_digest) = 32
  ),
  constraint personal_coverage_count_bounded check (
    covered_bucket_count between 1 and 2000
  ),
  constraint personal_coverage_sign_count_positive check (sign_count > 0),
  constraint personal_coverage_times_finite check (
    pg_catalog.isfinite(observed_at)
    and pg_catalog.isfinite(recorded_at)
  )
);

create table public.personal_sync_coverage_buckets (
  coverage_batch_id  uuid not null,
  challenge_id       uuid not null,
  user_id            uuid not null,
  bucket_start       timestamptz not null,

  primary key (coverage_batch_id, bucket_start),
  constraint personal_coverage_buckets_batch_fkey
    foreign key (coverage_batch_id, challenge_id, user_id)
    references public.personal_sync_coverage_batches (
      id, challenge_id, user_id
    )
    on delete restrict,
  constraint personal_coverage_bucket_finite check (
    pg_catalog.isfinite(bucket_start)
  )
);

comment on table public.personal_sync_coverage_buckets is
  'Durable Personal V1 evidence-completeness audit metadata: Calendar-hour query keys only, with no HealthKit value, source identifier, or sample payload. Classified as a retained derived fact rather than a raw metric observation under raw-evidence-retention-v1.';

create index personal_coverage_union_idx
  on public.personal_sync_coverage_buckets (
    challenge_id, user_id, bucket_start
  );

create table public.personal_trusted_diagnostics (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null
    references public.profiles (id) on delete restrict,
  client_diagnostic_id  uuid not null,
  -- Historical SHA-256 fingerprint only. Do not retain the operational device
  -- registration beyond D81 merely because this diagnostic audit fact remains.
  key_id                bytea not null,
  sign_count            bigint not null,
  payload_digest        bytea not null,
  observed_at           timestamptz not null,
  query_started_at      timestamptz not null,
  query_ended_at        timestamptz not null,
  trusted_device_sample_count integer not null,
  recorded_at           timestamptz not null default clock_timestamp(),

  constraint personal_diagnostic_client_unique
    unique (user_id, client_diagnostic_id),
  constraint personal_diagnostic_digest_sha256 check (
    octet_length(payload_digest) = 32
  ),
  constraint personal_diagnostic_sign_count_positive check (sign_count > 0),
  constraint personal_diagnostic_sample_count_positive check (
    trusted_device_sample_count between 1 and 100000
  ),
  constraint personal_diagnostic_window_ordered check (
    query_started_at < query_ended_at
    and query_ended_at <= observed_at
    and query_started_at >= observed_at - interval '24 hours'
  ),
  constraint personal_diagnostic_times_finite check (
    pg_catalog.isfinite(observed_at)
    and pg_catalog.isfinite(query_started_at)
    and pg_catalog.isfinite(query_ended_at)
    and pg_catalog.isfinite(recorded_at)
  )
);

comment on table public.personal_trusted_diagnostics is
  'Durable security/eligibility audit facts: bounded query window and aggregate positive trusted-device sample count only. No HealthKit values, sample timestamps, source identifiers, or medical records are stored; classified as retained derived facts under raw-evidence-retention-v1.';

-- ---------------------------------------------------------------------------
-- Service-owned assessment, owner-visible terminal result, and eligibility hold
-- ---------------------------------------------------------------------------

create table app.personal_evidence_assessments (
  id                    uuid primary key default gen_random_uuid(),
  challenge_id          uuid not null unique
    references public.contests (id) on delete restrict,
  user_id               uuid not null
    references public.profiles (id) on delete restrict,
  request_id             uuid not null,
  evidence_state         public.personal_evidence_state not null,
  evidence_cutoff        timestamptz not null,
  assessment_version     text not null,
  evidence_digest        bytea not null,
  full_expected_buckets  integer not null,
  covered_buckets        integer not null,
  total_steps            numeric(20, 2) not null,
  daily_totals           jsonb not null,
  outage_reference       text,
  assessed_at            timestamptz not null default clock_timestamp(),

  constraint personal_assessment_request_unique unique (user_id, request_id),
  constraint personal_assessment_digest_sha256 check (
    octet_length(evidence_digest) = 32
  ),
  constraint personal_assessment_counts_valid check (
    full_expected_buckets between 1 and 2000
    and covered_buckets between 0 and full_expected_buckets
  ),
  constraint personal_assessment_total_nonnegative check (total_steps >= 0),
  constraint personal_assessment_daily_array check (
    jsonb_typeof(daily_totals) = 'array'
    and jsonb_array_length(daily_totals) = 7
  ),
  constraint personal_assessment_version_bounded check (
    char_length(assessment_version) between 1 and 80
  ),
  constraint personal_assessment_outage_shape check (
    (evidence_state = 'gametime_outage') = (outage_reference is not null)
    and (outage_reference is null or char_length(outage_reference) between 1 and 240)
  ),
  constraint personal_assessment_times_finite check (
    pg_catalog.isfinite(evidence_cutoff)
    and pg_catalog.isfinite(assessed_at)
  )
);

-- Personal evidence flags deliberately do not reuse the social peer-review
-- state machine. A trusted service/operator may append one terminal decision
-- for a flag; no row means the flag remains unresolved.
create table app.personal_quarantine_resolutions (
  id               uuid primary key default gen_random_uuid(),
  quarantine_id    uuid not null unique
    references public.evidence_quarantines (id) on delete restrict,
  challenge_id     uuid not null
    references public.contests (id) on delete restrict,
  user_id          uuid not null
    references public.profiles (id) on delete restrict,
  request_id       uuid not null unique,
  resolution       public.personal_quarantine_resolution not null,
  reason_code      text not null,
  evidence_digest  bytea not null,
  resolved_at      timestamptz not null default clock_timestamp(),

  constraint personal_quarantine_resolution_reason_bounded check (
    char_length(reason_code) between 1 and 80
    and reason_code ~ '^[a-z0-9][a-z0-9_]*$'
  ),
  constraint personal_quarantine_resolution_digest_sha256 check (
    octet_length(evidence_digest) = 32
  ),
  constraint personal_quarantine_resolution_time_finite check (
    pg_catalog.isfinite(resolved_at)
  )
);

comment on table app.personal_quarantine_resolutions is
  'Service-only append-only terminal decisions for Personal V1 evidence flags. No row means unresolved; this table never accepts peer votes.';

create table public.personal_challenge_results (
  id                    uuid primary key default gen_random_uuid(),
  challenge_id          uuid not null unique
    references public.contests (id) on delete restrict,
  user_id               uuid not null
    references public.profiles (id) on delete restrict,
  assessment_id         uuid not null unique
    references app.personal_evidence_assessments (id) on delete restrict,
  outcome               public.personal_challenge_outcome not null,
  reason                public.personal_result_reason not null,
  evidence_state        public.personal_evidence_state not null,
  evidence_cutoff       timestamptz not null,
  total_steps           numeric(20, 2) not null,
  daily_totals          jsonb not null,
  commitment_waived     boolean not null,
  published_at          timestamptz not null default clock_timestamp(),

  constraint personal_result_outcome_reason_shape check (
    (
      outcome = 'met_goal'
      and evidence_state = 'complete'
      and reason = 'target_reached'
      and not commitment_waived
    )
    or (
      outcome = 'missed_goal'
      and evidence_state = 'complete'
      and reason = 'target_missed'
      and not commitment_waived
    )
    or (
      outcome = 'inconclusive'
      and evidence_state <> 'complete'
      and reason in (
        'missing_coverage',
        'quarantined_evidence',
        'conflicting_evidence',
        'unresolved_evidence',
        'user_device_sync_failure',
        'gametime_outage'
      )
      and commitment_waived
    )
  ),
  constraint personal_result_total_nonnegative check (total_steps >= 0),
  constraint personal_result_daily_array check (
    jsonb_typeof(daily_totals) = 'array'
    and jsonb_array_length(daily_totals) = 7
  ),
  constraint personal_result_times_finite check (
    pg_catalog.isfinite(evidence_cutoff)
    and pg_catalog.isfinite(published_at)
    and published_at >= evidence_cutoff
  )
);

create table public.personal_eligibility_holds (
  id                         uuid primary key default gen_random_uuid(),
  user_id                    uuid not null
    references public.profiles (id) on delete restrict,
  challenge_id               uuid not null
    references public.contests (id) on delete restrict,
  result_id                  uuid not null unique
    references public.personal_challenge_results (id) on delete restrict,
  reason                     public.personal_eligibility_hold_reason not null,
  placed_at                  timestamptz not null default clock_timestamp(),
  cleared_at                 timestamptz,
  cleared_by_diagnostic_id   uuid
    references public.personal_trusted_diagnostics (id) on delete restrict,

  constraint personal_hold_clear_shape check (
    (cleared_at is null) = (cleared_by_diagnostic_id is null)
  ),
  constraint personal_hold_times_finite check (
    pg_catalog.isfinite(placed_at)
    and (cleared_at is null or (pg_catalog.isfinite(cleared_at) and cleared_at > placed_at))
  )
);

create unique index personal_eligibility_one_active_hold_idx
  on public.personal_eligibility_holds (user_id)
  where cleared_at is null;

-- ---------------------------------------------------------------------------
-- Invariant triggers
-- ---------------------------------------------------------------------------

create function app.validate_personal_terms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contest public.contests;
begin
  select contest.* into v_contest
  from public.contests contest
  where contest.id = new.challenge_id;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from new.user_id
     or v_contest.metric <> 'steps'
     or v_contest.cadence <> new.cadence
     or v_contest.target_value <> new.target_steps
     or v_contest.stake_amount_cents <> new.commitment_amount_minor
     or v_contest.max_participants <> 1
     or v_contest.group_id is not null
     or v_contest.tie_break <> 'void'
  then
    raise exception 'personal terms do not match the immutable challenge row'
      using errcode = 'restrict_violation';
  end if;

  if new.evidence_cutoff <> v_contest.ends_at + interval '24 hours' then
    raise exception 'personal evidence cutoff must be exactly 24 hours after the seventh day'
      using errcode = 'invalid_parameter_value';
  end if;

  if not exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = new.challenge_id
      and participant.user_id = new.user_id
      and participant.status = 'accepted'
      and participant.timezone = new.timezone
      and participant.charity_id is null
  ) then
    raise exception 'personal terms require the accepted owner participant'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_terms_validate_insert
  before insert on public.personal_challenge_terms
  for each row execute function app.validate_personal_terms();

create function app.guard_personal_terms_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if to_jsonb(new) - 'closed_at' is distinct from to_jsonb(old) - 'closed_at'
     or old.closed_at is not null
     or new.closed_at is null
     or new.closed_at < old.agreed_at
  then
    raise exception 'personal terms are frozen; closed_at may be set exactly once'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger personal_terms_guard_update
  before update on public.personal_challenge_terms
  for each row execute function app.guard_personal_terms_update();

-- Every terminal contest transition closes Personal V1 terms, including the
-- account-deletion path that cancels a creator's pending challenge outside the
-- dedicated cancellation RPC.
create function app.close_personal_terms_on_terminal_contest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_terminal_at timestamptz;
begin
  if new.challenge_model = 'personal_accountability'
     and old.status in ('pending', 'active')
     and new.status in ('cancelled', 'finalized')
  then
    v_terminal_at := coalesce(
      new.cancelled_at,
      (
        select result.published_at
        from public.personal_challenge_results result
        where result.challenge_id = new.id
      ),
      clock_timestamp()
    );

    update public.personal_challenge_terms terms
    set closed_at = v_terminal_at
    where terms.challenge_id = new.id
      and terms.closed_at is null;

    if exists (
      select 1
      from app.workflow_scopes scope
      where scope.scope_kind = 'contest_lineage'
        and scope.scope_id = new.id
    ) then
      perform public.set_workflow_retention_state(
        'contest_lineage',
        new.id,
        false,
        v_terminal_at,
        v_terminal_at,
        'raw-evidence-retention-v1'
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger contests_close_personal_terms_terminal
  after update of status on public.contests
  for each row
  when (old.status is distinct from new.status)
  execute function app.close_personal_terms_on_terminal_contest();

create trigger personal_terms_forbid_delete
  before delete or truncate on public.personal_challenge_terms
  for each statement execute function app.forbid_mutation();

create function app.guard_personal_hold_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_diagnostic public.personal_trusted_diagnostics;
begin
  if to_jsonb(new) - 'cleared_at' - 'cleared_by_diagnostic_id'
       is distinct from
     to_jsonb(old) - 'cleared_at' - 'cleared_by_diagnostic_id'
     or old.cleared_at is not null
     or new.cleared_at is null
     or new.cleared_by_diagnostic_id is null
  then
    raise exception 'an eligibility hold may only be cleared once by a trusted diagnostic'
      using errcode = 'restrict_violation';
  end if;

  select diagnostic.* into v_diagnostic
  from public.personal_trusted_diagnostics diagnostic
  where diagnostic.id = new.cleared_by_diagnostic_id;

  if v_diagnostic.id is null
     or v_diagnostic.user_id <> old.user_id
     or v_diagnostic.query_started_at <= old.placed_at
     or v_diagnostic.observed_at <= old.placed_at
     or v_diagnostic.recorded_at <= old.placed_at
     or new.cleared_at < v_diagnostic.recorded_at
  then
    raise exception 'only a fresh post-hold trusted diagnostic may clear eligibility'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_holds_guard_update
  before update on public.personal_eligibility_holds
  for each row execute function app.guard_personal_hold_update();

create trigger personal_holds_forbid_delete
  before delete or truncate on public.personal_eligibility_holds
  for each statement execute function app.forbid_mutation();

create function app.validate_personal_quarantine_resolution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quarantine public.evidence_quarantines;
begin
  select quarantine.* into v_quarantine
  from public.evidence_quarantines quarantine
  join public.contests contest
    on contest.id = quarantine.contest_id
   and contest.challenge_model = 'personal_accountability'
  where quarantine.id = new.quarantine_id;

  if v_quarantine.id is null
     or v_quarantine.contest_id is distinct from new.challenge_id
     or v_quarantine.user_id is distinct from new.user_id
  then
    raise exception 'personal quarantine resolution must match one personal evidence flag'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from app.personal_evidence_assessments assessment
    where assessment.challenge_id = new.challenge_id
  ) then
    raise exception 'a personal quarantine cannot be resolved after its frozen assessment'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_quarantine_resolutions_validate_insert
  before insert on app.personal_quarantine_resolutions
  for each row execute function app.validate_personal_quarantine_resolution();

create trigger personal_coverage_batches_forbid_mutation
  before update or delete or truncate on public.personal_sync_coverage_batches
  for each statement execute function app.forbid_mutation();

create trigger personal_coverage_buckets_forbid_mutation
  before update or delete or truncate on public.personal_sync_coverage_buckets
  for each statement execute function app.forbid_mutation();

create trigger personal_diagnostics_forbid_mutation
  before update or delete or truncate on public.personal_trusted_diagnostics
  for each statement execute function app.forbid_mutation();

create trigger personal_assessments_forbid_mutation
  before update or delete or truncate on app.personal_evidence_assessments
  for each statement execute function app.forbid_mutation();

create trigger personal_quarantine_resolutions_forbid_mutation
  before update or delete or truncate on app.personal_quarantine_resolutions
  for each statement execute function app.forbid_mutation();

create trigger personal_results_forbid_mutation
  before update or delete or truncate on public.personal_challenge_results
  for each statement execute function app.forbid_mutation();

create trigger personal_creation_requests_forbid_mutation
  before update or delete or truncate on app.personal_challenge_creation_requests
  for each statement execute function app.forbid_mutation();

create trigger personal_cancellation_requests_forbid_mutation
  before update or delete or truncate on app.personal_challenge_cancellation_requests
  for each statement execute function app.forbid_mutation();

create trigger personal_terms_validate_timezone
  before insert on public.personal_challenge_terms
  for each row execute function app.assert_valid_timezone('timezone');

-- ---------------------------------------------------------------------------
-- Trusted upload primitives. The Edge handler verifies the assertion over the
-- exact request bytes; these service-only RPCs atomically consume its counter
-- and persist the digest-bound fact.
-- ---------------------------------------------------------------------------

create function app.consume_trusted_personal_assertion(
  p_user_id    uuid,
  p_key_id     bytea,
  p_sign_count bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_key public.device_attestations;
begin
  if p_key_id is null or p_sign_count is null or p_sign_count <= 0 then
    raise exception 'a trusted personal upload requires an App Attest key and positive counter'
      using errcode = 'invalid_parameter_value';
  end if;

  select device.* into v_key
  from public.device_attestations device
  where device.key_id = p_key_id
  for update;

  if v_key.key_id is null
     or v_key.user_id <> p_user_id
     or v_key.revoked_at is not null
     or not exists (
       select 1
       from app.device_attestation_receipts receipt
       where receipt.key_id = p_key_id
         and receipt.current_receipt_verified_at is not null
     )
  then
    raise exception 'the trusted device assertion could not be accepted'
      using errcode = 'insufficient_privilege';
  end if;

  if p_sign_count <= v_key.sign_count then
    raise exception 'the App Attest assertion counter was already consumed'
      using errcode = 'restrict_violation';
  end if;

  update public.device_attestations device
  set sign_count = p_sign_count,
      last_asserted_at = clock_timestamp()
  where device.key_id = p_key_id;
end;
$$;

-- Mirrors Foundation Calendar.dateInterval(of: .hour, for:). A calendar hour
-- starts by subtracting the instant's local minute/second phase, then spans one
-- elapsed hour. Walking each returned end reproduces both ordinary 23/25-hour
-- DST days and Lord Howe's overlapping half-hour transition keys. This is the
-- sole server definition used by coverage admission, progress, and assessment.
create function app.personal_expected_coverage_buckets_v1(
  p_challenge_id uuid,
  p_as_of        timestamptz
)
returns table (
  bucket_start timestamptz,
  local_day    date,
  local_hour   smallint
)
language sql
stable
security definer
set search_path = ''
as $$
  with recursive context as (
    select
      contest.starts_at,
      contest.ends_at,
      least(contest.ends_at, p_as_of) as completed_end,
      terms.timezone
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.id = p_challenge_id
      and contest.challenge_model = 'personal_accountability'
  ),
  walk as (
    select
      context.starts_at as cursor,
      context.starts_at
        - extract(minute from context.starts_at at time zone context.timezone)
            * interval '1 minute'
        - extract(second from context.starts_at at time zone context.timezone)
            * interval '1 second' as raw_start,
      context.starts_at
        - extract(minute from context.starts_at at time zone context.timezone)
            * interval '1 minute'
        - extract(second from context.starts_at at time zone context.timezone)
            * interval '1 second'
        + interval '1 hour' as raw_end,
      1 as iteration
    from context

    union all

    select
      walk.raw_end,
      walk.raw_end
        - extract(minute from walk.raw_end at time zone context.timezone)
            * interval '1 minute'
        - extract(second from walk.raw_end at time zone context.timezone)
            * interval '1 second',
      walk.raw_end
        - extract(minute from walk.raw_end at time zone context.timezone)
            * interval '1 minute'
        - extract(second from walk.raw_end at time zone context.timezone)
            * interval '1 second'
        + interval '1 hour',
      walk.iteration + 1
    from walk
    cross join context
    where walk.raw_end < context.completed_end
      and walk.iteration < 1000
  )
  select distinct
    walk.raw_start,
    (walk.raw_start at time zone context.timezone)::date,
    extract(hour from walk.raw_start at time zone context.timezone)::smallint
  from walk
  cross join context
  where walk.raw_start >= context.starts_at
    and walk.raw_end <= context.ends_at
    and walk.raw_end <= context.completed_end
  order by walk.raw_start;
$$;

comment on function app.personal_expected_coverage_buckets_v1(uuid, timestamptz) is
  'Authoritative frozen-timezone Calendar-hour keys, including overlapping Lord Howe transition hours.';

-- Foundation Calendar can return overlapping one-hour query intervals when an
-- IANA zone changes by a non-hour offset (for example Australia/Lord_Howe).
-- Until the client uploads explicit non-overlapping interval ends, those weeks
-- cannot safely be assessed as complete because the same HealthKit sample may
-- have contributed to both adjacent buckets.
create function app.personal_has_overlapping_coverage_v1(
  p_challenge_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with ordered as (
    select
      expected.bucket_start,
      lead(expected.bucket_start) over (order by expected.bucket_start)
        as next_bucket_start
    from app.personal_expected_coverage_buckets_v1(
      p_challenge_id,
      'infinity'::timestamptz
    ) expected
  )
  select coalesce(
    bool_or(
      ordered.next_bucket_start
        < ordered.bucket_start + interval '1 hour'
    ),
    false
  )
  from ordered;
$$;

comment on function app.personal_has_overlapping_coverage_v1(uuid) is
  'True when frozen-timezone Calendar-hour query intervals overlap. Complete scoring is fail-closed for these transition windows in Personal V1.';

create function public.record_personal_sync_coverage_v1(
  p_user_id              uuid,
  p_challenge_id         uuid,
  p_client_coverage_id   uuid,
  p_payload_digest       bytea,
  p_observed_at          timestamptz,
  p_covered_bucket_starts jsonb,
  p_key_id               bytea,
  p_sign_count           bigint
)
returns table (coverage_batch_id uuid, replayed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing         public.personal_sync_coverage_batches;
  v_contest          public.contests;
  v_terms            public.personal_challenge_terms;
  v_batch_id         uuid;
  v_bucket_count     integer;
  v_distinct_count   integer;
  v_now              timestamptz;
begin
  perform public.assert_active_actor(p_user_id);

  if p_user_id is null
     or p_challenge_id is null
     or p_client_coverage_id is null
     or p_observed_at is null
     or p_payload_digest is null
     or octet_length(p_payload_digest) <> 32
  then
    raise exception 'coverage identity, finite observed time, and SHA-256 digest are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select coverage.* into v_existing
  from public.personal_sync_coverage_batches coverage
  where coverage.user_id = p_user_id
    and coverage.client_coverage_id = p_client_coverage_id;

  if v_existing.id is not null then
    if v_existing.challenge_id <> p_challenge_id
       or v_existing.payload_digest <> p_payload_digest
    then
      raise exception 'coverage request UUID was already used with different contents'
        using errcode = 'unique_violation';
    end if;
    return query select v_existing.id, true;
    return;
  end if;

  if jsonb_typeof(p_covered_bucket_starts) <> 'array' then
    raise exception 'covered bucket starts must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  v_bucket_count := jsonb_array_length(p_covered_bucket_starts);
  if v_bucket_count not between 1 and 2000 then
    raise exception 'a coverage upload must contain 1 to 2000 bucket starts'
      using errcode = 'invalid_parameter_value';
  end if;

  select count(distinct bucket.value)
    into v_distinct_count
  from jsonb_array_elements_text(p_covered_bucket_starts) bucket(value);

  if v_distinct_count <> v_bucket_count then
    raise exception 'covered bucket starts must be unique'
      using errcode = 'invalid_parameter_value';
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = p_challenge_id
  for update;

  v_now := clock_timestamp();

  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id
    and terms.user_id = p_user_id;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from p_user_id
     or v_contest.status <> 'active'
     or v_terms.challenge_id is null
  then
    raise exception 'coverage is accepted only for the active owner personal challenge'
      using errcode = 'restrict_violation';
  end if;

  if not pg_catalog.isfinite(p_observed_at)
     or p_observed_at < v_contest.starts_at
     or p_observed_at > v_now + interval '1 minute'
     or v_now >= v_terms.evidence_cutoff
  then
    raise exception 'coverage is outside the personal evidence window'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements_text(p_covered_bucket_starts) bucket(value)
    where (bucket.value)::timestamptz < v_contest.starts_at
       or (bucket.value)::timestamptz + interval '1 hour' > v_contest.ends_at
       or (bucket.value)::timestamptz + interval '1 hour'
            > least(p_observed_at, v_now)
       or not exists (
         select 1
         from app.personal_expected_coverage_buckets_v1(
           p_challenge_id,
           least(p_observed_at, v_now)
         ) expected
         where expected.bucket_start = (bucket.value)::timestamptz
       )
  ) then
    raise exception 'coverage may contain only completed expected hourly buckets'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.consume_trusted_personal_assertion(
    p_user_id,
    p_key_id,
    p_sign_count
  );

  -- The device counter lock may have waited across the challenge cutoff.
  -- Re-sample after it; a rejected request rolls the counter update back.
  v_now := clock_timestamp();
  if p_observed_at > v_now + interval '1 minute'
     or v_now >= v_terms.evidence_cutoff
  then
    raise exception 'coverage is outside the personal evidence window'
      using errcode = 'restrict_violation';
  end if;

  insert into public.personal_sync_coverage_batches (
    challenge_id,
    user_id,
    client_coverage_id,
    key_id,
    sign_count,
    payload_digest,
    observed_at,
    covered_bucket_count
  )
  values (
    p_challenge_id,
    p_user_id,
    p_client_coverage_id,
    p_key_id,
    p_sign_count,
    p_payload_digest,
    p_observed_at,
    v_bucket_count
  )
  returning id into v_batch_id;

  insert into public.personal_sync_coverage_buckets (
    coverage_batch_id,
    challenge_id,
    user_id,
    bucket_start
  )
  select
    v_batch_id,
    p_challenge_id,
    p_user_id,
    bucket.value::timestamptz
  from jsonb_array_elements_text(p_covered_bucket_starts) bucket(value);

  return query select v_batch_id, false;
end;
$$;

comment on function public.record_personal_sync_coverage_v1(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) is
  'service_role-only append-only coverage boundary. Every listed hour was queried, including zero-valued hours; App Attest verification occurs before this RPC.';

create function public.record_trusted_personal_diagnostic_v1(
  p_user_id                uuid,
  p_client_diagnostic_id   uuid,
  p_payload_digest         bytea,
  p_observed_at            timestamptz,
  p_query_started_at       timestamptz,
  p_query_ended_at         timestamptz,
  p_trusted_device_sample_count integer,
  p_key_id                 bytea,
  p_sign_count             bigint
)
returns table (
  diagnostic_id uuid,
  performed_at timestamptz,
  replayed boolean,
  cleared_hold boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing       public.personal_trusted_diagnostics;
  v_diagnostic_id  uuid;
  v_performed_at   timestamptz;
  v_now            timestamptz;
  v_rows           integer;
begin
  perform public.assert_active_actor(p_user_id);

  if p_user_id is null
     or p_client_diagnostic_id is null
     or p_payload_digest is null
     or octet_length(p_payload_digest) <> 32
     or p_observed_at is null
     or p_query_started_at is null
     or p_query_ended_at is null
     or p_trusted_device_sample_count is null
  then
    raise exception 'complete diagnostic identity, query window, and SHA-256 digest are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select diagnostic.* into v_existing
  from public.personal_trusted_diagnostics diagnostic
  where diagnostic.user_id = p_user_id
    and diagnostic.client_diagnostic_id = p_client_diagnostic_id;

  if v_existing.id is not null then
    if v_existing.payload_digest <> p_payload_digest then
      raise exception 'diagnostic request UUID was already used with different contents'
        using errcode = 'unique_violation';
    end if;
    return query
      select
        v_existing.id,
        v_existing.recorded_at,
        true,
        exists (
          select 1
          from public.personal_eligibility_holds hold
          where hold.cleared_by_diagnostic_id = v_existing.id
        );
    return;
  end if;

  if not pg_catalog.isfinite(p_observed_at)
     or not pg_catalog.isfinite(p_query_started_at)
     or not pg_catalog.isfinite(p_query_ended_at)
     or p_query_started_at >= p_query_ended_at
     or p_query_ended_at > p_observed_at
     or p_query_started_at < p_observed_at - interval '24 hours'
     or p_trusted_device_sample_count not between 1 and 100000
  then
    raise exception 'a trusted diagnostic must be fresh, bounded, and contain readable HealthKit coverage'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.consume_trusted_personal_assertion(
    p_user_id,
    p_key_id,
    p_sign_count
  );

  -- Freshness is authoritative only after the App Attest counter lock. A
  -- request that waited more than fifteen minutes must not clear a hold.
  v_now := clock_timestamp();
  if p_observed_at < v_now - interval '15 minutes'
     or p_observed_at > v_now + interval '1 minute'
  then
    raise exception 'a trusted diagnostic must be fresh, bounded, and contain readable HealthKit coverage'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.personal_trusted_diagnostics (
    user_id,
    client_diagnostic_id,
    key_id,
    sign_count,
    payload_digest,
    observed_at,
    query_started_at,
    query_ended_at,
    trusted_device_sample_count
  )
  values (
    p_user_id,
    p_client_diagnostic_id,
    p_key_id,
    p_sign_count,
    p_payload_digest,
    p_observed_at,
    p_query_started_at,
    p_query_ended_at,
    p_trusted_device_sample_count
  )
  returning id, recorded_at into v_diagnostic_id, v_performed_at;

  update public.personal_eligibility_holds hold
  set cleared_at = clock_timestamp(),
      cleared_by_diagnostic_id = v_diagnostic_id
  where hold.user_id = p_user_id
    and hold.cleared_at is null
    and p_query_started_at > hold.placed_at;

  get diagnostics v_rows = row_count;

  return query select v_diagnostic_id, v_performed_at, false, v_rows > 0;
end;
$$;

comment on function public.record_trusted_personal_diagnostic_v1(
  uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
  integer, bytea, bigint
) is
  'service_role-only fresh HealthKit/App-Attest diagnostic. A successful post-hold record atomically clears the owner hold.';

-- ---------------------------------------------------------------------------
-- Atomic personal lifecycle
-- ---------------------------------------------------------------------------

create function public.create_personal_challenge_v1(
  request_id                uuid,
  cadence                   public.contest_cadence,
  target_steps              integer,
  commitment_amount_minor   integer,
  timezone                  text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request_id               uuid := $1;
  v_cadence                  public.contest_cadence := $2;
  v_target_steps             integer := $3;
  v_commitment_amount_minor  integer := $4;
  v_timezone                 text := $5;
  v_actor_id                 uuid;
  v_payload_hash             bytea;
  v_existing                 app.personal_challenge_creation_requests;
  v_challenge_id             uuid;
  v_now                      timestamptz;
  v_start_date               date;
  v_starts_at                timestamptz;
  v_ends_at                  timestamptz;
begin
  v_actor_id := app.require_active_caller();
  v_now := clock_timestamp();

  if v_request_id is null then
    raise exception 'request UUID is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_cadence is null then
    raise exception 'cadence is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_target_steps is null or v_target_steps not between 1 and 1000000 then
    raise exception 'target steps must be a whole number from 1 through 1000000'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_commitment_amount_minor not in (1000, 2000, 3000, 4000, 5000) then
    raise exception 'commitment must be one of the five Stage A presets'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names zone
       where zone.name = v_timezone
     )
  then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_accountability_v1',
        'cadence', v_cadence::text,
        'target_steps', v_target_steps,
        'commitment_amount_minor', v_commitment_amount_minor,
        'currency', 'USD',
        'settlement_mode', 'test_only',
        'terms_version', 'personal-v1',
        'timezone', v_timezone
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Exact committed retry precedes mutable eligibility/open-slot checks. The
  -- active-caller lock above still prevents a stale JWT replay after deletion.
  select request.* into v_existing
  from app.personal_challenge_creation_requests request
  where request.actor_id = v_actor_id
    and request.request_id = v_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception 'request UUID already used with different personal terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  if exists (
    select 1
    from public.personal_eligibility_holds hold
    where hold.user_id = v_actor_id
      and hold.cleared_at is null
  ) then
    raise exception 'a fresh trusted diagnostic is required before another challenge'
      using errcode = 'restrict_violation';
  end if;

  v_start_date := (v_now at time zone v_timezone)::date + 1;
  v_starts_at := v_start_date::timestamp at time zone v_timezone;
  v_ends_at := (v_start_date + 7)::timestamp at time zone v_timezone;

  insert into public.contests (
    title,
    group_id,
    created_by,
    challenge_model,
    metric,
    cadence,
    target_value,
    stake_amount_cents,
    tie_break,
    starts_at,
    ends_at,
    max_participants
  )
  values (
    '7-Day Personal Accountability',
    null,
    v_actor_id,
    'personal_accountability',
    'steps',
    v_cadence,
    v_target_steps,
    v_commitment_amount_minor,
    'void',
    v_starts_at,
    v_ends_at,
    1
  )
  returning id into v_challenge_id;

  insert into public.contest_participants (
    contest_id,
    user_id,
    status,
    timezone,
    charity_id
  )
  values (
    v_challenge_id,
    v_actor_id,
    'accepted',
    v_timezone,
    null
  );

  insert into public.personal_challenge_terms (
    challenge_id,
    user_id,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    settlement_mode,
    terms_version,
    timezone,
    agreed_at,
    evidence_cutoff
  )
  values (
    v_challenge_id,
    v_actor_id,
    v_cadence,
    v_target_steps,
    v_commitment_amount_minor,
    'USD',
    'test_only',
    'personal-v1',
    v_timezone,
    v_now,
    v_ends_at + interval '24 hours'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id,
    request_id,
    payload_hash,
    challenge_id
  )
  values (
    v_actor_id,
    v_request_id,
    v_payload_hash,
    v_challenge_id
  );

  return v_challenge_id;
end;
$$;

comment on function public.create_personal_challenge_v1(
  uuid, public.contest_cadence, integer, integer, text
) is
  'Atomic exact-retry Personal V1 creation. Server freezes test-only terms and derives the next local midnight plus seven local dates.';

create function public.cancel_personal_challenge_v1(
  challenge_id uuid,
  request_id   uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_challenge_id  uuid := $1;
  v_request_id    uuid := $2;
  v_actor_id      uuid;
  v_payload_hash  bytea;
  v_existing      app.personal_challenge_cancellation_requests;
  v_contest       public.contests;
  v_now           timestamptz;
begin
  v_actor_id := app.require_active_caller();

  if v_challenge_id is null or v_request_id is null then
    raise exception 'challenge and request UUID are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'cancel_personal_accountability_v1',
        'challenge_id', v_challenge_id
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select request.* into v_existing
  from app.personal_challenge_cancellation_requests request
  where request.actor_id = v_actor_id
    and request.request_id = v_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash <> v_payload_hash
       or v_existing.challenge_id <> v_challenge_id
    then
      raise exception 'request UUID already used for a different cancellation'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = v_challenge_id
  for update;

  -- The boundary is authoritative only after the contest serialization lock.
  -- A request that waited across local midnight cannot inherit a stale time.
  v_now := clock_timestamp();

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from v_actor_id
  then
    raise exception 'personal challenge not found'
      using errcode = 'insufficient_privilege';
  end if;

  if v_contest.status <> 'pending' or v_now >= v_contest.starts_at then
    raise exception 'a personal challenge can be cancelled only before it begins'
      using errcode = 'restrict_violation';
  end if;

  update public.contests contest
  set status = 'cancelled',
      cancellation_reason = 'creator_cancelled',
      cancelled_at = v_now
  where contest.id = v_challenge_id;

  update public.personal_challenge_terms terms
  set closed_at = v_now
  where terms.challenge_id = v_challenge_id
    and terms.user_id = v_actor_id
    and terms.closed_at is null;

  insert into app.personal_challenge_cancellation_requests (
    actor_id,
    request_id,
    payload_hash,
    challenge_id
  )
  values (
    v_actor_id,
    v_request_id,
    v_payload_hash,
    v_challenge_id
  );

  return v_challenge_id;
end;
$$;

comment on function public.cancel_personal_challenge_v1(uuid, uuid) is
  'Owner-only exact-retry cancellation. The server clock, not pending status alone, enforces the pre-start boundary.';

-- ---------------------------------------------------------------------------
-- Owner read models
-- ---------------------------------------------------------------------------

create type public.personal_challenge_card_v1 as (
  challenge_id                 uuid,
  status                       public.contest_status,
  cadence                      public.contest_cadence,
  target_steps                 integer,
  commitment_amount_minor      integer,
  currency                     text,
  settlement_mode              public.personal_settlement_mode,
  terms_version                text,
  timezone                     text,
  agreed_at                    timestamptz,
  starts_at                    timestamptz,
  ends_at                      timestamptz,
  evidence_cutoff              timestamptz,
  closed_at                    timestamptz,
  total_steps                  numeric,
  covered_bucket_count         bigint,
  expected_bucket_count        bigint,
  latest_sync_at               timestamptz,
  daily_progress               jsonb,
  outcome                      public.personal_challenge_outcome,
  outcome_reason               public.personal_result_reason,
  result_published_at          timestamptz,
  eligibility_hold_active      boolean
);

comment on type public.personal_challenge_card_v1 is
  'Stable owner-only Personal V1 read contract shared by list and detail RPCs.';

create function app.personal_result_daily_progress_v1(p_result_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'local_date', day.value ->> 'local_date',
        'trusted_steps', (day.value ->> 'total_steps')::numeric,
        'target_steps', terms.target_steps,
        'evidence_state', case result.evidence_state
          when 'gametime_outage' then 'outage_waived'
          when 'user_device_sync_failure' then 'missing'
          else result.evidence_state::text
        end,
        'met_target', case
          when result.evidence_state = 'complete'
           and terms.cadence = 'daily'
            then (day.value ->> 'total_steps')::numeric >= terms.target_steps
          else null
        end
      )
      order by day.ordinality
    ),
    '[]'::jsonb
  )
  from public.personal_challenge_results result
  join public.personal_challenge_terms terms
    on terms.challenge_id = result.challenge_id
   and terms.user_id = result.user_id
  cross join lateral pg_catalog.jsonb_array_elements(result.daily_totals)
    with ordinality day(value, ordinality)
  where result.id = p_result_id;
$$;

comment on function app.personal_result_daily_progress_v1(uuid) is
  'Renders completed history from the immutable result snapshot so D81 pruning cannot rewrite displayed progress.';

create function app.personal_daily_progress_v1(
  p_challenge_id uuid,
  p_user_id      uuid,
  p_as_of        timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select
      contest.id,
      contest.starts_at,
      contest.ends_at,
      terms.timezone,
      terms.cadence,
      terms.target_steps,
      (contest.starts_at at time zone terms.timezone)::date as first_local_date
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
     and terms.user_id = p_user_id
    where contest.id = p_challenge_id
      and contest.challenge_model = 'personal_accountability'
  ),
  days as (
    select
      base.*,
      base.first_local_date + day_index as local_date,
      (base.first_local_date + day_index)::timestamp
        at time zone base.timezone as day_start,
      (base.first_local_date + day_index + 1)::timestamp
        at time zone base.timezone as day_end
    from base
    cross join generate_series(0, 6) day_index
  ),
  progress as (
    select
      day.local_date,
      day.cadence,
      day.target_steps,
      day.day_start,
      day.day_end,
      coalesce((
        select sum(evidence.value)
        from public.contest_evidence evidence
        where evidence.contest_id = p_challenge_id
          and evidence.user_id = p_user_id
          and evidence.metric = 'steps'
          and evidence.local_day = day.local_date
      ), 0)::numeric(20, 2) as trusted_steps,
      (
        select count(*)
        from app.personal_expected_coverage_buckets_v1(
          p_challenge_id,
          day.ends_at
        ) expected
        where expected.local_day = day.local_date
      )::integer as full_expected_buckets,
      (
        select count(distinct coverage.bucket_start)
        from public.personal_sync_coverage_buckets coverage
        where coverage.challenge_id = p_challenge_id
          and coverage.user_id = p_user_id
          and coverage.bucket_start >= day.day_start
          and coverage.bucket_start < day.day_end
      )::integer as covered_buckets,
      exists (
        select 1
        from public.evidence_quarantines quarantine
        left join app.personal_quarantine_resolutions resolution
          on resolution.quarantine_id = quarantine.id
        where quarantine.contest_id = p_challenge_id
          and quarantine.user_id = p_user_id
          and quarantine.bucket_start >= day.day_start
          and quarantine.bucket_start < day.day_end
          and (
            resolution.id is null
            or resolution.resolution = 'rejected'
          )
      ) as has_quarantine,
      exists (
        select 1
        from (
          select
            expected.bucket_start,
            lead(expected.bucket_start) over (order by expected.bucket_start)
              as next_bucket_start
          from app.personal_expected_coverage_buckets_v1(
            p_challenge_id,
            day.day_end
          ) expected
          where expected.local_day = day.local_date
        ) ordered
        where ordered.next_bucket_start
          < ordered.bucket_start + interval '1 hour'
      ) as has_overlapping_coverage
    from days day
  )
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'local_date', progress.local_date,
        'trusted_steps', progress.trusted_steps,
        'target_steps', progress.target_steps,
        'evidence_state', case
          when p_as_of <= progress.day_start then 'future'
          when p_as_of < progress.day_end then 'in_progress'
          when progress.has_quarantine then 'quarantined'
          when progress.has_overlapping_coverage then 'unresolved'
          when progress.covered_buckets = progress.full_expected_buckets then 'complete'
          else 'incomplete'
        end,
        'met_target', case
          when progress.cadence <> 'daily'
            or p_as_of < progress.day_end
            or progress.has_quarantine
            or progress.has_overlapping_coverage
            or progress.covered_buckets <> progress.full_expected_buckets
          then null
          else progress.trusted_steps >= progress.target_steps
        end
      )
      order by progress.local_date
    ),
    '[]'::jsonb
  )
  from progress;
$$;

create function app.personal_challenge_cards_v1(
  p_user_id      uuid,
  p_challenge_id uuid default null
)
returns setof public.personal_challenge_card_v1
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_as_of timestamptz := clock_timestamp();
begin
  return query
  select
    contest.id,
    contest.status,
    terms.cadence,
    terms.target_steps,
    terms.commitment_amount_minor,
    terms.currency,
    terms.settlement_mode,
    terms.terms_version,
    terms.timezone,
    terms.agreed_at,
    contest.starts_at,
    contest.ends_at,
    terms.evidence_cutoff,
    terms.closed_at,
    coalesce(result.total_steps, progress.total_steps, 0)::numeric,
    case
      when result.id is not null then assessment.covered_buckets::bigint
      else coalesce(coverage.covered_bucket_count, 0)::bigint
    end,
    case
      when result.id is not null then assessment.full_expected_buckets::bigint
      else coalesce(expected.expected_bucket_count, 0)::bigint
    end,
    coverage.latest_sync_at,
    case
      when result.id is not null
        then app.personal_result_daily_progress_v1(result.id)
      else app.personal_daily_progress_v1(contest.id, p_user_id, v_as_of)
    end,
    result.outcome,
    result.reason,
    result.published_at,
    exists (
      select 1
      from public.personal_eligibility_holds hold
      where hold.user_id = p_user_id
        and hold.cleared_at is null
    )
  from public.personal_challenge_terms terms
  join public.contests contest
    on contest.id = terms.challenge_id
   and contest.challenge_model = 'personal_accountability'
  left join public.personal_challenge_results result
    on result.challenge_id = contest.id
  left join app.personal_evidence_assessments assessment
    on assessment.id = result.assessment_id
  left join lateral (
    select sum(evidence.value)::numeric(20, 2) as total_steps
    from public.contest_evidence evidence
    where evidence.contest_id = contest.id
      and evidence.user_id = p_user_id
      and evidence.metric = 'steps'
  ) progress on true
  left join lateral (
    select
      count(distinct bucket.bucket_start)::bigint as covered_bucket_count,
      max(batch.observed_at) as latest_sync_at
    from public.personal_sync_coverage_buckets bucket
    join public.personal_sync_coverage_batches batch
      on batch.id = bucket.coverage_batch_id
    where bucket.challenge_id = contest.id
      and bucket.user_id = p_user_id
      and bucket.bucket_start + interval '1 hour'
            <= least(v_as_of, contest.ends_at)
  ) coverage on true
  left join lateral (
    select count(*)::bigint as expected_bucket_count
    from app.personal_expected_coverage_buckets_v1(
      contest.id,
      v_as_of
    ) expected_bucket
  ) expected on true
  where terms.user_id = p_user_id
    and (p_challenge_id is null or contest.id = p_challenge_id)
  order by
    case contest.status
      when 'active' then 0
      when 'pending' then 1
      else 2
    end,
    contest.starts_at desc,
    contest.id;
end;
$$;

create function public.list_my_accountability_challenges_v1()
returns setof public.personal_challenge_card_v1
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  v_user_id := app.require_active_caller();
  return query
  select * from app.personal_challenge_cards_v1(v_user_id, null);
end;
$$;

create function public.get_my_accountability_challenge_v1(challenge_id uuid)
returns setof public.personal_challenge_card_v1
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id      uuid;
  v_challenge_id uuid := $1;
begin
  v_user_id := app.require_active_caller();
  return query
  select * from app.personal_challenge_cards_v1(v_user_id, v_challenge_id);
end;
$$;

create function public.get_my_personal_eligibility_v1()
returns table (
  eligible              boolean,
  hold_id               uuid,
  hold_reason           public.personal_eligibility_hold_reason,
  held_at               timestamptz,
  challenge_id          uuid,
  latest_diagnostic_id  uuid,
  latest_diagnostic_observed_at timestamptz,
  latest_diagnostic_recorded_at timestamptz,
  latest_diagnostic_trusted_device_sample_count integer,
  latest_diagnostic_cleared_hold boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  v_user_id := app.require_active_caller();
  return query
  select
    hold.id is null,
    hold.id,
    hold.reason,
    hold.placed_at,
    hold.challenge_id,
    latest_diagnostic.id,
    latest_diagnostic.observed_at,
    latest_diagnostic.recorded_at,
    latest_diagnostic.trusted_device_sample_count,
    coalesce(latest_diagnostic.cleared_hold, false)
  from (select 1) singleton
  left join public.personal_eligibility_holds hold
    on hold.user_id = v_user_id
   and hold.cleared_at is null
  left join lateral (
    select
      diagnostic.id,
      diagnostic.observed_at,
      diagnostic.recorded_at,
      diagnostic.trusted_device_sample_count,
      exists (
        select 1
        from public.personal_eligibility_holds cleared_hold
        where cleared_hold.cleared_by_diagnostic_id = diagnostic.id
      ) as cleared_hold
    from public.personal_trusted_diagnostics diagnostic
    where diagnostic.user_id = v_user_id
    order by diagnostic.recorded_at desc, diagnostic.id desc
    limit 1
  ) latest_diagnostic on true;
end;
$$;

comment on function public.get_my_personal_eligibility_v1() is
  'Owner-only eligibility plus the latest trusted diagnostic needed to restore diagnostic state after relaunch.';

-- ---------------------------------------------------------------------------
-- Model-dispatched activation and evidence admission
-- ---------------------------------------------------------------------------

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
  v_contest              record;
  v_accepted             integer;
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
      select contest.id, contest.challenge_model
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

      if (
        v_contest.challenge_model = 'personal_accountability'
        and v_accepted = 1
      ) or (
        v_contest.challenge_model <> 'personal_accountability'
        and v_accepted >= 2
      ) then
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

        if v_contest.challenge_model = 'personal_accountability' then
          update public.personal_challenge_terms terms
          set closed_at = p_now
          where terms.challenge_id = v_contest.id
            and terms.closed_at is null;
        end if;

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

comment on function app.activate_due_contests(timestamptz) is
  'Contest-first cron dispatcher. Personal activates with its one owner; both social models retain the legacy quorum of two.';

create or replace function app.prepare_metric_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status            public.contest_participant_status;
  v_initial_timezone  text;
  v_timezone          text;
  v_contest_status    public.contest_status;
  v_challenge_model   public.challenge_model;
  v_starts_at         timestamptz;
  v_ends_at           timestamptz;
  v_evidence_cutoff   timestamptz;
  v_local             timestamp;
  v_highest           numeric(12, 2);
begin
  select
    participant.status,
    participant.timezone,
    contest.status,
    contest.challenge_model,
    contest.starts_at,
    contest.ends_at,
    case
      when contest.challenge_model = 'personal_accountability'
        then terms.evidence_cutoff
      else contest.ends_at + app.ingest_grace_period()
    end
    into
      v_status,
      v_initial_timezone,
      v_contest_status,
      v_challenge_model,
      v_starts_at,
      v_ends_at,
      v_evidence_cutoff
  from public.contest_participants participant
  join public.contests contest
    on contest.id = participant.contest_id
  left join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
   and terms.user_id = participant.user_id
  where participant.contest_id = new.contest_id
    and participant.user_id = new.user_id
  for key share of participant;

  if v_status is null then
    raise exception 'no roster row for user % on contest %', new.user_id, new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_status <> 'accepted' then
    raise exception 'only an accepted participant may record evidence (status %)', v_status
      using errcode = 'restrict_violation';
  end if;

  if v_contest_status <> 'active' then
    raise exception 'contest % is not accepting evidence (status %)',
      new.contest_id, v_contest_status
      using errcode = 'restrict_violation';
  end if;

  if v_evidence_cutoff is null or now() >= v_evidence_cutoff then
    raise exception 'the ingest window for contest % is closed', new.contest_id
      using errcode = 'restrict_violation';
  end if;

  if v_challenge_model = 'personal_accountability' then
    if new.metric <> 'steps' then
      raise exception 'personal accountability accepts steps evidence only'
        using errcode = 'restrict_violation';
    end if;

    if new.provenance <> 'device' then
      raise exception 'personal accountability accepts first-party device evidence only'
        using errcode = 'restrict_violation';
    end if;
  end if;

  if new.bucket_start < v_starts_at
     or new.bucket_start + interval '1 hour' > v_ends_at
  then
    raise exception 'bucket % is outside the window of contest % (% to %)',
      new.bucket_start, new.contest_id, v_starts_at, v_ends_at
      using errcode = 'invalid_parameter_value';
  end if;

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

  v_local := new.bucket_start at time zone v_timezone;

  if v_challenge_model = 'personal_accountability' then
    if not exists (
      select 1
      from app.personal_expected_coverage_buckets_v1(
        new.contest_id,
        new.bucket_start + interval '1 hour'
      ) expected
      where expected.bucket_start = new.bucket_start
    ) then
      raise exception 'bucket % is not an expected frozen-timezone Calendar hour',
        new.bucket_start
        using errcode = 'invalid_parameter_value';
    end if;
  elsif v_local <> date_trunc('hour', v_local) then
    raise exception 'bucket % is not aligned to a whole hour in % (local %)',
      new.bucket_start, v_timezone, v_local
      using errcode = 'invalid_parameter_value';
  end if;

  new.local_day  := v_local::date;
  new.local_hour := extract(hour from v_local)::smallint;

  select max(snapshot.value) into v_highest
  from public.metric_snapshots snapshot
  where snapshot.contest_id = new.contest_id
    and snapshot.user_id = new.user_id
    and snapshot.metric = new.metric
    and snapshot.bucket_start = new.bucket_start
    and snapshot.provenance = new.provenance;

  if v_highest is not null and new.value < v_highest then
    raise exception 'bucket % of % from % already stands at %; a figure cannot be revised down to %',
      new.bucket_start, new.metric, new.provenance, v_highest, new.value
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.prepare_metric_snapshot() is
  'Model-aware evidence admission. Legacy keeps six-hour/local-hour behavior; personal accepts steps through its frozen 24-hour cutoff and authoritative Calendar-hour keys.';

-- ---------------------------------------------------------------------------
-- Service-only personal assessment and result publication
-- ---------------------------------------------------------------------------

create function public.resolve_personal_evidence_quarantine_v1(
  p_quarantine_id   uuid,
  p_request_id      uuid,
  p_resolution      public.personal_quarantine_resolution,
  p_reason_code     text,
  p_evidence_digest bytea
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quarantine public.evidence_quarantines;
  v_model      public.challenge_model;
  v_existing   app.personal_quarantine_resolutions;
  v_id         uuid;
begin
  if p_quarantine_id is null
     or p_request_id is null
     or p_resolution is null
     or p_reason_code is null
     or char_length(p_reason_code) not between 1 and 80
     or p_reason_code !~ '^[a-z0-9][a-z0-9_]*$'
     or p_evidence_digest is null
     or octet_length(p_evidence_digest) <> 32
  then
    raise exception 'personal quarantine, request, resolution, bounded reason code, and SHA-256 digest are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The quarantine lock serializes exact retries and competing operator
  -- decisions. A resolution can never be revised after the fact.
  select quarantine.*
    into v_quarantine
  from public.evidence_quarantines quarantine
  where quarantine.id = p_quarantine_id
  for update of quarantine;

  select contest.challenge_model into v_model
  from public.contests contest
  where contest.id = v_quarantine.contest_id;

  if v_quarantine.id is null
     or v_model <> 'personal_accountability'
  then
    raise exception 'personal evidence quarantine not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select resolution.* into v_existing
  from app.personal_quarantine_resolutions resolution
  where resolution.request_id = p_request_id
     or resolution.quarantine_id = p_quarantine_id
  order by (resolution.quarantine_id = p_quarantine_id) desc
  limit 1;

  if v_existing.id is not null then
    if v_existing.quarantine_id <> p_quarantine_id
       or v_existing.request_id <> p_request_id
       or v_existing.resolution <> p_resolution
       or v_existing.reason_code <> p_reason_code
       or v_existing.evidence_digest <> p_evidence_digest
    then
      raise exception 'personal quarantine already has a different terminal resolution or request collision'
        using errcode = 'unique_violation';
    end if;
    return v_existing.id;
  end if;

  insert into app.personal_quarantine_resolutions (
    quarantine_id,
    challenge_id,
    user_id,
    request_id,
    resolution,
    reason_code,
    evidence_digest
  ) values (
    v_quarantine.id,
    v_quarantine.contest_id,
    v_quarantine.user_id,
    p_request_id,
    p_resolution,
    p_reason_code,
    p_evidence_digest
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.resolve_personal_evidence_quarantine_v1(
  uuid, uuid, public.personal_quarantine_resolution, text, bytea
) is
  'service_role-only append-only and exact-retry-idempotent Personal V1 flag resolution. Cleared flags may be assessed; rejected or absent decisions fail closed.';

create function public.record_personal_assessment_v1(
  p_challenge_id       uuid,
  p_request_id         uuid,
  p_evidence_state     public.personal_evidence_state,
  p_assessment_version text,
  p_evidence_digest    bytea,
  p_outage_reference   text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest          public.contests;
  v_terms            public.personal_challenge_terms;
  v_existing         app.personal_evidence_assessments;
  v_assessment_id    uuid;
  v_full_expected    integer;
  v_covered          integer;
  v_total_steps      numeric(20, 2);
  v_daily_totals     jsonb;
begin
  if p_challenge_id is null
     or p_request_id is null
     or p_evidence_state is null
     or p_assessment_version <> 'personal-v1'
     or p_evidence_digest is null
     or octet_length(p_evidence_digest) <> 32
  then
    raise exception 'personal-v1 assessment identity, state, version, and SHA-256 digest are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = p_challenge_id
  for update;

  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_terms.challenge_id is null
  then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select assessment.* into v_existing
  from app.personal_evidence_assessments assessment
  where assessment.challenge_id = p_challenge_id;

  if v_existing.id is not null then
    if v_existing.request_id <> p_request_id
       or v_existing.evidence_state <> p_evidence_state
       or v_existing.assessment_version <> p_assessment_version
       or v_existing.evidence_digest <> p_evidence_digest
       or v_existing.outage_reference is distinct from p_outage_reference
    then
      raise exception 'personal challenge already has a different frozen assessment'
        using errcode = 'unique_violation';
    end if;
    return v_existing.id;
  end if;

  if v_contest.status <> 'active' then
    raise exception 'only an active personal challenge may be assessed'
      using errcode = 'restrict_violation';
  end if;

  if clock_timestamp() < v_terms.evidence_cutoff then
    raise exception 'personal assessment must wait for the 24-hour evidence cutoff'
      using errcode = 'restrict_violation';
  end if;

  if (p_evidence_state = 'gametime_outage') <> (p_outage_reference is not null)
     or (
       p_outage_reference is not null
       and char_length(p_outage_reference) not between 1 and 240
     )
  then
    raise exception 'GameTime outage assessments require one bounded service-owned reference'
      using errcode = 'invalid_parameter_value';
  end if;

  select count(*)::integer into v_full_expected
  from app.personal_expected_coverage_buckets_v1(
    p_challenge_id,
    v_contest.ends_at
  ) expected;

  select count(distinct coverage.bucket_start)::integer into v_covered
  from public.personal_sync_coverage_buckets coverage
  where coverage.challenge_id = p_challenge_id
    and coverage.user_id = v_terms.user_id;

  select coalesce(sum(evidence.value), 0)::numeric(20, 2)
    into v_total_steps
  from public.contest_evidence evidence
  where evidence.contest_id = p_challenge_id
    and evidence.user_id = v_terms.user_id
    and evidence.metric = 'steps';

  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'local_date', day.local_date,
      'total_steps', coalesce(day.total_steps, 0)::numeric(20, 2)
    )
    order by day.local_date
  )
    into v_daily_totals
  from (
    select
      first_day.local_date + day_index as local_date,
      (
        select sum(evidence.value)
        from public.contest_evidence evidence
        where evidence.contest_id = p_challenge_id
          and evidence.user_id = v_terms.user_id
          and evidence.metric = 'steps'
          and evidence.local_day = first_day.local_date + day_index
      ) as total_steps
    from (
      select (v_contest.starts_at at time zone v_terms.timezone)::date
        as local_date
    ) first_day
    cross join generate_series(0, 6) day_index
  ) day;

  if p_evidence_state = 'complete' then
    if app.personal_has_overlapping_coverage_v1(p_challenge_id) then
      raise exception 'overlapping Calendar-hour intervals cannot be assessed as complete in Personal V1; publish the fail-closed GameTime outage waiver'
        using errcode = 'restrict_violation';
    end if;

    if v_covered <> v_full_expected then
      raise exception 'complete evidence requires trusted coverage for every expected Calendar hour'
        using errcode = 'restrict_violation';
    end if;

    if exists (
      select 1
      from public.evidence_quarantines quarantine
      left join app.personal_quarantine_resolutions resolution
        on resolution.quarantine_id = quarantine.id
      where quarantine.contest_id = p_challenge_id
        and (
          resolution.id is null
          or resolution.resolution = 'rejected'
        )
    ) then
      raise exception 'unresolved or rejected personal evidence cannot be assessed as complete'
        using errcode = 'restrict_violation';
    end if;

    if exists (
      select 1
      from public.metric_snapshots snapshot
      join public.ingest_batches batch
        on batch.id = snapshot.batch_id
      where snapshot.contest_id = p_challenge_id
        and not batch.attested
    ) then
      raise exception 'complete personal evidence cannot depend on unattested metric batches'
        using errcode = 'restrict_violation';
    end if;
  end if;

  insert into app.personal_evidence_assessments (
    challenge_id,
    user_id,
    request_id,
    evidence_state,
    evidence_cutoff,
    assessment_version,
    evidence_digest,
    full_expected_buckets,
    covered_buckets,
    total_steps,
    daily_totals,
    outage_reference
  )
  values (
    p_challenge_id,
    v_terms.user_id,
    p_request_id,
    p_evidence_state,
    v_terms.evidence_cutoff,
    p_assessment_version,
    p_evidence_digest,
    v_full_expected,
    v_covered,
    v_total_steps,
    v_daily_totals,
    p_outage_reference
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$$;

comment on function public.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) is
  'service_role-only immutable personal-v1 assessment. Complete requires full trusted Calendar-hour coverage, attested evidence, and a cleared decision for every personal evidence flag.';

create function public.publish_personal_result_v1(
  p_challenge_id uuid,
  p_assessment_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest       public.contests;
  v_terms         public.personal_challenge_terms;
  v_assessment    app.personal_evidence_assessments;
  v_existing      public.personal_challenge_results;
  v_result_id     uuid;
  v_outcome       public.personal_challenge_outcome;
  v_reason        public.personal_result_reason;
  v_waived        boolean;
  v_published_at  timestamptz;
  v_met           boolean;
begin
  if p_challenge_id is null or p_assessment_id is null then
    raise exception 'challenge and assessment UUID are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = p_challenge_id
  for update;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
  then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select result.* into v_existing
  from public.personal_challenge_results result
  where result.challenge_id = p_challenge_id;

  if v_existing.id is not null then
    if v_existing.assessment_id <> p_assessment_id then
      raise exception 'personal challenge already has a different terminal result'
        using errcode = 'unique_violation';
    end if;
    return v_existing.id;
  end if;

  v_published_at := clock_timestamp();

  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  select assessment.* into v_assessment
  from app.personal_evidence_assessments assessment
  where assessment.id = p_assessment_id
    and assessment.challenge_id = p_challenge_id;

  if v_contest.status <> 'active'
     or v_terms.challenge_id is null
     or v_assessment.id is null
     or v_assessment.evidence_cutoff <> v_terms.evidence_cutoff
     or v_published_at < v_terms.evidence_cutoff
  then
    raise exception 'a matching post-cutoff active personal assessment is required'
      using errcode = 'restrict_violation';
  end if;

  if v_assessment.evidence_state = 'complete' then
    if v_terms.cadence = 'daily' then
      select not exists (
        select 1
        from jsonb_array_elements(v_assessment.daily_totals) day
        where (day ->> 'total_steps')::numeric < v_terms.target_steps
      ) into v_met;

      v_outcome := case
        when v_met then 'met_goal'::public.personal_challenge_outcome
        else 'missed_goal'::public.personal_challenge_outcome
      end;
      v_reason := case
        when v_met then 'target_reached'::public.personal_result_reason
        else 'target_missed'::public.personal_result_reason
      end;
    else
      v_met := v_assessment.total_steps >= v_terms.target_steps;
      v_outcome := case
        when v_met then 'met_goal'::public.personal_challenge_outcome
        else 'missed_goal'::public.personal_challenge_outcome
      end;
      v_reason := case
        when v_met then 'target_reached'::public.personal_result_reason
        else 'target_missed'::public.personal_result_reason
      end;
    end if;
    v_waived := false;
  else
    v_outcome := 'inconclusive';
    v_reason := case v_assessment.evidence_state
      when 'missing' then 'missing_coverage'::public.personal_result_reason
      when 'quarantined' then 'quarantined_evidence'::public.personal_result_reason
      when 'conflicting' then 'conflicting_evidence'::public.personal_result_reason
      when 'unresolved' then 'unresolved_evidence'::public.personal_result_reason
      when 'user_device_sync_failure' then 'user_device_sync_failure'::public.personal_result_reason
      when 'gametime_outage' then 'gametime_outage'::public.personal_result_reason
      else 'unresolved_evidence'::public.personal_result_reason
    end;
    v_waived := true;
  end if;

  insert into public.personal_challenge_results (
    challenge_id,
    user_id,
    assessment_id,
    outcome,
    reason,
    evidence_state,
    evidence_cutoff,
    total_steps,
    daily_totals,
    commitment_waived,
    published_at
  )
  values (
    p_challenge_id,
    v_terms.user_id,
    p_assessment_id,
    v_outcome,
    v_reason,
    v_assessment.evidence_state,
    v_assessment.evidence_cutoff,
    v_assessment.total_steps,
    v_assessment.daily_totals,
    v_waived,
    v_published_at
  )
  returning id into v_result_id;

  update public.contests contest
  set status = 'finalized'
  where contest.id = p_challenge_id;

  update public.personal_challenge_terms terms
  set closed_at = v_published_at
  where terms.challenge_id = p_challenge_id
    and terms.closed_at is null;

  -- Stage A has no payment, dispute, or review child workflow. Close the
  -- contest lineage at publication; D81 derives the operator/retention horizon
  -- from raw-evidence-retention-v1 and keeps any explicit scoped hold longer.
  perform public.set_workflow_retention_state(
    'contest_lineage',
    p_challenge_id,
    false,
    v_published_at,
    v_published_at,
    'raw-evidence-retention-v1'
  );

  if v_assessment.evidence_state = 'user_device_sync_failure'
     and exists (
       select 1
       from public.profiles profile
       where profile.id = v_terms.user_id
         and profile.deleted_at is null
     )
  then
    insert into public.personal_eligibility_holds (
      user_id,
      challenge_id,
      result_id,
      reason,
      placed_at
    )
    values (
      v_terms.user_id,
      p_challenge_id,
      v_result_id,
      'user_device_sync_failure',
      v_published_at
    );
  end if;

  return v_result_id;
end;
$$;

comment on function public.publish_personal_result_v1(uuid, uuid) is
  'service_role-only personal result publisher. It creates no standings, winner, charity, payout, or donation obligation.';

-- ---------------------------------------------------------------------------
-- Personal evidence never enters the inherited peer-review/finalizer path.
-- A personal quarantine may remain as an internal flagged-evidence fact, but
-- only the service-owned personal assessment above decides its outcome.
-- ---------------------------------------------------------------------------

create function app.reject_personal_legacy_contest_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.contests contest
    where contest.id = new.contest_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'personal accountability is isolated from legacy integrity review'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create function app.reject_personal_peer_review_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.id = new.quarantine_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'personal accountability evidence has no peer-review vote'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger contest_integrity_assessments_reject_personal
  before insert on app.contest_integrity_assessments
  for each row execute function app.reject_personal_legacy_contest_row();

create trigger quarantine_adjudications_reject_personal
  before insert on app.evidence_quarantine_adjudications
  for each row execute function app.reject_personal_legacy_contest_row();

create trigger quarantine_adjudication_events_reject_personal
  before insert on app.evidence_quarantine_adjudication_events
  for each row execute function app.reject_personal_legacy_contest_row();

create trigger quarantine_peer_reviews_reject_personal
  before insert on public.evidence_quarantine_reviews
  for each row execute function app.reject_personal_peer_review_row();

-- Preserve the mature legacy loader unchanged behind a private-to-Data-API
-- implementation name. The public contract now rejects personal contests
-- before acquiring the social assessment locks.
alter function public.load_contest_integrity_input_v1(uuid)
  rename to load_legacy_contest_integrity_input_v1;

create function public.load_contest_integrity_input_v1(p_contest_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.contests contest
    where contest.id = p_contest_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'personal accountability uses its dedicated evidence assessment'
      using errcode = 'restrict_violation';
  end if;

  return public.load_legacy_contest_integrity_input_v1(p_contest_id);
end;
$$;

-- Keep every mature D76 rule for legacy contests, while closing the callable
-- peer-review surface categorically for Personal V1.
alter function public.review_evidence_quarantine(uuid, boolean)
  rename to review_legacy_evidence_quarantine;

create function public.review_evidence_quarantine(
  p_quarantine_id uuid,
  p_approved boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.id = p_quarantine_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'quarantine not found'
      using errcode = 'insufficient_privilege';
  end if;

  perform public.review_legacy_evidence_quarantine(
    p_quarantine_id,
    p_approved
  );
end;
$$;

-- The subject-facing legacy peer-state and resolution endpoints are also
-- empty for personal rows. Personal progress/result RPCs are their sole UI
-- contract, so a one-person challenge can never appear to await a peer vote.
alter function public.list_my_evidence_quarantines(uuid)
  rename to list_my_legacy_evidence_quarantines;

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
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.contests contest
    where contest.id = p_contest_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    perform app.require_active_caller();
    return;
  end if;

  return query
  select * from public.list_my_legacy_evidence_quarantines(p_contest_id);
end;
$$;

alter function public.get_evidence_quarantine_resolution_v1(uuid)
  rename to get_legacy_evidence_quarantine_resolution_v1;

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
begin
  if exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.id = p_quarantine_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    perform app.require_active_caller();
    return;
  end if;

  return query
  select *
  from public.get_legacy_evidence_quarantine_resolution_v1(p_quarantine_id);
end;
$$;

revoke all on function public.load_legacy_contest_integrity_input_v1(uuid),
                       public.review_legacy_evidence_quarantine(uuid, boolean),
                       public.list_my_legacy_evidence_quarantines(uuid),
                       public.get_legacy_evidence_quarantine_resolution_v1(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.load_contest_integrity_input_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.load_contest_integrity_input_v1(uuid)
  to service_role;

revoke all on function public.review_evidence_quarantine(uuid, boolean),
                       public.list_my_evidence_quarantines(uuid),
                       public.get_evidence_quarantine_resolution_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.review_evidence_quarantine(uuid, boolean),
                          public.list_my_evidence_quarantines(uuid),
                          public.get_evidence_quarantine_resolution_v1(uuid)
  to authenticated;

-- The legacy operator clearance endpoint is also categorically closed for
-- personal flags. Operators must use the digest-bound personal resolution RPC.
alter function public.clear_evidence_quarantine_v1(uuid, uuid)
  rename to clear_legacy_evidence_quarantine_v1;

create function public.clear_evidence_quarantine_v1(
  p_request_id uuid,
  p_quarantine_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.id = p_quarantine_id
      and contest.challenge_model = 'personal_accountability'
  ) then
    raise exception 'personal accountability uses its dedicated quarantine resolution'
      using errcode = 'restrict_violation';
  end if;

  return public.clear_legacy_evidence_quarantine_v1(
    p_request_id,
    p_quarantine_id
  );
end;
$$;

revoke all on function public.clear_legacy_evidence_quarantine_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.clear_evidence_quarantine_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.clear_evidence_quarantine_v1(uuid, uuid)
  to service_role;

-- Keep the legacy timer intact while filtering on the immutable model before
-- either peer escalation or social timeout finalization can be attempted.
create or replace function app.process_evidence_quarantine_deadlines_at(
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
     and contest.challenge_model <> 'personal_accountability'
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
       and contest.challenge_model <> 'personal_accountability'
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

comment on function app.process_evidence_quarantine_deadlines_at(
  timestamptz, integer
) is
  'Legacy quarantine deadline worker. Personal accountability flags are skipped and terminate only through the personal assessment/result path.';

revoke all on function app.reject_personal_legacy_contest_row(),
                       app.reject_personal_peer_review_row()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Owner-only RLS and explicit API grants
-- ---------------------------------------------------------------------------

alter table public.personal_challenge_terms enable row level security;
alter table public.personal_sync_coverage_batches enable row level security;
alter table public.personal_sync_coverage_buckets enable row level security;
alter table public.personal_trusted_diagnostics enable row level security;
alter table public.personal_challenge_results enable row level security;
alter table public.personal_eligibility_holds enable row level security;
alter table app.personal_challenge_creation_requests enable row level security;
alter table app.personal_challenge_cancellation_requests enable row level security;
alter table app.personal_evidence_assessments enable row level security;
alter table app.personal_quarantine_resolutions enable row level security;

create policy personal_terms_select_owner
  on public.personal_challenge_terms
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy personal_coverage_batches_select_owner
  on public.personal_sync_coverage_batches
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy personal_coverage_buckets_select_owner
  on public.personal_sync_coverage_buckets
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy personal_diagnostics_select_owner
  on public.personal_trusted_diagnostics
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy personal_results_select_owner
  on public.personal_challenge_results
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy personal_holds_select_owner
  on public.personal_eligibility_holds
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

revoke all on table public.personal_challenge_terms,
                    public.personal_sync_coverage_batches,
                    public.personal_sync_coverage_buckets,
                    public.personal_trusted_diagnostics,
                    public.personal_challenge_results,
                    public.personal_eligibility_holds
  from public, anon, authenticated, service_role;

grant select on table public.personal_challenge_terms,
                      public.personal_sync_coverage_batches,
                      public.personal_sync_coverage_buckets,
                      public.personal_trusted_diagnostics,
                      public.personal_challenge_results,
                      public.personal_eligibility_holds
  to authenticated;

revoke all on table app.personal_challenge_creation_requests,
                    app.personal_challenge_cancellation_requests,
                    app.personal_evidence_assessments,
                    app.personal_quarantine_resolutions
  from public, anon, authenticated, service_role;

revoke all on function app.validate_personal_terms(),
                       app.guard_personal_terms_update(),
                       app.close_personal_terms_on_terminal_contest(),
                       app.guard_personal_hold_update(),
                       app.validate_personal_quarantine_resolution(),
                       app.consume_trusted_personal_assertion(uuid, bytea, bigint),
                       app.personal_expected_coverage_buckets_v1(uuid, timestamptz),
                       app.personal_has_overlapping_coverage_v1(uuid),
                       app.personal_result_daily_progress_v1(uuid),
                       app.personal_daily_progress_v1(uuid, uuid, timestamptz),
                       app.personal_challenge_cards_v1(uuid, uuid),
                       app.prepare_metric_snapshot()
  from public, anon, authenticated, service_role;

revoke all on function public.create_personal_challenge_v1(
                         uuid,
                         public.contest_cadence,
                         integer,
                         integer,
                         text
                       ),
                       public.cancel_personal_challenge_v1(uuid, uuid),
                       public.list_my_accountability_challenges_v1(),
                       public.get_my_accountability_challenge_v1(uuid),
                       public.get_my_personal_eligibility_v1(),
                       public.record_personal_sync_coverage_v1(
                         uuid,
                         uuid,
                         uuid,
                         bytea,
                         timestamptz,
                         jsonb,
                         bytea,
                         bigint
                       ),
                       public.record_trusted_personal_diagnostic_v1(
                         uuid,
                         uuid,
                         bytea,
                         timestamptz,
                         timestamptz,
                         timestamptz,
                         integer,
                         bytea,
                         bigint
                       ),
                       public.resolve_personal_evidence_quarantine_v1(
                         uuid,
                         uuid,
                         public.personal_quarantine_resolution,
                         text,
                         bytea
                       ),
                       public.record_personal_assessment_v1(
                         uuid,
                         uuid,
                         public.personal_evidence_state,
                         text,
                         bytea,
                         text
                       ),
                       public.publish_personal_result_v1(uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.create_personal_challenge_v1(
                           uuid,
                           public.contest_cadence,
                           integer,
                           integer,
                           text
                         ),
                         public.cancel_personal_challenge_v1(uuid, uuid),
                         public.list_my_accountability_challenges_v1(),
                         public.get_my_accountability_challenge_v1(uuid),
                         public.get_my_personal_eligibility_v1()
  to authenticated;

grant execute on function public.record_personal_sync_coverage_v1(
                           uuid,
                           uuid,
                           uuid,
                           bytea,
                           timestamptz,
                           jsonb,
                           bytea,
                           bigint
                         ),
                         public.record_trusted_personal_diagnostic_v1(
                           uuid,
                           uuid,
                           bytea,
                           timestamptz,
                           timestamptz,
                           timestamptz,
                           integer,
                         bytea,
                         bigint
                       ),
                         public.resolve_personal_evidence_quarantine_v1(
                           uuid,
                           uuid,
                           public.personal_quarantine_resolution,
                           text,
                           bytea
                         ),
                         public.record_personal_assessment_v1(
                           uuid,
                           uuid,
                           public.personal_evidence_state,
                           text,
                           bytea,
                           text
                         ),
                         public.publish_personal_result_v1(uuid, uuid),
                         app.activate_due_contests(timestamptz)
  to service_role;
