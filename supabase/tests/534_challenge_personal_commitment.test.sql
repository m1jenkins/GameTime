-- D144 optional Stripe sandbox commitment on personal goals. Fictional,
-- rollback-only actors and fictional sandbox-shaped provider ids.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

create function pg_temp.call(n integer, q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;
create function pg_temp.readiness(n integer, p_source text, p_request integer) returns jsonb language sql as $$
  select public.challenge_real_health_readiness_v1(
    ('d5340000-0000-4000-8000-' || lpad(p_request::text, 12, '0'))::uuid, pg_temp.ba(n), p_source,
    clock_timestamp() - interval '1 minute', pg_temp.br(n), clock_timestamp() + interval '1 hour', null, null,
    extensions.digest('commitment fictional body ' || p_request, 'sha256'), false, null)
$$;
create function pg_temp.card(n integer, p_request integer, p_amount integer default 2000) returns uuid
language plpgsql as $$
declare s jsonb; id uuid;
begin
  s := public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(n),
    ('d5341000-0000-4000-8000-' || lpad(p_request::text, 12, '0'))::uuid, p_amount);
  id := (s->>'setup_id')::uuid;
  perform public.challenge_commitment_record_customer_service_v1(pg_temp.ba(n), 'cus_fictional' || n, false);
  perform public.challenge_commitment_record_setup_service_v1(pg_temp.ba(n), id, 'seti_fictional' || p_request,
    'pm_fictional' || p_request, 'succeeded', false);
  return id;
end $$;

select public.challenge_real_health_runtime_v1(true, true, false);
update app.challenge_policy_runtime_v1 set account_mode = true;
select pg_temp.readiness(n, 'apple_watch_steps_v1', n) from generate_series(1, 4) n;
select set_config('test.c.start', to_char((clock_timestamp() at time zone 'UTC')::date + 5, 'YYYY-MM-DD'), true);
create function pg_temp.cfg(p_amount integer default 2000) returns jsonb language sql as $$
  select jsonb_build_object('start_date', current_setting('test.c.start'), 'days', 7, 'timezone', 'UTC', 'amount_cents', p_amount)
$$;

-- Off by default, private tables, service-only commands
select is((select enabled from app.challenge_commitment_runtime_v1), false, 'commitments are off by default');
select ok(not has_table_privilege('authenticated', 'app.challenge_commitment_agreements_v1', 'select')
  and not has_table_privilege('service_role', 'app.challenge_commitment_charges_v1', 'select')
  and not has_function_privilege('authenticated', 'public.challenge_commitment_begin_setup_service_v1(uuid,uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.challenge_commitment_claim_charges_service_v1(uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.challenge_commitment_set_runtime_v1(boolean)', 'execute')
  and not has_function_privilege('anon', 'public.challenge_commitment_availability_v1()', 'execute')
  and has_function_privilege('authenticated', 'public.challenge_commitment_availability_v1()', 'execute')
  and has_function_privilege('service_role', 'public.challenge_commitment_record_charge_service_v1(uuid,uuid,text,text,text,boolean)', 'execute'),
  'tables are private; clients read, the service writes');
select is(pg_temp.call(1, 'select public.challenge_commitment_availability_v1()')->>'reason',
  'challenge_commitment_unavailable', 'a signed-in account sees the feature is unavailable');
select throws_ok($$select public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), extensions.gen_random_uuid(), 2000)$$,
  '42501', 'challenge_commitment_unavailable', 'no card is saved while the switch is off');

select public.challenge_commitment_set_runtime_v1(true);
select throws_ok($$select public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), extensions.gen_random_uuid(), 2000)$$,
  '42501', 'challenge_commitment_unavailable', 'an account must also be eligible');
select public.challenge_commitment_set_eligibility_v1(pg_temp.ba(n), true) from generate_series(1, 3) n;
select is(pg_temp.call(1, 'select public.challenge_commitment_availability_v1()')->>'available', 'true',
  'an eligible account sees the feature once it is on');

-- Saving a card
select throws_ok($$select public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), extensions.gen_random_uuid(), 5100)$$,
  '22023', 'challenge_commitment_invalid_amount', 'amounts above $50 are refused');
select throws_ok($$select public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), extensions.gen_random_uuid(), 250)$$,
  '22023', 'challenge_commitment_invalid_amount', 'amounts must be whole dollars');
select throws_ok($$select public.challenge_commitment_record_customer_service_v1(pg_temp.ba(1), 'cus_live', true)$$,
  '42501', 'challenge_commitment_livemode_refused', 'live Stripe objects are refused');
create temp table cards as select pg_temp.card(1, 1) as card1;
grant all on cards to authenticated;
select is((select status from app.challenge_commitment_setups_v1 where id = (select card1 from cards)), 'succeeded',
  'the saved card is ready to bind');
select is(public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), 'd5341000-0000-4000-8000-000000000001', 2000)->>'setup_id',
  (select card1 from cards)::text, 'repeating the same request returns the same setup');
select throws_ok($$select public.challenge_commitment_begin_setup_service_v1(pg_temp.ba(1), 'd5341000-0000-4000-8000-000000000001', 3000)$$,
  '22023', 'challenge_commitment_request_conflict', 'a changed amount under the same request is refused');

-- Preview and commit
create temp table previews as
select pg_temp.call(1, format($$select public.challenge_commitment_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1', %L)$$,
  pg_temp.cfg(), (select card1 from cards))) as committed,
  pg_temp.call(1, format($$select public.challenge_personal_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1')$$,
  pg_temp.cfg())) as plain;
select is((select committed->'terms'->'commitment' from previews), jsonb_build_object('amount_cents', 2000, 'currency', 'usd',
  'recipient', 'gametime', 'recipient_version', 'gametime_recipient_v1', 'charge_rule', 'one_charge_after_confirmed_miss_v1',
  'proof_rule', 'complete_window_v1', 'provider', 'stripe_sandbox'), 'the terms name the amount, GameTime and the proof rule');
select is((select committed->'terms'->>'simulation' from previews), 'stripe_sandbox', 'committed terms are not labelled simulated');
select is((select (committed->'terms') - 'commitment' - 'simulation' from previews),
  (select (plain->'terms') - 'simulation' from previews), 'otherwise the terms match an uncommitted goal');
select ok((select plain->'terms' ? 'commitment' = false and plain->'terms'->>'simulation' = 'nonredeemable' from previews),
  'goals without a commitment keep their terms');
select throws_ok(format($$select pg_temp.call(1, %L)$$,
  format($$select public.challenge_commitment_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1', %L)$$,
  pg_temp.cfg(3000), (select card1 from cards))), '22023', 'challenge_commitment_amount_mismatch',
  'the goal amount must equal the saved card amount');
select throws_ok(format($$select pg_temp.call(1, %L)$$,
  format($$select public.challenge_commitment_preview_v1('personal_exercise_goal_v1', %L::jsonb, 30, 'apple_watch_exercise_credit_v2', %L)$$,
  pg_temp.cfg(), (select card1 from cards))), '22023', 'challenge_commitment_policy_unavailable',
  'Activity minutes goals cannot take a commitment');
select throws_ok(format($$select pg_temp.call(2, %L)$$,
  format($$select public.challenge_commitment_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1', %L)$$,
  pg_temp.cfg(), (select card1 from cards))), '42501', 'challenge_commitment_card_required',
  'another account cannot use this card');

create temp table committed as
select (pg_temp.call(1, format($$select public.challenge_mutate_v1(extensions.gen_random_uuid(), %L::jsonb)$$,
  jsonb_build_object('op', 'personal_commit', 'policy', 'personal_steps_goal_v1', 'source_policy_version', 'apple_watch_steps_v1',
    'config', pg_temp.cfg(), 'target', 50000, 'digest', (select committed->>'digest' from previews), 'consent', true,
    'commitment_setup_id', (select card1 from cards))))->>'id')::uuid as id;
select isnt((select id from committed), null, 'an eligible account commits with a saved card');
select is((select row(amount_cents, recipient_version, terms_digest, stripe_payment_method_id)::text
  from app.challenge_commitment_agreements_v1 where challenge_id = (select id from committed)),
  row(2000, 'gametime_recipient_v1', (select committed->>'digest' from previews), 'pm_fictional1')::text,
  'the commitment is bound to the agreed terms and the saved card');
select is((select row(status, consumed_by)::text from app.challenge_commitment_setups_v1 where id = (select card1 from cards)),
  row('consumed', (select id from committed))::text, 'the saved card is used once');
select is((select digest from app.challenge_agreements_v1 where challenge_id = (select id from committed)),
  (select committed->>'digest' from previews), 'the stored agreement is the previewed one');
select is(pg_temp.call(1, format($$select public.challenge_commitment_status_v1(%L)$$, (select id from committed)))->>'state',
  'committed', 'the owner sees an open commitment');
select is(pg_temp.call(2, format($$select public.challenge_commitment_status_v1(%L)$$, (select id from committed))),
  null, 'nobody else sees it');
select is(pg_temp.call(1, 'select public.challenge_commitment_availability_v1()')->>'reason',
  'challenge_commitment_limit', 'one open commitment at a time');
select throws_ok($$select pg_temp.card(1, 2)$$, '23505', 'challenge_commitment_limit', 'a second card cannot be saved meanwhile');
select throws_ok($$update app.challenge_commitment_agreements_v1 set amount_cents = 100$$,
  '42501', 'challenge_commitment_immutable', 'the binding cannot be rewritten');
select is(pg_temp.call(1, format($$select public.challenge_mutate_v1(extensions.gen_random_uuid(), %L::jsonb)$$,
  jsonb_build_object('op', 'personal_commit', 'policy', 'personal_steps_goal_v1', 'source_policy_version', 'apple_watch_steps_v1',
    'config', jsonb_build_object('start_date', to_char((clock_timestamp() at time zone 'UTC')::date + 20, 'YYYY-MM-DD'),
      'days', 7, 'timezone', 'UTC', 'amount_cents', 100), 'target', 50000,
    'digest', pg_temp.call(1, format($$select public.challenge_personal_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1')$$,
      jsonb_build_object('start_date', to_char((clock_timestamp() at time zone 'UTC')::date + 20, 'YYYY-MM-DD'),
        'days', 7, 'timezone', 'UTC', 'amount_cents', 100)))->>'digest', 'consent', true)))->>'status',
  'scheduled', 'an uncommitted goal still commits exactly as before');

-- Evaluation: fictional goals whose windows have ended, one per case.
create temp table cases(name text primary key, id uuid, actor integer, committed boolean);
grant all on cases to authenticated;
create function pg_temp.ended_goal(p_name text, p_actor integer, p_committed boolean) returns uuid language plpgsql as $$
declare cid uuid := extensions.gen_random_uuid(); s timestamptz := clock_timestamp() - interval '8 days';
  e timestamptz := clock_timestamp() - interval '1 hour'; terms jsonb; setup uuid;
begin
  perform set_config('app.challenge_write_v1', 'on', true);
  terms := jsonb_build_object('policy', 'personal_steps_goal_v1', 'source_policy_version', 'apple_watch_steps_v1',
    'config', jsonb_build_object('starts_at', s, 'ends_at', e, 'amount_cents', 2000));
  if p_committed then
    terms := terms || jsonb_build_object('simulation', 'stripe_sandbox', 'commitment', app.challenge_commitment_block_v1(2000));
  end if;
  insert into app.challenge_lobbies_v1(id, creator_id, policy, config, starts_at, ends_at, status, created_at,
    minimum, capacity, agreement_version, real_source_policy_version)
  values (cid, pg_temp.ba(p_actor), 'personal_steps_goal_v1', terms->'config', s, e, 'active', s - interval '1 day',
    1, 1, 1, 'apple_watch_steps_v1');
  insert into app.challenge_agreements_v1(challenge_id, version, terms, created_at) values (cid, 1, terms, s - interval '1 day');
  insert into app.challenge_members_v1(challenge_id, actor_id, selected, target) values (cid, pg_temp.ba(p_actor), true, 10000);
  insert into app.challenge_slots_v1(challenge_id, actor_id, mode, metric, starts_at, ends_at)
  values (cid, pg_temp.ba(p_actor), 'personal', 'steps', s, e);
  insert into app.challenge_consents_v1(challenge_id, version, actor_id, digest, recorded_at)
  select a.challenge_id, 1, pg_temp.ba(p_actor), a.digest, s - interval '1 day' from app.challenge_agreements_v1 a where a.challenge_id = cid;
  if p_committed then
    insert into app.challenge_commitment_setups_v1(actor_id, request_id, amount_cents, status, stripe_customer_id,
      stripe_setup_intent_id, stripe_payment_method_id, expires_at, consumed_by)
    values (pg_temp.ba(p_actor), extensions.gen_random_uuid(), 2000, 'consumed', 'cus_fictional' || p_actor,
      'seti_case' || replace(p_name, '_', ''), 'pm_case' || replace(p_name, '_', ''), s, cid) returning id into setup;
    insert into app.challenge_commitment_agreements_v1(challenge_id, actor_id, setup_id, amount_cents, currency,
      recipient_version, terms_digest, stripe_customer_id, stripe_payment_method_id)
    select cid, pg_temp.ba(p_actor), setup, 2000, 'usd', 'gametime_recipient_v1', a.digest, 'cus_fictional' || p_actor,
      'pm_case' || replace(p_name, '_', '') from app.challenge_agreements_v1 a where a.challenge_id = cid;
  end if;
  insert into cases values (p_name, cid, p_actor, p_committed);
  return cid;
end $$;
create function pg_temp.progress(p_name text, p_revision integer, p_value integer, p_through timestamptz default null)
returns jsonb language plpgsql as $$
declare body jsonb; k cases; req uuid := extensions.gen_random_uuid();
begin
  select * into k from cases where name = p_name;
  select jsonb_build_object('contract_version', 1, 'actor_id', pg_temp.ba(k.actor), 'challenge_id', c.id, 'agreement_version', 1,
    'terms_digest', a.digest, 'source_policy_version', 'apple_watch_steps_v1', 'metric', 'steps',
    'window_starts_at', c.starts_at, 'window_ends_at', c.ends_at, 'request_id', req,
    'revision', p_revision, 'previous_revision', case when p_revision = 1 then null else p_revision - 1 end,
    'state', 'value', 'value', p_value, 'observed_at', clock_timestamp(),
    'queried_through_at', coalesce(p_through, c.ends_at))
  into body from app.challenge_lobbies_v1 c join app.challenge_agreements_v1 a on a.challenge_id = c.id and a.version = 1
  where c.id = k.id;
  return public.challenge_real_health_ingest_v1(req, body, pg_temp.br(k.actor), clock_timestamp() + interval '1 hour',
    null, null, extensions.digest(body::text, 'sha256'), false);
end $$;
create function pg_temp.finish(p_name text) returns jsonb language plpgsql as $$
declare cid uuid := (select id from cases where name = p_name); r jsonb;
begin
  r := app.challenge_evaluate_v1(cid);
  perform app.challenge_finish_v1(cid, r, case when r->>'outcome' = 'void' then 'void' else 'final' end);
  return r;
end $$;
create function pg_temp.status(p_name text) returns text language sql as $$
  select (select result from app.challenge_finals_v1 where challenge_id = c.id)->'participants'->pg_temp.ba(c.actor)::text->>'status'
  from cases c where c.name = p_name
$$;
create function pg_temp.charged(p_name text) returns boolean language sql as $$
  select exists(select 1 from app.challenge_commitment_charges_v1 where challenge_id = (select id from cases where name = p_name))
$$;

select pg_temp.ended_goal('short_full', 2, true);
select pg_temp.ended_goal('short_partial', 3, true);
select pg_temp.ended_goal('no_data', 1, true);
select pg_temp.ended_goal('met', 1, true);
select pg_temp.ended_goal('plain_short', 1, false);
select lives_ok($$select pg_temp.progress('short_full', 1, 4000, clock_timestamp() - interval '2 days')$$, 'a partial total saves');
select lives_ok($$select pg_temp.progress('short_full', 2, 8000)$$, 'the full-window total saves');
select lives_ok($$select pg_temp.progress('short_partial', 1, 8000, clock_timestamp() - interval '2 days')$$, 'only a partial total saves');
select lives_ok($$select pg_temp.progress('met', 1, 12000, clock_timestamp() - interval '2 days')$$, 'a total over the target saves');
select lives_ok($$select pg_temp.progress('plain_short', 1, 8000)$$, 'an uncommitted full-window shortfall saves');

select is(pg_temp.finish('short_full')->>'outcome', 'scored', 'a complete shortfall is a result');
select is(pg_temp.status('short_full'), 'missed', 'and counts as a miss');
select ok(pg_temp.charged('short_full'), 'which queues one charge');
select is((select row(amount_cents, status, idempotency_key)::text from app.challenge_commitment_charges_v1
  where challenge_id = (select id from cases where name = 'short_full')),
  row(2000, 'pending', 'gt:challenge-commitment:v1:' || (select id from cases where name = 'short_full') || ':' || pg_temp.ba(2))::text,
  'for the committed amount with a stable idempotency key');
select is(pg_temp.finish('short_partial')->>'outcome', 'void', 'a partial window is not proof');
select ok(not pg_temp.charged('short_partial'), 'so nothing is charged');
select is(pg_temp.finish('no_data')->>'outcome', 'void', 'no data is not proof');
select ok(not pg_temp.charged('no_data'), 'so nothing is charged');
select is(pg_temp.finish('met')->>'outcome', 'scored', 'meeting the target is a result');
select is(pg_temp.status('met'), 'met', 'counts as met');
select ok(not pg_temp.charged('met'), 'and is never charged');
select is(pg_temp.finish('plain_short')->>'outcome', 'void', 'an uncommitted goal keeps the old rule: a shortfall stays unresolved');
select ok(not pg_temp.charged('plain_short'), 'and has nothing to charge');

-- Dispatch
select public.challenge_commitment_set_runtime_v1(false);
select is((select count(*) from public.challenge_commitment_claim_charges_service_v1('d5342000-0000-4000-8000-000000000001', 10)),
  0::bigint, 'nothing is dispatched while the switch is off');
select public.challenge_commitment_set_runtime_v1(true);
create temp table claim as select * from public.challenge_commitment_claim_charges_service_v1('d5342000-0000-4000-8000-000000000001', 10);
select is((select count(*) from claim), 1::bigint, 'the queued charge is claimed once');
select is((select row(amount_cents, stripe_customer_id, stripe_payment_method_id, attempt_count)::text from claim),
  row(2000, 'cus_fictional2', 'pm_caseshortfull', 1)::text, 'with the bound card');
select is((select count(*) from public.challenge_commitment_claim_charges_service_v1('d5342000-0000-4000-8000-000000000002', 10)),
  0::bigint, 'a leased charge is not claimed twice');
select throws_ok(format($$select public.challenge_commitment_record_charge_service_v1(%L, 'd5342000-0000-4000-8000-000000000002', 'succeeded', 'pi_fictional1', null, false)$$,
  (select charge_id from claim)), '40001', 'challenge_commitment_lease_lost', 'only the lease holder records the result');
select is(public.challenge_commitment_record_charge_service_v1((select charge_id from claim), 'd5342000-0000-4000-8000-000000000001',
  'requires_action', 'pi_fictional1', 'authentication_required', false)->>'status', 'requires_action',
  'a charge that needs the cardholder is recorded');
select is(pg_temp.call(2, format($$select public.challenge_commitment_status_v1(%L)$$, (select id from cases where name = 'short_full')))->>'state',
  'charge_needs_attention', 'the owner sees it needs attention');
select is(pg_temp.call(2, 'select public.challenge_commitment_availability_v1()')->>'reason', 'challenge_commitment_unpaid',
  'an unpaid charge blocks new commitments');
select is(public.challenge_commitment_apply_webhook_service_v1('evt_fictional1', 'payment_intent.succeeded', 'payment_intent',
  'pi_fictional1', 'succeeded', null, null, false)->>'disposition', 'applied', 'a signed webhook settles it');
select is(public.challenge_commitment_apply_webhook_service_v1('evt_fictional1', 'payment_intent.succeeded', 'payment_intent',
  'pi_fictional1', 'succeeded', null, null, false)->>'disposition', 'duplicate', 'the same event applies once');
select is(pg_temp.call(2, format($$select public.challenge_commitment_status_v1(%L)$$, (select id from cases where name = 'short_full')))->>'state',
  'charged', 'the owner sees the charge went through');
select is(public.challenge_commitment_apply_webhook_service_v1('evt_fictional2', 'payment_intent.payment_failed',
  'payment_intent', 'pi_fictional1', 'requires_payment_method', null, 'card_declined', false)->>'disposition', 'ignored',
  'a later event cannot undo a succeeded charge');
select throws_ok($$update app.challenge_commitment_charges_v1 set status = 'failed' where stripe_payment_intent_id = 'pi_fictional1'$$,
  '42501', 'challenge_commitment_immutable', 'nor can a direct write');
select is(public.challenge_commitment_apply_webhook_service_v1('evt_fictional3', 'payment_intent.succeeded', 'payment_intent',
  'pi_fictional1', 'succeeded', null, null, false)->>'disposition', 'ignored', 'a repeated success is a no-op');
select throws_ok($$select public.challenge_commitment_apply_webhook_service_v1('evt_live', 'payment_intent.succeeded', 'payment_intent',
  'pi_fictional1', 'succeeded', null, null, true)$$, '42501', 'challenge_commitment_livemode_refused', 'live events are refused');
select is(pg_temp.call(2, 'select public.challenge_commitment_availability_v1()')->>'available', 'true',
  'once paid, the account may commit again');
select is(pg_temp.call(1, format($$select public.challenge_commitment_status_v1(%L)$$, (select id from cases where name = 'met')))->>'state',
  'not_charged', 'a met goal reports no charge');

select * from finish();
rollback;
