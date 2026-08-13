-- Owner cancellation may end a still-running internal or Stripe sandbox
-- Personal challenge without erasing its frozen terms, payment agreement,
-- activation time, Health snapshot, or exact-request audit. The exception is
-- fail-closed for grace/finalized challenges and future live-mode agreements.

begin;
select no_plan();
set local timezone = 'UTC';

insert into auth.users (id) values
  ('fc111111-1111-1111-1111-111111111111'),
  ('fc222222-2222-2222-2222-222222222222'),
  ('fc333333-3333-3333-3333-333333333333'),
  ('fc444444-4444-4444-4444-444444444444'),
  ('fc555555-5555-5555-5555-555555555555'),
  ('fc666666-6666-6666-6666-666666666666');

insert into public.profiles (id, handle, display_name, timezone) values
  ('fc111111-1111-1111-1111-111111111111', 'cancelowner', 'Cancel Owner', 'UTC'),
  ('fc222222-2222-2222-2222-222222222222', 'cancelother', 'Cancel Other', 'UTC'),
  ('fc333333-3333-3333-3333-333333333333', 'cancelinternal', 'Cancel Internal', 'UTC'),
  ('fc444444-4444-4444-4444-444444444444', 'cancelfinal', 'Cancel Final', 'UTC'),
  ('fc555555-5555-5555-5555-555555555555', 'cancelgrace', 'Cancel Grace', 'UTC'),
  ('fc666666-6666-6666-6666-666666666666', 'cancellive', 'Cancel Live', 'UTC');

create function pg_temp.make_stripe_challenge(
  p_owner_id         uuid,
  p_request_id       uuid,
  p_customer_id      text,
  p_setup_intent_id  text,
  p_payment_method_id text,
  p_start_now        boolean
)
returns uuid
language plpgsql
as $$
declare
  v_requested_starts_at timestamptz;
  v_setup jsonb;
  v_challenge jsonb;
begin
  v_requested_starts_at := case
    when p_start_now then date_trunc('minute', clock_timestamp())
    else null
  end;

  v_setup := public.begin_personal_stripe_sandbox_setup_service_v1(
    p_owner_id,
    p_request_id,
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    v_requested_starts_at,
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1'
  );

  perform public.record_personal_stripe_sandbox_customer_v1(
    p_owner_id,
    p_customer_id
  );
  perform public.record_personal_stripe_sandbox_setup_v1(
    p_owner_id,
    (v_setup ->> 'setup_id')::uuid,
    p_customer_id,
    p_setup_intent_id,
    p_payment_method_id,
    'succeeded'
  );

  v_challenge := public.commit_personal_stripe_sandbox_challenge_service_v2(
    p_owner_id,
    p_request_id,
    (v_setup ->> 'setup_id')::uuid,
    'daily',
    10000,
    1000,
    'USD',
    'UTC',
    v_requested_starts_at,
    'personal-stripe-sandbox-v1',
    'personal-stripe-sandbox-consent-v1'
  );

  return (v_challenge ->> 'challenge_id')::uuid;
end;
$$;

set local role service_role;

select public.set_personal_stripe_sandbox_runtime_v1(
  'fc000000-0000-0000-0000-000000000001',
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
      'fc000000-0000-0000-0000-000000000011'::uuid,
      'fc111111-1111-1111-1111-111111111111'::uuid
    ),
    (
      'fc000000-0000-0000-0000-000000000012'::uuid,
      'fc555555-5555-5555-5555-555555555555'::uuid
    ),
    (
      'fc000000-0000-0000-0000-000000000013'::uuid,
      'fc666666-6666-6666-6666-666666666666'::uuid
    )
) fixture(request_id, owner_id);

create temporary table t_active as
select pg_temp.make_stripe_challenge(
  'fc111111-1111-1111-1111-111111111111',
  'fc100000-0000-0000-0000-000000000001',
  'cus_FC111111111111111111111111111111',
  'seti_FC11111111111111111111111111111',
  'pm_FC111111111111111111111111111111',
  true
) as challenge_id;

reset role;

insert into app.personal_health_snapshots_v2 (
  challenge_id,
  user_id,
  terms_fingerprint,
  observed_at,
  query_through,
  daily_progress,
  total_steps,
  updated_at
)
select
  active.challenge_id,
  'fc111111-1111-1111-1111-111111111111',
  app.personal_terms_fingerprint_v2(active.challenge_id),
  clock_timestamp(),
  clock_timestamp(),
  app.personal_zero_daily_progress_v2(active.challenge_id),
  0,
  clock_timestamp()
from t_active active;

create temporary table t_active_frozen as
select
  contest.activated_at,
  to_jsonb(terms) - 'closed_at' as terms,
  to_jsonb(agreement) as agreement,
  to_jsonb(snapshot) as health_snapshot
from t_active active
join public.contests contest
  on contest.id = active.challenge_id
join public.personal_challenge_terms terms
  on terms.challenge_id = active.challenge_id
join app.personal_stripe_sandbox_agreements agreement
  on agreement.challenge_id = active.challenge_id
join app.personal_health_snapshots_v2 snapshot
  on snapshot.challenge_id = active.challenge_id;

grant select on t_active to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc222222-2222-2222-2222-222222222222"}',
  true
);

select throws_ok(
  format(
    'select public.cancel_personal_challenge_v1(%L, %L)',
    (select challenge_id from t_active),
    'fc200000-0000-0000-0000-000000000001'::uuid
  ),
  '42501',
  null,
  'another account cannot cancel the owner active Stripe sandbox challenge'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fc111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.cancel_personal_challenge_v1(
    (select challenge_id from t_active),
    'fc100000-0000-0000-0000-000000000002'
  ),
  (select challenge_id from t_active),
  'the owner can end an active Stripe sandbox challenge'
);

select is(
  public.cancel_personal_challenge_v1(
    (select challenge_id from t_active),
    'fc100000-0000-0000-0000-000000000002'
  ),
  (select challenge_id from t_active),
  'an exact active-cancellation retry returns the original result'
);

reset role;

select ok(
  (
    select contest.status = 'cancelled'
       and contest.cancellation_reason = 'creator_cancelled'
       and contest.cancelled_at is not null
       and contest.activated_at = frozen.activated_at
       and terms.closed_at = contest.cancelled_at
    from t_active active
    join t_active_frozen frozen on true
    join public.contests contest on contest.id = active.challenge_id
    join public.personal_challenge_terms terms
      on terms.challenge_id = active.challenge_id
  ),
  'cancellation closes terms while preserving the activation timestamp'
);

select ok(
  (
    select (to_jsonb(terms) - 'closed_at') = frozen.terms
       and to_jsonb(agreement) = frozen.agreement
       and to_jsonb(snapshot) = frozen.health_snapshot
    from t_active active
    join t_active_frozen frozen on true
    join public.personal_challenge_terms terms
      on terms.challenge_id = active.challenge_id
    join app.personal_stripe_sandbox_agreements agreement
      on agreement.challenge_id = active.challenge_id
    join app.personal_health_snapshots_v2 snapshot
      on snapshot.challenge_id = active.challenge_id
  ),
  'frozen terms, Stripe agreement, and Health snapshot remain intact'
);

select ok(
  exists (
    select 1
    from app.personal_challenge_cancellation_requests request
    join t_active active on active.challenge_id = request.challenge_id
    where request.actor_id = 'fc111111-1111-1111-1111-111111111111'
      and request.request_id = 'fc100000-0000-0000-0000-000000000002'
      and octet_length(request.payload_hash) = 32
  ),
  'the exact cancellation audit record remains append-only history'
);

select throws_ok(
  format(
    'select app.publish_due_personal_result(%L, %L)',
    (select challenge_id from t_active),
    clock_timestamp() + interval '10 days'
  ),
  '23001',
  null,
  'a cancelled challenge cannot publish a result even after its cutoff'
);

select ok(
  not exists (
    select 1
    from public.personal_challenge_results result
    join t_active active on active.challenge_id = result.challenge_id
  )
  and not exists (
    select 1
    from app.personal_stripe_sandbox_payment_reviews review
    join t_active active on active.challenge_id = review.challenge_id
  )
  and not exists (
    select 1
    from app.personal_stripe_sandbox_charge_commands command
    join t_active active on active.challenge_id = command.challenge_id
  ),
  'cancellation creates no result, payment review, or charge command'
);

-- The cancelled row no longer occupies the owner open-challenge slot. The new
-- Stripe challenge is scheduled and retains the existing pre-start path.
set local role service_role;
create temporary table t_scheduled as
select pg_temp.make_stripe_challenge(
  'fc111111-1111-1111-1111-111111111111',
  'fc100000-0000-0000-0000-000000000003',
  'cus_FC111111111111111111111111111111',
  'seti_FC11111111111111111111111111112',
  'pm_FC111111111111111111111111111112',
  false
) as challenge_id;
reset role;

select is(
  (
    select contest.status::text
    from public.contests contest
    join t_scheduled scheduled on scheduled.challenge_id = contest.id
  ),
  'pending',
  'a new scheduled Stripe sandbox challenge can start after cancellation'
);

grant select on t_scheduled to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc111111-1111-1111-1111-111111111111"}',
  true
);
select is(
  public.cancel_personal_challenge_v1(
    (select challenge_id from t_scheduled),
    'fc100000-0000-0000-0000-000000000004'
  ),
  (select challenge_id from t_scheduled),
  'scheduled Stripe sandbox cancellation remains valid'
);
reset role;

-- Internal test-only active cancellation remains valid without a provider
-- agreement.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc333333-3333-3333-3333-333333333333"}',
  true
);
create temporary table t_internal as
select public.create_personal_challenge_v2(
  'fc300000-0000-0000-0000-000000000001',
  'daily',
  10000,
  1000,
  'UTC',
  date_trunc('minute', clock_timestamp())
) as challenge_id;
select is(
  public.cancel_personal_challenge_v1(
    (select challenge_id from t_internal),
    'fc300000-0000-0000-0000-000000000002'
  ),
  (select challenge_id from t_internal),
  'active internal test-only cancellation remains valid'
);
reset role;

-- Finalized challenges stay terminal.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc444444-4444-4444-4444-444444444444"}',
  true
);
create temporary table t_finalized as
select public.create_personal_challenge_v2(
  'fc400000-0000-0000-0000-000000000001',
  'daily',
  10000,
  1000,
  'UTC',
  date_trunc('minute', clock_timestamp())
) as challenge_id;
reset role;
update public.contests contest
set status = 'finalized'
where contest.id = (select challenge_id from t_finalized);
grant select on t_finalized to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc444444-4444-4444-4444-444444444444"}',
  true
);
select throws_ok(
  format(
    'select public.cancel_personal_challenge_v1(%L, %L)',
    (select challenge_id from t_finalized),
    'fc400000-0000-0000-0000-000000000002'::uuid
  ),
  '23001',
  null,
  'a finalized challenge cannot be cancelled'
);
reset role;

-- Persisted status remains active during the post-end evidence window. Moving
-- only the frozen end in this rolled-back fixture exercises that derived
-- awaiting-evidence state without weakening production constraints.
set local role service_role;
create temporary table t_awaiting as
select pg_temp.make_stripe_challenge(
  'fc555555-5555-5555-5555-555555555555',
  'fc500000-0000-0000-0000-000000000001',
  'cus_FC555555555555555555555555555555',
  'seti_FC55555555555555555555555555555',
  'pm_FC555555555555555555555555555555',
  true
) as challenge_id;
reset role;
alter table public.contests disable trigger contests_freeze_terms;
update public.contests contest
set starts_at = date_trunc('day', clock_timestamp()) - interval '8 days',
    ends_at = date_trunc('day', clock_timestamp()) - interval '1 day'
where contest.id = (select challenge_id from t_awaiting);
alter table public.contests enable trigger contests_freeze_terms;
grant select on t_awaiting to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc555555-5555-5555-5555-555555555555"}',
  true
);
select throws_ok(
  format(
    'select public.cancel_personal_challenge_v1(%L, %L)',
    (select challenge_id from t_awaiting),
    'fc500000-0000-0000-0000-000000000002'::uuid
  ),
  '23001',
  null,
  'an awaiting-evidence Stripe sandbox challenge cannot be cancelled'
);
reset role;

-- Simulate the future live agreement shape inside this rolled-back test. The
-- production sandbox provenance check stays intact outside the transaction.
set local role service_role;
create temporary table t_live as
select pg_temp.make_stripe_challenge(
  'fc666666-6666-6666-6666-666666666666',
  'fc600000-0000-0000-0000-000000000001',
  'cus_FC666666666666666666666666666666',
  'seti_FC66666666666666666666666666666',
  'pm_FC666666666666666666666666666666',
  true
) as challenge_id;
reset role;
alter table app.personal_stripe_sandbox_agreements
  drop constraint personal_stripe_agreements_fixed_provenance;
update app.personal_stripe_sandbox_agreements agreement
set environment = 'live',
    livemode = true
where agreement.challenge_id = (select challenge_id from t_live);
grant select on t_live to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc666666-6666-6666-6666-666666666666"}',
  true
);
select throws_ok(
  format(
    'select public.cancel_personal_challenge_v1(%L, %L)',
    (select challenge_id from t_live),
    'fc600000-0000-0000-0000-000000000002'::uuid
  ),
  '23001',
  null,
  'a future live-mode agreement remains non-cancellable after start'
);
reset role;

select * from finish();
rollback;
