begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
\ir fixtures/challenge-worker-fixture.inc

select ok(not has_table_privilege(role_name,'app.challenge_work_claims_v1','select,insert,update,delete'),role_name||' has no claim-table access')
from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege(role_name,'public.challenge_claim_batch_v1(uuid,integer)','execute'),role_name||' cannot drive claims')
from unnest(array['anon','authenticated']) role_name;
select ok(not has_function_privilege(role_name,'public.challenge_complete_claim_v1(uuid,uuid)','execute'),role_name||' cannot complete claims')
from unnest(array['anon','authenticated']) role_name;
select ok(prosecdef and proconfig=array['search_path=""'],'worker RPCs have fixed definer search paths')
from pg_proc where oid in ('public.challenge_claim_batch_v1(uuid,integer)'::regprocedure,'public.challenge_complete_claim_v1(uuid,uuid)'::regprocedure);
select ok(pg_get_functiondef('app.challenge_session_v1()'::regprocedure) not like '%challenge_gate%' and pg_get_functiondef('app.challenge_session_v1()'::regprocedure) not like '%challenge_lock%','read validation has no gate or actor mutex');
select throws_ok($$select public.challenge_run_batch_v1(extensions.gen_random_uuid(),1)$$,'0A000','challenge_use_claim_batch','old batch API cannot silently keep a transaction open across work');
select throws_ok($$select public.challenge_claim_batch_v1(extensions.gen_random_uuid(),51)$$,'22023','challenge_invalid_batch','claim batch is bounded');
select throws_ok($$select public.challenge_complete_claim_v1(null,null)$$,'22023','challenge_invalid_claim','completion needs a challenge and token');

insert into beta_ids values('retry',pg_temp.beta_group(1,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');
create temp table p4_claim(value jsonb);
insert into p4_claim select public.challenge_claim_batch_v1(pg_temp.br(60001),1)->'claims'->0;
select is(public.challenge_claim_batch_v1(pg_temp.br(60001),1)->'claims'->0,(select value from p4_claim),'claim retry returns exactly the same lease');
select is(jsonb_array_length(public.challenge_claim_batch_v1(pg_temp.br(60002),1)->'claims'),0,'live lease is not offered to another worker');

-- Test-only failure after a lobby update would otherwise have occurred. Catching
-- it must roll the entire tick back before persisting a retry result.
create function pg_temp.p4_fail() returns trigger language plpgsql as $$
begin
 if current_setting('p4.fail',true)='on' and new.status='review' then raise exception 'synthetic failure without private details' using errcode='23514'; end if;
 return new;
end $$;
create trigger p4_failure before update on app.challenge_lobbies_v1 for each row execute function pg_temp.p4_fail();
select set_config('p4.fail','on',true);
create temp table failed_result as select public.challenge_complete_claim_v1((value->>'id')::uuid,(value->>'claim_token')::uuid) value from p4_claim;
select is((select value->>'error_code' from failed_result),'23514','item failure persists categorical SQLSTATE');
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='retry')),'scheduled','failed tick rolls back lifecycle effects');
select is((select count(*) from app.challenge_notices_v1 where challenge_id=(select id from beta_ids where name='retry')),0::bigint,'failed later transition rolls back the preceding notice insert');
select is((select state from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='retry')),'retry','failed item is scheduled for retry');
select ok((select next_attempt_at>=updated_at+interval '1.9 seconds' from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='retry')),'first failure gets bounded backoff');
select is(public.challenge_complete_claim_v1((select (value->>'id')::uuid from p4_claim),(select (value->>'claim_token')::uuid from p4_claim)),(select value from failed_result),'duplicate failed completion returns its exact result');
select is(jsonb_array_length(public.challenge_claim_batch_v1(pg_temp.br(60003),1)->'claims'),0,'backoff prevents immediate retry');
select is(public.challenge_operations_status_v1()->>'retry_count','1','retry count is visible without raw errors');

-- Expedite only synthetic retry schedules to exercise all five attempts quickly.
do $$ declare i integer; c jsonb; r jsonb;
begin
 for i in 2..5 loop
  update app.challenge_work_claims_v1 set next_attempt_at=clock_timestamp()-interval '1 second' where challenge_id=(select id from beta_ids where name='retry');
  c := public.challenge_claim_batch_v1(extensions.gen_random_uuid(),1)->'claims'->0;
  if (c->>'attempt')::integer<>i then raise exception 'wrong retry attempt'; end if;
  r := public.challenge_complete_claim_v1((c->>'id')::uuid,(c->>'claim_token')::uuid);
  if r->>'error_code'<>'23514' then raise exception 'missing expected failure'; end if;
 end loop;
end $$;
select is(public.challenge_operations_status_v1()->>'dead_letter_count','1','fifth failed attempt is dead-lettered and visible');
select is((select total_attempts from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='retry')),5::bigint,'attempts count each acquired lease');
select is(jsonb_array_length(public.challenge_claim_batch_v1(pg_temp.br(60004),50)->'claims'),0,'dead letters cannot spin on subsequent polls');
select set_config('p4.fail','off',true);
drop trigger p4_failure on app.challenge_lobbies_v1;

-- Read/review/exit behavior still uses the original rules with a dead worker.
select pg_temp.clock_beta('2026-10-20T12:00Z',false,false);
select pg_temp.login_beta(1);
select lives_ok($$select public.challenge_detail_v1((select id from beta_ids where name='retry'))$$,'safe detail works while processing and admission are paused');
select lives_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='retry'),'leave')$$,'safe exit completes despite dead-lettered worker and pause');
reset role;
set constraints all immediate;
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='retry')),'void','exit synchronously returns unsettled entries below minimum');
select is(public.challenge_operations_status_v1()->>'dead_letter_count','0','closed challenge is excluded from active dead-letter inventory');

-- Abandoned claims also have a finite retry budget, including the last lease.
select pg_temp.clock_beta('2026-10-01T12:00Z');
select pg_temp.login_beta(3);
insert into beta_ids values('abandoned',pg_temp.beta_create());
reset role;
select pg_temp.clock_beta('2026-10-20T12:00Z');
do $$ declare i integer; c jsonb;
begin
 for i in 1..5 loop
  c := public.challenge_claim_batch_v1(extensions.gen_random_uuid(),1)->'claims'->0;
  if (c->>'attempt')::integer<>i then raise exception 'wrong abandoned attempt'; end if;
  update app.challenge_work_claims_v1 set lease_expires_at=clock_timestamp()-interval '1 second' where challenge_id=(select id from beta_ids where name='abandoned');
 end loop;
end $$;
select is(public.challenge_operations_status_v1()->>'abandoned_count','1','expired last lease remains visible until recovery');
select is(jsonb_array_length(public.challenge_claim_batch_v1(pg_temp.br(60005),1)->'claims'),0,'abandoned fifth lease is retired instead of reclaimed');
select is(public.challenge_operations_status_v1()->>'dead_letter_count','1','abandoned exhaustion becomes a dead letter');

-- A transient failure can recover; its earlier response remains immutable.
select pg_temp.clock_beta('2026-10-01T12:00Z');
insert into beta_ids values('transient',pg_temp.beta_group(5,2));
select pg_temp.clock_beta('2026-10-20T12:00Z');
create trigger p4_failure before update on app.challenge_lobbies_v1 for each row execute function pg_temp.p4_fail();
select set_config('p4.fail','on',true);
create temp table transient_claim as select public.challenge_claim_batch_v1(pg_temp.br(60006),1)->'claims'->0 value;
create temp table transient_failure as select public.challenge_complete_claim_v1((value->>'id')::uuid,(value->>'claim_token')::uuid) value from transient_claim;
select is((select value->>'error_code' from transient_failure),'23514','transient item fails after prior lifecycle writes');
select set_config('p4.fail','off',true);
drop trigger p4_failure on app.challenge_lobbies_v1;
update app.challenge_work_claims_v1 set next_attempt_at=clock_timestamp()-interval '1 second' where challenge_id=(select id from beta_ids where name='transient');
select is(pg_temp.beta_run_batch(pg_temp.br(60007),1)->'processed'->0->>'status','review','scheduled retry successfully publishes the notice');
select is((select attempts from app.challenge_work_claims_v1 where challenge_id=(select id from beta_ids where name='transient')),0,'successful completion resets the consecutive failure budget');
select is(public.challenge_complete_claim_v1((select (value->>'id')::uuid from transient_claim),(select (value->>'claim_token')::uuid from transient_claim)),(select value from transient_failure),'old failed completion response remains exact after recovery');
select is((select review_by from app.challenge_notices_v1 where challenge_id=(select id from beta_ids where name='transient')),'2026-10-22T12:00Z'::timestamptz,'successful retry starts a full review period at actual notice time');
select pg_temp.clock_beta('2026-10-20T12:00Z',false,false);
select pg_temp.login_beta(5);
select lives_ok($$select pg_temp.beta_mutate((select id from beta_ids where name='transient'),'review','{"notice_revision":1,"reason":"missing_activity"}')$$,'filing a review remains safe during admission and processing pauses');
reset role;
select is((select resolve_by from app.challenge_reviews_v1 where challenge_id=(select id from beta_ids where name='transient')),'2026-10-23T12:00Z'::timestamptz,'paused-worker review keeps 72 hours from actual filing');

select * from finish();
rollback;
