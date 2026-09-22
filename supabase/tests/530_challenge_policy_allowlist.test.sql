-- D142 per-policy allowlist and account mode. Fictional rollback-only actors.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- Actor 41 never confirms 21+.
insert into auth.users(id) values (pg_temp.ba(41));
insert into public.profiles(id, handle, display_name, timezone) values (pg_temp.ba(41), 'allowtest41', 'Fictional Allow', 'UTC');
insert into auth.sessions(id, user_id) values (pg_temp.br(41), pg_temp.ba(41));

create function pg_temp.call(n integer, q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;
create function pg_temp.lobby(p_policy text, p_source text, p_status text default 'lobby_open')
returns void language plpgsql as $$
begin
  perform set_config('app.challenge_write_v1', 'on', true);
  insert into app.challenge_lobbies_v1(id, creator_id, policy, config, starts_at, ends_at, status, created_at,
    minimum, capacity, real_source_policy_version)
  values (extensions.gen_random_uuid(), pg_temp.ba(1), p_policy, '{}', clock_timestamp() + interval '2 days',
    clock_timestamp() + interval '3 days', p_status, clock_timestamp(),
    case when p_policy like 'personal%' then 1 else 2 end, case when p_policy like 'personal%' then 1 else 6 end, p_source);
end $$;
create function pg_temp.readiness(n integer, p_source text, p_request integer) returns jsonb language sql as $$
  select public.challenge_real_health_readiness_v1(
    ('d5300000-0000-4000-8000-' || lpad(p_request::text, 12, '0'))::uuid, pg_temp.ba(n), p_source,
    clock_timestamp() - interval '1 minute', pg_temp.br(n), clock_timestamp() + interval '1 hour', null, null,
    extensions.digest('allowlist fictional body ' || p_request, 'sha256'), false, null)
$$;

select public.challenge_real_health_runtime_v1(true, true, false);

-- Defaults leave a project unchanged
select is((select row(allowlist_enforced, links_enabled, account_mode)::text from app.challenge_policy_runtime_v1),
  '(f,f,f)', 'nothing is enforced by default');
select is((select array_agg(policy || '/' || source_policy_version order by policy) from app.challenge_policy_allowlist_v1),
  array['personal_distance_goal_v1/apple_workout_outdoor_distance_v1', 'personal_steps_goal_v1/apple_watch_steps_v1'],
  'the allowlist is seeded with the private trial''s two pairs');
select ok(not has_table_privilege('authenticated', 'app.challenge_policy_allowlist_v1', 'select')
  and not has_table_privilege('service_role', 'app.challenge_policy_runtime_v1', 'update')
  and not has_function_privilege('authenticated', 'app.challenge_policy_pair_allowed_v1(text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.challenge_availability_v1()', 'execute')
  and not has_function_privilege('anon', 'public.challenge_availability_v1()', 'execute'),
  'the allowlist is private; only the status projection is callable');
create temp table open_status as select pg_temp.call(1, 'select public.challenge_availability_v1()') v;
select is((select v->>'restricted' from open_status), 'false', 'an unrestricted project says so');
select is((select jsonb_array_length(v->'policies') from open_status), 13,
  'an unrestricted project lists every goal and leaderboard pair');
select ok((select v->'links' = 'null'::jsonb and v->'community' = 'null'::jsonb from open_status),
  'links and community are not governed here when unrestricted');
select is((select v->>'verification_mode' from open_status), 'app_attest', 'device verification is the default mode');
select lives_ok($$select pg_temp.lobby('friend_steps_goal_v1', 'apple_watch_steps_v1')$$,
  'an unrestricted project still creates real friend lobbies');
select lives_ok($$select pg_temp.lobby('community_steps_goal_v1', null, 'published_open')$$,
  'and fixture community lobbies');
create temp table old_community as select id from app.challenge_lobbies_v1
  where policy = 'community_steps_goal_v1' and creator_id = pg_temp.ba(1) order by created_at desc limit 1;

-- The list accepts only real, matching pairs
select throws_ok($$insert into app.challenge_policy_allowlist_v1 values ('friend_steps_goal_v1', 'apple_workout_outdoor_distance_v1')$$,
  '23514', null, 'a policy cannot be paired with another metric''s source');
select throws_ok($$insert into app.challenge_policy_allowlist_v1 values ('friend_exercise_goal_v1', 'apple_watch_exercise_v1')$$,
  '23514', null, 'strict Exercise v1 is not an available source');
select throws_ok($$insert into app.challenge_policy_allowlist_v1 values ('friend_steps_race_v1', 'apple_watch_steps_v1')$$,
  '22023', 'challenge_invalid_policy', 'unknown policies are refused');

-- Account mode is independent of trial enrollment
select throws_ok($$select pg_temp.readiness(1, 'apple_watch_steps_v1', 1)$$,
  '42501', 'challenge_private_account_health_disabled', 'without account mode, device proof is still required');
update app.challenge_policy_runtime_v1 set account_mode = true;
select is(pg_temp.readiness(1, 'apple_watch_steps_v1', 2)->>'version', 'challenge_real_health_readiness_receipt_v1',
  'with account mode, an age-confirmed account saves readiness without device proof');
select is((select verification_mode from app.challenge_real_health_readiness_requests_v1
  where request_id = 'd5300000-0000-4000-8000-000000000002'), 'private_account',
  'the request records its verification mode');
select is((select count(*) from app.challenge_private_device_accounts_v1), 0::bigint, 'no enrollment was needed');
select throws_ok($$select pg_temp.readiness(41, 'apple_watch_steps_v1', 3)$$,
  '42501', 'challenge_private_account_health_disabled', 'an account without 21+ confirmation still needs device proof');
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_suspensions_v1 values (pg_temp.ba(2), true, pg_temp.ba(1), 'username', clock_timestamp());
select throws_ok($$select pg_temp.readiness(2, 'apple_watch_steps_v1', 4)$$,
  '42501', 'challenge_private_account_health_disabled', 'a suspended account still needs device proof');
select is(pg_temp.call(1, 'select public.challenge_availability_v1()')->>'verification_mode', 'private_account',
  'the status projection reports account mode for the caller');

-- Enforced allowlist
update app.challenge_policy_runtime_v1 set allowlist_enforced = true;
create temp table closed_status as select pg_temp.call(1, 'select public.challenge_availability_v1()') v;
select is((select v->>'restricted' from closed_status), 'true', 'the enforced project says it is restricted');
select is((select v->'policies' from closed_status), '[
  {"policy":"personal_distance_goal_v1","source_policy_version":"apple_workout_outdoor_distance_v1"},
  {"policy":"personal_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"}]'::jsonb,
  'it lists exactly the allowed pairs');
select is((select jsonb_build_array(v->'links', v->'community') from closed_status), '[false, false]'::jsonb,
  'links and community are reported closed');
select set_config('app.challenge_real_health_command_v1', 'off', true);
select throws_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  '42501', 'challenge_policy_unavailable', 'the fictional fixture path is closed');
select set_config('app.challenge_real_health_command_v1', 'on', true);
select lives_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$, 'real admission still admits the account');
select throws_ok($$select pg_temp.lobby('friend_steps_goal_v1', 'apple_watch_steps_v1')$$,
  '42501', 'challenge_policy_unavailable', 'a friend goal is refused until it is allowed');
select set_config('app.challenge_real_health_command_v1', 'off', true);
select throws_ok($$select pg_temp.lobby('personal_steps_goal_v1', null, 'scheduled')$$,
  '42501', 'challenge_policy_unavailable', 'a lobby without a real source is refused');
select set_config('app.challenge_real_health_command_v1', 'on', true);
select throws_ok($$select pg_temp.readiness(1, 'apple_watch_exercise_credit_v2', 5)$$,
  '42501', 'challenge_policy_unavailable', 'readiness for a source no allowed policy uses is refused');

-- Build 1: the four friend goals
insert into app.challenge_policy_allowlist_v1 values
  ('friend_steps_goal_v1', 'apple_watch_steps_v1'),
  ('friend_exercise_goal_v1', 'apple_watch_exercise_credit_v2'),
  ('friend_distance_goal_v1', 'apple_workout_outdoor_distance_v1'),
  ('friend_timed_goal_v1', 'apple_workout_outdoor_timed_v1');
select is(jsonb_array_length(pg_temp.call(1, 'select public.challenge_availability_v1()')->'policies'), 6,
  'the status projection lists the six build-1 pairs');
select lives_ok($$select pg_temp.lobby('friend_steps_goal_v1', 'apple_watch_steps_v1')$$, 'friend steps goal allowed');
select lives_ok($$select pg_temp.lobby('friend_exercise_goal_v1', 'apple_watch_exercise_credit_v2')$$, 'friend Activity minutes goal allowed');
select lives_ok($$select pg_temp.lobby('friend_distance_goal_v1', 'apple_workout_outdoor_distance_v1')$$, 'friend distance goal allowed');
select lives_ok($$select pg_temp.lobby('friend_timed_goal_v1', 'apple_workout_outdoor_timed_v1')$$, 'friend timed goal allowed');
select is(pg_temp.readiness(1, 'apple_watch_exercise_credit_v2', 6)->>'version', 'challenge_real_health_readiness_receipt_v1',
  'readiness opens with its policy');
select throws_ok($$select pg_temp.lobby('friend_steps_leaderboard_v2', 'apple_watch_steps_v1')$$,
  '42501', 'challenge_policy_unavailable', 'the D141 leaderboards stay off');
select throws_ok($$select pg_temp.lobby('personal_timed_goal_v1', 'apple_workout_outdoor_timed_v1', 'scheduled')$$,
  '42501', 'challenge_policy_unavailable', 'Personal timed runs stay off');
select throws_ok($$select pg_temp.lobby('community_steps_goal_v1', 'apple_watch_steps_v1', 'published_open')$$,
  '42501', 'challenge_policy_unavailable', 'community publication is closed');
select set_config('app.challenge_write_v1', 'on', true);
select throws_ok(format($$insert into app.challenge_consents_v1(challenge_id, version, actor_id, digest, recorded_at)
  values (%L, 1, %L, 'fictional', clock_timestamp())$$, (select id from old_community), pg_temp.ba(3)),
  '42501', 'challenge_policy_unavailable', 'joining an existing community lobby is closed');

-- The public command path
select set_config('test.allow.start', to_char((clock_timestamp() at time zone 'UTC')::date + 5, 'YYYY-MM-DD'), true);
select is(pg_temp.call(1, format($$select public.challenge_mutate_v1(extensions.gen_random_uuid(), %L::jsonb)$$,
  jsonb_build_object('op', 'create', 'policy', 'friend_steps_goal_v1', 'source_policy_version', 'apple_watch_steps_v1',
    'config', jsonb_build_object('start_date', current_setting('test.allow.start'), 'days', 1, 'timezone', 'UTC', 'amount_cents', 100))))->>'status',
  'lobby_open', 'a signed-in account creates an allowed friend goal through the public command');
select throws_ok(format($$select pg_temp.call(1, %L)$$, format($$select public.challenge_mutate_v1(extensions.gen_random_uuid(), %L::jsonb)$$,
  jsonb_build_object('op', 'create', 'policy', 'friend_steps_leaderboard_v2', 'source_policy_version', 'apple_watch_steps_v1',
    'config', jsonb_build_object('start_date', current_setting('test.allow.start'), 'days', 1, 'timezone', 'UTC', 'amount_cents', 100)))),
  '42501', 'challenge_policy_unavailable', 'and cannot create a leaderboard the list leaves out');

-- Invitation links
create temp table link_lobby as select id from app.challenge_lobbies_v1
  where policy = 'friend_steps_goal_v1' and status = 'lobby_open' order by created_at desc limit 1;
select set_config('app.challenge_write_v1', 'on', true);
select throws_ok(format($$insert into app.challenge_links_v1 values (extensions.gen_random_uuid(), %L, %L,
  'fictional-hash-1', clock_timestamp(), clock_timestamp() + interval '30 days', null)$$,
  (select id from link_lobby), pg_temp.ba(1)),
  '42501', 'challenge_link_unavailable', 'link issue is closed, even for a privileged writer');
update app.challenge_policy_runtime_v1 set links_enabled = true;
select lives_ok(format($$insert into app.challenge_links_v1 values ('d5300000-0000-4000-8000-00000000aaaa', %L, %L,
  'fictional-hash-2', clock_timestamp(), clock_timestamp() + interval '30 days', null)$$,
  (select id from link_lobby), pg_temp.ba(1)), 'an operator can turn links back on');
update app.challenge_policy_runtime_v1 set links_enabled = false;
select throws_ok(format($$insert into app.challenge_redemptions_v1 values ('d5300000-0000-4000-8000-00000000aaaa', %L, clock_timestamp())$$,
  pg_temp.ba(3)), '42501', 'challenge_link_unavailable', 'redeeming an existing link is closed');

-- An agreement already made keeps saving activity after its pair is removed
select set_config('app.challenge_write_v1', 'on', true);
create temp table inflight as select 'd5300000-0000-4000-8000-000000000100'::uuid id,
  clock_timestamp() - interval '1 hour' starts_at, clock_timestamp() + interval '1 day' ends_at;
insert into app.challenge_lobbies_v1(id, creator_id, policy, config, starts_at, ends_at, status, created_at,
  minimum, capacity, agreement_version, real_source_policy_version)
select id, pg_temp.ba(1), 'personal_steps_goal_v1', jsonb_build_object('starts_at', starts_at, 'ends_at', ends_at),
  starts_at, ends_at, 'active', clock_timestamp(), 1, 1, 1, 'apple_watch_steps_v1' from inflight;
insert into app.challenge_agreements_v1(challenge_id, version, terms, created_at)
select id, 1, jsonb_build_object('source_policy_version', 'apple_watch_steps_v1',
  'config', jsonb_build_object('starts_at', starts_at, 'ends_at', ends_at)), clock_timestamp() from inflight;
insert into app.challenge_members_v1(challenge_id, actor_id, selected, target) select id, pg_temp.ba(1), true, 100 from inflight;
insert into app.challenge_slots_v1(challenge_id, actor_id, mode, metric, starts_at, ends_at)
select id, pg_temp.ba(1), 'personal', 'steps', starts_at, ends_at from inflight;
insert into app.challenge_consents_v1(challenge_id, version, actor_id, digest, recorded_at)
select a.challenge_id, 1, pg_temp.ba(1), a.digest, clock_timestamp()
from app.challenge_agreements_v1 a where a.challenge_id = (select id from inflight);
create function pg_temp.progress(p_revision integer, p_value integer) returns jsonb language plpgsql as $$
declare body jsonb; req uuid := ('d5300000-0000-4000-8000-' || lpad((200 + p_revision)::text, 12, '0'))::uuid;
begin
  select jsonb_build_object('contract_version', 1, 'actor_id', pg_temp.ba(1), 'challenge_id', c.id, 'agreement_version', 1,
    'terms_digest', a.digest, 'source_policy_version', 'apple_watch_steps_v1', 'metric', 'steps',
    'window_starts_at', c.starts_at, 'window_ends_at', c.ends_at, 'request_id', req,
    'revision', p_revision, 'previous_revision', case when p_revision = 1 then null else p_revision - 1 end,
    'state', 'value', 'value', p_value, 'observed_at', clock_timestamp(), 'queried_through_at', clock_timestamp())
  into body from inflight c join app.challenge_agreements_v1 a on a.challenge_id = c.id and a.version = 1;
  return public.challenge_real_health_ingest_v1(req, body, pg_temp.br(1), clock_timestamp() + interval '1 hour',
    null, null, extensions.digest(body::text, 'sha256'), false);
end $$;
select lives_ok($$select pg_temp.progress(1, 100)$$, 'account-mode progress saves for the in-flight goal');
delete from app.challenge_policy_allowlist_v1 where policy = 'personal_steps_goal_v1';
select lives_ok($$select pg_temp.progress(2, 250)$$, 'it keeps saving after its pair leaves the list');
select is((select array_agg(verification_mode order by recorded_at) from app.challenge_real_health_requests_v1
  where actor_id = pg_temp.ba(1)), array['private_account', 'private_account'],
  'both saved requests keep their verification mode');
select throws_ok($$select pg_temp.lobby('personal_steps_goal_v1', 'apple_watch_steps_v1', 'scheduled')$$,
  '42501', 'challenge_policy_unavailable', 'but new goals of that kind are refused');

-- The trial still answers with its own error name when both apply
update app.challenge_private_device_trial_v1 set enabled = true;
insert into app.challenge_private_device_accounts_v1(actor_id) values (pg_temp.ba(1));
select throws_ok($$select pg_temp.lobby('friend_steps_leaderboard_v2', 'apple_watch_steps_v1')$$,
  '42501', 'challenge_private_trial_personal_steps_only', 'existing clients keep the trial''s error mapping');

select * from finish();
rollback;
