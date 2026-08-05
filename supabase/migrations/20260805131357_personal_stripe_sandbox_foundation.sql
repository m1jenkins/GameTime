-- Personal Stripe sandbox foundation.
--
-- This migration deliberately does not turn Personal V1 into a live-money
-- product. It stores only Stripe test-mode identifiers and normalized states.
-- A saved payment method is bound to frozen challenge terms, a missed result
-- opens a seven-day review, and only a later service decision may enqueue one
-- off-session test charge.

-- ===========================================================================
-- Private provider bindings and settlement state
-- ===========================================================================

create table app.personal_stripe_sandbox_customers (
  user_id                 uuid primary key
    references public.profiles (id) on delete restrict,
  stripe_customer_id      text not null unique,
  provider                text not null default 'stripe',
  environment             text not null default 'sandbox',
  livemode                boolean not null default false,
  integration_api_version text not null default '2026-02-25.clover',
  created_at              timestamptz not null default clock_timestamp(),

  constraint personal_stripe_customers_binding_unique
    unique (user_id, stripe_customer_id),
  constraint personal_stripe_customers_fixed_provenance check (
    provider = 'stripe'
    and environment = 'sandbox'
    and not livemode
    and integration_api_version = '2026-02-25.clover'
  ),
  constraint personal_stripe_customers_id_shape check (
    char_length(stripe_customer_id) between 5 and 255
    and stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'
  ),
  constraint personal_stripe_customers_time_finite check (
    pg_catalog.isfinite(created_at)
  )
);

create table app.personal_stripe_sandbox_setups (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null
    references public.profiles (id) on delete restrict,
  request_id               uuid not null,
  payload_hash             bytea not null,
  cadence                  public.contest_cadence not null,
  target_steps             integer not null,
  commitment_amount_minor  integer not null,
  currency                 text not null default 'USD',
  timezone                 text not null,
  requested_starts_at      timestamptz,
  agreement_version        text not null default 'personal-stripe-sandbox-v1',
  consent_version          text not null,
  consented_at             timestamptz not null,
  expires_at               timestamptz not null,
  stripe_customer_id       text,
  stripe_setup_intent_id   text unique,
  stripe_payment_method_id text,
  status                   text not null default 'pending_provider',
  succeeded_at             timestamptz,
  consumed_at              timestamptz,
  consumed_challenge_id    uuid unique
    references public.contests (id) on delete restrict,
  provider                 text not null default 'stripe',
  environment              text not null default 'sandbox',
  livemode                 boolean not null default false,
  integration_api_version  text not null default '2026-02-25.clover',
  created_at               timestamptz not null default clock_timestamp(),
  updated_at               timestamptz not null default clock_timestamp(),

  constraint personal_stripe_setups_request_unique unique (user_id, request_id),
  constraint personal_stripe_setups_customer_fkey
    foreign key (user_id, stripe_customer_id)
    references app.personal_stripe_sandbox_customers (
      user_id, stripe_customer_id
    )
    on delete restrict,
  constraint personal_stripe_setups_digest check (
    octet_length(payload_hash) = 32
  ),
  constraint personal_stripe_setups_terms check (
    target_steps between 1 and 1000000
    and commitment_amount_minor in (1000, 2000, 3000, 4000, 5000)
    and currency = 'USD'
    and char_length(timezone) between 1 and 80
    and agreement_version = 'personal-stripe-sandbox-v1'
    and consent_version = 'personal-stripe-sandbox-consent-v1'
  ),
  constraint personal_stripe_setups_fixed_provenance check (
    provider = 'stripe'
    and environment = 'sandbox'
    and not livemode
    and integration_api_version = '2026-02-25.clover'
  ),
  constraint personal_stripe_setups_provider_shape check (
    (
      status = 'pending_provider'
      and (
        (stripe_customer_id is null and stripe_setup_intent_id is null)
        or (
          stripe_customer_id is not null
          and stripe_setup_intent_id is not null
        )
      )
      and stripe_payment_method_id is null
      and succeeded_at is null
    )
    or (
      status in (
        'requires_action',
        'processing',
        'cancelled'
      )
      and stripe_customer_id is not null
      and stripe_setup_intent_id is not null
      and stripe_payment_method_id is null
      and succeeded_at is null
    )
    or (
      status = 'succeeded'
      and stripe_customer_id is not null
      and stripe_setup_intent_id is not null
      and stripe_payment_method_id is not null
      and succeeded_at is not null
    )
  ),
  constraint personal_stripe_setups_provider_ids check (
    (stripe_customer_id is null or stripe_customer_id ~ '^cus_[A-Za-z0-9]+$')
    and (
      stripe_setup_intent_id is null
      or stripe_setup_intent_id ~ '^seti_[A-Za-z0-9]+$'
    )
    and (
      stripe_payment_method_id is null
      or stripe_payment_method_id ~ '^pm_[A-Za-z0-9]+$'
    )
  ),
  constraint personal_stripe_setups_consumption_shape check (
    (consumed_at is null) = (consumed_challenge_id is null)
    and (consumed_at is null or status = 'succeeded')
  ),
  constraint personal_stripe_setups_times check (
    pg_catalog.isfinite(consented_at)
    and pg_catalog.isfinite(expires_at)
    and expires_at = consented_at + interval '24 hours'
    and (
      requested_starts_at is null
      or pg_catalog.isfinite(requested_starts_at)
    )
    and (
      succeeded_at is null
      or (
        pg_catalog.isfinite(succeeded_at)
        and succeeded_at >= consented_at
      )
    )
    and (
      consumed_at is null
      or (
        pg_catalog.isfinite(consumed_at)
        and succeeded_at is not null
        and consumed_at >= succeeded_at
      )
    )
    and pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
  )
);

create table app.personal_stripe_sandbox_agreements (
  challenge_id             uuid primary key,
  user_id                  uuid not null,
  setup_id                 uuid not null unique
    references app.personal_stripe_sandbox_setups (id) on delete restrict,
  create_request_id        uuid not null,
  creation_payload_hash    bytea not null,
  setup_payload_hash       bytea not null,
  cadence                  public.contest_cadence not null,
  target_steps             integer not null,
  commitment_amount_minor  integer not null,
  currency                 text not null,
  timezone                 text not null,
  requested_starts_at      timestamptz,
  agreement_version        text not null,
  consent_version          text not null,
  consented_at             timestamptz not null,
  stripe_customer_id       text not null,
  stripe_setup_intent_id   text not null unique,
  stripe_payment_method_id text not null,
  provider                 text not null default 'stripe',
  environment              text not null default 'sandbox',
  livemode                 boolean not null default false,
  integration_api_version  text not null default '2026-02-25.clover',
  created_at               timestamptz not null default clock_timestamp(),

  constraint personal_stripe_agreements_owner_request_unique
    unique (user_id, create_request_id),
  constraint personal_stripe_agreements_owner_unique
    unique (challenge_id, user_id),
  constraint personal_stripe_agreements_terms_fkey
    foreign key (challenge_id, user_id)
    references public.personal_challenge_terms (challenge_id, user_id)
    on delete restrict,
  constraint personal_stripe_agreements_digests check (
    octet_length(creation_payload_hash) = 32
    and octet_length(setup_payload_hash) = 32
  ),
  constraint personal_stripe_agreements_fixed_terms check (
    target_steps between 1 and 1000000
    and commitment_amount_minor in (1000, 2000, 3000, 4000, 5000)
    and currency = 'USD'
    and agreement_version = 'personal-stripe-sandbox-v1'
    and consent_version = 'personal-stripe-sandbox-consent-v1'
  ),
  constraint personal_stripe_agreements_fixed_provenance check (
    provider = 'stripe'
    and environment = 'sandbox'
    and not livemode
    and integration_api_version = '2026-02-25.clover'
  ),
  constraint personal_stripe_agreements_provider_ids check (
    stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'
    and stripe_setup_intent_id ~ '^seti_[A-Za-z0-9]+$'
    and stripe_payment_method_id ~ '^pm_[A-Za-z0-9]+$'
  ),
  constraint personal_stripe_agreements_times check (
    pg_catalog.isfinite(consented_at)
    and (
      requested_starts_at is null
      or pg_catalog.isfinite(requested_starts_at)
    )
    and pg_catalog.isfinite(created_at)
  )
);

create table app.personal_stripe_sandbox_payment_reviews (
  id                   uuid primary key default gen_random_uuid(),
  challenge_id         uuid not null unique,
  result_id            uuid not null unique
    references public.personal_challenge_results (id) on delete restrict,
  user_id              uuid not null,
  state                text not null default 'review_open',
  opened_at            timestamptz not null,
  review_deadline      timestamptz not null,
  review_started_at    timestamptz,
  review_reason_code   text,
  review_reference     text,
  decision_reason_code text,
  decision_reference   text,
  decided_at           timestamptz,
  created_at           timestamptz not null default clock_timestamp(),
  updated_at           timestamptz not null default clock_timestamp(),

  constraint personal_stripe_reviews_agreement_fkey
    foreign key (challenge_id, user_id)
    references app.personal_stripe_sandbox_agreements (
      challenge_id, user_id
    )
    on delete restrict,
  constraint personal_stripe_reviews_state check (
    state in ('review_open', 'under_review', 'confirmed_miss', 'waived')
  ),
  constraint personal_stripe_reviews_shape check (
    (
      state = 'review_open'
      and review_started_at is null
      and review_reason_code is null
      and review_reference is null
      and decision_reason_code is null
      and decision_reference is null
      and decided_at is null
    )
    or (
      state = 'under_review'
      and review_started_at is not null
      and review_reason_code is not null
      and decision_reason_code is null
      and decision_reference is null
      and decided_at is null
    )
    or (
      state in ('confirmed_miss', 'waived')
      and decision_reason_code is not null
      and decided_at is not null
    )
  ),
  constraint personal_stripe_reviews_bounded_text check (
    (
      review_reason_code is null
      or (
        char_length(review_reason_code) between 1 and 80
        and review_reason_code ~ '^[a-z0-9][a-z0-9_]*$'
      )
    )
    and (
      review_reference is null
      or char_length(review_reference) between 1 and 160
    )
    and (
      decision_reason_code is null
      or (
        char_length(decision_reason_code) between 1 and 80
        and decision_reason_code ~ '^[a-z0-9][a-z0-9_]*$'
      )
    )
    and (
      decision_reference is null
      or char_length(decision_reference) between 1 and 160
    )
  ),
  constraint personal_stripe_reviews_times check (
    pg_catalog.isfinite(opened_at)
    and review_deadline = opened_at + interval '7 days'
    and (
      review_started_at is null
      or (
        pg_catalog.isfinite(review_started_at)
        and review_started_at >= opened_at
      )
    )
    and (
      decided_at is null
      or (
        pg_catalog.isfinite(decided_at)
        and decided_at >= opened_at
      )
    )
    and pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
  )
);

create table app.personal_stripe_sandbox_charge_commands (
  id                       uuid primary key default gen_random_uuid(),
  challenge_id             uuid not null unique,
  result_id                uuid not null unique
    references public.personal_challenge_results (id) on delete restrict,
  review_id                uuid not null unique
    references app.personal_stripe_sandbox_payment_reviews (id)
      on delete restrict,
  user_id                  uuid not null,
  amount_minor             integer not null,
  currency                 text not null,
  stripe_customer_id       text not null,
  stripe_payment_method_id text not null,
  stripe_payment_intent_id text unique,
  stripe_idempotency_key   text not null unique,
  status                   text not null default 'pending',
  attempt_count            smallint not null default 0,
  first_attempted_at       timestamptz,
  next_attempt_at          timestamptz not null default clock_timestamp(),
  lease_owner              uuid,
  lease_expires_at         timestamptz,
  last_failure_code        text,
  succeeded_at             timestamptz,
  terminal_at              timestamptz,
  provider                 text not null default 'stripe',
  environment              text not null default 'sandbox',
  livemode                 boolean not null default false,
  integration_api_version  text not null default '2026-02-25.clover',
  created_at               timestamptz not null default clock_timestamp(),
  updated_at               timestamptz not null default clock_timestamp(),

  constraint personal_stripe_commands_agreement_fkey
    foreign key (challenge_id, user_id)
    references app.personal_stripe_sandbox_agreements (
      challenge_id, user_id
    )
    on delete restrict,
  constraint personal_stripe_commands_amount check (
    amount_minor in (1000, 2000, 3000, 4000, 5000)
    and currency = 'USD'
  ),
  constraint personal_stripe_commands_fixed_provenance check (
    provider = 'stripe'
    and environment = 'sandbox'
    and not livemode
    and integration_api_version = '2026-02-25.clover'
  ),
  constraint personal_stripe_commands_ids check (
    stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'
    and stripe_payment_method_id ~ '^pm_[A-Za-z0-9]+$'
    and (
      stripe_payment_intent_id is null
      or stripe_payment_intent_id ~ '^pi_[A-Za-z0-9]+$'
    )
    and char_length(stripe_idempotency_key) between 1 and 255
  ),
  constraint personal_stripe_commands_status check (
    status in ('pending', 'succeeded', 'requires_action', 'failed')
  ),
  constraint personal_stripe_commands_attempts check (
    attempt_count between 0 and 3
    and (attempt_count = 0) = (first_attempted_at is null)
  ),
  constraint personal_stripe_commands_lease_shape check (
    (lease_owner is null) = (lease_expires_at is null)
    and (lease_owner is null or status = 'pending')
  ),
  constraint personal_stripe_commands_terminal_shape check (
    (
      status = 'pending'
      and succeeded_at is null
      and terminal_at is null
    )
    or (
      status = 'succeeded'
      and stripe_payment_intent_id is not null
      and succeeded_at is not null
      and terminal_at = succeeded_at
    )
    or (
      status = 'requires_action'
      and stripe_payment_intent_id is not null
      and succeeded_at is null
      and terminal_at is not null
    )
    or (
      status = 'failed'
      and succeeded_at is null
      and terminal_at is not null
    )
  ),
  constraint personal_stripe_commands_failure_code check (
    last_failure_code is null
    or (
      char_length(last_failure_code) between 1 and 80
      and last_failure_code ~ '^[a-z0-9][a-z0-9_]*$'
    )
  ),
  constraint personal_stripe_commands_times check (
    (
      first_attempted_at is null
      or pg_catalog.isfinite(first_attempted_at)
    )
    and pg_catalog.isfinite(next_attempt_at)
    and (
      lease_expires_at is null
      or pg_catalog.isfinite(lease_expires_at)
    )
    and (
      succeeded_at is null
      or pg_catalog.isfinite(succeeded_at)
    )
    and (
      terminal_at is null
      or pg_catalog.isfinite(terminal_at)
    )
    and pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(updated_at)
  )
);

create index personal_stripe_sandbox_charge_commands_due_idx
  on app.personal_stripe_sandbox_charge_commands (
    next_attempt_at, created_at, id
  )
  where status = 'pending';

create table app.personal_stripe_sandbox_webhook_receipts (
  stripe_event_id         text primary key,
  event_type              text not null,
  object_kind             text,
  object_id               text not null,
  charge_command_id       uuid
    references app.personal_stripe_sandbox_charge_commands (id)
      on delete restrict,
  payload_digest          bytea not null,
  event_api_version       text,
  normalized_status       text,
  provider_created_at     timestamptz not null,
  disposition             text not null,
  provider                text not null default 'stripe',
  environment             text not null default 'sandbox',
  livemode                boolean not null default false,
  integration_api_version text not null default '2026-02-25.clover',
  received_at             timestamptz not null default clock_timestamp(),
  processed_at            timestamptz not null default clock_timestamp(),

  constraint personal_stripe_webhooks_event_id check (
    char_length(stripe_event_id) between 5 and 255
    and stripe_event_id ~ '^evt_[A-Za-z0-9]+$'
  ),
  constraint personal_stripe_webhooks_event_type check (
    char_length(event_type) between 3 and 120
    and event_type ~ '^[a-z0-9_.]+$'
  ),
  constraint personal_stripe_webhooks_object check (
    (object_kind is null or object_kind in ('setup', 'payment'))
    and (charge_command_id is null or object_kind = 'payment')
    and char_length(object_id) between 3 and 255
    and object_id ~ '^[A-Za-z0-9_]+$'
  ),
  constraint personal_stripe_webhooks_digest check (
    octet_length(payload_digest) = 32
  ),
  constraint personal_stripe_webhooks_status check (
    normalized_status is null
    or normalized_status in (
      'pending_provider',
      'requires_action',
      'processing',
      'succeeded',
      'cancelled',
      'failed'
    )
  ),
  constraint personal_stripe_webhooks_disposition check (
    disposition in (
      'reconciled',
      'no_terminal_change',
      'ignored'
    )
  ),
  constraint personal_stripe_webhooks_versions check (
    (
      event_api_version is null
      or char_length(event_api_version) between 1 and 80
    )
    and provider = 'stripe'
    and environment = 'sandbox'
    and not livemode
    and integration_api_version = '2026-02-25.clover'
  ),
  constraint personal_stripe_webhooks_times check (
    pg_catalog.isfinite(provider_created_at)
    and pg_catalog.isfinite(received_at)
    and pg_catalog.isfinite(processed_at)
  )
);

comment on table app.personal_stripe_sandbox_customers is
  'Private one-owner Stripe test Customer mapping. Contains no customer PII.';
comment on table app.personal_stripe_sandbox_setups is
  'Exact-request SetupIntent state and explicit off-session sandbox consent. Client secrets are never stored.';
comment on table app.personal_stripe_sandbox_agreements is
  'Immutable binding between one succeeded sandbox setup and one frozen Personal V1 challenge.';
comment on table app.personal_stripe_sandbox_payment_reviews is
  'Provisional missed-result review gate. A miss is not chargeable while review_open or under_review.';
comment on table app.personal_stripe_sandbox_charge_commands is
  'Exactly-once logical sandbox charge jobs created only after a confirmed miss.';
comment on table app.personal_stripe_sandbox_webhook_receipts is
  'Idempotent normalized Stripe sandbox event receipts. Raw webhook bodies and secrets are not stored.';

-- ===========================================================================
-- Cross-table invariant triggers
-- ===========================================================================

create function app.validate_personal_stripe_sandbox_agreement()
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

create trigger personal_stripe_sandbox_agreements_validate
  before insert on app.personal_stripe_sandbox_agreements
  for each row execute function app.validate_personal_stripe_sandbox_agreement();

create function app.validate_personal_stripe_sandbox_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.personal_challenge_results;
begin
  select result.* into v_result
  from public.personal_challenge_results result
  where result.id = new.result_id;

  if v_result.id is null
     or v_result.challenge_id <> new.challenge_id
     or v_result.user_id <> new.user_id
     or v_result.outcome <> 'missed_goal'
     or v_result.reason <> 'target_missed'
     or v_result.evidence_state <> 'complete'
     or v_result.commitment_waived
     or new.opened_at <> v_result.published_at
     or new.review_deadline <> v_result.published_at + interval '7 days'
  then
    raise exception 'only an exact provisional Personal missed result may open payment review'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_stripe_sandbox_reviews_validate
  before insert on app.personal_stripe_sandbox_payment_reviews
  for each row execute function app.validate_personal_stripe_sandbox_review();

create function app.validate_personal_stripe_sandbox_charge_command()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review    app.personal_stripe_sandbox_payment_reviews;
  v_agreement app.personal_stripe_sandbox_agreements;
begin
  select review.* into v_review
  from app.personal_stripe_sandbox_payment_reviews review
  where review.id = new.review_id;

  select agreement.* into v_agreement
  from app.personal_stripe_sandbox_agreements agreement
  where agreement.challenge_id = new.challenge_id
    and agreement.user_id = new.user_id;

  if v_review.id is null
     or v_agreement.challenge_id is null
     or v_review.state <> 'confirmed_miss'
     or v_review.challenge_id <> new.challenge_id
     or v_review.result_id <> new.result_id
     or v_review.user_id <> new.user_id
     or v_agreement.commitment_amount_minor <> new.amount_minor
     or v_agreement.currency <> new.currency
     or v_agreement.stripe_customer_id <> new.stripe_customer_id
     or v_agreement.stripe_payment_method_id <> new.stripe_payment_method_id
     or new.stripe_idempotency_key
          <> 'gt:personal-charge:v1:' || new.result_id::text
     or new.next_attempt_at < v_review.review_deadline
  then
    raise exception 'charge command requires one confirmed miss and exact frozen agreement'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create trigger personal_stripe_sandbox_commands_validate
  before insert on app.personal_stripe_sandbox_charge_commands
  for each row execute function app.validate_personal_stripe_sandbox_charge_command();

create function app.open_personal_stripe_sandbox_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.outcome = 'missed_goal'
     and new.reason = 'target_missed'
     and new.evidence_state = 'complete'
     and not new.commitment_waived
  then
    insert into app.personal_stripe_sandbox_payment_reviews (
      challenge_id,
      result_id,
      user_id,
      opened_at,
      review_deadline
    )
    select
      new.challenge_id,
      new.id,
      new.user_id,
      new.published_at,
      new.published_at + interval '7 days'
    from app.personal_stripe_sandbox_agreements agreement
    where agreement.challenge_id = new.challenge_id
      and agreement.user_id = new.user_id
    on conflict (result_id) do nothing;
  end if;

  return new;
end;
$$;

create trigger personal_results_open_stripe_sandbox_review
  after insert on public.personal_challenge_results
  for each row execute function app.open_personal_stripe_sandbox_review();

-- ===========================================================================
-- SetupIntent request, provider refresh, and Edge-safe load boundaries
-- ===========================================================================

create function app.begin_personal_stripe_sandbox_setup_unchecked(
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
    expires_at
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
    v_now + interval '24 hours'
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

create function public.begin_personal_stripe_sandbox_setup_v1(
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

create function public.begin_personal_stripe_sandbox_setup_service_v1(
  p_owner_id                 uuid,
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
language sql
volatile
security definer
set search_path = ''
as $$
  select app.begin_personal_stripe_sandbox_setup_unchecked(
    p_owner_id,
    p_request_id,
    p_cadence,
    p_target_steps,
    p_commitment_amount_minor,
    p_currency,
    p_timezone,
    p_requested_starts_at,
    p_agreement_version,
    p_consent_version,
    true
  )
$$;

create function public.record_personal_stripe_sandbox_customer_v1(
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

create function app.record_personal_stripe_sandbox_setup_unchecked(
  p_owner_id                 uuid,
  p_setup_id                 uuid,
  p_stripe_customer_id       text,
  p_stripe_setup_intent_id   text,
  p_stripe_payment_method_id text,
  p_status                   text,
  p_livemode                 boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_setup app.personal_stripe_sandbox_setups;
  v_now   timestamptz := clock_timestamp();
begin
  if p_owner_id is null
     or p_setup_id is null
     or p_livemode is distinct from false
     or p_stripe_customer_id is null
     or p_stripe_customer_id !~ '^cus_[A-Za-z0-9]+$'
     or p_stripe_setup_intent_id is null
     or p_stripe_setup_intent_id !~ '^seti_[A-Za-z0-9]+$'
     or p_status is null
     or p_status not in (
       'pending_provider',
       'requires_action',
       'processing',
       'succeeded',
       'cancelled'
     )
     or (
       p_status = 'succeeded'
       and (
         p_stripe_payment_method_id is null
         or p_stripe_payment_method_id !~ '^pm_[A-Za-z0-9]+$'
       )
     )
     or (
       p_status <> 'succeeded'
       and p_stripe_payment_method_id is not null
     )
  then
    raise exception 'valid normalized Stripe sandbox SetupIntent state is required'
      using errcode = 'invalid_parameter_value';
  end if;

  select setup.* into v_setup
  from app.personal_stripe_sandbox_setups setup
  where setup.id = p_setup_id
    and setup.user_id = p_owner_id
  for update;

  if v_setup.id is null then
    raise exception 'Stripe sandbox setup not found for verified owner'
      using errcode = 'invalid_parameter_value';
  end if;

  if not exists (
    select 1
    from app.personal_stripe_sandbox_customers customer
    where customer.user_id = p_owner_id
      and customer.stripe_customer_id = p_stripe_customer_id
  ) then
    raise exception 'Stripe sandbox Customer must be recorded first'
      using errcode = 'restrict_violation';
  end if;

  if v_setup.stripe_customer_id is not null
     and v_setup.stripe_customer_id <> p_stripe_customer_id
  then
    raise exception 'setup Customer binding is immutable'
      using errcode = 'restrict_violation';
  end if;

  if v_setup.stripe_setup_intent_id is not null
     and v_setup.stripe_setup_intent_id <> p_stripe_setup_intent_id
  then
    raise exception 'setup SetupIntent binding is immutable'
      using errcode = 'restrict_violation';
  end if;

  if v_setup.status in ('succeeded', 'cancelled') then
    if v_setup.status <> p_status
       or (
         v_setup.status = 'succeeded'
         and v_setup.stripe_payment_method_id
               <> p_stripe_payment_method_id
       )
    then
      raise exception 'terminal SetupIntent state cannot regress or change identity'
        using errcode = 'restrict_violation';
    end if;

    return pg_catalog.jsonb_build_object(
      'setup_id', v_setup.id,
      'stripe_customer_id', v_setup.stripe_customer_id,
      'stripe_setup_intent_id', v_setup.stripe_setup_intent_id,
      'status', v_setup.status,
      'replayed', true
    );
  end if;

  update app.personal_stripe_sandbox_setups setup
  set
    stripe_customer_id = p_stripe_customer_id,
    stripe_setup_intent_id = p_stripe_setup_intent_id,
    stripe_payment_method_id = case
      when p_status = 'succeeded' then p_stripe_payment_method_id
      else null
    end,
    status = p_status,
    succeeded_at = case
      when p_status = 'succeeded' then v_now
      else null
    end,
    updated_at = v_now
  where setup.id = p_setup_id;

  return pg_catalog.jsonb_build_object(
    'setup_id', p_setup_id,
    'stripe_customer_id', p_stripe_customer_id,
    'stripe_setup_intent_id', p_stripe_setup_intent_id,
    'status', p_status,
    'replayed', false
  );
end;
$$;

create function public.record_personal_stripe_sandbox_setup_v1(
  p_owner_id                 uuid,
  p_setup_id                 uuid,
  p_stripe_customer_id       text,
  p_stripe_setup_intent_id   text,
  p_stripe_payment_method_id text,
  p_status                   text,
  p_livemode                 boolean default false
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select app.record_personal_stripe_sandbox_setup_unchecked(
    p_owner_id,
    p_setup_id,
    p_stripe_customer_id,
    p_stripe_setup_intent_id,
    p_stripe_payment_method_id,
    p_status,
    p_livemode
  )
$$;

create function public.load_personal_stripe_sandbox_setup_service_v1(
  p_owner_id                 uuid,
  p_setup_id                 uuid,
  p_request_id               uuid,
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
  v_setup app.personal_stripe_sandbox_setups;
begin
  if p_owner_id is null
     or p_setup_id is null
     or p_request_id is null
     or p_cadence is null
     or p_target_steps is null
     or p_commitment_amount_minor is null
     or p_currency is null
     or p_timezone is null
     or p_agreement_version is null
     or p_consent_version is null
  then
    raise exception 'verified owner, setup, and normalized terms are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_active_actors(array[p_owner_id]);

  select setup.* into v_setup
  from app.personal_stripe_sandbox_setups setup
  where setup.id = p_setup_id
    and setup.user_id = p_owner_id;

  if v_setup.id is null then
    raise exception 'Stripe sandbox setup not found for verified owner'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_setup.request_id <> p_request_id
     or v_setup.cadence <> p_cadence
     or v_setup.target_steps <> p_target_steps
     or v_setup.commitment_amount_minor <> p_commitment_amount_minor
     or v_setup.currency <> p_currency
     or v_setup.timezone <> p_timezone
     or v_setup.requested_starts_at is distinct from p_requested_starts_at
     or v_setup.agreement_version <> p_agreement_version
     or v_setup.consent_version <> p_consent_version
  then
    raise exception 'commit terms do not match the consented Stripe setup'
      using errcode = 'invalid_parameter_value';
  end if;

  return pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'setup_id', v_setup.id,
      'owner_id', v_setup.user_id,
      'stripe_customer_id', v_setup.stripe_customer_id,
      'stripe_setup_intent_id', v_setup.stripe_setup_intent_id,
      'stripe_payment_method_id', v_setup.stripe_payment_method_id,
      'status', v_setup.status,
      'cadence', v_setup.cadence,
      'target_steps', v_setup.target_steps,
      'commitment_amount_minor', v_setup.commitment_amount_minor,
      'currency', v_setup.currency,
      'timezone', v_setup.timezone,
      'requested_starts_at', v_setup.requested_starts_at,
      'agreement_version', v_setup.agreement_version,
      'consent_version', v_setup.consent_version,
      'terms_digest_hex', encode(v_setup.payload_hash, 'hex'),
      'expires_at', v_setup.expires_at,
      'consumed', v_setup.consumed_at is not null,
      'consumed_challenge_id', v_setup.consumed_challenge_id,
      'provider', v_setup.provider,
      'environment', v_setup.environment,
      'livemode', v_setup.livemode,
      'integration_api_version', v_setup.integration_api_version
    )
  );
end;
$$;

-- ===========================================================================
-- Atomic v2 challenge commit
-- ===========================================================================

create function app.commit_personal_stripe_sandbox_challenge_unchecked(
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

  perform app.lock_active_actors(array[p_owner_id]);
  v_now := clock_timestamp();

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

    return pg_catalog.jsonb_build_object(
      'challenge_id', v_existing.challenge_id,
      'payment_state', 'method_saved',
      'replayed', true
    );
  end if;

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
  then
    raise exception 'an unexpired, succeeded, unused Stripe sandbox setup is required'
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
    stripe_payment_method_id
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
    v_setup.stripe_payment_method_id
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

create function public.create_personal_challenge_with_stripe_sandbox_v2(
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

create function public.commit_personal_stripe_sandbox_challenge_service_v1(
  p_owner_id                 uuid,
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
language sql
volatile
security definer
set search_path = ''
as $$
  select app.commit_personal_stripe_sandbox_challenge_unchecked(
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

-- ===========================================================================
-- Review settlement and exactly-once charge work
-- ===========================================================================

create function public.request_personal_stripe_sandbox_review_service_v1(
  p_owner_id      uuid,
  p_challenge_id  uuid,
  p_reason_code   text,
  p_reference     text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_review app.personal_stripe_sandbox_payment_reviews;
  v_now    timestamptz := clock_timestamp();
begin
  if p_owner_id is null
     or p_challenge_id is null
     or p_reason_code is null
     or char_length(p_reason_code) not between 1 and 80
     or p_reason_code !~ '^[a-z0-9][a-z0-9_]*$'
     or (
       p_reference is not null
       and char_length(p_reference) not between 1 and 160
     )
  then
    raise exception 'verified owner, challenge, and normalized review reason are required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_active_actors(array[p_owner_id]);

  select review.* into v_review
  from app.personal_stripe_sandbox_payment_reviews review
  where review.challenge_id = p_challenge_id
    and review.user_id = p_owner_id
  for update;

  if v_review.id is null then
    raise exception 'payment review is unavailable for verified owner'
      using errcode = 'insufficient_privilege';
  end if;

  if v_review.state = 'under_review' then
    if v_review.review_reason_code <> p_reason_code
       or v_review.review_reference is distinct from p_reference
    then
      raise exception 'payment review was already requested with different fields'
        using errcode = 'invalid_parameter_value';
    end if;

    return pg_catalog.jsonb_build_object(
      'review_state', v_review.state,
      'review_deadline', v_review.review_deadline,
      'replayed', true
    );
  end if;

  if v_review.state <> 'review_open'
     or v_now < v_review.opened_at
     or v_now >= v_review.review_deadline
  then
    raise exception 'payment review request window is closed'
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

  return pg_catalog.jsonb_build_object(
    'review_state', 'under_review',
    'review_deadline', v_review.review_deadline,
    'replayed', false
  );
end;
$$;

create function public.settle_personal_stripe_sandbox_review_v1(
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
  v_review    app.personal_stripe_sandbox_payment_reviews;
  v_result    public.personal_challenge_results;
  v_agreement app.personal_stripe_sandbox_agreements;
  v_contest   public.contests;
  v_now       timestamptz := clock_timestamp();
  v_command_id uuid;
  v_target_state text;
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

create function public.claim_personal_stripe_sandbox_charges_v1(
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
  v_claims jsonb;
  v_now    timestamptz := clock_timestamp();
begin
  if p_lease_owner is null or p_limit not between 1 and 100 then
    raise exception 'lease owner and a limit from 1 through 100 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- An unresolved filed review automatically waives at its absolute deadline.
  -- No command exists for these rows, so this update can never race a charge.
  update app.personal_stripe_sandbox_payment_reviews review
  set
    state = 'waived',
    decision_reason_code = 'review_unresolved_at_deadline',
    decision_reference = review.review_reference,
    decided_at = v_now,
    updated_at = v_now
  where review.state = 'under_review'
    and review.review_deadline <= v_now;

  -- Silence is not an indefinite hold: an unreviewed provisional miss becomes
  -- confirmed only at the absolute deadline, never before it.
  update app.personal_stripe_sandbox_payment_reviews review
  set
    state = 'confirmed_miss',
    decision_reason_code = 'review_window_expired',
    decision_reference = null,
    decided_at = v_now,
    updated_at = v_now
  where review.state = 'review_open'
    and review.review_deadline <= v_now;

  -- Discover both deadline confirmations above and completed upheld reviews.
  -- The command's own due time is never earlier than review_deadline.
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
  on conflict (review_id) do nothing;

  with due as (
    select command.id
    from app.personal_stripe_sandbox_charge_commands command
    join app.personal_stripe_sandbox_payment_reviews review
      on review.id = command.review_id
     and review.state = 'confirmed_miss'
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

create function public.record_personal_stripe_sandbox_charge_v1(
  p_command_id              uuid,
  p_lease_owner             uuid,
  p_status                  text,
  p_stripe_payment_intent_id text,
  p_failure_code            text,
  p_livemode                boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command app.personal_stripe_sandbox_charge_commands;
  v_now     timestamptz := clock_timestamp();
  v_status  text;
begin
  if p_command_id is null
     or p_lease_owner is null
     or p_livemode is distinct from false
     or p_status is null
     or p_status not in (
       'processing',
       'succeeded',
       'requires_action',
       'failed',
       'worker_failed',
       'transport_ambiguous'
     )
     or (
       p_status not in ('transport_ambiguous', 'worker_failed')
       and (
         p_stripe_payment_intent_id is null
         or p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
       )
     )
     or (
       p_stripe_payment_intent_id is not null
       and p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
     )
     or (
       p_status in ('succeeded', 'processing')
       and p_failure_code is not null
     )
     or (
       p_status in ('requires_action', 'failed', 'worker_failed')
       and (
         p_failure_code is null
         or char_length(p_failure_code) not between 1 and 80
         or p_failure_code !~ '^[a-z0-9][a-z0-9_]*$'
       )
     )
  then
    raise exception 'valid normalized Stripe sandbox charge result is required'
      using errcode = 'invalid_parameter_value';
  end if;

  select command.* into v_command
  from app.personal_stripe_sandbox_charge_commands command
  where command.id = p_command_id
  for update;

  if v_command.id is null then
    raise exception 'Stripe sandbox charge command not found'
      using errcode = 'invalid_parameter_value';
  end if;

  v_status := case
    when p_status = 'processing' then 'pending'
    when p_status = 'transport_ambiguous'
     and v_command.attempt_count < 3 then 'pending'
    when p_status = 'transport_ambiguous' then 'failed'
    when p_status = 'worker_failed' then 'failed'
    else p_status
  end;

  if v_command.status <> 'pending' then
    if v_command.status <> v_status
       or v_command.stripe_payment_intent_id
            is distinct from p_stripe_payment_intent_id
       or v_command.last_failure_code is distinct from p_failure_code
    then
      raise exception 'terminal Stripe sandbox charge result cannot change'
        using errcode = 'restrict_violation';
    end if;

    return pg_catalog.jsonb_build_object(
      'command_id', v_command.id,
      'status', v_command.status,
      'replayed', true
    );
  end if;

  if v_command.lease_owner is distinct from p_lease_owner
     or v_command.lease_expires_at is null
     or v_command.lease_expires_at <= v_now
     or (
       v_command.stripe_payment_intent_id is not null
       and v_command.stripe_payment_intent_id
             <> p_stripe_payment_intent_id
     )
  then
    raise exception 'Stripe sandbox charge lease is unavailable or PaymentIntent changed'
      using errcode = 'restrict_violation';
  end if;

  update app.personal_stripe_sandbox_charge_commands command
  set
    stripe_payment_intent_id = coalesce(
      command.stripe_payment_intent_id,
      p_stripe_payment_intent_id
    ),
    status = v_status,
    next_attempt_at = case
      when v_status = 'pending'
      then v_now
        + interval '15 seconds'
          * power(2::numeric, greatest(command.attempt_count - 1, 0))
      else command.next_attempt_at
    end,
    lease_owner = null,
    lease_expires_at = null,
    last_failure_code = case
      when p_status = 'transport_ambiguous' and v_status = 'failed'
      then 'transport_retry_exhausted'
      when p_status = 'transport_ambiguous'
      then coalesce(p_failure_code, 'transport_ambiguous')
      else p_failure_code
    end,
    succeeded_at = case
      when v_status = 'succeeded' then v_now
      else null
    end,
    terminal_at = case
      when v_status = 'pending' then null
      else v_now
    end,
    updated_at = v_now
  where command.id = p_command_id;

  return pg_catalog.jsonb_build_object(
    'command_id', p_command_id,
    'status', v_status,
    'replayed', false
  );
end;
$$;

-- ===========================================================================
-- Normalized webhook reconciliation and owner-safe status
-- ===========================================================================

create function public.apply_personal_stripe_sandbox_webhook_v1(
  p_stripe_event_id         text,
  p_payload_digest          bytea,
  p_event_type              text,
  p_object_id               text,
  p_api_version             text,
  p_provider_created_at     timestamptz,
  p_disposition             text,
  p_object_kind             text,
  p_status                  text,
  p_livemode                boolean,
  p_stripe_customer_id      text,
  p_stripe_payment_method_id text,
  p_amount_minor            integer,
  p_currency                text,
  p_failure_code            text,
  p_command_id              uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing    app.personal_stripe_sandbox_webhook_receipts;
  v_setup       app.personal_stripe_sandbox_setups;
  v_command     app.personal_stripe_sandbox_charge_commands;
  v_disposition text := 'ignored';
  v_now         timestamptz := clock_timestamp();
  v_target      text;
begin
  if p_livemode is distinct from false
     or p_stripe_event_id is null
     or p_stripe_event_id !~ '^evt_[A-Za-z0-9]+$'
     or p_event_type is null
     or char_length(p_event_type) not between 3 and 120
     or p_event_type !~ '^[a-z0-9_.]+$'
     or p_object_id is null
     or char_length(p_object_id) not between 3 and 255
     or p_object_id !~ '^[A-Za-z0-9_]+$'
     or p_payload_digest is null
     or octet_length(p_payload_digest) <> 32
     or (
       p_api_version is not null
       and char_length(p_api_version) not between 1 and 80
     )
     or p_provider_created_at is null
     or not pg_catalog.isfinite(p_provider_created_at)
     or p_disposition not in ('applied', 'ignored')
     or (
       p_failure_code is not null
       and (
         char_length(p_failure_code) not between 1 and 80
         or p_failure_code !~ '^[a-z0-9][a-z0-9_]*$'
      )
     )
     or (
       p_disposition = 'ignored'
       and (
         p_object_kind is not null
         or p_status is not null
         or p_stripe_customer_id is not null
         or p_stripe_payment_method_id is not null
         or p_amount_minor is not null
         or p_currency is not null
         or p_failure_code is not null
         or p_command_id is not null
       )
     )
     or (
       p_disposition = 'applied'
       and (
         p_object_kind not in ('setup', 'payment')
         or p_status is null
         or p_stripe_customer_id is null
         or p_stripe_customer_id !~ '^cus_[A-Za-z0-9]+$'
       )
     )
  then
    raise exception 'verified normalized Stripe sandbox webhook fields are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select receipt.* into v_existing
  from app.personal_stripe_sandbox_webhook_receipts receipt
  where receipt.stripe_event_id = p_stripe_event_id;

  if v_existing.stripe_event_id is not null then
    if v_existing.payload_digest <> p_payload_digest
       or v_existing.event_type <> p_event_type
       or v_existing.object_kind is distinct from p_object_kind
       or v_existing.object_id <> p_object_id
       or v_existing.event_api_version is distinct from p_api_version
       or (
         p_command_id is not null
         and v_existing.charge_command_id is distinct from p_command_id
       )
    then
      raise exception 'Stripe event ID already received with different normalized facts'
        using errcode = 'unique_violation';
    end if;

    return pg_catalog.jsonb_build_object(
      'stripe_event_id', p_stripe_event_id,
      'disposition', v_existing.disposition,
      'replayed', true
    );
  end if;

  if p_disposition = 'ignored' then
    v_disposition := 'ignored';
  elsif p_object_kind = 'setup' then
    if p_status not in (
      'pending_provider',
      'requires_action',
      'processing',
      'succeeded',
      'cancelled'
    )
       or p_object_id !~ '^seti_[A-Za-z0-9]+$'
       or p_command_id is not null
       or (
         p_status = 'succeeded'
         and (
           p_stripe_payment_method_id is null
           or p_stripe_payment_method_id !~ '^pm_[A-Za-z0-9]+$'
         )
       )
    then
      raise exception 'invalid normalized SetupIntent webhook snapshot'
        using errcode = 'invalid_parameter_value';
    end if;

    select setup.* into v_setup
    from app.personal_stripe_sandbox_setups setup
    where setup.stripe_setup_intent_id = p_object_id
    for update;

    if v_setup.id is not null then
      perform app.record_personal_stripe_sandbox_setup_unchecked(
        v_setup.user_id,
        v_setup.id,
        coalesce(p_stripe_customer_id, v_setup.stripe_customer_id),
        p_object_id,
        case
          when p_status = 'succeeded'
          then coalesce(
            p_stripe_payment_method_id,
            v_setup.stripe_payment_method_id
          )
          else null
        end,
        p_status,
        false
      );
      v_disposition := 'reconciled';
    end if;
  else
    if p_status not in (
      'processing', 'succeeded', 'requires_action', 'failed'
    )
       or p_object_id !~ '^pi_[A-Za-z0-9]+$'
       or p_amount_minor is null
       or p_currency is null
    then
      raise exception 'invalid normalized PaymentIntent webhook snapshot'
        using errcode = 'invalid_parameter_value';
    end if;

    select command.* into v_command
    from app.personal_stripe_sandbox_charge_commands command
    where command.stripe_payment_intent_id = p_object_id
    for update;

    if v_command.id is not null
       and p_command_id is not null
       and v_command.id <> p_command_id
    then
      raise exception 'PaymentIntent metadata command does not match its existing binding'
        using errcode = 'restrict_violation';
    end if;

    if v_command.id is null and p_command_id is not null then
      select command.* into v_command
      from app.personal_stripe_sandbox_charge_commands command
      where command.id = p_command_id
      for update;

      if v_command.id is not null then
        if v_command.status <> 'pending'
           or v_command.stripe_payment_intent_id is not null
           or v_command.first_attempted_at is null
           or v_command.amount_minor <> p_amount_minor
           or v_command.currency <> p_currency
           or v_command.stripe_customer_id <> p_stripe_customer_id
           or p_stripe_payment_method_id is null
           or v_command.stripe_payment_method_id
                <> p_stripe_payment_method_id
        then
          raise exception 'PaymentIntent metadata cannot bind to this charge command'
            using errcode = 'restrict_violation';
        end if;

        update app.personal_stripe_sandbox_charge_commands command
        set
          stripe_payment_intent_id = p_object_id,
          updated_at = v_now
        where command.id = v_command.id;

        v_command.stripe_payment_intent_id := p_object_id;
      end if;
    end if;

    if v_command.id is not null then
      if v_command.amount_minor <> p_amount_minor
         or v_command.currency <> p_currency
         or v_command.stripe_customer_id <> p_stripe_customer_id
         or (
           p_stripe_payment_method_id is not null
           and v_command.stripe_payment_method_id
                 <> p_stripe_payment_method_id
         )
      then
        raise exception 'PaymentIntent snapshot does not match the frozen charge command'
          using errcode = 'restrict_violation';
      end if;

      v_target := case
        when p_status = 'succeeded' then 'succeeded'
        when p_status = 'requires_action' then 'requires_action'
        when p_status = 'failed' then 'failed'
        else 'pending'
      end;

      if v_target = 'pending' then
        v_disposition := 'no_terminal_change';
      elsif v_command.status = 'succeeded'
         or v_command.status = 'failed'
         or (
           v_command.status = 'requires_action'
           and v_target <> 'succeeded'
         )
      then
        v_disposition := 'no_terminal_change';
      else
        update app.personal_stripe_sandbox_charge_commands command
        set
          status = v_target,
          lease_owner = null,
          lease_expires_at = null,
          last_failure_code = case
            when v_target = 'succeeded' then null
            when v_target = 'requires_action'
            then coalesce(p_failure_code, 'provider_requires_action')
            else coalesce(p_failure_code, 'provider_failed')
          end,
          succeeded_at = case
            when v_target = 'succeeded' then v_now
            else null
          end,
          terminal_at = v_now,
          updated_at = v_now
        where command.id = v_command.id;

        v_disposition := 'reconciled';
      end if;
    end if;
  end if;

  insert into app.personal_stripe_sandbox_webhook_receipts (
    stripe_event_id,
    event_type,
    object_kind,
    object_id,
    charge_command_id,
    payload_digest,
    event_api_version,
    normalized_status,
    provider_created_at,
    disposition,
    received_at,
    processed_at
  )
  values (
    p_stripe_event_id,
    p_event_type,
    p_object_kind,
    p_object_id,
    case when p_object_kind = 'payment' then v_command.id else null end,
    p_payload_digest,
    p_api_version,
    p_status,
    p_provider_created_at,
    v_disposition,
    v_now,
    v_now
  );

  return pg_catalog.jsonb_build_object(
    'stripe_event_id', p_stripe_event_id,
    'disposition', v_disposition,
    'replayed', false
  );
end;
$$;

create function public.get_my_personal_stripe_sandbox_status_v1(
  p_challenge_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_status   jsonb;
begin
  v_owner_id := app.require_active_caller();

  select pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'challenge_id', agreement.challenge_id,
      'setup_id', agreement.setup_id,
      'environment', agreement.environment,
      'payment_state', case
        when contest.status = 'cancelled' then 'no_charge'
        when command.status = 'succeeded' then 'charged'
        when command.status = 'requires_action' then 'requires_action'
        when command.status = 'failed' then 'collection_failed'
        when command.id is not null then 'charge_pending'
        when review.state = 'confirmed_miss' then 'charge_pending'
        when review.state = 'waived' then 'waived'
        when review.state is not null then review.state
        when result.id is not null then 'no_charge'
        else 'method_saved'
      end,
      'setup_status', setup.status,
      'result_outcome', result.outcome,
      'review_state', review.state,
      'review_deadline', review.review_deadline,
      'charge_status', command.status
    )
  )
  into v_status
  from app.personal_stripe_sandbox_agreements agreement
  join app.personal_stripe_sandbox_setups setup
    on setup.id = agreement.setup_id
  join public.contests contest
    on contest.id = agreement.challenge_id
  left join public.personal_challenge_results result
    on result.challenge_id = agreement.challenge_id
  left join app.personal_stripe_sandbox_payment_reviews review
    on review.challenge_id = agreement.challenge_id
  left join app.personal_stripe_sandbox_charge_commands command
    on command.challenge_id = agreement.challenge_id
  where agreement.challenge_id = p_challenge_id
    and agreement.user_id = v_owner_id;

  if v_status is null then
    raise exception 'Stripe sandbox challenge not found for active owner'
      using errcode = 'invalid_parameter_value';
  end if;

  return v_status;
end;
$$;

-- ===========================================================================
-- RLS, no direct policies, and explicit function grants
-- ===========================================================================

alter table app.personal_stripe_sandbox_customers enable row level security;
alter table app.personal_stripe_sandbox_setups enable row level security;
alter table app.personal_stripe_sandbox_agreements enable row level security;
alter table app.personal_stripe_sandbox_payment_reviews
  enable row level security;
alter table app.personal_stripe_sandbox_charge_commands
  enable row level security;
alter table app.personal_stripe_sandbox_webhook_receipts
  enable row level security;

revoke all on table app.personal_stripe_sandbox_customers,
                    app.personal_stripe_sandbox_setups,
                    app.personal_stripe_sandbox_agreements,
                    app.personal_stripe_sandbox_payment_reviews,
                    app.personal_stripe_sandbox_charge_commands,
                    app.personal_stripe_sandbox_webhook_receipts
  from public, anon, authenticated, service_role;

revoke all on function app.validate_personal_stripe_sandbox_agreement(),
                       app.validate_personal_stripe_sandbox_review(),
                       app.validate_personal_stripe_sandbox_charge_command(),
                       app.open_personal_stripe_sandbox_review(),
                       app.begin_personal_stripe_sandbox_setup_unchecked(
                         uuid,
                         uuid,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         text,
                         timestamptz,
                         text,
                         text,
                         boolean
                       ),
                       app.record_personal_stripe_sandbox_setup_unchecked(
                         uuid,
                         uuid,
                         text,
                         text,
                         text,
                         text,
                         boolean
                       ),
                       app.commit_personal_stripe_sandbox_challenge_unchecked(
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
                       )
  from public, anon, authenticated, service_role;

revoke all on function public.begin_personal_stripe_sandbox_setup_v1(
                         uuid,
                         public.contest_cadence,
                         integer,
                         integer,
                         text,
                         text,
                         timestamptz,
                         text,
                         text
                       ),
                       public.begin_personal_stripe_sandbox_setup_service_v1(
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
                       ),
                       public.record_personal_stripe_sandbox_customer_v1(
                         uuid, text, boolean
                       ),
                       public.record_personal_stripe_sandbox_setup_v1(
                         uuid, uuid, text, text, text, text, boolean
                       ),
                       public.load_personal_stripe_sandbox_setup_service_v1(
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
                       ),
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
                       ),
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
                       ),
                       public.request_personal_stripe_sandbox_review_service_v1(
                         uuid, uuid, text, text
                       ),
                       public.settle_personal_stripe_sandbox_review_v1(
                         uuid, text, text, text
                       ),
                       public.claim_personal_stripe_sandbox_charges_v1(
                         uuid, integer
                       ),
                       public.record_personal_stripe_sandbox_charge_v1(
                         uuid, uuid, text, text, text, boolean
                       ),
                       public.apply_personal_stripe_sandbox_webhook_v1(
                         text,
                         bytea,
                         text,
                         text,
                         text,
                         timestamptz,
                         text,
                         text,
                         text,
                         boolean,
                         text,
                         text,
                         integer,
                         text,
                         text,
                         uuid
                       ),
                       public.get_my_personal_stripe_sandbox_status_v1(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.begin_personal_stripe_sandbox_setup_v1(
                            uuid,
                            public.contest_cadence,
                            integer,
                            integer,
                            text,
                            text,
                            timestamptz,
                            text,
                            text
                          ),
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
                          ),
                          public.get_my_personal_stripe_sandbox_status_v1(uuid)
  to authenticated;

grant execute on function
  public.begin_personal_stripe_sandbox_setup_service_v1(
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
  ),
  public.record_personal_stripe_sandbox_customer_v1(uuid, text, boolean),
  public.record_personal_stripe_sandbox_setup_v1(
    uuid, uuid, text, text, text, text, boolean
  ),
  public.load_personal_stripe_sandbox_setup_service_v1(
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
  ),
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
  ),
  public.request_personal_stripe_sandbox_review_service_v1(
    uuid, uuid, text, text
  ),
  public.settle_personal_stripe_sandbox_review_v1(uuid, text, text, text),
  public.claim_personal_stripe_sandbox_charges_v1(uuid, integer),
  public.record_personal_stripe_sandbox_charge_v1(
    uuid, uuid, text, text, text, boolean
  ),
  public.apply_personal_stripe_sandbox_webhook_v1(
    text,
    bytea,
    text,
    text,
    text,
    timestamptz,
    text,
    text,
    text,
    boolean,
    text,
    text,
    integer,
    text,
    text,
    uuid
  )
  to service_role;

comment on function public.begin_personal_stripe_sandbox_setup_v1(
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
  'Authenticated exact-request setup consent. Returns no Stripe identifiers or client secret.';
comment on function public.commit_personal_stripe_sandbox_challenge_service_v1(
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
  'Service-only Edge commit with an explicit JWT-verified owner. Atomically preserves V1 creation and binds one succeeded sandbox setup.';
comment on function public.apply_personal_stripe_sandbox_webhook_v1(
  text,
  bytea,
  text,
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  boolean,
  text,
  text,
  integer,
  text,
  text,
  uuid
) is
  'Service-only normalized Stripe test webhook reconciliation. Signature verification and canonical object retrieval occur in Edge; raw bodies are never accepted.';
