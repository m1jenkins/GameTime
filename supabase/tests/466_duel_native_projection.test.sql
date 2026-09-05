-- Phase 2(d), rollback-only participant projection tests. No operator data added.
begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('db100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.session(n integer) returns uuid language sql immutable as $$
  select ('db200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'role','authenticated',
    'session_id',pg_temp.session(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,5) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'nativeprojection'||n,'Fictional Runner','UTC' from generate_series(1,5) n;
insert into auth.sessions(id,user_id) select pg_temp.session(n),pg_temp.actor(n) from generate_series(1,5) n;
insert into public.friendships(user_a,user_b,requested_by,status)
  values(pg_temp.actor(1),pg_temp.actor(2),pg_temp.actor(1),'accepted'),
        (pg_temp.actor(3),pg_temp.actor(4),pg_temp.actor(3),'accepted');
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,4) n));
select public.set_duel_lifecycle_enabled_v1(true);
create temp table ids(name text,id uuid);
grant select on ids to authenticated;
create function pg_temp.id(n text) returns uuid language sql as $$select id from ids where name=n$$;
create function pg_temp.make(a integer,b integer,age integer) returns uuid language plpgsql as $$
declare t timestamptz:=clock_timestamp()-make_interval(days=>age); e uuid:=extensions.gen_random_uuid(); c uuid;
begin
  perform public.curate_duel_fixture_event_v1(e,t+interval '3 days',t+interval '3 days 2 hours','America/Chicago');
  perform pg_temp.login(a);
  c:=app.create_duel_at_v1(extensions.gen_random_uuid(),pg_temp.actor(b),e,'duel-fixture-5k-v1',true,t);
  perform pg_temp.login(b);
  perform app.respond_duel_at_v1('accept_duel_v1',extensions.gen_random_uuid(),c,'duel-fixture-5k-v1',
    (select terms_digest from public.duel_challenges where id=c),t+interval '1 hour');
  return c;
end; $$;
insert into ids values('open',pg_temp.make(1,2,10)),('old',pg_temp.make(3,4,20));
create function pg_temp.notice(c uuid,t timestamptz,phase text default 'provisional') returns text language plpgsql as $$
declare i jsonb; d jsonb;
begin
  i:=app.duel_lifecycle_load_at_v1(c,t);
  d:=jsonb_build_object('version','duel-fixture-official-5k-v1','challengeId',c,'termsDigest',i->'agreement'->'terms_digest',
    'phase',phase,'proofRevision',0,'outcome',jsonb_build_object('kind','void','reason','unresolved_proof'),
    'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false);
  return app.duel_lifecycle_commit_at_v1(i,d,t);
end; $$;
select pg_temp.notice(pg_temp.id('open'),clock_timestamp()-interval '1 day');
select pg_temp.notice(pg_temp.id('old'),clock_timestamp()-interval '8 days');
select public.set_duel_admission_v1(false,'{}');
select public.set_duel_lifecycle_enabled_v1(false);
select pg_temp.login(1);
set local role authenticated;
select ok((public.get_duel_lifecycle_v1(pg_temp.id('open'))->>'canExit')::boolean,'gate off retains safe exit');
select ok((public.get_duel_lifecycle_v1(pg_temp.id('open'))->'notices'->0->>'canFileReview')::boolean,'gate off retains review');
select ok((public.get_duel_lifecycle_v1(pg_temp.id('open'))->>'serverNow')::timestamptz<=clock_timestamp(),'server clock observed');
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure','null'::jsonb,'no invented exit');
select public.file_duel_review_v1(pg_temp.session(101),pg_temp.id('open'),0,'missing_result');
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('open'))->'notices'->0->>'canFileReview')::boolean,'filed revision unavailable');
select is(jsonb_array_length(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'reviews'),1,'own review receipt');
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('open'))->'reviews'->0 ?| array['reviewerId','filedBy','source','document','bib']), 'case redacted');
select public.exit_duel_v1(pg_temp.session(102),pg_temp.id('open'),'injury');
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure'->>'kind','injury','saved injury visible before worker');
select ok((public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure'->>'isOwn')::boolean,'own receipt identified without raw actor');
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('open'))->>'canExit')::boolean,'saved exit cannot be sent again');
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'finalResult','null'::jsonb,'exit does not invent final result');
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'simulatedReturnCents','null'::jsonb,'exit does not invent return');
reset role;
create temp table captured(label text,document jsonb);
grant insert on captured to authenticated;
set local role authenticated;
insert into captured values('own_exit',jsonb_build_object('agreement',public.get_duel_v1(pg_temp.id('open')),
  'actorId',pg_temp.actor(1),'lifecycle',public.get_duel_lifecycle_v1(pg_temp.id('open'))));
reset role;
select pg_temp.login(2);
set local role authenticated;
select is(jsonb_array_length(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'reviews'),0,'opponent cannot read case');
select ok((public.get_duel_lifecycle_v1(pg_temp.id('open'))->'notices'->0->>'canFileReview')::boolean,'opponent retains own review window');
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure'->>'isOwn')::boolean,'shared exit has no actor ID');
reset role;
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(1),pg_temp.actor(2));
set local role authenticated;
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure','null'::jsonb,'blocked opponent injury hidden');
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'notices','[]'::jsonb,'blocked result notices hidden');
reset role;
select pg_temp.login(1);
set local role authenticated;
select is(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'closure'->>'kind','injury','blocked actor retains own exit');
select is(jsonb_array_length(public.get_duel_lifecycle_v1(pg_temp.id('open'))->'reviews'),1,'blocked actor retains own case');
reset role;
set local role authenticated;
insert into captured values('blocked_own',jsonb_build_object('agreement',public.get_duel_v1(pg_temp.id('open')),
  'actorId',pg_temp.actor(1),'lifecycle',public.get_duel_lifecycle_v1(pg_temp.id('open'))));
reset role;
select pg_temp.login(3);
set local role authenticated;
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('old'))->'notices'->0->>'canFileReview')::boolean,'elapsed review deadline is closed');
reset role;
select public.set_duel_lifecycle_enabled_v1(true);
select pg_temp.notice(pg_temp.id('old'),clock_timestamp(),'ready_to_finalize');
select public.set_duel_lifecycle_enabled_v1(false);
set local role authenticated;
select ok(not (public.get_duel_lifecycle_v1(pg_temp.id('old'))->>'canExit')::boolean,'final result disables exit with historical scheduled agreement');
select is(public.get_duel_lifecycle_v1(pg_temp.id('old'))->'simulatedReturnCents','null'::jsonb,'final result still awaits separate return');
reset role;
set local role authenticated;
insert into captured values('final_pending',jsonb_build_object('agreement',public.get_duel_v1(pg_temp.id('old')),
  'actorId',pg_temp.actor(3),'lifecycle',public.get_duel_lifecycle_v1(pg_temp.id('old'))));
reset role;
select public.set_duel_lifecycle_enabled_v1(true);
select public.settle_duel_simulation_v1(pg_temp.id('old'));
select public.set_duel_lifecycle_enabled_v1(false);
set local role authenticated;
select is((public.get_duel_lifecycle_v1(pg_temp.id('old'))->>'simulatedReturnCents')::int,2000,'separate own simulated return');
reset role;
set local role authenticated;
insert into captured values('final_return',jsonb_build_object('agreement',public.get_duel_v1(pg_temp.id('old')),
  'actorId',pg_temp.actor(3),'lifecycle',public.get_duel_lifecycle_v1(pg_temp.id('old'))));
reset role;
select pg_temp.login(5);
set local role authenticated;
select throws_ok($$select public.get_duel_lifecycle_v1(pg_temp.id('open'))$$,'42501','duel_unavailable','unrelated actor denied');
reset role;
select pg_temp.login(1);
delete from auth.sessions where id=pg_temp.session(1);
set local role authenticated;
select throws_ok($$select public.get_duel_lifecycle_v1(pg_temp.id('open'))$$,'42501',null,'revoked session denied');
reset role;
select ok(not has_function_privilege('anon','public.get_duel_lifecycle_v1(uuid)','execute'),'anonymous cannot read');
select ok(not has_function_privilege('service_role','public.get_duel_lifecycle_v1(uuid)','execute'),'no service participant read');
-- A machine-readable actual PostgreSQL DTO fixture, captured only on demand.
\if :{?capture_native_dto}
select 'NATIVE_DTO:'||jsonb_agg(jsonb_build_object('label',label,'document',document))::text from captured;
\endif
select * from finish();
rollback;
