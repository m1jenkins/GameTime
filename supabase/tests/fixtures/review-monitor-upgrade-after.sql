-- Run after applying only the new projection migration; all checks roll back.
begin;
select no_plan();
create function pg_temp.row_digest(s text,t text) returns text language plpgsql as $$declare d text;begin
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',s,t) into d;return d;
end $$;
select is(pg_temp.row_digest(schema_name,table_name),digest,schema_name||'.'||table_name||' bytes preserved') from review_monitor_upgrade.snapshots order by schema_name,table_name;
select ok(not exists(select 1 from review_monitor_upgrade.functions old left join pg_proc p on p.oid=old.oid where p.oid is null or (old.definition,old.proacl,old.proconfig) is distinct from (pg_get_functiondef(p.oid),p.proacl,p.proconfig)),'all prior function definitions, ACLs and search paths preserved');
select is((select count(*) from app.weekly_agreements),2::bigint,'two- and five-person historical weekly agreements present');
select is((select count(*) from app.weekly_participants where accepted_at is not null),7::bigint,'historical consents retained');
select is((select count(*) from public.personal_challenge_terms),1::bigint,'historical Personal terms present');
select is(public.challenge_local_review_status_v1()->>'outstanding_review_count','3','upgrade immediately projects existing reviews');
select is(public.challenge_local_review_status_v1()->>'reviews_without_eligible_operator_count','1','upgrade evaluates exact retained review scope');
select is(public.challenge_local_review_status_v1()->>'pending_appeal_count','2','upgrade projects existing appeals');
select is(public.challenge_local_review_status_v1()->>'appeals_without_eligible_operator_count','0','upgrade evaluates retained independent support');
-- The projection itself must be read-only, including grant/worker/audit records.
select is(pg_temp.row_digest(schema_name,table_name),digest,schema_name||'.'||table_name||' unchanged by monitoring reads') from review_monitor_upgrade.snapshots order by schema_name,table_name;
set local role authenticated;
set local request.jwt.claims='{"sub":"ed000000-0000-0000-0000-000000000001","session_id":"ee000000-0000-0000-0000-000000000001"}';
select is(jsonb_array_length(public.list_my_weekly_v1()),1,'historical own weekly access remains');
select is((select count(*) from public.personal_challenge_terms),1::bigint,'historical Personal RLS access remains');
set local request.jwt.claims='{"sub":"bf000000-0000-0000-0000-000000000001","session_id":"ba000000-0000-0000-0000-000000000001"}';
select is(public.challenge_command_v1(request_id,payload),response,'prior mutation receipt replays exactly') from review_monitor_upgrade.saved_create;
select is(public.challenge_detail_v1((select id from review_monitor_upgrade.ids where name='review_a'))->>'status','review','prior participant still has own review access');
reset role;
select * from finish();
rollback;
