begin;
select no_plan();
set local timezone='UTC';
-- Caller owns BEGIN/ROLLBACK. Fictional actors and private clock seams only.
create function pg_temp.pp_actor(n integer) returns uuid language sql immutable as $$
 select ('e7100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pp_req(n integer) returns uuid language sql immutable as $$
 select ('e7200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.pp_login(n integer) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.pp_actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pp_actor(n),'role','authenticated','session_id',pg_temp.pp_req(n))::text,true);
end; $$;
insert into auth.users(id) select pg_temp.pp_actor(n) from generate_series(1,3) n;
insert into public.profiles(id,handle,display_name,timezone)
 select pg_temp.pp_actor(n),'progressfixture'||n,'Fictional Runner','UTC' from generate_series(1,3) n;
insert into auth.sessions(id,user_id) select pg_temp.pp_req(n),pg_temp.pp_actor(n) from generate_series(1,3) n;
select public.set_performance_commitment_admission_v1(true,array[pg_temp.pp_actor(1),pg_temp.pp_actor(2)]);
create temp table pp_saved(name text primary key,value jsonb);
grant select,insert,update on pp_saved to authenticated;
create function pg_temp.pp_id(n text) returns uuid language sql as $$ select (value->>0)::uuid from pp_saved where name=n $$;
create function pg_temp.pp_create(q integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare s timestamptz:='2026-07-02T12:00:00.123456Z'; d timestamptz:='2026-08-31T12:00:00.123456Z'; t jsonb;
 begin
 t:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1');
 return app.create_performance_commitment_at_v1(pg_temp.pp_req(q),360,s,d,'America/Chicago','performance-commitment-fixture-5k-v1',encode(extensions.digest(t::text,'sha256'),'hex'),true,'2026-07-01T12:00:00.123456Z');
end; $$;
select pg_temp.pp_login(1);
set local role authenticated;
insert into pp_saved values('main',jsonb_build_array(pg_temp.pp_create(10)));
select pg_temp.pp_login(2);
insert into pp_saved values('other',jsonb_build_array(pg_temp.pp_create(10)));
reset role;
select pg_temp.pp_login(1);
create function pg_temp.pp_milestone(q integer,title text default 'Choose an event',due timestamptz default '2026-07-10T12:00:00.123456Z',n timestamptz default '2026-07-01T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'milestone_created',null,title,due,null,null,null,null,n) $$;
create function pg_temp.pp_note(q integer,note text default 'First practice run',mid uuid default null,occurred timestamptz default '2026-07-02T13:00:00.123456Z',n timestamptz default '2026-07-03T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'check_in',mid,null,null,null,null,note,occurred,n) $$;
create function pg_temp.pp_status(q integer,status text,revision integer,n timestamptz default '2026-07-04T13:00:00.123456Z')
 returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('main'),'milestone_status',pg_temp.pp_id('milestone'),null,null,status,revision,null,null,n) $$;
select is((select enabled from app.performance_progress_runtime),false,'progress defaults off');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname like 'performance_progress_%' and c.relkind='r' and c.relrowsecurity),6::bigint,'six private tables have RLS');
select ok(not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),r||' cannot access '||c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and c.relname like 'performance_progress_%' and c.relkind='r';
select ok(not has_function_privilege(r,p.oid,'EXECUTE'),r||' cannot call private '||p.proname)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
 where n.nspname='app' and (p.proname like '%performance_progress%v1' or p.proname='write_commitment_progress_at_v1');
set local role authenticated;
select throws_ok('select pg_temp.pp_milestone(20)','42501',null,'gate-off denies new progress');
select lives_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''))','empty history available gate-off');
select throws_ok('select public.set_commitment_progress_enabled_v1(true)','42501',null,'owner cannot open gate');
reset role;
set local role anon;
select throws_ok('select public.get_commitment_progress_v1(null)','42501',null,'anon cannot read');
reset role;
select public.set_commitment_progress_enabled_v1(true);
select public.set_commitment_attempts_enabled_v1(true);
insert into pp_saved values('snapshot',public.get_commitment_attempt_snapshot_v1(pg_temp.pp_id('main')) #- '{agreement,server_now}');
select public.set_commitment_attempts_enabled_v1(false);
set local role authenticated;
insert into pp_saved values('created',pg_temp.pp_milestone(20));
insert into pp_saved values('milestone',jsonb_build_array((select value->>'milestone_id' from pp_saved where name='created')));
select is(pg_temp.pp_milestone(20),(select value from pp_saved where name='created'),'exact create retry returns identical receipt');
select throws_ok('select pg_temp.pp_milestone(20,''Changed name'')','22023',null,'changed request rejected');
select throws_ok('select pg_temp.pp_note(20)','22023',null,'request identity binds operation');
select throws_ok('select public.create_commitment_milestone_v1(null,pg_temp.pp_id(''main''),''Name'',now())','22023',null,'request ID required');
select throws_ok($$select pg_temp.pp_milestone(21,'')$$,'22023',null,'empty name rejected');
select throws_ok('select pg_temp.pp_milestone(21,'' padded '')','22023',null,'names never silently trimmed');
select throws_ok('select pg_temp.pp_milestone(21,repeat(''x'',81))','22023',null,'name bounded');
select throws_ok('select pg_temp.pp_milestone(21,chr(10))','22023',null,'control characters rejected');
select throws_ok('select pg_temp.pp_milestone(21,null)','22023',null,'null name rejected');
select throws_ok('select pg_temp.pp_milestone(21,''Name'',''infinity'')','22023',null,'infinite due date rejected');
select throws_ok('select pg_temp.pp_milestone(21,''Name'',''2026-08-31T12:00:00.123456Z'')','22023',null,'milestone due at deadline rejected');
select throws_ok('select pg_temp.pp_milestone(21,''Name'',''2026-07-01T13:00:00.123455Z'')','22023',null,'past due date rejected by one microsecond');
select lives_ok('select pg_temp.pp_milestone(21,''Before the goal starts'',''2026-07-01T08:00:00.123456-05:00'')','pre-start planning and equal-now UTC offset allowed');
select throws_ok('select pg_temp.pp_note(22,repeat(''x'',501))','22023',null,'notes bounded');
select throws_ok('select pg_temp.pp_note(22,null)','22023',null,'null check-in rejected');
select throws_ok('select pg_temp.pp_note(22,''Practice'',null,''2026-07-03T13:00:00.123457Z'')','22023',null,'future self-report rejected by one microsecond');
select throws_ok('select pg_temp.pp_note(22,''Practice'',null,''2026-07-01T12:00:00.123455Z'')','22023',null,'pre-agreement self-report rejected');
select throws_ok('select pg_temp.pp_note(22,''Practice'',pg_temp.pp_id(''milestone''),''2026-07-01T12:30:00Z'')','22023',null,'linked check-in cannot predate milestone');
select throws_ok('select pg_temp.pp_note(22,''Practice'',pg_temp.pp_req(999))','42501',null,'unknown milestone denied');
insert into pp_saved values('note',pg_temp.pp_note(22,'Ran 5K in 5:59',pg_temp.pp_id('milestone')));
select is((select value->>'provenance' from pp_saved where name='note'),'owner_reported','receipt explicitly self-reported');
select is((select value->'counts_as_proof' from pp_saved where name='note'),'false'::jsonb,'manual time claim is not proof');
select is((select value->>'recorded_at' from pp_saved where name='note'),'2026-07-03T13:00:00.123456+00:00','server receipt preserves microseconds');
select throws_ok('select pg_temp.pp_status(23,''completed'',2)','22023',null,'wrong milestone revision rejected');
insert into pp_saved values('done',pg_temp.pp_status(23,'completed',1));
select is(pg_temp.pp_status(23,'completed',1),(select value from pp_saved where name='done'),'exact transition retry returns receipt');
select throws_ok('select pg_temp.pp_status(24,''completed'',4)','22023',null,'repeated status under new request rejected');
select throws_ok('select pg_temp.pp_status(24,''planned'',1)','22023',null,'stale status update rejected');
insert into pp_saved values('page',public.get_commitment_progress_v1(pg_temp.pp_id('main'),2));
select is((select value->'through_sequence' from pp_saved where name='page'),'4'::jsonb,'first page freezes upper sequence');
select is((select value->'has_more' from pp_saved where name='page'),'true'::jsonb,'bounded page reports more');
select lives_ok('select pg_temp.pp_status(24,''planned'',4)','completed milestone can reopen');
select is(public.get_commitment_progress_v1(pg_temp.pp_id('main'),2,2,4)->'entries'->0->>'sequence','3','next page neither skips nor duplicates');
select is(public.get_commitment_progress_v1(pg_temp.pp_id('main'),2,2,4)->'has_more','false'::jsonb,'snapshot page excludes concurrent append');
select is((select m->>'status' from jsonb_array_elements(public.get_commitment_progress_v1(pg_temp.pp_id('main'),2,2,4)->'milestones') m where m->>'id'=pg_temp.pp_id('milestone')::text),'completed','snapshot milestone status is stable across writes');
select is((select m->>'status' from jsonb_array_elements(public.get_commitment_progress_v1(pg_temp.pp_id('main'))->'milestones') m where m->>'id'=pg_temp.pp_id('milestone')::text),'planned','fresh page sees reopened milestone');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''),101)','22023',null,'page size capped');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''),null)','22023',null,'null page size rejected');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''),50,-1)','22023',null,'negative cursor rejected');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''),50,0,999)','22023',null,'future snapshot rejected');
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''),50,3,2)','22023',null,'reversed cursor rejected');
select lives_ok('select pg_temp.pp_status(25,''retired'',5)','retirement appends history');
select throws_ok('select pg_temp.pp_status(26,''planned'',6)','22023',null,'retirement is terminal');
select throws_ok('select pg_temp.pp_note(26,''Later'',pg_temp.pp_id(''milestone''),''2026-07-05Z'',''2026-07-05Z'')','22023',null,'retired milestone rejects linked check-ins');
select pg_temp.pp_login(2);
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''))','42501',null,'another owner cannot read');
select throws_ok('select pg_temp.pp_milestone(20)','42501',null,'another actor cannot recover request');
select lives_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''other''))','other actor sees own history');
select pg_temp.pp_login(1);
reset role;
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=pg_temp.pp_req(1);
set local role authenticated;
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''))','42501',null,'expired session cannot read');
select throws_ok('select pg_temp.pp_milestone(20)','42501',null,'expired session cannot recover');
reset role;
update auth.sessions set not_after=null where id=pg_temp.pp_req(1);
set local role service_role;
select throws_ok('select public.get_commitment_progress_v1(null)','42501',null,'service cannot impersonate owner read');
reset role;
select public.set_commitment_progress_enabled_v1(false);
set local role authenticated;
select is(pg_temp.pp_milestone(20),(select value from pp_saved where name='created'),'gate-off exact create recovery');
select is(pg_temp.pp_note(22,'Ran 5K in 5:59',pg_temp.pp_id('milestone')),(select value from pp_saved where name='note'),'gate-off check-in recovery');
select is(pg_temp.pp_status(23,'completed',1),(select value from pp_saved where name='done'),'gate-off status recovery');
select throws_ok('select pg_temp.pp_note(40)','42501',null,'gate-off denies new notes');
select lives_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''))','gate-off history readable');
reset role;
select public.set_commitment_attempts_enabled_v1(true);
select is(public.get_commitment_attempt_snapshot_v1(pg_temp.pp_id('main')) #- '{agreement,server_now}',(select value from pp_saved where name='snapshot'),'manual completion and fast run claim leave entire scorer snapshot unchanged');
select is((select count(*) from app.performance_attempt_retention where commitment_id=pg_temp.pp_id('main')),0::bigint,'manual progress never creates proof hold');
select is((select count(*) from app.performance_progress_retention where commitment_id=pg_temp.pp_id('main')),1::bigint,'separate progress retention hold');
select is((select count(*) from app.performance_commitment_enrollments where commitment_id=pg_temp.pp_id('main') and released_at is null),1::bigint,'manual completion never releases slot');
select throws_ok('update app.performance_progress_milestones set title=''Changed''','23001',null,'definitions immutable even in write context');
select throws_ok('delete from app.performance_progress_entries','23001',null,'history retained');
select throws_ok('truncate app.performance_progress_retention','23001',null,'retention cannot truncate');
select set_config('app.performance_progress_write_v1','off',true);
select throws_ok('insert into app.performance_progress_audit(enabled) values(true)','42501',null,'direct writes need RPC context');
select lives_ok($$select * from app.run_raw_evidence_retention('2030-01-01Z',500)$$,'legacy retention runs independently');
select is((select count(*) from app.performance_progress_entries where commitment_id=pg_temp.pp_id('main')),6::bigint,'legacy purge preserves progress');
select public.set_commitment_progress_enabled_v1(true);
set local role authenticated;
select throws_ok('select pg_temp.pp_note(41,''Practice'',null,''2026-08-31T12:00:00.123456Z'',''2026-08-31T12:00:00.123456Z'')','22023',null,'deadline is exclusive');
select lives_ok('select pg_temp.pp_note(41,''Last practice'',null,''2026-08-31T12:00:00.123455Z'',''2026-08-31T12:00:00.123455Z'')','last microsecond before deadline admitted');
reset role;
create function pg_temp.pp_fill() returns void language plpgsql security definer set search_path='' as $$ begin
 for i in 1..32 loop
 perform app.write_commitment_progress_at_v1(pg_temp.pp_req(100+i),pg_temp.pp_id('other'),'milestone_created',null,'Milestone '||i,'2026-07-10Z',null,null,null,null,'2026-07-02Z');
 end loop;
end; $$;
select pg_temp.pp_login(2);
set local role authenticated;
select lives_ok('select pg_temp.pp_fill()','32 milestones admitted on separate owner');
reset role;
create function pg_temp.pp_other(q integer,kind text,mid uuid default null) returns jsonb language sql security definer set search_path='' as $$
 select app.write_commitment_progress_at_v1(pg_temp.pp_req(q),pg_temp.pp_id('other'),kind,mid,case when kind='milestone_created' then 'One more' end,
 case when kind='milestone_created' then '2026-07-10Z'::timestamptz end,null,null,case when kind='check_in' then 'Practice' end,
 case when kind='check_in' then '2026-07-03Z'::timestamptz end,'2026-07-03Z') $$;
set local role authenticated;
select throws_ok('select pg_temp.pp_other(200,''milestone_created'')','54000',null,'33rd milestone rejected');
select throws_ok('select pg_temp.pp_other(201,''check_in'',pg_temp.pp_id(''milestone''))','42501',null,'milestone cannot cross agreement or owner');
reset role;
create function pg_temp.pp_fill_notes() returns void language plpgsql security definer set search_path='' as $$ begin
 for i in 1..480 loop perform pg_temp.pp_other(1000+i,'check_in'); end loop;
end; $$;
set local role authenticated;
select lives_ok('select pg_temp.pp_fill_notes()','history bounded at 512 entries');
select throws_ok('select pg_temp.pp_other(2000,''check_in'')','54000',null,'513th entry rejected');
select lives_ok('select pg_temp.pp_other(1480,''check_in'')','exact retry survives full history');
select lives_ok('select public.close_performance_commitment_v1(pg_temp.pp_req(2001),pg_temp.pp_id(''other''),''withdrawal'')','full history never blocks safe exit');
select lives_ok('select pg_temp.pp_other(1480,''check_in'')','recovery survives safe closure');
select throws_ok('select pg_temp.pp_other(2002,''check_in'')','42501',null,'closed agreement denies new notes');
select lives_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''other''),100)','closed history remains readable');
reset role;
select public.delete_account(pg_temp.pp_actor(1));
select is((select count(*) from app.performance_progress_entries where commitment_id=pg_temp.pp_id('main')),7::bigint,'deletion retains progress');
select is((select count(*) from app.performance_progress_requests where actor_id=pg_temp.pp_actor(1)),7::bigint,'deletion retains exact receipts');
select is((select count(*) from app.performance_progress_retention where commitment_id=pg_temp.pp_id('main')),1::bigint,'deletion retains product hold');
select pg_temp.pp_login(1);
set local role authenticated;
select throws_ok('select public.get_commitment_progress_v1(pg_temp.pp_id(''main''))','42501',null,'deleted owner cannot read history');
select throws_ok('select pg_temp.pp_milestone(20)','42501',null,'deleted owner cannot recover old requests');
reset role;
select * from finish();
rollback;
