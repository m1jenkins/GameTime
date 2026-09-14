-- Compare old rows before any new RPC audit writes. Everything rolls back.
begin;
set search_path=public,extensions;
select no_plan();
create function pg_temp.row_digest(s text,t text) returns text language plpgsql as $$declare d text;begin
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',s,t) into d;return d;
end $$;
select is(pg_temp.row_digest(schema_name,table_name),digest,schema_name||'.'||table_name||' original bytes preserved') from p8_upgrade.snapshots order by schema_name,table_name;
select ok(not exists(select 1 from p8_upgrade.function_access old join pg_proc p on p.oid=old.oid where (old.proacl,old.prosecdef,old.proconfig) is distinct from (p.proacl,p.prosecdef,p.proconfig)),'function ACLs, definer status and search paths unchanged');
select is((select count(*) from app.weekly_agreements),2::bigint,'populated two- and five-person historical weekly agreements');
select is((select count(*) from app.weekly_participants where accepted_at is not null),7::bigint,'seven historical weekly consents present');
select is((select count(*) from public.personal_challenge_terms),1::bigint,'populated historical Personal terms');
select ok((select count(*)>0 from app.challenge_agreements_v1),'new-domain immutable agreements present');
select ok((select count(*)>0 from app.challenge_reviews_v1),'existing review cases present');
set local role authenticated;
set local request.jwt.claims='{"sub":"ed000000-0000-0000-0000-000000000001","session_id":"ee000000-0000-0000-0000-000000000001"}';
select is(jsonb_array_length(public.list_my_weekly_v1()),1,'historical own weekly access with gates off');
select is((select count(*) from public.personal_challenge_terms),1::bigint,'historical own Personal RLS access');
set local request.jwt.claims='{"sub":"bf000000-0000-0000-0000-000000000001","session_id":"ba000000-0000-0000-0000-000000000001"}';
select is(public.challenge_command_v1(request_id,payload),response,'old committed create receipt recovers exactly with gates off') from p8_upgrade.saved_create;
select is(public.challenge_detail_v1((select id from p8_upgrade.ids where name='friend'))->>'status','review','old participant retains review access');
set local request.jwt.claims='{"sub":"bf000000-0000-0000-0000-000000000040","session_id":"ba000000-0000-0000-0000-000000000040"}';
select is(public.challenge_operator_cases_v1((select id from p8_upgrade.ids where name='friend'))->0->'context'->'fact'->>'value','20000','retained authorized grant reads original normalized fact');
reset role;
select * from finish();
rollback;
