-- Step 2A -- versioned Solo mutation boundary and account-deletion bridge.

create function app.solo_payload_digest_v1(payload jsonb)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(payload::text, 'UTF8'),
    'sha256'
  );
$$;

-- ---------------------------------------------------------------------------
-- Service-owned rollout gates
-- ---------------------------------------------------------------------------

create function public.set_solo_contract_runtime_v1(
  request_id             uuid,
  creation_enabled       boolean,
  active_policy_version  text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request_id       uuid := $1;
  v_enabled          boolean := $2;
  v_policy_version   text := $3;
  v_payload_hash     bytea;
  v_existing         app.solo_rpc_requests;
begin
  if v_request_id is null
     or v_enabled is null
     or v_policy_version is null
  then
    raise exception 'request UUID, switch value, and policy version are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'active_policy_version', v_policy_version,
      'contract_creation_enabled', v_enabled,
      'kind', 'set_solo_contract_runtime_v1'
    )
  );

  perform 1
  from app.solo_contract_runtime runtime
  where runtime.singleton
  for update;

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'set_solo_contract_runtime_v1'
    and request.request_scope = '00000000-0000-0000-0000-000000000000'::uuid
    and request.request_id = v_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with different runtime settings'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'creation_enabled')::boolean;
  end if;

  if not exists (
    select 1
    from app.solo_contract_policy_versions policy
    where policy.version = v_policy_version
  ) then
    raise exception 'unknown Solo policy version %', v_policy_version
      using errcode = 'foreign_key_violation';
  end if;

  perform pg_catalog.set_config('app.solo_write_path', 'runtime_v1', true);

  update app.solo_contract_runtime runtime
  set contract_creation_enabled = v_enabled,
      active_policy_version = v_policy_version,
      updated_at = clock_timestamp()
  where runtime.singleton;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'set_solo_contract_runtime_v1',
    '00000000-0000-0000-0000-000000000000'::uuid,
    v_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object(
      'active_policy_version', v_policy_version,
      'creation_enabled', v_enabled
    )
  );

  return v_enabled;
end;
$$;

comment on function public.set_solo_contract_runtime_v1(uuid, boolean, text) is
  'Service-only exact-request Solo creation switch. The migration seeds it disabled.';

create function public.set_solo_beta_eligibility_v1(
  request_id  uuid,
  owner_id    uuid,
  eligible    boolean
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request_id    uuid := $1;
  v_owner_id      uuid := $2;
  v_eligible      boolean := $3;
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_now           timestamptz;
begin
  if v_request_id is null or v_owner_id is null or v_eligible is null then
    raise exception 'request UUID, owner, and eligibility value are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'eligible', v_eligible,
      'kind', 'set_solo_beta_eligibility_v1',
      'owner_id', v_owner_id
    )
  );

  perform 1
  from public.profiles profile
  where profile.id = v_owner_id
  for update;

  if not found then
    raise exception 'owner is not active'
      using errcode = 'insufficient_privilege';
  end if;

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'set_solo_beta_eligibility_v1'
    and request.request_scope = v_owner_id
    and request.request_id = v_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with different beta eligibility'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'eligible')::boolean;
  end if;

  if not app.is_active_actor(v_owner_id) then
    raise exception 'owner is not active'
      using errcode = 'insufficient_privilege';
  end if;

  v_now := clock_timestamp();
  perform pg_catalog.set_config('app.solo_write_path', 'eligibility_v1', true);

  insert into app.solo_beta_eligibility (
    owner_id,
    eligible,
    created_at,
    updated_at
  )
  values (v_owner_id, v_eligible, v_now, v_now)
  on conflict on constraint solo_beta_eligibility_pkey do update
    set eligible = excluded.eligible,
        updated_at = excluded.updated_at;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'set_solo_beta_eligibility_v1',
    v_owner_id,
    v_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('eligible', v_eligible)
  );

  return v_eligible;
end;
$$;

comment on function public.set_solo_beta_eligibility_v1(uuid, uuid, boolean) is
  'Service-only exact-request database beta eligibility. JWT metadata is ignored.';

-- ---------------------------------------------------------------------------
-- Owner creation and cancellation
-- ---------------------------------------------------------------------------

create function public.create_solo_contract_v1(
  request_id                 uuid,
  expected_policy_version   text,
  cadence                    public.contest_cadence,
  target_steps               integer,
  commitment_amount_minor    integer,
  timezone                   text,
  start_date                 date,
  duration_days              smallint
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request_id         uuid := $1;
  v_policy_version     text := $2;
  v_cadence            public.contest_cadence := $3;
  v_target_steps       integer := $4;
  v_commitment_minor   integer := $5;
  v_timezone           text := $6;
  v_start_date         date := $7;
  v_duration_days      smallint := $8;
  v_owner_id           uuid;
  v_payload_hash       bytea;
  v_existing           app.solo_rpc_requests;
  v_runtime            app.solo_contract_runtime;
  v_policy             app.solo_contract_policy_versions;
  v_now                timestamptz;
  v_starts_at          timestamptz;
  v_ends_at            timestamptz;
  v_contract_id        uuid;
begin
  v_owner_id := app.require_active_caller();

  if v_request_id is null
     or v_policy_version is null
     or v_cadence is null
     or v_target_steps is null
     or v_commitment_minor is null
     or v_timezone is null
     or v_start_date is null
     or v_duration_days is null
  then
    raise exception 'all Solo creation terms are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_target_steps not between 1 and 1000000 then
    raise exception 'target steps must be a whole number from 1 through 1000000'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_cadence not in ('daily', 'cumulative') then
    raise exception 'Solo cadence must be daily or cumulative'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_commitment_minor not between 1000 and 5000 then
    raise exception 'commitment must be between $10 and $50'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_duration_days not between 1 and 7 then
    raise exception 'Solo duration must be from 1 through 7 local days'
      using errcode = 'invalid_parameter_value';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names zone
    where zone.name = v_timezone
  ) then
    raise exception 'a valid IANA timezone is required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'cadence', v_cadence::text,
      'commitment_amount_minor', v_commitment_minor,
      'currency', 'USD',
      'duration_days', v_duration_days,
      'expected_policy_version', v_policy_version,
      'kind', 'create_solo_contract_v1',
      'metric', 'steps',
      'settlement_mode', 'test_only',
      'start_date', v_start_date,
      'target_steps', v_target_steps,
      'timezone', v_timezone
    )
  );

  -- Exact committed retries recover before mutable rollout gates are rechecked.
  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'create_solo_contract_v1'
    and request.request_scope = v_owner_id
    and request.request_id = v_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with different Solo terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'contract_id')::uuid;
  end if;

  select runtime.* into strict v_runtime
  from app.solo_contract_runtime runtime
  where runtime.singleton
  for update;

  if not v_runtime.contract_creation_enabled then
    raise exception 'Solo contract creation is disabled'
      using errcode = 'insufficient_privilege';
  end if;
  if v_runtime.active_policy_version <> v_policy_version then
    raise exception 'review the active Solo policy before creating a contract'
      using errcode = 'restrict_violation';
  end if;
  if not exists (
    select 1
    from app.solo_beta_eligibility beta
    where beta.owner_id = v_owner_id
      and beta.eligible
  ) then
    raise exception 'owner is not eligible for the Solo beta'
      using errcode = 'insufficient_privilege';
  end if;

  select policy.* into strict v_policy
  from app.solo_contract_policy_versions policy
  where policy.version = v_policy_version;

  if v_commitment_minor not between
       v_policy.minimum_commitment_minor and v_policy.maximum_commitment_minor
     or v_duration_days not between
       v_policy.minimum_duration_days and v_policy.maximum_duration_days
  then
    raise exception 'Solo terms do not satisfy active policy %', v_policy_version
      using errcode = 'check_violation';
  end if;

  v_now := clock_timestamp();
  v_starts_at := v_start_date::timestamp at time zone v_timezone;
  v_ends_at :=
    (v_start_date + v_duration_days)::timestamp at time zone v_timezone;

  if v_starts_at <= v_now then
    raise exception 'Solo contract window must begin in the future'
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from public.solo_contracts contract
    where contract.owner_id = v_owner_id
      and contract.closed_at is null
  ) then
    raise exception 'owner already has an unsettled Solo contract'
      using errcode = 'unique_violation';
  end if;

  v_contract_id := gen_random_uuid();
  perform pg_catalog.set_config('app.solo_write_path', 'create_v1', true);

  insert into public.solo_contracts (
    id,
    owner_id,
    policy_version,
    policy_digest,
    metric,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    settlement_mode,
    timezone,
    start_date,
    duration_days,
    starts_at,
    ends_at,
    evidence_cutoff,
    locked_at,
    status,
    state_changed_at,
    created_at
  )
  values (
    v_contract_id,
    v_owner_id,
    v_policy.version,
    v_policy.policy_digest,
    'steps',
    v_cadence,
    v_target_steps,
    v_commitment_minor,
    'USD',
    'test_only',
    v_timezone,
    v_start_date,
    v_duration_days,
    v_starts_at,
    v_ends_at,
    v_ends_at + v_policy.evidence_grace,
    v_now,
    'scheduled',
    v_now,
    v_now
  );

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'create_solo_contract_v1',
    v_owner_id,
    v_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('contract_id', v_contract_id)
  );

  return v_contract_id;
end;
$$;

comment on function public.create_solo_contract_v1(
  uuid, text, public.contest_cadence, integer, integer, text, date, smallint
) is
  'Owner-only exact-request creation. Requires the DB beta allowlist, enabled runtime switch, and exact active policy version.';

create function app.cancel_solo_contract_at_v1(
  p_contract_id  uuid,
  p_request_id   uuid,
  p_test_now     timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id      uuid;
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_contract      public.solo_contracts;
  v_now           timestamptz;
begin
  v_owner_id := app.require_active_caller();

  if p_contract_id is null or p_request_id is null then
    raise exception 'contract and request UUID are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'kind', 'cancel_solo_contract_v1'
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'cancel_solo_contract_v1'
    and request.request_scope = v_owner_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used for a different cancellation'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'contract_id')::uuid;
  end if;

  select contract.* into v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id
  for update;

  v_now := coalesce(p_test_now, clock_timestamp());

  if v_contract.id is null or v_contract.owner_id <> v_owner_id then
    raise exception 'Solo contract not found'
      using errcode = 'insufficient_privilege';
  end if;
  if v_contract.status <> 'scheduled' or v_now >= v_contract.starts_at then
    raise exception 'a Solo contract can be cancelled only before it begins'
      using errcode = 'restrict_violation';
  end if;

  perform pg_catalog.set_config('app.solo_write_path', 'cancel_v1', true);

  update public.solo_contracts contract
  set status = 'cancelled',
      state_changed_at = v_now,
      cancellation_reason = 'owner_cancelled',
      cancelled_at = v_now,
      settlement_disposition = 'cancelled',
      closed_at = v_now
  where contract.id = p_contract_id;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'cancel_solo_contract_v1',
    v_owner_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('contract_id', p_contract_id)
  );

  return p_contract_id;
end;
$$;

create function public.cancel_solo_contract_v1(
  contract_id  uuid,
  request_id   uuid
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.cancel_solo_contract_at_v1($1, $2, null);
$$;

comment on function public.cancel_solo_contract_v1(uuid, uuid) is
  'Owner-only exact-request pre-start cancellation. A committed retry survives the later start boundary.';

-- ---------------------------------------------------------------------------
-- Service lifecycle, preliminary evaluation, appeal, and logical settlement
-- ---------------------------------------------------------------------------

create function app.advance_solo_contract_at_v1(
  p_contract_id  uuid,
  p_request_id   uuid,
  p_target       public.solo_contract_status,
  p_test_now     timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id      uuid;
  v_contract      public.solo_contracts;
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_now           timestamptz;
begin
  if p_contract_id is null or p_request_id is null or p_target is null then
    raise exception 'contract, request UUID, and target state are required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_target not in ('active', 'awaiting_evaluation') then
    raise exception 'advance target must be active or awaiting_evaluation'
      using errcode = 'invalid_parameter_value';
  end if;

  select contract.owner_id into v_owner_id
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  if v_owner_id is null then
    raise exception 'Solo contract not found'
      using errcode = 'invalid_parameter_value';
  end if;

  perform 1
  from public.profiles profile
  where profile.id = v_owner_id
  for update;

  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id
  for update;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'kind', 'advance_solo_contract_v1',
      'target', p_target::text
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'advance_solo_contract_v1'
    and request.request_scope = p_contract_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used for a different lifecycle step'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'contract_id')::uuid;
  end if;

  v_now := coalesce(p_test_now, clock_timestamp());

  if v_contract.status = p_target then
    null;
  elsif p_target = 'active'
        and v_contract.status = 'scheduled'
        and v_now >= v_contract.starts_at
  then
    perform pg_catalog.set_config('app.solo_write_path', 'advance_v1', true);
    update public.solo_contracts contract
    set status = 'active',
        state_changed_at = v_now
    where contract.id = p_contract_id;
  elsif p_target = 'awaiting_evaluation'
        and v_contract.status = 'active'
        and v_now >= v_contract.evidence_cutoff
  then
    perform pg_catalog.set_config('app.solo_write_path', 'advance_v1', true);
    update public.solo_contracts contract
    set status = 'awaiting_evaluation',
        state_changed_at = v_now
    where contract.id = p_contract_id;
  else
    raise exception 'Solo contract cannot advance from % to % at this time',
      v_contract.status, p_target
      using errcode = 'restrict_violation';
  end if;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'advance_solo_contract_v1',
    p_contract_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('contract_id', p_contract_id)
  );

  return p_contract_id;
end;
$$;

create function public.advance_solo_contract_v1(
  contract_id  uuid,
  request_id   uuid,
  target       public.solo_contract_status
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.advance_solo_contract_at_v1($1, $2, $3, null);
$$;

create function app.record_solo_evaluation_at_v1(
  p_contract_id       uuid,
  p_request_id        uuid,
  p_outcome           public.solo_evaluation_outcome,
  p_reason_code       text,
  p_evaluator_version text,
  p_evidence_digest   bytea,
  p_test_now          timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id        uuid;
  v_contract        public.solo_contracts;
  v_policy          app.solo_contract_policy_versions;
  v_payload_hash    bytea;
  v_existing        app.solo_rpc_requests;
  v_now             timestamptz;
  v_evaluation_id   uuid;
  v_appeal_deadline timestamptz;
begin
  if p_contract_id is null
     or p_request_id is null
     or p_outcome is null
     or p_reason_code is null
     or p_evaluator_version is null
     or p_evidence_digest is null
  then
    raise exception 'all evaluation fields are required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_reason_code !~ '^[a-z][a-z0-9_]{1,79}$'
     or char_length(p_evaluator_version) not between 1 and 80
     or octet_length(p_evidence_digest) <> 32
  then
    raise exception 'invalid evaluation reason, version, or digest'
      using errcode = 'invalid_parameter_value';
  end if;

  select contract.owner_id into v_owner_id
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  if v_owner_id is null then
    raise exception 'Solo contract not found'
      using errcode = 'invalid_parameter_value';
  end if;

  perform 1
  from public.profiles profile
  where profile.id = v_owner_id
  for update;

  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id
  for update;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'evaluator_version', p_evaluator_version,
      'evidence_digest', pg_catalog.encode(p_evidence_digest, 'hex'),
      'kind', 'record_solo_evaluation_v1',
      'outcome', p_outcome::text,
      'reason_code', p_reason_code
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'record_solo_evaluation_v1'
    and request.request_scope = p_contract_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with a different evaluation'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'evaluation_id')::uuid;
  end if;

  v_now := coalesce(p_test_now, clock_timestamp());

  if v_contract.status <> 'awaiting_evaluation'
     or v_now < v_contract.evidence_cutoff
  then
    raise exception 'Solo contract is not ready for preliminary evaluation'
      using errcode = 'restrict_violation';
  end if;

  select policy.* into strict v_policy
  from app.solo_contract_policy_versions policy
  where policy.version = v_contract.policy_version;

  v_evaluation_id := gen_random_uuid();
  v_appeal_deadline := case
    when p_outcome = 'failed' then v_now + v_policy.appeal_window
    else null
  end;

  perform pg_catalog.set_config('app.solo_write_path', 'evaluate_v1', true);

  insert into public.solo_evaluations (
    id,
    contract_id,
    owner_id,
    policy_version,
    outcome,
    reason_code,
    evaluator_version,
    evidence_digest,
    request_id,
    request_digest,
    evaluated_at,
    appeal_deadline
  )
  values (
    v_evaluation_id,
    p_contract_id,
    v_contract.owner_id,
    v_contract.policy_version,
    p_outcome,
    p_reason_code,
    p_evaluator_version,
    p_evidence_digest,
    p_request_id,
    v_payload_hash,
    v_now,
    v_appeal_deadline
  );

  update public.solo_contracts contract
  set status = case
        when p_outcome = 'failed'
          then 'preliminary_failure'::public.solo_contract_status
        else 'ready_to_settle'::public.solo_contract_status
      end,
      state_changed_at = v_now
  where contract.id = p_contract_id;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'record_solo_evaluation_v1',
    p_contract_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('evaluation_id', v_evaluation_id)
  );

  return v_evaluation_id;
end;
$$;

create function public.record_solo_evaluation_v1(
  contract_id       uuid,
  request_id        uuid,
  outcome           public.solo_evaluation_outcome,
  reason_code       text,
  evaluator_version text,
  evidence_digest   bytea
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.record_solo_evaluation_at_v1(
    $1, $2, $3, $4, $5, $6, null
  );
$$;

create function app.file_solo_appeal_at_v1(
  p_contract_id               uuid,
  p_preliminary_evaluation_id uuid,
  p_request_id                uuid,
  p_statement                 text,
  p_test_now                  timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id      uuid;
  v_contract      public.solo_contracts;
  v_evaluation    public.solo_evaluations;
  v_statement     text := pg_catalog.btrim(p_statement);
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_now           timestamptz;
  v_appeal_id     uuid;
begin
  v_owner_id := app.require_active_caller();

  if p_contract_id is null
     or p_preliminary_evaluation_id is null
     or p_request_id is null
     or v_statement is null
     or char_length(v_statement) not between 1 and 2000
  then
    raise exception 'contract, failure, request UUID, and bounded statement are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'kind', 'file_solo_appeal_v1',
      'preliminary_evaluation_id', p_preliminary_evaluation_id,
      'statement', v_statement
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'file_solo_appeal_v1'
    and request.request_scope = v_owner_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with a different appeal'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'appeal_id')::uuid;
  end if;

  select contract.* into v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id
  for update;

  select evaluation.* into v_evaluation
  from public.solo_evaluations evaluation
  where evaluation.id = p_preliminary_evaluation_id
  for share;

  v_now := coalesce(p_test_now, clock_timestamp());

  if v_contract.id is null
     or v_contract.owner_id <> v_owner_id
     or v_contract.status <> 'preliminary_failure'
     or v_evaluation.id is null
     or v_evaluation.contract_id <> p_contract_id
     or v_evaluation.owner_id <> v_owner_id
     or v_evaluation.outcome <> 'failed'
     or v_now >= v_evaluation.appeal_deadline
  then
    raise exception 'preliminary failure is not appealable'
      using errcode = 'restrict_violation';
  end if;

  v_appeal_id := gen_random_uuid();
  perform pg_catalog.set_config('app.solo_write_path', 'appeal_v1', true);

  insert into public.solo_appeals (
    id,
    contract_id,
    owner_id,
    policy_version,
    preliminary_evaluation_id,
    event_kind,
    filing_id,
    statement,
    decision,
    decision_reason_code,
    reviewer_version,
    decision_digest,
    request_id,
    request_digest,
    event_at
  )
  values (
    v_appeal_id,
    p_contract_id,
    v_owner_id,
    v_contract.policy_version,
    p_preliminary_evaluation_id,
    'filed',
    null,
    v_statement,
    null,
    null,
    null,
    null,
    p_request_id,
    v_payload_hash,
    v_now
  );

  update public.solo_contracts contract
  set status = 'appeal_pending',
      state_changed_at = v_now
  where contract.id = p_contract_id;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'file_solo_appeal_v1',
    v_owner_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('appeal_id', v_appeal_id)
  );

  return v_appeal_id;
end;
$$;

create function public.file_solo_appeal_v1(
  contract_id               uuid,
  preliminary_evaluation_id uuid,
  request_id                uuid,
  statement                 text
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.file_solo_appeal_at_v1($1, $2, $3, $4, null);
$$;

create function app.decide_solo_appeal_at_v1(
  p_filing_id            uuid,
  p_request_id           uuid,
  p_decision             public.solo_appeal_decision,
  p_reason_code          text,
  p_reviewer_version     text,
  p_decision_digest      bytea,
  p_test_now             timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_filing        public.solo_appeals;
  v_contract      public.solo_contracts;
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_now           timestamptz;
  v_decision_id   uuid;
begin
  if p_filing_id is null
     or p_request_id is null
     or p_decision is null
     or p_reason_code is null
     or p_reviewer_version is null
     or p_decision_digest is null
  then
    raise exception 'all appeal decision fields are required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_reason_code !~ '^[a-z][a-z0-9_]{1,79}$'
     or char_length(p_reviewer_version) not between 1 and 80
     or octet_length(p_decision_digest) <> 32
  then
    raise exception 'invalid appeal decision reason, version, or digest'
      using errcode = 'invalid_parameter_value';
  end if;

  select appeal.* into v_filing
  from public.solo_appeals appeal
  where appeal.id = p_filing_id
    and appeal.event_kind = 'filed';

  if v_filing.id is null then
    raise exception 'Solo appeal filing not found'
      using errcode = 'invalid_parameter_value';
  end if;

  perform 1
  from public.profiles profile
  where profile.id = v_filing.owner_id
  for update;

  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = v_filing.contract_id
  for update;

  select appeal.* into strict v_filing
  from public.solo_appeals appeal
  where appeal.id = p_filing_id
    and appeal.event_kind = 'filed'
  for share;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'decision', p_decision::text,
      'decision_digest', pg_catalog.encode(p_decision_digest, 'hex'),
      'filing_id', p_filing_id,
      'kind', 'decide_solo_appeal_v1',
      'reason_code', p_reason_code,
      'reviewer_version', p_reviewer_version
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'decide_solo_appeal_v1'
    and request.request_scope = v_contract.id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with a different appeal decision'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'decision_id')::uuid;
  end if;

  if v_contract.status <> 'appeal_pending'
     or exists (
       select 1
       from public.solo_appeals decision
       where decision.filing_id = p_filing_id
         and decision.event_kind = 'decided'
     )
  then
    raise exception 'Solo appeal is no longer pending'
      using errcode = 'restrict_violation';
  end if;

  v_now := coalesce(p_test_now, clock_timestamp());
  v_decision_id := gen_random_uuid();
  perform pg_catalog.set_config('app.solo_write_path', 'decide_appeal_v1', true);

  insert into public.solo_appeals (
    id,
    contract_id,
    owner_id,
    policy_version,
    preliminary_evaluation_id,
    event_kind,
    filing_id,
    statement,
    decision,
    decision_reason_code,
    reviewer_version,
    decision_digest,
    request_id,
    request_digest,
    event_at
  )
  values (
    v_decision_id,
    v_filing.contract_id,
    v_filing.owner_id,
    v_filing.policy_version,
    v_filing.preliminary_evaluation_id,
    'decided',
    v_filing.id,
    null,
    p_decision,
    p_reason_code,
    p_reviewer_version,
    p_decision_digest,
    p_request_id,
    v_payload_hash,
    v_now
  );

  update public.solo_contracts contract
  set status = 'ready_to_settle',
      state_changed_at = v_now
  where contract.id = v_contract.id;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'decide_solo_appeal_v1',
    v_contract.id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('decision_id', v_decision_id)
  );

  return v_decision_id;
end;
$$;

create function public.decide_solo_appeal_v1(
  filing_id        uuid,
  request_id       uuid,
  decision         public.solo_appeal_decision,
  reason_code      text,
  reviewer_version text,
  decision_digest  bytea
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.decide_solo_appeal_at_v1(
    $1, $2, $3, $4, $5, $6, null
  );
$$;

create function app.settle_solo_contract_at_v1(
  p_contract_id  uuid,
  p_request_id   uuid,
  p_test_now     timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id      uuid;
  v_contract      public.solo_contracts;
  v_evaluation    public.solo_evaluations;
  v_decision      public.solo_appeals;
  v_payload_hash  bytea;
  v_existing      app.solo_rpc_requests;
  v_now           timestamptz;
  v_disposition   public.solo_settlement_disposition;
begin
  if p_contract_id is null or p_request_id is null then
    raise exception 'contract and request UUID are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select contract.owner_id into v_owner_id
  from public.solo_contracts contract
  where contract.id = p_contract_id;

  if v_owner_id is null then
    raise exception 'Solo contract not found'
      using errcode = 'invalid_parameter_value';
  end if;

  perform 1
  from public.profiles profile
  where profile.id = v_owner_id
  for update;

  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = p_contract_id
  for update;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'kind', 'settle_solo_contract_v1'
    )
  );

  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'settle_solo_contract_v1'
    and request.request_scope = p_contract_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used for a different settlement'
        using errcode = 'invalid_parameter_value';
    end if;
    return (v_existing.result ->> 'contract_id')::uuid;
  end if;

  select evaluation.* into strict v_evaluation
  from public.solo_evaluations evaluation
  where evaluation.contract_id = p_contract_id;

  v_now := coalesce(p_test_now, clock_timestamp());

  if v_contract.status = 'preliminary_failure' then
    if v_now < v_evaluation.appeal_deadline
       or exists (
         select 1
         from public.solo_appeals appeal
         where appeal.preliminary_evaluation_id = v_evaluation.id
           and appeal.event_kind = 'filed'
       )
    then
      raise exception 'preliminary failure still has an appeal path'
        using errcode = 'restrict_violation';
    end if;
    v_disposition := 'forfeited';
  elsif v_contract.status = 'ready_to_settle' then
    if v_evaluation.outcome = 'passed' then
      v_disposition := 'released';
    elsif v_evaluation.outcome = 'inconclusive' then
      v_disposition := 'waived';
    else
      select appeal.* into strict v_decision
      from public.solo_appeals appeal
      where appeal.preliminary_evaluation_id = v_evaluation.id
        and appeal.event_kind = 'decided';

      v_disposition := case v_decision.decision
        when 'upheld' then 'released'::public.solo_settlement_disposition
        when 'denied' then 'forfeited'::public.solo_settlement_disposition
        when 'waived' then 'waived'::public.solo_settlement_disposition
      end;
    end if;
  else
    raise exception 'Solo contract is not ready for logical settlement'
      using errcode = 'restrict_violation';
  end if;

  perform pg_catalog.set_config('app.solo_write_path', 'settle_v1', true);

  update public.solo_contracts contract
  set status = 'settled',
      state_changed_at = v_now,
      settlement_disposition = v_disposition,
      settled_at = v_now,
      closed_at = v_now
  where contract.id = p_contract_id;

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'settle_solo_contract_v1',
    p_contract_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object(
      'contract_id', p_contract_id,
      'disposition', v_disposition
    )
  );

  return p_contract_id;
end;
$$;

create function public.settle_solo_contract_v1(
  contract_id  uuid,
  request_id   uuid
)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select app.settle_solo_contract_at_v1($1, $2, null);
$$;

-- ---------------------------------------------------------------------------
-- Existing D81 account deletion, extended without rewriting its migration
-- ---------------------------------------------------------------------------

create function app.resolve_solo_contracts_on_account_deletion_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_now timestamptz;
begin
  if old.deleted_at is not null or new.deleted_at is null then
    return new;
  end if;

  if not exists (
    select 1
    from app.account_deletion_transactions deletion
    where deletion.transaction_id = pg_catalog.txid_current()
      and deletion.backend_pid = pg_catalog.pg_backend_pid()
      and deletion.actor_id = new.id
  ) then
    raise exception 'Solo deletion transition requires the account deletion RPC'
      using errcode = 'insufficient_privilege';
  end if;

  -- D81 freezes the serialized deletion boundary on the profile row before
  -- this trigger runs. Reuse it so a start instant cannot slip between two
  -- wall-clock reads inside the same account-deletion transaction.
  v_now := new.deleted_at;

  perform 1
  from public.solo_contracts contract
  where contract.owner_id = new.id
    and contract.closed_at is null
  order by contract.starts_at, contract.id
  for update;

  perform pg_catalog.set_config(
    'app.solo_write_path',
    'account_deletion_v1',
    true
  );

  update public.solo_contracts contract
  set status = 'cancelled',
      state_changed_at = v_now,
      cancellation_reason = 'account_deleted',
      cancelled_at = v_now,
      settlement_disposition = 'cancelled',
      closed_at = v_now
  where contract.owner_id = new.id
    and contract.status = 'scheduled'
    and v_now < contract.starts_at;

  update app.solo_beta_eligibility beta
  set eligible = false,
      updated_at = v_now
  where beta.owner_id = new.id
    and beta.eligible;

  return new;
end;
$$;

create trigger profiles_resolve_solo_contracts_on_deletion
  after update of deleted_at on public.profiles
  for each row execute function app.resolve_solo_contracts_on_account_deletion_v1();

comment on function app.resolve_solo_contracts_on_account_deletion_v1() is
  'D81 bridge: cancels only not-yet-started Solo contracts, revokes beta eligibility, and preserves post-start facts for service finality.';

-- ---------------------------------------------------------------------------
-- Explicit function privileges
-- ---------------------------------------------------------------------------

revoke all on function app.solo_payload_digest_v1(jsonb),
                       app.cancel_solo_contract_at_v1(uuid, uuid, timestamptz),
                       app.advance_solo_contract_at_v1(
                         uuid, uuid, public.solo_contract_status, timestamptz
                       ),
                       app.record_solo_evaluation_at_v1(
                         uuid,
                         uuid,
                         public.solo_evaluation_outcome,
                         text,
                         text,
                         bytea,
                         timestamptz
                       ),
                       app.file_solo_appeal_at_v1(
                         uuid, uuid, uuid, text, timestamptz
                       ),
                       app.decide_solo_appeal_at_v1(
                         uuid,
                         uuid,
                         public.solo_appeal_decision,
                         text,
                         text,
                         bytea,
                         timestamptz
                       ),
                       app.settle_solo_contract_at_v1(uuid, uuid, timestamptz),
                       app.resolve_solo_contracts_on_account_deletion_v1()
  from public, anon, authenticated, service_role;

revoke all on function public.set_solo_contract_runtime_v1(uuid, boolean, text),
                       public.set_solo_beta_eligibility_v1(uuid, uuid, boolean),
                       public.create_solo_contract_v1(
                         uuid,
                         text,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         date,
                         smallint
                       ),
                       public.cancel_solo_contract_v1(uuid, uuid),
                       public.advance_solo_contract_v1(
                         uuid, uuid, public.solo_contract_status
                       ),
                       public.record_solo_evaluation_v1(
                         uuid,
                         uuid,
                         public.solo_evaluation_outcome,
                         text,
                         text,
                         bytea
                       ),
                       public.file_solo_appeal_v1(uuid, uuid, uuid, text),
                       public.decide_solo_appeal_v1(
                         uuid,
                         uuid,
                         public.solo_appeal_decision,
                         text,
                         text,
                         bytea
                       ),
                       public.settle_solo_contract_v1(uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.create_solo_contract_v1(
                           uuid,
                           text,
                           public.contest_cadence,
                           integer,
                           integer,
                           text,
                           date,
                           smallint
                         ),
                         public.cancel_solo_contract_v1(uuid, uuid),
                         public.file_solo_appeal_v1(uuid, uuid, uuid, text)
  to authenticated;

grant execute on function public.set_solo_contract_runtime_v1(
                           uuid, boolean, text
                         ),
                         public.set_solo_beta_eligibility_v1(
                           uuid, uuid, boolean
                         ),
                         public.advance_solo_contract_v1(
                           uuid, uuid, public.solo_contract_status
                         ),
                         public.record_solo_evaluation_v1(
                           uuid,
                           uuid,
                           public.solo_evaluation_outcome,
                           text,
                           text,
                           bytea
                         ),
                         public.decide_solo_appeal_v1(
                           uuid,
                           uuid,
                           public.solo_appeal_decision,
                           text,
                           text,
                           bytea
                         ),
                         public.settle_solo_contract_v1(uuid, uuid)
  to service_role;
