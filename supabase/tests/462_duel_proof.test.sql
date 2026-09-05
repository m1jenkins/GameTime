-- Fictional actors, deterministic private clock seams, and rollback-only data.
begin;
select no_plan();
set local timezone='UTC';
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d5000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('d6000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
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

select is((select enabled from app.duel_proof_runtime),false,'fresh proof admission is off');
select is((select count(*) from app.duel_proof_grants),0::bigint,'no reviewer is seeded');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='app' and c.relname like 'duel_proof_%' and c.relkind='r' and not c.relrowsecurity),0::bigint,'private proof tables all enable RLS');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('app','public') and p.proname like '%duel_proof%v1' and p.prosecdef
    and not ('search_path=""'=any(p.proconfig))),0::bigint,'every proof definer has a fixed empty search path');
select is((select count(*) from cron.job where command ilike '%duel%'),0::bigint,'no duel schedule created');
select ok(not has_table_privilege(r,'app.'||t,p),r||' has no '||p||' on '||t)
  from unnest(array['anon','authenticated','service_role']) r
  cross join unnest(array['duel_proof_runtime','duel_proof_grants','duel_proof_sources','duel_proof_revisions','duel_proof_access_audit']) t
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot execute private '||p.proname)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join unnest(array['anon','authenticated','service_role']) r
  where n.nspname='app' and p.proname like 'duel_proof_%v1';

insert into auth.users(id) select pg_temp.actor(n) from generate_series(1,20) n;
insert into public.profiles(id,handle,display_name,timezone)
  select pg_temp.actor(n),'proof'||n,'Fictional Runner','UTC' from generate_series(1,20) n;
insert into auth.sessions(id,user_id) select pg_temp.req(9000+n),pg_temp.actor(n) from generate_series(1,20) n;
insert into public.friendships(user_a,user_b,requested_by,status)
  select pg_temp.actor(a),pg_temp.actor(b),pg_temp.actor(a),'accepted'
  from generate_series(1,19) a cross join generate_series(2,20) b where a<b;
select public.set_duel_admission_v1(true,array(select pg_temp.actor(n) from generate_series(1,20) n));
select public.curate_duel_fixture_event_v1(pg_temp.req(1000),'2026-08-01 15:00Z','2026-08-01 17:00Z','America/Chicago');
insert into ids values('a',pg_temp.make(1,2)),('b',pg_temp.make(3,4)),('c',pg_temp.make(5,6)),('d',pg_temp.make(7,8));
select throws_ok($$select pg_temp.capture(100,pg_temp.id('a'))$$,'42501','duel_proof_disabled','source capture respects default-off gate');
select throws_ok($$select public.set_duel_proof_reviewer_v1(pg_temp.req(500),pg_temp.id('a'),pg_temp.actor(1),true)$$,
  '42501','duel_proof_self_review','service cannot appoint either contestant as reviewer');
select public.set_duel_proof_reviewer_v1(pg_temp.req(501),pg_temp.id('a'),pg_temp.actor(10),true);
select public.set_duel_proof_reviewer_v1(pg_temp.req(502),pg_temp.id('a'),pg_temp.actor(11),true);
select public.set_duel_proof_reviewer_v1(pg_temp.req(503),pg_temp.id('b'),pg_temp.actor(10),true);
select public.set_duel_proof_reviewer_v1(pg_temp.req(504),pg_temp.id('c'),pg_temp.actor(10),true);
select public.set_duel_proof_reviewer_v1(pg_temp.req(505),pg_temp.id('d'),pg_temp.actor(10),true);
select throws_ok($$select public.set_duel_proof_reviewer_v1(pg_temp.req(501),pg_temp.id('a'),pg_temp.actor(11),true)$$,
  '22023','duel_proof_request_conflict','grant request identity includes reviewer');
select public.set_duel_proof_enabled_v1(true);
select pg_temp.capture(100,pg_temp.id('a'));
select pg_temp.capture(101,pg_temp.id('b'));
select pg_temp.capture(102,pg_temp.id('c'));
select pg_temp.capture(103,pg_temp.id('d'));
select is(pg_temp.capture(100,pg_temp.id('a')),pg_temp.req(100),'source capture exact replay preserves identity');
select throws_ok($$select pg_temp.capture(100,pg_temp.id('a'),jsonb_set(pg_temp.doc(pg_temp.id('a')),'{rows,0,chipSeconds}','1199'))$$,
  '22023','duel_proof_request_conflict','source cannot be repointed');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),pg_temp.doc(pg_temp.id('b')))$$,
  '22023',null,'foreign actors cannot enter source');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),jsonb_set(pg_temp.doc(pg_temp.id('a')),'{eventId}',to_jsonb(pg_temp.req(999))))$$,
  '22023','duel_proof_invalid_source','source identity must match agreed event');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),pg_temp.doc(pg_temp.id('a'))||'{"url":"https://example.com"}')$$,
  '22023','duel_proof_invalid_source','arbitrary source URL or extra raw fields rejected');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),jsonb_set(pg_temp.doc(pg_temp.id('a')),'{rows}',(pg_temp.doc(pg_temp.id('a'))->'rows')-1))$$,
  '22023','duel_proof_complete_pair_required','partial source cannot erase opponent');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),jsonb_set(pg_temp.doc(pg_temp.id('a')),'{rows,1,mappedBib}','"fictional-bib-11"'))$$,
  '22023','duel_proof_invalid_source_row','duplicate expected bib mapping rejected');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),null,'2026-08-01 16:59:59.999999Z')$$,
  '55000','duel_proof_capture_closed','pre-end capture refused');
select throws_ok($$select pg_temp.capture(104,pg_temp.id('a'),null,'infinity')$$,
  '55000',null,'nonfinite retrieval refused');

set local role authenticated;
select pg_temp.login(10);
select throws_ok($$select public.set_duel_proof_enabled_v1(true)$$,'42501',null,'reviewer cannot enable ingestion');
select throws_ok($$select public.set_duel_proof_reviewer_v1(pg_temp.req(999),pg_temp.id('a'),pg_temp.actor(10),true)$$,
  '42501',null,'reviewer cannot grant authority');
select throws_ok($$select public.capture_duel_proof_fixture_v1(pg_temp.req(999),pg_temp.id('a'),pg_temp.doc(pg_temp.id('a')))$$,
  '42501',null,'reviewer cannot invent source times or bib mapping');
select throws_ok($$select app.duel_proof_append_at_v1(pg_temp.req(1),pg_temp.id('a'),pg_temp.req(100),0,pg_temp.confirm(pg_temp.id('a')),now())$$,
  '42501',null,'reviewer cannot inject server clock');
select throws_ok($$select app.duel_proof_history_v1(pg_temp.id('a'))$$,'42501',null,'private evaluator history has no client grant');
select lives_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'assigned active reviewer can read source');
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(101))$$,
  '42501',null,'source cannot cross agreement binding');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),101,0)$$,'42501',null,'proof cannot cross source binding');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,0,'2026-08-01 17:59:59.999999Z')$$,
  '55000',null,'receipt cannot precede source capture');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,0,'2026-08-01 19:00Z','[]')$$,
  '22023','duel_proof_complete_review_required','both identity verdicts required');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,0,'2026-08-01 19:00Z',
  jsonb_set(pg_temp.confirm(pg_temp.id('a')),'{0,chipSeconds}','1000'))$$,
  '22023','duel_proof_invalid_review','reviewer cannot overwrite source timing');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,0,'2026-08-01 19:00Z',
  jsonb_set(pg_temp.confirm(pg_temp.id('a')),'{1,actorId}',to_jsonb(pg_temp.actor(1))))$$,
  '22023','duel_proof_invalid_review','duplicate runner verdict refused');
select is(pg_temp.submit(200,pg_temp.id('a'),100,0),1,'initial full proof appends revision one');
select is(pg_temp.submit(200,pg_temp.id('a'),100,0),1,'exact reviewer retry returns original revision');
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,1)$$,
  '22023','duel_proof_request_conflict','retry binds expected revision');
select throws_ok($$select pg_temp.submit(201,pg_temp.id('a'),100,0)$$,
  '40001','duel_proof_revision_conflict','stale predecessor cannot overwrite latest revision');
select throws_ok($$select pg_temp.submit(201,pg_temp.id('a'),100,1,'2026-08-01 18:59:59.999999Z')$$,
  '55000',null,'correction receipts are monotonic');
select is(pg_temp.submit(201,pg_temp.id('a'),100,1,'2026-08-04 17:00Z'),2,'correction allowed at initial cutoff after admitted first proof');
select throws_ok($$select pg_temp.submit(202,pg_temp.id('b'),101,0,'2026-08-04 17:00Z')$$,
  '55000','duel_proof_submission_closed','initial submission exactly at cutoff is late');
select throws_ok($$select pg_temp.submit(202,pg_temp.id('b'),101,1,'2026-08-04 17:00Z')$$,
  '40001',null,'late initial cannot masquerade as correction');
select is(pg_temp.submit(202,pg_temp.id('b'),101,0,'2026-08-04 16:59:59.999999Z'),1,'last microsecond before initial cutoff allowed');
select is(pg_temp.submit(203,pg_temp.id('a'),100,2,'2026-08-31 16:59:59.999999Z'),3,'last microsecond before hard cap allowed');
select throws_ok($$select pg_temp.submit(204,pg_temp.id('a'),100,3,'2026-08-31 17:00Z')$$,
  '55000','duel_proof_submission_closed','correction exactly at cap refused');
select is(pg_temp.submit(200,pg_temp.id('a'),100,0,'2026-09-01 17:00Z'),1,'historical retry after cap returns first receipt');
select pg_temp.login(1);
select throws_ok($$select pg_temp.submit(300,pg_temp.id('a'),100,3)$$,'42501','duel_proof_reviewer_required','contestant cannot submit own proof');
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'42501',null,'contestant cannot read raw source');
select is((public.get_duel_proof_status_v1(pg_temp.id('a'))->>'proofRevision')::integer,3,'participant sees authoritative receipt revision');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_duel_proof_status_v1(pg_temp.id('a'))) k),
  array['challengeId','proofRevision','recordedAt','termsDigest'],'participant projection is an exact redacted allowlist');
select pg_temp.login(2);
select lives_ok($$select public.get_duel_proof_status_v1(pg_temp.id('a'))$$,'invitee can read receipt');
select pg_temp.login(12);
select throws_ok($$select public.get_duel_proof_status_v1(pg_temp.id('a'))$$,'42501',null,'unrelated actor denied redacted read');
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'42501',null,'unrelated actor denied raw read');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(12),'session_id',pg_temp.req(9012),
  'user_metadata',jsonb_build_object('duel_reviewer',true),'app_metadata',jsonb_build_object('duel_reviewer',true))::text,true);
select throws_ok($$select pg_temp.submit(300,pg_temp.id('a'),100,3)$$,'42501',null,'JWT metadata cannot grant reviewer power');
reset role;
select is((select count(*) from app.duel_proof_access_audit where operation='source_read'),1::bigint,'authorized raw read is audited, denied reads return no source');
select is((select content_digest from app.duel_proof_sources where id=pg_temp.req(100)),
  encode(extensions.digest(pg_temp.doc(pg_temp.id('a'))::text,'sha256'),'hex'),'canonical content digest is server computed');
select is((select reviewer_id from app.duel_proof_revisions where challenge_id=pg_temp.id('a') and revision=1),pg_temp.actor(10),'reviewer identity comes from authenticated session');
select is((select records->0->>'chipSeconds' from app.duel_proof_revisions where challenge_id=pg_temp.id('a') and revision=1),'1200','stored timing comes from captured source');
select is((select recorded_at from app.duel_proof_revisions where challenge_id=pg_temp.id('b') and revision=1),
  '2026-08-04 16:59:59.999999Z'::timestamptz,'receipt preserves six microsecond digits');
select is(jsonb_array_length(app.duel_proof_history_v1(pg_temp.id('a'))),3,'private evaluator projection retains whole chain');
select is((app.duel_proof_history_v1(pg_temp.id('a'))->2->>'supersedesRevision')::integer,2,'projection binds predecessor');
select is((select count(*) from app.duel_enrollments where challenge_id=pg_temp.id('a') and released_at is null),2::bigint,'proof never releases participant slots');
select is((select status from public.duel_challenges where id=pg_temp.id('a')),'scheduled','proof does not invent lifecycle/result state');

-- Wrong/duplicate published bibs are preserved as unresolved source facts;
-- the reviewer cannot claim a confirmed identity for either mismatch.
select pg_temp.capture(110,pg_temp.id('c'),jsonb_set(pg_temp.doc(pg_temp.id('c')),'{rows,1,publishedBib}','"fictional-bib-11"'));
set local role authenticated;
select pg_temp.login(10);
select throws_ok($$select pg_temp.submit(210,pg_temp.id('c'),110,0)$$,'22023','duel_proof_identity_unresolved','duplicate published bib cannot be confirmed');
select is(pg_temp.submit(210,pg_temp.id('c'),110,0,'2026-08-01 19:00Z',pg_temp.confirm(pg_temp.id('c'),false,false)),1,
  'unresolved identities can be recorded without assigning a loss');
reset role;
select pg_temp.capture(111,pg_temp.id('c'),jsonb_set(jsonb_set(jsonb_set(pg_temp.doc(pg_temp.id('c')),
  '{rows,1,status}','"missing"'),'{rows,1,chipSeconds}','null'),'{rows,1,publishedBib}','null'));
set local role authenticated;
select throws_ok($$select pg_temp.submit(211,pg_temp.id('c'),111,1)$$,'22023',null,'missing proof cannot receive identity confirmation');
select is(pg_temp.submit(211,pg_temp.id('c'),111,1,'2026-08-01 20:00Z',pg_temp.confirm(pg_temp.id('c'),true,false)),2,
  'correction carries the missing opponent explicitly');
reset role;
select is((select records->1->>'status' from app.duel_proof_revisions where challenge_id=pg_temp.id('c') and revision=2),'missing','latest correction never falls back to old opponent data');

-- Immediate server-owned revocation, even for exact retries and raw reads.
select public.set_duel_proof_reviewer_v1(pg_temp.req(510),pg_temp.id('a'),pg_temp.actor(10),false);
select public.set_duel_proof_reviewer_v1(pg_temp.req(501),pg_temp.id('a'),pg_temp.actor(10),true);
set local role authenticated;
select throws_ok($$select pg_temp.submit(200,pg_temp.id('a'),100,0)$$,'42501','duel_proof_reviewer_required','revoked reviewer cannot recover private request');
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'42501',null,'old grant replay does not undo revocation');
reset role;
select public.set_duel_proof_reviewer_v1(pg_temp.req(511),pg_temp.id('a'),pg_temp.actor(10),true);
select public.set_duel_proof_enabled_v1(false);
set local role authenticated;
select is(pg_temp.submit(200,pg_temp.id('a'),100,0),1,'gate-off preserves authorized committed retry');
select throws_ok($$select pg_temp.submit(220,pg_temp.id('d'),103,0)$$,'42501','duel_proof_disabled','gate-off rejects new proof');
select pg_temp.login(1);
select lives_ok($$select public.get_duel_proof_status_v1(pg_temp.id('a'))$$,'gate-off preserves receipt reads');
reset role;
select public.set_duel_proof_enabled_v1(true);
delete from auth.sessions where id=pg_temp.req(9010);
set local role authenticated;
select pg_temp.login(10);
select throws_ok($$select pg_temp.submit(220,pg_temp.id('d'),103,0)$$,'42501','duel_proof_session_required','revoked session cannot act with stale JWT');
reset role;
insert into auth.sessions(id,user_id,not_after) values(pg_temp.req(9010),pg_temp.actor(10),clock_timestamp()-interval '1 second');
set local role authenticated;
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'42501','duel_proof_session_required','expired session cannot read raw source');
reset role;
update auth.sessions set not_after=null where id=pg_temp.req(9010);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(10),'session_id',pg_temp.req(9011))::text,true);
select throws_ok($$select pg_temp.submit(220,pg_temp.id('d'),103,0)$$,'42501','duel_proof_session_required','session must belong to reviewer');
select pg_temp.login(10);
reset role;

insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(1),pg_temp.actor(2));
set local role authenticated;
select pg_temp.login(1);
select throws_ok($$select public.get_duel_proof_status_v1(pg_temp.id('a'))$$,'42501',null,'blocked pair cannot gain proof receipt access');
select pg_temp.login(10);
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('a'),pg_temp.req(100))$$,'42501',null,'blocked pair suppresses new operator access');
reset role;
select public.delete_account(pg_temp.actor(7));
set local role authenticated;
select throws_ok($$select pg_temp.submit(220,pg_temp.id('d'),103,0)$$,'42501',null,'participant deletion denies new proof');
select pg_temp.login(7);
select throws_ok($$select public.get_duel_proof_status_v1(pg_temp.id('d'))$$,'42501',null,'deleted actor cannot read with stale token');
reset role;
select public.delete_account(pg_temp.actor(10));
set local role authenticated;
select pg_temp.login(10);
select throws_ok($$select public.get_duel_proof_source_v1(pg_temp.id('b'),pg_temp.req(101))$$,'42501',null,'deleted reviewer cannot read with stale token');
reset role;
select lives_ok($$select public.set_duel_proof_reviewer_v1(pg_temp.req(512),pg_temp.id('d'),pg_temp.actor(10),false)$$,
  'service can revoke after participant and reviewer deletion');

-- Table access denied for every API role; owner still cannot rewrite history.
set local role authenticated;
select throws_ok('select * from app.'||t,'42501',null,t||': authenticated raw read denied')
  from unnest(array['duel_proof_sources','duel_proof_revisions','duel_proof_grants','duel_proof_access_audit','duel_proof_runtime']) t;
select set_config('app.duel_proof_write_v1','on',true);
select throws_ok($$update app.duel_proof_runtime set enabled=true$$,'42501',null,'spoofed write GUC confers no authority');
set local role anon;
select throws_ok($$select public.get_duel_proof_status_v1(pg_temp.id('a'))$$,'42501',null,'anonymous RPC denied');
select throws_ok('select * from app.'||t,'42501',null,t||': anonymous raw read denied')
  from unnest(array['duel_proof_sources','duel_proof_revisions','duel_proof_grants','duel_proof_access_audit']) t;
set local role service_role;
select throws_ok('select * from app.'||t,'42501',null,t||': service direct read denied')
  from unnest(array['duel_proof_sources','duel_proof_revisions','duel_proof_grants','duel_proof_access_audit']) t;
select throws_ok($$select public.submit_duel_proof_v1(pg_temp.req(900),pg_temp.id('a'),pg_temp.req(100),0,'[]')$$,
  '42501',null,'service cannot impersonate independent reviewer');
reset role;
select throws_ok('update app.'||t||' set recorded_at=clock_timestamp()','23001','duel_proof_append_only',t||': privileged update forbidden')
  from unnest(array['duel_proof_revisions','duel_proof_grants','duel_proof_access_audit']) t;
select throws_ok($$update app.duel_proof_sources set document='{}'$$,'23001','duel_proof_append_only','source document immutable');
select throws_ok('delete from app.'||t,'23001','duel_proof_append_only',t||': privileged deletion forbidden')
  from unnest(array['duel_proof_sources','duel_proof_revisions','duel_proof_grants','duel_proof_access_audit']) t;
select throws_ok($$truncate app.duel_proof_sources cascade$$,'23001','duel_proof_append_only','privileged truncate forbidden');
set constraints all immediate;
select * from finish();
rollback;
