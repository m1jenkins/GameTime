-- Real transactions; each competing operation must visibly wait on a lock.
begin;
select no_plan();
select extensions.dblink_connect('pc_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('pc_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pc_race_one');
select extensions.dblink_connect('pc_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=pc_race_two');
select extensions.dblink_exec('pc_setup',$setup$begin;
insert into auth.users(id) select ('ed100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,8) n;
insert into public.profiles(id,handle,display_name,timezone)
 select id,'pcrace'||right(id::text,2),'Fictional Runner','UTC' from auth.users where id::text like 'ed100000-%';
insert into auth.sessions(id,user_id)
 select replace(id::text,'ed100000','ed200000')::uuid,id from auth.users where id::text like 'ed100000-%';
do $x$ begin perform public.set_performance_commitment_admission_v1(true,array(select id from public.profiles where id::text like 'ed100000-%')); end $x$;
commit;$setup$);
create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
 select ('ed100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
 select ('ed200000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table params as select clock_timestamp()+interval '1 day' s,clock_timestamp()+interval '61 days' d;
create temp table saved(name text primary key,id uuid);
create function pg_temp.id(n text) returns uuid language sql as $$select id from saved where name=n$$;
select extensions.dblink_exec('pc_one',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('ed100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('ed100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('ed200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
select extensions.dblink_exec('pc_two',$install$create function pg_temp.action(n integer,q text) returns text language plpgsql as $fn$
declare r text;
begin
 perform set_config('request.jwt.claim.sub',('ed100000-0000-0000-0000-'||lpad(n::text,12,'0')),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',('ed100000-0000-0000-0000-'||lpad(n::text,12,'0')),
 'session_id',('ed200000-0000-0000-0000-'||lpad(n::text,12,'0')),'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 begin execute q into r; exception when others then r:=SQLSTATE; end;
 perform set_config('role','none',true);
 return r;
end; $fn$;$install$);
create function pg_temp.race(first_sql text,second_sql text,hold_seconds double precision default 0)
returns table(first_result text,second_result text,blocked boolean) language plpgsql as $$
declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';
begin
 perform extensions.dblink_exec('pc_one','begin; set local statement_timeout=''8s''');
 perform extensions.dblink_exec('pc_two','begin; set local statement_timeout=''8s''');
 select x.r into first_result from extensions.dblink('pc_one',first_sql) x(r text);
 perform extensions.dblink_send_query('pc_two',second_sql);
 loop
  perform pg_stat_clear_snapshot();
  select exists(select 1 from pg_stat_activity where application_name='pc_race_two'
    and cardinality(pg_blocking_pids(pid))>0) into blocked;
  exit when blocked or clock_timestamp()>=deadline;
  perform pg_sleep(0.01);
 end loop;
 perform pg_sleep(hold_seconds);
 perform extensions.dblink_exec('pc_one','commit');
 select x.r into second_result from extensions.dblink_get_result('pc_two') x(r text);
 perform * from extensions.dblink_get_result('pc_two') x(r text);
 perform extensions.dblink_exec('pc_two','commit');
 return next;
end; $$;

create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
create function pg_temp.query(n integer,q text) returns text language sql as $$select format('select pg_temp.action(%s,%L)',n,q)$$;
create function pg_temp.make(a integer,q integer,p_start timestamptz default null) returns text language plpgsql as $$
declare start_time timestamptz; end_time timestamptz; digest text;
begin
 select coalesce(p_start,p.s),case when p_start is null then p.d else p_start+interval '60 days' end into start_time,end_time from params p;
 digest:=encode(extensions.digest(app.performance_commitment_terms_v1(pg_temp.actor(a),1500,start_time,end_time,'UTC','performance-commitment-fixture-5k-v1')::text,'sha256'),'hex');
 return pg_temp.query(a,format('select public.create_performance_commitment_v1(%L,1500,%L,%L,%L,%L,%L,true)',
   pg_temp.req(q),start_time,end_time,'UTC','performance-commitment-fixture-5k-v1',digest));
end; $$;
insert into outcomes select 'two creates',* from pg_temp.race(pg_temp.make(1,101),pg_temp.make(1,102));
select is((select second_result from outcomes where name='two creates'),'23505','one concurrent reservation per owner');
insert into saved select 'first',first_result::uuid from outcomes where name='two creates';
insert into outcomes select 'exact create retry',* from pg_temp.race(pg_temp.make(2,201),pg_temp.make(2,201));
select is(first_result,second_result,'concurrent exact retries recover one agreement') from outcomes where name='exact create retry';
insert into outcomes select 'create then delete',* from pg_temp.race(pg_temp.make(3,301),format('select public.delete_account(%L)::text',pg_temp.actor(3)));
insert into outcomes select 'delete then create',* from pg_temp.race(format('select public.delete_account(%L)::text',pg_temp.actor(4)),pg_temp.make(4,401));
select is((select second_result from outcomes where name='delete then create'),'42501','waiting create observes deletion');
select is((select x.reason from extensions.dblink('pc_setup',format('select close_reason from app.performance_commitment_agreements where actor_id=%L',pg_temp.actor(3))) x(reason text)),
 'account_deleted','waiting deletion closes newly committed agreement');
insert into outcomes select 'cancel then create',* from pg_temp.race(
 pg_temp.query(1,format('select public.close_performance_commitment_v1(%L,%L,%L)',pg_temp.req(103),pg_temp.id('first'),'cancel')),pg_temp.make(1,104));
select ok((select second_result ~ '^[0-9a-f-]{36}$' from outcomes where name='cancel then create'),'waiting replacement observes released slot');
insert into saved select 'replacement',second_result::uuid from outcomes where name='cancel then create';
insert into outcomes select 'two closes',* from pg_temp.race(
 pg_temp.query(1,format('select public.close_performance_commitment_v1(%L,%L,%L)',pg_temp.req(105),pg_temp.id('replacement'),'cancel')),
 pg_temp.query(1,format('select public.close_performance_commitment_v1(%L,%L,%L)',pg_temp.req(106),pg_temp.id('replacement'),'injury')));
select is((select second_result from outcomes where name='two closes'),'55000','one terminal close only');
insert into outcomes select 'gate closes then create',* from pg_temp.race(
 'select public.set_performance_commitment_admission_v1(false,''{}'')::text',pg_temp.make(5,501));
select is((select second_result from outcomes where name='gate closes then create'),'42501','waiting create observes gate-off');
select x.r from extensions.dblink('pc_setup','select public.set_performance_commitment_admission_v1(true,array(select id from public.profiles where id::text like ''ed100000-%'' and deleted_at is null))::text') x(r text);
insert into outcomes select 'revoke session then create',* from pg_temp.race(
 format('with removed as (delete from auth.sessions where user_id=%L returning id) select count(*)::text from removed',pg_temp.actor(6)),pg_temp.make(6,601));
select is((select second_result from outcomes where name='revoke session then create'),'42501','waiting create observes revoked session');
insert into outcomes select 'wait crosses start',* from pg_temp.race(
 format('select id::text from public.profiles where id=%L for update',pg_temp.actor(7)),pg_temp.make(7,701,clock_timestamp()+interval '0.5 seconds'),0.8);
select is((select second_result from outcomes where name='wait crosses start'),'22023','wall clock sampled after blocking locks');
select extensions.dblink_exec('pc_setup','update auth.sessions set not_after=clock_timestamp()+interval ''0.5 seconds'' where user_id=''ed100000-0000-0000-0000-000000000008''');
insert into outcomes select 'wait crosses session expiry',* from pg_temp.race(
 'select singleton::text from app.performance_commitment_runtime for update',pg_temp.make(8,801),0.8);
select is((select second_result from outcomes where name='wait crosses session expiry'),'42501','session expiry rechecked after runtime lock');
select ok(blocked,name||': observed lock wait') from outcomes order by name;
select is((select x.n from extensions.dblink('pc_setup','select count(*) from app.performance_commitment_enrollments where actor_id::text like ''ed100000-%'' and released_at is null') x(n bigint)),1::bigint,'only actor two remains open');
select is((select x.n from extensions.dblink('pc_setup','select count(*) from app.performance_commitment_requests where actor_id=''ed100000-0000-0000-0000-000000000002''') x(n bigint)),1::bigint,'exact retry created one request');
-- Test-only superuser cleanup is confined to this fictional namespace.
select extensions.dblink_exec('pc_setup',$cleanup$
 begin;
 set local session_replication_role=replica;
 delete from app.performance_commitment_requests where actor_id::text like 'ed100000-%';
 delete from app.performance_commitment_enrollments where actor_id::text like 'ed100000-%';
 delete from app.performance_commitment_consents where actor_id::text like 'ed100000-%';
 delete from app.performance_commitment_agreements where actor_id::text like 'ed100000-%';
 delete from app.performance_commitment_beta_allowlist where actor_id::text like 'ed100000-%';
 update app.performance_commitment_runtime set admission_enabled=false;
 delete from app.profile_handle_claims where actor_id::text like 'ed100000-%';
 delete from app.active_profile_auth_bindings where actor_id::text like 'ed100000-%';
 delete from public.profiles where id::text like 'ed100000-%';
 delete from auth.sessions where user_id::text like 'ed100000-%';
 delete from auth.users where id::text like 'ed100000-%';
 commit;
$cleanup$);
select extensions.dblink_disconnect('pc_one');
select extensions.dblink_disconnect('pc_two');
select extensions.dblink_disconnect('pc_setup');
select * from finish();
rollback;
