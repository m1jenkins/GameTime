-- Run on committed main, before applying the forward projection migration.
-- Only a newly owned disposable stack; intentionally committed fictional rows.
begin;
\ir weekly-fixture.inc
select pg_temp.make_friend(1,2);
select pg_temp.make_friend(3,5);
select pg_temp.login(1);
select public.create_personal_challenge_v2(extensions.gen_random_uuid(),'daily',100,1000,'UTC',null);
reset role;
select public.set_weekly_runtime_v1(false,false,false,'{}');
\ir challenge-review-monitor-fixture.inc
select public.challenge_grant_operator_v1(pg_temp.ba(40),(select id from beta_ids where name='review_a'),'review','2026-10-14T12:00Z');
select public.challenge_grant_support_v1(pg_temp.ba(31),'2026-10-14T12:00Z');
create schema review_monitor_upgrade;
create table review_monitor_upgrade.ids as select * from beta_ids;
create table review_monitor_upgrade.saved_create as select * from app.challenge_requests_v1
 where actor_id=pg_temp.ba(1) and payload->>'op'='create' and response->>'id'=(select id::text from beta_ids where name='review_a');
create table review_monitor_upgrade.snapshots(schema_name text,table_name text,digest text,row_count bigint);
do $$ declare t record; d text; n bigint; begin
 for t in select schemaname,tablename from pg_tables where schemaname in('app','public') order by schemaname,tablename loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')),count(*) from %I.%I r',t.schemaname,t.tablename) into d,n;
  insert into review_monitor_upgrade.snapshots values(t.schemaname,t.tablename,d,n);
 end loop;
end $$;
create table review_monitor_upgrade.functions as
 select oid,pg_get_functiondef(oid) definition,proacl,proconfig from pg_proc
 where pronamespace in('public'::regnamespace,'app'::regnamespace) and prokind='f';
grant usage on schema review_monitor_upgrade to authenticated;
grant select on review_monitor_upgrade.ids,review_monitor_upgrade.saved_create to authenticated;
commit;
