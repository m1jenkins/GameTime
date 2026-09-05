begin;
select no_plan();
set local timezone='UTC';
-- Caller owns BEGIN/ROLLBACK. Fictional fixture and private clock seams only.
create function pg_temp.pa_actor(n integer) returns uuid language sql immutable as $$
 select ('ee100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pa_req(n integer) returns uuid language sql immutable as $$
 select ('ee200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pa_login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.pa_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pa_actor(n),'role','authenticated','session_id',pg_temp.pa_req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.pa_actor(n) from generate_series(1,4) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.pa_actor(n),'attemptfixture'||n,'Fictional Runner','UTC' from generate_series(1,4) n;
insert into auth.sessions(id,user_id) select pg_temp.pa_req(n),pg_temp.pa_actor(n) from generate_series(1,4) n;
select public.set_performance_commitment_admission_v1(true,array[pg_temp.pa_actor(1),pg_temp.pa_actor(4)]);
create temp table pa_saved(name text primary key,id uuid);
grant select,insert on pa_saved to authenticated;
create function pg_temp.pa_id(n text) returns uuid language sql as $$ select id from pa_saved where name=n $$;
create function pg_temp.pa_create(q integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare s timestamptz:='2026-07-02T12:00:00.123456Z'; d timestamptz:='2026-08-31T12:00:00.123456Z'; digest text;
 begin
 digest:=encode(extensions.digest(app.performance_commitment_terms_v1(auth.uid(),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1')::text,'sha256'),'hex');
 return app.create_performance_commitment_at_v1(pg_temp.pa_req(q),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1',digest,true,'2026-07-01T12:00:00.123456Z');
end; $$;
select pg_temp.pa_login(1);
set local role authenticated;
insert into pa_saved values('main',pg_temp.pa_create(10));
reset role;
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(101),'2026-07-03T12:00:00.123456Z','2026-07-03T14:00:00.123456Z');
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(102),'2026-08-03T12:00:00.123456Z','2026-08-03T14:00:00.123456Z');
select public.curate_commitment_fixture_event_v1(pg_temp.pa_req(103),'2026-08-31T10:00:00.123456Z','2026-08-31T12:00:00.123456Z');
create function pg_temp.pa_nominate(q integer,e integer,n timestamptz default '2026-07-01T13:00:00.123456Z',bib text default 'bib-1')
 returns uuid language sql security definer set search_path='' as $$
 select app.nominate_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_req(e),bib,n) $$;
create function pg_temp.pa_document(e integer,seconds integer default 359) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('source','fixture_official_5k_v1','event_id',id,'distance_meters',5000,'timing_basis','organizer_chip',
 'precision_ms',1000,'published_bib','bib-1','status','finished','chip_seconds',seconds,'started_at',starts_at,'finished_at',starts_at+seconds*interval '1 second')
 from app.performance_attempt_events where id=pg_temp.pa_req(e) $$;
create function pg_temp.pa_capture(q integer,a text,e integer,seconds integer default 359,n timestamptz default '2026-08-04T12:00:00.123456Z',doc jsonb default null)
 returns uuid language sql security definer set search_path='' as $$
 select app.capture_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_id(a),coalesce(doc,pg_temp.pa_document(e,seconds)),n) $$;
create function pg_temp.pa_review(q integer,s integer,previous integer default null,n timestamptz default '2026-08-04T13:00:00.123456Z',confirmed boolean default true)
 returns integer language sql security definer set search_path='' as $$
 select app.review_commitment_attempt_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),pg_temp.pa_req(s),previous,confirmed,n) $$;
create function pg_temp.pa_confirm(q integer,ids uuid[],n timestamptz default '2026-08-31T12:00:00.123456Z',confirmed boolean default true)
 returns uuid language sql security definer set search_path='' as $$
 select app.confirm_commitment_attempt_set_at_v1(pg_temp.pa_req(q),pg_temp.pa_id('main'),ids,confirmed,n) $$;

select is((select enabled from app.performance_attempt_runtime),false,'attempt admission defaults off');
select is((select count(*) from cron.job where command ilike '%commitment_attempt%'),0::bigint,'no attempt schedule');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname like 'performance_attempt_%'
 and c.relkind='r' and not c.relrowsecurity),0::bigint,'all attempt storage has RLS');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app'
 and (p.proname like '%performance_attempt%v1' or p.proname like '%commitment_attempt%v1') and has_function_privilege('authenticated',p.oid,'execute')),0::bigint,'no private clock/helper grants');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('app','public')
 and (p.proname like '%performance_attempt%v1' or p.proname like '%commitment_attempt%v1') and has_function_privilege('anon',p.oid,'execute')),0::bigint,'no anonymous APIs');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('app','public')
 and (p.proname like '%performance_attempt%v1' or p.proname like '%commitment_attempt%v1') and p.prosecdef and not ('search_path=""'=any(p.proconfig))),0::bigint,'empty definer search paths');
set local role authenticated;
select throws_ok('select pg_temp.pa_nominate(11,101)','42501',null,'new gate required');
select throws_ok('select public.set_commitment_attempts_enabled_v1(true)','42501',null,'owner cannot open gate');
select throws_ok('select * from app.performance_attempt_sources','42501',null,'owner cannot read source table');
select throws_ok('select public.get_commitment_attempt_snapshot_v1(pg_temp.pa_id(''main''))','42501',null,'owner cannot request private snapshot');
reset role;
select public.set_commitment_attempts_enabled_v1(true);
set local role authenticated;
select throws_ok('select pg_temp.pa_nominate(11,103)','22023',null,'event end at exclusive deadline rejected');
select throws_ok($$select pg_temp.pa_nominate(11,101,'2026-07-03T12:00:00.123456Z')$$,'22023',null,'nomination at event start too late');
select throws_ok($$select pg_temp.pa_nominate(11,101,bib=>'not a bib')$$,'22023',null,'bounded bib');
insert into pa_saved values('first',pg_temp.pa_nominate(11,101));
select is(pg_temp.pa_nominate(11,101),pg_temp.pa_id('first'),'exact nomination retry');
select throws_ok($$select pg_temp.pa_nominate(11,101,bib=>'bib-2')$$,'22023',null,'changed retry rejected');
select throws_ok('select pg_temp.pa_nominate(12,101)','23505',null,'same event cannot be nominated twice');
insert into pa_saved values('second',pg_temp.pa_nominate(12,102));
select is(jsonb_array_length(public.get_commitment_attempts_v1(pg_temp.pa_id('main'))->'attempts'),2,'owner has two distinct attempts');
select throws_ok('select public.list_commitment_attempt_events_v1(pg_temp.pa_id(''main''),101)','22023',null,'event reads bounded');
select pg_temp.pa_login(2);
select throws_ok('select public.get_commitment_attempts_v1(pg_temp.pa_id(''main''))','42501',null,'stranger cannot read attempts');
select throws_ok('select pg_temp.pa_nominate(13,101)','42501',null,'stranger cannot nominate');
reset role;
select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(201),pg_temp.pa_id('main'),pg_temp.pa_actor(2),true);
select throws_ok('select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(202),pg_temp.pa_id(''main''),pg_temp.pa_actor(1),true)','42501',null,'self review forbidden');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"source":"garmin"}')$$,'22023',null,'wrong source rejected');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"distance_meters":1609}')$$,'22023',null,'mile cannot pass as 5K');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"precision_ms":1}')$$,'22023',null,'subsecond precision rejected');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"chip_seconds":359.5}')$$,'22023',null,'fractional chip time rejected');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"published_bib":"wrong"}')$$,'22023',null,'wrong bib rejected');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03T12:00:00.123455Z"}')$$,'22023',null,'actual start one microsecond too early rejected');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,doc=>pg_temp.pa_document(101)||'{"arbitrary_notes":"private"}')$$,'22023',null,'extra fields rejected');
-- Source JSON must be consumable by the unchanged strict evaluator.
select throws_ok($$select pg_temp.pa_capture(391,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03 12:00:00.123456+00"}')$$,'22023',null,'PostgreSQL-only timestamp spelling rejected');
select throws_ok($$select pg_temp.pa_capture(392,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03T12:00:00.123456"}')$$,'22023',null,'timezone-free timestamp rejected');
select throws_ok($$select pg_temp.pa_capture(393,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03T12:00:00.1234560Z"}')$$,'22023',null,'excess source precision rejected without rounding');
select throws_ok($$select pg_temp.pa_capture(394,'first',101,doc=>pg_temp.pa_document(101)||'{"status":"missing","published_bib":123,"chip_seconds":null,"started_at":null,"finished_at":null}')$$,'22023',null,'numeric source bib is not a string');
select lives_ok($$select pg_temp.pa_capture(399,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03T07:00:00.123456-05:00","finished_at":"2026-07-03T07:05:59.123456-05:00"}')$$,'explicit offsets preserve microseconds');
-- Simulate an immutable document admitted before the forward validation fix.
select set_config('app.performance_attempt_write_v1','on',true);
insert into app.performance_attempt_sources values(pg_temp.pa_req(398),pg_temp.pa_id('main'),pg_temp.pa_id('first'),
 '2026-08-04T12:00:00.123456Z',pg_temp.pa_document(101)||'{"started_at":"2026-07-03 12:00:00.123456+00"}');
select is(pg_temp.pa_capture(398,'first',101,doc=>pg_temp.pa_document(101)||'{"started_at":"2026-07-03 12:00:00.123456+00"}'),pg_temp.pa_req(398),'historical source retains exact replay before new validation');
select throws_ok($$select pg_temp.pa_capture(398,'first',101)$$,'22023',null,'historical malformed source cannot be rewritten');
select pg_temp.pa_capture(301,'first',101);
select is(pg_temp.pa_capture(301,'first',101),pg_temp.pa_req(301),'exact source capture replay');
select throws_ok($$select pg_temp.pa_capture(301,'first',101,360)$$,'22023',null,'source cannot be overwritten');
select pg_temp.pa_capture(302,'second',102,400);
select pg_temp.pa_login(1);
set local role authenticated;
select throws_ok('select public.get_commitment_attempt_source_v1(pg_temp.pa_id(''main''),pg_temp.pa_req(301))','42501',null,'owner cannot read raw proof');
select pg_temp.pa_login(3);
select throws_ok('select public.get_commitment_attempt_source_v1(pg_temp.pa_id(''main''),pg_temp.pa_req(301))','42501',null,'ungranted reviewer denied');
select pg_temp.pa_login(2);
select throws_ok('select pg_temp.pa_review(401,301)','22023',null,'review requires audited source retrieval');
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(301));
select throws_ok('select pg_temp.pa_review(401,301,confirmed=>false)','22023',null,'explicit identity review required');
select is(pg_temp.pa_review(401,301),1,'independent first review');
select is(pg_temp.pa_review(401,301),1,'exact review retry');
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(302));
select is(pg_temp.pa_review(402,302),2,'second attempt review appended');
select throws_ok('select pg_temp.pa_review(401,302)','22023',null,'review retry cannot switch sources');
reset role;
select pg_temp.pa_capture(303,'first',101,380,'2026-09-04T12:00:00.123456Z');
set local role authenticated;
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(303));
select throws_ok($$select pg_temp.pa_review(403,303,null,'2026-09-04T13:00:00.123456Z')$$,'22023',null,'stale predecessor rejected');
select is(pg_temp.pa_review(403,303,1,'2026-09-04T13:00:00.123456Z'),3,'explicit correction after initial cutoff');
select pg_temp.pa_login(1);
select throws_ok('select pg_temp.pa_confirm(501,''{}'')','22023',null,'cannot claim no attempts with nominations');
select throws_ok('select pg_temp.pa_confirm(501,array[pg_temp.pa_id(''first'')])','22023',null,'complete set cannot omit a nominated attempt');
reset role;
create temp table pa_ids as select array_agg(id order by id) ids from app.performance_attempt_nominations where commitment_id=pg_temp.pa_id('main');
grant select on pa_ids to authenticated;
set local role authenticated;
select throws_ok($$select pg_temp.pa_confirm(501,(select ids from pa_ids),'2026-08-31T12:00:00.123455Z')$$,'22023',null,'confirmation before deadline rejected');
select throws_ok($$select pg_temp.pa_confirm(501,(select ids from pa_ids),'2026-09-03T12:00:00.123456Z')$$,'22023',null,'confirmation at proof cutoff rejected');
select throws_ok('select pg_temp.pa_confirm(501,(select ids from pa_ids),confirmed=>false)','22023',null,'confirmation requires explicit true');
select is(pg_temp.pa_confirm(501,(select ids from pa_ids)),pg_temp.pa_id('main'),'owner confirms exact completed set');
select is(pg_temp.pa_confirm(501,(select ids from pa_ids)),pg_temp.pa_id('main'),'confirmation exact recovery');
select ok(public.get_commitment_attempts_v1(pg_temp.pa_id('main'))::text !~ '(chip_seconds|published_bib|reviewer_id|document|source_id|bib-1)','owner projection redacts proof, bib and reviewers');
reset role;
select is((select count(*) from app.performance_attempt_retention where commitment_id=pg_temp.pa_id('main')),1::bigint,'explicit product retention hold');
select is((select count(*) from app.performance_attempt_revisions where commitment_id=pg_temp.pa_id('main')),3::bigint,'corrections retain all revisions');
select is((select status from app.performance_commitment_agreements where id=pg_temp.pa_id('main')),'open','attempts and scoring do not close agreement');
select is((select released_at from app.performance_commitment_enrollments where commitment_id=pg_temp.pa_id('main')),null::timestamptz,'no slot release');
select set_config('app.performance_attempt_write_v1','on',true);
select throws_ok('delete from app.performance_attempt_sources','23001',null,'sources cannot be purged');
select throws_ok('update app.performance_attempt_revisions set revision=99','23001',null,'corrections immutable');
select throws_ok('truncate app.performance_attempt_retention','23001',null,'retention hold cannot be truncated');
select lives_ok($$select * from app.run_raw_evidence_retention('2030-01-01Z',500)$$,'legacy retention can run independently');
select is((select count(*) from app.performance_attempt_sources),5::bigint,'legacy retention does not remove long-goal proof');
select public.set_commitment_attempts_enabled_v1(false);
set local role authenticated;
select is(pg_temp.pa_nominate(11,101),pg_temp.pa_id('first'),'gate-off preserves exact nominations');
select is(pg_temp.pa_confirm(501,(select ids from pa_ids)),pg_temp.pa_id('main'),'gate-off preserves exact confirmations');
select lives_ok('select public.get_commitment_attempts_v1(pg_temp.pa_id(''main''))','gate-off retains own receipts');
select pg_temp.pa_login(2);
select is(pg_temp.pa_review(403,303,1,'2026-09-04T13:00:00.123456Z'),3,'gate-off preserves exact reviewed request');
select throws_ok('select public.get_commitment_attempt_source_v1(pg_temp.pa_id(''main''),pg_temp.pa_req(301))','42501',null,'gate-off stops raw source reads');
reset role;
select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(203),pg_temp.pa_id('main'),pg_temp.pa_actor(2),false);
select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(201),pg_temp.pa_id('main'),pg_temp.pa_actor(2),true);
set local role authenticated;
select throws_ok('select pg_temp.pa_review(403,303,1,''2026-09-04T13:00:00.123456Z'')','42501',null,'old grant replay never restores revoked reviewer access');
reset role;
select public.set_commitment_attempts_enabled_v1(true);
select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(204),pg_temp.pa_id('main'),pg_temp.pa_actor(2),true);
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=pg_temp.pa_req(2);
set local role authenticated;
select throws_ok('select public.get_commitment_attempt_source_v1(pg_temp.pa_id(''main''),pg_temp.pa_req(301))','42501',null,'expired session denied');
reset role;
update auth.sessions set not_after=null where id=pg_temp.pa_req(2);
select public.delete_account(pg_temp.pa_actor(1));
select is((select count(*) from app.performance_attempt_sources),5::bigint,'account deletion retains scoped proof');
select is((select close_reason from app.performance_commitment_agreements where id=pg_temp.pa_id('main')),'account_deleted','existing deletion closes at zero consequence');
set local role authenticated;
select throws_ok('select public.get_commitment_attempt_source_v1(pg_temp.pa_id(''main''),pg_temp.pa_req(301))','42501',null,'reviewer cannot read deleted owner proof');
select pg_temp.pa_login(1);
select throws_ok('select public.get_commitment_attempts_v1(pg_temp.pa_id(''main''))','42501',null,'deleted owner cannot read');
reset role;
select * from finish();
rollback;
