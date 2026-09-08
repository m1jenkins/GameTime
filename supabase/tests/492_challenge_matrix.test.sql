begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
select is((select count(*) from (select app.challenge_policy_v1(mode||'_'||metric||'_'||competition||'_v1') from unnest(array['friend','personal']) mode cross join unnest(array['steps','exercise','distance','timed']) metric cross join unnest(array['goal','leaderboard']) competition where mode='friend' or competition='goal' union all select app.challenge_policy_v1('community_steps_goal_v1')) x),13::bigint,'exact thirteen policy combinations');
select throws_ok($$select app.challenge_policy_v1('personal_steps_leaderboard_v1')$$,'22023','challenge_invalid_policy','no personal leaderboard');
create function pg_temp.matrix_people(timed boolean,leaderboard boolean) returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_object('actor_id',pg_temp.ba(n),'target',case when leaderboard then null else 100 end,'value',case when n=1 then 100 else 99 end,'state','complete','excluded',false)) from generate_series(1,2) n
$$;
create function pg_temp.matrix_evaluator_checks() returns setof text language plpgsql as $$ declare m text; competition text; mode text; policy text; result jsonb; c uuid; i integer:=10; conf jsonb; begin
 for m in select unnest(array['steps','exercise','distance','timed']) loop
  foreach competition in array array['goal','leaderboard'] loop
   policy:='friend_'||m||'_'||competition||'_v1';
   result:=app.challenge_evaluate_policy_v1(policy,pg_temp.matrix_people(m='timed',competition='leaderboard'),100,2);
   return next ok(result->>'outcome'='scored',policy||' normalized results score');
   return next is(result->'participants'->pg_temp.ba(case when m='timed' then 2 else 1 end)::text->>'returned_cents','200',policy||' exact comparator');
  end loop;
  result:=app.challenge_evaluate_policy_v1('personal_'||m||'_goal_v1',jsonb_build_array(pg_temp.matrix_people(m='timed',false)->0),100,1);
  return next is(result->>'unallocated_cents',case when m='timed' then '100' else '0' end,'personal '||m||' equality rule');
 end loop;
end $$;
select * from pg_temp.matrix_evaluator_checks();
select is(app.challenge_evaluate_policy_v1('friend_steps_leaderboard_v1','[{"actor_id":"a","target":null,"value":20,"state":"complete","excluded":false},{"actor_id":"b","target":null,"value":20,"state":"complete","excluded":false},{"actor_id":"c","target":null,"value":20,"state":"complete","excluded":false},{"actor_id":"d","target":null,"value":10,"state":"complete","excluded":false}]',100,2)->>'unallocated_cents','1','leaderboard co-winners preserve remainder');
select is(app.challenge_evaluate_policy_v1('friend_steps_leaderboard_v1','[{"actor_id":"a","target":null,"value":20,"state":"complete","excluded":false},{"actor_id":"b","target":null,"value":null,"state":"unresolved","excluded":false}]',100,2)->>'outcome','void','any unresolved leaderboard voids');
select is(app.challenge_evaluate_policy_v1('personal_timed_goal_v1','[{"actor_id":"a","target":360,"value":360,"state":"complete","excluded":false}]',100,1)->'participants'->'a'->>'status','missed','strict timed equality is miss only with complete facts');
select is(app.challenge_evaluate_policy_v1('personal_timed_goal_v1','[{"actor_id":"a","target":360,"value":null,"state":"unresolved","excluded":false}]',100,1)->'participants'->'a'->>'status','void','missing personal timed data voids');
-- Persist every friend and personal policy with its own readiness and lifecycle.
\ir fixtures/challenge-matrix-fixture.inc

insert into beta_ids(name,id) select p,pg_temp.matrix_create(p,10) from (select mode||'_'||metric||'_'||competition||'_v1' p from unnest(array['friend','personal']) mode cross join unnest(array['steps','exercise','distance','timed']) metric cross join unnest(array['goal','leaderboard']) competition where mode='friend' or competition='goal' limit 1) policies;
-- Close each before the next to exercise all types without bypassing admission.
create function pg_temp.matrix_lifecycle_checks() returns setof text language plpgsql as $$ declare p text; c uuid; a uuid; begin
 for p in select mode||'_'||metric||'_'||competition||'_v1' from unnest(array['friend','personal']) mode cross join unnest(array['steps','exercise','distance','timed']) metric cross join unnest(array['goal','leaderboard']) competition where mode='friend' or competition='goal' loop
  -- Use a disjoint actor pair from the separately persisted admission fixture.
  c:=pg_temp.matrix_create(p,20);
  return next is((select status from app.challenge_lobbies_v1 where id=c),'scheduled',p||' schedules after full consent');
  perform pg_temp.clock_beta('2026-10-04T12:00Z');
  for a in select actor_id from app.challenge_slots_v1 where challenge_id=c loop
   perform public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),c,a,99,'complete');
  end loop;
  perform pg_temp.clock_beta('2026-10-06T12:00Z');perform public.challenge_process_v1(c);
  perform pg_temp.clock_beta('2026-10-08T12:00Z');perform public.challenge_process_v1(c);
  return next ok(exists(select 1 from app.challenge_finals_v1 where challenge_id=c),p||' immutable final persisted');
 end loop;
end $$;
select * from pg_temp.matrix_lifecycle_checks();
select * from finish();
rollback;
