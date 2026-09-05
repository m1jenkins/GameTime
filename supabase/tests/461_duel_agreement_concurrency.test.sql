-- Real, separate PostgreSQL transactions. First request remains uncommitted
-- while the second is observed waiting on a database lock (not a sleep-based
-- guess). Both commit orders are covered where the lifecycle differs.
begin;
select no_plan();

create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d3000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.req(n integer) returns uuid language sql immutable as $$
  select ('d4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
$$;
select extensions.dblink_connect('duel_setup','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('duel_one','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=duel_race_one');
select extensions.dblink_connect('duel_two','host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=duel_race_two');

select extensions.dblink_exec('duel_setup',$setup$
  insert into auth.users(id)
    select ('d3000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,60) n;
  insert into public.profiles(id,handle,display_name,timezone)
    select id,'duelrace'||right(id::text,4),'Fictional Race Runner','UTC'
    from auth.users where id::text like 'd3000000-%';
  insert into public.friendships(user_a,user_b,requested_by,status)
    select a.id,b.id,a.id,'accepted' from public.profiles a cross join public.profiles b
    where a.id::text like 'd3000000-%' and b.id::text like 'd3000000-%' and a.id<b.id;
  do $do$ begin
  perform public.set_duel_admission_v1(true,array(select id from public.profiles where id::text like 'd3000000-%'));
  perform public.curate_duel_fixture_event_v1('d4000000-0000-0000-0000-000000001000',
    clock_timestamp()+interval '2 days',clock_timestamp()+interval '2 days 2 hours','America/Chicago');
  end; $do$;
$setup$);

-- Test-only helpers live in each worker's temporary schema and disappear on
-- disconnect. They catch SQLSTATE without aborting the enclosing transaction.
-- Production actor calls still run with the authenticated role and JWT actor;
-- only the private expiry/clock seam and service delete need definer authority.
do $$
declare conn text;
begin
  foreach conn in array array['duel_one','duel_two'] loop
    perform extensions.dblink_exec(conn,$install$
      create function pg_temp.action(p jsonb) returns text
      language plpgsql security definer set search_path='' as $fn$
      declare a uuid := ('d3000000-0000-0000-0000-'||lpad((p->>'other'),12,'0'))::uuid;
        r uuid := ('d4000000-0000-0000-0000-'||lpad((p->>'request'),12,'0'))::uuid;
        c uuid := (p->>'challenge')::uuid;
        e uuid := coalesce((p->>'event')::uuid,'d4000000-0000-0000-0000-000000001000'::uuid);
        t timestamptz := (p->>'at')::timestamptz; v_digest text;
      begin
        if p->>'op'='create' then
          if t is null then return public.create_duel_v1(r,a,e,'duel-fixture-5k-v1',true)::text; end if;
          return app.create_duel_at_v1(r,a,e,'duel-fixture-5k-v1',true,t)::text;
        elsif p->>'op'='accept' then
          select terms_digest into v_digest from public.duel_challenges where id=c;
          if t is null then return public.accept_duel_v1(r,c,'duel-fixture-5k-v1',v_digest)::text; end if;
          return app.respond_duel_at_v1('accept_duel_v1',r,c,'duel-fixture-5k-v1',v_digest,t)::text;
        elsif p->>'op'='cancel' then return public.cancel_duel_v1(r,c)::text;
        elsif p->>'op'='decline' then return public.decline_duel_v1(r,c)::text;
        elsif p->>'op'='expire' then return app.expire_duel_invitation_at_v1(c,t)::text;
        elsif p->>'op'='delete' then perform public.delete_account(a); return 'deleted';
        elsif p->>'op'='gate_off' then perform public.set_duel_admission_v1(false,'{}'); return 'off';
        elsif p->>'op'='lock' then perform 1 from public.profiles where id=a for update; return 'locked';
        end if;
        raise exception 'unknown test operation';
      exception when others then return sqlstate;
      end;
      $fn$;
    $install$);
  end loop;
end;
$$;

create function pg_temp.query(p jsonb) returns text language sql as $$
  select format('select pg_temp.action(%L::jsonb)',p::text);
$$;
create function pg_temp.start_session(conn text,actor integer,service boolean default false)
returns void language plpgsql as $$
begin
  perform extensions.dblink_exec(conn,format('begin; set local statement_timeout=''8s'';
    set local role %I; set local request.jwt.claim.sub=%L',
    case when service then 'service_role' else 'authenticated' end,pg_temp.actor(actor)::text));
end;
$$;
create function pg_temp.make(actor integer,friend integer,request integer) returns uuid language plpgsql as $$
declare r text;
begin
  perform pg_temp.start_session('duel_one',actor);
  select x.result into r from extensions.dblink('duel_one',pg_temp.query(jsonb_build_object('op','create','other',friend,'request',request))) x(result text);
  perform extensions.dblink_exec('duel_one','commit');
  return r::uuid;
end;
$$;
create function pg_temp.race(a integer,b integer,first_action jsonb,second_action jsonb,
  first_service boolean default false,second_service boolean default false,wait_until timestamptz default null)
returns table(first_result text,second_result text,blocked boolean)
language plpgsql as $$
declare deadline timestamptz := clock_timestamp()+interval '4 seconds';
begin
  perform pg_temp.start_session('duel_one',a,first_service);
  perform pg_temp.start_session('duel_two',b,second_service);
  select x.result into first_result from extensions.dblink('duel_one',pg_temp.query(first_action)) x(result text);
  perform extensions.dblink_send_query('duel_two',pg_temp.query(second_action));
  blocked := false;
  loop
    perform pg_stat_clear_snapshot();
    select exists(select 1 from pg_stat_activity where application_name='duel_race_two'
      and cardinality(pg_blocking_pids(pid))>0) into blocked;
    exit when blocked or clock_timestamp()>=deadline;
    perform pg_sleep(0.01);
  end loop;
  if wait_until is not null then
    while clock_timestamp() < wait_until loop perform pg_sleep(0.01); end loop;
  end if;
  perform extensions.dblink_exec('duel_one','commit');
  select x.result into second_result from extensions.dblink_get_result('duel_two') x(result text);
  perform * from extensions.dblink_get_result('duel_two') x(result text);
  perform extensions.dblink_exec('duel_two','commit');
  return next;
end;
$$;
create temp table outcomes(name text,first_result text,second_result text,blocked boolean);
create temp table ids(name text primary key,id uuid);
create function pg_temp.id(n text) returns uuid language sql as $$select id from ids where name=n$$;

insert into outcomes select 'distinct create',* from pg_temp.race(1,1,
  '{"op":"create","other":2,"request":1}','{"op":"create","other":3,"request":2}');
insert into outcomes select 'exact create',* from pg_temp.race(4,4,
  '{"op":"create","other":5,"request":3}','{"op":"create","other":5,"request":3}');
insert into outcomes select 'changed payload',* from pg_temp.race(6,6,
  '{"op":"create","other":7,"request":4}','{"op":"create","other":8,"request":4}');
insert into outcomes select 'opposing create',* from pg_temp.race(9,10,
  '{"op":"create","other":10,"request":5}','{"op":"create","other":9,"request":6}');
select is((select second_result from outcomes where name='distinct create'),'23505','competing distinct creation loses actor slot');
select is((select first_result=second_result from outcomes where name='exact create'),true,'concurrent exact retry returns same committed agreement');
select is((select second_result from outcomes where name='changed payload'),'22023','concurrent changed payload refuses reused request');
select ok((select first_result::uuid<>second_result::uuid from outcomes where name='opposing create'),'opposing creates serialize stable pair order without deadlock');

insert into ids values('accept_cancel',pg_temp.make(11,12,10));
insert into outcomes select 'accept then cancel',* from pg_temp.race(12,11,
  jsonb_build_object('op','accept','challenge',pg_temp.id('accept_cancel'),'request',11),
  jsonb_build_object('op','cancel','challenge',pg_temp.id('accept_cancel'),'request',12));
insert into ids values('cancel_accept',pg_temp.make(13,14,13));
insert into outcomes select 'cancel then accept',* from pg_temp.race(13,14,
  jsonb_build_object('op','cancel','challenge',pg_temp.id('cancel_accept'),'request',14),
  jsonb_build_object('op','accept','challenge',pg_temp.id('cancel_accept'),'request',15));
select is((select status from public.duel_challenges where id=pg_temp.id('accept_cancel')),'cancelled','cancel after accepted commit closes scheduled agreement');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.id('accept_cancel') and accepted_at is not null),2::bigint,'accept-winning order retains both consents');
select is((select second_result from outcomes where name='cancel then accept'),'55000','cancel-winning order refuses acceptance');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.id('cancel_accept') and accepted_at is not null),1::bigint,'cancel-winning order never records second consent');

insert into ids values('accept_expire',pg_temp.make(15,16,16));
insert into outcomes select 'accept then expire',r.* from public.duel_challenges c cross join lateral pg_temp.race(16,15,
  jsonb_build_object('op','accept','challenge',c.id,'request',17,'at',c.accept_by-interval '1 microsecond'),
  jsonb_build_object('op','expire','challenge',c.id,'at',c.accept_by),false,true) r where c.id=pg_temp.id('accept_expire');
insert into ids values('expire_accept',pg_temp.make(17,18,18));
insert into outcomes select 'expire then accept',r.* from public.duel_challenges c cross join lateral pg_temp.race(17,18,
  jsonb_build_object('op','expire','challenge',c.id,'at',c.accept_by),
  jsonb_build_object('op','accept','challenge',c.id,'request',19,'at',c.accept_by-interval '1 microsecond'),true,false) r where c.id=pg_temp.id('expire_accept');
select is((select second_result from outcomes where name='accept then expire'),'false','expiry cannot close accepted agreement');
select is((select status from public.duel_challenges where id=pg_temp.id('accept_expire')),'scheduled','accept-before-cutoff commit wins expiry race');
select is((select second_result from outcomes where name='expire then accept'),'55000','expiry-winning order refuses acceptance');
select is((select status from public.duel_challenges where id=pg_temp.id('expire_accept')),'expired','expiry-winning order remains durable');

insert into ids values('accept_delete',pg_temp.make(19,20,20));
insert into outcomes select 'accept then delete',* from pg_temp.race(20,19,
  jsonb_build_object('op','accept','challenge',pg_temp.id('accept_delete'),'request',21),
  '{"op":"delete","other":19}',false,true);
insert into ids values('delete_accept',pg_temp.make(21,22,22));
insert into outcomes select 'delete then accept',* from pg_temp.race(22,22,
  '{"op":"delete","other":22}',
  jsonb_build_object('op','accept','challenge',pg_temp.id('delete_accept'),'request',23),true,false);
select is((select second_result from outcomes where name='accept then delete'),'deleted','deletion waits for acceptance and succeeds');
select is((select status from public.duel_challenges where id=pg_temp.id('accept_delete')),'cancelled','deletion closes accepted pair');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.id('accept_delete') and accepted_at is not null),2::bigint,'deletion preserves committed second consent');
select is((select second_result from outcomes where name='delete then accept'),'42501','deleted stale actor cannot consent after waiting');
select is((select status from public.duel_challenges where id=pg_temp.id('delete_accept')),'cancelled','deletion-winning invitation is cancelled');

insert into ids values('slot_a',pg_temp.make(23,25,24)),('slot_b',pg_temp.make(24,25,25));
insert into outcomes select 'two acceptances',* from pg_temp.race(25,25,
  jsonb_build_object('op','accept','challenge',pg_temp.id('slot_a'),'request',26),
  jsonb_build_object('op','accept','challenge',pg_temp.id('slot_b'),'request',27));
select is((select second_result from outcomes where name='two acceptances'),'23505','two incoming accepts cannot reserve two slots');
select is((select count(*) from app.duel_enrollments where actor_id=pg_temp.actor(25) and released_at is null),1::bigint,'unique enrollment survives concurrent acceptance');

insert into outcomes select 'create then delete',* from pg_temp.race(26,27,
  '{"op":"create","other":27,"request":28}','{"op":"delete","other":27}',false,true);
insert into outcomes select 'delete then create',* from pg_temp.race(29,28,
  '{"op":"delete","other":29}','{"op":"create","other":29,"request":29}',true,false);
select is((select c.status from public.duel_challenges c join outcomes o on c.id::text=o.first_result where o.name='create then delete'),
  'cancelled','invitee deletion after create closes invitation');
select is((select second_result from outcomes where name='delete then create'),'42501','creation after invitee deletion denied');

insert into ids values('decline_accept',pg_temp.make(30,31,30));
insert into outcomes select 'decline then accept',* from pg_temp.race(31,31,
  jsonb_build_object('op','decline','challenge',pg_temp.id('decline_accept'),'request',31),
  jsonb_build_object('op','accept','challenge',pg_temp.id('decline_accept'),'request',32));
select is((select second_result from outcomes where name='decline then accept'),'55000','decline prevents later acceptance');

-- Public acceptance must sample wall clock after acquiring the blocked pair.
select extensions.dblink_exec('duel_setup',$setup$
  do $do$ begin
  perform public.curate_duel_fixture_event_v1('d4000000-0000-0000-0000-000000001001',
    clock_timestamp()+interval '1 hour 2 seconds',clock_timestamp()+interval '2 hours','UTC');
  end; $do$;
$setup$);
select pg_temp.start_session('duel_one',32);
insert into ids select 'wait_cutoff',result::uuid from extensions.dblink('duel_one',pg_temp.query(
  '{"op":"create","other":33,"request":33,"event":"d4000000-0000-0000-0000-000000001001"}')) x(result text);
select extensions.dblink_exec('duel_one','commit');
insert into outcomes select 'wait past cutoff',r.* from public.duel_challenges c cross join lateral pg_temp.race(32,33,
  '{"op":"lock","other":32}',jsonb_build_object('op','accept','challenge',c.id,'request',34),
  true,false,c.accept_by+interval '10 milliseconds') r where c.id=pg_temp.id('wait_cutoff');
select is((select second_result from outcomes where name='wait past cutoff'),'55000','waiting past cutoff rejects despite earlier transaction start');
select is((select count(*) from public.duel_participants where challenge_id=pg_temp.id('wait_cutoff') and accepted_at is not null),1::bigint,'no late consent after lock wait');

insert into ids values('gate',pg_temp.make(34,35,35));
insert into outcomes select 'gate then accept',* from pg_temp.race(34,35,
  '{"op":"gate_off"}',jsonb_build_object('op','accept','challenge',pg_temp.id('gate'),'request',36),true,false);
select is((select second_result from outcomes where name='gate then accept'),'42501','gate-off commit blocks waiting acceptance');

select ok(blocked,name||': second session actually waited on a database lock') from outcomes order by name;
select ok(first_result !~ '^[0-9A-Z]{5}$',name||': first operation succeeded') from outcomes order by name;
select is((select count(*) from (select actor_id from app.duel_enrollments where released_at is null group by actor_id having count(*)>1) x),
  0::bigint,'no actor has more than one unsettled duel after all races');
select is((select count(*) from public.duel_challenges c where c.creator_id::text like 'd3000000-%' and c.closed_at is not null
  and exists(select 1 from app.duel_enrollments e where e.challenge_id=c.id and released_at is null)),0::bigint,'every closed race released all slots');

-- Only disposable fictional test rows are removed. Replica mode is the same
-- superuser-only cleanup convention used by the existing concurrency suite.
select extensions.dblink_exec('duel_setup',$cleanup$
  set session_replication_role=replica;
  delete from app.duel_requests where actor_id::text like 'd3000000-%';
  delete from app.duel_enrollments where actor_id::text like 'd3000000-%';
  delete from public.duel_participants where actor_id::text like 'd3000000-%';
  delete from public.duel_challenges where creator_id::text like 'd3000000-%';
  delete from public.duel_event_fixtures where id::text like 'd4000000-%';
  delete from app.duel_beta_allowlist where actor_id::text like 'd3000000-%';
  update app.duel_runtime set admission_enabled=false;
  delete from public.friendships where user_a::text like 'd3000000-%' or user_b::text like 'd3000000-%';
  delete from app.profile_handle_claims where actor_id::text like 'd3000000-%';
  delete from app.active_profile_auth_bindings where actor_id::text like 'd3000000-%';
  delete from public.profiles where id::text like 'd3000000-%';
  delete from auth.users where id::text like 'd3000000-%';
  set session_replication_role=origin;
$cleanup$);
select extensions.dblink_disconnect('duel_one');
select extensions.dblink_disconnect('duel_two');
select extensions.dblink_disconnect('duel_setup');
select * from finish();
rollback;
