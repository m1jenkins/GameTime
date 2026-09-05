-- Real PostgreSQL sessions, observed lock waits, fictional progress only.
begin;
select no_plan();
select extensions.dblink_connect('pp_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('pp_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pp_race_one');
select extensions.dblink_connect('pp_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pp_race_two');
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$select ('e8100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$select ('e8200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table saved(name text primary key,id uuid);
create function pg_temp.id(n text) returns uuid language sql as $$select id from saved where name=n$$;
select extensions.dblink_exec('pp_setup',$setup$
begin;
insert into auth.users(id) values('e8100000-0000-0000-0000-000000000001');
insert into public.profiles(id,handle,display_name,timezone) values('e8100000-0000-0000-0000-000000000001','pprace01','Fictional Runner','UTC');
insert into auth.sessions(id,user_id) values('e8200000-0000-0000-0000-000000000001','e8100000-0000-0000-0000-000000000001');
create temp table pp_setup_ids(name text primary key,id uuid);
create function pg_temp.setup() returns void language plpgsql security definer set search_path='' as $fn$
declare c uuid; m uuid; s timestamptz:=clock_timestamp()-interval '9 days'; d timestamptz; terms jsonb;
begin
 d:=s+interval '60 days';
 terms:=app.performance_commitment_terms_v1(auth.uid(),360,s,d,'UTC','performance-commitment-fixture-5k-v1');
 c:=app.create_performance_commitment_at_v1('e8200000-0000-0000-0000-000000000010',360,s,d,'UTC','performance-commitment-fixture-5k-v1',encode(extensions.digest(terms::text,'sha256'),'hex'),true,s-interval '1 day');
 insert into pg_temp.pp_setup_ids values('main',c);
 m:=(public.create_commitment_milestone_v1('e8200000-0000-0000-0000-000000000011',c,'First event',s+interval '20 days')->>'milestone_id')::uuid;
 insert into pg_temp.pp_setup_ids values('milestone',m);
end; $fn$;
do $fn$ begin
 perform public.set_performance_commitment_admission_v1(true,array['e8100000-0000-0000-0000-000000000001'::uuid]);
 perform public.set_commitment_progress_enabled_v1(true);
end; $fn$;
set local request.jwt.claim.sub='e8100000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"e8100000-0000-0000-0000-000000000001","role":"authenticated","session_id":"e8200000-0000-0000-0000-000000000001"}';
set local role authenticated;
do $fn$ begin perform pg_temp.setup(); end; $fn$;
reset role;
commit;
$setup$);
insert into saved select name,id from extensions.dblink('pp_setup','select name,id from pp_setup_ids') x(name text,id uuid);
select extensions.dblink_exec('pp_one',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('e8100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('e8100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('e8200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
select extensions.dblink_exec('pp_two',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('e8100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('e8100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('e8200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('pp_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('pp_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('pp_one',first_sql) x(r text);
 perform extensions.dblink_send_query('pp_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='pp_race_two'
    and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('pp_one','commit');
 select x.r into second_result from extensions.dblink_get_result('pp_two') x(r text);
 perform * from extensions.dblink_get_result('pp_two') x(r text);
 perform extensions.dblink_exec('pp_two','commit');
 return next;
end; $$;

create function pg_temp.query(q text) returns text language sql as $$ select format('select pg_temp.action(1,%L)',q) $$;
-- Freeze the report instant once for all exact retry race queries.
create temp table report_time as select clock_timestamp()-interval '1 day' as occurred_at;
create function pg_temp.note(q integer,note text default 'Practice run') returns text language sql as $$
 select pg_temp.query(format('select public.record_commitment_progress_v1(%L,%L,%L,%L)->>''sequence''',pg_temp.req(q),pg_temp.id('main'),note,(select occurred_at from report_time))) $$;
create function pg_temp.status(q integer,status text,revision integer) returns text language sql as $$
 select pg_temp.query(format('select public.set_commitment_milestone_status_v1(%L,%L,%L,%L,%s)->>''sequence''',pg_temp.req(q),pg_temp.id('main'),pg_temp.id('milestone'),status,revision)) $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'exact check-in retries',* from pg_temp.race(pg_temp.note(20),pg_temp.note(20));
select is(first_result,second_result,'competing exact check-ins return identical sequence') from outcomes where name='exact check-in retries';
select is((select second_result from outcomes where name='exact check-in retries'),'2','one manual check-in committed');
insert into outcomes select 'changed exact payload',* from pg_temp.race(pg_temp.note(21,'Practice A'),pg_temp.note(21,'Practice B'));
select is((select second_result from outcomes where name='changed exact payload'),'22023','waiting changed payload cannot reuse request');
insert into outcomes select 'competing status updates',* from pg_temp.race(pg_temp.status(22,'completed',1),pg_temp.status(23,'retired',1));
select is((select first_result from outcomes where name='competing status updates'),'4','first status change committed');
select is((select second_result from outcomes where name='competing status updates'),'22023','waiting status update observes changed revision');
insert into outcomes select 'exact status retries',* from pg_temp.race(pg_temp.status(24,'planned',4),pg_temp.status(24,'planned',4));
select is(first_result,second_result,'exact concurrent status changes append once') from outcomes where name='exact status retries';
insert into outcomes select 'gate shutdown then check-in',* from pg_temp.race('select public.set_commitment_progress_enabled_v1(false)::text',pg_temp.note(25));
select is((select second_result from outcomes where name='gate shutdown then check-in'),'42501','waiting check-in sees shutdown');
select x.r from extensions.dblink('pp_setup','select public.set_commitment_progress_enabled_v1(true)::text') x(r text);
select extensions.dblink_exec('pp_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''e8100000-0000-0000-0000-000000000001''');
insert into outcomes select 'natural expiry while waiting',* from pg_temp.race('select singleton::text from app.performance_progress_runtime for update',pg_temp.note(26),0.8);
select is((select second_result from outcomes where name='natural expiry while waiting'),'42501','natural session expiry rechecked after runtime wait');
select extensions.dblink_exec('pp_setup','update auth.sessions set not_after=null where user_id=''e8100000-0000-0000-0000-000000000001''');
insert into outcomes select 'withdrawal then check-in',* from pg_temp.race(pg_temp.query(format('select public.close_performance_commitment_v1(%L,%L,''withdrawal'')::text',pg_temp.req(27),pg_temp.id('main'))),pg_temp.note(28));
select is((select second_result from outcomes where name='withdrawal then check-in'),'42501','waiting note observes safe closure');
insert into outcomes select 'session revocation then recovery',* from pg_temp.race(format('with d as (delete from auth.sessions where user_id=%L returning id) select count(*)::text from d',pg_temp.actor(1)),pg_temp.note(20));
select is((select second_result from outcomes where name='session revocation then recovery'),'42501','revoked session cannot recover receipt');
select extensions.dblink_exec('pp_setup','insert into auth.sessions(id,user_id) values(''e8200000-0000-0000-0000-000000000001'',''e8100000-0000-0000-0000-000000000001'')');
insert into outcomes select 'deletion then history read',* from pg_temp.race(format('select public.delete_account(%L)::text',pg_temp.actor(1)),pg_temp.query(format('select public.get_commitment_progress_v1(%L)::text',pg_temp.id('main'))));
select is((select second_result from outcomes where name='deletion then history read'),'42501','waiting history read sees deletion');
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select is((select x.n from extensions.dblink('pp_setup','select count(*) from app.performance_progress_entries where commitment_id in(select id from pp_setup_ids where name=''main'')') x(n bigint)),5::bigint,'only five authorized entries retained after deletion');
select is((select x.n from extensions.dblink('pp_setup','select count(*) from app.performance_progress_retention where commitment_id in(select id from pp_setup_ids where name=''main'')') x(n bigint)),1::bigint,'progress hold survives deletion');
-- Local test cleanup is limited to this fictional namespace.
select extensions.dblink_exec('pp_setup',$cleanup$
begin;
set local session_replication_role=replica;
delete from app.performance_progress_requests where actor_id::text like 'e8100000-%';
delete from app.performance_progress_entries where commitment_id in(select id from pp_setup_ids where name='main');
delete from app.performance_progress_milestones where commitment_id in(select id from pp_setup_ids where name='main');
delete from app.performance_progress_retention where commitment_id in(select id from pp_setup_ids where name='main');
delete from app.performance_commitment_requests where actor_id::text like 'e8100000-%';
delete from app.performance_commitment_enrollments where actor_id::text like 'e8100000-%';
delete from app.performance_commitment_consents where actor_id::text like 'e8100000-%';
delete from app.performance_commitment_agreements where actor_id::text like 'e8100000-%';
delete from app.performance_commitment_beta_allowlist where actor_id::text like 'e8100000-%';
update app.performance_commitment_runtime set admission_enabled=false;
update app.performance_progress_runtime set enabled=false;
delete from app.profile_handle_claims where actor_id::text like 'e8100000-%';
delete from app.active_profile_auth_bindings where actor_id::text like 'e8100000-%';
delete from public.profiles where id::text like 'e8100000-%';
delete from auth.sessions where user_id::text like 'e8100000-%';
delete from auth.users where id::text like 'e8100000-%';
commit;
$cleanup$);
select extensions.dblink_disconnect('pp_one');
select extensions.dblink_disconnect('pp_two');
select extensions.dblink_disconnect('pp_setup');
select * from finish();
rollback;
