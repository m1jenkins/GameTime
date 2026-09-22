-- Hosted-order upgrade rehearsal, part 2 of 2. Run after part 1 and
-- `supabase migration up --include-all`. Rolls back, so it can be re-run.
begin;
select no_plan();

create function pg_temp.call(q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"b7000000-0000-4000-8000-000000000701","session_id":"b7100000-0000-4000-8000-000000000701"}', true);
  perform set_config('role', 'authenticated', true);
  execute q into r;
  perform set_config('role', 'none', true);
  return r;
end $$;
create function pg_temp.progress(p_request uuid, p_revision integer, p_value integer) returns jsonb language sql as $$
  select public.challenge_real_health_ingest_v1(p_request, body, 'b7100000-0000-4000-8000-000000000701',
    clock_timestamp() + interval '1 hour', null, null, extensions.digest(body::text, 'sha256'), false)
  from (select jsonb_build_object('contract_version', 1, 'actor_id', c.creator_id, 'challenge_id', c.id,
    'agreement_version', c.agreement_version, 'terms_digest', a.digest, 'source_policy_version', 'apple_watch_steps_v1',
    'metric', 'steps', 'window_starts_at', c.starts_at, 'window_ends_at', c.ends_at, 'request_id', p_request,
    'revision', p_revision, 'previous_revision', case when p_revision = 1 then null else p_revision - 1 end,
    'state', 'value', 'value', p_value, 'observed_at', k.now, 'queried_through_at', k.now) body
    from friends_upgrade.before b
    join app.challenge_lobbies_v1 c on c.id = b.id
    join app.challenge_agreements_v1 a on a.challenge_id = c.id and a.version = c.agreement_version
    cross join friends_upgrade.clock k) x
$$;

select is(array(select version from supabase_migrations.schema_migrations
  except select unnest(migrations) from friends_upgrade.before order by 1),
  array['20260920162025', '20260922181912', '20260922210000', '20260922210100']::text[],
  'the older leaderboard migration applied after the later ones, then the new ones');

-- The in-flight goal is untouched by the upgrade
select is((select row(c.status, c.revision)::text from app.challenge_lobbies_v1 c join friends_upgrade.before b using (id)),
  (select row(status, revision)::text from friends_upgrade.before), 'status and revision are unchanged');
select is((select a.digest from app.challenge_agreements_v1 a join friends_upgrade.before b on a.challenge_id = b.id),
  (select digest from friends_upgrade.before), 'the agreement digest is unchanged');
select is((select a.terms from app.challenge_agreements_v1 a join friends_upgrade.before b on a.challenge_id = b.id),
  (select terms from friends_upgrade.before), 'the agreement terms are unchanged');
select ok(not ((select terms from friends_upgrade.before) ? 'score_rule'), 'the Personal goal carries no leaderboard rule');
select is((select jsonb_agg(to_jsonb(f) order by f.revision) from app.challenge_real_health_facts_v1 f
  where f.challenge_id = (select id from friends_upgrade.before)), (select facts from friends_upgrade.before),
  'the saved update is unchanged');
select is(app.challenge_real_health_evaluate_v1((select id from friends_upgrade.before)),
  (select evaluation from friends_upgrade.before), 'the evaluation is the same across the upgrade');

-- It keeps saving and reaches its result
update friends_upgrade.clock set now = '2026-09-28 19:00:00+00';
select is(pg_temp.progress('b7200000-0000-4000-8000-000000000004', 2, 5200)->>'revision', '2',
  'a later update saves after the upgrade');
select is((select array_agg(verification_mode order by recorded_at) from app.challenge_real_health_requests_v1
  where actor_id = 'b7000000-0000-4000-8000-000000000701'), array['private_account', 'private_account'],
  'both saved requests record the private-account mode');
update friends_upgrade.clock set now = '2026-10-04 12:00:00+00';
select public.challenge_process_v1((select id from friends_upgrade.before));
select public.challenge_process_v1((select id from friends_upgrade.before));
select ok((select status from app.challenge_lobbies_v1 where id = (select id from friends_upgrade.before)) in ('review', 'final'),
  'the goal moves on to its result after the deadlines');
select is(app.challenge_real_health_evaluate_v1((select id from friends_upgrade.before)),
  '{"outcome": "scored", "simulation": "nonredeemable", "entry_cents": 2000, "unallocated_cents": 0,
    "participants": {"b7000000-0000-4000-8000-000000000701": {"status": "met", "returned_cents": 2000}}}'::jsonb,
  'the goal is scored as met and returns its full simulated stake');

-- The trial behaves as before; the new surfaces are present
select is(pg_temp.call('select public.challenge_availability_v1()') - 'admission' - 'account_allowed',
  '{"restricted": true, "verification_mode": "private_account", "links": false, "community": false,
    "policies": [{"policy": "personal_distance_goal_v1", "source_policy_version": "apple_workout_outdoor_distance_v1"},
                 {"policy": "personal_steps_goal_v1", "source_policy_version": "apple_watch_steps_v1"}]}'::jsonb,
  'the enrolled account sees the trial''s two pairs and account mode');
select set_config('app.challenge_write_v1', 'on', true);
select throws_ok($$insert into app.challenge_lobbies_v1(id, creator_id, policy, config, starts_at, ends_at, status,
    created_at, minimum, capacity, real_source_policy_version)
  values (extensions.gen_random_uuid(), 'b7000000-0000-4000-8000-000000000701', 'friend_steps_goal_v1', '{}',
    clock_timestamp() + interval '2 days', clock_timestamp() + interval '3 days', 'lobby_open', clock_timestamp(), 2, 6,
    'apple_watch_steps_v1')$$,
  '42501', 'challenge_private_trial_personal_steps_only', 'the trial still refuses friend challenges');
select is(pg_temp.call($q$select public.friend_lookup_v1('upgrade701')$q$)->>'relation', 'self',
  'the friend commands are installed and callable');

select * from finish();
rollback;
