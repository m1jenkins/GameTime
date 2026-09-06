-- Fixture mirrors scripts/examples/performance-lifecycle-setup.sql; the CLI mounts only this test file.
-- Rollback-only shared fixture for SQL and the actual evaluator/worker smoke.
-- Every timestamp below is a fictional clock injection, not elapsed operation.
begin;
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('e7100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('e7200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated','session_id',pg_temp.req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,30) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.actor(n),'lifecyclefixture'||n,'Fictional Runner','UTC' from generate_series(1,30) n;
insert into auth.sessions(id,user_id) select pg_temp.req(n),pg_temp.actor(n) from generate_series(1,30) n;
select public.set_performance_commitment_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,29) n));
select public.set_commitment_attempts_enabled_v1(true);
create temp table saved(name text primary key,value jsonb);
grant select,insert,update on saved to authenticated;
create function pg_temp.id(n integer) returns uuid language sql as $$select (value->>0)::uuid from saved where name='c'||n$$;
create function pg_temp.attempt(q text) returns text language plpgsql as $$ begin
 execute q; return 'ok'; exception when others then return sqlstate; end; $$;
create function pg_temp.terms(a uuid,s timestamptz,d timestamptz) returns jsonb language sql security definer set search_path='' as $$select app.performance_commitment_terms_v1(a,360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')$$;
create function pg_temp.prepare(n integer) returns uuid language plpgsql as $$
declare c uuid; t jsonb; s timestamptz:='2026-05-02T12:00:00.123456Z'; d timestamptz:='2026-07-01T12:00:00.123456Z'; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 t:=pg_temp.terms(auth.uid(),s,d);
 c:=pg_temp.create_at(pg_temp.req(100+n),t);
 perform set_config('role','none',true);
 insert into saved values('c'||n,jsonb_build_array(c));
 perform public.set_commitment_attempt_reviewer_v1(pg_temp.req(200+n),c,pg_temp.actor(30),true);
 perform public.set_commitment_lifecycle_operator_v1(pg_temp.req(300+n),c,pg_temp.actor(30),'review',clock_timestamp()+interval '6 days');
 return c;
end; $$;
-- Private helpers remain owned by postgres and use explicit role checks in RPCs.
-- SECURITY DEFINER permits only the test clock seam while current role is authenticated.
create function pg_temp.create_at(q uuid,t jsonb) returns uuid language sql security definer set search_path='' as $$
 select app.create_performance_commitment_at_v1(q,360,(t->>'starts_at')::timestamptz,(t->>'deadline_at')::timestamptz,
 'America/Chicago','performance-commitment-fixture-5k-v1',encode(extensions.digest(t::text,'sha256'),'hex'),true,'2026-05-01T12:00:00.123456Z')$$;
-- Replace the direct private call above with this clock wrapper for role realism.
create function pg_temp.nominate_at(q uuid,c uuid,e uuid) returns uuid language sql security definer set search_path='' as $$
 select app.nominate_commitment_attempt_at_v1(q,c,e,'bib-1','2026-05-01T13:00:00.123456Z')$$;
create function pg_temp.review_at(q uuid,c uuid,s uuid,r integer,t timestamptz) returns integer language sql security definer set search_path='' as $$
 select app.review_commitment_attempt_at_v1(q,c,s,r,true,t)$$;
create function pg_temp.proof(n integer,slot integer,seconds integer,t timestamptz default '2026-06-01T12:00:00.123456Z',missing boolean default false)
returns integer language plpgsql as $$
declare c uuid:=pg_temp.id(n); e uuid:=pg_temp.req(1000+n*10+slot); a uuid; s uuid:=extensions.gen_random_uuid(); r integer; doc jsonb;
begin
 select id into a from app.performance_attempt_nominations where commitment_id=c and event_id=e;
 if a is null then
   perform public.curate_commitment_fixture_event_v1(e,'2026-05-03T12:00:00.123456Z','2026-05-03T14:00:00.123456Z');
   perform pg_temp.login(n); perform set_config('role','authenticated',true);
   a:=pg_temp.nominate_at(e,c,e); perform set_config('role','none',true);
 end if;
 doc:=jsonb_build_object('source','fixture_official_5k_v1','event_id',e,'distance_meters',5000,'timing_basis','organizer_chip',
 'precision_ms',1000,'published_bib','bib-1','status',case when missing then 'missing' when seconds=0 then 'dnf' else 'finished' end,
 'chip_seconds',case when seconds=0 or missing then null else seconds end,
 'started_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz end,
 'finished_at',case when seconds=0 or missing then null else '2026-05-03T12:00:00.123456Z'::timestamptz+seconds*interval '1 second' end);
 perform app.capture_commitment_attempt_at_v1(s,c,a,doc,t);
 select max(revision) into r from app.performance_attempt_revisions where commitment_id=c and attempt_id=a;
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.get_commitment_attempt_source_v1(c,s);
 r:=pg_temp.review_at(s,c,s,r,t);
 perform set_config('role','none',true); return r;
end; $$;
create function pg_temp.confirm_at(q uuid,c uuid,ids uuid[]) returns uuid language sql security definer set search_path='' as $$
 select app.confirm_commitment_attempt_set_at_v1(q,c,ids,true,'2026-07-01T12:00:00.123456Z')$$;
create function pg_temp.confirm(n integer) returns uuid language plpgsql as $$ declare ids uuid[]; c uuid:=pg_temp.id(n); begin
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into ids from app.performance_attempt_nominations where commitment_id=c;
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 perform pg_temp.confirm_at(pg_temp.req(400+n),c,ids); perform set_config('role','none',true); return c;
end; $$;
create function pg_temp.file_at(q uuid,c uuid,r integer,reason text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_case_at_v1(q,c,r,reason,t)$$;
create function pg_temp.file(n integer,r integer,t timestamptz,q integer default 500) returns uuid language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.file_at(pg_temp.req(q+n),pg_temp.id(n),r,'wrong_result',t);
 perform set_config('role','none',true); return (result->>'case_id')::uuid;
end; $$;
create function pg_temp.resolve_at(q uuid,k uuid,d text,t timestamptz) returns jsonb language sql security definer set search_path='' as $$
 select app.performance_lifecycle_resolve_at_v1(q,k,d,t)$$;
create function pg_temp.resolve(n integer,k uuid,d text,t timestamptz) returns jsonb language plpgsql as $$ declare result jsonb; begin
 perform pg_temp.login(30); perform set_config('role','authenticated',true);
 perform public.read_commitment_lifecycle_operator_v1(pg_temp.id(n),'review');
 result:=pg_temp.resolve_at(pg_temp.req(600+n),k,d,t);
 perform set_config('role','none',true); return result;
end; $$;
create function pg_temp.exit_at(q uuid,c uuid,d text,t timestamptz) returns uuid language sql security definer set search_path='' as $$
 select app.close_performance_commitment_at_v1(q,c,d,t)$$;
create function pg_temp.exit(n integer,d text,t timestamptz) returns uuid language plpgsql as $$ declare result uuid; begin
 perform pg_temp.login(n); perform set_config('role','authenticated',true);
 result:=pg_temp.exit_at(pg_temp.req(700+n),pg_temp.id(n),d,t);
 perform set_config('role','none',true); return result;
end; $$;

select no_plan();
select is((select enabled from app.performance_lifecycle_runtime),false,'lifecycle defaults off');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app'
  and c.relname like 'performance_lifecycle_%' and c.relkind='r' and c.relrowsecurity),12::bigint,'all twelve tables use RLS');
select ok(not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),r||' cannot access '||c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and c.relname like 'performance_lifecycle_%' and c.relkind='r';
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot call private '||p.proname)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and p.proname like '%performance_lifecycle%v1';
set local role anon;
select throws_ok('select public.get_commitment_lifecycle_v1(null)','42501',null,'anonymous history denied');
select throws_ok('select public.load_commitment_lifecycle_v1(null)','42501',null,'anonymous snapshot denied');
reset role;
select public.set_commitment_lifecycle_enabled_v1(true);
select pg_temp.prepare(1);
select pg_temp.prepare(2);
select pg_temp.prepare(3);
select pg_temp.prepare(4);
select pg_temp.prepare(5);
select public.set_commitment_lifecycle_enabled_v1(false);
select throws_ok('select public.load_commitment_lifecycle_v1(pg_temp.id(1))','42501',null,'worker gate off');
select pg_temp.login(1);
set local role authenticated;
select lives_ok('select public.get_commitment_lifecycle_v1(pg_temp.id(1))','owner reads empty history gate off');
select throws_ok('select public.load_commitment_lifecycle_v1(pg_temp.id(1))','42501',null,'owner cannot load private proof');
select throws_ok('select public.commit_commitment_lifecycle_v1(null,null)','42501',null,'owner cannot commit outcome');
select throws_ok('select public.settle_commitment_simulation_v1(pg_temp.id(1))','42501',null,'owner cannot settle');
select throws_ok('select public.set_commitment_lifecycle_enabled_v1(true)','42501',null,'owner cannot enable worker');
select throws_ok('select public.get_commitment_lifecycle_v1(pg_temp.id(2))','42501',null,'other owner history private');
select throws_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''review'')','42501',null,'owner cannot independently review');
reset role;
set local role service_role;
select throws_ok('select public.get_commitment_lifecycle_v1(null)','42501',null,'service cannot impersonate owner');
reset role;
select public.set_commitment_lifecycle_enabled_v1(true);
create function pg_temp.decision(c uuid,phase text,rev integer default 0,kind text default 'inconclusive',reason text default 'unresolved_proof') returns jsonb
 language sql as $$select jsonb_build_object('version','performance-fixture-official-5k-v1','commitmentId',c,'termsDigest',terms_digest,
 'proofRevision',rev,'phase',phase,'outcome',case when phase in ('provisional','ready_to_finalize') then jsonb_build_object('kind',kind,'reason',reason) else 'null'::jsonb end,
 'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false) from app.performance_commitment_agreements where id=c$$;
create function pg_temp.tick(n integer,t timestamptz,phase text,rev integer default 0,kind text default 'inconclusive',reason text default 'unresolved_proof') returns text
 language sql as $$select app.performance_lifecycle_commit_at_v1(app.performance_lifecycle_load_at_v1(pg_temp.id(n),t),pg_temp.decision(pg_temp.id(n),phase,rev,kind,reason),t)$$;
select is(pg_temp.tick(1,'2026-05-01T13:00:00.123456Z','scheduled'),'scheduled','scheduled returns without result');
select is(pg_temp.tick(1,'2026-05-02T12:00:00.123456Z','active'),'active','activation at start');
select is((select count(*) from app.performance_lifecycle_activations where commitment_id=pg_temp.id(1)),1::bigint,'one activation');
select is(pg_temp.tick(1,'2026-07-01T12:00:00.123456Z','awaiting_proof'),'awaiting_proof','deadline alone creates no result');
select is((select count(*) from app.performance_commitment_enrollments where commitment_id=pg_temp.id(1) and released_at is null),1::bigint,'deadline keeps slot');
select throws_ok('select public.settle_commitment_simulation_v1(pg_temp.id(1))','55000',null,'no simulation before final');
insert into saved values('stale',app.performance_lifecycle_load_at_v1(pg_temp.id(1),'2026-07-04T12:00:00.123455Z'));
select is(app.performance_lifecycle_commit_at_v1((select value from saved where name='stale'),pg_temp.decision(pg_temp.id(1),'awaiting_proof'),'2026-07-04T12:00:00.123456Z'),'stale','microsecond clock boundary');
select is(pg_temp.tick(1,'2026-07-04T12:00:00.123456Z','provisional'),'provisional','durable notice saved');
select is(app.performance_lifecycle_commit_at_v1((select value from saved where name='stale'),pg_temp.decision(pg_temp.id(1),'awaiting_proof'),'2026-07-04T12:00:00.123456Z'),'stale','notice invalidates old snapshot');
select is(pg_temp.tick(1,'2026-07-05T12:00:00.123456Z','provisional'),'provisional','notice exact retry');
select is((select recorded_at from app.performance_lifecycle_notices where commitment_id=pg_temp.id(1)),'2026-07-04T12:00:00.123456Z'::timestamptz,'notice timestamp never reset');
select pg_temp.login(1);
set local role authenticated;
select ok(not public.get_commitment_lifecycle_v1(pg_temp.id(1))::text ~ 'published_bib|document|grant_id|operator_id|terms_digest|note','owner projection redacted');
select throws_ok('select public.file_commitment_review_v1(null,pg_temp.id(1),0,''wrong_result'')','22023',null,'request required');
select throws_ok('select pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),0,null,''2026-07-05T12:00:00.123456Z'')','22023',null,'reason required');
select throws_ok('select pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),1,''wrong_result'',''2026-07-05T12:00:00.123456Z'')','55000',null,'notice required for revision');
select throws_ok('select pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),0,''wrong_result'',''2026-07-11T12:00:00.123456Z'')','55000',null,'filing closes at exact full seven days');
reset role;
select public.set_commitment_lifecycle_enabled_v1(false);
select pg_temp.login(1);
set local role authenticated;
insert into saved values('case',pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),0,'wrong_result','2026-07-11T12:00:00.123455Z'));
select is(pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),0,'wrong_result','2026-07-30T12:00:00.123456Z'),(select value from saved where name='case'),'case recovery gate off ignores retry clock');
select throws_ok('select pg_temp.file_at(pg_temp.req(801),pg_temp.id(1),0,''wrong_identity'',''2026-07-11T12:00:00.123455Z'')','22023',null,'request binds reason');
select throws_ok('select pg_temp.file_at(pg_temp.req(802),pg_temp.id(1),0,''wrong_result'',''2026-07-11T12:00:00.123455Z'')','23505',null,'one case per notice');
reset role;
select public.set_commitment_lifecycle_enabled_v1(true);
select throws_ok('select public.set_commitment_lifecycle_operator_v1(pg_temp.req(810),pg_temp.id(1),pg_temp.actor(1),''review'',clock_timestamp()+interval ''1 day'')','22023',null,'owner cannot receive operator grant');
select throws_ok('select public.set_commitment_lifecycle_operator_v1(pg_temp.req(810),pg_temp.id(1),pg_temp.actor(29),''review'',clock_timestamp()+interval ''8 days'')','42501',null,'operator grant at most seven days');
select pg_temp.login(29);
set local role authenticated;
select throws_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''review'')','42501',null,'unassigned independent actor denied');
reset role;
select pg_temp.login(30);
set local role authenticated;
select throws_ok('select pg_temp.resolve_at(pg_temp.req(820),(select (value->>''case_id'')::uuid from saved where name=''case''),''uphold'',''2026-07-12T12:00:00.123456Z'')','42501',null,'review read required before decision');
select lives_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''review'')','assigned operator audited read');
insert into saved values('resolution',pg_temp.resolve_at(pg_temp.req(820),(select (value->>'case_id')::uuid from saved where name='case'),'uphold','2026-07-12T12:00:00.123456Z'));
select is(pg_temp.resolve_at(pg_temp.req(820),(select (value->>'case_id')::uuid from saved where name='case'),'uphold','2026-07-30T12:00:00.123456Z'),(select value from saved where name='resolution'),'resolution exact recovery');
select throws_ok('select pg_temp.resolve_at(pg_temp.req(820),(select (value->>''case_id'')::uuid from saved where name=''case''),''inconclusive'',''2026-07-12T12:00:00.123456Z'')','22023',null,'operator request binds decision');
reset role;
select public.set_commitment_lifecycle_operator_v1(pg_temp.req(821),pg_temp.id(1),pg_temp.actor(30),'review',null);
set local role authenticated;
select throws_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''review'')','42501',null,'revoked operator cannot read');
select throws_ok('select pg_temp.resolve_at(pg_temp.req(820),(select (value->>''case_id'')::uuid from saved where name=''case''),''uphold'',''2026-07-12T12:00:00.123456Z'')','42501',null,'revocation denies operator exact recovery');
reset role;
select is(pg_temp.tick(1,'2026-07-18T12:00:00.123456Z','ready_to_finalize'),'final','final persists independently');
select is((select count(*) from app.performance_lifecycle_settlements where commitment_id=pg_temp.id(1)),0::bigint,'no implicit settlement');
select is((select status from app.performance_commitment_agreements where id=pg_temp.id(1)),'open','original agreement receipt preserved');
select is((select count(*) from app.performance_commitment_enrollments where commitment_id=pg_temp.id(1) and released_at is null),0::bigint,'final releases slot');
select is(public.settle_commitment_simulation_v1(pg_temp.id(1))->>'returned_cents','2000','uncertain result returns simulated amount');
select is(public.settle_commitment_simulation_v1(pg_temp.id(1))->>'lost_cents','0','no simulated loss for missing proof');
select is((select count(*) from app.performance_lifecycle_settlements where commitment_id=pg_temp.id(1)),1::bigint,'settlement exact retry');
select pg_temp.login(1);
set local role authenticated;
select is(public.file_commitment_review_v1(pg_temp.req(801),pg_temp.id(1),0,'wrong_result'),(select value from saved where name='case'),'owner case recovery after final');
select throws_ok('select public.close_performance_commitment_v1(pg_temp.req(830),pg_temp.id(1),''withdrawal'')','55000',null,'withdrawal cannot alter final');
reset role;
select is(pg_temp.attempt('select pg_temp.proof(1,0,359)'),'55000','new proof blocked after final');
select public.set_commitment_lifecycle_operator_v1(pg_temp.req(840),pg_temp.id(1),pg_temp.actor(30),'support',clock_timestamp()+interval '1 day');
select pg_temp.login(30);
set local role authenticated;
select throws_ok('select public.submit_commitment_support_correction_v1(pg_temp.req(841),pg_temp.id(1),''result_correction'',''Fictional correction'')','42501',null,'support read required');
select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),'support');
select throws_ok('select public.submit_commitment_support_correction_v1(pg_temp.req(841),pg_temp.id(1),''result_correction'','' '')','22023',null,'empty correction note rejected');
insert into saved values('support',public.submit_commitment_support_correction_v1(pg_temp.req(841),pg_temp.id(1),'result_correction','Fictional correction'));
select is(public.submit_commitment_support_correction_v1(pg_temp.req(841),pg_temp.id(1),'result_correction','Fictional correction'),(select value from saved where name='support'),'support exact request');
select throws_ok('select public.submit_commitment_support_correction_v1(pg_temp.req(841),pg_temp.id(1),''result_correction'',''Changed correction'')','22023',null,'support request binds full note');
reset role;
select is((select count(*) from app.performance_attempt_revisions where commitment_id=pg_temp.id(1)),0::bigint,'support never becomes proof');
select is((select result->'outcome'->>'kind' from app.performance_lifecycle_results where commitment_id=pg_temp.id(1)),'inconclusive','support cannot rewrite result');
select set_config('app.performance_lifecycle_write_v1','on',true);
select throws_ok('update app.performance_lifecycle_results set result=''{}''','23001',null,'final immutable even with write marker');
select throws_ok('update app.performance_lifecycle_settlements set lost_cents=2000','23001',null,'simulation immutable');
select throws_ok('delete from app.performance_lifecycle_support','23001',null,'support retained');
select throws_ok('delete from app.performance_lifecycle_retention','23001',null,'retention hold immutable');
select pg_temp.login(1);
set local role authenticated;
select ok(not public.get_commitment_lifecycle_v1(pg_temp.id(1))::text ~ 'Fictional correction|operator_id|grant_id|document','support owner receipt omits raw note');
reset role;
select lives_ok('select public.delete_account(pg_temp.actor(1))','deletion after final remains possible');
set local role authenticated;
select throws_ok('select public.get_commitment_lifecycle_v1(pg_temp.id(1))','42501',null,'deleted owner loses result access');
reset role;
select is((select count(*) from app.performance_lifecycle_results where commitment_id=pg_temp.id(1)),1::bigint,'deletion preserves final');
select pg_temp.login(30);
set local role authenticated;
select lives_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''support'')','separately assigned support survives owner deletion');
reset role;
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=pg_temp.req(30);
set local role authenticated;
select throws_ok('select public.read_commitment_lifecycle_operator_v1(pg_temp.id(1),''support'')','42501',null,'expired operator session denied');
reset role;
select pg_temp.login(2);
set local role authenticated;
reset role;
select lives_ok('select public.delete_account(pg_temp.actor(2))','unfinalized deletion closes agreement');
set local role authenticated;
reset role;
select is((select close_reason from app.performance_commitment_agreements where id=pg_temp.id(2)),'account_deleted','deletion closure preserved for evaluator');
select set_config('app.performance_commitment_write_v1','on',true);
select throws_ok('update app.performance_commitment_enrollments set released_at=clock_timestamp() where commitment_id=pg_temp.id(3); set constraints all immediate','23514',null,'arbitrary slot release still rejected');
-- Actual current-time consent plus an accelerated finality clock: finalization
-- ends sharing, and old consent can never authorize a new result-sharing scope.
create function pg_temp.active_fixture() returns uuid language plpgsql security definer set search_path='' as $$
declare s timestamptz:=clock_timestamp()+interval '1 day'; d timestamptz; t jsonb; c uuid; begin
 d:=s+interval '60 days'; t:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'UTC','performance-commitment-fixture-5k-v1');
 c:=app.create_performance_commitment_at_v1(pg_temp.req(921),360,s,d,'UTC','performance-commitment-fixture-5k-v1',
 encode(extensions.digest(t::text,'sha256'),'hex'),true);
 return c;
end; $$;
select pg_temp.login(21);
select public.set_commitment_progress_enabled_v1(true);
select public.set_commitment_following_enabled_v1(true);
insert into public.friendships(user_a,user_b,requested_by,status) values(pg_temp.actor(21),pg_temp.actor(22),pg_temp.actor(21),'accepted');
set local role authenticated;
insert into saved values('c21',jsonb_build_array(pg_temp.active_fixture()));
reset role;
insert into saved values('social_snapshot',app.performance_lifecycle_snapshot_v1((select a from app.performance_commitment_agreements a where id=pg_temp.id(21)),clock_timestamp()));
set local role authenticated;
select public.record_commitment_progress_v1(pg_temp.req(922),pg_temp.id(21),'PRIVATE manual progress is not proof',clock_timestamp());
select public.publish_commitment_progress_v1(pg_temp.req(923),pg_temp.id(21),1);
insert into saved values('follow',public.invite_commitment_follower_v1(pg_temp.req(924),pg_temp.id(21),pg_temp.actor(22),'goal_and_selected_progress_v1',true));
select pg_temp.login(22);
insert into saved values('follow_receipt',public.respond_commitment_follow_v1(pg_temp.req(925),(select (value->>'follow_id')::uuid from saved where name='follow'),true));
select public.set_commitment_follow_reminder_v1(pg_temp.req(926),(select (value->>'follow_id')::uuid from saved where name='follow'),clock_timestamp()+interval '2 days');
select is(public.get_commitment_follow_v1((select (value->>'follow_id')::uuid from saved where name='follow'))->'access_allowed','true'::jsonb,'following consent active before final');
select throws_ok('select public.get_commitment_lifecycle_v1(pg_temp.id(21))','42501',null,'accepted follower still cannot read results');
reset role;
select is(app.performance_lifecycle_snapshot_v1((select a from app.performance_commitment_agreements a where id=pg_temp.id(21)),
 (select (value->>'now')::timestamptz from saved where name='social_snapshot')),(select value from saved where name='social_snapshot'),
 'manual note, publication, following and reminder cannot affect scoring input');
select is(pg_temp.tick(21,(select (terms->>'finality_due_at')::timestamptz from app.performance_commitment_agreements where id=pg_temp.id(21)),
 'ready_to_finalize',0,'inconclusive','finality_timeout'),'final','accelerated final closes social access');
select pg_temp.login(22);
set local role authenticated;
select is(public.get_commitment_follow_v1((select (value->>'follow_id')::uuid from saved where name='follow'))->'access_allowed','false'::jsonb,'final removes follower goal/cards');
select is(public.respond_commitment_follow_v1(pg_temp.req(925),(select (value->>'follow_id')::uuid from saved where name='follow'),true),
 (select value from saved where name='follow_receipt'),'old acceptance recovers only original receipt');
select is(public.get_commitment_follow_v1((select (value->>'follow_id')::uuid from saved where name='follow'))->'access_allowed','false'::jsonb,'exact acceptance never restores access');
select pg_temp.login(21);
select throws_ok('select public.invite_commitment_follower_v1(pg_temp.req(927),pg_temp.id(21),pg_temp.actor(22),''goal_and_selected_progress_v1'',true)',
 '55000',null,'new following cannot admit a final agreement');
select throws_ok('select public.record_commitment_progress_v1(pg_temp.req(928),pg_temp.id(21),''new note'',clock_timestamp())',
 '55000',null,'new manual progress cannot append to a final agreement');
reset role;
select is((select reminder_at from app.performance_following_grants where commitment_id=pg_temp.id(21)),null::timestamptz,'final clears durable reminder');

set constraints all immediate;
select * from finish();
rollback;
