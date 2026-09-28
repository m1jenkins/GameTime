-- Friends plan Phase 5: dormant legacy social grants are closed, while the
-- build 1 friend commands, build 1 challenges and retained Personal paths
-- keep working. Fictional rollback-only actors; no hosted identity.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- Actors 41 and 42 are outside the fixture's all-friends roster.
insert into auth.users(id) select pg_temp.ba(n) from generate_series(41, 42) n;
insert into public.profiles(id, handle, display_name, timezone)
  select pg_temp.ba(n), 'granttest' || n, 'Fictional Grant ' || n, 'UTC' from generate_series(41, 42) n;
insert into auth.sessions(id, user_id) select pg_temp.br(n), pg_temp.ba(n) from generate_series(41, 42) n;
do $$ declare i integer; begin
  for i in 41..42 loop
    perform pg_temp.login_beta(i);
    perform public.challenge_confirm_age_v1(pg_temp.br(10000 + i), true);
  end loop;
  perform set_config('role', 'none', true);
end $$;

create function pg_temp.call(n integer, q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;
-- Run one statement as actor n and return the SQLSTATE it raised, or 'ok'.
create function pg_temp.refused(n integer, q text) returns text language plpgsql as $$
begin
  perform pg_temp.login_beta(n);
  execute q;
  perform set_config('role', 'none', true);
  return 'ok';
exception when others then
  perform set_config('role', 'none', true);
  return sqlstate;
end $$;
create function pg_temp.rid(n integer) returns uuid language sql as $$
  select ('d5350000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;
create function pg_temp.cmd(fn text, req integer, subject integer) returns text language sql as $$
  select format('select public.%s(%L::uuid, %L::uuid)', fn, pg_temp.rid(req), pg_temp.ba(subject))
$$;

-- ---------------------------------------------------------------------------
-- The revocations took effect
-- ---------------------------------------------------------------------------
select is((select count(*) from pg_proc p, aclexplode(p.proacl) a
  where p.oid in ('public.find_profile_by_handle(text)'::regprocedure,
                  'public.join_group_by_code(text)'::regprocedure,
                  'public.rotate_group_join_code(uuid)'::regprocedure)
    and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole)), 0::bigint,
  'no client role or PUBLIC can execute the legacy lookup or group-code functions');
select ok((select bool_and(p.proacl is not null) from pg_proc p
  where p.oid in ('public.find_profile_by_handle(text)'::regprocedure,
                  'public.join_group_by_code(text)'::regprocedure,
                  'public.rotate_group_join_code(uuid)'::regprocedure)),
  'their ACLs are explicit, so no default PUBLIC execute comes back');
select is((select count(*) from pg_class c, aclexplode(c.relacl) a
  where c.oid in ('public.friendships'::regclass, 'public.blocks'::regclass,
                  'public.groups'::regclass, 'public.group_members'::regclass)
    and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole)), 0::bigint,
  'no client role holds any table privilege on friendships, blocks, groups or group_members');
select is((select count(*) from pg_attribute t, aclexplode(t.attacl) a
  where t.attrelid in ('public.friendships'::regclass, 'public.blocks'::regclass,
                       'public.groups'::regclass, 'public.group_members'::regclass)
    and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole)), 0::bigint,
  'and no column privilege either, including the old groups.name update');
select ok((select relrowsecurity from pg_class where oid = 'public.friendships'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.blocks'::regclass)
  and (select count(*) from pg_policies where schemaname = 'public'
       and tablename in ('friendships', 'blocks', 'groups', 'group_members')) = 16,
  'row-level security and the 16 legacy policies stay behind the closed grants');

select is(pg_temp.refused(41, 'select * from public.find_profile_by_handle(''granttest42'')'), '42501',
  'a signed-in client cannot look up a handle without the rate limit');
select is(pg_temp.refused(41, 'select * from public.friendships'), '42501',
  'a signed-in client cannot read friendships directly');
select is(pg_temp.refused(41, format('insert into public.friendships(user_a, user_b, requested_by) values (%L, %L, %L)',
  least(pg_temp.ba(41), pg_temp.ba(42)), greatest(pg_temp.ba(41), pg_temp.ba(42)), pg_temp.ba(41))), '42501',
  'or send a request by inserting a row');
select is(pg_temp.refused(1, format('delete from public.friendships where user_a = %L', pg_temp.ba(1))), '42501',
  'or remove a friend by deleting a row');
select is(pg_temp.refused(41, 'select * from public.blocks'), '42501',
  'a signed-in client cannot read blocks directly');
select is(pg_temp.refused(41, format('insert into public.blocks(blocker_id, blocked_id) values (%L, %L)',
  pg_temp.ba(41), pg_temp.ba(42))), '42501', 'or write a block row');
select is(pg_temp.refused(41, 'select * from public.groups'), '42501', 'groups are closed to clients');
select is(pg_temp.refused(41, 'select * from public.group_members'), '42501', 'and so is group membership');
select is(pg_temp.refused(41, 'select public.join_group_by_code(''ABCDEFGH'')'), '42501',
  'joining a group by code is closed');
select is(pg_temp.refused(41, format('select public.rotate_group_join_code(%L)', extensions.gen_random_uuid())), '42501',
  'rotating a group code is closed');
select is(pg_temp.refused(41, 'select * from public.list_my_friendship_cards()'), 'ok',
  'the read-only legacy friendship cards stay callable for the loopback experiments');

-- ---------------------------------------------------------------------------
-- The build 1 friend commands still work
-- ---------------------------------------------------------------------------
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''GrantTest42'')')->>'relation', 'none',
  'friend_lookup_v1 still finds an account by exact username');
select is(pg_temp.call(41, pg_temp.cmd('friend_request_v1', 1, 42)), '{"state":"outgoing"}'::jsonb,
  'friend_request_v1 still sends a request');
select is(pg_temp.call(42, 'select public.friend_list_v1()')->'incoming'->0->>'username', 'granttest41',
  'friend_list_v1 still shows it to the recipient');
select is(pg_temp.call(42, pg_temp.cmd('friend_accept_v1', 2, 41)), '{"state":"friends"}'::jsonb,
  'friend_accept_v1 still accepts');
select ok(app.is_friend(pg_temp.ba(41), pg_temp.ba(42)), 'and the friendship row exists');
select is((select count(*) from pg_temp.call(41, 'select to_jsonb(array(select c from public.list_my_friendship_cards() c))') j,
  jsonb_array_elements(j) e where e->>'other_user_id' = pg_temp.ba(42)::text), 1::bigint,
  'the legacy cards reader sees the friendship the command made');
select is(pg_temp.call(41, pg_temp.cmd('friend_remove_v1', 3, 42)), '{"state":"none"}'::jsonb,
  'friend_remove_v1 still removes');
select is(pg_temp.call(41, pg_temp.cmd('friend_request_v1', 4, 42)), '{"state":"outgoing"}'::jsonb,
  'a new request can follow');
select is(pg_temp.call(41, pg_temp.cmd('friend_cancel_v1', 5, 42)), '{"state":"none"}'::jsonb,
  'friend_cancel_v1 still cancels');
select is(pg_temp.call(42, pg_temp.cmd('friend_request_v1', 6, 41)), '{"state":"outgoing"}'::jsonb,
  'the other person can ask too');
select is(pg_temp.call(41, pg_temp.cmd('friend_decline_v1', 7, 42)), '{"state":"none"}'::jsonb,
  'friend_decline_v1 still declines');
select is(pg_temp.call(42, pg_temp.cmd('friend_block_v1', 8, 41)), '{"state":"blocked"}'::jsonb,
  'friend_block_v1 still blocks');
select ok(app.is_blocked_either_way(pg_temp.ba(41), pg_temp.ba(42)), 'and the block row exists');
select is(pg_temp.call(42, pg_temp.cmd('friend_unblock_v1', 9, 41)), '{"state":"none"}'::jsonb,
  'friend_unblock_v1 still unblocks');
select lives_ok(format($$select pg_temp.call(41, %L)$$,
  format('select public.friend_report_v1(%L::uuid, %L::uuid, ''username'')', pg_temp.rid(10), pg_temp.ba(42))),
  'friend_report_v1 still records a report');

-- The same holds with commands_only on, the hosted build 1 setting.
update app.friend_runtime_v1 set commands_only = true;
select is(pg_temp.call(41, pg_temp.cmd('friend_request_v1', 11, 42)), '{"state":"outgoing"}'::jsonb,
  'with commands_only on, requests still work');
select is(pg_temp.call(42, pg_temp.cmd('friend_accept_v1', 12, 41)), '{"state":"friends"}'::jsonb,
  'and so does accepting');

-- ---------------------------------------------------------------------------
-- The build 1 challenge paths still work
-- ---------------------------------------------------------------------------
insert into beta_ids values ('group', pg_temp.beta_group(1, 3));
select is(pg_temp.call(1, format('select public.challenge_detail_v1(%L)', (select id from beta_ids where name = 'group')))->>'id',
  (select id from beta_ids where name = 'group')::text,
  'a friends challenge is still created, invited by username, frozen and agreed');
select is((select count(*) from app.challenge_members_v1 where challenge_id = (select id from beta_ids where name = 'group')),
  3::bigint, 'all three invited friends are members');
select ok(jsonb_array_length(pg_temp.call(2, 'select public.challenge_list_v1()')) >= 1,
  'an invited friend still lists the challenge');
select is(pg_temp.call(2, 'select public.friend_list_v1()')->'friends' @> jsonb_build_array(jsonb_build_object('username', 'betafixture0001')),
  true, 'friend_list_v1 still reads the fixture friendships');
select lives_ok(format($$select pg_temp.call(3, %L)$$,
  format('select public.challenge_block_v1(%L, %L)', pg_temp.rid(20), pg_temp.ba(2))),
  'the challenge block still writes its block through the definer path');
select ok(app.is_blocked_either_way(pg_temp.ba(2), pg_temp.ba(3)), 'and the block row exists');
select lives_ok(format($$select pg_temp.call(5, %L)$$,
  format($$select public.challenge_personal_preview_v1('personal_steps_goal_v1', %L::jsonb, 50000, 'apple_watch_steps_v1')$$,
  jsonb_build_object('start_date', '2026-10-03', 'days', 7, 'timezone', 'America/Chicago', 'amount_cents', 100))),
  'a personal goal preview still works');

-- ---------------------------------------------------------------------------
-- Retained Personal paths still work
-- ---------------------------------------------------------------------------
select ok(has_table_privilege('authenticated', 'public.profiles', 'select')
  and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'handle', 'insert'),
  'Personal profile setup keeps its direct profile grants');
select is(pg_temp.call(6, format('select to_jsonb(array(select handle::text from public.profiles where id = %L))', pg_temp.ba(6))),
  '["betafixture0006"]'::jsonb, 'a signed-in person still reads their own profile');
select is(pg_temp.call(6, format('with u as (update public.profiles set display_name = ''Fictional Renamed'' where id = %L returning 1) select to_jsonb(count(*)) from u', pg_temp.ba(6))),
  '1'::jsonb, 'and can still rename themselves');
create temp table personal as
  select pg_temp.call(7, format('select to_jsonb(public.create_personal_challenge_v2(%L, ''daily'', 10000, 1000, ''UTC''))', pg_temp.rid(30)))
    #>> '{}' as id;
grant all on personal to authenticated;
select isnt((select id from personal), null, 'Personal creation still works');
select ok(pg_temp.call(7, 'select to_jsonb(array(select c from public.list_my_accountability_challenges_v2() c))')::text
  like '%' || (select id from personal) || '%', 'and the Personal list still shows it');
select lives_ok(format($$select pg_temp.call(7, %L)$$,
  format('select to_jsonb(public.cancel_personal_challenge_v1(%L, %L))', (select id from personal), pg_temp.rid(31))),
  'and Personal cancellation still works');

select * from finish();
rollback;
