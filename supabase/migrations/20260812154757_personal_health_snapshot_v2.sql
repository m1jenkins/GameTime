-- Automatic Apple Health daily snapshots for Personal accountability.
--
-- This is a forward-compatible support migration. It installs the v2 policy,
-- authenticated snapshot boundary, clean read contracts, policy-dispatched
-- result worker, and an explicit service-only cutover operation. It does not
-- migrate an existing challenge and it leaves the result-worker cron dormant.

begin;

-- ==========================================================================
-- Frozen policy and opaque terms identity
-- ==========================================================================

create type public.personal_step_data_policy as enum (
  'attested_hourly_v1',
  'healthkit_nonmanual_daily_v1'
);

alter table public.personal_challenge_terms
  add column step_data_policy public.personal_step_data_policy
    not null default 'attested_hourly_v1';

comment on column public.personal_challenge_terms.step_data_policy is
  'Frozen scoring input policy. Historical rows remain attested_hourly_v1; automatic Apple Health daily snapshots use healthkit_nonmanual_daily_v1.';

create function app.personal_terms_fingerprint_v2(p_challenge_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'schema_version', 'personal-terms-fingerprint-v2',
          'challenge_id', contest.id::text,
          'owner_id', terms.user_id::text,
          'cadence', terms.cadence::text,
          'target_steps', terms.target_steps,
          'commitment_amount_minor', terms.commitment_amount_minor,
          'currency', terms.currency,
          'settlement_mode', terms.settlement_mode::text,
          'terms_version', terms.terms_version,
          'timezone', terms.timezone,
          'agreed_at_us',
            (extract(epoch from terms.agreed_at) * 1000000)::bigint,
          'starts_at_us',
            (extract(epoch from contest.starts_at) * 1000000)::bigint,
          'ends_at_us',
            (extract(epoch from contest.ends_at) * 1000000)::bigint,
          'evidence_cutoff_us',
            (extract(epoch from terms.evidence_cutoff) * 1000000)::bigint,
          'step_data_policy', terms.step_data_policy::text
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  from public.contests contest
  join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
  where contest.id = p_challenge_id
    and contest.challenge_model = 'personal_accountability';
$$;

comment on function app.personal_terms_fingerprint_v2(uuid) is
  'Server-owned lowercase SHA-256 identity for the complete frozen Personal terms and step policy.';

revoke all on function app.personal_terms_fingerprint_v2(uuid)
  from public, anon, authenticated, service_role;

-- ==========================================================================
-- Private whole-window snapshot and validation helpers
-- ==========================================================================

create table app.personal_health_snapshots_v2 (
  challenge_id       uuid primary key,
  user_id            uuid not null,
  terms_fingerprint  text not null,
  observed_at        timestamptz not null,
  query_through      timestamptz not null,
  daily_progress     jsonb not null,
  total_steps        bigint not null,
  updated_at         timestamptz not null default clock_timestamp(),

  constraint personal_health_snapshots_v2_terms_fkey
    foreign key (challenge_id, user_id)
    references public.personal_challenge_terms (challenge_id, user_id)
    on delete restrict,
  constraint personal_health_snapshots_v2_fingerprint_shape check (
    char_length(terms_fingerprint) = 64
    and terms_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint personal_health_snapshots_v2_total_bounded check (
    total_steps between 0 and 70000000
  ),
  constraint personal_health_snapshots_v2_daily_shape check (
    jsonb_typeof(daily_progress) = 'array'
    and jsonb_array_length(daily_progress) = 7
  ),
  constraint personal_health_snapshots_v2_times_finite check (
    pg_catalog.isfinite(observed_at)
    and pg_catalog.isfinite(query_through)
    and pg_catalog.isfinite(updated_at)
    and query_through <= observed_at
  )
);

comment on table app.personal_health_snapshots_v2 is
  'Private mutable latest whole seven-day Apple Health snapshot. A newer observation replaces the entire prior row; terminal publication copies then removes it.';

alter table app.personal_health_snapshots_v2 enable row level security;

revoke all on table app.personal_health_snapshots_v2
  from public, anon, authenticated, service_role;

create function app.personal_canonical_daily_progress_v2(
  p_challenge_id  uuid,
  p_daily_progress jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_terms public.personal_challenge_terms;
  v_contest public.contests;
  v_canonical jsonb;
begin
  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = p_challenge_id;

  if v_terms.challenge_id is null
     or v_contest.id is null
     or jsonb_typeof(p_daily_progress) is distinct from 'array'
  then
    raise exception 'daily progress must contain exactly seven ordered local days'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_daily_progress) <> 7 then
    raise exception 'daily progress must contain exactly seven ordered local days'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_daily_progress)
      with ordinality day(value, ordinality)
    where jsonb_typeof(day.value) is distinct from 'object'
       or jsonb_typeof(day.value -> 'local_date') is distinct from 'string'
       or jsonb_typeof(day.value -> 'total_steps') is distinct from 'number'
       or (day.value ->> 'total_steps') !~ '^[0-9]+$'
       or (day.value ->> 'total_steps')::numeric > 10000000
       or day.value ->> 'local_date' <>
          pg_catalog.to_char(
            (v_contest.starts_at at time zone v_terms.timezone)::date
              + (day.ordinality::integer - 1),
            'YYYY-MM-DD'
          )
  ) then
    raise exception 'daily progress must match the seven frozen dates with whole totals from 0 through 10000000'
      using errcode = 'invalid_parameter_value';
  end if;

  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'local_date', day.value ->> 'local_date',
      'total_steps', (day.value ->> 'total_steps')::bigint
    )
    order by day.ordinality
  )
  into v_canonical
  from jsonb_array_elements(p_daily_progress)
    with ordinality day(value, ordinality);

  return v_canonical;
end;
$$;

create function app.personal_daily_progress_total_v2(p_daily_progress jsonb)
returns bigint
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(sum((day.value ->> 'total_steps')::bigint), 0)::bigint
  from jsonb_array_elements(p_daily_progress) day(value);
$$;

create function app.personal_zero_daily_progress_v2(p_challenge_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'local_date', pg_catalog.to_char(
        (contest.starts_at at time zone terms.timezone)::date + day_index,
        'YYYY-MM-DD'
      ),
      'total_steps', 0
    )
    order by day_index
  )
  from public.contests contest
  join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
  cross join generate_series(0, 6) day_index
  where contest.id = p_challenge_id;
$$;

revoke all on function
  app.personal_canonical_daily_progress_v2(uuid, jsonb),
  app.personal_daily_progress_total_v2(jsonb),
  app.personal_zero_daily_progress_v2(uuid)
from public, anon, authenticated, service_role;

create function public.upsert_my_personal_health_snapshot_v2(
  challenge_id      uuid,
  terms_fingerprint text,
  observed_at       timestamptz,
  query_through     timestamptz,
  daily_progress    jsonb
)
returns table (
  health_observed_at timestamptz,
  health_query_through timestamptz,
  snapshot_updated_at timestamptz,
  replayed boolean,
  ignored_as_stale boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_input_challenge_id uuid := $1;
  v_input_terms_fingerprint text := $2;
  v_input_observed_at timestamptz := $3;
  v_input_query_through timestamptz := $4;
  v_input_daily_progress jsonb := $5;
  v_actor_id uuid;
  v_contest public.contests;
  v_terms public.personal_challenge_terms;
  v_existing app.personal_health_snapshots_v2;
  v_expected_fingerprint text;
  v_canonical jsonb;
  v_total bigint;
  v_now timestamptz;
  v_updated_at timestamptz;
begin
  v_actor_id := app.require_active_caller();

  if v_input_challenge_id is null
     or v_input_terms_fingerprint is null
     or v_input_terms_fingerprint !~ '^[0-9a-f]{64}$'
     or v_input_observed_at is null
     or v_input_query_through is null
  then
    raise exception 'challenge, terms fingerprint, and snapshot times are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Ownership is part of the locking query so an authenticated caller cannot
  -- use an arbitrary challenge UUID as a cross-tenant row-lock primitive.
  select contest.* into v_contest
  from public.contests contest
  join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
   and terms.user_id = v_actor_id
  where contest.id = v_input_challenge_id
  for update of contest;

  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = v_input_challenge_id
    and terms.user_id = v_actor_id;

  v_now := clock_timestamp();

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by is distinct from v_actor_id
     or v_contest.status not in ('pending', 'active')
     or v_terms.challenge_id is null
     or v_terms.step_data_policy <> 'healthkit_nonmanual_daily_v1'
  then
    raise exception 'automatic Health snapshots are accepted only for the owner open v2 challenge'
      using errcode = 'insufficient_privilege';
  end if;

  if not pg_catalog.isfinite(v_input_observed_at)
     or not pg_catalog.isfinite(v_input_query_through)
     or v_input_observed_at < v_terms.agreed_at
     or v_input_observed_at > v_now + interval '5 minutes'
     or v_input_query_through > v_input_observed_at
     or v_input_query_through > v_contest.ends_at
  then
    raise exception 'snapshot times are outside the open challenge window'
      using errcode = 'restrict_violation';
  end if;

  v_expected_fingerprint :=
    app.personal_terms_fingerprint_v2(v_input_challenge_id);
  if v_input_terms_fingerprint <> v_expected_fingerprint then
    raise exception 'snapshot terms fingerprint does not match the frozen challenge'
      using errcode = 'invalid_parameter_value';
  end if;

  v_canonical := app.personal_canonical_daily_progress_v2(
    v_input_challenge_id,
    v_input_daily_progress
  );
  v_total := app.personal_daily_progress_total_v2(v_canonical);

  if exists (
    select 1
    from jsonb_array_elements(v_canonical)
      with ordinality day(value, ordinality)
    where greatest(
      (
        (v_contest.starts_at at time zone v_terms.timezone)::date
          + (day.ordinality::integer - 1)
      )::timestamp at time zone v_terms.timezone
      , v_contest.starts_at
    ) >= v_input_query_through
      and (day.value ->> 'total_steps')::bigint <> 0
  ) then
    raise exception 'days not reached by query-through must contain zero steps'
      using errcode = 'invalid_parameter_value';
  end if;

  select snapshot.* into v_existing
  from app.personal_health_snapshots_v2 snapshot
  where snapshot.challenge_id = v_input_challenge_id
  for update;

  if v_existing.challenge_id is not null then
    if v_input_observed_at < v_existing.observed_at then
      return query select
        v_existing.observed_at,
        v_existing.query_through,
        v_existing.updated_at,
        true,
        true;
      return;
    end if;

    if v_input_observed_at = v_existing.observed_at then
      if v_existing.terms_fingerprint is distinct from v_input_terms_fingerprint
         or v_existing.query_through is distinct from v_input_query_through
         or v_existing.daily_progress is distinct from v_canonical
         or v_existing.total_steps is distinct from v_total
      then
        raise exception 'equal observation time was already used with different snapshot contents'
          using errcode = 'unique_violation';
      end if;

      return query select
        v_existing.observed_at,
        v_existing.query_through,
        v_existing.updated_at,
        true,
        false;
      return;
    end if;
  end if;

  -- Re-sample after all serialization locks. A request that waited across the
  -- cutoff or advanced too far into the future must roll back without change.
  v_now := clock_timestamp();
  if v_input_observed_at > v_now + interval '5 minutes'
     or v_now >= v_terms.evidence_cutoff
  then
    raise exception 'snapshot times are outside the open challenge window'
      using errcode = 'restrict_violation';
  end if;

  v_updated_at := v_now;

  insert into app.personal_health_snapshots_v2 as snapshot (
    challenge_id,
    user_id,
    terms_fingerprint,
    observed_at,
    query_through,
    daily_progress,
    total_steps,
    updated_at
  )
  values (
    v_input_challenge_id,
    v_actor_id,
    v_input_terms_fingerprint,
    v_input_observed_at,
    v_input_query_through,
    v_canonical,
    v_total,
    v_updated_at
  )
  on conflict on constraint personal_health_snapshots_v2_pkey do update
  set terms_fingerprint = excluded.terms_fingerprint,
      observed_at = excluded.observed_at,
      query_through = excluded.query_through,
      daily_progress = excluded.daily_progress,
      total_steps = excluded.total_steps,
      updated_at = excluded.updated_at;

  return query select
    v_input_observed_at,
    v_input_query_through,
    v_updated_at,
    false,
    false;
end;
$$;

comment on function public.upsert_my_personal_health_snapshot_v2(
  uuid, text, timestamptz, timestamptz, jsonb
) is
  'Authenticated owner-derived whole-snapshot replacement. Stale and identical replays succeed without mutation; equal-time conflicts fail; newer observations replace all seven days including decreases.';

revoke all on function public.upsert_my_personal_health_snapshot_v2(
  uuid, text, timestamptz, timestamptz, jsonb
) from public, anon, authenticated, service_role;

grant execute on function public.upsert_my_personal_health_snapshot_v2(
  uuid, text, timestamptz, timestamptz, jsonb
) to authenticated;

-- ==========================================================================
-- Non-destructive retirement of legacy eligibility holds
-- ==========================================================================

alter table public.personal_eligibility_holds
  add column retired_at timestamptz,
  add column retirement_reason text,
  add column retirement_policy public.personal_step_data_policy;

alter table public.personal_eligibility_holds
  add constraint personal_hold_retirement_shape check (
    (
      pg_catalog.num_nonnulls(
        retired_at, retirement_reason, retirement_policy
      ) = 0
    )
    or (
      pg_catalog.num_nonnulls(
        retired_at, retirement_reason, retirement_policy
      ) = 3
      and
      pg_catalog.isfinite(retired_at)
      and retired_at > placed_at
      and retirement_reason = 'step_policy_superseded'
      and retirement_policy = 'healthkit_nonmanual_daily_v1'
      and cleared_at is null
      and cleared_by_diagnostic_id is null
    )
  );

drop index public.personal_eligibility_one_active_hold_idx;

create unique index personal_eligibility_one_active_hold_idx
  on public.personal_eligibility_holds (user_id)
  where cleared_at is null and retired_at is null;

create or replace function app.guard_personal_hold_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_diagnostic public.personal_trusted_diagnostics;
begin
  -- A legacy diagnostic may race a policy retirement. Suppress its attempted
  -- clearance rather than making an otherwise successful recovery call fail.
  if old.retired_at is not null
     and new.retired_at = old.retired_at
     and new.retirement_reason = old.retirement_reason
     and new.retirement_policy = old.retirement_policy
     and to_jsonb(new) - 'cleared_at' - 'cleared_by_diagnostic_id'
          is not distinct from
         to_jsonb(old) - 'cleared_at' - 'cleared_by_diagnostic_id'
  then
    return null;
  end if;

  if old.cleared_at is null
     and old.retired_at is null
     and new.cleared_at is null
     and new.cleared_by_diagnostic_id is null
     and new.retired_at is not null
     and new.retirement_reason = 'step_policy_superseded'
     and new.retirement_policy = 'healthkit_nonmanual_daily_v1'
     and to_jsonb(new) - 'retired_at' - 'retirement_reason' - 'retirement_policy'
          is not distinct from
         to_jsonb(old) - 'retired_at' - 'retirement_reason' - 'retirement_policy'
  then
    return new;
  end if;

  if to_jsonb(new)
       - 'cleared_at' - 'cleared_by_diagnostic_id'
       - 'retired_at' - 'retirement_reason' - 'retirement_policy'
       is distinct from
     to_jsonb(old)
       - 'cleared_at' - 'cleared_by_diagnostic_id'
       - 'retired_at' - 'retirement_reason' - 'retirement_policy'
     or old.cleared_at is not null
     or old.retired_at is not null
     or new.cleared_at is null
     or new.cleared_by_diagnostic_id is null
     or new.retired_at is not null
     or new.retirement_reason is not null
     or new.retirement_policy is not null
  then
    raise exception 'an eligibility hold may only be cleared once by a trusted diagnostic or retired once by v2 policy'
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

create function app.retire_personal_eligibility_holds_v2(
  p_user_id uuid,
  p_retired_at timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  update public.personal_eligibility_holds hold
  set retired_at = p_retired_at,
      retirement_reason = 'step_policy_superseded',
      retirement_policy = 'healthkit_nonmanual_daily_v1'
  where hold.user_id = p_user_id
    and hold.cleared_at is null
    and hold.retired_at is null;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke all on function app.retire_personal_eligibility_holds_v2(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- ==========================================================================
-- Result source shape and v2-safe provenance dispatch
-- ==========================================================================

alter table public.personal_challenge_results
  alter column assessment_id drop not null,
  add column step_data_policy public.personal_step_data_policy
    not null default 'attested_hourly_v1',
  add column health_observed_at timestamptz,
  add column health_query_through timestamptz,
  add column health_updated_at timestamptz;

alter table public.personal_challenge_results
  add constraint personal_result_step_source_shape check (
    (
      step_data_policy = 'attested_hourly_v1'
      and assessment_id is not null
      and health_observed_at is null
      and health_query_through is null
      and health_updated_at is null
    )
    or (
      step_data_policy = 'healthkit_nonmanual_daily_v1'
      and assessment_id is null
      and (
        (
          pg_catalog.num_nonnulls(
            health_observed_at, health_query_through, health_updated_at
          ) = 0
        )
        or (
          pg_catalog.num_nonnulls(
            health_observed_at, health_query_through, health_updated_at
          ) = 3
          and
          pg_catalog.isfinite(health_observed_at)
          and pg_catalog.isfinite(health_query_through)
          and pg_catalog.isfinite(health_updated_at)
          and health_query_through <= health_observed_at
        )
      )
    )
  );

comment on column public.personal_challenge_results.step_data_policy is
  'Frozen result source. Legacy results retain their assessment reference; v2 results copy one daily Health snapshot directly and have no legacy assessment.';

create function app.validate_personal_result_step_source_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_terms public.personal_challenge_terms;
  v_contest public.contests;
  v_canonical jsonb;
begin
  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = new.challenge_id
    and terms.user_id = new.user_id;

  -- Preserve historical/synthetic legacy inserts that predate a terms row,
  -- while never allowing a legacy publisher into a migrated v2 challenge.
  if new.step_data_policy = 'attested_hourly_v1' then
    if v_terms.challenge_id is not null
       and v_terms.step_data_policy <> new.step_data_policy
    then
      raise exception 'personal result policy must match the frozen challenge policy'
        using errcode = 'restrict_violation';
    end if;
    return new;
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = new.challenge_id;

  if v_terms.challenge_id is null
     or v_contest.id is null
     or new.step_data_policy <> v_terms.step_data_policy
  then
    raise exception 'personal result policy must match the frozen challenge policy'
      using errcode = 'restrict_violation';
  end if;

  if new.assessment_id is not null then
    raise exception 'daily Health snapshot results do not use legacy evidence assessments'
      using errcode = 'restrict_violation';
  end if;

  v_canonical := app.personal_canonical_daily_progress_v2(
    new.challenge_id,
    new.daily_totals
  );

  if new.daily_totals <> v_canonical
     or new.total_steps <> app.personal_daily_progress_total_v2(v_canonical)
  then
    raise exception 'v2 result totals must be the exact canonical seven-day snapshot'
      using errcode = 'restrict_violation';
  end if;

  if new.evidence_state = 'complete' then
    if new.health_observed_at is null
       or new.health_query_through <> v_contest.ends_at
       or new.health_updated_at is null
    then
      raise exception 'complete v2 results require a snapshot queried through the challenge end'
        using errcode = 'restrict_violation';
    end if;
  end if;

  if new.evidence_state <> 'complete'
     and new.health_query_through = v_contest.ends_at
  then
    raise exception 'a v2 snapshot queried through challenge end is complete'
      using errcode = 'restrict_violation';
  end if;

  if new.health_query_through is not null
     and new.health_query_through > v_contest.ends_at
  then
    raise exception 'v2 result query-through cannot pass the challenge end'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_results_validate_step_source_v2
  before insert on public.personal_challenge_results
  for each row execute function app.validate_personal_result_step_source_v2();

-- The pre-v2 production guard assumed every result dereferenced an assessment.
-- Preserve that exact legacy assertion while explicitly dispatching the new
-- ordinary-authenticated policy away from App Attest provenance.
create or replace function app.require_production_personal_result_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment app.personal_evidence_assessments;
begin
  if new.step_data_policy = 'healthkit_nonmanual_daily_v1' then
    return new;
  end if;

  select assessment.* into v_assessment
  from app.personal_evidence_assessments assessment
  where assessment.id = new.assessment_id;

  if v_assessment.id is null then
    raise exception 'legacy Personal V1 result requires its immutable assessment'
      using errcode = 'restrict_violation';
  end if;

  if v_assessment.evidence_state = 'complete' then
    perform app.assert_production_personal_evidence_v1(
      v_assessment.challenge_id,
      v_assessment.user_id
    );
  end if;

  return new;
end;
$$;

revoke all on function
  app.validate_personal_result_step_source_v2(),
  app.require_production_personal_result_v1()
from public, anon, authenticated, service_role;

-- ==========================================================================
-- Clean owner list/detail contract across both policies
-- ==========================================================================

create type public.personal_challenge_card_v2 as (
  challenge_id              uuid,
  status                    public.contest_status,
  cadence                   public.contest_cadence,
  target_steps              integer,
  commitment_amount_minor   integer,
  currency                  text,
  settlement_mode           text,
  terms_version             text,
  timezone                  text,
  agreed_at                 timestamptz,
  starts_at                 timestamptz,
  ends_at                   timestamptz,
  evidence_cutoff           timestamptz,
  closed_at                 timestamptz,
  step_data_policy          public.personal_step_data_policy,
  terms_fingerprint         text,
  total_steps               bigint,
  daily_progress            jsonb,
  health_observed_at        timestamptz,
  health_query_through      timestamptz,
  snapshot_updated_at       timestamptz,
  outcome                   public.personal_challenge_outcome,
  outcome_reason            text,
  commitment_waived         boolean,
  result_published_at       timestamptz
);

create function app.personal_plain_daily_progress_v2(p_progress jsonb)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'local_date', day.value ->> 'local_date',
        'total_steps', coalesce(
          day.value -> 'total_steps',
          day.value -> 'trusted_steps',
          '0'::jsonb
        )
      )
      order by day.ordinality
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_progress, '[]'::jsonb))
    with ordinality day(value, ordinality);
$$;

create function app.personal_challenge_cards_v2(
  p_user_id uuid,
  p_challenge_id uuid default null
)
returns setof public.personal_challenge_card_v2
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
    case
      when agreement.challenge_id is not null then 'stripe_sandbox'
      else terms.settlement_mode::text
    end,
    terms.terms_version,
    terms.timezone,
    terms.agreed_at,
    contest.starts_at,
    contest.ends_at,
    terms.evidence_cutoff,
    terms.closed_at,
    terms.step_data_policy,
    app.personal_terms_fingerprint_v2(contest.id),
    coalesce(
      result.total_steps::bigint,
      case
        when terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
          then snapshot.total_steps
        else legacy_progress.total_steps::bigint
      end,
      0::bigint
    ),
    app.personal_plain_daily_progress_v2(
      case
        when result.id is not null then result.daily_totals
        when terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
          then coalesce(
            snapshot.daily_progress,
            app.personal_zero_daily_progress_v2(contest.id)
          )
        else app.personal_daily_progress_v1(contest.id, p_user_id, v_as_of)
      end
    ),
    case
      when terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
        then coalesce(result.health_observed_at, snapshot.observed_at)
      else legacy_health.observed_at
    end,
    case
      when terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
        then coalesce(result.health_query_through, snapshot.query_through)
      else least(legacy_health.observed_at, contest.ends_at)
    end,
    case
      when terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
        then coalesce(result.health_updated_at, snapshot.updated_at)
      else legacy_health.updated_at
    end,
    result.outcome,
    case
      when result.reason = 'missing_coverage' then 'missing_health_data'
      else result.reason::text
    end,
    result.commitment_waived,
    result.published_at
  from public.personal_challenge_terms terms
  join public.contests contest
    on contest.id = terms.challenge_id
   and contest.challenge_model = 'personal_accountability'
  left join public.personal_challenge_results result
    on result.challenge_id = contest.id
  left join app.personal_stripe_sandbox_agreements agreement
    on agreement.challenge_id = contest.id
   and agreement.user_id = terms.user_id
  left join app.personal_health_snapshots_v2 snapshot
    on snapshot.challenge_id = contest.id
   and snapshot.user_id = terms.user_id
  left join lateral (
    select sum(evidence.value)::numeric(20, 2) as total_steps
    from public.contest_evidence evidence
    where evidence.contest_id = contest.id
      and evidence.user_id = terms.user_id
      and evidence.metric = 'steps'
  ) legacy_progress on true
  left join lateral (
    select
      max(batch.observed_at) as observed_at,
      max(batch.recorded_at) as updated_at
    from public.personal_sync_coverage_batches batch
    where batch.challenge_id = contest.id
      and batch.user_id = terms.user_id
  ) legacy_health on true
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

create function public.list_my_accountability_challenges_v2()
returns setof public.personal_challenge_card_v2
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
  select * from app.personal_challenge_cards_v2(v_user_id, null);
end;
$$;

create function public.get_my_accountability_challenge_v2(challenge_id uuid)
returns setof public.personal_challenge_card_v2
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_challenge_id uuid := $1;
begin
  v_user_id := app.require_active_caller();
  return query
  select *
  from app.personal_challenge_cards_v2(v_user_id, v_challenge_id);
end;
$$;

revoke all on function
  app.personal_plain_daily_progress_v2(jsonb),
  app.personal_challenge_cards_v2(uuid, uuid)
from public, anon, authenticated, service_role;

revoke all on function
  public.list_my_accountability_challenges_v2(),
  public.get_my_accountability_challenge_v2(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.list_my_accountability_challenges_v2(),
  public.get_my_accountability_challenge_v2(uuid)
to authenticated;

-- ==========================================================================
-- Explicit v2 construction
-- ==========================================================================

create function app.create_personal_challenge_v2_unchecked(
  p_actor_id                uuid,
  p_request_id              uuid,
  p_cadence                 public.contest_cadence,
  p_target_steps            integer,
  p_commitment_amount_minor integer,
  p_timezone                text,
  p_requested_starts_at     timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_payload_hash bytea;
  v_legacy_payload_hash bytea;
  v_existing app.personal_challenge_creation_requests;
  v_challenge_id uuid;
  v_now timestamptz;
  v_local_start timestamp;
  v_start_date date;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
begin
  if p_actor_id is null then
    raise exception 'an active owner is required'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_actor_id]);
  v_now := clock_timestamp();

  if p_request_id is null then
    raise exception 'request UUID is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_cadence is null then
    raise exception 'cadence is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_target_steps is null or p_target_steps not between 1 and 1000000 then
    raise exception 'target steps must be a whole number from 1 through 1000000'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_commitment_amount_minor not in (1000, 2000, 3000, 4000, 5000) then
    raise exception 'commitment must be one of the five test presets'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names zone
       where zone.name = p_timezone
     )
  then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_requested_starts_at is not null then
    if not pg_catalog.isfinite(p_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := p_requested_starts_at at time zone p_timezone;
    if extract(minute from v_local_start) <> 0
       or extract(second from v_local_start) <> 0
    then
      raise exception 'a chosen start must land on a whole hour in the frozen timezone'
        using errcode = 'invalid_parameter_value';
    end if;
    if p_requested_starts_at <= v_now
       or p_requested_starts_at > v_now + interval '90 days'
    then
      raise exception 'a chosen start must be in the future and within 90 days'
        using errcode = 'invalid_parameter_value';
    end if;
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_accountability_v2',
        'cadence', p_cadence::text,
        'target_steps', p_target_steps,
        'commitment_amount_minor', p_commitment_amount_minor,
        'currency', 'USD',
        'settlement_mode', 'test_only',
        'terms_version', 'personal-v2',
        'timezone', p_timezone,
        'requested_starts_at_epoch', case
          when p_requested_starts_at is null then null
          else extract(epoch from p_requested_starts_at)::bigint
        end,
        'step_data_policy', 'healthkit_nonmanual_daily_v1'
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- A mandatory v2 build may retry the exact request that originally created
  -- a now-cut-over v1 challenge. Reconstruct the historical request identity
  -- so that lost-response retry remains idempotent without accepting changed
  -- terms. The frozen row below must still match every caller input.
  v_legacy_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      (
        pg_catalog.jsonb_build_object(
          'kind', 'personal_accountability_v1',
          'cadence', p_cadence::text,
          'target_steps', p_target_steps,
          'commitment_amount_minor', p_commitment_amount_minor,
          'currency', 'USD',
          'settlement_mode', 'test_only',
          'terms_version', 'personal-v1',
          'timezone', p_timezone
        )
        || case
             when p_requested_starts_at is null then '{}'::jsonb
             else pg_catalog.jsonb_build_object(
               'requested_starts_at',
               extract(epoch from p_requested_starts_at)::bigint
             )
           end
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select request.* into v_existing
  from app.personal_challenge_creation_requests request
  where request.actor_id = p_actor_id
    and request.request_id = p_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.payload_hash not in (v_payload_hash, v_legacy_payload_hash)
       or not exists (
         select 1
         from public.personal_challenge_terms terms
         join public.contests contest
           on contest.id = terms.challenge_id
         where terms.challenge_id = v_existing.challenge_id
           and terms.user_id = p_actor_id
           and terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
           and terms.cadence = p_cadence
           and terms.target_steps = p_target_steps
           and terms.commitment_amount_minor = p_commitment_amount_minor
           and terms.currency = 'USD'
           and terms.settlement_mode = 'test_only'
           and terms.timezone = p_timezone
           and (
             (p_requested_starts_at is null and contest.starts_at is not null)
             or contest.starts_at = p_requested_starts_at
           )
       )
    then
      raise exception 'request UUID already used with different personal terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.challenge_id;
  end if;

  perform app.retire_personal_eligibility_holds_v2(p_actor_id, v_now);

  if p_requested_starts_at is null then
    v_start_date := (v_now at time zone p_timezone)::date + 1;
    v_starts_at := v_start_date::timestamp at time zone p_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := p_requested_starts_at;
  end if;
  v_ends_at := (v_start_date + 7)::timestamp at time zone p_timezone;

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
    p_actor_id,
    'personal_accountability',
    'steps',
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    'void',
    v_starts_at,
    v_ends_at,
    1
  )
  returning id into v_challenge_id;

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  )
  values (
    v_challenge_id, p_actor_id, 'accepted', p_timezone, null
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
    evidence_cutoff,
    step_data_policy
  )
  values (
    v_challenge_id,
    p_actor_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    'USD',
    'test_only',
    'personal-v2',
    p_timezone,
    v_now,
    v_ends_at + interval '24 hours',
    'healthkit_nonmanual_daily_v1'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id, request_id, payload_hash, challenge_id
  )
  values (
    p_actor_id, p_request_id, v_payload_hash, v_challenge_id
  );

  return v_challenge_id;
end;
$$;

create function public.create_personal_challenge_v2(
  request_id               uuid,
  cadence                  public.contest_cadence,
  target_steps             integer,
  commitment_amount_minor  integer,
  timezone                 text,
  requested_starts_at      timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
begin
  v_actor_id := app.require_active_caller();
  return app.create_personal_challenge_v2_unchecked(
    v_actor_id,
    request_id,
    cadence,
    target_steps,
    commitment_amount_minor,
    timezone,
    requested_starts_at
  );
end;
$$;

revoke all on function app.create_personal_challenge_v2_unchecked(
  uuid, uuid, public.contest_cadence, integer, integer, text, timestamptz
) from public, anon, authenticated, service_role;

revoke all on function public.create_personal_challenge_v2(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.create_personal_challenge_v2(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) to authenticated;

-- Terminal transitions remove only the mutable v2 snapshot. Every legacy
-- audit row and the immutable copied result remain untouched.
create function app.delete_personal_health_snapshot_on_terminal_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.challenge_model = 'personal_accountability'
     and old.status in ('pending', 'active')
     and new.status in ('cancelled', 'finalized')
  then
    delete from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id = new.id;
  end if;
  return new;
end;
$$;

create trigger contests_delete_personal_health_snapshot_v2
  after update of status on public.contests
  for each row
  when (old.status is distinct from new.status)
  execute function app.delete_personal_health_snapshot_on_terminal_v2();

revoke all on function app.delete_personal_health_snapshot_on_terminal_v2()
  from public, anon, authenticated, service_role;

-- ==========================================================================
-- Policy-dispatched result publication
-- ==========================================================================

create function app.publish_due_personal_result_v2(
  p_challenge_id uuid,
  p_now timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest public.contests;
  v_terms public.personal_challenge_terms;
  v_snapshot app.personal_health_snapshots_v2;
  v_existing_result uuid;
  v_daily_progress jsonb;
  v_total_steps bigint;
  v_evidence_state public.personal_evidence_state;
  v_outcome public.personal_challenge_outcome;
  v_reason public.personal_result_reason;
  v_waived boolean;
  v_met boolean;
  v_published_at timestamptz;
  v_result_id uuid;
begin
  if p_challenge_id is null
     or p_now is null
     or not pg_catalog.isfinite(p_now)
  then
    raise exception 'challenge and finite worker time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Preserve the repository lock order: retained profile, then contest, then
  -- the mutable snapshot. Deleted accounts still retain the profile row and
  -- therefore can receive a service-owned terminal result.
  select terms.* into v_terms
  from public.personal_challenge_terms terms
  join public.profiles profile on profile.id = terms.user_id
  where terms.challenge_id = p_challenge_id
  for update of profile;

  if v_terms.challenge_id is null then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = p_challenge_id
  for update;

  if v_contest.id is null
     or v_contest.challenge_model <> 'personal_accountability'
     or v_terms.step_data_policy <> 'healthkit_nonmanual_daily_v1'
  then
    raise exception 'automatic Health personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select result.id into v_existing_result
  from public.personal_challenge_results result
  where result.challenge_id = p_challenge_id;

  if v_existing_result is not null then
    return v_existing_result;
  end if;

  v_published_at := clock_timestamp();
  if v_contest.status <> 'active'
     or v_terms.evidence_cutoff is null
     or p_now < v_terms.evidence_cutoff
     or v_published_at < v_terms.evidence_cutoff
  then
    raise exception 'personal challenge is not due for automatic result'
      using errcode = 'restrict_violation';
  end if;

  select snapshot.* into v_snapshot
  from app.personal_health_snapshots_v2 snapshot
  where snapshot.challenge_id = p_challenge_id
    and snapshot.user_id = v_terms.user_id
  for update;

  if v_snapshot.challenge_id is null then
    v_daily_progress := app.personal_zero_daily_progress_v2(p_challenge_id);
    v_total_steps := 0;
    v_evidence_state := 'missing';
  else
    v_daily_progress := v_snapshot.daily_progress;
    v_total_steps := v_snapshot.total_steps;
    v_evidence_state := case
      when v_snapshot.query_through = v_contest.ends_at
        then 'complete'::public.personal_evidence_state
      else 'missing'::public.personal_evidence_state
    end;
  end if;

  if v_evidence_state = 'complete' then
    if v_terms.cadence = 'daily' then
      select not exists (
        select 1
        from jsonb_array_elements(v_daily_progress) day
        where (day ->> 'total_steps')::bigint < v_terms.target_steps
      ) into v_met;
    else
      v_met := v_total_steps >= v_terms.target_steps;
    end if;

    v_outcome := case
      when v_met then 'met_goal'::public.personal_challenge_outcome
      else 'missed_goal'::public.personal_challenge_outcome
    end;
    v_reason := case
      when v_met then 'target_reached'::public.personal_result_reason
      else 'target_missed'::public.personal_result_reason
    end;
    v_waived := false;
  else
    v_outcome := 'inconclusive';
    -- Keep the historical storage enum stable in this support migration. The
    -- clean v2 read boundary maps this internal value to missing_health_data.
    v_reason := 'missing_coverage';
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
    published_at,
    step_data_policy,
    health_observed_at,
    health_query_through,
    health_updated_at
  )
  values (
    p_challenge_id,
    v_terms.user_id,
    null,
    v_outcome,
    v_reason,
    v_evidence_state,
    v_terms.evidence_cutoff,
    v_total_steps,
    v_daily_progress,
    v_waived,
    v_published_at,
    'healthkit_nonmanual_daily_v1',
    v_snapshot.observed_at,
    v_snapshot.query_through,
    v_snapshot.updated_at
  )
  returning id into v_result_id;

  -- The immutable result now owns the copied totals. The contest terminal
  -- trigger removes the mutable snapshot and closes frozen terms.
  update public.contests contest
  set status = 'finalized'
  where contest.id = p_challenge_id;

  perform public.set_workflow_retention_state(
    'contest_lineage',
    p_challenge_id,
    false,
    v_published_at,
    v_published_at,
    'raw-evidence-retention-v1'
  );

  return v_result_id;
end;
$$;

comment on function app.publish_due_personal_result_v2(uuid, timestamptz) is
  'Private v2 publisher. Completeness requires query-through at the frozen end; otherwise it freezes a waived inconclusive result, copies any partial totals, and removes the mutable snapshot.';

create function app.publish_due_personal_result(
  p_challenge_id uuid,
  p_now timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_policy public.personal_step_data_policy;
begin
  select terms.step_data_policy into v_policy
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  if v_policy = 'healthkit_nonmanual_daily_v1' then
    return app.publish_due_personal_result_v2(p_challenge_id, p_now);
  end if;

  if v_policy = 'attested_hourly_v1' then
    return app.publish_due_personal_result_v1(p_challenge_id, p_now);
  end if;

  raise exception 'personal challenge not found'
    using errcode = 'invalid_parameter_value';
end;
$$;

-- Preserve the existing bounded SKIP LOCKED sweep and privacy-safe attempt
-- ledger, changing only the per-challenge call to policy dispatch.
create or replace function app.run_personal_result_worker_at(
  p_now timestamptz,
  p_limit integer
)
returns table (
  challenges_selected integer,
  results_published integer,
  failures_recorded integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_due record;
  v_result_id uuid;
  v_attempted_at timestamptz;
  v_sqlstate text;
begin
  if p_now is null
     or not pg_catalog.isfinite(p_now)
     or p_limit is null
     or p_limit not between 1 and 100
  then
    raise exception 'finite worker time and limit from 1 through 100 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  challenges_selected := 0;
  results_published := 0;
  failures_recorded := 0;

  for v_due in
    select contest.id
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    join public.profiles profile
      on profile.id = terms.user_id
    where contest.challenge_model = 'personal_accountability'
      and contest.status in ('pending', 'active')
      and terms.evidence_cutoff <= p_now
      and not exists (
        select 1
        from public.personal_challenge_results result
        where result.challenge_id = contest.id
      )
    order by terms.evidence_cutoff, contest.id
    limit p_limit
    for update of profile skip locked
  loop
    challenges_selected := challenges_selected + 1;
    v_attempted_at := clock_timestamp();

    begin
      v_result_id := app.publish_due_personal_result(v_due.id, p_now);

      insert into app.personal_result_worker_attempts as attempt (
        challenge_id,
        attempt_count,
        first_attempted_at,
        last_attempted_at,
        last_status,
        last_sqlstate,
        published_result_id
      )
      values (
        v_due.id,
        1,
        v_attempted_at,
        v_attempted_at,
        'published',
        null,
        v_result_id
      )
      on conflict (challenge_id) do update
      set attempt_count = attempt.attempt_count + 1,
          last_attempted_at = excluded.last_attempted_at,
          last_status = excluded.last_status,
          last_sqlstate = null,
          published_result_id = excluded.published_result_id;

      results_published := results_published + 1;
    exception
      when others then
        get stacked diagnostics v_sqlstate = returned_sqlstate;

        insert into app.personal_result_worker_attempts as attempt (
          challenge_id,
          attempt_count,
          first_attempted_at,
          last_attempted_at,
          last_status,
          last_sqlstate,
          published_result_id
        )
        values (
          v_due.id,
          1,
          v_attempted_at,
          v_attempted_at,
          'failed',
          v_sqlstate,
          null
        )
        on conflict (challenge_id) do update
        set attempt_count = attempt.attempt_count + 1,
            last_attempted_at = excluded.last_attempted_at,
            last_status = excluded.last_status,
            last_sqlstate = excluded.last_sqlstate,
            published_result_id = null;

        failures_recorded := failures_recorded + 1;
    end;
  end loop;

  return next;
end;
$$;

comment on function app.run_personal_result_worker_at(timestamptz, integer) is
  'Private bounded policy-dispatched Personal result sweep with SKIP LOCKED concurrency and per-challenge failure isolation.';

comment on function app.run_personal_result_worker() is
  'Dormant five-minute Personal result entry point, dispatching legacy attestations and automatic Health snapshots by frozen policy.';

revoke all on function
  app.publish_due_personal_result_v2(uuid, timestamptz),
  app.publish_due_personal_result(uuid, timestamptz)
from public, anon, authenticated, service_role;

-- ==========================================================================
-- Stripe sandbox v2 construction path
-- ==========================================================================

-- Keep the externally consented Stripe sandbox agreement and consent versions
-- stable. The new service path creates Health-policy challenges, while the
-- legacy constructor remains the unmarked path for old builds.
create function app.commit_personal_stripe_sandbox_challenge_v2_unchecked(
  p_owner_id uuid,
  p_request_id uuid,
  p_setup_id uuid,
  p_cadence public.contest_cadence,
  p_target_steps integer,
  p_commitment_amount_minor integer,
  p_currency text,
  p_timezone text,
  p_requested_starts_at timestamptz,
  p_agreement_version text,
  p_consent_version text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_setup app.personal_stripe_sandbox_setups;
  v_existing app.personal_stripe_sandbox_agreements;
  v_base_request app.personal_challenge_creation_requests;
  v_creation_hash bytea;
  v_legacy_creation_hash bytea;
  v_challenge_id uuid;
  v_now timestamptz;
begin
  if p_owner_id is null
     or p_request_id is null
     or p_setup_id is null
     or p_currency is distinct from 'USD'
     or p_agreement_version is distinct from
          'personal-stripe-sandbox-v1'
     or p_consent_version is distinct from
          'personal-stripe-sandbox-consent-v1'
  then
    raise exception 'verified owner, request, and setup are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_personal_stripe_sandbox_control_v1(false);
  perform app.lock_active_actors(array[p_owner_id]);

  v_creation_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_stripe_sandbox_health_challenge_v2',
        'step_data_policy', 'healthkit_nonmanual_daily_v1',
        'setup_id', p_setup_id,
        'cadence', p_cadence::text,
        'target_steps', p_target_steps,
        'commitment_amount_minor', p_commitment_amount_minor,
        'currency', p_currency,
        'timezone', p_timezone,
        'requested_starts_at_epoch', case
          when p_requested_starts_at is null then null
          else extract(epoch from p_requested_starts_at)::bigint
        end,
        'agreement_version', p_agreement_version,
        'consent_version', p_consent_version
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Retain the deployed hash only to recognize a v1 agreement whose frozen
  -- challenge was explicitly migrated by cutover. New Health agreements use
  -- the policy-bound digest above, so the untouched legacy commit boundary
  -- rejects a fresh v2 winner as a different request payload.
  v_legacy_creation_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_stripe_sandbox_challenge_v2',
        'setup_id', p_setup_id,
        'cadence', p_cadence::text,
        'target_steps', p_target_steps,
        'commitment_amount_minor', p_commitment_amount_minor,
        'currency', p_currency,
        'timezone', p_timezone,
        'requested_starts_at_epoch', case
          when p_requested_starts_at is null then null
          else extract(epoch from p_requested_starts_at)::bigint
        end,
        'agreement_version', p_agreement_version,
        'consent_version', p_consent_version
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select agreement.* into v_existing
  from app.personal_stripe_sandbox_agreements agreement
  where agreement.user_id = p_owner_id
    and agreement.create_request_id = p_request_id;

  if v_existing.challenge_id is not null then
    if v_existing.setup_id <> p_setup_id
       or (
         v_existing.creation_payload_hash <> v_creation_hash
         and v_existing.creation_payload_hash <> v_legacy_creation_hash
       )
    then
      raise exception 'challenge request UUID already used with different Stripe terms'
        using errcode = 'invalid_parameter_value';
    end if;

    if not exists (
      select 1
      from public.personal_challenge_terms terms
      where terms.challenge_id = v_existing.challenge_id
        and terms.user_id = p_owner_id
        and terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
    ) then
      raise exception 'challenge request was committed with a different step-data policy'
        using errcode = 'invalid_parameter_value';
    end if;

    if v_existing.beta_authorization_version is distinct from
         'personal-stripe-sandbox-beta-v1'
       or v_existing.beta_authorized_at is null
    then
      raise exception 'challenge request was not admitted by the Stripe sandbox beta controls'
        using errcode = 'insufficient_privilege';
    end if;

    return pg_catalog.jsonb_build_object(
      'challenge_id', v_existing.challenge_id,
      'payment_state', 'method_saved',
      'replayed', true
    );
  end if;

  perform app.require_personal_stripe_sandbox_beta_admission_v1(p_owner_id);
  v_now := clock_timestamp();

  select request.* into v_base_request
  from app.personal_challenge_creation_requests request
  where request.actor_id = p_owner_id
    and request.request_id = p_request_id;

  if v_base_request.challenge_id is not null then
    raise exception 'challenge request UUID was already used outside the Stripe v2 boundary'
      using errcode = 'invalid_parameter_value';
  end if;

  select setup.* into v_setup
  from app.personal_stripe_sandbox_setups setup
  where setup.id = p_setup_id
    and setup.user_id = p_owner_id
  for update;

  if v_setup.id is null
     or v_setup.status <> 'succeeded'
     or v_setup.succeeded_at is null
     or v_setup.expires_at <= v_now
     or v_setup.consumed_at is not null
     or v_setup.stripe_customer_id is null
     or v_setup.stripe_setup_intent_id is null
     or v_setup.stripe_payment_method_id is null
     or v_setup.beta_authorization_version is distinct from
          'personal-stripe-sandbox-beta-v1'
     or v_setup.beta_authorized_at is null
  then
    raise exception 'an admitted, unexpired, succeeded, unused Stripe sandbox setup is required'
      using errcode = 'restrict_violation';
  end if;

  if v_setup.cadence <> p_cadence
     or v_setup.target_steps <> p_target_steps
     or v_setup.commitment_amount_minor <> p_commitment_amount_minor
     or v_setup.currency <> p_currency
     or v_setup.timezone <> p_timezone
     or v_setup.requested_starts_at is distinct from p_requested_starts_at
     or v_setup.agreement_version <> p_agreement_version
     or v_setup.consent_version <> p_consent_version
  then
    raise exception 'challenge terms must exactly match the consented Stripe setup'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from app.personal_stripe_sandbox_agreements agreement
    join app.personal_stripe_sandbox_payment_reviews review
      on review.challenge_id = agreement.challenge_id
    left join app.personal_stripe_sandbox_charge_commands command
      on command.challenge_id = agreement.challenge_id
    where agreement.user_id = p_owner_id
      and (
        review.state in ('review_open', 'under_review')
        or (
          review.state = 'confirmed_miss'
          and (
            command.id is null
            or command.status <> 'succeeded'
          )
        )
      )
  ) then
    raise exception 'an earlier paid challenge review or collection is unresolved'
      using errcode = 'restrict_violation';
  end if;

  v_challenge_id := app.create_personal_challenge_v2_unchecked(
    p_owner_id,
    p_request_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_timezone,
    p_requested_starts_at
  );

  insert into app.personal_stripe_sandbox_agreements (
    challenge_id,
    user_id,
    setup_id,
    create_request_id,
    creation_payload_hash,
    setup_payload_hash,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    timezone,
    requested_starts_at,
    agreement_version,
    consent_version,
    consented_at,
    stripe_customer_id,
    stripe_setup_intent_id,
    stripe_payment_method_id,
    beta_authorization_version,
    beta_authorized_at
  )
  values (
    v_challenge_id,
    p_owner_id,
    p_setup_id,
    p_request_id,
    v_creation_hash,
    v_setup.payload_hash,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    'USD',
    p_timezone,
    p_requested_starts_at,
    v_setup.agreement_version,
    v_setup.consent_version,
    v_setup.consented_at,
    v_setup.stripe_customer_id,
    v_setup.stripe_setup_intent_id,
    v_setup.stripe_payment_method_id,
    'personal-stripe-sandbox-beta-v1',
    v_now
  );

  update app.personal_stripe_sandbox_setups setup
  set consumed_at = v_now,
      consumed_challenge_id = v_challenge_id,
      updated_at = v_now
  where setup.id = p_setup_id;

  return pg_catalog.jsonb_build_object(
    'challenge_id', v_challenge_id,
    'payment_state', 'method_saved',
    'replayed', false
  );
end;
$$;

create function public.commit_personal_stripe_sandbox_challenge_service_v2(
  p_owner_id uuid,
  p_request_id uuid,
  p_setup_id uuid,
  p_cadence public.contest_cadence,
  p_target_steps integer,
  p_commitment_amount_minor integer,
  p_currency text,
  p_timezone text,
  p_requested_starts_at timestamptz default null,
  p_agreement_version text default 'personal-stripe-sandbox-v1',
  p_consent_version text default 'personal-stripe-sandbox-consent-v1'
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select app.commit_personal_stripe_sandbox_challenge_v2_unchecked(
    p_owner_id,
    p_request_id,
    p_setup_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_currency,
    p_timezone,
    p_requested_starts_at,
    p_agreement_version,
    p_consent_version
  )
$$;

comment on function public.commit_personal_stripe_sandbox_challenge_service_v2(
  uuid, uuid, uuid, public.contest_cadence, integer, integer, text, text,
  timestamptz, text, text
) is
  'Service-only policy-marked Stripe sandbox commit that freezes Personal v2 Health terms while retaining v1 agreement and consent versions.';

revoke all on function
  app.commit_personal_stripe_sandbox_challenge_v2_unchecked(
    uuid, uuid, uuid, public.contest_cadence, integer, integer, text, text,
    timestamptz, text, text
  ),
  public.commit_personal_stripe_sandbox_challenge_service_v2(
    uuid, uuid, uuid, public.contest_cadence, integer, integer, text, text,
    timestamptz, text, text
  )
from public, anon, authenticated, service_role;

grant execute on function
  public.commit_personal_stripe_sandbox_challenge_service_v2(
    uuid, uuid, uuid, public.contest_cadence, integer, integer, text, text,
    timestamptz, text, text
  )
to service_role;

-- ==========================================================================
-- Explicit, non-invoked service cutover
-- ==========================================================================

create table app.personal_health_cutover_requests_v2 (
  request_id uuid primary key,
  payload_hash bytea not null,
  as_of timestamptz not null,
  migrated_challenges integer not null,
  retired_holds integer not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint personal_health_cutover_digest check (
    octet_length(payload_hash) = 32
  ),
  constraint personal_health_cutover_counts check (
    migrated_challenges >= 0 and retired_holds >= 0
  ),
  constraint personal_health_cutover_times check (
    pg_catalog.isfinite(as_of) and pg_catalog.isfinite(created_at)
  )
);

alter table app.personal_health_cutover_requests_v2 enable row level security;

create trigger personal_health_cutover_requests_v2_forbid_mutation
  before update or delete or truncate
  on app.personal_health_cutover_requests_v2
  for each statement execute function app.forbid_mutation();

revoke all on table app.personal_health_cutover_requests_v2
  from public, anon, authenticated, service_role;

create or replace function app.guard_personal_terms_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.step_data_policy = 'attested_hourly_v1'
     and new.step_data_policy = 'healthkit_nonmanual_daily_v1'
     and current_setting('app.personal_step_policy_cutover_v2', true) = 'enabled'
     and to_jsonb(new) - 'step_data_policy'
          is not distinct from to_jsonb(old) - 'step_data_policy'
  then
    return new;
  end if;

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

create function public.cutover_personal_health_snapshots_v2(
  p_request_id uuid,
  p_as_of timestamptz
)
returns table (
  migrated_challenges integer,
  retired_holds integer,
  replayed boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_payload_hash bytea;
  v_existing app.personal_health_cutover_requests_v2;
  v_owner record;
  v_migrated integer := 0;
  v_retired integer := 0;
  v_execution_as_of timestamptz := clock_timestamp();
begin
  if p_request_id is null
     or p_as_of is null
     or not pg_catalog.isfinite(p_as_of)
     or p_as_of > v_execution_as_of + interval '5 minutes'
  then
    raise exception 'cutover request UUID and finite selection time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_health_snapshot_cutover_v2',
        'as_of_us', (extract(epoch from p_as_of) * 1000000)::bigint,
        'target_policy', 'healthkit_nonmanual_daily_v1'
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Serialize this one explicit operator operation before reading its ledger,
  -- so concurrent exact retries deterministically replay instead of colliding.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'personal-health-cutover-v2:' || p_request_id::text,
      0
    )
  );

  select request.* into v_existing
  from app.personal_health_cutover_requests_v2 request
  where request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception 'cutover request UUID was already used with different selection input'
        using errcode = 'unique_violation';
    end if;
    return query select
      v_existing.migrated_challenges,
      v_existing.retired_holds,
      true;
    return;
  end if;

  if exists (
    select 1
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.challenge_model = 'personal_accountability'
      and contest.status in ('pending', 'active')
      and terms.step_data_policy = 'attested_hourly_v1'
      and terms.evidence_cutoff <= greatest(p_as_of, v_execution_as_of)
      and not exists (
        select 1
        from public.personal_challenge_results result
        where result.challenge_id = contest.id
      )
  ) then
    raise exception 'already-due legacy Personal challenges must be resolved before v2 cutover'
      using errcode = 'restrict_violation';
  end if;

  -- Match the repository-wide actor then contest lock order. Retained deleted
  -- profiles are lockable, so service-owned unresolved work can still migrate.
  for v_owner in
    select distinct terms.user_id
    from public.personal_challenge_terms terms
    join public.contests contest on contest.id = terms.challenge_id
    where terms.step_data_policy = 'attested_hourly_v1'
      and contest.status in ('pending', 'active')
      and terms.evidence_cutoff > greatest(p_as_of, v_execution_as_of)
    order by terms.user_id
  loop
    perform 1
    from public.profiles profile
    where profile.id = v_owner.user_id
    for update;
  end loop;

  perform 1
  from public.contests contest
  join public.personal_challenge_terms terms on terms.challenge_id = contest.id
  where terms.step_data_policy = 'attested_hourly_v1'
    and contest.status in ('pending', 'active')
    and terms.evidence_cutoff > greatest(p_as_of, v_execution_as_of)
  order by contest.id
  for update of contest;

  perform set_config(
    'app.personal_step_policy_cutover_v2',
    'enabled',
    true
  );

  update public.personal_challenge_terms terms
  set step_data_policy = 'healthkit_nonmanual_daily_v1'
  from public.contests contest
  where contest.id = terms.challenge_id
    and contest.challenge_model = 'personal_accountability'
    and contest.status in ('pending', 'active')
    and terms.step_data_policy = 'attested_hourly_v1'
    and terms.evidence_cutoff > greatest(p_as_of, v_execution_as_of)
    and not exists (
      select 1
      from public.personal_challenge_results result
      where result.challenge_id = contest.id
    );

  get diagnostics v_migrated = row_count;

  for v_owner in
    select distinct terms.user_id
    from public.personal_challenge_terms terms
    join public.contests contest on contest.id = terms.challenge_id
    where terms.step_data_policy = 'healthkit_nonmanual_daily_v1'
      and contest.status in ('pending', 'active')
      and terms.evidence_cutoff > greatest(p_as_of, v_execution_as_of)
    order by terms.user_id
  loop
    v_retired := v_retired + app.retire_personal_eligibility_holds_v2(
      v_owner.user_id,
      clock_timestamp()
    );
  end loop;

  insert into app.personal_health_cutover_requests_v2 (
    request_id,
    payload_hash,
    as_of,
    migrated_challenges,
    retired_holds
  )
  values (
    p_request_id,
    v_payload_hash,
    p_as_of,
    v_migrated,
    v_retired
  );

  return query select v_migrated, v_retired, false;
end;
$$;

revoke all on function public.cutover_personal_health_snapshots_v2(
  uuid, timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.cutover_personal_health_snapshots_v2(
  uuid, timestamptz
) to service_role;

-- A retired hold is an immutable audit row, never active eligibility state.
-- Patch the four inherited readers/mutators in place so legacy APIs agree with
-- the new partial index and a racing diagnostic cannot target retired history.
do $retired_hold_queries$
declare
  v_signature regprocedure;
  v_definition text;
  v_old text := 'and hold.cleared_at is null';
  v_new text := 'and hold.cleared_at is null' || chr(10)
    || '      and hold.retired_at is null';
begin
  foreach v_signature in array array[
    'public.create_personal_challenge_v1(uuid,public.contest_cadence,integer,integer,text,timestamptz)'::regprocedure,
    'app.record_trusted_personal_diagnostic_v1_unchecked(uuid,uuid,bytea,timestamptz,timestamptz,timestamptz,integer,bytea,bigint)'::regprocedure,
    'app.personal_challenge_cards_v1(uuid,uuid)'::regprocedure,
    'public.get_my_personal_eligibility_v1()'::regprocedure
  ]
  loop
    select pg_catalog.pg_get_functiondef(v_signature)
      into v_definition;

    if pg_catalog.strpos(v_definition, v_old) = 0 then
      raise exception 'expected active-hold predicate is absent from %',
        v_signature::text
        using errcode = 'data_exception';
    end if;

    execute pg_catalog.replace(v_definition, v_old, v_new);
  end loop;
end;
$retired_hold_queries$;

commit;
