begin;set search_path=public,extensions;select no_plan();
create function pg_temp.row_digest(s text,t text) returns text language plpgsql as $$declare d text;begin
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',s,t) into d;return d;
end $$;
select is(pg_temp.row_digest(schema_name,table_name),digest,schema_name||'.'||table_name||' original bytes preserved') from p6_upgrade.snapshots order by schema_name,table_name;
select ok((select count(*)>0 from app.weekly_agreements),'historical weekly agreement present');
select is((select reserved from app.challenge_community_capacity_v1 where challenge_id=(select id from p6_upgrade.ids where name='community')),2,'old community capacity backfilled');
select is((select count(*) from app.challenge_community_members_v1),2::bigint,'own revision metadata backfilled');
select is((select count(*) from app.challenge_report_scopes_v1),0::bigint,'old report not assigned invented challenge scope');
select set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000011',true);
select set_config('request.jwt.claims','{"sub":"bf000000-0000-0000-0000-000000000011","session_id":"ba000000-0000-0000-0000-000000000011"}',true);set local role authenticated;
select is(public.challenge_detail_v1((select id from p6_upgrade.ids where name='community'))->'counts'->'joined','null'::jsonb,'old community now obeys threshold privacy');
select is(public.challenge_command_v1('ba000000-0000-0000-0000-000000079002',(select payload from p6_upgrade.request))->>'revision','1','old receipt revision masked');
reset role;
select set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000020',true);
select set_config('request.jwt.claims','{"sub":"bf000000-0000-0000-0000-000000000020","session_id":"ba000000-0000-0000-0000-000000000020"}',true);set local role authenticated;
select is(jsonb_array_length(public.challenge_section_v1('history',(select value->'next_cursor' from p6_upgrade.cursor),1)->'rows'),1,'P5 cursor still resumes across migration');
select * from finish();rollback;
