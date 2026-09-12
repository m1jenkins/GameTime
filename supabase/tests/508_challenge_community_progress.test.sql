begin;select no_plan();
\ir fixtures/challenge-fixture.inc
insert into beta_ids values('community',public.challenge_publish_community_fixture_v1(pg_temp.br(80000),pg_temp.ba(40),'{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}',100,2,250,true));
select public.challenge_discovery_fixture_v1(true);
create function pg_temp.community() returns uuid language sql as $$select id from beta_ids where name='community'$$;
do $$declare i integer;begin
 for i in 1..6 loop perform pg_temp.login_beta(i);perform public.challenge_join_community_v1(pg_temp.br(80000+i),jsonb_build_object('op','join_community','id',pg_temp.community(),'digest',public.challenge_community_catalog_v1()->0->>'digest','consent',true));end loop;
 perform set_config('role','none',true);
end $$;
select public.challenge_capture_community_snapshot_v1(pg_temp.community());
select pg_temp.clock_beta('2026-10-03T12:00Z');select public.challenge_process_v1(pg_temp.community());
select public.challenge_capture_fixture_v1(pg_temp.br(80101),pg_temp.community(),pg_temp.ba(1),123,'complete');
select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'members'->0->'fact'->>'value','123','own progress immediately current');
create temp table own_revision as select public.challenge_detail_v1(pg_temp.community())->>'revision' revision;
grant all on own_revision to authenticated;
reset role;select public.challenge_capture_fixture_v1(pg_temp.br(80102),pg_temp.community(),pg_temp.ba(2),456,'complete');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->>'revision',(select revision from own_revision),'stranger activity does not advance own revision');
select ok(public.challenge_detail_v1(pg_temp.community())::text not like '%456%','stranger current value absent from full response');
reset role;select public.challenge_capture_fixture_v1(pg_temp.br(80103),pg_temp.community(),pg_temp.ba(1),100,'complete');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'members'->0->'fact'->>'value','100','downward own correction immediately current');
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'joined','6','own freshness independent of delayed aggregate');
reset role;
-- Blocked/suspended/removed accounts are not part of the five-person threshold.
select public.challenge_grant_support_v1(pg_temp.ba(39),'2026-10-06T00:00Z');select pg_temp.login_beta(39);
select public.challenge_support_suspend_v1(pg_temp.br(80201),pg_temp.ba(6),'unsafe_behavior');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'joined','6','five eligible can still see only old snapshot of six');
select pg_temp.login_beta(39);select public.challenge_support_suspend_v1(pg_temp.br(80202),pg_temp.ba(5),'unsafe_behavior');select pg_temp.login_beta(1);
select is(public.challenge_detail_v1(pg_temp.community())->'counts'->>'state','threshold','suspension to four suppresses exact counts immediately');
reset role;
-- More than 250 historical people, with only 250 nonexcluded, can settle.
select is(app.challenge_evaluate_policy_v1('community_steps_goal_v1',(select jsonb_agg(jsonb_build_object('actor_id',md5(n::text)::uuid,'target',100,'value',100,'state','complete','excluded',n>250)) from generate_series(1,251)n),100,2,true)->>'entry_cents','25100','replacement cohort preserves every historical entry');
select throws_ok($$select app.challenge_evaluate_policy_v1('community_steps_goal_v1',(select jsonb_agg(jsonb_build_object('actor_id',md5(n::text)::uuid,'target',100,'value',100,'state','complete','excluded',false)) from generate_series(1,251)n),100,2,true)$$,'22023','challenge_invalid_evaluation','251 active participants still rejected');
select * from finish();rollback;
