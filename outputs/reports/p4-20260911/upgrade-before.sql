begin;
create extension if not exists pgtap with schema extensions;
\ir /private/tmp/gametime-simplify-20260911-byc27c1u/GameTime/supabase/tests/fixtures/challenge-fixture.inc
select pg_temp.beta_group(1,2);
select pg_temp.clock_beta('2026-10-20T12:00Z');
select public.challenge_run_batch_v1('12340000-0000-0000-0000-000000000001',20);
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_worker_runs_v1 values('12340000-0000-0000-0000-000000000002','{"version":"challenge_batch_v1","limit":20}','{"processed":[],"failed_count":3}','2026-10-20T12:00Z');
\ir /private/tmp/gametime-simplify-20260911-byc27c1u/GameTime/supabase/tests/fixtures/weekly-fixture.inc
select pg_temp.make_friend(1,2);
reset role;
create schema p4_upgrade_evidence;
create table p4_upgrade_evidence.snapshots(schema_name text,table_name text,digest text,row_count bigint);
do $$ declare t record; d text; n bigint; begin
 for t in select schemaname,tablename from pg_tables where schemaname in('app','public') order by schemaname,tablename loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')),count(*) from %I.%I r',t.schemaname,t.tablename) into d,n;
  insert into p4_upgrade_evidence.snapshots values(t.schemaname,t.tablename,d,n);
 end loop;
end $$;
commit;
