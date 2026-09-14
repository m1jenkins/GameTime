-- Run once on the populated, task-owned pre-P8 database. Reuses existing fixtures.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
\ir ../../../supabase/tests/fixtures/weekly-fixture.inc
select pg_temp.make_friend(1,2);
select pg_temp.make_friend(3,5);
select pg_temp.login(1);
select public.create_personal_challenge_v2(extensions.gen_random_uuid(),'daily',100,1000,'UTC',null);
reset role;
select public.set_weekly_runtime_v1(false,false,false,'{}');
\ir ../../../supabase/tests/fixtures/challenge-fixture.inc
insert into beta_ids values('friend',pg_temp.beta_group(1,3));
select pg_temp.clock_beta('2026-10-04T12:00Z');
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='friend'),pg_temp.ba(n),20000,'complete') from generate_series(1,3)n;
select pg_temp.clock_beta('2026-10-13T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='friend'));
select pg_temp.login_beta(1);
select pg_temp.beta_mutate((select id from beta_ids where name='friend'),'review','{"notice_revision":1,"reason":"wrong_total"}');
reset role;
select public.challenge_grant_operator_v1(pg_temp.ba(40),(select id from beta_ids where name='friend'),'review','2026-10-18T12:00Z');
select public.challenge_runtime_v1(false,true,false,array(select id from public.profiles where id::text like 'bf000000-%'),'2026-10-13T12:00Z');
create schema p8_upgrade;
create table p8_upgrade.ids as select * from beta_ids;
create table p8_upgrade.saved_create as select * from app.challenge_requests_v1
 where actor_id=pg_temp.ba(1) and payload->>'op'='create' and response->>'id'=(select id::text from beta_ids where name='friend');
create table p8_upgrade.snapshots(schema_name text,table_name text,digest text,row_count bigint);
do $$ declare t record; d text; n bigint; begin
 for t in select schemaname,tablename from pg_tables where schemaname in('app','public') order by schemaname,tablename loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')),count(*) from %I.%I r',t.schemaname,t.tablename) into d,n;
  insert into p8_upgrade.snapshots values(t.schemaname,t.tablename,d,n);
 end loop;
end $$;
create table p8_upgrade.function_access as select oid,proacl,prosecdef,proconfig from pg_proc
 where oid in ('public.challenge_operator_cases_v1(uuid)'::regprocedure,'app.challenge_mutate_unmetered_v1(uuid,jsonb)'::regprocedure);
grant usage on schema p8_upgrade to authenticated;
grant select on p8_upgrade.ids,p8_upgrade.saved_create to authenticated;
commit;
