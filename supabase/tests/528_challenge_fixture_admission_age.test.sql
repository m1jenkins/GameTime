-- Fixture admission requires 21+ confirmation (20260922181912). Fictional
-- rollback-only actors; no hosted identity is used.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- The shared fixture confirms 21+ for actors 1 through 40. Actors 41 and 44
-- join the fixture roster without confirming; outside(42) and outside(43) are
-- not on the roster, and only outside(42) has Beta access.
create function pg_temp.outside(n integer) returns uuid language sql as $$select ('be000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.outside_session(n integer) returns uuid language sql as $$select ('bd000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.login_outside(n integer) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.outside(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.outside(n),'session_id',pg_temp.outside_session(n))::text,true);
 perform set_config('role','authenticated',true);
end $$;
insert into auth.users(id) values(pg_temp.ba(41)),(pg_temp.ba(44)),(pg_temp.outside(42)),(pg_temp.outside(43));
insert into public.profiles(id,handle,display_name,timezone) values
 (pg_temp.ba(41),'betafixture0041','Fictional Beta','America/Chicago'),
 (pg_temp.ba(44),'betafixture0044','Fictional Beta','America/Chicago'),
 (pg_temp.outside(42),'outsidefixture42','Fictional access','America/Chicago'),
 (pg_temp.outside(43),'outsidefixture43','Fictional outsider','America/Chicago');
insert into auth.sessions(id,user_id) values
 (pg_temp.br(41),pg_temp.ba(41)),(pg_temp.br(44),pg_temp.ba(44)),
 (pg_temp.outside_session(42),pg_temp.outside(42)),(pg_temp.outside_session(43),pg_temp.outside(43));
select pg_temp.clock_beta('2026-10-01T12:00Z');
select public.challenge_readiness_fixture_v1(pg_temp.ba(n)) from unnest(array[41,44]) n;
select set_config('app.challenge_write_v1','on',true);
insert into app.challenge_access_v1(actor_id,granted_at) values(pg_temp.outside(42),'2026-10-01T12:00Z');
select set_config('app.challenge_write_v1','off',true);

-- Fixture branch: roster and Beta access both require an age record.
select lives_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  'an age-confirmed fixture roster actor is still admitted');
select throws_ok($$select app.challenge_admit_v1(pg_temp.ba(41))$$,
  '42501','challenge_age_required',
  'a fixture roster actor without 21+ confirmation is refused');
select throws_ok($$select app.challenge_admit_v1(pg_temp.outside(42))$$,
  '42501','challenge_age_required',
  'a fixture actor with Beta access but without 21+ confirmation is refused');
select pg_temp.login_beta(41);
select throws_ok($$select pg_temp.beta_create()$$,
  '42501','challenge_age_required',
  'creating a challenge through the public command is refused without 21+ confirmation');
reset role;

-- The paused check still runs first, with its original code.
select throws_ok($$select app.challenge_admit_v1(pg_temp.outside(43))$$,
  '42501','challenge_admission_paused',
  'an actor outside the roster without Beta access is still paused');
select public.challenge_grant_support_v1(pg_temp.ba(40),'2026-10-05T12:00Z');
select pg_temp.login_beta(40);
select public.challenge_support_suspend_v1(pg_temp.br(52801),pg_temp.ba(44),'unsafe_behavior');
reset role;
select throws_ok($$select app.challenge_admit_v1(pg_temp.ba(44))$$,
  '42501','challenge_admission_paused',
  'a suspended fixture actor is still paused');
select public.challenge_runtime_v1(true,false,true,array(select id from public.profiles where id::text like 'bf000000-%'));
select throws_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  '42501','challenge_admission_paused',
  'with fixtures off even an age-confirmed actor is paused');
select pg_temp.clock_beta('2026-10-01T12:00Z');

-- Confirming 21+ restores admission on both fixture paths.
select pg_temp.login_beta(41);
select public.challenge_confirm_age_v1(pg_temp.br(52802),true);
reset role;
select lives_ok($$select app.challenge_admit_v1(pg_temp.ba(41))$$,
  'the roster actor is admitted after confirming 21+');
select pg_temp.login_beta(41);
select lives_ok($$select pg_temp.beta_create()$$,
  'the roster actor can create a challenge after confirming 21+');
reset role;
select pg_temp.login_outside(42);
select public.challenge_confirm_age_v1(pg_temp.br(52803),true);
reset role;
select lives_ok($$select app.challenge_admit_v1(pg_temp.outside(42))$$,
  'the Beta access actor is admitted after confirming 21+');

-- The real-health branch is unchanged: it checks age without the roster.
select public.challenge_real_health_runtime_v1(true,true,false);
select set_config('app.challenge_real_health_command_v1','on',true);
select throws_ok($$select app.challenge_admit_v1(pg_temp.outside(43))$$,
  '42501','challenge_age_required',
  'the real-health branch still requires 21+ confirmation');
select lives_ok($$select app.challenge_admit_v1(pg_temp.ba(1))$$,
  'the real-health branch still admits an age-confirmed actor');
select set_config('app.challenge_real_health_command_v1','off',true);

-- Private-trial checks still run before either branch.
update app.challenge_private_device_trial_v1 set enabled = true where singleton;
select throws_ok($$select app.challenge_admit_v1(pg_temp.outside(43))$$,
  '42501','challenge_private_trial_account_required',
  'the private trial still refuses an unenrolled account first');
insert into app.challenge_private_device_accounts_v1(actor_id) values(pg_temp.outside(43));
select throws_ok($$select app.challenge_admit_v1(pg_temp.outside(43))$$,
  '42501','challenge_private_trial_personal_steps_only',
  'the private trial still refuses the fixture path before the age check');

select * from finish();
rollback;
