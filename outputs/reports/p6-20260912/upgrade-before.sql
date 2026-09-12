begin;create extension if not exists pgtap with schema extensions;set search_path=public,extensions;
\ir /private/tmp/gametime-p6-20260912/GameTime/supabase/tests/fixtures/weekly-fixture.inc
select pg_temp.make_friend(1,2);reset role;
\ir /private/tmp/gametime-p6-20260912/GameTime/supabase/tests/fixtures/challenge-fixture.inc
insert into beta_ids values('friend',pg_temp.beta_group(1,3));
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(79000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
select pg_temp.login_beta(10);
select public.challenge_join_community_v1(pg_temp.br(79001),jsonb_build_object('op','join_community','id',(select id from beta_ids where name='community'),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
select pg_temp.login_beta(11);
select public.challenge_join_community_v1(pg_temp.br(79002),jsonb_build_object('op','join_community','id',(select id from beta_ids where name='community'),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
select public.challenge_report_v1(pg_temp.br(79003),pg_temp.ba(10),'username');
select pg_temp.login_beta(20);
insert into beta_ids values('history1',pg_temp.beta_create());
select pg_temp.beta_mutate((select id from beta_ids where name='history1'),'cancel');
insert into beta_ids values('history2',pg_temp.beta_create());
select pg_temp.beta_mutate((select id from beta_ids where name='history2'),'cancel');
reset role;
create schema p6_upgrade;
create table p6_upgrade.ids as select * from beta_ids;
create table p6_upgrade.cursor(value jsonb);
create table p6_upgrade.request as select payload from app.challenge_requests_v1 where request_id=pg_temp.br(79002);
grant select on p6_upgrade.request to authenticated;
grant usage on schema p6_upgrade to authenticated;
grant select,insert on p6_upgrade.cursor to authenticated;
grant select on p6_upgrade.ids to authenticated;
select pg_temp.login_beta(20);
insert into p6_upgrade.cursor select public.challenge_section_v1('history',null,1);
reset role;
create table p6_upgrade.snapshots(schema_name text,table_name text,digest text,row_count bigint);
do $$ declare t record; d text; n bigint; begin
 for t in select schemaname,tablename from pg_tables where schemaname in('app','public') order by schemaname,tablename loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')),count(*) from %I.%I r',t.schemaname,t.tablename) into d,n;
  insert into p6_upgrade.snapshots values(t.schemaname,t.tablename,d,n);
 end loop;
end $$;commit;
