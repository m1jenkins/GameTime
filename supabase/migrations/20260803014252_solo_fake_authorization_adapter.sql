-- Step 2B -- local-only processor-neutral fake authorization adapter.
--
-- This forward slice leaves create_solo_contract_v1 contract-only. The new v2
-- owner boundary creates a contract, one immutable private authorization, and
-- its initial event in one transaction. The adapter accepts no credential,
-- payment instrument, provider identifier, mandate, or arbitrary payload and
-- performs no external call or money movement.

create type app.solo_fake_authorization_scenario as enum (
  'authorize',
  'refuse',
  'retryable',
  'injected_failure'
);

create type app.solo_fake_authorization_outcome as enum (
  'authorized',
  'refused',
  'retryable'
);

create type app.solo_authorization_event_kind as enum (
  'authorized',
  'cancelled',
  'released',
  'forfeited',
  'waived'
);

-- The full key makes every copied authorization fact relationally dependent
-- on one frozen contract rather than relying on an application comparison.
alter table public.solo_contracts
  add constraint solo_contracts_authorization_binding_key
  unique (
    id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode
  );

create table app.solo_authorizations (
  id                         uuid primary key,
  contract_id                uuid not null unique,
  owner_id                   uuid not null,
  policy_version             text not null,
  policy_digest              bytea not null,
  commitment_amount_minor    integer not null,
  currency                   text not null,
  settlement_mode            public.solo_settlement_mode not null,
  adapter_kind               text not null,
  adapter_version            text not null,
  authorization_digest       bytea not null,
  create_request_id          uuid not null,
  create_request_digest      bytea not null,
  created_at                 timestamptz not null,

  constraint solo_authorization_contract_fkey
    foreign key (
      contract_id,
      owner_id,
      policy_version,
      policy_digest,
      commitment_amount_minor,
      currency,
      settlement_mode
    )
    references public.solo_contracts (
      id,
      owner_id,
      policy_version,
      policy_digest,
      commitment_amount_minor,
      currency,
      settlement_mode
    )
    on delete restrict,
  constraint solo_authorization_adapter_fixed check (
    adapter_kind = 'processor_neutral_fake'
    and adapter_version = 'local-fake-v1'
  ),
  constraint solo_authorization_policy_shape check (
    char_length(policy_version) between 1 and 80
    and octet_length(policy_digest) = 32
  ),
  constraint solo_authorization_amount_bounded check (
    commitment_amount_minor between 1000 and 5000
  ),
  constraint solo_authorization_currency_usd check (currency = 'USD'),
  constraint solo_authorization_test_only check (
    settlement_mode = 'test_only'
  ),
  constraint solo_authorization_digests_sha256 check (
    octet_length(authorization_digest) = 32
    and octet_length(create_request_digest) = 32
  ),
  constraint solo_authorization_created_at_finite check (
    pg_catalog.isfinite(created_at)
  ),
  unique (
    id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode
  )
);

comment on table app.solo_authorizations is
  'Private immutable processor-neutral fake authorizations. One row binds exactly one v2 Solo contract and moves no money.';
comment on column app.solo_authorizations.authorization_digest is
  'SHA-256 digest of the typed immutable authorization facts; never a provider payload or instrument fingerprint.';

create table app.solo_authorization_events (
  id                         uuid primary key,
  authorization_id           uuid not null,
  contract_id                uuid not null,
  owner_id                   uuid not null,
  policy_version             text not null,
  policy_digest              bytea not null,
  commitment_amount_minor    integer not null,
  currency                   text not null,
  settlement_mode            public.solo_settlement_mode not null,
  sequence_number            smallint not null,
  event_kind                 app.solo_authorization_event_kind not null,
  source_operation           text not null,
  event_digest               bytea not null,
  event_at                   timestamptz not null,

  constraint solo_authorization_event_parent_fkey
    foreign key (
      authorization_id,
      contract_id,
      owner_id,
      policy_version,
      policy_digest,
      commitment_amount_minor,
      currency,
      settlement_mode
    )
    references app.solo_authorizations (
      id,
      contract_id,
      owner_id,
      policy_version,
      policy_digest,
      commitment_amount_minor,
      currency,
      settlement_mode
    )
    on delete restrict,
  constraint solo_authorization_event_sequence check (
    sequence_number in (1, 2)
  ),
  constraint solo_authorization_event_policy_shape check (
    char_length(policy_version) between 1 and 80
    and octet_length(policy_digest) = 32
  ),
  constraint solo_authorization_event_amount_bounded check (
    commitment_amount_minor between 1000 and 5000
  ),
  constraint solo_authorization_event_currency_usd check (currency = 'USD'),
  constraint solo_authorization_event_test_only check (
    settlement_mode = 'test_only'
  ),
  constraint solo_authorization_event_digest_sha256 check (
    octet_length(event_digest) = 32
  ),
  constraint solo_authorization_event_at_finite check (
    pg_catalog.isfinite(event_at)
  ),
  constraint solo_authorization_event_shape check (
    (
      sequence_number = 1
      and event_kind = 'authorized'
      and source_operation = 'create_solo_contract_with_fake_authorization_v2'
    )
    or (
      sequence_number = 2
      and event_kind = 'cancelled'
      and source_operation in (
        'cancel_solo_contract_v1',
        'delete_account'
      )
    )
    or (
      sequence_number = 2
      and event_kind in ('released', 'forfeited', 'waived')
      and source_operation = 'settle_solo_contract_v1'
    )
  ),
  unique (authorization_id, sequence_number)
);

comment on table app.solo_authorization_events is
  'Append-only fake authorization lifecycle: authorized, then exactly one logical cancellation or settlement outcome.';
comment on column app.solo_authorization_events.event_kind is
  'Logical fake outcome only. Released, forfeited, and waived do not mean funds moved.';

-- ---------------------------------------------------------------------------
-- Canonical typed digests and the deterministic fake adapter
-- ---------------------------------------------------------------------------

create function app.solo_authorization_fact_digest_v1(
  p_contract_id               uuid,
  p_owner_id                  uuid,
  p_policy_version            text,
  p_policy_digest             bytea,
  p_commitment_amount_minor   integer,
  p_currency                  text,
  p_settlement_mode           public.solo_settlement_mode,
  p_adapter_kind              text,
  p_adapter_version           text
)
returns bytea
language sql
immutable
strict
set search_path = ''
as $$
  select app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'adapter_kind', p_adapter_kind,
      'adapter_version', p_adapter_version,
      'commitment_amount_minor', p_commitment_amount_minor,
      'contract_id', p_contract_id,
      'currency', p_currency,
      'outcome', 'authorized',
      'owner_id', p_owner_id,
      'policy_digest', pg_catalog.encode(p_policy_digest, 'hex'),
      'policy_version', p_policy_version,
      'settlement_mode', p_settlement_mode::text
    )
  );
$$;

create function app.solo_authorization_event_digest_v1(
  p_authorization_id          uuid,
  p_contract_id               uuid,
  p_owner_id                  uuid,
  p_policy_version            text,
  p_policy_digest             bytea,
  p_commitment_amount_minor   integer,
  p_currency                  text,
  p_settlement_mode           public.solo_settlement_mode,
  p_sequence_number           smallint,
  p_event_kind                app.solo_authorization_event_kind,
  p_source_operation          text,
  p_event_at                  timestamptz
)
returns bytea
language sql
immutable
strict
set search_path = ''
as $$
  select app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'authorization_id', p_authorization_id,
      'commitment_amount_minor', p_commitment_amount_minor,
      'contract_id', p_contract_id,
      'currency', p_currency,
      'event_at', p_event_at,
      'event_kind', p_event_kind::text,
      'owner_id', p_owner_id,
      'policy_digest', pg_catalog.encode(p_policy_digest, 'hex'),
      'policy_version', p_policy_version,
      'sequence_number', p_sequence_number,
      'settlement_mode', p_settlement_mode::text,
      'source_operation', p_source_operation
    )
  );
$$;

create function app.run_solo_fake_authorization_v1(
  p_contract_id               uuid,
  p_owner_id                  uuid,
  p_policy_version            text,
  p_policy_digest             bytea,
  p_commitment_amount_minor   integer,
  p_currency                  text,
  p_settlement_mode           public.solo_settlement_mode,
  p_scenario                  app.solo_fake_authorization_scenario
)
returns app.solo_fake_authorization_outcome
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if octet_length(p_policy_digest) <> 32
     or p_commitment_amount_minor not between 1000 and 5000
     or p_currency <> 'USD'
     or p_settlement_mode <> 'test_only'
     or char_length(p_policy_version) not between 1 and 80
  then
    raise exception 'invalid typed facts for local fake authorization'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Read every typed identity input so no caller can accidentally turn this
  -- adapter into a scenario-only stub while still keeping the result pure.
  perform p_contract_id, p_owner_id;

  case p_scenario
    when 'authorize' then
      return 'authorized'::app.solo_fake_authorization_outcome;
    when 'refuse' then
      return 'refused'::app.solo_fake_authorization_outcome;
    when 'retryable' then
      return 'retryable'::app.solo_fake_authorization_outcome;
    when 'injected_failure' then
      raise exception 'deterministic local fake authorization failure'
        using errcode = 'P2B02';
  end case;

  raise exception 'unknown local fake authorization scenario'
    using errcode = 'invalid_parameter_value';
end;
$$;

comment on function app.run_solo_fake_authorization_v1(
  uuid,
  uuid,
  text,
  bytea,
  integer,
  text,
  public.solo_settlement_mode,
  app.solo_fake_authorization_scenario
) is
  'Pure local fake adapter over typed contract facts. It stores nothing, logs nothing, and performs no external call.';

-- ---------------------------------------------------------------------------
-- Immutable and append-only write-path enforcement
-- ---------------------------------------------------------------------------

create function app.assert_solo_authorization_write_path()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_path text := pg_catalog.current_setting('app.solo_write_path', true);
begin
  if v_path is null or not (v_path = any (tg_argv)) then
    raise exception 'write to %.% must use a versioned Solo mutation',
      tg_table_schema, tg_table_name
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create function app.validate_solo_authorization_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contract public.solo_contracts;
  v_expected_digest bytea;
begin
  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = new.contract_id
  for update;

  if v_contract.status <> 'scheduled'
     or v_contract.closed_at is not null
     or v_contract.owner_id <> new.owner_id
     or v_contract.policy_version <> new.policy_version
     or v_contract.policy_digest <> new.policy_digest
     or v_contract.commitment_amount_minor <> new.commitment_amount_minor
     or v_contract.currency <> new.currency
     or v_contract.settlement_mode <> new.settlement_mode
  then
    raise exception 'fake authorization does not match one scheduled Solo contract'
      using errcode = 'restrict_violation';
  end if;

  v_expected_digest := app.solo_authorization_fact_digest_v1(
    new.contract_id,
    new.owner_id,
    new.policy_version,
    new.policy_digest,
    new.commitment_amount_minor,
    new.currency,
    new.settlement_mode,
    new.adapter_kind,
    new.adapter_version
  );

  if new.authorization_digest is distinct from v_expected_digest then
    raise exception 'fake authorization digest does not match its typed facts'
      using errcode = 'check_violation';
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'Solo contract not found for fake authorization'
      using errcode = 'foreign_key_violation';
end;
$$;

create function app.validate_solo_authorization_event_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_authorization app.solo_authorizations;
  v_contract public.solo_contracts;
  v_expected_digest bytea;
begin
  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = new.contract_id
  for update;

  select authorization_row.* into strict v_authorization
  from app.solo_authorizations authorization_row
  where authorization_row.id = new.authorization_id
  for update;

  if v_authorization.contract_id <> new.contract_id
     or v_authorization.owner_id <> new.owner_id
     or v_authorization.policy_version <> new.policy_version
     or v_authorization.policy_digest <> new.policy_digest
     or v_authorization.commitment_amount_minor
          <> new.commitment_amount_minor
     or v_authorization.currency <> new.currency
     or v_authorization.settlement_mode <> new.settlement_mode
  then
    raise exception 'fake authorization event does not match its authorization'
      using errcode = 'restrict_violation';
  end if;

  v_expected_digest := app.solo_authorization_event_digest_v1(
    new.authorization_id,
    new.contract_id,
    new.owner_id,
    new.policy_version,
    new.policy_digest,
    new.commitment_amount_minor,
    new.currency,
    new.settlement_mode,
    new.sequence_number,
    new.event_kind,
    new.source_operation,
    new.event_at
  );

  if new.event_digest is distinct from v_expected_digest then
    raise exception 'fake authorization event digest does not match its typed facts'
      using errcode = 'check_violation';
  end if;

  if new.sequence_number = 1 then
    if new.event_kind <> 'authorized'
       or new.event_at is distinct from v_authorization.created_at
       or v_contract.status <> 'scheduled'
       or v_contract.closed_at is not null
       or exists (
         select 1
         from app.solo_authorization_events event
         where event.authorization_id = new.authorization_id
       )
    then
      raise exception 'the first fake authorization event must authorize one scheduled contract'
        using errcode = 'restrict_violation';
    end if;
  else
    if not exists (
      select 1
      from app.solo_authorization_events event
      where event.authorization_id = new.authorization_id
        and event.sequence_number = 1
        and event.event_kind = 'authorized'
    )
       or exists (
         select 1
         from app.solo_authorization_events event
         where event.authorization_id = new.authorization_id
           and event.sequence_number = 2
       )
    then
      raise exception 'fake authorization can resolve exactly once after authorization'
        using errcode = 'restrict_violation';
    end if;

    if v_contract.status = 'cancelled' then
      if new.event_kind <> 'cancelled'
         or new.event_at is distinct from v_contract.cancelled_at
         or new.source_operation not in (
           'cancel_solo_contract_v1',
           'delete_account'
         )
      then
        raise exception 'cancelled contract requires one matching fake cancellation event'
          using errcode = 'restrict_violation';
      end if;
    elsif v_contract.status = 'settled' then
      if new.event_kind::text
           is distinct from v_contract.settlement_disposition::text
         or new.event_at is distinct from v_contract.settled_at
         or new.source_operation <> 'settle_solo_contract_v1'
      then
        raise exception 'settled contract requires one matching fake resolution event'
          using errcode = 'restrict_violation';
      end if;
    else
      raise exception 'fake authorization cannot resolve before contract finality'
        using errcode = 'restrict_violation';
    end if;
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'fake authorization or Solo contract not found for event'
      using errcode = 'foreign_key_violation';
end;
$$;

create function app.append_solo_authorization_resolution_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_authorization app.solo_authorizations;
  v_event_kind app.solo_authorization_event_kind;
  v_source_operation text;
  v_event_at timestamptz;
  v_write_path text := pg_catalog.current_setting('app.solo_write_path', true);
  v_event_id uuid;
begin
  select authorization_row.* into v_authorization
  from app.solo_authorizations authorization_row
  where authorization_row.contract_id = new.id
  for update;

  -- A contract-only v1 row deliberately remains authorization-free.
  if v_authorization.id is null then
    return new;
  end if;

  if exists (
    select 1
    from app.solo_authorization_events event
    where event.authorization_id = v_authorization.id
      and event.sequence_number = 2
  ) then
    raise exception 'fake authorization is already resolved'
      using errcode = 'restrict_violation';
  end if;

  if new.status = 'cancelled' then
    if v_write_path = 'cancel_v1' then
      v_source_operation := 'cancel_solo_contract_v1';
    elsif v_write_path = 'account_deletion_v1' then
      v_source_operation := 'delete_account';
    else
      raise exception 'fake cancellation must share an approved Solo transaction'
        using errcode = 'insufficient_privilege';
    end if;
    v_event_kind := 'cancelled';
    v_event_at := new.cancelled_at;
  elsif new.status = 'settled' then
    if v_write_path <> 'settle_v1' then
      raise exception 'fake resolution must share the Solo settlement transaction'
        using errcode = 'insufficient_privilege';
    end if;
    v_event_kind := new.settlement_disposition::text
      ::app.solo_authorization_event_kind;
    v_source_operation := 'settle_solo_contract_v1';
    v_event_at := new.settled_at;
  else
    raise exception 'fake authorization resolution requires contract finality'
      using errcode = 'restrict_violation';
  end if;

  v_event_id := gen_random_uuid();
  perform pg_catalog.set_config('app.solo_write_path', v_write_path, true);

  insert into app.solo_authorization_events (
    id,
    authorization_id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    sequence_number,
    event_kind,
    source_operation,
    event_digest,
    event_at
  )
  values (
    v_event_id,
    v_authorization.id,
    v_authorization.contract_id,
    v_authorization.owner_id,
    v_authorization.policy_version,
    v_authorization.policy_digest,
    v_authorization.commitment_amount_minor,
    v_authorization.currency,
    v_authorization.settlement_mode,
    2,
    v_event_kind,
    v_source_operation,
    app.solo_authorization_event_digest_v1(
      v_authorization.id,
      v_authorization.contract_id,
      v_authorization.owner_id,
      v_authorization.policy_version,
      v_authorization.policy_digest,
      v_authorization.commitment_amount_minor,
      v_authorization.currency,
      v_authorization.settlement_mode,
      2::smallint,
      v_event_kind,
      v_source_operation,
      v_event_at
    ),
    v_event_at
  );

  return new;
end;
$$;

create trigger solo_authorizations_require_versioned_insert
  before insert on app.solo_authorizations
  for each row execute function app.assert_solo_authorization_write_path(
    'create_with_fake_v2'
  );

create trigger solo_authorizations_validate_insert
  before insert on app.solo_authorizations
  for each row execute function app.validate_solo_authorization_insert_v1();

create trigger solo_authorizations_forbid_mutation
  before update or delete or truncate on app.solo_authorizations
  for each statement execute function app.forbid_mutation();

create trigger solo_authorization_events_require_versioned_insert
  before insert on app.solo_authorization_events
  for each row execute function app.assert_solo_authorization_write_path(
    'create_with_fake_v2',
    'cancel_v1',
    'settle_v1',
    'account_deletion_v1'
  );

create trigger solo_authorization_events_validate_insert
  before insert on app.solo_authorization_events
  for each row execute function app.validate_solo_authorization_event_insert_v1();

create trigger solo_authorization_events_forbid_mutation
  before update or delete or truncate on app.solo_authorization_events
  for each statement execute function app.forbid_mutation();

create trigger solo_contracts_append_fake_authorization_resolution
  after update of status on public.solo_contracts
  for each row
  when (
    old.status is distinct from new.status
    and new.status in ('cancelled', 'settled')
  )
  execute function app.append_solo_authorization_resolution_v1();

-- ---------------------------------------------------------------------------
-- Atomic v2 owner boundary
-- ---------------------------------------------------------------------------

create function app.create_solo_contract_with_fake_authorization_at_v2(
  p_request_id                 uuid,
  p_expected_policy_version   text,
  p_cadence                    public.contest_cadence,
  p_target_steps               integer,
  p_commitment_amount_minor    integer,
  p_timezone                   text,
  p_start_date                 date,
  p_duration_days              smallint,
  p_scenario                   app.solo_fake_authorization_scenario
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id              uuid;
  v_payload_hash          bytea;
  v_existing              app.solo_rpc_requests;
  v_contract              public.solo_contracts;
  v_contract_id           uuid;
  v_authorization_id      uuid;
  v_authorization_digest  bytea;
  v_outcome               app.solo_fake_authorization_outcome;
  v_result                jsonb;
  v_created_at            timestamptz;
begin
  v_owner_id := app.require_active_caller();

  if p_request_id is null
     or p_expected_policy_version is null
     or p_cadence is null
     or p_target_steps is null
     or p_commitment_amount_minor is null
     or p_timezone is null
     or p_start_date is null
     or p_duration_days is null
     or p_scenario is null
  then
    raise exception 'all Solo v2 creation fields are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_payload_hash := app.solo_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'adapter_kind', 'processor_neutral_fake',
      'adapter_version', 'local-fake-v1',
      'cadence', p_cadence::text,
      'commitment_amount_minor', p_commitment_amount_minor,
      'currency', 'USD',
      'duration_days', p_duration_days,
      'expected_policy_version', p_expected_policy_version,
      'fake_scenario', p_scenario::text,
      'kind', 'create_solo_contract_with_fake_authorization_v2',
      'metric', 'steps',
      'settlement_mode', 'test_only',
      'start_date', p_start_date,
      'target_steps', p_target_steps,
      'timezone', p_timezone
    )
  );

  -- Exact committed retries recover before rollout gates are rechecked.
  select request.* into v_existing
  from app.solo_rpc_requests request
  where request.operation = 'create_solo_contract_with_fake_authorization_v2'
    and request.request_scope = v_owner_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with different Solo v2 terms'
        using errcode = 'invalid_parameter_value';
    end if;
    return v_existing.result;
  end if;

  -- A request first committed through v1 is an explicitly contract-only
  -- request. It cannot be upgraded into a v2 linked authorization later.
  if exists (
    select 1
    from app.solo_rpc_requests request
    where request.operation = 'create_solo_contract_v1'
      and request.request_scope = v_owner_id
      and request.request_id = p_request_id
  ) then
    raise exception 'request UUID already belongs to contract-only Solo creation'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_scenario in ('refuse', 'retryable') then
    -- Reuse the complete reviewed v1 validation and rollout-gate contract in a
    -- savepoint, then intentionally roll its candidate contract back. The
    -- refusal/retry result is the only committed mutation.
    begin
      v_contract_id := public.create_solo_contract_v1(
        p_request_id,
        p_expected_policy_version,
        p_cadence,
        p_target_steps,
        p_commitment_amount_minor,
        p_timezone,
        p_start_date,
        p_duration_days
      );

      select contract.* into strict v_contract
      from public.solo_contracts contract
      where contract.id = v_contract_id
      for update;

      v_outcome := app.run_solo_fake_authorization_v1(
        v_contract.id,
        v_contract.owner_id,
        v_contract.policy_version,
        v_contract.policy_digest,
        v_contract.commitment_amount_minor,
        v_contract.currency,
        v_contract.settlement_mode,
        p_scenario
      );

      raise exception 'roll back unlinked local fake authorization candidate'
        using errcode = 'P2B01';
    exception
      when sqlstate 'P2B01' then
        v_contract_id := null;
    end;

    v_result := pg_catalog.jsonb_build_object(
      'adapter_version', 'local-fake-v1',
      'outcome', v_outcome::text
    );

    insert into app.solo_rpc_requests (
      operation,
      request_scope,
      request_id,
      payload_hash,
      result
    )
    values (
      'create_solo_contract_with_fake_authorization_v2',
      v_owner_id,
      p_request_id,
      v_payload_hash,
      v_result
    );

    return v_result;
  end if;

  -- Authorized and injected-failure paths create the candidate first. An
  -- injected failure occurs afterward so PostgreSQL proves the entire v1
  -- contract/request write rolls back with the missing authorization.
  v_contract_id := public.create_solo_contract_v1(
    p_request_id,
    p_expected_policy_version,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_timezone,
    p_start_date,
    p_duration_days
  );

  select contract.* into strict v_contract
  from public.solo_contracts contract
  where contract.id = v_contract_id
  for update;

  v_outcome := app.run_solo_fake_authorization_v1(
    v_contract.id,
    v_contract.owner_id,
    v_contract.policy_version,
    v_contract.policy_digest,
    v_contract.commitment_amount_minor,
    v_contract.currency,
    v_contract.settlement_mode,
    p_scenario
  );

  if v_outcome <> 'authorized' then
    raise exception 'local fake authorization did not authorize'
      using errcode = 'restrict_violation';
  end if;

  v_authorization_id := gen_random_uuid();
  v_created_at := clock_timestamp();
  v_authorization_digest := app.solo_authorization_fact_digest_v1(
    v_contract.id,
    v_contract.owner_id,
    v_contract.policy_version,
    v_contract.policy_digest,
    v_contract.commitment_amount_minor,
    v_contract.currency,
    v_contract.settlement_mode,
    'processor_neutral_fake',
    'local-fake-v1'
  );

  perform pg_catalog.set_config(
    'app.solo_write_path',
    'create_with_fake_v2',
    true
  );

  insert into app.solo_authorizations (
    id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    adapter_kind,
    adapter_version,
    authorization_digest,
    create_request_id,
    create_request_digest,
    created_at
  )
  values (
    v_authorization_id,
    v_contract.id,
    v_contract.owner_id,
    v_contract.policy_version,
    v_contract.policy_digest,
    v_contract.commitment_amount_minor,
    v_contract.currency,
    v_contract.settlement_mode,
    'processor_neutral_fake',
    'local-fake-v1',
    v_authorization_digest,
    p_request_id,
    v_payload_hash,
    v_created_at
  );

  insert into app.solo_authorization_events (
    id,
    authorization_id,
    contract_id,
    owner_id,
    policy_version,
    policy_digest,
    commitment_amount_minor,
    currency,
    settlement_mode,
    sequence_number,
    event_kind,
    source_operation,
    event_digest,
    event_at
  )
  values (
    gen_random_uuid(),
    v_authorization_id,
    v_contract.id,
    v_contract.owner_id,
    v_contract.policy_version,
    v_contract.policy_digest,
    v_contract.commitment_amount_minor,
    v_contract.currency,
    v_contract.settlement_mode,
    1,
    'authorized',
    'create_solo_contract_with_fake_authorization_v2',
    app.solo_authorization_event_digest_v1(
      v_authorization_id,
      v_contract.id,
      v_contract.owner_id,
      v_contract.policy_version,
      v_contract.policy_digest,
      v_contract.commitment_amount_minor,
      v_contract.currency,
      v_contract.settlement_mode,
      1::smallint,
      'authorized'::app.solo_authorization_event_kind,
      'create_solo_contract_with_fake_authorization_v2',
      v_created_at
    ),
    v_created_at
  );

  v_result := pg_catalog.jsonb_build_object(
    'adapter_version', 'local-fake-v1',
    'authorization_id', v_authorization_id,
    'contract_id', v_contract.id,
    'outcome', 'authorized'
  );

  insert into app.solo_rpc_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'create_solo_contract_with_fake_authorization_v2',
    v_owner_id,
    p_request_id,
    v_payload_hash,
    v_result
  );

  return v_result;
end;
$$;

create function public.create_solo_contract_with_fake_authorization_v2(
  request_id                 uuid,
  expected_policy_version   text,
  cadence                    public.contest_cadence,
  target_steps               integer,
  commitment_amount_minor    integer,
  timezone                   text,
  start_date                 date,
  duration_days              smallint
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select app.create_solo_contract_with_fake_authorization_at_v2(
    $1,
    $2,
    $3,
    $4,
    $5,
    $6,
    $7,
    $8,
    'authorize'
  );
$$;

comment on function public.create_solo_contract_with_fake_authorization_v2(
  uuid,
  text,
  public.contest_cadence,
  integer,
  integer,
  text,
  date,
  smallint
) is
  'Owner-only exact-request atomic Solo contract plus local fake authorization. The v1 creation contract remains unchanged.';

-- ---------------------------------------------------------------------------
-- Private tables, RLS defense in depth, and exact grants
-- ---------------------------------------------------------------------------

alter table app.solo_authorizations enable row level security;
alter table app.solo_authorization_events enable row level security;

revoke all on type app.solo_fake_authorization_scenario,
                   app.solo_fake_authorization_outcome,
                   app.solo_authorization_event_kind
  from public, anon, authenticated, service_role;

revoke all on table app.solo_authorizations,
                    app.solo_authorization_events
  from public, anon, authenticated, service_role;

revoke all on function app.solo_authorization_fact_digest_v1(
                         uuid,
                         uuid,
                         text,
                         bytea,
                         integer,
                         text,
                         public.solo_settlement_mode,
                         text,
                         text
                       ),
                       app.solo_authorization_event_digest_v1(
                         uuid,
                         uuid,
                         uuid,
                         text,
                         bytea,
                         integer,
                         text,
                         public.solo_settlement_mode,
                         smallint,
                         app.solo_authorization_event_kind,
                         text,
                         timestamptz
                       ),
                       app.run_solo_fake_authorization_v1(
                         uuid,
                         uuid,
                         text,
                         bytea,
                         integer,
                         text,
                         public.solo_settlement_mode,
                         app.solo_fake_authorization_scenario
                       ),
                       app.assert_solo_authorization_write_path(),
                       app.validate_solo_authorization_insert_v1(),
                       app.validate_solo_authorization_event_insert_v1(),
                       app.append_solo_authorization_resolution_v1(),
                       app.create_solo_contract_with_fake_authorization_at_v2(
                         uuid,
                         text,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         date,
                         smallint,
                         app.solo_fake_authorization_scenario
                       )
  from public, anon, authenticated, service_role;

revoke all on function public.create_solo_contract_with_fake_authorization_v2(
                         uuid,
                         text,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         date,
                         smallint
                       )
  from public, anon, authenticated, service_role;

grant execute on function public.create_solo_contract_with_fake_authorization_v2(
                           uuid,
                           text,
                           public.contest_cadence,
                           integer,
                           integer,
                           text,
                           date,
                           smallint
                         )
  to authenticated;
