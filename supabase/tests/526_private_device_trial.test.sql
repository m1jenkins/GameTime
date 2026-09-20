-- Private trial uses fictional accounts and rolls back. No hosted identity is used.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

select ok(app.challenge_private_device_allowed_v1(pg_temp.ba(1)),
  'disabled private trial preserves the existing project behavior');
select ok(not has_table_privilege('authenticated', 'app.challenge_private_device_accounts_v1', 'insert')
  and not has_table_privilege('service_role', 'app.challenge_private_device_accounts_v1', 'insert'),
  'client and service API roles cannot self-enroll accounts');

update app.challenge_private_device_trial_v1 set enabled = true where singleton;
select set_config('app.challenge_real_health_command_v1', 'on', true);
select public.challenge_real_health_runtime_v1(true, true, false);
select throws_ok(
  $$select app.challenge_admit_v1(pg_temp.ba(2))$$,
  '42501', 'challenge_private_trial_account_required',
  'an unapproved account cannot enter real challenge admission');
select throws_ok(
  $$insert into public.device_attestations(key_id,user_id,public_key,environment)
    values(extensions.digest('trial-key','sha256'),pg_temp.ba(2),decode('04','hex'),'development')$$,
  '42501', 'challenge_private_trial_account_required',
  'an unapproved account cannot register a device key');
select throws_ok(
  $$insert into app.challenge_real_health_readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)
    values(pg_temp.ba(2),'apple_watch_steps_v1',clock_timestamp(),clock_timestamp())$$,
  '42501', 'challenge_private_trial_account_required',
  'an unapproved account cannot save real readiness even through a privileged writer');
select throws_ok(
  $$insert into app.challenge_real_health_requests_v1(request_id,actor_id,payload,payload_digest,device_key_id,assertion_counter,response,recorded_at)
    values(extensions.gen_random_uuid(),pg_temp.ba(2),'{}',extensions.digest('payload','sha256'),
      extensions.digest('key','sha256'),1,'{}',clock_timestamp())$$,
  '42501', 'challenge_private_trial_account_required',
  'an unapproved account cannot save an ingest receipt');

insert into app.challenge_private_device_accounts_v1(actor_id) values(pg_temp.ba(1));
select lives_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  'the enrolled, age-confirmed account can enter real admission');
select set_config('app.challenge_real_health_command_v1','off',true);
select throws_ok(
  $$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  '42501', 'challenge_private_trial_personal_steps_only',
  'the private trial does not admit the historical fixture challenge path');
select set_config('app.challenge_real_health_command_v1','on',true);
select set_config('app.challenge_write_v1','on',true);
select throws_ok(
  $$insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,
       minimum,capacity,real_source_policy_version)
    values(extensions.gen_random_uuid(),pg_temp.ba(1),'friend_steps_goal_v1','{}',
      clock_timestamp(),clock_timestamp()+interval '1 day','lobby_open',clock_timestamp(),2,2,'apple_watch_steps_v1')$$,
  '42501', 'challenge_private_trial_personal_steps_only',
  'even an enrolled account cannot create a real friend challenge in this trial');
select lives_ok(
  $$insert into app.challenge_real_health_readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)
    values(pg_temp.ba(1),'apple_watch_steps_v1',clock_timestamp(),clock_timestamp())$$,
  'the enrolled account can save real steps readiness');
select throws_ok(
  $$insert into app.challenge_real_health_readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)
    values(pg_temp.ba(1),'apple_watch_exercise_credit_v2',clock_timestamp(),clock_timestamp())$$,
  '42501', 'challenge_private_trial_personal_steps_only',
  'the trial excludes other real source policies');
delete from app.challenge_private_device_accounts_v1 where actor_id=pg_temp.ba(1);
select throws_ok(
  $$insert into app.challenge_real_health_readiness_v1(actor_id,source_policy_version,observed_at,recorded_at)
    values(pg_temp.ba(1),'apple_watch_steps_v1',clock_timestamp(),clock_timestamp())
    on conflict(actor_id,source_policy_version,distance_mm) do update set recorded_at=excluded.recorded_at$$,
  '42501', 'challenge_private_trial_account_required',
  'removing enrollment blocks later readiness updates');

select * from finish();
rollback;
