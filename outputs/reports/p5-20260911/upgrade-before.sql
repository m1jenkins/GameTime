begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
\ir /private/tmp/gametime-p5-20260911/GameTime/supabase/tests/fixtures/weekly-fixture.inc
select pg_temp.make_friend(1,2);
reset role;
create schema p5_upgrade_evidence;
create table p5_upgrade_evidence.old_cursor(value jsonb);
select set_config('request.jwt.claims',(select jsonb_build_object('sub',id,'session_id',session_id)::text from challenge_load_fixture.actors where ordinal=0),true);
select set_config('request.jwt.claim.sub',(select id::text from challenge_load_fixture.actors where ordinal=0),true);
grant all on p5_upgrade_evidence.old_cursor to authenticated;
grant usage on schema p5_upgrade_evidence to authenticated;
set local role authenticated;
insert into p5_upgrade_evidence.old_cursor select public.challenge_section_v1('history',null,1);
reset role;
create table p5_upgrade_evidence.snapshots(schema_name text,table_name text,digest text,row_count bigint);
do $$ declare t record; d text; n bigint; begin
 for t in select schemaname,tablename from pg_tables where schemaname in('app','public') order by schemaname,tablename loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r)-''history_revision'' order by (to_jsonb(r)-''history_revision'')::text)::text,''[]'')),count(*) from %I.%I r',t.schemaname,t.tablename) into d,n;
  insert into p5_upgrade_evidence.snapshots values(t.schemaname,t.tablename,d,n);
 end loop;
end $$;
commit;
