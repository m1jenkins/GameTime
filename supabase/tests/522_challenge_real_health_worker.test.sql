begin;
select no_plan();

-- This test runs after the populated historical-upgrade baseline.  It owns two
-- otherwise-unused actors instead of replaying the shared challenge fixture.
insert into auth.users(id) values
  ('bf000000-0000-0000-0000-000000000051'),
  ('bf000000-0000-0000-0000-000000000052'),
  ('bf000000-0000-0000-0000-000000000053');
insert into public.profiles(id, handle, display_name, timezone) values
  ('bf000000-0000-0000-0000-000000000051', 'realhealthfixture51', 'Real Health Fixture', 'America/Chicago'),
  ('bf000000-0000-0000-0000-000000000052', 'realhealthfixture52', 'Real Health Fixture', 'America/Chicago'),
  ('bf000000-0000-0000-0000-000000000053', 'realhealthfixture53', 'Real Health Fixture', 'America/Chicago');
insert into auth.sessions(id, user_id) values
  ('ba000000-0000-0000-0000-000000000051', 'bf000000-0000-0000-0000-000000000051'),
  ('ba000000-0000-0000-0000-000000000052', 'bf000000-0000-0000-0000-000000000052'),
  ('ba000000-0000-0000-0000-000000000053', 'bf000000-0000-0000-0000-000000000053');
create function pg_temp.ba(n integer) returns uuid language sql as $$
  select ('bf000000-0000-0000-0000-' || lpad((50 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.br(n integer) returns uuid language sql as $$
  select ('ba000000-0000-0000-0000-' || lpad((50 + n)::text, 12, '0'))::uuid
$$;
create function pg_temp.real_login(p_actor uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_actor, 'session_id', pg_temp.br(case when p_actor=pg_temp.ba(1) then 1 else 2 end))::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

select has_table('app', 'challenge_real_health_admissions_v1', 'real-health admissions are private records');
select has_table('app', 'challenge_real_health_facts_v1', 'real-health facts are private records');
select has_table('app', 'challenge_real_health_requests_v1', 'real-health request receipts are private records');
select ok((select relrowsecurity from pg_class where oid = 'app.challenge_real_health_facts_v1'::regclass), 'real-health facts have RLS');
select ok(not has_table_privilege('authenticated', 'app.challenge_real_health_facts_v1', 'select'), 'people cannot read raw real-health facts');
select ok(not has_table_privilege('service_role', 'app.challenge_real_health_requests_v1', 'select'), 'service cannot read raw real-health receipts');
select ok(has_function_privilege('service_role', 'public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)', 'execute'), 'only service receives the ingress RPC');
select ok(not has_function_privilege('authenticated', 'public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)', 'execute'), 'a person cannot call real ingress directly');
select ok(has_function_privilege('service_role',
 coalesce(to_regprocedure('public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean,bigint)'),
          to_regprocedure('public.challenge_real_health_readiness_v1(uuid,uuid,text,timestamptz,uuid,timestamptz,bytea,bigint,bytea,boolean)')),
 'execute'), 'service receives the separately attested readiness RPC');

select set_config('app.challenge_write_v1', 'on', true);
create temp table real_ids as
select
  'be000000-0000-0000-0000-000000000518'::uuid as challenge_id,
  pg_temp.ba(1) as actor_id,
  pg_temp.ba(2) as other_actor,
  clock_timestamp() - interval '1 hour' as starts_at,
  clock_timestamp() + interval '1 hour' as ends_at,
  decode('04' || repeat('11', 64), 'hex') as public_key;
insert into app.challenge_lobbies_v1(
  id, creator_id, policy, config, starts_at, ends_at, status, revision,
  agreement_version, created_at, minimum, capacity
)
select challenge_id, actor_id, 'friend_steps_goal_v1', '{"amount_cents":100}'::jsonb,
  starts_at, ends_at, 'active', 1, 1, starts_at, 2, 6
from real_ids;
update app.challenge_lobbies_v1
set real_source_policy_version = 'apple_watch_steps_v1'
where id = (select challenge_id from real_ids);
insert into app.challenge_members_v1(challenge_id, actor_id, selected, target)
select challenge_id, actor_id, true, 100 from real_ids
union all
select challenge_id, other_actor, true, 100 from real_ids;
insert into app.challenge_slots_v1(challenge_id, actor_id, mode, metric, starts_at, ends_at)
select challenge_id, actor_id, 'friend', 'steps', starts_at, ends_at from real_ids
union all
select challenge_id, other_actor, 'friend', 'steps', starts_at, ends_at from real_ids;
insert into app.challenge_agreements_v1(challenge_id, version, terms, created_at)
select challenge_id, 1, '{"metric":"steps","policy":"friend_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"}'::jsonb
 ||jsonb_build_object('config',jsonb_build_object('starts_at',starts_at,'ends_at',ends_at)), starts_at from real_ids;
insert into app.challenge_consents_v1(challenge_id, version, actor_id, digest, recorded_at)
select r.challenge_id, 1, r.actor_id, agreement.digest, clock_timestamp()
from real_ids r join app.challenge_agreements_v1 agreement on agreement.challenge_id = r.challenge_id and agreement.version = 1
union all
select r.challenge_id, 1, r.other_actor, agreement.digest, clock_timestamp()
from real_ids r join app.challenge_agreements_v1 agreement on agreement.challenge_id = r.challenge_id and agreement.version = 1;
insert into public.device_attestations(key_id, user_id, public_key, environment)
select extensions.digest(public_key, 'sha256'), actor_id, public_key, 'development'::public.attestation_environment from real_ids;
insert into app.device_attestation_receipts(key_id, initial_receipt, current_receipt, received_at, current_receipt_verified_at)
select extensions.digest(public_key, 'sha256'), '\x01'::bytea, '\x01'::bytea, clock_timestamp() - interval '1 minute', clock_timestamp()
from real_ids;

select public.challenge_real_health_runtime_v1(true, true, true);
create function pg_temp.real_payload(p_request uuid, p_revision integer, p_previous integer, p_state text, p_value bigint default null)
returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'contract_version', 1,
    'actor_id', r.actor_id,
    'challenge_id', r.challenge_id,
    'agreement_version', 1,
    'terms_digest', agreement.digest,
    'source_policy_version', 'apple_watch_steps_v1',
    'metric', 'steps',
    'window_starts_at', r.starts_at,
    'window_ends_at', r.ends_at,
    'request_id', p_request,
    'revision', p_revision,
    'previous_revision', case when p_previous is null then 'null'::jsonb else to_jsonb(p_previous) end,
    'state', p_state,
    'observed_at', clock_timestamp() - interval '1 second',
    'queried_through_at', clock_timestamp() - interval '30 seconds'
  ) || jsonb_build_object('value', case when p_state = 'value' then to_jsonb(p_value) else 'null'::jsonb end)
  from real_ids r
  join app.challenge_agreements_v1 agreement on agreement.challenge_id = r.challenge_id and agreement.version = 1
$$;
create function pg_temp.real_ingest(p_request uuid, p_payload jsonb, p_counter bigint, p_recovery_only boolean default false)
returns jsonb language sql volatile as $$
  select public.challenge_real_health_ingest_v1(
    p_request, p_payload, pg_temp.br(1), clock_timestamp() + interval '1 hour',
    (select extensions.digest(public_key, 'sha256') from real_ids), p_counter,
    extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256'), p_recovery_only
  )
$$;

select throws_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000518', pg_temp.real_payload('ba000000-0000-0000-0000-000000000518', 1, null, 'value', 0), 1)$$,
  '22023', 'challenge_invalid_real_health_request', 'zero is not a score and cannot enter as a value'
);
select throws_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000519', pg_temp.real_payload('ba000000-0000-0000-0000-000000000519', 1, null, 'unresolved') || '{"complete":true}'::jsonb, 1)$$,
  '22023', 'challenge_invalid_real_health_request', 'caller cannot assert completeness'
);

create temp table saved_real_receipt(value jsonb);
create temp table saved_real_request(payload jsonb);
insert into saved_real_request
select pg_temp.real_payload('ba000000-0000-0000-0000-000000000520', 1, null, 'value', 100);
insert into saved_real_receipt
select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000520', payload, 1) from saved_real_request;
select is((select value ->> 'revision' from saved_real_receipt), '1', 'positive normalized lower bound is accepted as revision one');
select is((select sign_count from public.device_attestations where user_id = pg_temp.ba(1)), 1::bigint, 'accepted fact atomically consumes the device counter');
select is((select count(*) from app.challenge_real_health_admissions_v1), 1::bigint, 'first accepted fact freezes one actor agreement policy window binding');
select is((select count(*) from app.challenge_real_health_facts_v1), 1::bigint, 'accepted fact is stored privately');
select is(
  app.challenge_detail_for_actor_v1((select challenge_id from real_ids), pg_temp.ba(1))
    -> 'members' -> 0 -> 'fact' ->> 'value',
  '100', 'the existing server detail projection reads the real fact ledger'
);
insert into app.challenge_real_health_admissions_v1(
  challenge_id, actor_id, agreement_version, terms_digest, source_policy_version,
  metric, window_starts_at, window_ends_at, admitted_at
)
select r.challenge_id, r.other_actor, 1, agreement.digest, 'apple_watch_steps_v1',
  'steps', r.starts_at, r.ends_at, clock_timestamp()
from real_ids r join app.challenge_agreements_v1 agreement on agreement.challenge_id = r.challenge_id and agreement.version = 1;
insert into app.challenge_real_health_facts_v1(
  challenge_id, actor_id, agreement_version, revision, previous_revision, state,
  value, observed_at, queried_through_at, recorded_at, request_id
)
select challenge_id, other_actor, 1, 1, null, 'value', 200,
  clock_timestamp() - interval '1 second', clock_timestamp() - interval '30 seconds', clock_timestamp(),
  'ba000000-0000-0000-0000-000000000524'::uuid
from real_ids;
select is(
  app.challenge_real_health_evaluate_v1((select challenge_id from real_ids)) -> 'participants' -> pg_temp.ba(1)::text ->> 'status',
  'met', 'a positive lower bound can qualify a goal only through server derivation'
);
select is(
  pg_temp.real_ingest('ba000000-0000-0000-0000-000000000520', (select payload from saved_real_request), 1),
  (select value from saved_real_receipt), 'exact current-session retry recovers the committed receipt'
);
select public.challenge_real_health_runtime_v1(true, false, true);
select is(
  pg_temp.real_ingest('ba000000-0000-0000-0000-000000000520', (select payload from saved_real_request), 1, true),
  (select value from saved_real_receipt), 'disabled Edge recovery returns only the exact committed receipt'
);
select throws_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000521', pg_temp.real_payload('ba000000-0000-0000-0000-000000000521', 2, 1, 'unresolved'), 2, true)$$,
  '42501', 'challenge_real_health_paused', 'recovery-only mode refuses a new fact'
);
select public.challenge_real_health_runtime_v1(true, true, true);
select throws_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000529', pg_temp.real_payload('ba000000-0000-0000-0000-000000000529', 2, null, 'unresolved'), 2)$$,
  '22023', 'challenge_invalid_real_health_revision', 'a correction must name the exact parent even when a caller sends null'
);
select throws_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000522', pg_temp.real_payload('ba000000-0000-0000-0000-000000000522', 3, 1, 'unresolved'), 2)$$,
  '22023', 'challenge_invalid_real_health_revision', 'a caller cannot skip a replacement revision'
);
select lives_ok(
  $$select pg_temp.real_ingest('ba000000-0000-0000-0000-000000000523', pg_temp.real_payload('ba000000-0000-0000-0000-000000000523', 2, 1, 'unresolved'), 2)$$,
  'unresolved replacement is accepted but does not synthesize zero'
);
select is(
  app.challenge_real_health_evaluate_v1((select challenge_id from real_ids)) -> 'participants' -> pg_temp.ba(1)::text ->> 'status',
  'void', 'missing or unresolved replacement cannot become a missed goal'
);
select is(
  app.challenge_detail_for_actor_v1((select challenge_id from real_ids), pg_temp.ba(1))
    -> 'members' -> 0 -> 'fact' ->> 'state',
  'unresolved', 'the same server projection replaces progress with the lower correction'
);
select lives_ok(
  $$select public.challenge_real_health_readiness_v1(
    'ba000000-0000-0000-0000-000000000527', pg_temp.ba(1), 'apple_watch_steps_v1',
    clock_timestamp() - interval '1 minute', pg_temp.br(1), clock_timestamp() + interval '1 hour',
    (select extensions.digest(public_key, 'sha256') from real_ids), 3,
    extensions.digest(convert_to('p8-readiness-527', 'UTF8'), 'sha256'), false
  )$$,
  'a positive real-source policy read is atomically admitted through the service boundary'
);
select ok(exists(select 1 from app.challenge_real_health_readiness_v1 where actor_id=pg_temp.ba(1) and source_policy_version='apple_watch_steps_v1'), 'readiness records no claimed total or completeness flag');
update app.challenge_lobbies_v1 set policy = 'friend_steps_leaderboard_v1' where id = (select challenge_id from real_ids);
update app.challenge_members_v1 set target = null where challenge_id = (select challenge_id from real_ids);
select is(
  app.challenge_real_health_evaluate_v1((select challenge_id from real_ids)) ->> 'outcome',
  'void', 'a lower bound never proves a leaderboard complete'
);

-- Move only the disposable test clock, preserving the consented window.
-- Function replacement rolls back with this test transaction.
create or replace function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('test.p8_real_health_now',true),'')::timestamptz,clock_timestamp())
$$;

-- The real row is due under its own logical clock.  Legacy fixtures stay
-- disabled throughout: dispatch/complete must still advance only this source
-- ledger and eventually retain its history.
select public.challenge_runtime_v1(false,false,false,'{}'::uuid[],null);
select public.challenge_real_health_runtime_v1(true,true,false);
select set_config('test.p8_real_health_now',(ends_at+interval '48 hours 1 second')::text,true) from real_ids;
update app.challenge_lobbies_v1 set policy='friend_steps_goal_v1' where id=(select challenge_id from real_ids);
update app.challenge_members_v1 set target=100 where challenge_id=(select challenge_id from real_ids);
select public.challenge_prepare_worker_invocation_v1('ba000000-0000-0000-0000-000000000541',jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select challenge_id from real_ids))),1);
select is(public.challenge_dispatch_worker_invocation_v1('ba000000-0000-0000-0000-000000000541')->>'status','disabled','real work stays disabled until its independent processing gate opens');
select ok(not exists(select 1 from app.challenge_work_claims_v1 where challenge_id=(select challenge_id from real_ids) and state='claimed'),'disabled real processing does not lease work');

select public.challenge_real_health_runtime_v1(true,true,true);
select public.challenge_prepare_worker_invocation_v1('ba000000-0000-0000-0000-000000000542',jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select challenge_id from real_ids))),1);
create temp table worker_dispatch(value jsonb);
insert into worker_dispatch select public.challenge_dispatch_worker_invocation_v1('ba000000-0000-0000-0000-000000000542');
select is((select value->>'status' from worker_dispatch),'dispatched','real processing claims due work while legacy fixtures remain off');
select is(jsonb_array_length((select value->'claims' from worker_dispatch)),1,'real dispatch returns one bounded claim');
select lives_ok($$select public.challenge_complete_claim_v1(((select value->'claims'->0->>'id' from worker_dispatch)::uuid),((select value->'claims'->0->>'claim_token' from worker_dispatch)::uuid))$$,'real claimed work completes through the shared worker boundary');
select isnt(public.challenge_local_worker_status_v1()->>'processing_state','disabled','worker projection is source-aware when only real work is enabled');
select ok(not exists(select 1 from app.challenge_facts_v1 where challenge_id=(select challenge_id from real_ids)),'real worker never creates fictional fact scores');

select set_config('test.p8_real_health_now',(ends_at+interval '146 hours')::text,true) from real_ids;
select public.challenge_prepare_worker_invocation_v1('ba000000-0000-0000-0000-000000000543',jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select challenge_id from real_ids))),1);
create temp table final_dispatch(value jsonb);
insert into final_dispatch select public.challenge_dispatch_worker_invocation_v1('ba000000-0000-0000-0000-000000000543');
select lives_ok($$select public.challenge_complete_claim_v1(((select value->'claims'->0->>'id' from final_dispatch)::uuid),((select value->'claims'->0->>'claim_token' from final_dispatch)::uuid))$$,'later real worker claim reaches terminal history');
select ok(exists(select 1 from app.challenge_finals_v1 where challenge_id=(select challenge_id from real_ids)),'real worker retains final history after processing');

-- A real-enabled dispatch must not lease a due legacy row while legacy
-- processing is paused; this catches an unqualified outer work-row alias.
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,revision,agreement_version,created_at,minimum,capacity)
values('be000000-0000-0000-0000-000000000522',pg_temp.ba(3),'friend_steps_goal_v1','{"amount_cents":100}'::jsonb,'2020-01-01T00:00Z','2020-01-02T00:00Z','active',1,1,'2020-01-01T00:00Z',1,2);
select public.challenge_runtime_v1(false,true,false,array[pg_temp.ba(3)],null);
select public.challenge_real_health_runtime_v1(true,true,true);
select public.challenge_prepare_worker_invocation_v1('ba000000-0000-0000-0000-000000000544',jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array('be000000-0000-0000-0000-000000000522'::uuid)),1);
select is(public.challenge_dispatch_worker_invocation_v1('ba000000-0000-0000-0000-000000000544')->>'status','healthy_empty','real processing does not lease a due legacy row while legacy processing is paused');
select ok(not exists(select 1 from app.challenge_work_claims_v1 where challenge_id='be000000-0000-0000-0000-000000000522'::uuid and state='claimed'),'mixed gates leave the paused legacy claim unleased');

-- Real community snapshots use their own gate and source clock.  Counts stay
-- hidden below five and for fifteen minutes after the first eligible capture.
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,revision,agreement_version,created_at,minimum,capacity,real_source_policy_version)
select 'be000000-0000-0000-0000-000000000523',actor_id,'community_steps_goal_v1','{"amount_cents":100}'::jsonb,starts_at,ends_at,'published_open',1,1,starts_at,2,6,'apple_watch_steps_v1' from real_ids;
insert into app.challenge_community_publications_v1 values('be000000-0000-0000-0000-000000000523',pg_temp.ba(1),'operator',clock_timestamp());
insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
select 'be000000-0000-0000-0000-000000000523'::uuid,actor_id,true,100 from real_ids
union all select 'be000000-0000-0000-0000-000000000523'::uuid,other_actor,true,100 from real_ids;
select public.challenge_runtime_v1(false,false,false,'{}'::uuid[],null);
select set_config('test.p8_real_health_now',(ends_at+interval '200 hours')::text,true) from real_ids;
select lives_ok($$select public.challenge_capture_community_snapshot_v1('be000000-0000-0000-0000-000000000523')$$,'real community capture works with legacy gates off');
select is(app.challenge_community_counts_v1('be000000-0000-0000-0000-000000000523')->>'state','threshold','real community counts stay hidden below five');
insert into auth.users(id) values('bf000000-0000-0000-0000-000000000054'),('bf000000-0000-0000-0000-000000000055'),('bf000000-0000-0000-0000-000000000056');
insert into public.profiles(id,handle,display_name,timezone) values('bf000000-0000-0000-0000-000000000054','realhealthfixture54','Real Health Fixture','America/Chicago'),('bf000000-0000-0000-0000-000000000055','realhealthfixture55','Real Health Fixture','America/Chicago'),('bf000000-0000-0000-0000-000000000056','realhealthfixture56','Real Health Fixture','America/Chicago');
insert into app.challenge_members_v1(challenge_id,actor_id,selected,target) values('be000000-0000-0000-0000-000000000523','bf000000-0000-0000-0000-000000000054',true,100),('be000000-0000-0000-0000-000000000523','bf000000-0000-0000-0000-000000000055',true,100),('be000000-0000-0000-0000-000000000523','bf000000-0000-0000-0000-000000000056',true,100);
select is(app.challenge_community_counts_v1('be000000-0000-0000-0000-000000000523')->>'state','pending','five real members wait for the next eligible source snapshot');
select set_config('test.p8_real_health_now',(ends_at+interval '200 hours 15 minutes')::text,true) from real_ids;
select public.challenge_capture_community_snapshot_v1('be000000-0000-0000-0000-000000000523');
select is(app.challenge_community_counts_v1('be000000-0000-0000-0000-000000000523')->>'state','pending','a newly eligible real capture remains hidden for fifteen minutes');
select set_config('test.p8_real_health_now',(ends_at+interval '200 hours 30 minutes')::text,true) from real_ids;
select is(app.challenge_community_counts_v1('be000000-0000-0000-0000-000000000523')->>'joined','5','real community count appears after its source-clock fifteen-minute delay');

select * from finish();
rollback;
