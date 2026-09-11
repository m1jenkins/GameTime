begin;
set search_path=public,extensions;
select no_plan();
create function pg_temp.p4_digest(s text,t text) returns text language plpgsql as $$declare d text;begin
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',s,t) into d;return d;
end $$;
select is(pg_temp.p4_digest(schema_name,table_name),digest,schema_name||'.'||table_name||' old rows preserved') from p4_upgrade_evidence.snapshots order by schema_name,table_name;
select is((select count(*) from app.challenge_work_claims_v1),(select count(*) from app.challenge_lobbies_v1),'every old challenge has a durable coordination row');
select ok((select count(*)>0 from app.weekly_agreements),'historical weekly agreements existed before upgrade');
select ok((select count(*)>0 from app.challenge_agreements_v1),'accepted Beta agreements existed before upgrade');
select is(public.challenge_run_batch_v1('12340000-0000-0000-0000-000000000002',20),'{"processed":[],"failed_count":3}'::jsonb,'old batch receipt still returns exact content');
select is(public.challenge_operations_status_v1()->>'recent_failures','3','pre-upgrade failures stay visible');
select ok(not exists(select 1 from app.challenge_work_v1() where status='cancelled'),'old cancelled rows are excluded from new discovery');
select * from finish();
rollback;
