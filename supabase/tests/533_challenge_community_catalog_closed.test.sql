-- The community catalog follows the allowlist. Fictional rollback-only actors.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

create function pg_temp.catalog(n integer) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  r := public.challenge_community_catalog_v1();
  perform set_config('role', 'none', true);
  return r;
end $$;

-- A real-activity community published while nothing restricts the project.
select public.challenge_real_health_runtime_v1(true, true, false);
select set_config('test.catalog.start', to_char((clock_timestamp() at time zone 'UTC')::date + 5, 'YYYY-MM-DD'), true);
select lives_ok(format($$select public.challenge_publish_community_real_health_v1(extensions.gen_random_uuid(), %L,
  jsonb_build_object('start_date', %L, 'days', 1, 'timezone', 'UTC', 'amount_cents', 100), 8000, 2, 6, 'apple_watch_steps_v1')$$,
  pg_temp.ba(40), current_setting('test.catalog.start')), 'a community is published before enforcement');
select is(jsonb_array_length(pg_temp.catalog(1)), 1, 'an unrestricted project lists it');

update app.challenge_policy_runtime_v1 set allowlist_enforced = true;
select is(pg_temp.catalog(1), '[]'::jsonb, 'with community off the list, the catalog is empty');

insert into app.challenge_policy_allowlist_v1 values ('community_steps_goal_v1', 'apple_watch_steps_v1');
select is(jsonb_array_length(pg_temp.catalog(1)), 1, 'allowing community lists it again');

select * from finish();
rollback;
