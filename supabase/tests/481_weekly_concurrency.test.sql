begin;
select no_plan();
select extensions.dblink_connect('weekly_setup','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=weekly_setup');
select extensions.dblink_connect('weekly_one','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=weekly_race_one');
select extensions.dblink_connect('weekly_two','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres application_name=weekly_race_two');
select extensions.dblink_exec('weekly_setup',$setup$-- Rollback-only fictional fixtures. Caller owns BEGIN/ROLLBACK. No hosted runner.
insert into auth.users(id) select ('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.profiles(id,handle,display_name,timezone)
 select id,'weeklyfixture'||right(id::text,4),'Weekly Fixture','America/Chicago' from auth.users where id::text like 'ed000000-%';
insert into auth.sessions(id,user_id)
 select ('ee000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,40) n;
insert into public.friendships(user_a,user_b,requested_by,status)
 select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b where a.id::text like 'ed000000-%' and b.id::text like 'ed000000-%' and a.id<b.id;
do $d$ begin perform public.set_weekly_runtime_v1(true,true,true,array(select id from public.profiles where id::text like 'ed000000-%')); end; $d$;$setup$);
do $outer$ declare c text; begin foreach c in array array['weekly_setup','weekly_one','weekly_two'] loop perform extensions.dblink_exec(c,$helpers$create function pg_temp.actor(n integer) returns uuid language sql as $$select ('ed000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql as $$select ('ee000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.login(n integer) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.actor(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor(n),'session_id',pg_temp.req(n))::text,true);
 perform set_config('role','authenticated',true);
end; $$;
create function pg_temp.terms(first_actor integer,total integer,week date default '2026-09-07',stamp timestamptz default '2026-08-31T10:00:00Z') returns jsonb
language sql security definer set search_path='' as $$select app.weekly_terms_v1((select jsonb_agg(jsonb_build_object('actor_id',pg_temp.actor(n),'target_steps',70000)) from generate_series(first_actor,first_actor+total-1) n),week,'America/Chicago',pg_temp.actor(first_actor),stamp)$$;
create function pg_temp.create_friend(r uuid,t jsonb,n timestamptz default '2026-08-31T10:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_create_at_v1(r,t,encode(extensions.digest(t::text,'sha256'),'hex'),true,n)$$;
create function pg_temp.accept(r uuid,c uuid,n timestamptz default '2026-08-31T11:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_join_at_v1(r,c,(select terms_digest from app.weekly_agreements where id=c),true,(select mode from app.weekly_agreements where id=c),n)$$;
create function pg_temp.exit(r uuid,c uuid,k text,n timestamptz default '2026-09-08T11:00:00Z') returns uuid
language sql security definer set search_path='' as $$select app.weekly_exit_at_v1(r,c,k,n)$$;
create function pg_temp.file(r uuid,c uuid,rev integer,reason text,n timestamptz) returns uuid
language sql security definer set search_path='' as $$select app.weekly_file_at_v1(r,c,rev,reason,n)$$;
create function pg_temp.make_friend(first_actor integer,total integer,week date default '2026-09-07') returns uuid language plpgsql as $$
declare c uuid; n integer; begin
 perform pg_temp.login(first_actor); c:=pg_temp.create_friend(extensions.gen_random_uuid(),pg_temp.terms(first_actor,total,week));
 for n in first_actor+1..first_actor+total-1 loop perform pg_temp.login(n); perform pg_temp.accept(extensions.gen_random_uuid(),c); end loop;
 perform set_config('role','none',true); return c;
end; $$;
create function pg_temp.capture(c uuid,steps integer,status text default 'complete',n timestamptz default '2026-09-15T04:00:00Z') returns void language plpgsql as $$
declare actor uuid; day date; begin
 for actor in select actor_id from app.weekly_participants where challenge_id=c and accepted_at is not null loop
  for day in select (x->>'date')::date from app.weekly_agreements g cross join lateral jsonb_array_elements(g.terms->'days') x where id=c loop
   perform app.weekly_fixture_at_v1(extensions.gen_random_uuid(),c,actor,day,status,steps,n);
  end loop;
 end loop;
end; $$;

create function pg_temp.friend_id(a integer) returns uuid language sql security definer set search_path='' as $f$select id from app.weekly_agreements where creator_id=pg_temp.actor(a)$f$;
create function pg_temp.call(actor integer,command text) returns text language plpgsql as $fn$
declare result text; begin
 if actor>0 then perform pg_temp.login(actor); end if;
 execute command into result; perform set_config('role','none',true); return result;
exception when others then perform set_config('role','none',true); return sqlstate;
end; $fn$;
$helpers$); end loop; end; $outer$;
create temp table ids(name text primary key,id uuid);
insert into ids select 'friend1',r from extensions.dblink('weekly_setup',$sql$select pg_temp.call(1,'select pg_temp.create_friend(pg_temp.req(101),pg_temp.terms(1,2))')$sql$) x(r uuid);
insert into ids select 'friend3',r from extensions.dblink('weekly_setup',$sql$select pg_temp.call(3,'select pg_temp.create_friend(pg_temp.req(103),pg_temp.terms(3,2))')$sql$) x(r uuid);
insert into ids select 'friend5',r from extensions.dblink('weekly_setup',$sql$select pg_temp.call(5,'select pg_temp.create_friend(pg_temp.req(105),pg_temp.terms(5,2))')$sql$) x(r uuid);
insert into ids select 'friend7',r from extensions.dblink('weekly_setup',$sql$select pg_temp.call(7,'select pg_temp.create_friend(pg_temp.req(107),pg_temp.terms(7,2))')$sql$) x(r uuid);
insert into ids select 'friend9',r from extensions.dblink('weekly_setup',$sql$select pg_temp.call(9,'select pg_temp.create_friend(pg_temp.req(109),pg_temp.terms(9,2))')$sql$) x(r uuid);
select extensions.dblink_exec('weekly_setup',$setup$do $d$ begin
 perform pg_temp.login(8); perform pg_temp.accept(pg_temp.req(108),pg_temp.friend_id(7)); perform set_config('role','none',true);
 perform pg_temp.login(10); perform pg_temp.accept(pg_temp.req(110),pg_temp.friend_id(9)); perform set_config('role','none',true);
 perform pg_temp.capture(pg_temp.friend_id(7),10000);
 perform pg_temp.capture(pg_temp.friend_id(9),10000);
 perform app.weekly_curate_at_v1(pg_temp.req(200),'2026-09-07','America/Chicago',70000,2,'2026-08-31T10:00:00Z');
 perform app.weekly_curate_at_v1(pg_temp.req(201),'2026-09-07','America/Chicago',70000,30,'2026-08-31T10:00:00Z');
 perform app.weekly_curate_at_v1(pg_temp.req(202),'2026-09-07','America/Chicago',70000,30,'2026-08-31T10:00:00Z');
 perform pg_temp.login(20); perform pg_temp.accept(pg_temp.req(300),pg_temp.req(200)); perform set_config('role','none',true);
 perform pg_temp.login(36); perform public.set_weekly_pilot_consent_v1(pg_temp.req(301),true); perform set_config('role','none',true);
 perform pg_temp.login(7); perform public.set_weekly_sharing_v1(pg_temp.req(501),pg_temp.friend_id(7),pg_temp.actor(37),true); perform set_config('role','none',true);
 perform pg_temp.login(37); perform public.respond_weekly_follow_v1(pg_temp.req(502),pg_temp.friend_id(7),pg_temp.actor(7),pg_temp.req(501),'accept'); perform set_config('role','none',true);
end; $d$;$setup$);
create function pg_temp.race(first_sql text,second_sql text,p_delay numeric default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds'; begin
 perform extensions.dblink_exec('weekly_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('weekly_two','begin; set local statement_timeout=''8s''');
 select r into first_result from extensions.dblink('weekly_one',first_sql) x(r text);
 perform extensions.dblink_send_query('weekly_two',second_sql);
 loop
  perform pg_stat_clear_snapshot(); select exists(select 1 from pg_stat_activity where application_name='weekly_race_two' and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>deadline; perform pg_sleep(.01);
 end loop;
 if p_delay>0 then perform pg_sleep(p_delay::double precision); end if;
 perform extensions.dblink_exec('weekly_one','commit');
 select r into second_result from extensions.dblink_get_result('weekly_two') x(r text);
 perform * from extensions.dblink_get_result('weekly_two') x(r text);
 perform extensions.dblink_exec('weekly_two','commit'); return next;
end; $$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
insert into outcomes select 'capacity',* from pg_temp.race(
 $$select pg_temp.call(21,'select pg_temp.accept(pg_temp.req(401),pg_temp.req(200))')$$,
 $$select pg_temp.call(22,'select pg_temp.accept(pg_temp.req(402),pg_temp.req(200))')$$);
select is((select second_result from outcomes where name='capacity'),'23505','simultaneous community join respects capacity');
insert into outcomes select 'cancel_accept',r.* from ids cross join lateral pg_temp.race(
 format('select pg_temp.call(1,%L)',format('select pg_temp.exit(pg_temp.req(403),%L,''cancel'',''2026-08-31T12:00:00Z'')',id)),
 format('select pg_temp.call(2,%L)',format('select pg_temp.accept(pg_temp.req(404),%L)',id))) r where ids.name='friend1';
select is((select second_result from outcomes where name='cancel_accept'),'55000','cancel wins over waiting accept');
insert into outcomes select 'block_accept',r.* from ids cross join lateral pg_temp.race(
 $$select pg_temp.call(3,'insert into public.blocks(blocker_id,blocked_id) values(pg_temp.actor(3),pg_temp.actor(4)) returning blocker_id')$$,
 format('select pg_temp.call(4,%L)',format('select pg_temp.accept(pg_temp.req(405),%L)',id))) r where ids.name='friend3';
select is((select second_result from outcomes where name='block_accept'),'42501','block wins over waiting accept');
insert into outcomes select 'delete_accept',r.* from ids cross join lateral pg_temp.race(
 $$select pg_temp.call(0,'select public.delete_account(pg_temp.actor(5))')$$,
 format('select pg_temp.call(6,%L)',format('select pg_temp.accept(pg_temp.req(406),%L)',id))) r where ids.name='friend5';
select is((select second_result from outcomes where name='delete_accept'),'55000','deletion closes group before waiting accept');
insert into outcomes select 'overlap',* from pg_temp.race(
 $$select pg_temp.call(25,'select pg_temp.accept(pg_temp.req(407),pg_temp.req(201))')$$,
 $$select pg_temp.call(25,'select pg_temp.accept(pg_temp.req(408),pg_temp.req(202))')$$);
select is((select second_result from outcomes where name='overlap'),'23505','same actor simultaneous overlapping enrollments serialize');
create temp table snapshots(name text,i jsonb);
insert into snapshots select name,x.i from ids cross join lateral extensions.dblink('weekly_setup',format('select app.weekly_load_at_v1(%L,''2026-09-16T04:00:00Z'')',id)) x(i jsonb) where name in ('friend7','friend9');
create function pg_temp.final_query(i jsonb) returns text language sql as $$select format('select pg_temp.call(0,%L)',format('select app.weekly_commit_at_v1(%L,%L,%L)',i,
 jsonb_build_object('version','weekly-lifecycle-v1','agreementId',i->'agreement'->>'id','termsDigest',i->'agreement'->>'termsDigest','phase','final','reason','safe_fixture_refund',
 'qualifications',(select jsonb_agg(jsonb_build_object('participantId',x->>'actor_id','qualification','refund')) from jsonb_array_elements(i->'participants') x)),i->>'now'))$$;
insert into outcomes select 'correction_final',r.* from snapshots cross join lateral pg_temp.race(
 format('select pg_temp.call(0,%L)',format('select app.weekly_fixture_at_v1(pg_temp.req(409),%L,pg_temp.actor(7),''2026-09-07'',''complete'',0,''2026-09-16T03:00:00Z'')',i->'agreement'->>'id')),
 pg_temp.final_query(i)) r where snapshots.name='friend7';
select is((select second_result from outcomes where name='correction_final'),'stale','correction invalidates competing final snapshot');
insert into outcomes select 'final_correction',r.* from snapshots cross join lateral pg_temp.race(pg_temp.final_query(i),
 format('select pg_temp.call(0,%L)',format('select app.weekly_fixture_at_v1(pg_temp.req(410),%L,pg_temp.actor(9),''2026-09-07'',''complete'',0,''2026-09-16T03:00:00Z'')',i->'agreement'->>'id'))) r where snapshots.name='friend9';
select is((select second_result from outcomes where name='final_correction'),'22023','final blocks late correction');
select is((select count(*) from app.weekly_results where challenge_id=(select id from ids where name='friend9')),1::bigint,'exactly one immutable final persisted');
insert into outcomes select 'allocation_allocation',r.* from ids cross join lateral pg_temp.race(
 format('select public.settle_weekly_simulation_v1(%L)',id),format('select public.settle_weekly_simulation_v1(%L)',id)) r where ids.name='friend9';
select is((select first_result from outcomes where name='allocation_allocation'),(select second_result from outcomes where name='allocation_allocation'),'simultaneous allocations return identical single ledger record');
select extensions.dblink_exec('weekly_setup',$sql$update auth.sessions set not_after=clock_timestamp()+interval '1 second' where id='ee000000-0000-0000-0000-000000000035'$sql$);
insert into outcomes select 'expiry_wait',* from pg_temp.race(
 $$select id from app.weekly_agreements where id='ee000000-0000-0000-0000-000000000202' for update$$,
 $$select pg_temp.call(35,'select pg_temp.accept(pg_temp.req(411),pg_temp.req(202))')$$,1.2);
select is((select second_result from outcomes where name='expiry_wait'),'42501','session expiry while waiting on agreement denies mutation');
insert into outcomes select 'retire_create',* from pg_temp.race(
 $$select pg_temp.call(33,'select public.resolve_weekly_request_v1(pg_temp.req(412))')$$,
 $$select pg_temp.call(33,'select pg_temp.create_friend(pg_temp.req(412),pg_temp.terms(33,2))')$$);
select is((select second_result from outcomes where name='retire_create'),'55000','retirement serializes against delayed original create');
insert into outcomes select 'revoke_event',* from pg_temp.race(
 $$select pg_temp.call(36,'select public.set_weekly_pilot_consent_v1(pg_temp.req(413),false)')$$,
 $$select pg_temp.call(36,'select public.record_weekly_pilot_event_v1(pg_temp.req(414),null,''rule_preview'',''exposure'')')$$);
select is((select second_result from outcomes where name='revoke_event'),'42501','consent revocation wins over optional measurement append');
insert into outcomes select 'share_revoke_read',r.* from ids cross join lateral pg_temp.race(
 format('select pg_temp.call(7,%L)',format('select public.set_weekly_sharing_v1(pg_temp.req(503),%L,pg_temp.actor(37),false)',id)),
 $$select pg_temp.call(37,'select public.list_shared_weekly_progress_v1()')$$) r where ids.name='friend7';
select is((select second_result from outcomes where name='share_revoke_read'),'[]','sharing revocation linearizes before waiting recipient refresh');
select ok(blocked,name||' demonstrated actual independent-session blocking') from outcomes order by name;
-- Scoped test-only cleanup; immutable production paths remain unchanged.
select extensions.dblink_exec('weekly_setup',$cleanup$
 set session_replication_role=replica;
 delete from app.weekly_sharing where owner_id::text like 'ed000000-%' or friend_id::text like 'ed000000-%';
 delete from app.weekly_pilot_events where actor_id::text like 'ed000000-%';
 delete from app.weekly_pilot_consents where actor_id::text like 'ed000000-%';
 delete from app.weekly_requests where actor_id::text like 'ed000000-%';
 delete from app.weekly_pauses where actor_id::text like 'ed000000-%';
 delete from app.weekly_allocations where challenge_id in(select id from app.weekly_agreements where creator_id::text like 'ed000000-%' or id::text like 'ee000000-%');
 delete from app.weekly_results where challenge_id in(select id from app.weekly_agreements where creator_id::text like 'ed000000-%' or id::text like 'ee000000-%');
 delete from app.weekly_resolutions where case_id in(select id from app.weekly_cases where actor_id::text like 'ed000000-%');
 delete from app.weekly_cases where actor_id::text like 'ed000000-%';
 delete from app.weekly_notices where challenge_id in(select id from app.weekly_agreements where creator_id::text like 'ed000000-%' or id::text like 'ee000000-%');
 delete from app.weekly_support where actor_id::text like 'ed000000-%';
 delete from app.weekly_progress where actor_id::text like 'ed000000-%';
 delete from app.weekly_revisions where actor_id::text like 'ed000000-%';
 delete from app.weekly_exits where actor_id::text like 'ed000000-%';
 delete from app.weekly_participants where actor_id::text like 'ed000000-%';
 delete from app.weekly_agreements where creator_id::text like 'ed000000-%' or id::text like 'ee000000-%';
 update app.weekly_runtime set enabled=false,fixture_enabled=false,worker_enabled=false,actor_ids='{}';
 delete from public.blocks where blocker_id::text like 'ed000000-%';
 delete from public.friendships where user_a::text like 'ed000000-%' or user_b::text like 'ed000000-%';
 delete from app.profile_handle_claims where actor_id::text like 'ed000000-%';
 delete from app.active_profile_auth_bindings where actor_id::text like 'ed000000-%';
 delete from public.profiles where id::text like 'ed000000-%';
 delete from auth.sessions where user_id::text like 'ed000000-%';
 delete from auth.users where id::text like 'ed000000-%';
 set session_replication_role=origin;
$cleanup$);
select extensions.dblink_disconnect('weekly_setup');
select extensions.dblink_disconnect('weekly_one');
select extensions.dblink_disconnect('weekly_two');
select * from finish();
rollback;
