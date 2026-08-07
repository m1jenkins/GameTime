-- Database-enforced beta controls for the Stripe sandbox.
--
-- The migration deliberately starts fail-closed: payment activity is disabled
-- and the exact tester allowlist is empty. Existing obligations remain readable
-- and reconcilable, but only rows admitted under this version may use the
-- exact-retry exemption or later authorize a simulated test charge.

-- ===========================================================================
-- Private runtime, allowlist, and exact-request control ledger
-- ===========================================================================

create table app.personal_stripe_sandbox_runtime (
  singleton                boolean primary key default true
    constraint personal_stripe_runtime_singleton check (singleton),
  payment_activity_enabled boolean not null default false,
  control_version          text not null
    default 'personal-stripe-sandbox-beta-v1',
  created_at               timestamptz not null default clock_timestamp(),
  updated_at               timestamptz not null default clock_timestamp(),

  constraint personal_stripe_runtime_version check (
    control_version = 'personal-stripe-sandbox-beta-v1'
  ),
  constraint personal_stripe_runtime_times check (
    pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
    and updated_at >= created_at
  )
);

insert into app.personal_stripe_sandbox_runtime (
  singleton,
  payment_activity_enabled,
  control_version
)
values (true, false, 'personal-stripe-sandbox-beta-v1');

create table app.personal_stripe_sandbox_beta_eligibility (
  owner_id    uuid primary key
    references public.profiles (id) on delete restrict,
  eligible    boolean not null,
  created_at  timestamptz not null default clock_timestamp(),
  updated_at  timestamptz not null default clock_timestamp(),

  constraint personal_stripe_beta_eligibility_times check (
    pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
    and updated_at >= created_at
  )
);

create table app.personal_stripe_sandbox_control_requests (
  operation      text not null,
  request_scope  uuid not null,
  request_id     uuid not null,
  payload_hash   bytea not null,
  result         jsonb not null,
  created_at     timestamptz not null default clock_timestamp(),

  primary key (operation, request_scope, request_id),
  constraint personal_stripe_control_operation check (
    operation in (
      'set_personal_stripe_sandbox_runtime_v1',
      'set_personal_stripe_sandbox_beta_eligibility_v1'
    )
  ),
  constraint personal_stripe_control_payload_sha256 check (
    octet_length(payload_hash) = 32
  ),
  constraint personal_stripe_control_result_object check (
    pg_catalog.jsonb_typeof(result) = 'object'
  ),
  constraint personal_stripe_control_created_at_finite check (
    pg_catalog.isfinite(created_at)
  )
);

comment on table app.personal_stripe_sandbox_runtime is
  'Authoritative Stripe sandbox payment-activity switch. Seeded disabled.';
comment on table app.personal_stripe_sandbox_beta_eligibility is
  'Exact database-backed Stripe sandbox tester allowlist. JWT metadata is ignored.';
comment on table app.personal_stripe_sandbox_control_requests is
  'Append-only exact-request ledger for service-owned Stripe sandbox beta controls.';

alter table app.personal_stripe_sandbox_runtime enable row level security;
alter table app.personal_stripe_sandbox_beta_eligibility
  enable row level security;
alter table app.personal_stripe_sandbox_control_requests
  enable row level security;

revoke all on table app.personal_stripe_sandbox_runtime,
                    app.personal_stripe_sandbox_beta_eligibility,
                    app.personal_stripe_sandbox_control_requests
  from public, anon, authenticated, service_role;

create function app.assert_personal_stripe_sandbox_control_write_path()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_path text := current_setting(
    'app.personal_stripe_sandbox_control_write_path',
    true
  );
begin
  if v_path is null or v_path <> all(tg_argv) then
    raise exception 'Stripe sandbox controls require a versioned service boundary'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

create trigger personal_stripe_runtime_require_versioned_update
  before update on app.personal_stripe_sandbox_runtime
  for each row execute function
    app.assert_personal_stripe_sandbox_control_write_path('runtime_v1');

create trigger personal_stripe_runtime_forbid_delete
  before delete or truncate on app.personal_stripe_sandbox_runtime
  for each statement execute function app.forbid_mutation();

create trigger personal_stripe_beta_require_versioned_insert
  before insert on app.personal_stripe_sandbox_beta_eligibility
  for each row execute function
    app.assert_personal_stripe_sandbox_control_write_path('eligibility_v1');

create trigger personal_stripe_beta_require_versioned_update
  before update on app.personal_stripe_sandbox_beta_eligibility
  for each row execute function
    app.assert_personal_stripe_sandbox_control_write_path('eligibility_v1');

create trigger personal_stripe_beta_freeze_identity
  before update on app.personal_stripe_sandbox_beta_eligibility
  for each row execute function
    app.forbid_column_change('owner_id', 'created_at');

create trigger personal_stripe_beta_forbid_delete
  before delete or truncate on app.personal_stripe_sandbox_beta_eligibility
  for each statement execute function app.forbid_mutation();

create trigger personal_stripe_control_requests_require_versioned_insert
  before insert on app.personal_stripe_sandbox_control_requests
  for each row execute function
    app.assert_personal_stripe_sandbox_control_write_path(
      'runtime_v1',
      'eligibility_v1'
    );

create trigger personal_stripe_control_requests_forbid_mutation
  before update or delete or truncate
  on app.personal_stripe_sandbox_control_requests
  for each statement execute function app.forbid_mutation();

create function app.personal_stripe_sandbox_control_payload_digest_v1(
  payload jsonb
)
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

-- Every control reader takes the shared form before any profile or control-row
-- lock. Every control writer takes the exclusive form before any such lock.
-- This makes a multi-RPC operator transaction one atomic control boundary and
-- prevents profile/runtime/eligibility lock-order cycles.
create function app.lock_personal_stripe_sandbox_control_v1(
  p_exclusive boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_exclusive is null then
    raise exception 'control lock mode is required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_exclusive then
    perform pg_catalog.pg_advisory_xact_lock(20260807, 151320);
  else
    perform pg_catalog.pg_advisory_xact_lock_shared(20260807, 151320);
  end if;
end;
$$;

create function public.set_personal_stripe_sandbox_runtime_v1(
  p_request_id uuid,
  p_enabled    boolean
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_payload_hash bytea;
  v_existing     app.personal_stripe_sandbox_control_requests;
begin
  if p_request_id is null or p_enabled is null then
    raise exception 'request UUID and switch value are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_personal_stripe_sandbox_control_v1(true);

  v_payload_hash := app.personal_stripe_sandbox_control_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'enabled', p_enabled,
      'kind', 'set_personal_stripe_sandbox_runtime_v1',
      'version', 'personal-stripe-sandbox-beta-v1'
    )
  );

  perform 1
  from app.personal_stripe_sandbox_runtime runtime
  where runtime.singleton
  for update;

  if not found then
    raise exception 'Stripe sandbox beta configuration is unavailable'
      using errcode = 'insufficient_privilege';
  end if;

  select request.* into v_existing
  from app.personal_stripe_sandbox_control_requests request
  where request.operation = 'set_personal_stripe_sandbox_runtime_v1'
    and request.request_scope =
      '00000000-0000-0000-0000-000000000000'::uuid
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with a different switch value'
        using errcode = 'invalid_parameter_value';
    end if;

    return (v_existing.result ->> 'enabled')::boolean;
  end if;

  perform pg_catalog.set_config(
    'app.personal_stripe_sandbox_control_write_path',
    'runtime_v1',
    true
  );

  update app.personal_stripe_sandbox_runtime runtime
  set
    payment_activity_enabled = p_enabled,
    updated_at = clock_timestamp()
  where runtime.singleton;

  insert into app.personal_stripe_sandbox_control_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'set_personal_stripe_sandbox_runtime_v1',
    '00000000-0000-0000-0000-000000000000'::uuid,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('enabled', p_enabled)
  );

  return p_enabled;
end;
$$;

create function public.set_personal_stripe_sandbox_beta_eligibility_v1(
  p_request_id uuid,
  p_owner_id   uuid,
  p_eligible   boolean
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_payload_hash bytea;
  v_existing     app.personal_stripe_sandbox_control_requests;
  v_now          timestamptz;
begin
  if p_request_id is null
     or p_owner_id is null
     or p_eligible is null
  then
    raise exception 'request UUID, owner, and eligibility value are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_personal_stripe_sandbox_control_v1(true);

  v_payload_hash := app.personal_stripe_sandbox_control_payload_digest_v1(
    pg_catalog.jsonb_build_object(
      'eligible', p_eligible,
      'kind', 'set_personal_stripe_sandbox_beta_eligibility_v1',
      'owner_id', p_owner_id,
      'version', 'personal-stripe-sandbox-beta-v1'
    )
  );

  perform 1
  from public.profiles profile
  where profile.id = p_owner_id
  for update;

  if not found then
    raise exception 'owner is not active'
      using errcode = 'insufficient_privilege';
  end if;

  select request.* into v_existing
  from app.personal_stripe_sandbox_control_requests request
  where request.operation =
      'set_personal_stripe_sandbox_beta_eligibility_v1'
    and request.request_scope = p_owner_id
    and request.request_id = p_request_id;

  if v_existing.request_id is not null then
    if v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'request UUID already used with different beta eligibility'
        using errcode = 'invalid_parameter_value';
    end if;

    return (v_existing.result ->> 'eligible')::boolean;
  end if;

  if not app.is_active_actor(p_owner_id) then
    raise exception 'owner is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform 1
  from app.personal_stripe_sandbox_beta_eligibility beta
  where beta.owner_id = p_owner_id
  for update;

  v_now := clock_timestamp();
  perform pg_catalog.set_config(
    'app.personal_stripe_sandbox_control_write_path',
    'eligibility_v1',
    true
  );

  insert into app.personal_stripe_sandbox_beta_eligibility (
    owner_id,
    eligible,
    created_at,
    updated_at
  )
  values (p_owner_id, p_eligible, v_now, v_now)
  on conflict on constraint
    personal_stripe_sandbox_beta_eligibility_pkey
  do update
    set
      eligible = excluded.eligible,
      updated_at = excluded.updated_at;

  insert into app.personal_stripe_sandbox_control_requests (
    operation,
    request_scope,
    request_id,
    payload_hash,
    result
  )
  values (
    'set_personal_stripe_sandbox_beta_eligibility_v1',
    p_owner_id,
    p_request_id,
    v_payload_hash,
    pg_catalog.jsonb_build_object('eligible', p_eligible)
  );

  return p_eligible;
end;
$$;

create function app.personal_stripe_sandbox_runtime_enabled_v1()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_enabled boolean;
begin
  perform app.lock_personal_stripe_sandbox_control_v1(false);

  select runtime.payment_activity_enabled
  into v_enabled
  from app.personal_stripe_sandbox_runtime runtime
  where runtime.singleton
  for share;

  if not found then
    return false;
  end if;

  return v_enabled is true;
end;
$$;

create function app.require_personal_stripe_sandbox_beta_admission_v1(
  p_owner_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app.lock_personal_stripe_sandbox_control_v1(false);
  perform app.lock_active_actors(array[p_owner_id]);

  if not app.personal_stripe_sandbox_runtime_enabled_v1() then
    raise exception 'Personal Stripe sandbox beta is unavailable'
      using errcode = 'insufficient_privilege';
  end if;

  perform 1
  from app.personal_stripe_sandbox_beta_eligibility beta
  where beta.owner_id = p_owner_id
    and beta.eligible
  for share;

  if not found then
    raise exception 'Personal Stripe sandbox beta is unavailable'
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

-- ===========================================================================
-- Frozen authorization provenance for exact setup and commitment retries
-- ===========================================================================

alter table app.personal_stripe_sandbox_setups
  add column beta_authorization_version text,
  add column beta_authorized_at timestamptz,
  add constraint personal_stripe_setups_beta_authorization check (
    (
      beta_authorization_version is null
      and beta_authorized_at is null
    )
    or (
      beta_authorization_version = 'personal-stripe-sandbox-beta-v1'
      and beta_authorized_at is not null
      and pg_catalog.isfinite(beta_authorized_at)
    )
  );

alter table app.personal_stripe_sandbox_agreements
  add column beta_authorization_version text,
  add column beta_authorized_at timestamptz,
  add constraint personal_stripe_agreements_beta_authorization check (
    (
      beta_authorization_version is null
      and beta_authorized_at is null
    )
    or (
      beta_authorization_version = 'personal-stripe-sandbox-beta-v1'
      and beta_authorized_at is not null
      and pg_catalog.isfinite(beta_authorized_at)
    )
  );

create trigger personal_stripe_setups_freeze_beta_authorization
  before update on app.personal_stripe_sandbox_setups
  for each row execute function app.forbid_column_change(
    'beta_authorization_version',
    'beta_authorized_at'
  );

create trigger personal_stripe_agreements_freeze_beta_authorization
  before update on app.personal_stripe_sandbox_agreements
  for each row execute function app.forbid_column_change(
    'beta_authorization_version',
    'beta_authorized_at'
  );

create or replace function app.validate_personal_stripe_sandbox_agreement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setup   app.personal_stripe_sandbox_setups;
  v_terms   public.personal_challenge_terms;
  v_contest public.contests;
begin
  select setup.* into v_setup
  from app.personal_stripe_sandbox_setups setup
  where setup.id = new.setup_id;

  select terms.* into v_terms
  from public.personal_challenge_terms terms
  where terms.challenge_id = new.challenge_id
    and terms.user_id = new.user_id;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = new.challenge_id;

  if v_setup.id is null
     or v_terms.challenge_id is null
     or v_contest.id is null
     or v_setup.user_id <> new.user_id
     or v_setup.status <> 'succeeded'
     or v_setup.payload_hash <> new.setup_payload_hash
     or v_setup.cadence <> new.cadence
     or v_setup.target_steps <> new.target_steps
     or v_setup.commitment_amount_minor <> new.commitment_amount_minor
     or v_setup.currency <> new.currency
     or v_setup.timezone <> new.timezone
     or v_setup.requested_starts_at is distinct from new.requested_starts_at
     or v_setup.agreement_version <> new.agreement_version
     or v_setup.consent_version <> new.consent_version
     or v_setup.consented_at <> new.consented_at
     or v_setup.stripe_customer_id <> new.stripe_customer_id
     or v_setup.stripe_setup_intent_id <> new.stripe_setup_intent_id
     or v_setup.stripe_payment_method_id <> new.stripe_payment_method_id
     or v_setup.beta_authorization_version
          is distinct from new.beta_authorization_version
     or (
       new.beta_authorization_version is not null
       and new.beta_authorized_at < v_setup.beta_authorized_at
     )
     or v_terms.cadence <> new.cadence
     or v_terms.target_steps <> new.target_steps
     or v_terms.commitment_amount_minor <> new.commitment_amount_minor
     or v_terms.currency <> new.currency
     or v_terms.timezone <> new.timezone
     or v_terms.settlement_mode <> 'test_only'
     or v_contest.challenge_model <> 'personal_accountability'
     or v_contest.created_by <> new.user_id
     or (
       new.requested_starts_at is not null
       and v_contest.starts_at <> new.requested_starts_at
     )
  then
    raise exception 'Stripe sandbox agreement does not match setup and frozen Personal terms'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

-- A Customer binding may finish an already-admitted setup after the runtime
-- switch changes, but it cannot be created without such a setup.
create or replace function public.record_personal_stripe_sandbox_customer_v1(
  p_owner_id           uuid,
  p_stripe_customer_id text,
  p_livemode           boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing app.personal_stripe_sandbox_customers;
begin
  if p_owner_id is null
     or p_livemode is distinct from false
     or p_stripe_customer_id is null
     or p_stripe_customer_id !~ '^cus_[A-Za-z0-9]+$'
     or char_length(p_stripe_customer_id) > 255
  then
    raise exception 'verified owner and a Stripe test Customer are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_active_actors(array[p_owner_id]);

  select customer.* into v_existing
  from app.personal_stripe_sandbox_customers customer
  where customer.user_id = p_owner_id
  for update;

  if v_existing.user_id is not null then
    if v_existing.stripe_customer_id <> p_stripe_customer_id then
      raise exception 'owner is already bound to a different Stripe sandbox Customer'
        using errcode = 'restrict_violation';
    end if;

    return pg_catalog.jsonb_build_object(
      'stripe_customer_id', v_existing.stripe_customer_id,
      'replayed', true
    );
  end if;

  if not exists (
    select 1
    from app.personal_stripe_sandbox_setups setup
    where setup.user_id = p_owner_id
      and setup.beta_authorization_version =
        'personal-stripe-sandbox-beta-v1'
      and setup.beta_authorized_at is not null
      and setup.consumed_at is null
      and setup.status <> 'cancelled'
      and setup.expires_at > clock_timestamp()
  ) then
    raise exception 'Personal Stripe sandbox beta is unavailable'
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.personal_stripe_sandbox_customers (
    user_id, stripe_customer_id
  )
  values (p_owner_id, p_stripe_customer_id);

  return pg_catalog.jsonb_build_object(
    'stripe_customer_id', p_stripe_customer_id,
    'replayed', false
  );
end;
$$;

create or replace function app.begin_personal_stripe_sandbox_setup_unchecked(
  p_owner_id                 uuid,
  p_request_id               uuid,
  p_cadence                  public.contest_cadence,
  p_target_steps             integer,
  p_commitment_amount_minor  integer,
  p_currency                 text,
  p_timezone                 text,
  p_requested_starts_at      timestamptz,
  p_agreement_version        text,
  p_consent_version          text,
  p_include_provider_ids     boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_now          timestamptz;
  v_local_start  timestamp;
  v_payload_hash bytea;
  v_existing     app.personal_stripe_sandbox_setups;
  v_setup_id     uuid;
begin
  if p_owner_id is null then
    raise exception 'verified owner is required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_personal_stripe_sandbox_control_v1(false);
  perform app.lock_active_actors(array[p_owner_id]);
  v_now := clock_timestamp();

  if p_request_id is null
     or p_cadence is null
     or p_target_steps is null
     or p_target_steps not between 1 and 1000000
     or p_commitment_amount_minor not in (1000, 2000, 3000, 4000, 5000)
     or p_currency <> 'USD'
     or p_agreement_version <> 'personal-stripe-sandbox-v1'
     or p_consent_version <> 'personal-stripe-sandbox-consent-v1'
     or p_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names zone
       where zone.name = p_timezone
     )
  then
    raise exception 'valid request, Personal terms, timezone, and consent version are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_requested_starts_at is not null then
    if not pg_catalog.isfinite(p_requested_starts_at) then
      raise exception 'chosen start must be finite'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := p_requested_starts_at at time zone p_timezone;

    if extract(minute from v_local_start) <> 0
       or extract(second from v_local_start) <> 0
       or p_requested_starts_at <= v_now
       or p_requested_starts_at > v_now + interval '90 days'
    then
      raise exception 'chosen start must be a future whole local hour within 90 days'
        using errcode = 'invalid_parameter_value';
    end if;
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'kind', 'personal_stripe_sandbox_setup_v1',
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
        'consent_version', p_consent_version,
        'provider', 'stripe',
        'environment', 'sandbox',
        'livemode', false
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  select setup.* into v_existing
  from app.personal_stripe_sandbox_setups setup
  where setup.user_id = p_owner_id
    and setup.request_id = p_request_id;

  if v_existing.id is not null then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception 'setup request UUID already used with different terms'
        using errcode = 'invalid_parameter_value';
    end if;

    if v_existing.beta_authorization_version is distinct from
         'personal-stripe-sandbox-beta-v1'
       or v_existing.beta_authorized_at is null
    then
      raise exception 'setup request was not admitted by the Stripe sandbox beta controls'
        using errcode = 'insufficient_privilege';
    end if;

    return pg_catalog.jsonb_strip_nulls(
      pg_catalog.jsonb_build_object(
        'setup_id', v_existing.id,
        'status', v_existing.status,
        'expires_at', v_existing.expires_at,
        'replayed', true
      )
      || case
           when p_include_provider_ids then
             pg_catalog.jsonb_build_object(
               'stripe_customer_id', v_existing.stripe_customer_id,
               'stripe_setup_intent_id', v_existing.stripe_setup_intent_id
             )
           else '{}'::jsonb
         end
    );
  end if;

  perform app.require_personal_stripe_sandbox_beta_admission_v1(p_owner_id);

  insert into app.personal_stripe_sandbox_setups (
    user_id,
    request_id,
    payload_hash,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    timezone,
    requested_starts_at,
    agreement_version,
    consent_version,
    consented_at,
    expires_at,
    beta_authorization_version,
    beta_authorized_at
  )
  values (
    p_owner_id,
    p_request_id,
    v_payload_hash,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_currency,
    p_timezone,
    p_requested_starts_at,
    p_agreement_version,
    p_consent_version,
    v_now,
    v_now + interval '24 hours',
    'personal-stripe-sandbox-beta-v1',
    v_now
  )
  returning id into v_setup_id;

  return pg_catalog.jsonb_build_object(
    'setup_id', v_setup_id,
    'status', 'pending_provider',
    'expires_at', v_now + interval '24 hours',
    'replayed', false
  );
end;
$$;

-- The authenticated wrapper must enter the shared control epoch before
-- require_active_caller locks the profile. Otherwise an atomic shutdown that
-- already owns the exclusive epoch could wait on that profile while this
-- request waits on the shared epoch.
create or replace function public.begin_personal_stripe_sandbox_setup_v1(
  p_request_id               uuid,
  p_cadence                  public.contest_cadence,
  p_target_steps             integer,
  p_commitment_amount_minor  integer,
  p_currency                 text,
  p_timezone                 text,
  p_requested_starts_at      timestamptz default null,
  p_agreement_version        text default
    'personal-stripe-sandbox-v1',
  p_consent_version          text default
    'personal-stripe-sandbox-consent-v1'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app.lock_personal_stripe_sandbox_control_v1(false);
  v_owner_id := app.require_active_caller();

  return app.begin_personal_stripe_sandbox_setup_unchecked(
    v_owner_id,
    p_request_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_currency,
    p_timezone,
    p_requested_starts_at,
    p_agreement_version,
    p_consent_version,
    false
  );
end;
$$;

create or replace function app.commit_personal_stripe_sandbox_challenge_unchecked(
  p_owner_id                 uuid,
  p_request_id               uuid,
  p_setup_id                 uuid,
  p_cadence                  public.contest_cadence,
  p_target_steps             integer,
  p_commitment_amount_minor  integer,
  p_currency                 text,
  p_timezone                 text,
  p_requested_starts_at      timestamptz,
  p_agreement_version        text,
  p_consent_version          text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_setup          app.personal_stripe_sandbox_setups;
  v_existing       app.personal_stripe_sandbox_agreements;
  v_base_request   app.personal_challenge_creation_requests;
  v_creation_hash  bytea;
  v_challenge_id   uuid;
  v_old_claims     text;
  v_now            timestamptz;
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
       or v_existing.creation_payload_hash <> v_creation_hash
    then
      raise exception 'challenge request UUID already used with different Stripe terms'
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

  -- Preserve Personal V1 as the only challenge constructor. The explicit
  -- service owner is copied into a transaction-local JWT claim solely for this
  -- nested call; it is restored before this function returns.
  v_old_claims := current_setting('request.jwt.claims', true);
  perform set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', p_owner_id)::text,
    true
  );

  v_challenge_id := public.create_personal_challenge_v1(
    p_request_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_timezone,
    p_requested_starts_at
  );

  perform set_config(
    'request.jwt.claims',
    case
      when v_old_claims is null or v_old_claims = '' then '{}'
      else v_old_claims
    end,
    true
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
  set
    consumed_at = v_now,
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

-- Match the setup wrapper's advisory-before-profile order for the second
-- authenticated payment mutation.
create or replace function public.create_personal_challenge_with_stripe_sandbox_v2(
  p_request_id               uuid,
  p_setup_id                 uuid,
  p_cadence                  public.contest_cadence,
  p_target_steps             integer,
  p_commitment_amount_minor  integer,
  p_currency                 text,
  p_timezone                 text,
  p_requested_starts_at      timestamptz default null,
  p_agreement_version        text default
    'personal-stripe-sandbox-v1',
  p_consent_version          text default
    'personal-stripe-sandbox-consent-v1'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app.lock_personal_stripe_sandbox_control_v1(false);
  v_owner_id := app.require_active_caller();

  return app.commit_personal_stripe_sandbox_challenge_unchecked(
    v_owner_id,
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
  );
end;
$$;

create or replace function public.settle_personal_stripe_sandbox_review_v1(
  p_review_id    uuid,
  p_action       text,
  p_reason_code  text,
  p_reference    text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_review       app.personal_stripe_sandbox_payment_reviews;
  v_result       public.personal_challenge_results;
  v_agreement    app.personal_stripe_sandbox_agreements;
  v_contest      public.contests;
  v_now          timestamptz := clock_timestamp();
  v_command_id   uuid;
  v_target_state text;
  v_probe_state  text;
  v_owner_id     uuid;
begin
  if p_review_id is null
     or p_action not in ('start_review', 'confirm_miss', 'waive')
     or p_reason_code is null
     or char_length(p_reason_code) not between 1 and 80
     or p_reason_code !~ '^[a-z0-9][a-z0-9_]*$'
     or (
       p_reference is not null
       and char_length(p_reference) not between 1 and 160
     )
  then
    raise exception 'valid review action, reason, and bounded reference are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Read the owner before taking the review lock. A new charge-authorizing
  -- decision follows the common profile -> runtime -> eligibility -> review
  -- lock order. Terminal exact retries intentionally recover without rechecking
  -- mutable rollout controls.
  select review.user_id, review.state
  into v_owner_id, v_probe_state
  from app.personal_stripe_sandbox_payment_reviews review
  where review.id = p_review_id;

  if v_owner_id is null then
    raise exception 'Stripe sandbox payment review not found'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_action = 'confirm_miss'
     and v_probe_state not in ('confirmed_miss', 'waived')
  then
    perform app.require_personal_stripe_sandbox_beta_admission_v1(v_owner_id);
  end if;

  select review.* into v_review
  from app.personal_stripe_sandbox_payment_reviews review
  where review.id = p_review_id
  for update;

  if v_review.id is null then
    raise exception 'Stripe sandbox payment review not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select result.* into v_result
  from public.personal_challenge_results result
  where result.id = v_review.result_id;

  select agreement.* into v_agreement
  from app.personal_stripe_sandbox_agreements agreement
  where agreement.challenge_id = v_review.challenge_id
    and agreement.user_id = v_review.user_id;

  select contest.* into v_contest
  from public.contests contest
  where contest.id = v_review.challenge_id;

  if v_result.id is null
     or v_agreement.challenge_id is null
     or v_contest.id is null
     or v_contest.status <> 'finalized'
     or v_result.outcome <> 'missed_goal'
     or v_result.reason <> 'target_missed'
     or v_result.evidence_state <> 'complete'
     or v_result.commitment_waived
  then
    raise exception 'review no longer has an exact chargeable Personal miss'
      using errcode = 'restrict_violation';
  end if;

  v_target_state := case
    when p_action = 'confirm_miss' then 'confirmed_miss'
    when p_action = 'waive' then 'waived'
    else 'under_review'
  end;

  if v_review.state in ('confirmed_miss', 'waived') then
    if v_review.state <> v_target_state
       or v_review.decision_reason_code <> p_reason_code
       or v_review.decision_reference is distinct from p_reference
    then
      raise exception 'terminal review decision cannot change'
        using errcode = 'restrict_violation';
    end if;

    select command.id into v_command_id
    from app.personal_stripe_sandbox_charge_commands command
    where command.review_id = v_review.id;

    return pg_catalog.jsonb_strip_nulls(
      pg_catalog.jsonb_build_object(
        'review_id', v_review.id,
        'state', v_review.state,
        'charge_command_id', v_command_id,
        'replayed', true
      )
    );
  end if;

  if p_action = 'start_review' then
    if v_review.state <> 'review_open'
       or v_now >= v_review.review_deadline
       or p_reason_code <> 'review_requested'
       or p_reference is null
    then
      raise exception 'review may start once, before its deadline, with a case reference'
        using errcode = 'restrict_violation';
    end if;

    update app.personal_stripe_sandbox_payment_reviews review
    set
      state = 'under_review',
      review_started_at = v_now,
      review_reason_code = p_reason_code,
      review_reference = p_reference,
      updated_at = v_now
    where review.id = v_review.id;
  elsif p_action = 'confirm_miss' then
    if v_agreement.beta_authorization_version is distinct from
         'personal-stripe-sandbox-beta-v1'
       or v_agreement.beta_authorized_at is null
    then
      raise exception 'payment commitment was not admitted by the Stripe sandbox beta controls'
        using errcode = 'insufficient_privilege';
    end if;

    if (
      v_review.state = 'review_open'
      and (
        v_now < v_review.review_deadline
        or p_reason_code <> 'review_window_expired'
        or p_reference is not null
      )
    )
    or (
      v_review.state = 'under_review'
      and (
        p_reason_code <> 'review_upheld'
        or p_reference is null
      )
    )
    then
      raise exception 'miss confirmation requires an expired open window or an upheld review'
        using errcode = 'restrict_violation';
    end if;

    update app.personal_stripe_sandbox_payment_reviews review
    set
      state = 'confirmed_miss',
      decision_reason_code = p_reason_code,
      decision_reference = p_reference,
      decided_at = v_now,
      updated_at = v_now
    where review.id = v_review.id;

    insert into app.personal_stripe_sandbox_charge_commands (
      challenge_id,
      result_id,
      review_id,
      user_id,
      amount_minor,
      currency,
      stripe_customer_id,
      stripe_payment_method_id,
      stripe_idempotency_key,
      next_attempt_at
    )
    values (
      v_review.challenge_id,
      v_review.result_id,
      v_review.id,
      v_review.user_id,
      v_agreement.commitment_amount_minor,
      v_agreement.currency,
      v_agreement.stripe_customer_id,
      v_agreement.stripe_payment_method_id,
      'gt:personal-charge:v1:' || v_review.result_id::text,
      greatest(v_now, v_review.review_deadline)
    )
    on conflict (review_id) do nothing
    returning id into v_command_id;

    if v_command_id is null then
      select command.id into v_command_id
      from app.personal_stripe_sandbox_charge_commands command
      where command.review_id = v_review.id;
    end if;
  else
    update app.personal_stripe_sandbox_payment_reviews review
    set
      state = 'waived',
      decision_reason_code = p_reason_code,
      decision_reference = p_reference,
      decided_at = v_now,
      updated_at = v_now
    where review.id = v_review.id;
  end if;

  return pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'review_id', v_review.id,
      'state', v_target_state,
      'charge_command_id', v_command_id,
      'replayed', false
    )
  );
end;
$$;

create or replace function public.claim_personal_stripe_sandbox_charges_v1(
  p_lease_owner uuid,
  p_limit       integer default 25
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_claims              jsonb;
  v_now                 timestamptz := clock_timestamp();
  v_admitted_owner_ids  uuid[] := '{}'::uuid[];
  v_owner_id            uuid;
begin
  if p_lease_owner is null or p_limit not between 1 and 100 then
    raise exception 'lease owner and a limit from 1 through 100 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_personal_stripe_sandbox_control_v1(false);

  -- Missing runtime configuration is disabled. Returning an empty batch keeps
  -- the worker safe without preventing fail-safe no-charge resolution.
  if not app.personal_stripe_sandbox_runtime_enabled_v1() then
    update app.personal_stripe_sandbox_payment_reviews review
    set
      state = 'waived',
      decision_reason_code = 'review_unresolved_at_deadline',
      decision_reference = review.review_reference,
      decided_at = v_now,
      updated_at = v_now
    where review.state = 'under_review'
      and review.review_deadline <= v_now;

    return '[]'::jsonb;
  end if;

  -- Freeze the currently active allowlisted owners and hold their profile rows
  -- through commit. Account deletion takes an incompatible profile lock, so it
  -- either commits before this snapshot (and is excluded) or waits until this
  -- claim transaction has completely finished.
  for v_owner_id in
    select beta.owner_id
    from app.personal_stripe_sandbox_beta_eligibility beta
    join public.profiles profile
      on profile.id = beta.owner_id
     and profile.deleted_at is null
    join app.active_profile_auth_bindings binding
      on binding.actor_id = profile.id
    join auth.users auth_user
      on auth_user.id = profile.id
    where beta.eligible
    order by beta.owner_id
    for share of profile
  loop
    v_admitted_owner_ids :=
      pg_catalog.array_append(v_admitted_owner_ids, v_owner_id);
  end loop;

  -- The shared transaction lock already excludes service-owned revocations.
  -- Row locks add a second, explicit freeze of the exact positive entries used
  -- by all charge-capable statements below.
  perform 1
  from app.personal_stripe_sandbox_beta_eligibility beta
  where beta.owner_id = any (v_admitted_owner_ids)
    and beta.eligible
  order by beta.owner_id
  for share;

  -- An unresolved filed review automatically waives at its absolute deadline.
  -- Eligible active profiles were locked first, matching the confirm-miss path;
  -- inactive or ineligible owners cannot enter that charge-authorizing path.
  update app.personal_stripe_sandbox_payment_reviews review
  set
    state = 'waived',
    decision_reason_code = 'review_unresolved_at_deadline',
    decision_reference = review.review_reference,
    decided_at = v_now,
    updated_at = v_now
  where review.state = 'under_review'
    and review.review_deadline <= v_now;

  -- Silence is not an indefinite hold, but only a currently active, allowlisted
  -- owner with a controls-era agreement may receive a new confirmation.
  update app.personal_stripe_sandbox_payment_reviews review
  set
    state = 'confirmed_miss',
    decision_reason_code = 'review_window_expired',
    decision_reference = null,
    decided_at = v_now,
    updated_at = v_now
  where review.state = 'review_open'
    and review.review_deadline <= v_now
    and review.user_id = any (v_admitted_owner_ids)
    and app.is_active_actor(review.user_id)
    and exists (
      select 1
      from app.personal_stripe_sandbox_beta_eligibility beta
      join app.personal_stripe_sandbox_agreements agreement
        on agreement.challenge_id = review.challenge_id
       and agreement.user_id = review.user_id
      where beta.owner_id = review.user_id
        and beta.eligible
        and agreement.beta_authorization_version =
          'personal-stripe-sandbox-beta-v1'
        and agreement.beta_authorized_at is not null
    );

  -- Discover both deadline confirmations above and completed upheld reviews.
  -- Legacy, inactive, or nonallowlisted agreements remain resolvable but cannot
  -- create a new simulated charge command.
  insert into app.personal_stripe_sandbox_charge_commands (
    challenge_id,
    result_id,
    review_id,
    user_id,
    amount_minor,
    currency,
    stripe_customer_id,
    stripe_payment_method_id,
    stripe_idempotency_key,
    next_attempt_at
  )
  select
    review.challenge_id,
    review.result_id,
    review.id,
    review.user_id,
    agreement.commitment_amount_minor,
    agreement.currency,
    agreement.stripe_customer_id,
    agreement.stripe_payment_method_id,
    'gt:personal-charge:v1:' || review.result_id::text,
    greatest(v_now, review.review_deadline)
  from app.personal_stripe_sandbox_payment_reviews review
  join app.personal_stripe_sandbox_agreements agreement
    on agreement.challenge_id = review.challenge_id
   and agreement.user_id = review.user_id
  join app.personal_stripe_sandbox_beta_eligibility beta
    on beta.owner_id = review.user_id
   and beta.eligible
  join public.personal_challenge_results result
    on result.id = review.result_id
   and result.challenge_id = review.challenge_id
   and result.user_id = review.user_id
   and result.outcome = 'missed_goal'
   and result.reason = 'target_missed'
   and result.evidence_state = 'complete'
   and not result.commitment_waived
  join public.contests contest
    on contest.id = review.challenge_id
   and contest.status = 'finalized'
   and contest.challenge_model = 'personal_accountability'
  where review.state = 'confirmed_miss'
    and review.user_id = any (v_admitted_owner_ids)
    and agreement.beta_authorization_version =
      'personal-stripe-sandbox-beta-v1'
    and agreement.beta_authorized_at is not null
    and app.is_active_actor(review.user_id)
  on conflict (review_id) do nothing;

  with due as (
    select command.id
    from app.personal_stripe_sandbox_charge_commands command
    join app.personal_stripe_sandbox_payment_reviews review
      on review.id = command.review_id
     and review.state = 'confirmed_miss'
    join app.personal_stripe_sandbox_agreements agreement
      on agreement.challenge_id = command.challenge_id
     and agreement.user_id = command.user_id
     and agreement.beta_authorization_version =
       'personal-stripe-sandbox-beta-v1'
     and agreement.beta_authorized_at is not null
    join app.personal_stripe_sandbox_beta_eligibility beta
      on beta.owner_id = command.user_id
     and beta.eligible
    join public.personal_challenge_results result
      on result.id = command.result_id
     and result.challenge_id = command.challenge_id
     and result.user_id = command.user_id
     and result.outcome = 'missed_goal'
     and result.reason = 'target_missed'
     and result.evidence_state = 'complete'
     and not result.commitment_waived
    join public.contests contest
      on contest.id = command.challenge_id
     and contest.status = 'finalized'
     and contest.challenge_model = 'personal_accountability'
    where command.status = 'pending'
      and command.user_id = any (v_admitted_owner_ids)
      and app.is_active_actor(command.user_id)
      and review.review_deadline <= v_now
      and command.attempt_count < 3
      and (
        command.first_attempted_at is null
        or v_now < command.first_attempted_at + interval '23 hours'
      )
      and command.next_attempt_at <= v_now
      and (
        command.lease_expires_at is null
        or command.lease_expires_at <= v_now
      )
    order by command.created_at, command.id
    for update of command skip locked
    limit p_limit
  ),
  claimed as (
    update app.personal_stripe_sandbox_charge_commands command
    set
      attempt_count = command.attempt_count + 1,
      first_attempted_at = coalesce(command.first_attempted_at, v_now),
      lease_owner = p_lease_owner,
      lease_expires_at = v_now + interval '2 minutes',
      updated_at = v_now
    from due
    where command.id = due.id
    returning command.*
  )
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'command_id', claimed.id,
        'challenge_id', claimed.challenge_id,
        'result_id', claimed.result_id,
        'owner_id', claimed.user_id,
        'amount_minor', claimed.amount_minor,
        'currency', claimed.currency,
        'stripe_customer_id', claimed.stripe_customer_id,
        'stripe_payment_method_id', claimed.stripe_payment_method_id,
        'stripe_payment_intent_id', claimed.stripe_payment_intent_id,
        'stripe_idempotency_key', claimed.stripe_idempotency_key,
        'attempt_count', claimed.attempt_count,
        'livemode', claimed.livemode,
        'integration_api_version', claimed.integration_api_version
      )
      order by claimed.created_at, claimed.id
    ),
    '[]'::jsonb
  )
  into v_claims
  from claimed;

  return v_claims;
end;
$$;

-- ===========================================================================
-- Explicit privileges and operator-facing contracts
-- ===========================================================================

revoke all on function
  app.assert_personal_stripe_sandbox_control_write_path(),
  app.personal_stripe_sandbox_control_payload_digest_v1(jsonb),
  app.lock_personal_stripe_sandbox_control_v1(boolean),
  app.personal_stripe_sandbox_runtime_enabled_v1(),
  app.require_personal_stripe_sandbox_beta_admission_v1(uuid)
  from public, anon, authenticated, service_role;

revoke all on function
  public.set_personal_stripe_sandbox_runtime_v1(uuid, boolean),
  public.set_personal_stripe_sandbox_beta_eligibility_v1(
    uuid, uuid, boolean
  )
  from public, anon, authenticated, service_role;

grant execute on function
  public.set_personal_stripe_sandbox_runtime_v1(uuid, boolean),
  public.set_personal_stripe_sandbox_beta_eligibility_v1(
    uuid, uuid, boolean
  )
  to service_role;

comment on function
  public.set_personal_stripe_sandbox_runtime_v1(uuid, boolean) is
  'Service-only exact-request Stripe sandbox beta kill switch. Seeded disabled.';
comment on function
  public.set_personal_stripe_sandbox_beta_eligibility_v1(
    uuid, uuid, boolean
  ) is
  'Service-only exact-request Stripe sandbox tester allowlist. JWT metadata is ignored.';
comment on function
  app.require_personal_stripe_sandbox_beta_admission_v1(uuid) is
  'Private active-owner, runtime, and exact allowlist admission boundary.';
comment on function
  app.lock_personal_stripe_sandbox_control_v1(boolean) is
  'Private transaction epoch: shared for admitted work and exclusive for control changes.';
comment on function
  public.begin_personal_stripe_sandbox_setup_v1(
    uuid,
    public.contest_cadence,
    integer,
    integer,
    text,
    text,
    timestamptz,
    text,
    text
  ) is
  'Authenticated exact-request setup consent. Requires database beta admission and returns no Stripe identifiers or client secret.';
comment on function
  public.create_personal_challenge_with_stripe_sandbox_v2(
    uuid,
    uuid,
    public.contest_cadence,
    integer,
    integer,
    text,
    text,
    timestamptz,
    text,
    text
  ) is
  'Authenticated Stripe sandbox commitment. Acquires the shared control epoch before active-owner locking and database beta admission.';
comment on function
  public.commit_personal_stripe_sandbox_challenge_service_v1(
    uuid,
    uuid,
    uuid,
    public.contest_cadence,
    integer,
    integer,
    text,
    text,
    timestamptz,
    text,
    text
  ) is
  'Service-only Edge commit with an explicit active owner and database beta admission. Exact controls-era retries remain recoverable.';
comment on function
  public.claim_personal_stripe_sandbox_charges_v1(uuid, integer) is
  'Service-only bounded sandbox dispatch claim. Disabled or ineligible work returns no claims while overdue filed reviews still waive safely.';
