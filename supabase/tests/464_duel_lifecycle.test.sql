-- Rollback-only lifecycle boundary and authorization tests.
begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d9000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('da000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),
    'role','authenticated','session_id',pg_temp.req(9000+n))::text,true);
end; $$;
create temp table ids(name text primary key,id uuid);
grant select on ids to authenticated,service_role;
create function pg_temp.id(n text) returns uuid language sql as $$select id from ids where name=n$$;
create function pg_temp.make(a integer,b integer) returns uuid language plpgsql as $$
declare c uuid;
begin
  perform pg_temp.login(a);
  c:=app.create_duel_at_v1(pg_temp.req(a),pg_temp.actor(b),pg_temp.req(1000),
    'duel-fixture-5k-v1',true,'2026-07-31 12:00Z');
  perform pg_temp.login(b);
  perform app.respond_duel_at_v1('accept_duel_v1',pg_temp.req(b),c,'duel-fixture-5k-v1',
    (select terms_digest from public.duel_challenges where id=c),'2026-07-31 13:00Z');
  return c;
end; $$;
create function pg_temp.doc(c uuid) returns jsonb language sql security definer set search_path='' as $$
  select jsonb_build_object('eventId',event_id,'course','fixture_course_5k_v1','wave','fixture_common_wave_v1',
    'distanceMeters',5000,'timingBasis','organizer_chip','precisionSeconds',1,'rows',jsonb_build_array(
      jsonb_build_object('actorId',creator_id,'mappedBib','fictional-bib-11','publishedBib','fictional-bib-11','status','finished','chipSeconds',1200),
      jsonb_build_object('actorId',invitee_id,'mappedBib','fictional-bib-22','publishedBib','fictional-bib-22','status','finished','chipSeconds',1250)))
  from public.duel_challenges where id=c;
$$;
create function pg_temp.confirm(c uuid,a boolean default true,b boolean default true) returns jsonb
language sql security definer set search_path='' as $$
  select jsonb_build_array(jsonb_build_object('actorId',creator_id,'identityConfirmed',a),
    jsonb_build_object('actorId',invitee_id,'identityConfirmed',b)) from public.duel_challenges where id=c;
$$;
create function pg_temp.capture(n integer,c uuid,d jsonb default null,t timestamptz default '2026-08-01 18:00Z')
returns uuid language sql security definer set search_path='' as $$
  select app.duel_proof_capture_at_v1(pg_temp.req(n),c,coalesce(d,pg_temp.doc(c)),t);
$$;
create function pg_temp.submit(n integer,c uuid,s integer,rev integer,t timestamptz default '2026-08-01 19:00Z',v jsonb default null)
returns integer language sql security definer set search_path='' as $$
  select app.duel_proof_append_at_v1(pg_temp.req(n),c,pg_temp.req(s),rev,coalesce(v,pg_temp.confirm(c)),t);
$$;

insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,20) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'lifecycle'||n,'Fictional Runner','UTC' from generate_series(1,20) n;
insert into auth.sessions(id,user_id) select pg_temp.req(9000+n),pg_temp.actor(n) from generate_series(1,20) n;
insert into public.friendships(user_a,user_b,requested_by,status)
  select pg_temp.actor(a),pg_temp.actor(b),pg_temp.actor(a),'accepted'
  from generate_series(1,19) a cross join generate_series(2,20) b where a<b;
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,20) n));
select public.curate_duel_fixture_event_v1(pg_temp.req(1000),'2026-08-01 15:00Z','2026-08-01 17:00Z','America/Chicago');
insert into ids values('a',pg_temp.make(1,2)),('b',pg_temp.make(3,4)),('c',pg_temp.make(5,6)),('d',pg_temp.make(7,8));
select is((select enabled from app.duel_lifecycle_runtime),false,'lifecycle is default off');
select ok(not has_table_privilege(r,'app.'||t,p),r||' has no '||p||' on '||t)
  from unnest(array['anon','authenticated','service_role']) r
  cross join unnest(array['duel_lifecycle_runtime','duel_lifecycle_notices','duel_lifecycle_cases',
    'duel_lifecycle_resolutions','duel_lifecycle_closures','duel_lifecycle_results','duel_lifecycle_settlements',
    'duel_lifecycle_support','duel_lifecycle_activations','duel_lifecycle_gate_events']) t
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot execute private '||p.proname)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join unnest(array['anon','authenticated','service_role']) r
  where n.nspname='app' and p.proname like 'duel_lifecycle_%v1';
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot execute worker '||p.proname)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join unnest(array['anon','authenticated']) r where n.nspname='public'
    and p.proname in ('load_duel_lifecycle_v1','commit_duel_lifecycle_v1','settle_duel_simulation_v1','set_duel_lifecycle_enabled_v1','cancel_duel_event_v1');
select is((select count(*) from cron.job where command ilike '%duel%'),0::bigint,'no scheduler');
select throws_ok($$select app.duel_lifecycle_load_at_v1(pg_temp.id('a'),'2026-08-01 18:00Z')$$,
  '42501','duel_lifecycle_disabled','default off blocks worker');
select public.set_duel_lifecycle_enabled_v1(true);
select is(app.duel_lifecycle_load_at_v1(pg_temp.id('a'),'2026-08-01 14:59Z')->'notices','[]'::jsonb,'complete initial notice history');
select is((select count(*) from app.duel_lifecycle_activations),0::bigint,'not active before start');
select app.duel_lifecycle_load_at_v1(pg_temp.id('a'),'2026-08-01 15:00Z');
select app.duel_lifecycle_load_at_v1(pg_temp.id('a'),'2026-08-01 15:01Z');
select is((select count(*) from app.duel_lifecycle_activations),1::bigint,'activation is idempotent');
select is((select count(*) from app.duel_enrollments where challenge_id=pg_temp.id('a') and released_at is null),2::bigint,'activation retains both slots');

-- The evaluator decision is service-only. SQL tests use a known no-proof cutoff.
create function pg_temp.decision(i jsonb,phase text default 'provisional',reason text default 'unresolved_proof') returns jsonb
language sql as $$select jsonb_build_object('version','duel-fixture-official-5k-v1',
  'challengeId',i->'agreement'->'id','termsDigest',i->'agreement'->'terms_digest','proofRevision',0,
  'phase',phase,'outcome',jsonb_build_object('kind','void','reason',reason),
  'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false)$$;
create temp table snapshots(name text primary key,i jsonb);
insert into snapshots values('a',app.duel_lifecycle_load_at_v1(pg_temp.id('a'),'2026-08-04 17:00Z'));
select is(app.duel_lifecycle_commit_at_v1(i,pg_temp.decision(i),'2026-08-04 17:00Z'),'provisional','cutoff publishes durable pair notices') from snapshots where name='a';
select is(app.duel_lifecycle_commit_at_v1(i,pg_temp.decision(i),'2026-08-04 17:00Z'),'stale','duplicate old input is stale after notices') from snapshots where name='a';
select is((select count(*) from app.duel_lifecycle_notices where challenge_id=pg_temp.id('a')),2::bigint,'one notice per runner and revision');
select is((select count(*) from app.duel_enrollments where challenge_id=pg_temp.id('a') and released_at is null),2::bigint,'notices never release slots');
create function pg_temp.file(n integer,revision integer,at timestamptz) returns uuid language sql security definer set search_path='' as $$
 select app.duel_lifecycle_case_at_v1(pg_temp.req(n),pg_temp.id('a'),revision,'wrong_result',at)$$;
select pg_temp.login(1);
set local role authenticated;
select throws_ok($$select pg_temp.file(200,1,'2026-08-04 18:00Z')$$,'55000','duel_review_window_closed','unnoticed revision rejected');
select lives_ok($$select pg_temp.file(200,0,'2026-08-04 18:00Z')$$,'participant files in window');
select lives_ok($$select pg_temp.file(200,0,'2026-09-01 18:00Z')$$,'exact retry after deadline');
select throws_ok($$select pg_temp.file(201,0,'2026-08-11 17:00Z')$$,'55000','duel_review_window_closed','filing deadline equality rejected');
select is(jsonb_array_length(public.get_duel_lifecycle_v1(pg_temp.id('a'))->'reviews'),1,'own case receipt available');
select pg_temp.login(2);
select lives_ok($$select pg_temp.file(202,0,'2026-08-11 16:59:59.999999Z')$$,'last microsecond accepted');
select pg_temp.login(3);
select throws_ok($$select public.get_duel_lifecycle_v1(pg_temp.id('a'))$$,'42501','duel_unavailable','unrelated actor denied');
reset role;
select is(app.duel_lifecycle_commit_at_v1(i,pg_temp.decision(i),'2026-08-04 18:00Z'),'stale','case filing invalidates old snapshot') from snapshots where name='a';
select public.set_duel_proof_reviewer_v1(pg_temp.req(501),pg_temp.id('a'),pg_temp.actor(10),true);
create function pg_temp.resolve(n integer,at timestamptz) returns uuid language sql security definer set search_path='' as $$
 select app.duel_lifecycle_resolve_at_v1(pg_temp.req(n),
   (select id from app.duel_lifecycle_cases where challenge_id=pg_temp.id('a') and actor_id=pg_temp.actor(1)), 'uphold',at)$$;
select pg_temp.login(1);
set local role authenticated;
select throws_ok($$select pg_temp.resolve(300,'2026-08-05 18:00Z')$$,'42501','duel_proof_reviewer_required','self review rejected');
select pg_temp.login(10);
select throws_ok($$select pg_temp.resolve(300,'2026-08-11 18:00Z')$$,'55000','duel_review_resolution_closed','resolution exact timeout rejected');
select lives_ok($$select pg_temp.resolve(300,'2026-08-11 17:59:59.999999Z')$$,'resolution last microsecond accepted');
reset role;
select public.set_duel_proof_reviewer_v1(pg_temp.req(502),pg_temp.id('a'),pg_temp.actor(10),false);
select pg_temp.login(10);
set local role authenticated;
select throws_ok($$select pg_temp.resolve(300,'2026-08-11 17:59:59.999999Z')$$,'42501','duel_proof_reviewer_required','revoked reviewer cannot recover resolution');
reset role;

create function pg_temp.exit(kind text) returns uuid language sql security definer set search_path='' as $$select app.duel_lifecycle_exit_at_v1(pg_temp.req(400),pg_temp.id('b'),kind,'2026-08-05 18:00Z')$$;
-- Safe exits remain possible with admission closed and blocked contact.
select public.set_duel_lifecycle_enabled_v1(false);
select pg_temp.login(3);
set local role authenticated;
select lives_ok($$select pg_temp.exit('injury')$$,'safe exit passes closed lifecycle gate');
select throws_ok($$select pg_temp.exit('withdrawal')$$,'22023','duel_lifecycle_request_conflict','safe exit request payload frozen');
reset role;
select throws_ok($$update app.duel_lifecycle_notices set outcome='{}'$$,'23001','duel_lifecycle_append_only','owner cannot edit notices with write setting');
select throws_ok($$truncate app.duel_lifecycle_cases cascade$$,'23001',null,'case history cannot truncate');
set constraints all immediate;
select * from finish();
rollback;
