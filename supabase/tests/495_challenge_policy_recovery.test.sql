begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
\ir fixtures/challenge-matrix-fixture.inc
create function pg_temp.policy_recovery_checks() returns setof text language plpgsql as $$
declare policy text;c uuid;start_actor integer:=10;row jsonb;begin
 for policy in select mode||'_'||metric||'_'||competition||'_v1' from unnest(array['friend','personal']) mode cross join unnest(array['steps','exercise','distance','timed']) metric cross join unnest(array['goal','leaderboard']) competition where mode='friend' or competition='goal' loop
  c:=pg_temp.matrix_create(policy,start_actor);
  perform pg_temp.clock_beta('2026-10-03T12:00Z');
  perform public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),c,pg_temp.ba(start_actor),null,'unresolved');
  if split_part(policy,'_',1)='friend' then perform public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),c,pg_temp.ba(start_actor+1),100,'complete');end if;
  perform pg_temp.clock_beta('2026-10-06T12:00Z');perform public.challenge_process_v1(c);
  perform pg_temp.clock_beta('2026-10-08T11:59:59Z');perform pg_temp.login_beta(start_actor);
  perform pg_temp.beta_mutate(c,'review','{"notice_revision":1,"reason":"missing_activity"}');
  perform set_config('role','none',true);perform pg_temp.clock_beta('2026-10-08T12:00Z',false,true);
  return next is(public.challenge_process_v1(c),'review',policy||' late filing retains its 72-hour resolution window');
  perform pg_temp.clock_beta('2026-10-11T11:59:59Z',false,true);perform public.challenge_process_v1(c);
  return next is((select result->>'outcome' from app.challenge_finals_v1 where challenge_id=c),'void',policy||' unresolved minimum voids without a confirmed miss');
  return next is((select result->'participants'->pg_temp.ba(start_actor)::text->>'returned_cents' from app.challenge_finals_v1 where challenge_id=c),'100',policy||' missing data returns entry');
  c:=pg_temp.matrix_create(policy,start_actor);
  perform pg_temp.clock_beta('2026-10-01T12:00Z',false,false);perform pg_temp.login_beta(start_actor);
  perform pg_temp.beta_mutate(c,'leave');perform set_config('role','none',true);perform app.challenge_tick_v1(c,true);
  return next is((select result->'participants'->pg_temp.ba(start_actor)::text->>'returned_cents' from app.challenge_finals_v1 where challenge_id=c),'100',policy||' voluntary exit works during admission and processing pause');
 end loop;
end $$;
select * from pg_temp.policy_recovery_checks();
select * from finish();rollback;
