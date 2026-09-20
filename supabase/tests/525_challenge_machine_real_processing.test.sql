begin;
select no_plan();

-- The synthetic source rows, clock override, Vault secrets and pg_net requests
-- all roll back. In particular pg_net cannot send an uncommitted request.
insert into auth.users(id) values
 ('bf000000-0000-0000-0000-000000052501'),
 ('bf000000-0000-0000-0000-000000052502'),
 ('bf000000-0000-0000-0000-000000052503');
insert into public.profiles(id,handle,display_name,timezone) values
 ('bf000000-0000-0000-0000-000000052501','machine_real_52501','Machine Real Test','UTC'),
 ('bf000000-0000-0000-0000-000000052502','machine_real_52502','Machine Real Test','UTC'),
 ('bf000000-0000-0000-0000-000000052503','machine_real_52503','Machine Real Test','UTC');
insert into auth.sessions(id,user_id) values
 ('ba000000-0000-0000-0000-000000052501','bf000000-0000-0000-0000-000000052501'),
 ('ba000000-0000-0000-0000-000000052502','bf000000-0000-0000-0000-000000052502');

create temp table machine_real_ids as select
 'bf000000-0000-0000-0000-000000052501'::uuid actor_a,
 'bf000000-0000-0000-0000-000000052502'::uuid actor_b,
 'bf000000-0000-0000-0000-000000052503'::uuid reviewer,
 'ba000000-0000-0000-0000-000000052501'::uuid session_a,
 'be000000-0000-0000-0000-000000052501'::uuid notice_id,
 'be000000-0000-0000-0000-000000052502'::uuid expired_id,
 'be000000-0000-0000-0000-000000052503'::uuid failure_id,
 clock_timestamp()-interval '1 hour' starts_at,
 clock_timestamp()+interval '1 hour' ends_at;

create function pg_temp.make_machine_real(p_id uuid) returns void language plpgsql as $$
declare r machine_real_ids; digest text;
begin
 select * into r from machine_real_ids;
 insert into app.challenge_lobbies_v1
  (id,creator_id,policy,config,starts_at,ends_at,status,revision,agreement_version,created_at,minimum,capacity)
 values(p_id,r.actor_a,'friend_steps_goal_v1','{"amount_cents":100}',r.starts_at,r.ends_at,'active',1,1,r.starts_at,2,6);
 update app.challenge_lobbies_v1 set real_source_policy_version='apple_watch_steps_v1' where id=p_id;
 insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
 values(p_id,r.actor_a,true,100),(p_id,r.actor_b,true,100);
 insert into app.challenge_slots_v1(challenge_id,actor_id,mode,metric,starts_at,ends_at)
 values(p_id,r.actor_a,'friend','steps',r.starts_at,r.ends_at),
       (p_id,r.actor_b,'friend','steps',r.starts_at,r.ends_at);
 insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
 values(p_id,1,'{"metric":"steps","policy":"friend_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"}'::jsonb
  ||jsonb_build_object('config',jsonb_build_object('starts_at',r.starts_at,'ends_at',r.ends_at)),r.starts_at);
 select a.digest into digest from app.challenge_agreements_v1 a where a.challenge_id=p_id and a.version=1;
 insert into app.challenge_consents_v1(challenge_id,version,actor_id,digest,recorded_at)
 values(p_id,1,r.actor_a,digest,clock_timestamp()),(p_id,1,r.actor_b,digest,clock_timestamp());
 insert into app.challenge_real_health_admissions_v1
  (challenge_id,actor_id,agreement_version,terms_digest,source_policy_version,metric,window_starts_at,window_ends_at,admitted_at)
 values(p_id,r.actor_a,1,digest,'apple_watch_steps_v1','steps',r.starts_at,r.ends_at,clock_timestamp()),
       (p_id,r.actor_b,1,digest,'apple_watch_steps_v1','steps',r.starts_at,r.ends_at,clock_timestamp());
 insert into app.challenge_real_health_facts_v1
  (challenge_id,actor_id,agreement_version,revision,previous_revision,state,value,observed_at,queried_through_at,recorded_at,request_id)
 values(p_id,r.actor_a,1,1,null,'value',100,clock_timestamp()-interval '1 second',clock_timestamp()-interval '30 seconds',clock_timestamp(),extensions.gen_random_uuid()),
       (p_id,r.actor_b,1,1,null,'value',200,clock_timestamp()-interval '1 second',clock_timestamp()-interval '30 seconds',clock_timestamp(),extensions.gen_random_uuid());
end $$;

create or replace function app.challenge_real_health_now_v1()
returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('test.p11_machine_now',true),'')::timestamptz,clock_timestamp())
$$;
select public.challenge_runtime_v1(false,false,false,'{}'::uuid[],null);
select public.challenge_real_health_runtime_v1(true,true,true);
select set_config('test.p11_machine_now',(ends_at+interval '48 hours 1 second')::text,true) from machine_real_ids;
update app.challenge_schedule_config_v1 set edge_base_url='http://127.0.0.1:65534/functions/v1',
 worker_secret_id=vault.create_secret(repeat('w',32),'p11-machine-real-worker'),
 monitor_secret_id=vault.create_secret(repeat('m',32),'p11-machine-real-monitor'),worker_enabled=true;

-- A real fact reaches a notice through Cron preparation and the new fixed
-- dispatch/complete/finish RPCs. No fictional fact or fixture gate is used.
select pg_temp.make_machine_real((select notice_id from machine_real_ids));
select app.challenge_cron_tick_v1('worker');
create temp table machine_notice_run as
 select invocation_id from app.challenge_machine_runs_v1 where kind='worker' and state='pending';
create temp table machine_notice_dispatch as
 select public.challenge_machine_worker_dispatch_v1((select invocation_id from machine_notice_run),
  'ba000000-0000-0000-0000-000000052511') value;
select is((select value->>'status' from machine_notice_dispatch),'running','real source is dispatched by the fixed machine RPC');
select is(jsonb_array_length((select value->'claims' from machine_notice_dispatch)),1,'only the due real challenge is claimed');
create temp table machine_notice_receipt as
 select public.challenge_machine_complete_v1((select invocation_id from machine_notice_run),
  'ba000000-0000-0000-0000-000000052511',
  ((select value->'claims'->0->>'id' from machine_notice_dispatch)::uuid),
  ((select value->'claims'->0->>'claim_token' from machine_notice_dispatch)::uuid)) value;
select is((select value->>'status' from machine_notice_receipt),'review','machine completion writes the real provisional notice');
select public.challenge_real_health_runtime_v1(true,true,false);
select is(public.challenge_machine_complete_v1((select invocation_id from machine_notice_run),
 'ba000000-0000-0000-0000-000000052511',
 ((select value->'claims'->0->>'id' from machine_notice_dispatch)::uuid),
 ((select value->'claims'->0->>'claim_token' from machine_notice_dispatch)::uuid)),
 (select value from machine_notice_receipt),'paused processing still replays the exact committed receipt');
select is(public.challenge_machine_finish_v1((select invocation_id from machine_notice_run),
 'ba000000-0000-0000-0000-000000052511')->>'status','completed','machine finish sees the committed item receipt');
select ok((select bool_and(review_by-recorded_at=interval '48 hours')
 from app.challenge_notices_v1 where challenge_id=(select notice_id from machine_real_ids)),
 'review window starts at the actual notice, not the scheduled deadline');
select ok(not exists(select 1 from app.challenge_facts_v1 where challenge_id=(select notice_id from machine_real_ids)),
 'the machine path never synthesizes a fictional fact');

-- Pausing real processing stops fresh machine dispatch, while the participant
-- can still file a review and its full resolution window remains available.
select set_config('test.p11_machine_review',jsonb_build_object('op','review','id',id,'revision',revision,
 'notice_revision',1,'reason','wrong_total')::text,true)
 from app.challenge_lobbies_v1 where id=(select notice_id from machine_real_ids);
select set_config('request.jwt.claim.sub',(select actor_a::text from machine_real_ids),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select actor_a from machine_real_ids),
 'session_id',(select session_a from machine_real_ids))::text,true);
select set_config('role','authenticated',true);
select lives_ok($$select public.challenge_mutate_v1('ba000000-0000-0000-0000-000000052512',
 current_setting('test.p11_machine_review')::jsonb)$$,'participant can request review while processing is paused');
select set_config('role','none',true);
select ok((select bool_and(resolve_by-filed_at=interval '72 hours')
 from app.challenge_reviews_v1 where challenge_id=(select notice_id from machine_real_ids)),
 'review resolution keeps 72 hours from the actual filing');
select lives_ok($$select public.challenge_resolve_v1((select id from app.challenge_reviews_v1
 where challenge_id=(select notice_id from machine_real_ids)),
 (select reviewer from machine_real_ids),'exclude')$$,'safe review resolution remains available during processing pause');
select is((select count(*) from app.challenge_finals_v1 where challenge_id=(select notice_id from machine_real_ids)),
 0::bigint,'pause cannot force an early final result');

-- Expire the wall-clock item and run leases in rollback-owned rows. The saved
-- response carries the same expired item lease, as it would after 60 seconds.
select public.challenge_real_health_runtime_v1(true,true,true);
select pg_temp.make_machine_real((select expired_id from machine_real_ids));
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '61 seconds' where kind='worker';
select app.challenge_cron_tick_v1('worker');
create temp table machine_expired_first as
 select invocation_id from app.challenge_machine_runs_v1 where kind='worker' and state='pending';
create temp table machine_expired_claim as
 select public.challenge_machine_worker_dispatch_v1((select invocation_id from machine_expired_first),
  'ba000000-0000-0000-0000-000000052521') value;
select is(jsonb_array_length((select value->'claims' from machine_expired_claim)),1,'expiring real work has one first claim');
update app.challenge_work_claims_v1 set lease_expires_at=clock_timestamp()-interval '1 second'
 where challenge_id=(select expired_id from machine_real_ids);
update app.challenge_worker_invocations_v1 set claim_response=jsonb_set(claim_response,
 '{claims,0,lease_expires_at}',to_jsonb((clock_timestamp()-interval '1 second')::text))
 where id=(select invocation_id from machine_expired_first);
update app.challenge_machine_runs_v1 set lease_expires_at=clock_timestamp()-interval '1 second'
 where invocation_id=(select invocation_id from machine_expired_first);
update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '61 seconds' where kind='worker';
select app.challenge_cron_tick_v1('worker');
select is((select state from app.challenge_machine_runs_v1 where invocation_id=(select invocation_id from machine_expired_first)),
 'finished','Cron retires the expired invocation before preparing another');
select throws_ok($$select public.challenge_machine_complete_v1((select invocation_id from machine_expired_first),
 'ba000000-0000-0000-0000-000000052521',(select expired_id from machine_real_ids),
 ((select value->'claims'->0->>'claim_token' from machine_expired_claim)::uuid))$$,
 '55000','challenge_stale_machine_run','old machine fence cannot complete expired work');
create temp table machine_expired_second as
 select invocation_id from app.challenge_machine_runs_v1 where kind='worker' and state='pending';
create temp table machine_expired_reclaim as
 select public.challenge_machine_worker_dispatch_v1((select invocation_id from machine_expired_second),
  'ba000000-0000-0000-0000-000000052522') value;
select is(((select value->'claims'->0->>'attempt' from machine_expired_reclaim)::integer),2,
 'fresh Cron invocation reclaims the item with bounded attempt two');
select isnt((select value->'claims'->0->>'claim_token' from machine_expired_reclaim),
 (select value->'claims'->0->>'claim_token' from machine_expired_claim),
 'reclaimed real work receives a new item fence');
select public.challenge_machine_complete_v1((select invocation_id from machine_expired_second),
 'ba000000-0000-0000-0000-000000052522',(select expired_id from machine_real_ids),
 ((select value->'claims'->0->>'claim_token' from machine_expired_reclaim)::uuid));
select is(public.challenge_machine_finish_v1((select invocation_id from machine_expired_second),
 'ba000000-0000-0000-0000-000000052522')->>'status','completed',
 'reclaimed real work completes once under the new fence');
select is((select count(*) from app.challenge_notices_v1 where challenge_id=(select expired_id from machine_real_ids)),
 1::bigint,'the expired first claim did not create a duplicate notice');

-- A selected real item fails after the lifecycle subtransaction starts. Only
-- categorical receipts persist; five new invocations exhaust the item limit.
select pg_temp.make_machine_real((select failure_id from machine_real_ids));
create function pg_temp.machine_fail_review() returns trigger language plpgsql as $$
begin
 if new.id=(select failure_id from machine_real_ids) and new.status='review' then
  raise exception 'synthetic private machine failure' using errcode='23514';
 end if;
 return new;
end $$;
create trigger machine_real_failure before update on app.challenge_lobbies_v1
 for each row execute function pg_temp.machine_fail_review();
do $$
declare i integer; inv uuid; run_token uuid; claim jsonb; result jsonb; summary jsonb;
begin
 for i in 1..5 loop
  if i>1 then
   update app.challenge_work_claims_v1 set next_attempt_at=clock_timestamp()-interval '1 second'
    where challenge_id=(select failure_id from machine_real_ids);
  end if;
  update app.challenge_schedule_ticks_v1 set last_queued_at=clock_timestamp()-interval '61 seconds' where kind='worker';
  perform app.challenge_cron_tick_v1('worker');
  select invocation_id into inv from app.challenge_machine_runs_v1 where kind='worker' and state='pending';
  run_token:=('ba000000-0000-0000-0000-'||lpad((52530+i)::text,12,'0'))::uuid;
  claim:=public.challenge_machine_worker_dispatch_v1(inv,run_token)->'claims'->0;
  if claim is null or (claim->>'id')::uuid<>(select failure_id from machine_real_ids)
     or (claim->>'attempt')::integer<>i then raise exception 'wrong real failure claim at attempt %',i; end if;
  result:=public.challenge_machine_complete_v1(inv,run_token,(claim->>'id')::uuid,(claim->>'claim_token')::uuid);
  if result->>'error_code'<>'23514' or result::text like '%synthetic private%' then
   raise exception 'missing categorical real failure receipt at attempt %',i;
  end if;
  summary:=public.challenge_machine_finish_v1(inv,run_token);
  if summary->>'status'<>'failed' then raise exception 'machine did not report failed attempt %',i; end if;
 end loop;
end $$;
drop trigger machine_real_failure on app.challenge_lobbies_v1;
select is((select state from app.challenge_work_claims_v1 where challenge_id=(select failure_id from machine_real_ids)),
 'dead','five real machine failures produce one dead-letter item');
select is((select total_attempts from app.challenge_work_claims_v1 where challenge_id=(select failure_id from machine_real_ids)),
 5::bigint,'dead-letter bound is exactly five item attempts');
select ok(not exists(select 1 from app.challenge_notices_v1 where challenge_id=(select failure_id from machine_real_ids)),
 'failed lifecycle attempts commit no partial notice');
select ok(public.challenge_machine_monitor_v1()::text not like '%synthetic private machine failure%'
 and public.challenge_machine_monitor_v1()::text not like '%'||(select failure_id::text from machine_real_ids)||'%',
 'monitor output omits raw failure text and item identity');

select * from finish();
rollback;
