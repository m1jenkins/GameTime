begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
\ir fixtures/challenge-worker-fixture.inc

-- The new local projection is sanitized, while the existing restricted status
-- RPC remains the selector for an authorized failed-item investigation.
select ok(not has_function_privilege('anon','public.challenge_prepare_worker_invocation_v1(uuid,jsonb,integer)','execute'),'anonymous cannot prepare a worker invocation');
select ok(not has_function_privilege('authenticated','public.challenge_dispatch_worker_invocation_v1(uuid)','execute'),'participant cannot dispatch a worker invocation');
select ok(not has_function_privilege('authenticated','public.challenge_recover_failed_item_v1(uuid,uuid)','execute'),'participant cannot recover failed work');
select ok(not has_function_privilege('authenticated','public.challenge_local_worker_status_v1()','execute'),'participant cannot read generic worker status');
select ok(has_function_privilege('service_role','public.challenge_prepare_worker_invocation_v1(uuid,jsonb,integer)','execute'),'service role can prepare local work');
select ok((select bool_and(prosecdef and proconfig=array['search_path=""']) from pg_proc where oid in
 ('public.challenge_prepare_worker_invocation_v1(uuid,jsonb,integer)'::regprocedure,
  'public.challenge_dispatch_worker_invocation_v1(uuid)'::regprocedure,
  'public.challenge_recover_failed_item_v1(uuid,uuid)'::regprocedure,
  'public.challenge_local_worker_status_v1()'::regprocedure)),'new worker RPCs use fixed definer paths');
select ok(public.challenge_operations_status_v1() ? 'failed_work','existing restricted status keeps failed-item detail');

insert into beta_ids values('scoped',pg_temp.beta_group(1,2));
insert into beta_ids values('other',pg_temp.beta_group(3,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');

select throws_ok($$select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90000),'{}',1)$$,'22023','challenge_invalid_scope','scope version and kind are required');
-- Fresh-session regression: prepare and dispatch are separate service calls.
-- Clear the transaction-local write flag before dispatch so this nonempty
-- path cannot inherit fixture authorization. The scoped claim helper must set
-- its own guard before updating the durable claim.
select is(set_config('app.challenge_write_v1','off',true),'off','fresh-session dispatch starts without fixture write authorization');
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90001),jsonb_build_object(
 'version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='scoped'))),1);
select is(public.challenge_prepare_worker_invocation_v1(pg_temp.br(90001),jsonb_build_object(
 'kind','challenge_ids','version','challenge_worker_scope_v1','ids',jsonb_build_array((select id from beta_ids where name='scoped'))),1)->>'status','prepared','exact scope retry is accepted');
select throws_ok($$select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90001),jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='scoped'))),2)$$,'22023','challenge_request_conflict','scope limit cannot change under one invocation ID');
select is(set_config('app.challenge_write_v1','off',true),'off','fresh-session dispatch write flag is cleared after prepare');
create temp table scoped_dispatch(value jsonb);
insert into scoped_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90001));
select is((select value->>'status' from scoped_dispatch),'dispatched','fresh-session scoped dispatch claims a due item');
select is(jsonb_array_length((select value->'claims' from scoped_dispatch)),1,'fresh-session scoped dispatch returns one claim');
select is(public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90001)),(select value from scoped_dispatch),'response-loss retry returns the exact invocation receipt');
create temp table scoped_completion(value jsonb);
insert into scoped_completion select public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from scoped_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from scoped_dispatch)->>'claim_token')::uuid);
select ok((select value ? 'status' from scoped_completion),'authorized completion succeeds');
select is(public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from scoped_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from scoped_dispatch)->>'claim_token')::uuid),
 (select value from scoped_completion),'duplicate completion returns the exact receipt');

-- Explicit ID scopes are validated at the privileged boundary and cannot
-- claim an unrelated due item.
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90002),jsonb_build_object(
 'version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='other'))),5);
create temp table id_dispatch(value jsonb);
insert into id_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90002));
select is((select value->'claims'->0->>'id' from id_dispatch),(select id::text from beta_ids where name='other'),'ID scope selects only its requested challenge');
select is(jsonb_array_length((select value->'claims' from id_dispatch)),1,'ID scope excludes unrelated due work');
select public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from id_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from id_dispatch)->>'claim_token')::uuid);

-- A paused pass emits a heartbeat and remains distinct from empty healthy work;
-- the due backlog is not silently treated as complete.
select pg_temp.clock_beta('2026-10-01T12:00Z');
insert into beta_ids values('paused',pg_temp.beta_group(5,2));
select pg_temp.clock_beta('2026-10-20T12:00Z',false,false);
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90003),'{"version":"challenge_worker_scope_v1","kind":"due"}',1);
select is(public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90003))->>'status','paused','paused processing does not lease work');
select is(jsonb_array_length(public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90003))->'claims'),0,'paused invocation has no claims');
select is(public.challenge_local_worker_status_v1()->>'processing_state','paused','paused status is not healthy empty');
select is(public.challenge_local_worker_status_v1()->>'heartbeat_status','paused','paused pass records a heartbeat');
select ok((public.challenge_local_worker_status_v1()->>'due_count')::integer>0,'paused status keeps due backlog visible');
select pg_temp.clock_beta('2026-10-20T12:00Z',true,true);
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90004),'{"version":"challenge_worker_scope_v1","kind":"due"}',1);
create temp table resumed_dispatch(value jsonb);
insert into resumed_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90004));
select is((select value->>'status' from resumed_dispatch),'dispatched','resume permits a fresh invocation');
select public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from resumed_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from resumed_dispatch)->>'claim_token')::uuid);

-- Expired claims are rejected by the established completion boundary and may
-- be replaced only by a fresh invocation identity.
select pg_temp.clock_beta('2026-10-01T12:00Z');
insert into beta_ids values('expired',pg_temp.beta_group(7,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90005),jsonb_build_object(
 'version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='expired'))),1);
create temp table expired_dispatch(value jsonb);
insert into expired_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90005));
select set_config('app.challenge_write_v1','on',true);
update app.challenge_work_claims_v1 set lease_expires_at=clock_timestamp()-interval '1 second' where challenge_id=(select id from beta_ids where name='expired');
select throws_ok($$select public.challenge_complete_claim_v1(((select value->'claims'->0 from expired_dispatch)->>'id')::uuid,((select value->'claims'->0 from expired_dispatch)->>'claim_token')::uuid)$$,'55000','challenge_stale_claim','expired claim token is rejected');
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90006),jsonb_build_object(
 'version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='expired'))),1);
create temp table replacement_dispatch(value jsonb);
insert into replacement_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90006));
select is(((select value->'claims'->0 from replacement_dispatch)->>'attempt')::integer,2,'expired lease gets a fresh bounded attempt');
select public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from replacement_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from replacement_dispatch)->>'claim_token')::uuid);

-- Repeated item failure exhausts only the selected claim. Recovery snapshots
-- its prior failure and resets only that item for one exact retry request.
select pg_temp.clock_beta('2026-10-01T12:00Z');
insert into beta_ids values('failure',pg_temp.beta_group(9,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');
create function pg_temp.p11a_fail() returns trigger language plpgsql as $$
begin
 if current_setting('p11a.fail',true)='on' and new.status='review' then
  raise exception 'synthetic failure must stay private' using errcode='23514';
 end if;
 return new;
end $$;
create trigger p11a_failure before update on app.challenge_lobbies_v1 for each row execute function pg_temp.p11a_fail();
select set_config('p11a.fail','on',true);
do $$declare i integer; c jsonb; r jsonb; inv uuid; cid uuid:=(select id from beta_ids where name='failure');begin
 for i in 1..5 loop
  inv:=pg_temp.br(90100+i);
  if i>1 then
   perform set_config('app.challenge_write_v1','on',true);
   update app.challenge_work_claims_v1 set next_attempt_at=clock_timestamp()-interval '1 second' where challenge_id=cid;
  end if;
  perform public.challenge_prepare_worker_invocation_v1(inv,jsonb_build_object('version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array(cid)),1);
  c:=public.challenge_dispatch_worker_invocation_v1(inv)->'claims'->0;
  if (c->>'attempt')::integer<>i then raise exception 'wrong bounded attempt'; end if;
  r:=public.challenge_complete_claim_v1((c->>'id')::uuid,(c->>'claim_token')::uuid);
  if r->>'error_code'<>'23514' then raise exception 'missing categorical failure'; end if;
 end loop;
end $$;
drop trigger p11a_failure on app.challenge_lobbies_v1;
select is((select state from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='failure')),'dead','repeated failure becomes a dead letter');
select ok(public.challenge_operations_status_v1()->'failed_work' @> jsonb_build_array(jsonb_build_object('challenge_id',(select id from beta_ids where name='failure'))),'restricted status identifies the selected failed item');
select ok(public.challenge_local_worker_status_v1()::text not like '%'||(select id::text from beta_ids where name='failure')||'%','generic status redacts challenge IDs');
select ok(public.challenge_local_worker_status_v1()::text not like '%claim_token%' and public.challenge_local_worker_status_v1()::text not like '%synthetic failure%','generic status redacts tokens and raw errors');
select public.challenge_recover_failed_item_v1(pg_temp.br(90200),(select id from beta_ids where name='failure'));
select is(public.challenge_recover_failed_item_v1(pg_temp.br(90200),(select id from beta_ids where name='failure'))->>'recovered','true','individual recovery is exactly retryable');
select throws_ok($$select public.challenge_recover_failed_item_v1(pg_temp.br(90200),(select id from beta_ids where name='other'))$$,'22023','challenge_request_conflict','recovery request cannot change item scope');
select is((select previous_error_code from app.challenge_worker_recoveries_v1 where request_id=pg_temp.br(90200)),'23514','recovery preserves prior categorical failure');
select ok(exists(select 1 from app.challenge_worker_audit_v1 where operation='recover' and challenge_id=(select id from beta_ids where name='failure')),'individual recovery is audited');
select pg_temp.clock_beta('2026-10-20T12:00Z');
select public.challenge_prepare_worker_invocation_v1(pg_temp.br(90201),jsonb_build_object(
 'version','challenge_worker_scope_v1','kind','challenge_ids','ids',jsonb_build_array((select id from beta_ids where name='failure'))),1);
create temp table recovered_dispatch(value jsonb);
insert into recovered_dispatch select public.challenge_dispatch_worker_invocation_v1(pg_temp.br(90201));
select is(((select value->'claims'->0 from recovered_dispatch)->>'attempt')::integer,1,'recovered item starts one fresh attempt');
select public.challenge_complete_claim_v1(
 ((select value->'claims'->0 from recovered_dispatch)->>'id')::uuid,
 ((select value->'claims'->0 from recovered_dispatch)->>'claim_token')::uuid);
select is((select total_attempts from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='failure')),6::bigint,'recovery retains total attempt history');

-- Snapshot invocation delegates to the existing server-time capture RPC. The
-- five-person threshold and fifteen-minute capture/disclosure delays remain
-- unchanged, including a delayed duplicate invocation.
select pg_temp.clock_beta('2026-10-01T12:00Z',true,true);
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(90300),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
create function pg_temp.community() returns uuid language sql as $$select id from beta_ids where name='community'$$;
create function pg_temp.join_community(n integer) returns jsonb language plpgsql as $$begin
 perform pg_temp.login_beta(n);
 return public.challenge_join_community_v1(pg_temp.br(90350+n),jsonb_build_object('op','join_community','id',pg_temp.community(),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
end $$;
select pg_temp.join_community(n) from generate_series(1,4) n;
reset role;
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(90400),pg_temp.community());
select is(public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(90400))->>'status','checked','snapshot invocation uses the existing capture boundary');
select pg_temp.join_community(5);
reset role;
select is(public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(90400))->>'status','checked','duplicate snapshot invocation is exact and delayed');
select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'state','pending','fifth participant waits for mature snapshot');
reset role;
select pg_temp.clock_beta('2026-10-01T12:15Z');
select public.challenge_prepare_community_snapshot_invocation_v1(pg_temp.br(90401),pg_temp.community());
select public.challenge_dispatch_community_snapshot_invocation_v1(pg_temp.br(90401));
select pg_temp.clock_beta('2026-10-01T12:29:59Z');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'joined',null::text,'snapshot remains undisclosed before fifteen minutes');
reset role;select pg_temp.clock_beta('2026-10-01T12:30Z');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'joined','5','snapshot discloses exactly after fifteen minutes');
reset role;
select ok(public.challenge_local_worker_status_v1() ? 'heartbeat_status','sanitized status reports bounded heartbeat state');

select * from finish();
rollback;
