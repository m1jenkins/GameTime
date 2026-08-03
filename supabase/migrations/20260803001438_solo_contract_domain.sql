-- Step 2A -- owner-only Solo contract domain.
--
-- This aggregate is intentionally separate from the transitional Personal V1
-- challenge tables and from every historical social contest. It introduces no
-- processor, payment method, authorization, charge, transfer, or payout row.

create type public.solo_contract_status as enum (
  'scheduled',
  'active',
  'awaiting_evaluation',
  'preliminary_failure',
  'appeal_pending',
  'ready_to_settle',
  'settled',
  'cancelled'
);

create type public.solo_settlement_mode as enum ('test_only');

create type public.solo_settlement_disposition as enum (
  'released',
  'forfeited',
  'waived',
  'cancelled'
);

create type public.solo_evaluation_outcome as enum (
  'passed',
  'failed',
  'inconclusive'
);

create type public.solo_appeal_event_kind as enum ('filed', 'decided');

create type public.solo_appeal_decision as enum (
  'upheld',
  'denied',
  'waived'
);

-- ---------------------------------------------------------------------------
-- Private policy, rollout, eligibility, and exact-request state
-- ---------------------------------------------------------------------------

create table app.solo_contract_policy_versions (
  version                       text primary key,
  policy_digest                 bytea not null unique,
  settlement_mode               public.solo_settlement_mode not null
    default 'test_only',
  minimum_commitment_minor      integer not null,
  maximum_commitment_minor      integer not null,
  minimum_duration_days         smallint not null,
  maximum_duration_days         smallint not null,
  evidence_grace                interval not null,
  appeal_window                 interval not null,
  created_at                    timestamptz not null default clock_timestamp(),

  constraint solo_policy_version_bounded check (
    char_length(version) between 1 and 80
  ),
  constraint solo_policy_digest_sha256 check (
    octet_length(policy_digest) = 32
  ),
  constraint solo_policy_test_only check (
    settlement_mode = 'test_only'
  ),
  constraint solo_policy_commitment_bounds check (
    minimum_commitment_minor = 1000
    and maximum_commitment_minor = 5000
  ),
  constraint solo_policy_duration_bounds check (
    minimum_duration_days = 1
    and maximum_duration_days = 7
  ),
  constraint solo_policy_windows_positive check (
    evidence_grace > interval '0 seconds'
    and appeal_window > interval '0 seconds'
  ),
  constraint solo_policy_created_at_finite check (
    pg_catalog.isfinite(created_at)
  ),
  unique (version, policy_digest)
);

comment on table app.solo_contract_policy_versions is
  'Append-only Solo policy registry. A contract copies both version and digest so reviewed terms cannot drift.';

insert into app.solo_contract_policy_versions (
  version,
  policy_digest,
  settlement_mode,
  minimum_commitment_minor,
  maximum_commitment_minor,
  minimum_duration_days,
  maximum_duration_days,
  evidence_grace,
  appeal_window
)
values (
  'solo-test-v1',
  extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'appeal_window_seconds', 604800,
        'currency', 'USD',
        'evidence_grace_seconds', 86400,
        'maximum_commitment_minor', 5000,
        'maximum_duration_days', 7,
        'minimum_commitment_minor', 1000,
        'minimum_duration_days', 1,
        'settlement_mode', 'test_only',
        'version', 'solo-test-v1'
      )::text,
      'UTF8'
    ),
    'sha256'
  ),
  'test_only',
  1000,
  5000,
  1,
  7,
  interval '24 hours',
  interval '7 days'
);

create table app.solo_contract_runtime (
  singleton               boolean primary key default true
    constraint solo_runtime_singleton check (singleton),
  contract_creation_enabled boolean not null default false,
  active_policy_version   text not null
    references app.solo_contract_policy_versions (version) on delete restrict,
  updated_at              timestamptz not null default clock_timestamp(),

  constraint solo_runtime_updated_at_finite check (
    pg_catalog.isfinite(updated_at)
  )
);

insert into app.solo_contract_runtime (
  singleton,
  contract_creation_enabled,
  active_policy_version
)
values (true, false, 'solo-test-v1');

comment on table app.solo_contract_runtime is
  'Authoritative server-side Solo creation switch and active policy pointer. The migration leaves creation disabled.';

create table app.solo_beta_eligibility (
  owner_id       uuid primary key
    references public.profiles (id) on delete restrict,
  eligible       boolean not null,
  created_at     timestamptz not null default clock_timestamp(),
  updated_at     timestamptz not null default clock_timestamp(),

  constraint solo_beta_times_finite check (
    pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
    and updated_at >= created_at
  )
);

comment on table app.solo_beta_eligibility is
  'Database-backed Solo beta allowlist. JWT user_metadata is never an authorization input.';

create table app.solo_rpc_requests (
  operation       text not null,
  request_scope   uuid not null,
  request_id      uuid not null,
  payload_hash    bytea not null,
  result          jsonb not null,
  created_at      timestamptz not null default clock_timestamp(),

  primary key (operation, request_scope, request_id),
  constraint solo_rpc_operation_bounded check (
    operation ~ '^[a-z][a-z0-9_]{2,79}$'
  ),
  constraint solo_rpc_payload_sha256 check (
    octet_length(payload_hash) = 32
  ),
  constraint solo_rpc_result_object check (
    pg_catalog.jsonb_typeof(result) = 'object'
  ),
  constraint solo_rpc_created_at_finite check (
    pg_catalog.isfinite(created_at)
  )
);

comment on table app.solo_rpc_requests is
  'Append-only exact-request ledger for every Step 2A Solo mutation.';

-- ---------------------------------------------------------------------------
-- Public owner records
-- ---------------------------------------------------------------------------

create table public.solo_contracts (
  id                         uuid primary key default gen_random_uuid(),
  owner_id                   uuid not null
    references public.profiles (id) on delete restrict,
  policy_version             text not null,
  policy_digest              bytea not null,
  metric                     public.contest_metric not null default 'steps',
  cadence                    public.contest_cadence not null,
  target_steps               integer not null,
  commitment_amount_minor    integer not null,
  currency                   text not null default 'USD',
  settlement_mode            public.solo_settlement_mode not null
    default 'test_only',
  timezone                   text not null,
  start_date                 date not null,
  duration_days              smallint not null,
  starts_at                  timestamptz not null,
  ends_at                    timestamptz not null,
  evidence_cutoff            timestamptz not null,
  locked_at                  timestamptz not null,
  status                     public.solo_contract_status not null
    default 'scheduled',
  state_changed_at           timestamptz not null,
  cancellation_reason        text,
  cancelled_at               timestamptz,
  settlement_disposition     public.solo_settlement_disposition,
  settled_at                 timestamptz,
  closed_at                  timestamptz,
  created_at                 timestamptz not null,

  constraint solo_contract_policy_fkey
    foreign key (policy_version, policy_digest)
    references app.solo_contract_policy_versions (version, policy_digest)
    on delete restrict,
  constraint solo_contract_metric_steps check (metric = 'steps'),
  constraint solo_contract_cadence_locked check (
    cadence in ('daily', 'cumulative')
  ),
  constraint solo_contract_target_bounded check (
    target_steps between 1 and 1000000
  ),
  constraint solo_contract_commitment_bounded check (
    commitment_amount_minor between 1000 and 5000
  ),
  constraint solo_contract_currency_usd check (currency = 'USD'),
  constraint solo_contract_test_only check (settlement_mode = 'test_only'),
  constraint solo_contract_duration_bounded check (
    duration_days between 1 and 7
  ),
  constraint solo_contract_window_ordered check (
    starts_at < ends_at
    and ends_at < evidence_cutoff
  ),
  constraint solo_contract_times_finite check (
    pg_catalog.isfinite(starts_at)
    and pg_catalog.isfinite(ends_at)
    and pg_catalog.isfinite(evidence_cutoff)
    and pg_catalog.isfinite(locked_at)
    and pg_catalog.isfinite(state_changed_at)
    and pg_catalog.isfinite(created_at)
    and (cancelled_at is null or pg_catalog.isfinite(cancelled_at))
    and (settled_at is null or pg_catalog.isfinite(settled_at))
    and (closed_at is null or pg_catalog.isfinite(closed_at))
  ),
  constraint solo_contract_policy_version_bounded check (
    char_length(policy_version) between 1 and 80
    and octet_length(policy_digest) = 32
  ),
  constraint solo_contract_cancellation_reason_bounded check (
    cancellation_reason is null
    or char_length(cancellation_reason) between 1 and 80
  ),
  constraint solo_contract_lifecycle_shape check (
    (
      status in (
        'scheduled', 'active', 'awaiting_evaluation',
        'preliminary_failure', 'appeal_pending', 'ready_to_settle'
      )
      and cancellation_reason is null
      and cancelled_at is null
      and settlement_disposition is null
      and settled_at is null
      and closed_at is null
    )
    or (
      status = 'cancelled'
      and cancellation_reason is not null
      and cancellation_reason in ('owner_cancelled', 'account_deleted')
      and cancelled_at is not null
      and settlement_disposition is not null
      and settlement_disposition = 'cancelled'
      and settled_at is null
      and closed_at is not null
      and closed_at = cancelled_at
      and state_changed_at = cancelled_at
      and cancelled_at < starts_at
    )
    or (
      status = 'settled'
      and cancellation_reason is null
      and cancelled_at is null
      and settlement_disposition is not null
      and settlement_disposition in ('released', 'forfeited', 'waived')
      and settled_at is not null
      and closed_at is not null
      and closed_at = settled_at
      and state_changed_at = settled_at
    )
  ),
  unique (id, owner_id, policy_version)
);

comment on table public.solo_contracts is
  'Owner-only Solo terms plus a guarded lifecycle projection. Terms lock at insert; logical test settlement moves no money.';
comment on column public.solo_contracts.settlement_disposition is
  'Logical test-only resolution. No processor authorization, capture, transfer, or charge exists in Step 2A.';

create unique index solo_contracts_one_unsettled_owner_idx
  on public.solo_contracts (owner_id)
  where closed_at is null;

create index solo_contracts_due_idx
  on public.solo_contracts (status, starts_at, evidence_cutoff);

create table public.solo_evaluations (
  id                         uuid primary key default gen_random_uuid(),
  contract_id                uuid not null,
  owner_id                   uuid not null,
  policy_version             text not null,
  outcome                    public.solo_evaluation_outcome not null,
  reason_code                text not null,
  evaluator_version          text not null,
  evidence_digest            bytea not null,
  request_id                 uuid not null,
  request_digest             bytea not null,
  evaluated_at               timestamptz not null,
  appeal_deadline            timestamptz,

  constraint solo_evaluation_contract_fkey
    foreign key (contract_id, owner_id, policy_version)
    references public.solo_contracts (id, owner_id, policy_version)
    on delete restrict,
  constraint solo_evaluation_one_preliminary unique (contract_id),
  constraint solo_evaluation_owner_request unique (owner_id, request_id),
  constraint solo_evaluation_identity unique (
    id, contract_id, owner_id, policy_version
  ),
  constraint solo_evaluation_reason_bounded check (
    reason_code ~ '^[a-z][a-z0-9_]{1,79}$'
  ),
  constraint solo_evaluator_version_bounded check (
    char_length(evaluator_version) between 1 and 80
  ),
  constraint solo_evaluation_digests_sha256 check (
    octet_length(evidence_digest) = 32
    and octet_length(request_digest) = 32
  ),
  constraint solo_evaluation_appeal_shape check (
    (outcome = 'failed' and appeal_deadline is not null)
    or (outcome <> 'failed' and appeal_deadline is null)
  ),
  constraint solo_evaluation_times_finite check (
    pg_catalog.isfinite(evaluated_at)
    and (appeal_deadline is null or pg_catalog.isfinite(appeal_deadline))
  )
);

comment on table public.solo_evaluations is
  'Append-only service-authored preliminary Solo evaluations. A failure opens one policy-locked appeal window.';

create table public.solo_appeals (
  id                         uuid primary key default gen_random_uuid(),
  contract_id                uuid not null,
  owner_id                   uuid not null,
  policy_version             text not null,
  preliminary_evaluation_id  uuid not null,
  event_kind                 public.solo_appeal_event_kind not null,
  filing_id                  uuid,
  statement                  text,
  decision                   public.solo_appeal_decision,
  decision_reason_code       text,
  reviewer_version           text,
  decision_digest            bytea,
  request_id                 uuid not null,
  request_digest             bytea not null,
  event_at                   timestamptz not null,

  constraint solo_appeal_contract_fkey
    foreign key (contract_id, owner_id, policy_version)
    references public.solo_contracts (id, owner_id, policy_version)
    on delete restrict,
  constraint solo_appeal_evaluation_fkey
    foreign key (
      preliminary_evaluation_id,
      contract_id,
      owner_id,
      policy_version
    )
    references public.solo_evaluations (
      id,
      contract_id,
      owner_id,
      policy_version
    )
    on delete restrict,
  constraint solo_appeal_owner_request unique (owner_id, request_id),
  constraint solo_appeal_identity unique (
    id, contract_id, owner_id, policy_version
  ),
  constraint solo_appeal_request_digest_sha256 check (
    octet_length(request_digest) = 32
  ),
  constraint solo_appeal_event_shape check (
    (
      event_kind = 'filed'
      and filing_id is null
      and statement is not null
      and char_length(statement) between 1 and 2000
      and decision is null
      and decision_reason_code is null
      and reviewer_version is null
      and decision_digest is null
    )
    or (
      event_kind = 'decided'
      and filing_id is not null
      and statement is null
      and decision is not null
      and decision_reason_code is not null
      and decision_reason_code ~ '^[a-z][a-z0-9_]{1,79}$'
      and reviewer_version is not null
      and char_length(reviewer_version) between 1 and 80
      and decision_digest is not null
      and octet_length(decision_digest) = 32
    )
  ),
  constraint solo_appeal_event_at_finite check (
    pg_catalog.isfinite(event_at)
  )
);

alter table public.solo_appeals
  add constraint solo_appeal_filing_fkey
  foreign key (filing_id, contract_id, owner_id, policy_version)
  references public.solo_appeals (id, contract_id, owner_id, policy_version)
  on delete restrict;

create unique index solo_appeals_one_filing_per_failure_idx
  on public.solo_appeals (preliminary_evaluation_id)
  where event_kind = 'filed';

create unique index solo_appeals_one_decision_per_filing_idx
  on public.solo_appeals (filing_id)
  where event_kind = 'decided';

comment on table public.solo_appeals is
  'Append-only Solo appeal event ledger: one filed event per preliminary failure and at most one immutable decided event.';

-- ---------------------------------------------------------------------------
-- Structural validation and write-path enforcement
-- ---------------------------------------------------------------------------

create function app.assert_solo_write_path()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_path text := pg_catalog.current_setting('app.solo_write_path', true);
begin
  if v_path is null or not (v_path = any (tg_argv)) then
    raise exception 'write to %.% must use a versioned Solo RPC',
      tg_table_schema, tg_table_name
      using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create function app.validate_solo_contract_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy app.solo_contract_policy_versions;
begin
  select policy.* into strict v_policy
  from app.solo_contract_policy_versions policy
  where policy.version = new.policy_version
    and policy.policy_digest = new.policy_digest;

  if not exists (
    select 1
    from pg_catalog.pg_timezone_names zone
    where zone.name = new.timezone
  ) then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if new.commitment_amount_minor not between
       v_policy.minimum_commitment_minor and v_policy.maximum_commitment_minor
     or new.duration_days not between
       v_policy.minimum_duration_days and v_policy.maximum_duration_days
     or new.settlement_mode <> v_policy.settlement_mode
  then
    raise exception 'Solo terms do not satisfy locked policy %', new.policy_version
      using errcode = 'check_violation';
  end if;

  if new.starts_at is distinct from
       (new.start_date::timestamp at time zone new.timezone)
     or new.ends_at is distinct from
       ((new.start_date + new.duration_days)::timestamp at time zone new.timezone)
     or new.evidence_cutoff is distinct from
       new.ends_at + v_policy.evidence_grace
  then
    raise exception 'Solo window does not match its frozen local dates and policy'
      using errcode = 'check_violation';
  end if;

  if new.status <> 'scheduled'
     or new.locked_at is distinct from new.created_at
     or new.state_changed_at is distinct from new.created_at
  then
    raise exception 'a Solo contract must be created scheduled and locked once'
      using errcode = 'check_violation';
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'unknown or mismatched Solo policy version %', new.policy_version
      using errcode = 'foreign_key_violation';
end;
$$;

create function app.enforce_solo_contract_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    if new.state_changed_at is distinct from old.state_changed_at
       or new.cancellation_reason is distinct from old.cancellation_reason
       or new.cancelled_at is distinct from old.cancelled_at
       or new.settlement_disposition is distinct from old.settlement_disposition
       or new.settled_at is distinct from old.settled_at
       or new.closed_at is distinct from old.closed_at
    then
      raise exception 'Solo lifecycle fields cannot change without a state transition'
        using errcode = 'restrict_violation';
    end if;
    return new;
  end if;

  if not (
    (old.status = 'scheduled' and new.status in ('active', 'cancelled'))
    or (old.status = 'active' and new.status = 'awaiting_evaluation')
    or (
      old.status = 'awaiting_evaluation'
      and new.status in ('preliminary_failure', 'ready_to_settle')
    )
    or (
      old.status = 'preliminary_failure'
      and new.status in ('appeal_pending', 'settled')
    )
    or (old.status = 'appeal_pending' and new.status = 'ready_to_settle')
    or (old.status = 'ready_to_settle' and new.status = 'settled')
  ) then
    raise exception 'Solo contract status cannot move from % to %',
      old.status, new.status
      using errcode = 'restrict_violation';
  end if;

  if new.state_changed_at < old.state_changed_at then
    raise exception 'Solo lifecycle timestamps cannot move backward'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create function app.validate_solo_evaluation_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contract public.solo_contracts;
  v_policy   app.solo_contract_policy_versions;
begin
  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = new.contract_id
  for update;

  if v_contract.owner_id <> new.owner_id
     or v_contract.policy_version <> new.policy_version
     or v_contract.status <> 'awaiting_evaluation'
     or new.evaluated_at < v_contract.evidence_cutoff
  then
    raise exception 'preliminary evaluation does not match an eligible Solo contract'
      using errcode = 'restrict_violation';
  end if;

  select policy.* into strict v_policy
  from app.solo_contract_policy_versions policy
  where policy.version = new.policy_version;

  if new.outcome = 'failed'
     and new.appeal_deadline is distinct from new.evaluated_at + v_policy.appeal_window
  then
    raise exception 'failure appeal deadline does not match locked policy'
      using errcode = 'check_violation';
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'Solo contract or policy not found for evaluation'
      using errcode = 'foreign_key_violation';
end;
$$;

create function app.validate_solo_appeal_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_evaluation public.solo_evaluations;
  v_filing     public.solo_appeals;
  v_contract   public.solo_contracts;
begin
  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = new.contract_id
  for update;

  select evaluation.* into strict v_evaluation
  from public.solo_evaluations evaluation
  where evaluation.id = new.preliminary_evaluation_id;

  if v_contract.owner_id <> new.owner_id
     or v_contract.policy_version <> new.policy_version
     or v_evaluation.contract_id <> new.contract_id
     or v_evaluation.owner_id <> new.owner_id
     or v_evaluation.policy_version <> new.policy_version
     or v_evaluation.outcome <> 'failed'
  then
    raise exception 'appeal must reference the matching preliminary failure'
      using errcode = 'restrict_violation';
  end if;

  if new.event_kind = 'filed' then
    if v_contract.status <> 'preliminary_failure'
       or new.event_at < v_evaluation.evaluated_at
       or new.event_at >= v_evaluation.appeal_deadline
    then
      raise exception 'appeal filing is outside its locked failure window'
        using errcode = 'restrict_violation';
    end if;
  else
    select appeal.* into strict v_filing
    from public.solo_appeals appeal
    where appeal.id = new.filing_id;

    if v_filing.event_kind <> 'filed'
       or v_filing.preliminary_evaluation_id <> new.preliminary_evaluation_id
       or v_contract.status <> 'appeal_pending'
       or new.event_at < v_filing.event_at
    then
      raise exception 'appeal decision must reference its filed event'
        using errcode = 'restrict_violation';
    end if;
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'preliminary failure or appeal filing not found'
      using errcode = 'foreign_key_violation';
end;
$$;

create trigger solo_contracts_require_versioned_insert
  before insert on public.solo_contracts
  for each row execute function app.assert_solo_write_path('create_v1');

create trigger solo_contracts_validate_insert
  before insert on public.solo_contracts
  for each row execute function app.validate_solo_contract_insert();

create trigger solo_contracts_require_versioned_update
  before update on public.solo_contracts
  for each row execute function app.assert_solo_write_path(
    'cancel_v1',
    'advance_v1',
    'evaluate_v1',
    'appeal_v1',
    'decide_appeal_v1',
    'settle_v1',
    'account_deletion_v1'
  );

create trigger solo_contracts_freeze_terms
  before update on public.solo_contracts
  for each row execute function app.forbid_column_change(
    'id',
    'owner_id',
    'policy_version',
    'policy_digest',
    'metric',
    'cadence',
    'target_steps',
    'commitment_amount_minor',
    'currency',
    'settlement_mode',
    'timezone',
    'start_date',
    'duration_days',
    'starts_at',
    'ends_at',
    'evidence_cutoff',
    'locked_at',
    'created_at'
  );

create trigger solo_contracts_enforce_lifecycle
  before update on public.solo_contracts
  for each row execute function app.enforce_solo_contract_lifecycle();

create trigger solo_contracts_forbid_delete
  before delete or truncate on public.solo_contracts
  for each statement execute function app.forbid_mutation();

create trigger solo_evaluations_require_versioned_insert
  before insert on public.solo_evaluations
  for each row execute function app.assert_solo_write_path('evaluate_v1');

create trigger solo_evaluations_validate_insert
  before insert on public.solo_evaluations
  for each row execute function app.validate_solo_evaluation_insert();

create trigger solo_evaluations_forbid_mutation
  before update or delete or truncate on public.solo_evaluations
  for each statement execute function app.forbid_mutation();

create trigger solo_appeals_require_versioned_insert
  before insert on public.solo_appeals
  for each row execute function app.assert_solo_write_path(
    'appeal_v1',
    'decide_appeal_v1'
  );

create trigger solo_appeals_validate_insert
  before insert on public.solo_appeals
  for each row execute function app.validate_solo_appeal_insert();

create trigger solo_appeals_forbid_mutation
  before update or delete or truncate on public.solo_appeals
  for each statement execute function app.forbid_mutation();

create trigger solo_policies_forbid_mutation
  before update or delete or truncate on app.solo_contract_policy_versions
  for each statement execute function app.forbid_mutation();

create trigger solo_runtime_require_versioned_update
  before update on app.solo_contract_runtime
  for each row execute function app.assert_solo_write_path('runtime_v1');

create trigger solo_runtime_forbid_delete
  before delete or truncate on app.solo_contract_runtime
  for each statement execute function app.forbid_mutation();

create trigger solo_beta_require_versioned_insert
  before insert on app.solo_beta_eligibility
  for each row execute function app.assert_solo_write_path('eligibility_v1');

create trigger solo_beta_require_versioned_update
  before update on app.solo_beta_eligibility
  for each row execute function app.assert_solo_write_path(
    'eligibility_v1',
    'account_deletion_v1'
  );

create trigger solo_beta_freeze_identity
  before update on app.solo_beta_eligibility
  for each row execute function app.forbid_column_change('owner_id', 'created_at');

create trigger solo_beta_forbid_delete
  before delete or truncate on app.solo_beta_eligibility
  for each statement execute function app.forbid_mutation();

create trigger solo_requests_forbid_mutation
  before update or delete or truncate on app.solo_rpc_requests
  for each statement execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Owner-only reads and no direct writes
-- ---------------------------------------------------------------------------

alter table public.solo_contracts enable row level security;
alter table public.solo_evaluations enable row level security;
alter table public.solo_appeals enable row level security;
alter table app.solo_contract_policy_versions enable row level security;
alter table app.solo_contract_runtime enable row level security;
alter table app.solo_beta_eligibility enable row level security;
alter table app.solo_rpc_requests enable row level security;

create policy solo_contracts_select_owner
  on public.solo_contracts
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy solo_evaluations_select_owner
  on public.solo_evaluations
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

create policy solo_appeals_select_owner
  on public.solo_appeals
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and app.is_active_actor((select auth.uid()))
  );

revoke all on table public.solo_contracts,
                    public.solo_evaluations,
                    public.solo_appeals
  from public, anon, authenticated, service_role;

grant select on table public.solo_contracts,
                      public.solo_evaluations,
                      public.solo_appeals
  to authenticated;

revoke all on table app.solo_contract_policy_versions,
                    app.solo_contract_runtime,
                    app.solo_beta_eligibility,
                    app.solo_rpc_requests
  from public, anon, authenticated, service_role;

revoke all on function app.assert_solo_write_path(),
                       app.validate_solo_contract_insert(),
                       app.enforce_solo_contract_lifecycle(),
                       app.validate_solo_evaluation_insert(),
                       app.validate_solo_appeal_insert()
  from public, anon, authenticated, service_role;
