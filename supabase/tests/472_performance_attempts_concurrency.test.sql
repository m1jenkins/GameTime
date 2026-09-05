-- Real PostgreSQL sessions, observed waits, isolated fictional actors.
begin;
select no_plan();
select extensions.dblink_connect('pa_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('pa_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pa_race_one');
select extensions.dblink_connect('pa_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pa_race_two');
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$select ('ef100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$select ('ef200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table saved(name text primary key,id uuid);
create function pg_temp.id(n text) returns uuid language sql as $$select id from saved where name=n$$;
select extensions.dblink_exec('pa_setup',$setup$
begin;
insert into auth.users(id) select ('ef100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,3) n;
insert into public.profiles(id,handle,display_name,timezone) select id,'parace'||right(id::text,2),'Fictional Runner','UTC' from auth.users where id::text like 'ef100000-%';
insert into auth.sessions(id,user_id) select replace(id::text,'ef100000','ef200000')::uuid,id from auth.users where id::text like 'ef100000-%';
create temp table pa_setup_ids(name text primary key,id uuid);
create function pg_temp.setup() returns void language plpgsql security definer set search_path='' as $fn$
declare c uuid; a uuid; s timestamptz:=clock_timestamp()-interval '9 days'; d timestamptz; terms jsonb;
begin
 d:=s+interval '60 days';
 terms:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'UTC','performance-commitment-fixture-5k-v1');
 c:=app.create_performance_commitment_at_v1('ef200000-0000-0000-0000-000000000010',360,s,d,'UTC','performance-commitment-fixture-5k-v1',encode(extensions.digest(terms::text,'sha256'),'hex'),true,s-interval '1 day');
 insert into pg_temp.pa_setup_ids values('main',c);
 a:=app.nominate_commitment_attempt_at_v1('ef200000-0000-0000-0000-000000000011',c,'ef200000-0000-0000-0000-000000000101','bib-1',s-interval '1 hour');
 insert into pg_temp.pa_setup_ids values('attempt',a);
end; $fn$;
do $fn$ begin
 perform public.set_performance_commitment_admission_v1(true,array['ef100000-0000-0000-0000-000000000001'::uuid]);
 perform public.set_commitment_attempts_enabled_v1(true);
 perform public.curate_commitment_fixture_event_v1('ef200000-0000-0000-0000-000000000101',clock_timestamp()-interval '8 days',clock_timestamp()-interval '8 days'+interval '2 hours');
 perform public.curate_commitment_fixture_event_v1('ef200000-0000-0000-0000-000000000102',clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 2 hours');
 perform public.curate_commitment_fixture_event_v1('ef200000-0000-0000-0000-000000000103',clock_timestamp()+interval '3 days',clock_timestamp()+interval '3 days 2 hours');
end; $fn$;
set local request.jwt.claim.sub='ef100000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"ef100000-0000-0000-0000-000000000001","role":"authenticated","session_id":"ef200000-0000-0000-0000-000000000001"}';
set local role authenticated;
do $fn$ begin perform pg_temp.setup(); end; $fn$;
reset role;
do $fn$ declare c uuid; a uuid; e app.performance_attempt_events; doc jsonb; begin
 select id into c from pa_setup_ids where name='main'; select id into a from pa_setup_ids where name='attempt';
 select * into e from app.performance_attempt_events where id='ef200000-0000-0000-0000-000000000101';
 perform public.set_commitment_attempt_reviewer_v1('ef200000-0000-0000-0000-000000000201',c,'ef100000-0000-0000-0000-000000000002',true);
 perform public.set_commitment_attempt_reviewer_v1('ef200000-0000-0000-0000-000000000202',c,'ef100000-0000-0000-0000-000000000003',true);
 for i in 1..3 loop
 doc:=jsonb_build_object('source','fixture_official_5k_v1','event_id',e.id,'distance_meters',5000,'timing_basis','organizer_chip','precision_ms',1000,'published_bib','bib-1','status','finished','chip_seconds',358+i,'started_at',e.starts_at,'finished_at',e.starts_at+(358+i)*interval '1 second');
 perform public.capture_commitment_attempt_fixture_v1(('ef200000-0000-0000-0000-'||lpad((300+i)::text,12,'0'))::uuid,c,a,doc);
 end loop;
end; $fn$;
commit;
$setup$);
insert into saved select name,id from extensions.dblink('pa_setup','select name,id from pa_setup_ids') x(name text,id uuid);
select extensions.dblink_exec('pa_one',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('ef100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('ef100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('ef200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
select extensions.dblink_exec('pa_two',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('ef100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('ef100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('ef200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('pa_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('pa_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('pa_one',first_sql) x(r text);
 perform extensions.dblink_send_query('pa_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='pa_race_two'
    and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('pa_one','commit');
 select x.r into second_result from extensions.dblink_get_result('pa_two') x(r text);
 perform * from extensions.dblink_get_result('pa_two') x(r text);
 perform extensions.dblink_exec('pa_two','commit');
 return next;
end; $$;

create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
create function pg_temp.query(n integer,q text) returns text language sql as $$select format('select pg_temp.action(%s,%L)',n,q)$$;
-- Reviewers must actually retrieve each source before reviewing it.
select x.r from extensions.dblink('pa_one',pg_temp.query(2,format('select public.get_commitment_attempt_source_v1(%L,%L)',pg_temp.id('main'),pg_temp.req(301)))) x(r text);
select x.r from extensions.dblink('pa_two',pg_temp.query(3,format('select public.get_commitment_attempt_source_v1(%L,%L)',pg_temp.id('main'),pg_temp.req(301)))) x(r text);
create function pg_temp.review(actor integer,q integer,s integer,previous integer) returns text language sql as $$
 select pg_temp.query(actor,format('select public.review_commitment_attempt_v1(%L,%L,%L,%s,true)',pg_temp.req(q),pg_temp.id('main'),pg_temp.req(s),coalesce(previous::text,'null'))) $$;
create function pg_temp.nominate(q integer,e integer) returns text language sql as $$
 select pg_temp.query(1,format('select public.nominate_commitment_attempt_v1(%L,%L,%L,''bib-1'')',pg_temp.req(q),pg_temp.id('main'),pg_temp.req(e))) $$;
insert into outcomes select 'competing reviews',* from pg_temp.race(pg_temp.review(2,401,301,null),pg_temp.review(3,402,301,null));
select is((select first_result from outcomes where name='competing reviews'),'1','first reviewer appends once');
select is((select second_result from outcomes where name='competing reviews'),'22023','waiting reviewer sees changed predecessor');
select x.r from extensions.dblink('pa_one',pg_temp.query(2,format('select public.get_commitment_attempt_source_v1(%L,%L)',pg_temp.id('main'),pg_temp.req(302)))) x(r text);
insert into outcomes select 'exact correction retries',* from pg_temp.race(pg_temp.review(2,403,302,1),pg_temp.review(2,403,302,1));
select is(first_result,second_result,'concurrent exact correction retries return one revision') from outcomes where name='exact correction retries';
select is((select second_result from outcomes where name='exact correction retries'),'2','one correction appended');
insert into outcomes select 'duplicate event nominations',* from pg_temp.race(pg_temp.nominate(501,102),pg_temp.nominate(502,102));
select is((select second_result from outcomes where name='duplicate event nominations'),'23505','one nomination per event under contention');
insert into outcomes select 'gate off then nominate',* from pg_temp.race('select public.set_commitment_attempts_enabled_v1(false)::text',pg_temp.nominate(503,103));
select is((select second_result from outcomes where name='gate off then nominate'),'42501','waiting nomination observes gate-off');
select x.r from extensions.dblink('pa_setup','select public.set_commitment_attempts_enabled_v1(true)::text') x(r text);
select x.r from extensions.dblink('pa_one',pg_temp.query(2,format('select public.get_commitment_attempt_source_v1(%L,%L)',pg_temp.id('main'),pg_temp.req(303)))) x(r text);
insert into outcomes select 'grant revoked then correction',* from pg_temp.race(
 format('select public.set_commitment_attempt_reviewer_v1(%L,%L,%L,false)::text',pg_temp.req(203),pg_temp.id('main'),pg_temp.actor(2)),pg_temp.review(2,404,303,2));
select is((select second_result from outcomes where name='grant revoked then correction'),'42501','waiting correction observes revoked grant');
select x.r from extensions.dblink('pa_two',pg_temp.query(3,format('select public.get_commitment_attempt_source_v1(%L,%L)',pg_temp.id('main'),pg_temp.req(303)))) x(r text);
insert into outcomes select 'session revoked then correction',* from pg_temp.race(
 format('with d as (delete from auth.sessions where user_id=%L returning id) select count(*)::text from d',pg_temp.actor(3)),pg_temp.review(3,405,303,2));
select is((select second_result from outcomes where name='session revoked then correction'),'42501','waiting correction observes session revocation');
select extensions.dblink_exec('pa_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''ef100000-0000-0000-0000-000000000001''');
insert into outcomes select 'session expiry while waiting',* from pg_temp.race('select singleton::text from app.performance_attempt_runtime for update',pg_temp.nominate(504,103),0.8);
select is((select second_result from outcomes where name='session expiry while waiting'),'42501','session natural expiry rechecked after wait');
select extensions.dblink_exec('pa_setup','update auth.sessions set not_after=null where user_id=''ef100000-0000-0000-0000-000000000001''');
insert into outcomes select 'deletion then nomination',* from pg_temp.race(format('select public.delete_account(%L)::text',pg_temp.actor(1)),pg_temp.nominate(505,103));
select is((select second_result from outcomes where name='deletion then nomination'),'42501','waiting nomination sees deletion');
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select is((select x.n from extensions.dblink('pa_setup','select count(*) from app.performance_attempt_revisions where commitment_id in(select id from pa_setup_ids where name=''main'')') x(n bigint)),2::bigint,'only two authorized revisions retained');
select is((select x.n from extensions.dblink('pa_setup','select count(*) from app.performance_attempt_sources where commitment_id in(select id from pa_setup_ids where name=''main'')') x(n bigint)),3::bigint,'deletion preserves all proof sources');
-- Test-only cleanup, exclusively the fictional namespace and local gates.
select extensions.dblink_exec('pa_setup',$cleanup$
begin;
set local session_replication_role=replica;
delete from app.performance_attempt_audit where commitment_id in(select id from pa_setup_ids where name='main');
delete from app.performance_attempt_requests where actor_id::text like 'ef100000-%';
delete from app.performance_attempt_revisions where commitment_id in(select id from pa_setup_ids where name='main');
delete from app.performance_attempt_sources where id::text like 'ef200000-%';
delete from app.performance_attempt_grants where reviewer_id::text like 'ef100000-%';
delete from app.performance_attempt_confirmations where commitment_id in(select id from pa_setup_ids where name='main');
delete from app.performance_attempt_retention where commitment_id in(select id from pa_setup_ids where name='main');
delete from app.performance_attempt_nominations where commitment_id in(select id from pa_setup_ids where name='main');
delete from app.performance_attempt_events where id::text like 'ef200000-%';
delete from app.performance_commitment_requests where actor_id::text like 'ef100000-%';
delete from app.performance_commitment_enrollments where actor_id::text like 'ef100000-%';
delete from app.performance_commitment_consents where actor_id::text like 'ef100000-%';
delete from app.performance_commitment_agreements where actor_id::text like 'ef100000-%';
delete from app.performance_commitment_beta_allowlist where actor_id::text like 'ef100000-%';
update app.performance_commitment_runtime set admission_enabled=false;
update app.performance_attempt_runtime set enabled=false;
delete from app.profile_handle_claims where actor_id::text like 'ef100000-%';
delete from app.active_profile_auth_bindings where actor_id::text like 'ef100000-%';
delete from public.profiles where id::text like 'ef100000-%';
delete from auth.sessions where user_id::text like 'ef100000-%';
delete from auth.users where id::text like 'ef100000-%';
commit;
$cleanup$);
select extensions.dblink_disconnect('pa_one');
select extensions.dblink_disconnect('pa_two');
select extensions.dblink_disconnect('pa_setup');
select * from finish();
rollback;
