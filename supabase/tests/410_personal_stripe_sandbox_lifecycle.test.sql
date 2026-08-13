-- Stripe sandbox lifecycle: exact setup/commit, provisional review, one charge
-- only after confirmation, no charge for non-miss/cancelled outcomes, leased
-- recording, and idempotent webhook receipts.

begin;
select no_plan();
set local timezone = 'UTC';

insert into auth.users (id) values
  ('fa111111-1111-1111-1111-111111111111'),
  ('fa222222-2222-2222-2222-222222222222'),
  ('fa333333-3333-3333-3333-333333333333'),
  ('fa444444-4444-4444-4444-444444444444'),
  ('fa555555-5555-5555-5555-555555555555'),
  ('fa666666-6666-6666-6666-666666666666'),
  ('fa777777-7777-7777-7777-777777777777');

insert into public.profiles (id, handle, display_name, timezone) values
  ('fa111111-1111-1111-1111-111111111111', 'stripeapi', 'Stripe API', 'UTC'),
  ('fa222222-2222-2222-2222-222222222222', 'stripemiss', 'Stripe Miss', 'UTC'),
  ('fa333333-3333-3333-3333-333333333333', 'stripemet', 'Stripe Met', 'UTC'),
  ('fa444444-4444-4444-4444-444444444444', 'stripeinc', 'Stripe Inc', 'UTC'),
  ('fa555555-5555-5555-5555-555555555555', 'stripecancel', 'Stripe Cancel', 'UTC'),
  ('fa666666-6666-6666-6666-666666666666', 'stripereview', 'Stripe Review', 'UTC'),
  ('fa777777-7777-7777-7777-777777777777', 'stripenow', 'Stripe Now', 'UTC');

-- ---------------------------------------------------------------------------
-- The Edge contract commits one succeeded setup to unchanged Personal V1.
-- ---------------------------------------------------------------------------

set local role service_role;

select public.set_personal_stripe_sandbox_runtime_v1(
  'f4100000-0000-0000-0000-000000000001',
  true
);

select public.set_personal_stripe_sandbox_beta_eligibility_v1(
  fixture.request_id,
  fixture.owner_id,
  true
)
from (
  values
    (
      'f4100000-0000-0000-0000-000000000011'::uuid,
      'fa111111-1111-1111-1111-111111111111'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000012'::uuid,
      'fa222222-2222-2222-2222-222222222222'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000013'::uuid,
      'fa333333-3333-3333-3333-333333333333'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000014'::uuid,
      'fa444444-4444-4444-4444-444444444444'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000015'::uuid,
      'fa555555-5555-5555-5555-555555555555'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000016'::uuid,
      'fa666666-6666-6666-6666-666666666666'::uuid
    ),
    (
      'f4100000-0000-0000-0000-000000000017'::uuid,
      'fa777777-7777-7777-7777-777777777777'::uuid
    )
) fixture(request_id, owner_id);

create temporary table t_api_setup as
select public.begin_personal_stripe_sandbox_setup_service_v1(
  'fa111111-1111-1111-1111-111111111111',
  'fa100000-0000-0000-0000-000000000001',
  'daily',
  10000,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select public.record_personal_stripe_sandbox_customer_v1(
  'fa111111-1111-1111-1111-111111111111',
  'cus_FA111111111111111111111111111111'
);

select public.record_personal_stripe_sandbox_setup_v1(
  'fa111111-1111-1111-1111-111111111111',
  (select (value ->> 'setup_id')::uuid from t_api_setup),
  'cus_FA111111111111111111111111111111',
  'seti_FA11111111111111111111111111111',
  'pm_FA111111111111111111111111111111',
  'succeeded'
);

select is(
  (
    public.load_personal_stripe_sandbox_setup_service_v1(
      'fa111111-1111-1111-1111-111111111111',
      (select (value ->> 'setup_id')::uuid from t_api_setup),
      'fa100000-0000-0000-0000-000000000001',
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      null,
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1'
    ) ->> 'stripe_setup_intent_id'
  ),
  'seti_FA11111111111111111111111111111',
  'service load returns the canonical SetupIntent only for identical terms'
);

create temporary table t_api_challenge as
select public.commit_personal_stripe_sandbox_challenge_service_v1(
  'fa111111-1111-1111-1111-111111111111',
  'fa100000-0000-0000-0000-000000000001',
  (select (value ->> 'setup_id')::uuid from t_api_setup),
  'daily',
  10000,
  1000,
  'USD',
  'UTC',
  null,
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select is(
  (
    public.commit_personal_stripe_sandbox_challenge_service_v1(
      'fa111111-1111-1111-1111-111111111111',
      'fa100000-0000-0000-0000-000000000001',
      (select (value ->> 'setup_id')::uuid from t_api_setup),
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      null,
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1'
    ) ->> 'replayed'
  ),
  'true',
  'service commit is an exact replay'
);

create temporary table t_start_now_terms as
select date_trunc('minute', clock_timestamp()) as requested_at;

create temporary table t_start_now_setup as
select public.begin_personal_stripe_sandbox_setup_service_v1(
  'fa777777-7777-7777-7777-777777777777',
  'fa700000-0000-0000-0000-000000000001',
  'daily', 10000, 1000, 'USD', 'UTC',
  (select requested_at from t_start_now_terms),
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select public.record_personal_stripe_sandbox_customer_v1(
  'fa777777-7777-7777-7777-777777777777',
  'cus_FA777777777777777777777777777777'
);

select public.record_personal_stripe_sandbox_setup_v1(
  'fa777777-7777-7777-7777-777777777777',
  (select (value ->> 'setup_id')::uuid from t_start_now_setup),
  'cus_FA777777777777777777777777777777',
  'seti_FA77777777777777777777777777777',
  'pm_FA777777777777777777777777777777',
  'succeeded'
);

create temporary table t_start_now_challenge as
select public.commit_personal_stripe_sandbox_challenge_service_v2(
  'fa777777-7777-7777-7777-777777777777',
  'fa700000-0000-0000-0000-000000000001',
  (select (value ->> 'setup_id')::uuid from t_start_now_setup),
  'daily', 10000, 1000, 'USD', 'UTC',
  (select requested_at from t_start_now_terms),
  'personal-stripe-sandbox-v1',
  'personal-stripe-sandbox-consent-v1'
) as value;

select throws_ok(
  $$ select public.commit_personal_stripe_sandbox_challenge_service_v2(
       'fa111111-1111-1111-1111-111111111111',
       'fa100000-0000-0000-0000-000000000001',
       (select (value ->> 'setup_id')::uuid from t_api_setup),
       'daily', 10000, 1000, 'USD', 'UTC', null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$,
  '22023',
  null,
  'a Health-policy retry cannot acknowledge an unmarked Personal V1 commit'
);

reset role;

select is(
  (
    select contest.starts_at
    from public.contests contest
    where contest.id =
      (select (value ->> 'challenge_id')::uuid from t_start_now_challenge)
  ),
  date_trunc('day', clock_timestamp()),
  'Stripe sandbox start now freezes the scored start at today''s midnight'
);

select is(
  (
    select contest.status::text
    from public.contests contest
    where contest.id =
      (select (value ->> 'challenge_id')::uuid from t_start_now_challenge)
  ),
  'active',
  'Stripe sandbox start now activates before commit returns'
);

select is(
  (
    select terms.step_data_policy::text
    from public.personal_challenge_terms terms
    where terms.challenge_id =
      (select (value ->> 'challenge_id')::uuid from t_start_now_challenge)
  ),
  'healthkit_nonmanual_daily_v1',
  'Stripe sandbox start now keeps the Health snapshot policy'
);

grant select on t_api_challenge to authenticated;

select ok(
  exists (
    select 1
    from public.personal_challenge_terms terms
    join app.personal_stripe_sandbox_agreements agreement
      on agreement.challenge_id = terms.challenge_id
     and agreement.user_id = terms.user_id
    where terms.challenge_id =
      (select (value ->> 'challenge_id')::uuid from t_api_challenge)
      and terms.settlement_mode = 'test_only'
      and terms.step_data_policy = 'attested_hourly_v1'
      and terms.terms_version = 'personal-v1'
      and agreement.environment = 'sandbox'
      and not agreement.livemode
  ),
  'an unmarked legacy Edge commit preserves Personal V1 and adds one sandbox-only agreement atomically'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (
    select status ? 'setup_id'
       and status ->> 'payment_state' = 'method_saved'
       and not status ? 'stripe_customer_id'
       and not status ? 'stripe_setup_intent_id'
       and not status ? 'stripe_payment_method_id'
    from (
      select public.get_my_personal_stripe_sandbox_status_v1(
        (select (value ->> 'challenge_id')::uuid from t_api_challenge)
      ) as status
    ) source
  ),
  'owner status exposes workflow state but no Stripe identifier'
);

reset role;

-- A retained provider agreement is still explicitly sandbox/livemode=false,
-- so an owner may now end it while active without changing the agreement.
alter table public.contests
  disable trigger contests_enforce_status_transition;
update public.contests contest
set status = 'active',
    activated_at = clock_timestamp()
where contest.id =
  (select (value ->> 'challenge_id')::uuid from t_api_challenge);
alter table public.contests
  enable trigger contests_enforce_status_transition;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.cancel_personal_challenge_v1(
    (select (value ->> 'challenge_id')::uuid from t_api_challenge),
    'fa100000-0000-0000-0000-000000000099'::uuid
  ),
  (select (value ->> 'challenge_id')::uuid from t_api_challenge),
  'an owner may end an active Stripe sandbox challenge'
);

reset role;

-- ---------------------------------------------------------------------------
-- Compact trusted fixtures for terminal result behavior.
-- ---------------------------------------------------------------------------

create function pg_temp.make_paid_fixture(
  p_user_id uuid,
  p_contest_status public.contest_status
)
returns uuid
language plpgsql
as $$
declare
  v_challenge uuid := gen_random_uuid();
  v_setup uuid := gen_random_uuid();
  v_customer text := 'cus_' || replace(p_user_id::text, '-', '');
  v_setup_intent text := 'seti_' || replace(v_setup::text, '-', '');
  v_payment_method text := 'pm_' || replace(gen_random_uuid()::text, '-', '');
  v_now timestamptz := clock_timestamp();
  v_starts_at timestamptz := v_now - interval '9 days';
  v_ends_at timestamptz := v_now - interval '2 days';
  v_cutoff timestamptz := v_now - interval '1 day';
begin
  insert into public.contests (
    id,
    title,
    created_by,
    challenge_model,
    metric,
    cadence,
    target_value,
    stake_amount_cents,
    tie_break,
    starts_at,
    ends_at,
    max_participants,
    status,
    cancellation_reason,
    activated_at,
    cancelled_at
  )
  values (
    v_challenge,
    'Stripe lifecycle fixture',
    p_user_id,
    'personal_accountability',
    'steps',
    'daily',
    10000,
    1000,
    'void',
    v_starts_at,
    v_ends_at,
    1,
    'pending',
    null,
    null,
    null
  );

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  )
  values (v_challenge, p_user_id, 'accepted', 'UTC', null);

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
    closed_at
  )
  values (
    v_challenge,
    p_user_id,
    'daily',
    10000,
    1000,
    'USD',
    'test_only',
    'personal-v1',
    'UTC',
    v_starts_at - interval '1 day',
    v_cutoff,
    null
  );

  insert into app.personal_stripe_sandbox_customers (
    user_id, stripe_customer_id
  )
  values (p_user_id, v_customer);

  insert into app.personal_stripe_sandbox_setups (
    id,
    user_id,
    request_id,
    payload_hash,
    cadence,
    target_steps,
    commitment_amount_minor,
    currency,
    timezone,
    agreement_version,
    consent_version,
    consented_at,
    expires_at,
    stripe_customer_id,
    stripe_setup_intent_id,
    stripe_payment_method_id,
    status,
    succeeded_at,
    beta_authorization_version,
    beta_authorized_at
  )
  values (
    v_setup,
    p_user_id,
    gen_random_uuid(),
    decode(repeat('11', 32), 'hex'),
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1',
    v_now - interval '1 hour',
    v_now + interval '23 hours',
    v_customer,
    v_setup_intent,
    v_payment_method,
    'succeeded',
    v_now - interval '30 minutes',
    'personal-stripe-sandbox-beta-v1',
    v_now - interval '1 hour'
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
    v_challenge,
    p_user_id,
    v_setup,
    gen_random_uuid(),
    decode(repeat('22', 32), 'hex'),
    decode(repeat('11', 32), 'hex'),
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1',
    v_now - interval '1 hour',
    v_customer,
    v_setup_intent,
    v_payment_method,
    'personal-stripe-sandbox-beta-v1',
    v_now - interval '30 minutes'
  );

  update app.personal_stripe_sandbox_setups
  set
    consumed_at = v_now - interval '10 minutes',
    consumed_challenge_id = v_challenge
  where id = v_setup;

  return v_challenge;
end;
$$;

create function pg_temp.add_result(
  p_challenge_id uuid,
  p_outcome public.personal_challenge_outcome
)
returns uuid
language plpgsql
as $$
declare
  v_user_id uuid;
  v_cutoff timestamptz;
  v_assessment uuid := gen_random_uuid();
  v_result uuid := gen_random_uuid();
  v_state public.personal_evidence_state;
  v_reason public.personal_result_reason;
  v_waived boolean;
  v_days jsonb := jsonb_build_array(
    jsonb_build_object('local_date', '2099-01-01', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-02', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-03', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-04', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-05', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-06', 'total_steps', 0),
    jsonb_build_object('local_date', '2099-01-07', 'total_steps', 0)
  );
begin
  select terms.user_id, terms.evidence_cutoff
    into v_user_id, v_cutoff
  from public.personal_challenge_terms terms
  where terms.challenge_id = p_challenge_id;

  v_state := case when p_outcome = 'inconclusive'
    then 'missing'::public.personal_evidence_state
    else 'complete'::public.personal_evidence_state end;
  v_reason := case p_outcome
    when 'met_goal' then 'target_reached'::public.personal_result_reason
    when 'missed_goal' then 'target_missed'::public.personal_result_reason
    else 'missing_coverage'::public.personal_result_reason end;
  v_waived := p_outcome = 'inconclusive';

  insert into app.personal_evidence_assessments (
    id,
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
    assessed_at
  )
  values (
    v_assessment,
    p_challenge_id,
    v_user_id,
    gen_random_uuid(),
    v_state,
    v_cutoff,
    'personal-v1',
    decode(repeat('33', 32), 'hex'),
    168,
    case when v_state = 'complete' then 168 else 0 end,
    0,
    v_days,
    v_cutoff + interval '30 minutes'
  );

  insert into public.personal_challenge_results (
    id,
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
    v_result,
    p_challenge_id,
    v_user_id,
    v_assessment,
    p_outcome,
    v_reason,
    v_state,
    v_cutoff,
    0,
    v_days,
    v_waived,
    v_cutoff + interval '1 hour'
  );

  return v_result;
end;
$$;

-- These fixtures represent challenges whose real lifecycle has already ended.
-- Production creation remains future-only; tests bypass only that insert guard,
-- as the existing personal lifecycle acceptance suite does for historical data.
alter table public.contests
  disable trigger contests_assert_future_window;

create temporary table t_miss as
select pg_temp.make_paid_fixture(
  'fa222222-2222-2222-2222-222222222222',
  'finalized'
) as challenge_id;
create temporary table t_met as
select pg_temp.make_paid_fixture(
  'fa333333-3333-3333-3333-333333333333',
  'finalized'
) as challenge_id;
create temporary table t_inconclusive as
select pg_temp.make_paid_fixture(
  'fa444444-4444-4444-4444-444444444444',
  'finalized'
) as challenge_id;
create temporary table t_cancelled as
select pg_temp.make_paid_fixture(
  'fa555555-5555-5555-5555-555555555555',
  'cancelled'
) as challenge_id;
create temporary table t_review as
select pg_temp.make_paid_fixture(
  'fa666666-6666-6666-6666-666666666666',
  'finalized'
) as challenge_id;

alter table public.contests
  enable trigger contests_assert_future_window;

alter table public.contests
  disable trigger contests_enforce_status_transition;

update public.contests contest
set
  status = 'finalized',
  activated_at = clock_timestamp()
where contest.id in (
  (select challenge_id from t_miss),
  (select challenge_id from t_met),
  (select challenge_id from t_inconclusive),
  (select challenge_id from t_review)
);

update public.contests contest
set
  status = 'cancelled',
  cancellation_reason = 'creator_cancelled',
  cancelled_at = clock_timestamp()
where contest.id = (select challenge_id from t_cancelled);

alter table public.contests
  enable trigger contests_enforce_status_transition;

select pg_temp.add_result(
  (select challenge_id from t_miss), 'missed_goal'
);
select pg_temp.add_result(
  (select challenge_id from t_met), 'met_goal'
);
select pg_temp.add_result(
  (select challenge_id from t_inconclusive), 'inconclusive'
);
select pg_temp.add_result(
  (select challenge_id from t_review), 'missed_goal'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id = (select challenge_id from t_miss)
      and review.state = 'review_open'
  ),
  1::bigint,
  'a confirmed evidence miss opens one provisional review'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id = (select challenge_id from t_miss)
  ),
  0::bigint,
  'publishing a miss does not create a charge command'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id in (
      (select challenge_id from t_met),
      (select challenge_id from t_inconclusive),
      (select challenge_id from t_cancelled)
    )
  ),
  0::bigint,
  'met, inconclusive, and cancelled challenges never enter payment review'
);

grant select on t_review to service_role;
set local role service_role;

select is(
  (
    public.request_personal_stripe_sandbox_review_service_v1(
      'fa666666-6666-6666-6666-666666666666',
      (select challenge_id from t_review),
      'injury_attestation',
      null
    ) ->> 'review_state'
  ),
  'under_review',
  'the verified owner can file a bounded review before the deadline'
);

select is(
  (
    public.request_personal_stripe_sandbox_review_service_v1(
      'fa666666-6666-6666-6666-666666666666',
      (select challenge_id from t_review),
      'injury_attestation',
      null
    ) ->> 'replayed'
  ),
  'true',
  'an identical owner review request is an exact replay'
);

select throws_ok(
  $$ select public.request_personal_stripe_sandbox_review_service_v1(
       'fa666666-6666-6666-6666-666666666666',
       (select challenge_id from t_review),
       'different_reason',
       null
     ) $$,
  '22023',
  null,
  'a conflicting review retry is rejected'
);

select throws_ok(
  $$ select public.request_personal_stripe_sandbox_review_service_v1(
       'fa333333-3333-3333-3333-333333333333',
       (select challenge_id from t_review),
       'injury_attestation',
       null
     ) $$,
  '42501',
  null,
  'a different owner cannot file or discover the review'
);

reset role;

select throws_ok(
  format(
    'select public.settle_personal_stripe_sandbox_review_v1(%L, %L, %L, null)',
    (
      select review.id
      from app.personal_stripe_sandbox_payment_reviews review
      where review.challenge_id = (select challenge_id from t_miss)
    ),
    'confirm_miss',
    'review_window_expired'
  ),
  '23001',
  null,
  'a provisional miss cannot be confirmed before its absolute deadline'
);

update app.personal_stripe_sandbox_payment_reviews review
set
  opened_at = statement_timestamp() - interval '8 days',
  review_deadline = statement_timestamp() - interval '1 day'
where review.challenge_id = (select challenge_id from t_miss);

grant select on t_miss to service_role;

set local role service_role;

select throws_ok(
  $$ select public.request_personal_stripe_sandbox_review_service_v1(
       'fa222222-2222-2222-2222-222222222222',
       (select challenge_id from t_miss),
       'late_request',
       null
     ) $$,
  '23001',
  null,
  'a review request at or after the absolute deadline is rejected'
);

create temporary table t_claims as
select public.claim_personal_stripe_sandbox_charges_v1(
  'fa900000-0000-0000-0000-000000000001',
  10
) as value;

select is(
  jsonb_array_length((select value from t_claims)),
  1,
  'the worker auto-confirms an expired unreviewed miss and claims it once'
);

select ok(
  ((select value from t_claims) -> 0) ? 'command_id'
  and (((select value from t_claims) -> 0) ->> 'stripe_idempotency_key')
        like 'gt:personal-charge:v1:%',
  'claim uses the Edge snake_case shape and deterministic idempotency key'
);

select public.record_personal_stripe_sandbox_charge_v1(
  (((select value from t_claims) -> 0) ->> 'command_id')::uuid,
  'fa900000-0000-0000-0000-000000000001',
  'succeeded',
  'pi_FA222222222222222222222222222222',
  null
);

reset role;

select is(
  (
    select review.state
    from app.personal_stripe_sandbox_payment_reviews review
    where review.challenge_id = (select challenge_id from t_miss)
  ),
  'confirmed_miss',
  'an expired review_open row is confirmed only on the worker deadline tick'
);

select is(
  (
    select command.status
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id = (select challenge_id from t_miss)
  ),
  'succeeded',
  'the leased worker records one terminal sandbox success'
);

set local role service_role;

select is(
  (
    public.apply_personal_stripe_sandbox_webhook_v1(
      'evt_FA22222222222222222222222222222',
      decode(repeat('44', 32), 'hex'),
      'payment_intent.succeeded',
      'pi_FA222222222222222222222222222222',
      '2026-02-25.clover',
      clock_timestamp(),
      'applied',
      'payment',
      'succeeded',
      false,
      'cus_fa222222222222222222222222222222',
      ((select value from t_claims) -> 0)
        ->> 'stripe_payment_method_id',
      1000,
      'USD',
      null,
      (((select value from t_claims) -> 0) ->> 'command_id')::uuid
    ) ->> 'replayed'
  ),
  'false',
  'the first verified normalized webhook receipt is applied once'
);

select is(
  (
    public.apply_personal_stripe_sandbox_webhook_v1(
      'evt_FA22222222222222222222222222222',
      decode(repeat('44', 32), 'hex'),
      'payment_intent.succeeded',
      'pi_FA222222222222222222222222222222',
      '2026-02-25.clover',
      clock_timestamp(),
      'applied',
      'payment',
      'succeeded',
      false,
      'cus_fa222222222222222222222222222222',
      ((select value from t_claims) -> 0)
        ->> 'stripe_payment_method_id',
      1000,
      'USD',
      null,
      (((select value from t_claims) -> 0) ->> 'command_id')::uuid
    ) ->> 'replayed'
  ),
  'true',
  'the same Stripe event ID and digest is an idempotent replay'
);

reset role;

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id in (
      (select challenge_id from t_met),
      (select challenge_id from t_inconclusive),
      (select challenge_id from t_cancelled)
    )
  ),
  0::bigint,
  'met, inconclusive, and cancelled challenges never produce a charge command'
);

select is(
  (
    select count(*)
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id = (select challenge_id from t_review)
  ),
  0::bigint,
  'a timely unresolved review produces no charge command'
);

select * from finish();
rollback;
