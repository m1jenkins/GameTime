-- Personal Accountability: start now and count today's trusted Health data.
--
-- A client expresses start-now with a minute-aligned instant on the owner's
-- current frozen-timezone date. The instant is request identity; the scored
-- window is canonically opened at that date's local midnight. This makes all
-- eligible steps from today count while keeping the seven scored local dates
-- aligned with the hourly coverage ledger.

create or replace function app.assert_contest_window_is_future()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_start_now_timezone text := pg_catalog.current_setting(
    'app.personal_start_now_timezone',
    true
  );
  v_clock timestamptz := clock_timestamp();
begin
  if new.starts_at < v_clock
     and not (
       new.challenge_model = 'personal_accountability'
       and v_start_now_timezone is not null
       and v_start_now_timezone <> ''
       and exists (
         select 1
         from pg_catalog.pg_timezone_names zone
         where zone.name = v_start_now_timezone
       )
       and new.starts_at = (
         (v_clock at time zone v_start_now_timezone)::date::timestamp
           at time zone v_start_now_timezone
       )
     )
  then
    raise exception 'a contest window cannot open in the past (starts_at %, now %)',
      new.starts_at, v_clock
      using errcode = 'invalid_parameter_value';
  end if;
  return new;
end;
$$;

comment on function app.assert_contest_window_is_future() is
  'BEFORE INSERT on contests. Refuses backdated windows except the creation RPC''s transaction-scoped Personal start-now marker for the current local midnight.';

create or replace function public.create_personal_challenge_v1(
  request_id                uuid,
  cadence                   public.contest_cadence,
  target_steps              integer,
  commitment_amount_minor   integer,
  timezone                  text,
  requested_starts_at       timestamptz default null
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
  v_requested_starts_at      timestamptz := $6;
  v_actor_id                 uuid;
  v_payload_hash             bytea;
  v_existing                 app.personal_challenge_creation_requests;
  v_challenge_id             uuid;
  v_now                      timestamptz;
  v_local_now                timestamp;
  v_local_start              timestamp;
  v_start_date               date;
  v_starts_at                timestamptz;
  v_ends_at                  timestamptz;
  v_starts_now               boolean := false;
  v_previous_start_timezone  text;
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

  v_local_now := v_now at time zone v_timezone;

  if v_requested_starts_at is not null then
    if not pg_catalog.isfinite(v_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := v_requested_starts_at at time zone v_timezone;
    v_starts_now :=
      v_local_start::date = v_local_now::date
      and v_requested_starts_at <= v_now
      and extract(second from v_local_start) = 0;

    if not v_starts_now then
      if extract(minute from v_local_start) <> 0
         or extract(second from v_local_start) <> 0
      then
        raise exception
          'a chosen start must be start-now on the current local date or a whole local hour'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_requested_starts_at <= v_now then
        raise exception 'a chosen start must be in the future'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_requested_starts_at > v_now + interval '90 days' then
        raise exception 'a chosen start must be within 90 days'
          using errcode = 'invalid_parameter_value';
      end if;
    end if;
  end if;

  v_payload_hash := extensions.digest(
    pg_catalog.convert_to(
      (
        pg_catalog.jsonb_build_object(
          'kind', 'personal_accountability_v1',
          'cadence', v_cadence::text,
          'target_steps', v_target_steps,
          'commitment_amount_minor', v_commitment_amount_minor,
          'currency', 'USD',
          'settlement_mode', 'test_only',
          'terms_version', 'personal-v1',
          'timezone', v_timezone
        )
        || case
             when v_requested_starts_at is null then '{}'::jsonb
             else pg_catalog.jsonb_build_object(
               'requested_starts_at',
               extract(epoch from v_requested_starts_at)::bigint
             )
           end
      )::text,
      'UTF8'
    ),
    'sha256'
  );

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

  if v_requested_starts_at is null then
    v_start_date := v_local_now::date + 1;
    v_starts_at := v_start_date::timestamp at time zone v_timezone;
  elsif v_starts_now then
    v_start_date := v_local_now::date;
    v_starts_at := v_start_date::timestamp at time zone v_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := v_requested_starts_at;
  end if;

  v_ends_at := (v_start_date + 7)::timestamp at time zone v_timezone;

  if v_starts_now then
    v_previous_start_timezone := pg_catalog.current_setting(
      'app.personal_start_now_timezone',
      true
    );
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      v_timezone,
      true
    );
  end if;

  insert into public.contests (
    title, group_id, created_by, challenge_model, metric, cadence,
    target_value, stake_amount_cents, tie_break, starts_at, ends_at,
    max_participants
  )
  values (
    '7-Day Personal Accountability', null, v_actor_id,
    'personal_accountability', 'steps', v_cadence, v_target_steps,
    v_commitment_amount_minor, 'void', v_starts_at, v_ends_at, 1
  )
  returning id into v_challenge_id;

  if v_starts_now then
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      coalesce(v_previous_start_timezone, ''),
      true
    );
  end if;

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  )
  values (v_challenge_id, v_actor_id, 'accepted', v_timezone, null);

  insert into public.personal_challenge_terms (
    challenge_id, user_id, cadence, target_steps,
    commitment_amount_minor, currency, settlement_mode, terms_version,
    timezone, agreed_at, evidence_cutoff
  )
  values (
    v_challenge_id, v_actor_id, v_cadence, v_target_steps,
    v_commitment_amount_minor, 'USD', 'test_only', 'personal-v1',
    v_timezone, v_now, v_ends_at + interval '24 hours'
  );

  insert into app.personal_challenge_creation_requests (
    actor_id, request_id, payload_hash, challenge_id
  )
  values (v_actor_id, v_request_id, v_payload_hash, v_challenge_id);

  if v_starts_now then
    update public.contests contest
    set status = 'active', activated_at = v_now
    where contest.id = v_challenge_id;
  end if;

  return v_challenge_id;
end;
$$;

comment on function public.create_personal_challenge_v1(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) is
  'Atomic exact-retry Personal V1 creation. Omitted starts open next local midnight; a minute-aligned instant earlier today means start now and counts from local midnight; future starts remain whole local hours within 90 days.';

-- Stripe consent stores the exact client marker. Accept the same current-date
-- start-now marker during setup; commit still has to happen on that local date.
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
  v_now           timestamptz;
  v_local_now     timestamp;
  v_local_start   timestamp;
  v_starts_now    boolean := false;
  v_payload_hash  bytea;
  v_existing      app.personal_stripe_sandbox_setups;
  v_setup_id      uuid;
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
       select 1 from pg_catalog.pg_timezone_names zone
       where zone.name = p_timezone
     )
  then
    raise exception 'valid request, Personal terms, timezone, and consent version are required'
      using errcode = 'invalid_parameter_value';
  end if;

  v_local_now := v_now at time zone p_timezone;

  if p_requested_starts_at is not null then
    if not pg_catalog.isfinite(p_requested_starts_at) then
      raise exception 'chosen start must be finite'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := p_requested_starts_at at time zone p_timezone;
    v_starts_now :=
      v_local_start::date = v_local_now::date
      and p_requested_starts_at <= v_now
      and extract(second from v_local_start) = 0;

    if not v_starts_now and (
      extract(minute from v_local_start) <> 0
      or extract(second from v_local_start) <> 0
      or p_requested_starts_at <= v_now
      or p_requested_starts_at > v_now + interval '90 days'
    ) then
      raise exception 'chosen start must be start-now today or a future whole local hour within 90 days'
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
      || case when p_include_provider_ids then
           pg_catalog.jsonb_build_object(
             'stripe_customer_id', v_existing.stripe_customer_id,
             'stripe_setup_intent_id', v_existing.stripe_setup_intent_id
           )
         else '{}'::jsonb end
    );
  end if;

  perform app.require_personal_stripe_sandbox_beta_admission_v1(p_owner_id);

  insert into app.personal_stripe_sandbox_setups (
    user_id, request_id, payload_hash, cadence, target_steps,
    commitment_amount_minor, currency, timezone, requested_starts_at,
    agreement_version, consent_version, consented_at, expires_at,
    beta_authorization_version, beta_authorized_at
  )
  values (
    p_owner_id, p_request_id, v_payload_hash, p_cadence, p_target_steps,
    p_commitment_amount_minor, p_currency, p_timezone,
    p_requested_starts_at, p_agreement_version, p_consent_version, v_now,
    v_now + interval '24 hours', 'personal-stripe-sandbox-beta-v1', v_now
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

create or replace function app.validate_personal_stripe_sandbox_agreement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setup           app.personal_stripe_sandbox_setups;
  v_terms           public.personal_challenge_terms;
  v_contest         public.contests;
  v_expected_start  timestamptz;
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

  v_expected_start := new.requested_starts_at;
  if new.requested_starts_at is not null
     and new.requested_starts_at <= v_setup.consented_at
     and (new.requested_starts_at at time zone new.timezone)::date
       = (v_setup.consented_at at time zone new.timezone)::date
     and extract(
       second from new.requested_starts_at at time zone new.timezone
     ) = 0
  then
    v_expected_start := (
      (v_setup.consented_at at time zone new.timezone)::date::timestamp
        at time zone new.timezone
    );
  end if;

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
       and v_contest.starts_at <> v_expected_start
     )
  then
    raise exception 'Stripe sandbox agreement does not match setup and frozen Personal terms'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

revoke all on function app.assert_contest_window_is_future(),
                       app.begin_personal_stripe_sandbox_setup_unchecked(
                         uuid, uuid, public.contest_cadence, integer, integer,
                         text, text, timestamptz, text, text, boolean
                       ),
                       app.validate_personal_stripe_sandbox_agreement()
  from public, anon, authenticated, service_role;

revoke all on function public.create_personal_challenge_v1(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.create_personal_challenge_v1(
  uuid, public.contest_cadence, integer, integer, text, timestamptz
) to authenticated;

-- New main-mode clients construct policy-marked Personal v2 challenges.
create or replace function app.create_personal_challenge_v2_unchecked(
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
  v_local_now timestamp;
  v_local_start timestamp;
  v_start_date date;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_starts_now boolean := false;
  v_previous_start_timezone text;
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

  v_local_now := v_now at time zone p_timezone;

  if p_requested_starts_at is not null then
    if not pg_catalog.isfinite(p_requested_starts_at) then
      raise exception 'a chosen start must be a finite instant'
        using errcode = 'invalid_parameter_value';
    end if;

    v_local_start := p_requested_starts_at at time zone p_timezone;
    v_starts_now :=
      v_local_start::date = v_local_now::date
      and p_requested_starts_at <= v_now
      and extract(second from v_local_start) = 0;

    if not v_starts_now then
      if extract(minute from v_local_start) <> 0
         or extract(second from v_local_start) <> 0
      then
        raise exception
          'a chosen start must be start-now on the current local date or a whole local hour'
          using errcode = 'invalid_parameter_value';
      end if;
      if p_requested_starts_at <= v_now
         or p_requested_starts_at > v_now + interval '90 days'
      then
        raise exception 'a chosen start must be in the future and within 90 days'
          using errcode = 'invalid_parameter_value';
      end if;
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
             or (
               v_starts_now
               and contest.starts_at = (
                 v_local_now::date::timestamp at time zone p_timezone
               )
             )
             or (
               not v_starts_now
               and contest.starts_at = p_requested_starts_at
             )
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
    v_start_date := v_local_now::date + 1;
    v_starts_at := v_start_date::timestamp at time zone p_timezone;
  elsif v_starts_now then
    v_start_date := v_local_now::date;
    v_starts_at := v_start_date::timestamp at time zone p_timezone;
  else
    v_start_date := v_local_start::date;
    v_starts_at := p_requested_starts_at;
  end if;
  v_ends_at := (v_start_date + 7)::timestamp at time zone p_timezone;

  if v_starts_now then
    v_previous_start_timezone := pg_catalog.current_setting(
      'app.personal_start_now_timezone',
      true
    );
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      p_timezone,
      true
    );
  end if;

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

  if v_starts_now then
    perform pg_catalog.set_config(
      'app.personal_start_now_timezone',
      coalesce(v_previous_start_timezone, ''),
      true
    );
  end if;

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

  if v_starts_now then
    update public.contests contest
    set status = 'active', activated_at = v_now
    where contest.id = v_challenge_id;
  end if;

  return v_challenge_id;
end;
$$;
