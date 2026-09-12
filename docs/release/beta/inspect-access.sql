-- P10: read-only catalog audit of the closed challenge_v1 baseline.
-- Run only on an explicitly selected/authorized database; no target is inferred.
-- psql -X -qAt -v ON_ERROR_STOP=1 ... -f docs/release/beta/inspect-access.sql
-- Output is JSON. A successful query is NOT acceptance: inspect violations.
-- No tokens, actor IDs, request bodies, Health facts or job commands are emitted.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '15s';
set local lock_timeout = '2s';
set local search_path = pg_catalog;
with expected(name,role_name) as (
 select unnest(array[
 'challenge_abandon_v1','challenge_access_status_v1','challenge_appeal_v1',
 'challenge_block_v1','challenge_command_v1','challenge_community_catalog_v1',
 'challenge_confirm_age_v1','challenge_detail_v1','challenge_issue_link_v1',
 'challenge_join_community_v1','challenge_list_v1','challenge_mutate_v1',
 'challenge_operator_action_v1','challenge_operator_cases_v1','challenge_operator_close_v1',
 'challenge_operator_reports_v1','challenge_own_appeals_v1','challenge_personal_preview_v1',
 'challenge_preview_v1','challenge_redeem_link_v1','challenge_report_scoped_v1',
 'challenge_report_v1','challenge_resolve_appeal_v1','challenge_revoke_link_v1',
 'challenge_section_v1','challenge_stop_command_v1','challenge_support_appeals_v1',
 'challenge_support_reports_v1','challenge_support_suspend_v1'
 ]),'authenticated'
 union all
 select unnest(array[
 'challenge_capture_community_snapshot_v1','challenge_capture_fixture_v1',
 'challenge_claim_batch_v1','challenge_complete_claim_v1','challenge_discovery_fixture_v1',
 'challenge_grant_operator_v1','challenge_grant_support_v1','challenge_operations_status_v1',
 'challenge_process_v1','challenge_publish_community_fixture_v1','challenge_readiness_fixture_v1',
 'challenge_readiness_metric_fixture_v1','challenge_resolve_v1','challenge_revoke_operator_v1',
 'challenge_revoke_support_v1','challenge_run_batch_v1','challenge_runtime_v1'
 ]),'service_role'
), functions as (
 select p.*, n.nspname, p.oid::regprocedure::text as signature,
  exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   where a.grantee=0 and a.privilege_type='EXECUTE') public_execute
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('app','public') and starts_with(p.proname,'challenge_')
), relations as (
 select c.*,n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('app','public') and starts_with(c.relname,'challenge_')
 and c.relkind in ('r','p','v','m','S')
), roles(role_name) as (values ('anon'),('authenticated'),('service_role')),
violations(reason,object) as (
 select 'unexpected or overloaded public challenge RPC',f.signature from functions f
 where f.nspname='public' and
 (not exists(select 1 from expected e where e.name=f.proname)
 or (select count(*) from functions other where other.nspname='public' and other.proname=f.proname)<>1)
 union all
 select 'missing expected RPC',e.name from expected e where not exists
 (select 1 from functions f where f.nspname='public' and f.proname=e.name)
 union all
 select 'incorrect effective RPC privilege for '||r.role_name,f.signature
 from functions f cross join roles r left join expected e on e.name=f.proname
 where has_function_privilege(r.role_name,f.oid,'EXECUTE') is distinct from
 (f.nspname='public' and coalesce(r.role_name=e.role_name,false))
 union all
 select 'PUBLIC execute privilege',signature from functions where public_execute
 union all
 select 'public RPC missing definer or fixed empty search_path',signature from functions
 where nspname='public' and (not prosecdef or not coalesce('search_path=""'=any(proconfig),false))
 union all
 select 'direct relation privilege for '||r.role_name,c.nspname||'.'||c.relname
 from relations c cross join roles r where case when c.relkind='S'
 then has_sequence_privilege(r.role_name,c.oid,'USAGE,SELECT,UPDATE')
 else has_table_privilege(r.role_name,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') end
 union all
 select 'table without RLS',nspname||'.'||relname from relations
 where relkind in ('r','p') and not relrowsecurity
 union all
 select 'challenge relation in exposed public schema',nspname||'.'||relname from relations where nspname='public'
 union all
 select 'runtime absent or not singleton','app.challenge_runtime_v1'
 where (select count(*) from app.challenge_runtime_v1)<>1
 union all
 select 'runtime is not fully closed','app.challenge_runtime_v1' from app.challenge_runtime_v1
 where admission or fixtures or processing or discovery or ingestion or steps_source or exercise_source
 or distance_source or timed_source or analytics or cardinality(actors)<>0 or fictional_now is not null
 union all
 select 'challenge cron job exists',jobname from cron.job where command ilike '%challenge_%' or jobname ilike '%challenge%'
)
select jsonb_pretty(jsonb_build_object(
 'scope','P10 closed local baseline; not hosted acceptance',
 'migration_count',(select count(*) from supabase_migrations.schema_migrations),
 'migration_head',(select max(version) from supabase_migrations.schema_migrations),
 'violations',coalesce((select jsonb_agg(to_jsonb(v) order by reason,object) from violations v),'[]'),
 'challenge_rpc_inventory',(select jsonb_agg(jsonb_build_object('signature',f.signature,
   'intended_local_role',e.role_name,'anon',has_function_privilege('anon',f.oid,'EXECUTE'),
   'authenticated',has_function_privilege('authenticated',f.oid,'EXECUTE'),
   'service_role',has_function_privilege('service_role',f.oid,'EXECUTE')) order by f.signature)
   from functions f left join expected e on e.name=f.proname where f.nspname='public'),
 'private_helper_count',(select count(*) from functions where nspname='app'),
 'private_relation_count',(select count(*) from relations where nspname='app'),
 'runtime',(select (to_jsonb(r)-'actors'-'fictional_now')||jsonb_build_object(
   'actor_allowlist_empty',cardinality(actors)=0,'fictional_clock_absent',fictional_now is null)
   from app.challenge_runtime_v1 r),
 'legacy_cron_inventory',(select jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'active',active) order by jobname) from cron.job),
 'other_public_function_inventory',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
   'anon',has_function_privilege('anon',p.oid,'EXECUTE'),
   'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
   'service_role',has_function_privilege('service_role',p.oid,'EXECUTE')) order by p.oid::regprocedure::text)
   from pg_proc p where p.pronamespace='public'::regnamespace and not starts_with(p.proname,'challenge_')),
 'exposure_note','Database grants are not the Data API schema allowlist. Verify actual hosted schemas and HTTP denial separately. Legacy API inventory requires its own deployment allowlist.'
));
rollback;
