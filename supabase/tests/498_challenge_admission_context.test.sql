begin;
select no_plan();
\ir fixtures/challenge-fixture.inc
\ir fixtures/challenge-matrix-fixture.inc
create function pg_temp.matrix_window(p text,a integer,input_config jsonb) returns uuid language plpgsql as $$
declare cfg jsonb; preview jsonb; c uuid; m text:=split_part(p,'_',2); begin
 perform set_config('role','none',true);
 perform public.challenge_readiness_metric_fixture_v1(pg_temp.ba(a),m);
 perform pg_temp.login_beta(a);
 cfg:=input_config;
 if m='timed' then cfg:=cfg||'{"distance_mm":1609344}';end if;
 if split_part(p,'_',1)='personal' then
  preview:=public.challenge_personal_preview_v1(p,cfg,100);
  c:=(public.challenge_mutate_v1(extensions.gen_random_uuid(),jsonb_build_object('op','personal_commit','policy',p,'config',cfg,'target',100,'digest',preview->>'digest','consent',true))->>'id')::uuid;
  perform set_config('role','none',true);return c;
 end if;
 c:=(public.challenge_mutate_v1(extensions.gen_random_uuid(),jsonb_build_object('op','create','policy',p,'config',cfg))->>'id')::uuid;
 if split_part(p,'_',3)='goal' then perform pg_temp.beta_mutate(c,'target','{"target":100}');end if;
 if split_part(p,'_',1)='friend' then
  perform pg_temp.beta_mutate(c,'invite',jsonb_build_object('username','betafixture'||lpad((a+1)::text,4,'0')));
  perform set_config('role','none',true);perform public.challenge_readiness_metric_fixture_v1(pg_temp.ba(a+1),m);
  perform pg_temp.login_beta(a+1);
  if split_part(p,'_',3)='goal' then perform pg_temp.beta_mutate(c,'target','{"target":100}');end if;
  perform pg_temp.login_beta(a);perform pg_temp.beta_mutate(c,'select',jsonb_build_object('actor_id',pg_temp.ba(a+1),'selected',true));
 end if;
 perform pg_temp.beta_mutate(c,'freeze');
 perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 if split_part(p,'_',1)='friend' then
  perform pg_temp.login_beta(a+1);perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 end if;
 perform set_config('role','none',true); return c;
end $$;

insert into beta_ids values('old',pg_temp.matrix_create('friend_steps_goal_v1',1));
select pg_temp.clock_beta('2026-10-03T12:00Z');
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='old'),pg_temp.ba(n),200,'complete') from generate_series(1,2)n;
select pg_temp.clock_beta('2026-10-06T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='old'));
select is((select status from app.challenge_lobbies_v1 where id=(select id from beta_ids where name='old')),'review','previous activity window is finished but result is still in review');
insert into beta_ids values('future',pg_temp.matrix_window('friend_steps_goal_v1',1,'{"start_date":"2026-10-08","days":1,"timezone":"UTC","amount_cents":100}'));
select is((select count(*)::integer from app.challenge_slots_v1 where actor_id=pg_temp.ba(1)),2,'future friend window can coexist with prior review and counts both unsettled slots');
select throws_ok($$select pg_temp.matrix_window('friend_steps_leaderboard_v1',1,'{"start_date":"2026-10-08","days":1,"timezone":"UTC","amount_cents":100}')$$,'23505','challenge_metric_overlap','overlapping friend goal and leaderboard of same metric are rejected');
reset role;
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(48001),pg_temp.ba(40),'{"start_date":"2026-10-08","days":1,"timezone":"UTC","amount_cents":100}',100,2,6,true));
select public.challenge_discovery_fixture_v1(true);
select pg_temp.login_beta(1);
select lives_ok($$select public.challenge_join_community_v1(pg_temp.br(48002),jsonb_build_object('op','join_community','id',(select id from beta_ids where name='community'),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true))$$,'one community may overlap the friend steps window');
reset role;
select is((select count(*)::integer from app.challenge_slots_v1 where actor_id=pg_temp.ba(1)),3,'community exception still consumes aggregate unsettled slot');
select throws_ok($$select pg_temp.matrix_window('personal_exercise_goal_v1',1,'{"start_date":"2026-10-08","days":1,"timezone":"UTC","amount_cents":100}')$$,'23505','challenge_unsettled_limit','different-metric personal challenge cannot exceed three unsettled');
reset role;
select pg_temp.login_beta(2);
select public.challenge_join_community_v1(pg_temp.br(48003),jsonb_build_object('op','join_community','id',(select id from beta_ids where name='community'),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));
reset role;
select pg_temp.clock_beta('2026-10-08T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='community'));
select public.challenge_capture_fixture_v1(pg_temp.br(48004),(select id from beta_ids where name='community'),pg_temp.ba(1),200,'complete');
select public.challenge_capture_fixture_v1(pg_temp.br(48005),(select id from beta_ids where name='community'),pg_temp.ba(2),null,'unresolved');
select pg_temp.clock_beta('2026-10-12T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='community'));
select pg_temp.clock_beta('2026-10-14T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='community'));
select pg_temp.login_beta(1);
select is(public.challenge_detail_v1((select id from beta_ids where name='community'))->'final'->'result'->'own'->>'returned_cents','100','community unknown leaves fewer than minimum and returns known participant entry');
select pg_temp.login_beta(2);
select is(public.challenge_detail_v1((select id from beta_ids where name='community'))->'final'->'result'->'own'->>'returned_cents','100','unknown community result returns its own entry');
reset role;
insert into beta_ids values('leader',pg_temp.matrix_create('friend_steps_leaderboard_v1',20));
select pg_temp.clock_beta('2026-10-03T12:00Z');
select public.challenge_capture_fixture_v1(extensions.gen_random_uuid(),(select id from beta_ids where name='leader'),pg_temp.ba(n),200,'complete') from generate_series(20,21)n;
select pg_temp.clock_beta('2026-10-06T12:00Z');
select public.challenge_process_v1((select id from beta_ids where name='leader'));
select pg_temp.login_beta(20);
select pg_temp.beta_mutate((select id from beta_ids where name='leader'),'review','{"notice_revision":1,"reason":"wrong_total"}');
reset role;
select public.challenge_grant_operator_v1(pg_temp.ba(40),(select id from beta_ids where name='leader'),'review','2026-10-10T12:00Z');
select pg_temp.login_beta(40);
select ok(not (public.challenge_operator_cases_v1((select id from beta_ids where name='leader'))->0->'context' ? 'target'),'reviewer context also keeps leaderboards target-free');
select is(public.challenge_operator_cases_v1((select id from beta_ids where name='leader'))->0->'context'->'fact'->>'value','200','assigned reviewer sees only normalized filer total');
select ok(not (public.challenge_operator_cases_v1((select id from beta_ids where name='leader'))->0->'context' ? 'participants'),'review context does not contain other participant histories or roster');
select pg_temp.login_beta(39);
select throws_ok($$select public.challenge_operator_cases_v1((select id from beta_ids where name='leader'))$$,'42501','challenge_operator_required','unassigned actor cannot obtain normalized case context');
reset role;
select pg_temp.clock_beta('2026-10-10T12:00Z');
select pg_temp.login_beta(40);
select throws_ok($$select public.challenge_operator_cases_v1((select id from beta_ids where name='leader'))$$,'42501','challenge_operator_required','assignment expiry equality closes case context');
reset role;
select * from finish();rollback;
