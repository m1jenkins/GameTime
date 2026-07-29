-- M7 / M8.3c -- canonical provisional standings, immutable first results, and
-- one donation obligation per debtor.
--
-- The TypeScript scoring/integrity engine remains the only implementation of
-- the competition rules. This migration is its durable boundary:
--
--   * service_role publishes a complete, ordered snapshot;
--   * the database validates the accepted roster and display ranks;
--   * finalization freezes both metric and check-in ingest in the same
--     transaction, waits for grace, and refuses unresolved quarantine review;
--   * winner and all-donate outcomes create their exact D75 obligation map;
--   * accepted participants read one phase-aware, D77-redacted document.
--
-- No scheduled caller is installed here. M6.5's physical App Attest gate still
-- controls when hosted finalization may be enabled.

-- ===========================================================================
-- SECTION 1 -- Durable result vocabulary
-- ===========================================================================

create type public.contest_standings_phase as enum (
  'provisional',
  'final'
);

create type public.contest_standings_reason as enum (
  'live',
  'awaiting_ingest',
  'under_review',
  'final'
);

create type public.contest_result_kind as enum (
  'winner',
  'all_donate',
  'void',
  'inconclusive'
);

create type public.contest_result_reason as enum (
  'sole_qualifier',
  'earliest_to_target',
  'integrity_score',
  'both_donate',
  'no_qualifying_participant',
  'tie_break_void',
  'tie_break_inconclusive',
  'review_timeout'
);

create type public.donation_obligation_kind as enum (
  'loser_to_winner_charity',
  'self_directed'
);

-- ===========================================================================
-- SECTION 2 -- Append-only snapshots, results, and obligations
-- ===========================================================================

create table public.contest_results (
  id                           uuid primary key default gen_random_uuid(),
  contest_id                   uuid not null
    references public.contests (id) on delete restrict,
  version                      integer not null default 1,
  supersedes_result_id         uuid,
  kind                         public.contest_result_kind not null,
  reason                       public.contest_result_reason not null,
  winner_participant_id        uuid,
  evidence_cutoff              timestamptz not null,
  scoring_version              text not null,
  integrity_configuration_version text not null,
  input_digest                 bytea not null,
  finalized_at                 timestamptz not null,
  created_at                   timestamptz not null default now(),

  constraint contest_results_identity_unique
    unique (id, contest_id),
  constraint contest_results_version_unique
    unique (contest_id, version),
  constraint contest_results_input_digest_unique
    unique (contest_id, input_digest),
  constraint contest_results_supersedes_fkey
    foreign key (supersedes_result_id, contest_id)
    references public.contest_results (id, contest_id)
    on delete restrict,
  constraint contest_results_winner_participant_fkey
    foreign key (contest_id, winner_participant_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint contest_results_version_positive
    check (version > 0),
  constraint contest_results_first_version_shape
    check (
      (version = 1 and supersedes_result_id is null)
      or (version > 1 and supersedes_result_id is not null)
    ),
  constraint contest_results_digest_sha256
    check (octet_length(input_digest) = 32),
  constraint contest_results_versions_bounded
    check (
      char_length(scoring_version) between 1 and 80
      and char_length(integrity_configuration_version) between 1 and 80
    ),
  constraint contest_results_times_finite
    check (
      pg_catalog.isfinite(evidence_cutoff)
      and pg_catalog.isfinite(finalized_at)
      and finalized_at >= evidence_cutoff
    ),
  constraint contest_results_kind_reason_shape
    check (
      (
        kind = 'winner'
        and winner_participant_id is not null
        and reason in (
          'sole_qualifier',
          'earliest_to_target',
          'integrity_score'
        )
      )
      or (
        kind = 'all_donate'
        and winner_participant_id is null
        and reason = 'both_donate'
      )
      or (
        kind = 'void'
        and winner_participant_id is null
        and reason in (
          'no_qualifying_participant',
          'tie_break_void'
        )
      )
      or (
        kind = 'inconclusive'
        and winner_participant_id is null
        and reason in (
          'tie_break_inconclusive',
          'review_timeout'
        )
      )
    )
);

-- D78 corrections will append later versions. M8.3c deliberately supports
-- only the first immutable result, while leaving the versioned shape in place.
create unique index contest_results_one_initial_result_idx
  on public.contest_results (contest_id)
  where supersedes_result_id is null;

comment on table public.contest_results is
  'Append-only D75 result versions. M8.3c writes only version 1; D78 may append corrections.';

create table public.contest_standing_snapshots (
  id                           uuid primary key default gen_random_uuid(),
  contest_id                   uuid not null
    references public.contests (id) on delete restrict,
  phase                        public.contest_standings_phase not null,
  reason                       public.contest_standings_reason not null,
  as_of                        timestamptz not null,
  scoring_version              text not null,
  integrity_configuration_version text not null,
  evidence_cutoff              timestamptz,
  result_id                    uuid,
  input_digest                 bytea not null,
  created_at                   timestamptz not null default now(),

  constraint contest_standing_snapshots_identity_unique
    unique (id, contest_id),
  constraint contest_standing_snapshots_input_digest_unique
    unique (contest_id, input_digest),
  constraint contest_standing_snapshots_result_unique
    unique (result_id),
  constraint contest_standing_snapshots_result_fkey
    foreign key (result_id, contest_id)
    references public.contest_results (id, contest_id)
    on delete restrict,
  constraint contest_standing_snapshots_digest_sha256
    check (octet_length(input_digest) = 32),
  constraint contest_standing_snapshots_versions_bounded
    check (
      char_length(scoring_version) between 1 and 80
      and char_length(integrity_configuration_version) between 1 and 80
    ),
  constraint contest_standing_snapshots_as_of_finite
    check (pg_catalog.isfinite(as_of)),
  constraint contest_standing_snapshots_phase_shape
    check (
      (
        phase = 'provisional'
        and reason in ('live', 'awaiting_ingest', 'under_review')
        and evidence_cutoff is null
        and result_id is null
      )
      or (
        phase = 'final'
        and reason = 'final'
        and evidence_cutoff is not null
        and result_id is not null
        and pg_catalog.isfinite(evidence_cutoff)
        and as_of >= evidence_cutoff
      )
    )
);

create index contest_standing_snapshots_latest_idx
  on public.contest_standing_snapshots (
    contest_id,
    phase,
    as_of desc,
    created_at desc
  );

comment on table public.contest_standing_snapshots is
  'Append-only complete scoring snapshots. Provisional rows are presentation only; final rows bind one immutable result.';

create table public.contest_standing_entries (
  snapshot_id        uuid not null,
  contest_id         uuid not null,
  participant_id     uuid not null,
  display_order      smallint not null,
  rank               smallint not null,
  qualified          boolean not null,
  total              numeric(18, 2) not null,
  qualifying_days    smallint not null,
  scoreable_days     smallint not null,
  day_rate           numeric(9, 8) not null,
  reached_target_at  timestamptz,
  integrity_score    numeric(5, 2) not null,
  integrity_flags    jsonb not null default '[]'::jsonb,
  rationale          jsonb not null default '[]'::jsonb,
  created_at         timestamptz not null default now(),

  primary key (snapshot_id, participant_id),
  constraint contest_standing_entries_snapshot_fkey
    foreign key (snapshot_id, contest_id)
    references public.contest_standing_snapshots (id, contest_id)
    on delete restrict,
  constraint contest_standing_entries_participant_fkey
    foreign key (contest_id, participant_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint contest_standing_entries_order_unique
    unique (snapshot_id, display_order),
  constraint contest_standing_entries_order_range
    check (display_order between 1 and 20 and rank between 1 and 20),
  constraint contest_standing_entries_totals_nonnegative
    check (total >= 0),
  constraint contest_standing_entries_days_valid
    check (
      qualifying_days between 0 and 366
      and scoreable_days between 0 and 366
      and qualifying_days <= scoreable_days
      and day_rate between 0 and 1
    ),
  constraint contest_standing_entries_integrity_range
    check (integrity_score between 0 and 100),
  constraint contest_standing_entries_reached_target_finite
    check (
      reached_target_at is null
      or pg_catalog.isfinite(reached_target_at)
    ),
  constraint contest_standing_entries_flags_array
    check (jsonb_typeof(integrity_flags) = 'array'),
  constraint contest_standing_entries_rationale_array
    check (jsonb_typeof(rationale) = 'array')
);

comment on table public.contest_standing_entries is
  'Complete trusted scoring output. The read RPC redacts rival integrity fields while a snapshot is provisional.';

create table public.donation_obligations (
  id                        uuid primary key default gen_random_uuid(),
  result_id                 uuid not null,
  contest_id                uuid not null,
  debtor_participant_id     uuid not null,
  destination_owner_id      uuid not null,
  kind                      public.donation_obligation_kind not null,
  amount_cents              integer not null,
  charity_id                uuid not null
    references public.charities (id) on delete restrict,
  charity_name              text not null,
  charity_ein               text not null,
  charity_slug              text not null,
  result_dispute_closes_at  timestamptz not null,
  created_at                timestamptz not null default now(),

  constraint donation_obligations_result_fkey
    foreign key (result_id, contest_id)
    references public.contest_results (id, contest_id)
    on delete restrict,
  constraint donation_obligations_debtor_fkey
    foreign key (contest_id, debtor_participant_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint donation_obligations_destination_owner_fkey
    foreign key (contest_id, destination_owner_id)
    references public.contest_participants (contest_id, user_id)
    on delete restrict,
  constraint donation_obligations_one_per_debtor
    unique (result_id, debtor_participant_id),
  constraint donation_obligations_amount_range
    check (amount_cents between 100 and 1000000),
  constraint donation_obligations_charity_snapshot
    check (
      char_length(charity_name) between 1 and 120
      and charity_ein ~ '^[0-9]{2}-[0-9]{7}$'
      and charity_slug ~ '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'
    ),
  constraint donation_obligations_kind_shape
    check (
      (
        kind = 'loser_to_winner_charity'
        and debtor_participant_id <> destination_owner_id
      )
      or (
        kind = 'self_directed'
        and debtor_participant_id = destination_owner_id
      )
    ),
  constraint donation_obligations_dispute_close_finite
    check (pg_catalog.isfinite(result_dispute_closes_at))
);

create index donation_obligations_contest_debtor_idx
  on public.donation_obligations (contest_id, debtor_participant_id);

comment on table public.donation_obligations is
  'One immutable D75 obligation per debtor. result_dispute_closes_at is the earliest possible actionability boundary, not proof that D78 disputes are resolved.';

-- Results, snapshots, and obligations are immutable facts. Future corrections
-- append new versions/events; they never rewrite the first verdict.
create trigger contest_results_forbid_mutation
  before update or delete or truncate on public.contest_results
  for each statement execute function app.forbid_mutation();

create trigger contest_standing_snapshots_forbid_mutation
  before update or delete or truncate on public.contest_standing_snapshots
  for each statement execute function app.forbid_mutation();

create trigger contest_standing_entries_forbid_mutation
  before update or delete or truncate on public.contest_standing_entries
  for each statement execute function app.forbid_mutation();

create trigger donation_obligations_forbid_mutation
  before update or delete or truncate on public.donation_obligations
  for each statement execute function app.forbid_mutation();

-- ===========================================================================
-- SECTION 3 -- Close the existing check-in/finality race
-- ===========================================================================

-- Metric snapshots already re-check contest status in their BEFORE INSERT
-- trigger. Check-ins previously checked only before their INSERT statement.
-- This trigger gives both ledgers the same final status check after any table
-- lock wait imposed by finalization.
create function app.assert_geofence_checkin_window_open()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status   public.contest_status;
  v_ends_at  timestamptz;
begin
  select contest.status, contest.ends_at
    into v_status, v_ends_at
  from public.contests contest
  where contest.id = new.contest_id;

  if v_status is null then
    raise exception 'contest % does not exist', new.contest_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_status <> 'active' then
    raise exception
      'contest % is not accepting check-ins (status %)',
      new.contest_id,
      v_status
      using errcode = 'restrict_violation';
  end if;

  if clock_timestamp() >= v_ends_at + app.ingest_grace_period() then
    raise exception
      'the check-in window for contest % closed at %',
      new.contest_id,
      v_ends_at + app.ingest_grace_period()
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger geofence_checkins_assert_window_open
  before insert on public.geofence_checkins
  for each row execute function app.assert_geofence_checkin_window_open();

-- ===========================================================================
-- SECTION 4 -- Trusted publish/finalize boundary
-- ===========================================================================

create function public.publish_contest_standings_v1(
  p_contest_id                     uuid,
  p_as_of                          timestamptz,
  p_scoring_version                text,
  p_integrity_configuration_version text,
  p_standings                      jsonb,
  p_outcome                        jsonb default null,
  p_evidence_cutoff                timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_contest              public.contests;
  v_phase                public.contest_standings_phase;
  v_reason               public.contest_standings_reason;
  v_accepted_ids         uuid[];
  v_supplied_ids         uuid[];
  v_outcome_ids          uuid[];
  v_accepted_count       integer;
  v_supplied_count       integer;
  v_distinct_count       integer;
  v_qualified_count      integer;
  v_canonical_standings  jsonb;
  v_canonical_outcome    jsonb;
  v_input_digest         bytea;
  v_existing_snapshot_id uuid;
  v_snapshot_id          uuid;
  v_result_id            uuid;
  v_result_kind          public.contest_result_kind;
  v_result_reason        public.contest_result_reason;
  v_winner_id            uuid;
  v_grace_close          timestamptz;
  v_finalized_at         timestamptz;
begin
  if p_contest_id is null
     or p_as_of is null
     or p_scoring_version is null
     or p_integrity_configuration_version is null
     or p_standings is null
  then
    raise exception
      'contest, as-of, scoring version, integrity version, and standings are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if not pg_catalog.isfinite(p_as_of)
     or p_as_of > clock_timestamp() + interval '1 second'
  then
    raise exception 'standings as-of must be a finite server-present instant'
      using errcode = 'invalid_parameter_value';
  end if;

  if char_length(p_scoring_version) not between 1 and 80
     or char_length(p_integrity_configuration_version) not between 1 and 80
  then
    raise exception 'scoring and integrity versions must contain 1 to 80 characters'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_typeof(p_standings) <> 'array'
     or jsonb_array_length(p_standings) not between 2 and 20
  then
    raise exception 'standings must be a complete array of 2 to 20 participants'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    where jsonb_typeof(item) <> 'object'
       or not (
         item ?& array[
           'participant_id',
           'display_order',
           'rank',
           'qualified',
           'total',
           'qualifying_days',
           'scoreable_days',
           'day_rate',
           'reached_target_at',
           'integrity_score',
           'integrity_flags',
           'rationale'
         ]
       )
       or item - array[
         'participant_id',
         'display_order',
         'rank',
         'qualified',
         'total',
         'qualifying_days',
         'scoreable_days',
         'day_rate',
         'reached_target_at',
         'integrity_score',
         'integrity_flags',
         'rationale'
       ]::text[] <> '{}'::jsonb
       or jsonb_typeof(item -> 'integrity_flags') <> 'array'
       or jsonb_typeof(item -> 'rationale') <> 'array'
  ) then
    raise exception 'every standing must use the exact version-1 field set'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    cross join lateral jsonb_array_elements(item -> 'integrity_flags') flag
    where jsonb_typeof(flag) <> 'string'
       or char_length(flag #>> '{}') not between 1 and 80
  ) then
    raise exception 'integrity flags must be bounded rule-code strings'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_standings) item
    cross join lateral jsonb_array_elements(item -> 'rationale') rationale
    where jsonb_typeof(rationale) <> 'object'
       or not (rationale ?& array['code', 'summary', 'points'])
       or rationale - array['code', 'summary', 'points']::text[] <> '{}'::jsonb
       or jsonb_typeof(rationale -> 'code') <> 'string'
       or char_length(rationale ->> 'code') not between 1 and 80
       or jsonb_typeof(rationale -> 'summary') <> 'string'
       or char_length(rationale ->> 'summary') not between 1 and 240
       or jsonb_typeof(rationale -> 'points') <> 'number'
       or (rationale ->> 'points')::numeric not between -100 and 100
  ) then
    raise exception
      'rationale may contain only bounded code, summary, and points fields'
      using errcode = 'invalid_parameter_value';
  end if;

  select jsonb_agg(item order by (item ->> 'display_order')::integer)
    into v_canonical_standings
  from jsonb_array_elements(p_standings) item;

  -- Finalization's table locks linearize against every INSERT already in
  -- progress and every INSERT that begins before the contest status flips.
  if p_outcome is not null then
    lock table public.metric_snapshots,
               public.geofence_checkins
      in share row exclusive mode;
  end if;

  select contest.*
    into v_contest
  from public.contests contest
  where contest.id = p_contest_id
  for update;

  if v_contest.id is null then
    raise exception 'contest not found'
      using errcode = 'foreign_key_violation';
  end if;

  select
    array_agg(participant.user_id order by participant.user_id),
    count(*)::integer
    into v_accepted_ids, v_accepted_count
  from public.contest_participants participant
  where participant.contest_id = p_contest_id
    and participant.status = 'accepted';

  with supplied as (
    select *
    from jsonb_to_recordset(v_canonical_standings) as entry (
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
  )
  select
    array_agg(participant_id order by participant_id),
    count(*)::integer,
    count(distinct participant_id)::integer,
    count(*) filter (where qualified)::integer
    into
      v_supplied_ids,
      v_supplied_count,
      v_distinct_count,
      v_qualified_count
  from supplied;

  if v_accepted_count not between 2 and 20
     or v_supplied_count <> v_accepted_count
     or v_distinct_count <> v_supplied_count
     or v_supplied_ids is distinct from v_accepted_ids
  then
    raise exception 'standings must exactly match the complete accepted roster'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(v_canonical_standings) as entry (
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
    where participant_id is null
       or display_order not between 1 and v_accepted_count
       or rank not between 1 and v_accepted_count
       or qualified is null
       or total is null
       or total < 0
       or qualifying_days not between 0 and 366
       or scoreable_days not between 0 and 366
       or qualifying_days > scoreable_days
       or day_rate not between 0 and 1
       or reached_target_at is not null
          and (
            not pg_catalog.isfinite(reached_target_at)
            or reached_target_at < v_contest.starts_at
            or reached_target_at > v_contest.ends_at
          )
       or integrity_score not between 0 and 100
  ) then
    raise exception 'standing values are outside the version-1 domain'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    with supplied as (
      select *
      from jsonb_to_recordset(v_canonical_standings) as entry (
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
    ),
    expected as (
      select
        participant_id,
        display_order,
        rank,
        case
          when v_contest.cadence = 'daily'
            then rank() over (order by day_rate desc, total desc)
          else rank() over (order by total desc)
        end as expected_rank,
        case
          when v_contest.cadence = 'daily'
            then row_number() over (
              order by
                day_rate desc,
                total desc,
                reached_target_at asc nulls last,
                participant_id
            )
          else row_number() over (
            order by
              total desc,
              reached_target_at asc nulls last,
              participant_id
          )
        end as expected_order
      from supplied
    )
    select 1
    from expected
    where rank <> expected_rank
       or display_order <> expected_order
  ) then
    raise exception 'display order or competition rank contradicts the scoring output'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_contest.cadence = 'cumulative'
     and exists (
       select 1
       from jsonb_to_recordset(v_canonical_standings) as entry (
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
       where qualifying_days <> 0
          or scoreable_days <> 0
          or day_rate <> 0
     )
  then
    raise exception 'cumulative standings cannot carry daily-rate fields'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_outcome is null then
    v_phase := 'provisional';
    v_reason := case
      when p_as_of < v_contest.ends_at
        then 'live'::public.contest_standings_reason
      when p_as_of < v_contest.ends_at + app.ingest_grace_period()
        then 'awaiting_ingest'::public.contest_standings_reason
      else 'under_review'::public.contest_standings_reason
    end;

    if p_evidence_cutoff is not null then
      raise exception 'provisional standings cannot claim a frozen evidence cutoff'
        using errcode = 'invalid_parameter_value';
    end if;

    if v_contest.status <> 'active' then
      raise exception 'only an active contest may publish provisional standings'
        using errcode = 'restrict_violation';
    end if;

    v_canonical_outcome := null;
  else
    v_phase := 'final';
    v_reason := 'final';
    v_grace_close := v_contest.ends_at + app.ingest_grace_period();

    if p_evidence_cutoff is null
       or not pg_catalog.isfinite(p_evidence_cutoff)
       or p_evidence_cutoff <> v_grace_close
    then
      raise exception 'final evidence cutoff must equal the server ingest-grace close'
        using errcode = 'invalid_parameter_value';
    end if;

    if clock_timestamp() < v_grace_close or p_as_of < v_grace_close then
      raise exception 'a contest cannot finalize before ingest grace closes'
        using errcode = 'restrict_violation';
    end if;

    if jsonb_typeof(p_outcome) <> 'object'
       or jsonb_typeof(p_outcome -> 'kind') <> 'string'
       or jsonb_typeof(p_outcome -> 'reason') <> 'string'
    then
      raise exception 'final outcome must name one kind and reason'
        using errcode = 'invalid_parameter_value';
    end if;

    v_result_kind := (p_outcome ->> 'kind')::public.contest_result_kind;
    v_result_reason := (p_outcome ->> 'reason')::public.contest_result_reason;

    if v_result_kind = 'winner' then
      if not (p_outcome ?& array['kind', 'reason', 'participant_id'])
         or p_outcome - array['kind', 'reason', 'participant_id']::text[]
            <> '{}'::jsonb
      then
        raise exception 'winner outcome must use kind, reason, and participant_id'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := (p_outcome ->> 'participant_id')::uuid;

      if not (v_winner_id = any(v_accepted_ids))
         or not exists (
           select 1
           from jsonb_to_recordset(v_canonical_standings) as entry (
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
           where participant_id = v_winner_id
             and qualified
         )
      then
        raise exception 'winner must be one qualified accepted participant'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_result_reason = 'sole_qualifier' then
        if v_qualified_count <> 1 then
          raise exception 'sole-qualifier result requires exactly one qualifier'
            using errcode = 'invalid_parameter_value';
        end if;
      elsif v_result_reason = 'earliest_to_target' then
        if v_contest.tie_break <> 'earliest_to_target'
           or v_qualified_count < 2
        then
          raise exception 'earliest winner contradicts the agreed tie-break'
            using errcode = 'invalid_parameter_value';
        end if;

        if not exists (
          with qualified as (
            select
              participant_id,
              qualified,
              reached_target_at
            from jsonb_to_recordset(v_canonical_standings) as entry (
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
          )
          select 1
          from qualified candidate
          where candidate.participant_id = v_winner_id
            and candidate.qualified
            and candidate.reached_target_at is not null
            and not exists (
              select 1
              from qualified rival
              where rival.qualified
                and rival.participant_id <> candidate.participant_id
                and rival.reached_target_at is not null
                and rival.reached_target_at <= candidate.reached_target_at
            )
        ) then
          raise exception
            'earliest winner must be the unique earliest qualified participant'
            using errcode = 'invalid_parameter_value';
        end if;
      elsif v_result_reason = 'integrity_score' then
        if v_contest.tie_break <> 'integrity_score'
           or v_qualified_count < 2
        then
          raise exception 'integrity winner contradicts the agreed tie-break'
            using errcode = 'invalid_parameter_value';
        end if;

        if not exists (
          with qualified as (
            select
              participant_id,
              qualified,
              integrity_score
            from jsonb_to_recordset(v_canonical_standings) as entry (
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
          )
          select 1
          from qualified candidate
          where candidate.participant_id = v_winner_id
            and candidate.qualified
            and not exists (
              select 1
              from qualified rival
              where rival.qualified
                and rival.participant_id <> candidate.participant_id
                and rival.integrity_score >= candidate.integrity_score
            )
        ) then
          raise exception
            'integrity winner must have the unique highest qualified score'
            using errcode = 'invalid_parameter_value';
        end if;
      else
        raise exception 'winner result reason is invalid'
          using errcode = 'invalid_parameter_value';
      end if;

      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason,
        'participant_id', v_winner_id
      );
    elsif v_result_kind = 'all_donate' then
      if not (p_outcome ?& array['kind', 'reason', 'participant_ids'])
         or p_outcome - array['kind', 'reason', 'participant_ids']::text[]
            <> '{}'::jsonb
         or jsonb_typeof(p_outcome -> 'participant_ids') <> 'array'
      then
        raise exception
          'all-donate outcome must use kind, reason, and participant_ids'
          using errcode = 'invalid_parameter_value';
      end if;

      select array_agg((item #>> '{}')::uuid order by (item #>> '{}')::uuid)
        into v_outcome_ids
      from jsonb_array_elements(p_outcome -> 'participant_ids') item;

      if v_result_reason <> 'both_donate'
         or v_contest.tie_break <> 'both_donate'
         or v_qualified_count < 2
         or v_outcome_ids is distinct from v_accepted_ids
      then
        raise exception
          'all-donate must name the complete accepted roster and agreed tie-break'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason,
        'participant_ids', to_jsonb(v_accepted_ids)
      );
    elsif v_result_kind = 'void' then
      if not (p_outcome ?& array['kind', 'reason'])
         or p_outcome - array['kind', 'reason']::text[] <> '{}'::jsonb
         or not (
           (
             v_result_reason = 'no_qualifying_participant'
             and v_qualified_count = 0
           )
           or (
             v_result_reason = 'tie_break_void'
             and v_contest.tie_break = 'void'
             and v_qualified_count >= 2
           )
         )
      then
        raise exception 'void result contradicts qualification or the agreed tie-break'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason
      );
    elsif v_result_kind = 'inconclusive' then
      if not (p_outcome ?& array['kind', 'reason'])
         or p_outcome - array['kind', 'reason']::text[] <> '{}'::jsonb
         or v_result_reason <> 'tie_break_inconclusive'
         or v_contest.tie_break not in ('earliest_to_target', 'integrity_score')
         or v_qualified_count < 2
      then
        raise exception
          'M8.3c only accepts a deterministic tie-break inconclusive result'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_contest.tie_break = 'earliest_to_target'
         and exists (
           with qualified as (
             select
               participant_id,
               qualified,
               reached_target_at
             from jsonb_to_recordset(v_canonical_standings) as entry (
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
           )
           select 1
           from qualified candidate
           where candidate.qualified
             and candidate.reached_target_at is not null
             and not exists (
               select 1
               from qualified rival
               where rival.qualified
                 and rival.participant_id <> candidate.participant_id
                 and rival.reached_target_at is not null
                 and rival.reached_target_at <= candidate.reached_target_at
             )
         )
      then
        raise exception
          'inconclusive result contradicts a unique earliest qualifier'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_contest.tie_break = 'integrity_score'
         and exists (
           with qualified as (
             select
               participant_id,
               qualified,
               integrity_score
             from jsonb_to_recordset(v_canonical_standings) as entry (
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
           )
           select 1
           from qualified candidate
           where candidate.qualified
             and not exists (
               select 1
               from qualified rival
               where rival.qualified
                 and rival.participant_id <> candidate.participant_id
                 and rival.integrity_score >= candidate.integrity_score
             )
         )
      then
        raise exception
          'inconclusive result contradicts a unique integrity-score winner'
          using errcode = 'invalid_parameter_value';
      end if;

      v_winner_id := null;
      v_canonical_outcome := jsonb_build_object(
        'kind', v_result_kind,
        'reason', v_result_reason
      );
    end if;

    if exists (
      select 1
      from public.evidence_quarantine_status quarantine
      where quarantine.contest_id = p_contest_id
        and quarantine.state <> 'approved'
    ) then
      raise exception 'evidence review is unresolved'
        using errcode = 'restrict_violation';
    end if;
  end if;

  v_input_digest := extensions.digest(
    jsonb_build_object(
      'contest_id', p_contest_id,
      'phase', v_phase,
      'as_of', p_as_of,
      'scoring_version', p_scoring_version,
      'integrity_configuration_version',
        p_integrity_configuration_version,
      'evidence_cutoff', p_evidence_cutoff,
      'standings', v_canonical_standings,
      'outcome', v_canonical_outcome
    )::text,
    'sha256'
  );

  select snapshot.id
    into v_existing_snapshot_id
  from public.contest_standing_snapshots snapshot
  where snapshot.contest_id = p_contest_id
    and snapshot.input_digest = v_input_digest;

  if found then
    return v_existing_snapshot_id;
  end if;

  if v_phase = 'final' and v_contest.status = 'finalized' then
    raise exception 'contest already has a different immutable result'
      using errcode = 'unique_violation';
  end if;

  if v_phase = 'final' and v_contest.status <> 'active' then
    raise exception 'only an active contest may finalize'
      using errcode = 'restrict_violation';
  end if;

  if v_phase = 'final' then
    v_finalized_at := clock_timestamp();

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
      p_contest_id,
      1,
      v_result_kind,
      v_result_reason,
      v_winner_id,
      p_evidence_cutoff,
      p_scoring_version,
      p_integrity_configuration_version,
      v_input_digest,
      v_finalized_at
    )
    returning id into v_result_id;
  end if;

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
    p_contest_id,
    v_phase,
    v_reason,
    p_as_of,
    p_scoring_version,
    p_integrity_configuration_version,
    p_evidence_cutoff,
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
    p_contest_id,
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
  from jsonb_to_recordset(v_canonical_standings) as entry (
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

  if v_result_kind = 'winner' then
    insert into public.donation_obligations (
      result_id,
      contest_id,
      debtor_participant_id,
      destination_owner_id,
      kind,
      amount_cents,
      charity_id,
      charity_name,
      charity_ein,
      charity_slug,
      result_dispute_closes_at,
      created_at
    )
    select
      v_result_id,
      p_contest_id,
      debtor.user_id,
      winner.user_id,
      'loser_to_winner_charity',
      v_contest.stake_amount_cents,
      winner.charity_id,
      charity.name,
      charity.ein,
      charity.slug::text,
      v_finalized_at + interval '7 days',
      v_finalized_at
    from public.contest_participants debtor
    join public.contest_participants winner
      on winner.contest_id = debtor.contest_id
     and winner.user_id = v_winner_id
     and winner.status = 'accepted'
    join public.charities charity on charity.id = winner.charity_id
    where debtor.contest_id = p_contest_id
      and debtor.status = 'accepted'
      and debtor.user_id <> v_winner_id
    order by debtor.user_id;
  elsif v_result_kind = 'all_donate' then
    insert into public.donation_obligations (
      result_id,
      contest_id,
      debtor_participant_id,
      destination_owner_id,
      kind,
      amount_cents,
      charity_id,
      charity_name,
      charity_ein,
      charity_slug,
      result_dispute_closes_at,
      created_at
    )
    select
      v_result_id,
      p_contest_id,
      participant.user_id,
      participant.user_id,
      'self_directed',
      v_contest.stake_amount_cents,
      participant.charity_id,
      charity.name,
      charity.ein,
      charity.slug::text,
      v_finalized_at + interval '7 days',
      v_finalized_at
    from public.contest_participants participant
    join public.charities charity on charity.id = participant.charity_id
    where participant.contest_id = p_contest_id
      and participant.status = 'accepted'
    order by participant.user_id;
  end if;

  if v_phase = 'final' then
    update public.contests
    set status = 'finalized'
    where id = p_contest_id;

    perform app.ensure_contest_workflow_scope(p_contest_id);
  end if;

  return v_snapshot_id;
end;
$$;

comment on function public.publish_contest_standings_v1(
  uuid, timestamptz, text, text, jsonb, jsonb, timestamptz
) is
  'Trusted M7 boundary. Publishes complete provisional standings or atomically freezes one first result and its D75 obligations.';

-- Result creation, not a client read, owns the durable finalization intent.
create function app.emit_contest_result_intents()
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
      'contest_finalized'::public.notification_event_type,
      new.contest_id
    );
  end loop;

  return new;
end;
$$;

create trigger contest_results_emit_intents
  after insert on public.contest_results
  for each row execute function app.emit_contest_result_intents();

-- ===========================================================================
-- SECTION 5 -- Canonical D77 participant read surface
-- ===========================================================================

create function public.get_contest_standings_v1(p_contest_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller_id  uuid;
  v_snapshot   public.contest_standing_snapshots;
  v_result     public.contest_results;
  v_standings  jsonb;
  v_result_doc jsonb;
begin
  if p_contest_id is null then
    raise exception 'contest id is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_caller_id := app.require_active_caller();

  if not exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = p_contest_id
      and participant.user_id = v_caller_id
      and participant.status = 'accepted'
  ) then
    raise exception 'only an accepted participant may read standings'
      using errcode = 'insufficient_privilege';
  end if;

  select snapshot.*
    into v_snapshot
  from public.contest_standing_snapshots snapshot
  join public.contests contest on contest.id = snapshot.contest_id
  where snapshot.contest_id = p_contest_id
    and (
      (contest.status = 'finalized' and snapshot.phase = 'final')
      or (contest.status = 'active' and snapshot.phase = 'provisional')
    )
  order by
    case when snapshot.phase = 'final' then 0 else 1 end,
    snapshot.as_of desc,
    snapshot.created_at desc,
    snapshot.id desc
  limit 1;

  if v_snapshot.id is null then
    return null;
  end if;

  if v_snapshot.result_id is not null then
    select result.*
      into v_result
    from public.contest_results result
    where result.id = v_snapshot.result_id
      and result.contest_id = p_contest_id;

    v_result_doc := jsonb_strip_nulls(
      jsonb_build_object(
        'id', v_result.id,
        'kind', v_result.kind,
        'reason', v_result.reason,
        'winner_participant_id', v_result.winner_participant_id,
        'evidence_cutoff', v_result.evidence_cutoff,
        'finalized_at', v_result.finalized_at
      )
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'participant_id', entry.participant_id,
          'display_name',
            case
              when profile.deleted_at is not null then 'Former participant'
              else coalesce(nullif(profile.display_name, ''), 'Participant')
            end,
          'handle',
            case
              when profile.deleted_at is not null then null
              else profile.handle::text
            end,
          'display_order', entry.display_order,
          'rank', entry.rank,
          'qualified', entry.qualified,
          'total', entry.total,
          'qualifying_days', entry.qualifying_days,
          'scoreable_days', entry.scoreable_days,
          'day_rate', entry.day_rate,
          'reached_target_at', entry.reached_target_at,
          'integrity_score',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.integrity_score
              else null
            end,
          'integrity_flags',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.integrity_flags
              else null
            end,
          'rationale',
            case
              when v_snapshot.phase = 'final'
                   or entry.participant_id = v_caller_id
                then entry.rationale
              else null
            end,
          'obligation',
            case
              when obligation.id is null then null
              else jsonb_build_object(
                'id', obligation.id,
                'kind', obligation.kind,
                'amount_cents', obligation.amount_cents,
                'charity_id', obligation.charity_id,
                'charity_name', obligation.charity_name,
                'charity_slug', obligation.charity_slug,
                'destination_owner_id', obligation.destination_owner_id,
                'result_dispute_closes_at',
                  obligation.result_dispute_closes_at
              )
            end
        )
      )
      order by entry.display_order
    ),
    '[]'::jsonb
  )
    into v_standings
  from public.contest_standing_entries entry
  join public.profiles profile on profile.id = entry.participant_id
  left join public.donation_obligations obligation
    on obligation.result_id = v_snapshot.result_id
   and obligation.contest_id = entry.contest_id
   and obligation.debtor_participant_id = entry.participant_id
   and obligation.debtor_participant_id = v_caller_id
  where entry.snapshot_id = v_snapshot.id
    and entry.contest_id = p_contest_id;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'contest_id', p_contest_id,
      'snapshot_id', v_snapshot.id,
      'phase', v_snapshot.phase,
      'reason', v_snapshot.reason,
      'as_of', v_snapshot.as_of,
      'scoring_version', v_snapshot.scoring_version,
      'integrity_configuration_version',
        v_snapshot.integrity_configuration_version,
      'result', v_result_doc,
      'standings', v_standings
    )
  );
end;
$$;

comment on function public.get_contest_standings_v1(uuid) is
  'Canonical D77 read surface. Accepted participants only; rival integrity detail is redacted until final.';

-- ===========================================================================
-- SECTION 6 -- RLS and least privilege
-- ===========================================================================

alter table public.contest_results enable row level security;
alter table public.contest_standing_snapshots enable row level security;
alter table public.contest_standing_entries enable row level security;
alter table public.donation_obligations enable row level security;

-- There are intentionally no client policies. Even accepted participants read
-- through the function above so phase-specific redaction cannot be bypassed.
revoke all on table public.contest_results,
                         public.contest_standing_snapshots,
                         public.contest_standing_entries,
                         public.donation_obligations
  from public, anon, authenticated, service_role;

grant select on table public.contest_results,
                      public.contest_standing_snapshots,
                      public.contest_standing_entries,
                      public.donation_obligations
  to service_role;

revoke all on function public.publish_contest_standings_v1(
  uuid, timestamptz, text, text, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.publish_contest_standings_v1(
  uuid, timestamptz, text, text, jsonb, jsonb, timestamptz
) to service_role;

revoke all on function public.get_contest_standings_v1(uuid)
  from public, anon, service_role;
grant execute on function public.get_contest_standings_v1(uuid)
  to authenticated;

revoke all on function app.assert_geofence_checkin_window_open(),
                       app.emit_contest_result_intents()
  from public, anon, authenticated, service_role;
