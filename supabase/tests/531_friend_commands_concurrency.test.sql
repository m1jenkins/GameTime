-- Friend commands in real, separate transactions. The first command stays
-- uncommitted while the second is observed waiting on a lock, then the first
-- commits. Fictional committed rows are removed at the end.
begin;
select no_plan();

create function pg_temp.actor(n integer) returns uuid language sql immutable as $$
  select ('d5310000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
select extensions.dblink_connect('friend_setup', 'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres');
select extensions.dblink_connect('friend_one', 'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=friend_race_one');
select extensions.dblink_connect('friend_two', 'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres application_name=friend_race_two');

select extensions.dblink_exec('friend_setup', $setup$
  insert into auth.users(id) select ('d5310000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid from generate_series(1, 12) n;
  insert into public.profiles(id, handle, display_name, timezone)
    select id, 'friendrace' || right(id::text, 2), 'Fictional Race Friend', 'UTC' from auth.users where id::text like 'd5310000-%';
  insert into auth.sessions(id, user_id)
    select ('d5320000-0000-0000-0000-' || right(id::text, 12))::uuid, id from auth.users where id::text like 'd5310000-%';
  set app.challenge_write_v1 = 'on';
  insert into app.challenge_age_v1 select id, 'age_21_v1', clock_timestamp() from auth.users where id::text like 'd5310000-%';
  reset app.challenge_write_v1;
$setup$);

do $$
declare conn text;
begin
  foreach conn in array array['friend_one', 'friend_two'] loop
    perform extensions.dblink_exec(conn, $install$
      create function pg_temp.action(p jsonb) returns text language plpgsql as $fn$
      declare s uuid := ('d5310000-0000-0000-0000-' || lpad(p->>'subject', 12, '0'))::uuid;
        r uuid := ('d5330000-0000-0000-0000-' || lpad(p->>'request', 12, '0'))::uuid;
      begin
        return case p->>'op'
          when 'request' then public.friend_request_v1(r, s)::text
          when 'accept' then public.friend_accept_v1(r, s)::text
          when 'cancel' then public.friend_cancel_v1(r, s)::text
          when 'block' then public.friend_block_v1(r, s)::text end;
      exception when others then return sqlstate || ':' || sqlerrm;
      end;
      $fn$;
    $install$);
  end loop;
end;
$$;

create function pg_temp.start_session(conn text, n integer) returns void language plpgsql as $$
begin
  perform extensions.dblink_exec(conn, format('begin; set local statement_timeout=''8s''; set local role authenticated;
    set local request.jwt.claims=%L',
    jsonb_build_object('sub', pg_temp.actor(n), 'session_id', ('d5320000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid)::text));
end;
$$;
create function pg_temp.query(p jsonb) returns text language sql as $$
  select format('select pg_temp.action(%L::jsonb)', p::text)
$$;
create function pg_temp.once(n integer, p jsonb) returns text language plpgsql as $$
declare r text;
begin
  perform pg_temp.start_session('friend_one', n);
  select x.result into r from extensions.dblink('friend_one', pg_temp.query(p)) x(result text);
  perform extensions.dblink_exec('friend_one', 'commit');
  return r;
end;
$$;
create function pg_temp.race(a integer, b integer, first_action jsonb, second_action jsonb)
returns table(first_result text, second_result text, blocked boolean) language plpgsql as $$
declare deadline timestamptz := clock_timestamp() + interval '4 seconds';
begin
  perform pg_temp.start_session('friend_one', a);
  perform pg_temp.start_session('friend_two', b);
  select x.result into first_result from extensions.dblink('friend_one', pg_temp.query(first_action)) x(result text);
  perform extensions.dblink_send_query('friend_two', pg_temp.query(second_action));
  blocked := false;
  loop
    perform pg_stat_clear_snapshot();
    select exists(select 1 from pg_stat_activity where application_name = 'friend_race_two'
      and cardinality(pg_blocking_pids(pid)) > 0) into blocked;
    exit when blocked or clock_timestamp() >= deadline;
    perform pg_sleep(0.01);
  end loop;
  perform extensions.dblink_exec('friend_one', 'commit');
  select x.result into second_result from extensions.dblink_get_result('friend_two') x(result text);
  perform * from extensions.dblink_get_result('friend_two') x(result text);
  perform extensions.dblink_exec('friend_two', 'commit');
  return next;
end;
$$;
create temp table outcomes(name text, first_result text, second_result text, blocked boolean);

insert into outcomes select 'crossed requests', * from pg_temp.race(1, 2,
  '{"op":"request","subject":2,"request":1}', '{"op":"request","subject":1,"request":2}');
select ok((select blocked from outcomes where name = 'crossed requests'), 'the crossed request waits on the pair lock');
select is((select first_result from outcomes where name = 'crossed requests'), '{"state": "outgoing"}',
  'the first request is saved');
select is((select second_result from outcomes where name = 'crossed requests'), '23505:friend_incoming_request_exists',
  'the crossed request finds the first one waiting');

insert into outcomes select 'exact retry', * from pg_temp.race(3, 3,
  '{"op":"request","subject":4,"request":3}', '{"op":"request","subject":4,"request":3}');
select is((select second_result from outcomes where name = 'exact retry'),
  (select first_result from outcomes where name = 'exact retry'),
  'a concurrent exact retry returns the committed receipt');

select pg_temp.once(5, '{"op":"request","subject":6,"request":4}');
insert into outcomes select 'accept then cancel', * from pg_temp.race(6, 5,
  '{"op":"accept","subject":5,"request":5}', '{"op":"cancel","subject":6,"request":6}');
select is((select first_result from outcomes where name = 'accept then cancel'), '{"state": "friends"}',
  'the accept wins');
select is((select second_result from outcomes where name = 'accept then cancel'), '55000:friend_state_changed',
  'the cancel sees the pair has moved on');

select pg_temp.once(7, '{"op":"request","subject":8,"request":7}');
insert into outcomes select 'cancel then accept', * from pg_temp.race(7, 8,
  '{"op":"cancel","subject":8,"request":8}', '{"op":"accept","subject":7,"request":9}');
select is((select first_result from outcomes where name = 'cancel then accept'), '{"state": "none"}',
  'the cancel wins');
select is((select second_result from outcomes where name = 'cancel then accept'), '55000:friend_state_changed',
  'a stale accept cannot create a friendship');

insert into outcomes select 'block then request', * from pg_temp.race(9, 10,
  '{"op":"block","subject":10,"request":10}', '{"op":"request","subject":9,"request":11}');
select is((select first_result from outcomes where name = 'block then request'), '{"state": "blocked"}',
  'the block is saved');
select is((select second_result from outcomes where name = 'block then request'), '42501:friend_unavailable',
  'the request waiting behind it is refused');

select ok((select bool_and(blocked) from outcomes where name <> 'crossed requests'),
  'every race waited on a lock rather than interleaving');

select extensions.dblink_exec('friend_setup', $cleanup$
  set session_replication_role = replica;
  delete from app.friend_commands_v1 where actor_id::text like 'd5310000-%';
  delete from app.challenge_quotas_v1 where actor_id::text like 'd5310000-%';
  delete from public.friendships where user_a::text like 'd5310000-%' or user_b::text like 'd5310000-%';
  delete from public.blocks where blocker_id::text like 'd5310000-%' or blocked_id::text like 'd5310000-%';
  delete from app.challenge_age_v1 where actor_id::text like 'd5310000-%';
  delete from auth.sessions where user_id::text like 'd5310000-%';
  delete from app.profile_handle_claims where actor_id::text like 'd5310000-%';
  delete from app.active_profile_auth_bindings where actor_id::text like 'd5310000-%';
  delete from public.profiles where id::text like 'd5310000-%';
  delete from auth.users where id::text like 'd5310000-%';
  set session_replication_role = origin;
$cleanup$);
select is((select count(*) from auth.users where id::text like 'd5310000-%'), 0::bigint,
  'the committed fictional rows are gone');
select extensions.dblink_disconnect('friend_one');
select extensions.dblink_disconnect('friend_two');
select extensions.dblink_disconnect('friend_setup');
select * from finish();
rollback;
