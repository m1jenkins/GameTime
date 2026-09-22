-- D142 friend commands. Fictional rollback-only actors; no hosted identity.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- Actors 41-49 are not in the fixture's all-friends roster. 49 never
-- confirms 21+.
insert into auth.users(id) select pg_temp.ba(n) from generate_series(41, 49) n;
insert into public.profiles(id, handle, display_name, timezone)
  select pg_temp.ba(n), 'friendtest' || n, 'Fictional Friend ' || n, 'UTC' from generate_series(41, 49) n;
insert into auth.sessions(id, user_id) select pg_temp.br(n), pg_temp.ba(n) from generate_series(41, 49) n;
do $$ declare i integer; begin
  for i in 41..48 loop
    perform pg_temp.login_beta(i);
    perform public.challenge_confirm_age_v1(pg_temp.br(10000 + i), true);
  end loop;
  perform set_config('role', 'none', true);
end $$;

-- Run one statement as actor n and return its jsonb result as postgres.
create function pg_temp.call(n integer, q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;
create function pg_temp.rid(n integer) returns uuid language sql as $$
  select ('d5290000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;
create function pg_temp.cmd(actor integer, fn text, req integer, subject integer, extra text default '')
returns text language sql as $$
  select format('select public.%s(%L::uuid, %L::uuid%s)', fn, pg_temp.rid(req), pg_temp.ba(subject), extra)
$$;
create function pg_temp.state(a integer, b integer) returns text language sql as $$
  select app.friend_state_v1(pg_temp.ba(a), pg_temp.ba(b))
$$;

-- Privileges
select ok(has_function_privilege('authenticated', 'public.friend_request_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.friend_request_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.friend_request_v1(uuid,uuid)', 'execute'),
  'friend commands are callable by signed-in clients only');
select ok(not has_function_privilege('authenticated', 'app.friend_state_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.friend_save_v1(uuid,uuid,jsonb,jsonb)', 'execute'),
  'internal friend helpers are not callable by clients');
select ok(not has_table_privilege('authenticated', 'app.friend_commands_v1', 'select')
  and not has_table_privilege('service_role', 'app.friend_commands_v1', 'insert')
  and not has_table_privilege('authenticated', 'app.friend_runtime_v1', 'update'),
  'the command journal and runtime are private');
select is((select commands_only from app.friend_runtime_v1), false,
  'direct writes stay open by default so historical behavior holds');

-- Lookup
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''@FriendTest42'')')
  - 'id', jsonb_build_object('found', true, 'username', 'friendtest42',
  'display_name', 'Fictional Friend 42', 'relation', 'none'),
  'exact lookup is case-insensitive, accepts a leading @ and shows no relation yet');
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''friendtest42'')')->>'id', pg_temp.ba(42)::text,
  'lookup returns the account id for the request');
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''friendtest41'')')->>'relation', 'self',
  'looking yourself up says so');
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''friendtest4'')'), '{"found":false}'::jsonb,
  'a prefix is not a match');
select is(pg_temp.call(41, 'select public.friend_lookup_v1(''friendtest49'')'), '{"found":false}'::jsonb,
  'an account without 21+ confirmation is hidden');
select throws_ok($$select pg_temp.call(49, 'select public.friend_lookup_v1(''friendtest41'')')$$,
  '42501', 'friend_age_required', 'looking people up needs 21+ confirmation');

-- Request, retry, conflict
select is(pg_temp.call(41, pg_temp.cmd(41, 'friend_request_v1', 1, 42)), '{"state":"outgoing"}'::jsonb,
  'a request is saved as outgoing');
select is(pg_temp.state(42, 41), 'incoming', 'the other person sees it as incoming');
select is(pg_temp.call(41, pg_temp.cmd(41, 'friend_request_v1', 1, 42)), '{"state":"outgoing"}'::jsonb,
  'an exact retry returns the saved receipt');
select is((select count(*) from app.friend_commands_v1 where actor_id = pg_temp.ba(41)), 1::bigint,
  'the retry adds no second journal row');
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_request_v1', 1, 43)),
  '22023', 'friend_request_conflict', 'reusing a request id for a different subject is refused');
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_request_v1', 2, 42)),
  '23505', 'friend_request_already_sent', 'a second request to the same person is refused');
select throws_ok(format($$select pg_temp.call(42, %L)$$, pg_temp.cmd(42, 'friend_request_v1', 3, 41)),
  '23505', 'friend_incoming_request_exists', 'a crossed request points at the one already waiting');
select is(pg_temp.call(42, 'select public.friend_lookup_v1(''friendtest41'')')->>'relation', 'incoming',
  'lookup tells the recipient the request is waiting for them');
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_request_v1', 4, 41)),
  '42501', 'friend_unavailable', 'you cannot send yourself a request');
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_request_v1', 5, 49)),
  '42501', 'friend_unavailable', 'an account without 21+ confirmation cannot be asked');
select throws_ok(format($$select pg_temp.call(49, %L)$$, pg_temp.cmd(49, 'friend_request_v1', 6, 41)),
  '42501', 'friend_age_required', 'sending needs 21+ confirmation');

-- Accept, stale accept, remove
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_accept_v1', 7, 42)),
  '55000', 'friend_state_changed', 'the sender cannot accept their own request');
select is(pg_temp.call(42, pg_temp.cmd(42, 'friend_accept_v1', 8, 41)), '{"state":"friends"}'::jsonb,
  'the recipient accepts');
select ok(app.is_friend(pg_temp.ba(41), pg_temp.ba(42)), 'accepting makes them friends');
select is(pg_temp.call(42, pg_temp.cmd(42, 'friend_accept_v1', 8, 41)), '{"state":"friends"}'::jsonb,
  'a retried accept returns the same receipt');
select throws_ok(format($$select pg_temp.call(42, %L)$$, pg_temp.cmd(42, 'friend_accept_v1', 9, 41)),
  '55000', 'friend_state_changed', 'a second accept with a new id sees the state has moved on');
select throws_ok(format($$select pg_temp.call(41, %L)$$, pg_temp.cmd(41, 'friend_request_v1', 10, 42)),
  '23505', 'friend_already_friends', 'friends cannot be asked again');
select is(pg_temp.call(41, pg_temp.cmd(41, 'friend_remove_v1', 11, 42)), '{"state":"none"}'::jsonb,
  'either friend can remove the friendship');
select is(pg_temp.state(41, 42), 'none', 'removal deletes the row');
select throws_ok(format($$select pg_temp.call(42, %L)$$, pg_temp.cmd(42, 'friend_remove_v1', 12, 41)),
  '55000', 'friend_state_changed', 'a stale remove is refused');

-- Stale accept after the sender cancels
select pg_temp.call(43, pg_temp.cmd(43, 'friend_request_v1', 13, 44));
select is(pg_temp.call(43, pg_temp.cmd(43, 'friend_cancel_v1', 14, 44)), '{"state":"none"}'::jsonb,
  'the sender cancels');
select throws_ok(format($$select pg_temp.call(44, %L)$$, pg_temp.cmd(44, 'friend_accept_v1', 15, 43)),
  '55000', 'friend_state_changed', 'accepting a cancelled request is refused');
select throws_ok(format($$select pg_temp.call(44, %L)$$, pg_temp.cmd(44, 'friend_cancel_v1', 16, 43)),
  '55000', 'friend_state_changed', 'only the sender can cancel');

-- Silent decline
select pg_temp.call(43, pg_temp.cmd(43, 'friend_request_v1', 17, 45));
select is(pg_temp.call(45, pg_temp.cmd(45, 'friend_decline_v1', 18, 43)), '{"state":"none"}'::jsonb,
  'the recipient declines');
select is(pg_temp.call(43, 'select public.friend_list_v1()')->'outgoing', '[]'::jsonb,
  'the declined request no longer appears in the sender''s list');
select is((select count(*) from app.friend_commands_v1 where actor_id = pg_temp.ba(43)
  and payload->>'op' = 'decline'), 0::bigint, 'nothing is written on the sender''s side');
select throws_ok(format($$select pg_temp.call(43, %L)$$, pg_temp.cmd(43, 'friend_decline_v1', 19, 45)),
  '55000', 'friend_state_changed', 'the sender cannot decline their own request');

-- Lists
select pg_temp.call(46, pg_temp.cmd(46, 'friend_request_v1', 20, 47));
select pg_temp.call(47, pg_temp.cmd(47, 'friend_accept_v1', 21, 46));
select pg_temp.call(46, pg_temp.cmd(46, 'friend_request_v1', 22, 48));
select pg_temp.call(44, pg_temp.cmd(44, 'friend_request_v1', 23, 46));
create temp table list46 as select pg_temp.call(46, 'select public.friend_list_v1()') v;
select is((select jsonb_array_length(v->'friends') from list46), 1, 'one friend');
select is((select v->'friends'->0->>'username' from list46), 'friendtest47', 'the friend is listed by username');
select is((select (v->'friends'->0->>'you_asked')::boolean from list46), true, 'the list says who asked');
select is((select v->'incoming'->0->>'username' from list46), 'friendtest44', 'incoming request listed');
select is((select v->'outgoing'->0->>'username' from list46), 'friendtest48', 'outgoing request listed');
select is((select array_agg(k order by k) from list46, jsonb_object_keys(v->'friends'->0) k),
  array['display_name', 'id', 'since', 'username', 'you_asked'],
  'a friend entry carries identity and dates only, no challenge or activity');

-- Suspension
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_suspensions_v1 values (pg_temp.ba(48), true, pg_temp.ba(1), 'username', clock_timestamp());
select is(pg_temp.call(46, 'select public.friend_list_v1()')->'outgoing', '[]'::jsonb,
  'a suspended person drops out of the lists');
select is(pg_temp.call(46, 'select public.friend_lookup_v1(''friendtest48'')'), '{"found":false}'::jsonb,
  'a suspended person cannot be found');
select throws_ok(format($$select pg_temp.call(48, %L)$$, pg_temp.cmd(48, 'friend_request_v1', 24, 45)),
  '42501', 'friend_account_restricted', 'a suspended account cannot send requests');
select throws_ok(format($$select pg_temp.call(48, %L)$$, pg_temp.cmd(48, 'friend_accept_v1', 25, 46)),
  '42501', 'friend_account_restricted', 'a suspended account cannot accept');
select throws_ok(format($$select pg_temp.call(46, %L)$$, pg_temp.cmd(46, 'friend_request_v1', 26, 48)),
  '42501', 'friend_unavailable', 'a suspended account cannot be asked');
select is(pg_temp.state(48, 46), 'incoming', 'the earlier pending request itself is kept');
select is(pg_temp.call(48, pg_temp.cmd(48, 'friend_decline_v1', 27, 46)), '{"state":"none"}'::jsonb,
  'a suspended account can still decline');
select is(pg_temp.call(48, pg_temp.cmd(48, 'friend_block_v1', 28, 45)), '{"state":"blocked"}'::jsonb,
  'a suspended account can still block');
select set_config('app.challenge_write_v1', 'on', true);
update app.challenge_suspensions_v1 set suspended = false where actor_id = pg_temp.ba(48);

-- Block with no shared challenge, then unblock
select pg_temp.call(43, pg_temp.cmd(43, 'friend_request_v1', 29, 47));
select is(pg_temp.call(47, pg_temp.cmd(47, 'friend_block_v1', 30, 43)), '{"state":"blocked"}'::jsonb,
  'anyone can be blocked, with no shared challenge');
select is(pg_temp.state(43, 47), 'none', 'the block removes the pending request');
select is(pg_temp.call(43, 'select public.friend_lookup_v1(''friendtest47'')'), '{"found":false}'::jsonb,
  'the blocked person cannot find the blocker');
select is(pg_temp.call(47, 'select public.friend_lookup_v1(''friendtest43'')'), '{"found":false}'::jsonb,
  'the blocker cannot find the blocked person either');
select throws_ok(format($$select pg_temp.call(43, %L)$$, pg_temp.cmd(43, 'friend_request_v1', 31, 47)),
  '42501', 'friend_unavailable', 'the blocked person cannot send a request');
select throws_ok(format($$select pg_temp.call(47, %L)$$, pg_temp.cmd(47, 'friend_block_v1', 32, 43)),
  '55000', 'friend_state_changed', 'a second block is stale');
select is(pg_temp.call(47, 'select public.friend_list_v1()')->'blocked'->0->>'username', 'friendtest43',
  'blocked people are listed for the blocker');
select is(pg_temp.call(43, 'select public.friend_list_v1()')->'blocked', '[]'::jsonb,
  'the blocked person sees no trace of the block');
select throws_ok(format($$select pg_temp.call(43, %L)$$, pg_temp.cmd(43, 'friend_unblock_v1', 33, 47)),
  '55000', 'friend_state_changed', 'only the blocker can unblock');
select is(pg_temp.call(47, pg_temp.cmd(47, 'friend_unblock_v1', 34, 43)), '{"state":"none"}'::jsonb,
  'the blocker unblocks');
select ok(not app.is_blocked_either_way(pg_temp.ba(43), pg_temp.ba(47)) and pg_temp.state(43, 47) = 'none',
  'unblocking restores neither the friendship nor the request');
select is(pg_temp.call(43, 'select public.friend_lookup_v1(''friendtest47'')')->>'relation', 'none',
  'after unblocking they can find each other again');

-- Block inside a shared challenge keeps the existing consequence
select pg_temp.login_beta(1);
insert into beta_ids values ('friend_block_pair', pg_temp.beta_group(1, 2));
reset role;
select is(pg_temp.call(1, pg_temp.cmd(1, 'friend_block_v1', 35, 2)), '{"state":"blocked"}'::jsonb,
  'a co-participant can be blocked with the new command');
select is((select count(*) from app.challenge_members_v1
  where challenge_id = (select id from beta_ids where name = 'friend_block_pair') and exited_at is not null),
  2::bigint, 'both people leave the unfinished shared challenge, as before');
select ok(not app.is_friend(pg_temp.ba(1), pg_temp.ba(2)), 'the block severs the friendship');

-- Report any account
select is(pg_temp.call(45, pg_temp.cmd(45, 'friend_report_v1', 36, 46, ', ''unwanted_contact''')),
  '{"saved":true}'::jsonb, 'anyone can be reported, with no shared challenge');
select ok(exists (select 1 from app.challenge_reports_v1 r
  where r.reporter = pg_temp.ba(45) and r.subject = pg_temp.ba(46) and r.reason = 'unwanted_contact'
    and not exists (select 1 from app.challenge_report_scopes_v1 s where s.report_id = r.id)),
  'the report joins the support queue as an account report');
select is(pg_temp.call(45, pg_temp.cmd(45, 'friend_report_v1', 36, 46, ', ''unwanted_contact''')),
  '{"saved":true}'::jsonb, 'a retried report returns the same receipt');
select is((select count(*) from app.challenge_reports_v1 where reporter = pg_temp.ba(45)), 1::bigint,
  'the retry files no second report');
select throws_ok(format($$select pg_temp.call(45, %L)$$, pg_temp.cmd(45, 'friend_report_v1', 37, 46, ', ''spite''')),
  '22023', 'friend_invalid_request', 'only the three report reasons are accepted');
do $$ declare i integer; begin
  for i in 38..46 loop
    perform pg_temp.call(45, pg_temp.cmd(45, 'friend_report_v1', i, 47, ', ''username'''));
  end loop;
end $$;
select throws_ok(format($$select pg_temp.call(45, %L)$$, pg_temp.cmd(45, 'friend_report_v1', 47, 44, ', ''username''')),
  'P0001', 'friend_rate_limited', 'the shared report budget holds at ten an hour');

-- Daily request cap
update app.friend_runtime_v1 set daily_request_limit = 2;
select pg_temp.call(44, pg_temp.cmd(44, 'friend_request_v1', 48, 41));
select throws_ok(format($$select pg_temp.call(44, %L)$$, pg_temp.cmd(44, 'friend_request_v1', 49, 42)),
  'P0001', 'friend_request_limit', 'the daily request cap counts sent requests');
select is(pg_temp.state(44, 42), 'none', 'the refused request left nothing behind');
update app.friend_runtime_v1 set daily_request_limit = 20;

-- Lookup rate limit, shared with the invite command
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_quotas_v1 values (pg_temp.ba(42), 'lookup', clock_timestamp(), 30)
  on conflict (actor_id, bucket) do update set window_at = excluded.window_at, used = 30;
select is(pg_temp.call(42, 'select public.friend_lookup_v1(''friendtest41'')'),
  '{"message":"friend_lookup_rate_limited"}'::jsonb,
  'the 31st lookup in a minute returns an error body instead of raising');
select is(current_setting('response.status', true), '429', 'and it answers with status 429');

-- commands_only closes direct writes and keeps every command path
update app.friend_runtime_v1 set commands_only = true;
select throws_ok($$select pg_temp.call(41, 'insert into public.friendships(user_a,user_b,requested_by)
  select least(''' || pg_temp.ba(41) || '''::uuid,''' || pg_temp.ba(45) || '''::uuid),
         greatest(''' || pg_temp.ba(41) || '''::uuid,''' || pg_temp.ba(45) || '''::uuid),
         ''' || pg_temp.ba(41) || '''::uuid returning null::jsonb')$$,
  '42501', 'friend_command_required', 'a signed-in client can no longer insert a friendship row');
select throws_ok(format($$select pg_temp.call(47, %L)$$,
  format('insert into public.blocks(blocker_id,blocked_id) values(%L,%L) returning null::jsonb', pg_temp.ba(47), pg_temp.ba(41))),
  '42501', 'friend_command_required', 'a signed-in client can no longer insert a block row');
select set_config('app.friend_write_v1', '', true);
select set_config('app.challenge_write_v1', '', true);
select throws_ok(format($$delete from public.friendships where user_a = %L$$, least(pg_temp.ba(46), pg_temp.ba(47))),
  '42501', 'friend_command_required', 'even the owner needs a command marker');
select is(pg_temp.call(41, pg_temp.cmd(41, 'friend_request_v1', 50, 45)), '{"state":"outgoing"}'::jsonb,
  'the request command still works');
select is(pg_temp.call(45, pg_temp.cmd(45, 'friend_accept_v1', 51, 41)), '{"state":"friends"}'::jsonb,
  'the accept command still works');
select pg_temp.login_beta(3);
insert into beta_ids values ('legacy_block_pair', pg_temp.beta_group(3, 2));
reset role;
select lives_ok(format($$select pg_temp.call(3, %L)$$,
  format('select public.challenge_block_v1(%L, %L)', pg_temp.rid(52), pg_temp.ba(4))),
  'the legacy challenge block still writes its block');

-- Account deletion removes friendships, blocks and the actor's own journal,
-- with commands_only still on.
select pg_temp.call(41, pg_temp.cmd(41, 'friend_block_v1', 53, 46));
select lives_ok($$select public.challenge_begin_account_deletion_v1(
  'bf000000-0000-0000-0000-000000000041', 'd5290000-0000-4000-8000-000000009941',
  'local_friend_deletion_receipt_01234567890123456789012345678', 'fictional-apple-friend-41')$$,
  'account deletion runs with direct writes closed');
select ok(not exists (select 1 from public.friendships where pg_temp.ba(41) in (user_a, user_b))
  and not exists (select 1 from public.blocks where pg_temp.ba(41) in (blocker_id, blocked_id)),
  'deletion removes the friendships and blocks');
select is((select count(*) from app.friend_commands_v1 where actor_id = pg_temp.ba(41)), 0::bigint,
  'deletion removes the deleted account''s own journal');
select is(pg_temp.call(45, 'select public.friend_lookup_v1(''friendtest41'')'), '{"found":false}'::jsonb,
  'a deleted account cannot be found');
select is(pg_temp.call(45, 'select public.friend_list_v1()')->'friends', '[]'::jsonb,
  'a deleted account leaves the former friend''s list');
select throws_ok($$select pg_temp.call(41, 'select public.friend_list_v1()')$$,
  '42501', 'challenge_session_required', 'the deleted account can no longer use friend commands');

select * from finish();
rollback;
