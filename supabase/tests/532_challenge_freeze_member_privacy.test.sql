-- A freeze that fails because of another member names no reason.
-- Fictional rollback-only actors on the fixture clock.
begin;
select no_plan();
\ir fixtures/challenge-fixture.inc

-- A two-person lobby between two fixture actors, frozen and agreed, starting
-- on the given date for seven days.
create function pg_temp.group_on(creator integer, other integer, start_date text, do_freeze boolean default true)
returns uuid language plpgsql as $$
declare c uuid;
begin
  perform pg_temp.login_beta(creator);
  c := (public.challenge_mutate_v1(extensions.gen_random_uuid(), jsonb_build_object('op', 'create', 'config',
    jsonb_build_object('start_date', start_date, 'days', 7, 'timezone', 'America/Chicago', 'amount_cents', 100)))->>'id')::uuid;
  perform pg_temp.beta_mutate(c, 'target', '{"target":10000}');
  perform pg_temp.beta_mutate(c, 'invite', jsonb_build_object('username', 'betafixture' || lpad(other::text, 4, '0')));
  perform pg_temp.login_beta(other);
  perform pg_temp.beta_mutate(c, 'target', '{"target":10000}');
  perform pg_temp.login_beta(creator);
  perform pg_temp.beta_mutate(c, 'select', jsonb_build_object('actor_id', pg_temp.ba(other), 'selected', true));
  if do_freeze then perform pg_temp.beta_mutate(c, 'freeze'); end if;
  perform set_config('role', 'none', true);
  return c;
end $$;
create function pg_temp.freeze_as(n integer, c uuid) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login_beta(n);
  r := pg_temp.beta_mutate(c, 'freeze');
  perform set_config('role', 'none', true);
  return r;
end $$;
create temp table lobbies(name text primary key, id uuid);

-- Another member already has a same-activity challenge on these dates.
insert into lobbies select 'busy', pg_temp.group_on(2, 3, '2026-10-03');
insert into lobbies select 'overlap', pg_temp.group_on(1, 2, '2026-10-03', false);
select throws_ok(format('select pg_temp.freeze_as(1, %L)', (select id from lobbies where name = 'overlap')),
  '42501', 'challenge_member_unavailable', 'another member''s overlap names no reason');
select is((select status from app.challenge_lobbies_v1 where id = (select id from lobbies where name = 'overlap')),
  'lobby_open', 'the lobby stays open');
select is((select count(*) from app.challenge_slots_v1 where challenge_id = (select id from lobbies where name = 'overlap')),
  0::bigint, 'no slot is saved for anyone');

-- The creator's own overlap keeps its specific reason.
insert into lobbies select 'own_overlap', pg_temp.group_on(2, 4, '2026-10-03', false);
select throws_ok(format('select pg_temp.freeze_as(2, %L)', (select id from lobbies where name = 'own_overlap')),
  '23505', 'challenge_metric_overlap', 'the creator''s own overlap keeps its reason');

-- When the creator and another member are both at a limit, the creator hears
-- their own reason, whatever order the roster is checked in.
insert into lobbies select 'both_overlap', pg_temp.group_on(3, 2, '2026-10-03', false);
select throws_ok(format('select pg_temp.freeze_as(3, %L)', (select id from lobbies where name = 'both_overlap')),
  '23505', 'challenge_metric_overlap', 'a creator at a limit hears their own reason first');

-- Another member with three unsettled challenges.
insert into lobbies select 'u1', pg_temp.group_on(10, 11, '2026-10-03');
insert into lobbies select 'u2', pg_temp.group_on(10, 12, '2026-10-11');
insert into lobbies select 'u3', pg_temp.group_on(10, 13, '2026-10-19');
insert into lobbies select 'fourth', pg_temp.group_on(14, 10, '2026-10-27', false);
select throws_ok(format('select pg_temp.freeze_as(14, %L)', (select id from lobbies where name = 'fourth')),
  '42501', 'challenge_member_unavailable', 'another member''s unsettled limit names no reason');
insert into lobbies select 'own_fourth', pg_temp.group_on(10, 15, '2026-10-27', false);
select throws_ok(format('select pg_temp.freeze_as(10, %L)', (select id from lobbies where name = 'own_fourth')),
  '23505', 'challenge_unsettled_limit', 'the creator''s own unsettled limit keeps its reason');

-- Another member suspended after being picked.
insert into lobbies select 'suspended', pg_temp.group_on(20, 21, '2026-10-03', false);
select set_config('app.challenge_write_v1', 'on', true);
insert into app.challenge_suspensions_v1 values (pg_temp.ba(21), true, pg_temp.ba(1), 'username', clock_timestamp());
select throws_ok(format('select pg_temp.freeze_as(20, %L)', (select id from lobbies where name = 'suspended')),
  '42501', 'challenge_member_unavailable', 'a suspended member names no reason');

-- A roster everyone can join still freezes.
insert into lobbies select 'clear', pg_temp.group_on(30, 31, '2026-10-03', false);
select is(pg_temp.freeze_as(30, (select id from lobbies where name = 'clear'))->>'status', 'consent_pending',
  'a roster everyone can join still freezes');

select * from finish();
rollback;
