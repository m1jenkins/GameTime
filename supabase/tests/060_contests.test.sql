-- contests: the terms, the window, and who is allowed to see or change them.
--
-- The properties that matter:
--   * a contest window cannot open in the past, because that is an unlosable bet
--   * the terms are frozen from the instant the row exists
--   * status moves forward only, and cancelled and finalized are terminal
--   * a contest is visible to its participants and to nobody else — not even to
--     the rest of the group it is scoped to

begin;
select plan(52);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice, the author
  ('22222222-2222-2222-2222-222222222222'),  -- bob, her friend
  ('33333333-3333-3333-3333-333333333333'),  -- carol, a group co-member
  ('44444444-4444-4444-4444-444444444444'),  -- dave, unrelated
  ('55555555-5555-5555-5555-555555555555');  -- no profile: mid-onboarding

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol'),
  ('44444444-4444-4444-4444-444444444444', 'dave',  'Dave');

insert into public.friendships (user_a, user_b, requested_by, status) values
  ('11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111', 'accepted');

-- alice's group; carol is in it, bob is not.
insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999999', 'Crew',
   '11111111-1111-1111-1111-111111111111');
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999',
   '33333333-3333-3333-3333-333333333333');

insert into public.charities (id, name, ein, slug, is_active) values
  ('c0000001-0000-0000-0000-000000000001', 'Trail Fund',   '12-3456789', 'trail-fund',  true),
  ('c0000002-0000-0000-0000-000000000002', 'Retired Fund', '66-3456789', 'retired-fund', false);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'contests', 'public.contests exists');
select col_is_pk('public', 'contests', 'id', 'contests is keyed by a surrogate id');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.contests'::regclass),
  'row level security is enabled on contests'
);

-- ---------------------------------------------------------------------------
-- Creation
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

create temporary table t_duel as
select public.create_contest(
  'Step Duel',
  'steps', 'daily', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'America/New_York', 'c0000001-0000-0000-0000-000000000001',
  2::smallint
) as id;

reset role;

select is(
  (select status::text from public.contests where id = (select id from t_duel)),
  'pending',
  'a new contest starts pending'
);

select is(
  (select tie_break::text from public.contests where id = (select id from t_duel)),
  'integrity_score',
  'the tie-break defaults to integrity score, so clean data wins a tie'
);

-- The author is enrolled from the first instant. They wrote the terms, so there
-- is nothing left for them to agree to — and it makes "a contest always has at
-- least one participant" true immediately, the way M1 did for groups.
select is(
  (select count(*) from public.contest_participants
   where contest_id = (select id from t_duel)),
  1::bigint,
  'creating a contest enrols its author'
);

select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_duel)),
  'accepted',
  'and enrols them as accepted, not invited'
);

select is(
  (select timezone from public.contest_participants
   where contest_id = (select id from t_duel)),
  'America/New_York',
  'with the timezone they supplied, frozen on the participant row'
);

-- ---------------------------------------------------------------------------
-- The window cannot open in the past
-- ---------------------------------------------------------------------------
-- This is the anti-cheat assertion in this file. A creator who already knows
-- what they walked yesterday and can name yesterday as the window has a contest
-- they cannot lose, and every sample in it is genuine, so nothing downstream
-- would ever flag it.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ select public.create_contest(
       'Backdated', 'steps', 'cumulative', 10000, 2500,
       now() - interval '1 day', now() + interval '1 day',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '22023',
  null,
  'a contest window cannot open in the past'
);

select throws_ok(
  $$ select public.create_contest(
       'Inverted', 'steps', 'cumulative', 10000, 2500,
       now() + interval '2 days', now() + interval '1 day',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a window must end after it starts'
);

select throws_ok(
  $$ select public.create_contest(
       'Forever', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '400 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a window is bounded, so a pledge cannot stay open indefinitely'
);

-- A daily-cadence contest over four hours has no days to evaluate.
select throws_ok(
  $$ select public.create_contest(
       'Too Short For Daily', 'steps', 'daily', 10000, 2500,
       now() + interval '1 day', now() + interval '1 day 4 hours',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a daily-cadence window must span at least one day'
);

-- The same window is fine cumulatively — a four-hour hike challenge is a real
-- contest, so the floor belongs to the cadence and not to the window.
select lives_ok(
  $$ select public.create_contest(
       'Short Hike', 'distance_meters', 'cumulative', 8000, 2500,
       now() + interval '1 day', now() + interval '1 day 4 hours',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  'a short window is fine for a cumulative goal'
);

-- ---------------------------------------------------------------------------
-- Term guards
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select public.create_contest(
       'Too Cheap', 'steps', 'cumulative', 10000, 99,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a stake below the floor is refused'
);

-- The ceiling is a fat-finger guard, not a technical limit: this column creates
-- a donation obligation and a stray zero is a plausible and expensive typo.
select throws_ok(
  $$ select public.create_contest(
       'Too Rich', 'steps', 'cumulative', 10000, 1000001,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a stake above the ceiling is refused'
);

select throws_ok(
  $$ select public.create_contest(
       'No Target', 'steps', 'cumulative', 0, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a contest needs a positive target'
);

select throws_ok(
  $$ select public.create_contest(
       'Solo', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001', 1::smallint) $$,
  '23514',
  null,
  'a contest of one is not a contest'
);

-- Twenty is the ceiling because a winner-takes-all roster of n produces n-1
-- donation obligations (D4).
select throws_ok(
  $$ select public.create_contest(
       'Stadium', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001', 21::smallint) $$,
  '23514',
  null,
  'the roster ceiling bounds how many obligations one contest can create'
);

select throws_ok(
  $$ select public.create_contest(
       repeat('x', 81), 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a title has a length limit'
);

-- A retired charity cannot be nominated afresh.
select throws_ok(
  $$ select public.create_contest(
       'Retired Nomination', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000002-0000-0000-0000-000000000002') $$,
  '22023',
  null,
  'a retired charity cannot be nominated'
);

-- ---------------------------------------------------------------------------
-- Authentication, onboarding, and group scope
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$ select public.create_contest(
       'Anonymous', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'creating a contest requires a signed-in caller'
);

-- An auth user with no profile is mid-onboarding (D20), which is a legitimate
-- state and not one that can author a contest.
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}', true);
select throws_ok(
  $$ select public.create_contest(
       'Unonboarded', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'a caller without a profile cannot author a contest'
);

-- Scoping a contest to a group you are not in would name a roster you have no
-- reach into.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ select public.create_contest(
       'Not My Group', 'steps', 'cumulative', 10000, 2500,
       now() + interval '1 day', now() + interval '2 days',
       'UTC', 'c0000001-0000-0000-0000-000000000001',
       4::smallint, 'integrity_score',
       '99999999-9999-9999-9999-999999999999') $$,
  '42501',
  null,
  'a non-member cannot scope a contest to a group'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

create temporary table t_group_contest as
select public.create_contest(
  'Crew Cumulative', 'steps', 'cumulative', 50000, 5000,
  now() + interval '1 day', now() + interval '10 days',
  'America/New_York', 'c0000001-0000-0000-0000-000000000001',
  4::smallint, 'integrity_score',
  '99999999-9999-9999-9999-999999999999'
) as id;

reset role;
select is(
  (select group_id from public.contests where id = (select id from t_group_contest)),
  '99999999-9999-9999-9999-999999999999'::uuid,
  'a member may scope a contest to their group'
);

-- ---------------------------------------------------------------------------
-- The terms are frozen
-- ---------------------------------------------------------------------------
-- Asserted as superuser on purpose. Clients hold no UPDATE on this table at
-- all, so these assertions are about the second mechanism: a privileged writer
-- that gets past the missing grant is still stopped by the trigger. Same
-- two-layer pattern as groups.created_by in M1 (D21).
select throws_ok(
  $$ update public.contests set stake_amount_cents = 100
     where id = (select id from t_duel) $$,
  '23001',
  null,
  'the stake cannot be rewritten after anyone has agreed to it'
);

select throws_ok(
  $$ update public.contests set ends_at = now() + interval '30 days'
     where id = (select id from t_duel) $$,
  '23001',
  null,
  'the window cannot be moved'
);

select throws_ok(
  $$ update public.contests set max_participants = 20
     where id = (select id from t_duel) $$,
  '23001',
  null,
  'the roster ceiling cannot be raised after invitees were shown it'
);

select throws_ok(
  $$ update public.contests
     set created_by = '22222222-2222-2222-2222-222222222222'
     where id = (select id from t_duel) $$,
  '23001',
  null,
  'authorship cannot be reassigned'
);

-- created_by and group_id are references with `on delete set null`, so they use
-- the variant of the freeze that tolerates being cleared. Repointing is still
-- refused, which is the half that matters: a contest cannot be moved into a
-- different group's reach after people agreed to it.
insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999998', 'Other Crew',
   '11111111-1111-1111-1111-111111111111');

select throws_ok(
  $$ update public.contests
     set group_id = '99999999-9999-9999-9999-999999999998'
     where id = (select id from t_group_contest) $$,
  '23001',
  null,
  'a contest cannot be moved into a different group'
);

-- ---------------------------------------------------------------------------
-- The status machine
-- ---------------------------------------------------------------------------
insert into public.contests
  (id, title, created_by, metric, cadence, target_value,
   stake_amount_cents, starts_at, ends_at)
values
  ('d0000001-0000-0000-0000-000000000001', 'Status Machine',
   '11111111-1111-1111-1111-111111111111', 'steps', 'cumulative', 100, 1000,
   now() + interval '1 day', now() + interval '2 days'),
  ('d0000002-0000-0000-0000-000000000002', 'Terminal Check',
   '11111111-1111-1111-1111-111111111111', 'steps', 'cumulative', 100, 1000,
   now() + interval '1 day', now() + interval '2 days');

select lives_ok(
  $$ update public.contests set status = 'active'
     where id = 'd0000001-0000-0000-0000-000000000001' $$,
  'pending moves to active'
);

select throws_ok(
  $$ update public.contests set status = 'pending'
     where id = 'd0000001-0000-0000-0000-000000000001' $$,
  '23001',
  null,
  'and cannot move back to pending'
);

-- An active contest cannot be called off. A stake the loser can cancel is not
-- a stake.
select throws_ok(
  $$ update public.contests
     set status = 'cancelled', cancellation_reason = 'creator_cancelled',
         cancelled_at = now()
     where id = 'd0000001-0000-0000-0000-000000000001' $$,
  '23001',
  null,
  'an active contest cannot be cancelled'
);

select throws_ok(
  $$ update public.contests set status = 'finalized'
     where id = 'd0000002-0000-0000-0000-000000000002' $$,
  '23001',
  null,
  'a pending contest cannot skip straight to finalized'
);

update public.contests
set status = 'cancelled', cancellation_reason = 'creator_cancelled',
    cancelled_at = now()
where id = 'd0000002-0000-0000-0000-000000000002';

select throws_ok(
  $$ update public.contests set status = 'active'
     where id = 'd0000002-0000-0000-0000-000000000002' $$,
  '23001',
  null,
  'cancelled is terminal'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.contests', 'select'),
  'authenticated may read contests it can see'
);
select ok(
  not has_table_privilege('authenticated', 'public.contests', 'insert'),
  'authenticated cannot INSERT a contest; create_contest owns that'
);
select ok(
  not has_table_privilege('authenticated', 'public.contests', 'update'),
  'authenticated cannot UPDATE a contest at all: terms are frozen, status is not theirs'
);
select ok(
  not has_table_privilege('authenticated', 'public.contests', 'delete'),
  'authenticated cannot DELETE a contest; a contest that happened is evidence'
);
select ok(
  not has_table_privilege('anon', 'public.contests', 'select'),
  'anon cannot read contests'
);
select ok(
  not has_function_privilege('anon',
    'public.create_contest(text,public.contest_metric,public.contest_cadence,'
    || 'numeric,integer,timestamptz,timestamptz,text,uuid,smallint,'
    || 'public.contest_tie_break,uuid)', 'execute'),
  'anon cannot execute create_contest'
);

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is(
  (select count(*) from public.contests where id = (select id from t_duel)),
  1::bigint,
  'a participant can read their contest'
);

select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
select is(
  (select count(*) from public.contests),
  0::bigint,
  'an unrelated user sees no contests at all'
);

-- The interesting one: carol is in the group this contest is scoped to, and
-- still cannot see it. A group contest's stake and roster are an arrangement
-- between the people in it, not group-wide news.
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select is(
  (select count(*) from public.contests
   where id = (select id from t_group_contest)),
  0::bigint,
  'a co-member of the scoped group cannot see a contest they are not in'
);

-- ---------------------------------------------------------------------------
-- cancel_contest
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

create temporary table t_cancelme as
select public.create_contest(
  'Cancel Me', 'steps', 'cumulative', 10000, 2500,
  now() + interval '3 days', now() + interval '5 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001'
) as id;

insert into public.contest_participants (contest_id, user_id, invited_by)
values ((select id from t_cancelme),
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111');

-- A participant cannot call off someone else's contest.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ select public.cancel_contest((select id from t_cancelme)) $$,
  '42501',
  null,
  'only the author may cancel'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select lives_ok(
  $$ select public.cancel_contest((select id from t_cancelme)) $$,
  'the author may cancel while the contest is still pending'
);

reset role;
select is(
  (select cancellation_reason::text from public.contests
   where id = (select id from t_cancelme)),
  'creator_cancelled',
  'and the reason is recorded, so the client can say why it vanished'
);

-- Nobody is owed an answer to an invitation to a contest that will not happen.
select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_cancelme)
     and user_id = '22222222-2222-2222-2222-222222222222'),
  'lapsed',
  'cancelling closes every outstanding invitation'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ select public.cancel_contest((select id from t_cancelme)) $$,
  '23001',
  null,
  'cancelling twice is refused rather than silently idempotent'
);

-- d0000001 is active and authored by alice.
select throws_ok(
  $$ select public.cancel_contest('d0000001-0000-0000-0000-000000000001') $$,
  '23001',
  null,
  'and an active contest cannot be cancelled by its author either'
);

-- ---------------------------------------------------------------------------
-- A contest outlives its author and its group
-- ---------------------------------------------------------------------------
-- The other half of the freeze above, and the reason it is not the strict
-- variant. A contest is financial history: deleting the account that wrote it,
-- or the group it was scoped to, must clear the reference and leave the contest
-- standing — not fail, and not take the contest with it.
--
-- A throwaway author, so this does not disturb the rest of the file.
reset role;
insert into auth.users (id) values ('88888888-8888-8888-8888-888888888888');
insert into public.profiles (id, handle, display_name) values
  ('88888888-8888-8888-8888-888888888888', 'departing', 'Departing');
insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999997', 'Doomed Crew',
   '88888888-8888-8888-8888-888888888888');
insert into public.contests
  (id, title, group_id, created_by, metric, cadence, target_value,
   stake_amount_cents, starts_at, ends_at)
values
  ('d0000003-0000-0000-0000-000000000003', 'Outlives Everyone',
   '99999999-9999-9999-9999-999999999997',
   '88888888-8888-8888-8888-888888888888', 'steps', 'cumulative', 100, 1000,
   now() + interval '1 day', now() + interval '2 days');

select lives_ok(
  $$ delete from public.groups
     where id = '99999999-9999-9999-9999-999999999997' $$,
  'deleting the scoped group clears group_id rather than failing'
);

select lives_ok(
  $$ delete from auth.users
     where id = '88888888-8888-8888-8888-888888888888' $$,
  'and deleting the author clears created_by rather than failing'
);

select is(
  (select count(*) from public.contests
   where id = 'd0000003-0000-0000-0000-000000000003'),
  1::bigint,
  'the contest itself survives both, because it is evidence'
);

select * from finish();
rollback;
