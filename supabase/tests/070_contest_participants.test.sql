-- contest_participants: invitations, the participant state machine, and the
-- three checks that cannot be written as row policies.
--
-- The properties that matter:
--   * who may be invited depends on rows other than the one being written — a
--     friendship, a group membership, or a block held by somebody already on the
--     roster. None of those fit in a WITH CHECK, which is why invitation is a
--     function
--   * the cap is a bound on a COUNT, so it is only real under a lock
--   * declining is terminal. There is no re-invitation, and the way to stop
--     being asked is a block, visibly, not a quirk of the state machine
--   * a block placed after an invitation does not hide the opponent, because
--     hiding them would announce the block to the person D19 declined to tell

begin;
select plan(56);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice, creator throughout
  ('22222222-2222-2222-2222-222222222222'),  -- bob, friend + group co-member
  ('33333333-3333-3333-3333-333333333333'),  -- carol, group co-member only
  ('44444444-4444-4444-4444-444444444444'),  -- dave, group co-member only
  ('66666666-6666-6666-6666-666666666666'),  -- erin, friend only, no group
  ('77777777-7777-7777-7777-777777777777'),  -- frank, friend only, no group
  ('88888888-8888-8888-8888-888888888888');  -- no profile: mid-onboarding

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol'),
  ('44444444-4444-4444-4444-444444444444', 'dave',  'Dave'),
  ('66666666-6666-6666-6666-666666666666', 'erin',  'Erin'),
  ('77777777-7777-7777-7777-777777777777', 'frank', 'Frank');

-- Erin and frank are friends with alice and nothing else. That isolation is what
-- makes the visibility assertions at the end mean something: with no shared
-- group, co-participation is the only route left.
insert into public.friendships (user_a, user_b, requested_by, status) values
  ('11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111',
   '66666666-6666-6666-6666-666666666666',
   '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111',
   '77777777-7777-7777-7777-777777777777',
   '11111111-1111-1111-1111-111111111111', 'accepted');

insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999999', 'Run Club',
   '11111111-1111-1111-1111-111111111111');
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222'),
  ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333'),
  ('99999999-9999-9999-9999-999999999999', '44444444-4444-4444-4444-444444444444');

-- The 00-9xxxxxx EIN range and `fixture-` slugs are reserved for tests; ein and
-- donation_slug are globally unique, so sharing seed.sql's values would make
-- these fixtures collide with it. See 050_charities.test.sql.
insert into public.charities (id, name, ein, donation_slug) values
  ('c0000001-0000-0000-0000-000000000001', 'Fixture Food Bank',
   '00-9000001', 'fixture-food-bank'),
  ('c0000002-0000-0000-0000-000000000002', 'Fixture Retired Cause',
   '00-9000002', 'fixture-retired-cause');
update public.charities set is_active = false
  where id = 'c0000002-0000-0000-0000-000000000002';

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'contest_participants', 'public.contest_participants exists');
select col_is_pk('public', 'contest_participants',
  array['contest_id', 'user_id'],
  'a person appears at most once per contest');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.contest_participants'::regclass),
  'row level security is enabled on contest_participants'
);

-- A nomination is part of the agreed terms, so a charity any contest points at
-- cannot be deleted out from under it. Retiring one is is_active = false.
select ok(
  (select confdeltype = 'r'  -- 'r' = RESTRICT
   from pg_constraint
   where conrelid = 'public.contest_participants'::regclass
     and confrelid = 'public.charities'::regclass),
  'a nominated charity cannot be deleted while a contest points at it'
);

insert into public.contests
  (id, kind, created_by, title, metric, cadence, target_value,
   starts_at, ends_at, stake_amount_cents, max_participants)
values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'duel',
   '11111111-1111-1111-1111-111111111111', 'Shape Fixture',
   'steps', 'total', 50000,
   now() + interval '2 days', now() + interval '9 days', 2500, 2);

-- ---------------------------------------------------------------------------
-- Row shape: the statuses are distinguishable by data, not only by name
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.contest_participants
       (contest_id, user_id, status, charity_id, responded_at)
     values ('aaaaaaa1-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'accepted',
             'c0000001-0000-0000-0000-000000000001', now()) $$,
  '23514',
  null,
  'a charity without a timezone is refused: both are chosen in the same act'
);

select throws_ok(
  $$ insert into public.contest_participants
       (contest_id, user_id, status, responded_at)
     values ('aaaaaaa1-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'accepted', now()) $$,
  '23514',
  null,
  'accepting without having chosen anything is refused'
);

-- This is what makes 'lapsed' tell a different story from 'withdrawn': a lapsed
-- row never chose, and could not have.
select throws_ok(
  $$ insert into public.contest_participants
       (contest_id, user_id, status, charity_id, timezone)
     values ('aaaaaaa1-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'invited',
             'c0000001-0000-0000-0000-000000000001', 'UTC') $$,
  '23514',
  null,
  'an unanswered invitation cannot have chosen a charity'
);

select throws_ok(
  $$ insert into public.contest_participants
       (contest_id, user_id, status, responded_at)
     values ('aaaaaaa1-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'invited', now()) $$,
  '23514',
  null,
  'and cannot carry a response timestamp'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.contest_participants', 'select'),
  'authenticated may read a roster it belongs to'
);
select ok(
  not has_table_privilege('authenticated', 'public.contest_participants', 'insert'),
  'but cannot INSERT a roster row; invite_to_contest() owns that'
);
select ok(
  not has_table_privilege('authenticated', 'public.contest_participants', 'update'),
  'and cannot UPDATE one; accept, decline, and withdraw own that'
);
select ok(
  not has_table_privilege('authenticated', 'public.contest_participants', 'delete'),
  'and cannot DELETE one: leaving is a status, so it stays on the record'
);
select ok(
  not has_table_privilege('anon', 'public.contest_participants', 'select'),
  'anon cannot read rosters'
);

-- ---------------------------------------------------------------------------
-- Invitation eligibility
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select public.create_contest(
  p_kind => 'duel', p_title => 'The Duel',
  p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
  p_starts_at => now() + interval '1 day',
  p_ends_at => now() + interval '8 days',
  p_stake_amount_cents => 2500,
  p_charity_id => 'c0000001-0000-0000-0000-000000000001',
  p_timezone => 'America/New_York');

-- Non-existent and not-yours give the same error, so this cannot be used to
-- discover that a contest id is real.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Duel'),
       '33333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'a non-creator cannot invite anybody'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Duel'),
       '11111111-1111-1111-1111-111111111111') $$,
  '22023',
  null,
  'the creator is already a participant and cannot invite themselves'
);

select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Duel'),
       '88888888-8888-8888-8888-888888888888') $$,
  '22023',
  null,
  'a user who has not finished onboarding cannot be invited'
);

-- Carol is a group co-member, which is enough to see alice's profile but not
-- enough to be duelled. A duel is between friends.
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Duel'),
       '33333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'a duel invitation must go to a friend, not merely to somebody visible'
);

select is(
  public.invite_to_contest(
    (select id from public.contests where title = 'The Duel'),
    '22222222-2222-2222-2222-222222222222'),
  'invited'::public.participant_status,
  'a friend can be invited to a duel'
);

-- Idempotent, and it reports what it found: the client can tell "already asked"
-- from "they said no" without a second read.
select is(
  public.invite_to_contest(
    (select id from public.contests where title = 'The Duel'),
    '22222222-2222-2222-2222-222222222222'),
  'invited'::public.participant_status,
  'inviting twice is not an error and reports the existing status'
);

select is(
  (select count(*) from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'The Duel'),
  2::bigint,
  'and does not duplicate the roster row'
);

-- A duel is capped at two, and an outstanding invitation counts against the cap.
-- Otherwise a creator could invite everybody and let the race decide.
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Duel'),
       '66666666-6666-6666-6666-666666666666') $$,
  '23001',
  null,
  'a third invitation to a duel is refused: outstanding invitations fill the cap'
);

-- ---------------------------------------------------------------------------
-- Group contests invite from the group
-- ---------------------------------------------------------------------------
select public.create_contest(
  p_kind => 'group', p_title => 'The Group Contest',
  p_metric => 'exercise_minutes', p_cadence => 'daily', p_target_value => 30,
  p_starts_at => now() + interval '1 day',
  p_ends_at => now() + interval '15 days',
  p_stake_amount_cents => 5000,
  p_charity_id => 'c0000001-0000-0000-0000-000000000001',
  p_timezone => 'America/New_York',
  p_group_id => '99999999-9999-9999-9999-999999999999',
  p_max_participants => 2::smallint);

-- Erin is a friend of alice but not in Run Club. Friendship is not a route into
-- a group contest, just as membership is not a route into a duel.
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Group Contest'),
       '66666666-6666-6666-6666-666666666666') $$,
  '42501',
  null,
  'a group contest invitation must go to a member of its group'
);

select is(
  public.invite_to_contest(
    (select id from public.contests where title = 'The Group Contest'),
    '33333333-3333-3333-3333-333333333333'),
  'invited'::public.participant_status,
  'a group co-member can be invited without being a friend'
);

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------
-- M1 recorded the tension and left it for M2: blocking does not eject either
-- party from a shared group (D17 withholds that power from everyone), so without
-- a check here a group contest would be a way to put two people who have blocked
-- each other into a mutual donation obligation. The check refuses the pairing;
-- it still removes nobody from anything.
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
insert into public.blocks (blocker_id, blocked_id) values
  ('44444444-4444-4444-4444-444444444444',
   '33333333-3333-3333-3333-333333333333');

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Group Contest'),
       '44444444-4444-4444-4444-444444444444') $$,
  '42501',
  null,
  'dave cannot be invited: he has blocked carol, who is already on the roster'
);

select is(
  (select count(*) from public.group_members
   where group_id = '99999999-9999-9999-9999-999999999999'
     and user_id in ('33333333-3333-3333-3333-333333333333',
                     '44444444-4444-4444-4444-444444444444')),
  2::bigint,
  'and the block still ejects neither of them from the group'
);

-- The check is symmetric. Reversing the direction changes nothing, because a
-- block that only worked one way would be routed around by having the other
-- person be the one already on the roster.
reset role;
delete from public.blocks
  where blocker_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
insert into public.blocks (blocker_id, blocked_id) values
  ('33333333-3333-3333-3333-333333333333',
   '44444444-4444-4444-4444-444444444444');

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'The Group Contest'),
       '44444444-4444-4444-4444-444444444444') $$,
  '42501',
  null,
  'and is refused with the block pointing the other way too'
);

reset role;
delete from public.blocks
  where blocker_id = '33333333-3333-3333-3333-333333333333';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

-- ---------------------------------------------------------------------------
-- Accepting
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
select throws_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Duel'),
       'c0000001-0000-0000-0000-000000000001', 'UTC') $$,
  'P0002',
  null,
  'a user with no invitation cannot accept one'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

select throws_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Duel'),
       'c0000001-0000-0000-0000-000000000001', 'Mars/Olympus_Mons') $$,
  '22023',
  null,
  'a timezone Postgres does not know is refused'
);

select throws_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Duel'),
       'c0000002-0000-0000-0000-000000000002', 'Europe/Lisbon') $$,
  '22023',
  null,
  'and a retired charity cannot be newly nominated'
);

select lives_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Duel'),
       'c0000001-0000-0000-0000-000000000001', 'Europe/Lisbon') $$,
  'bob accepts the duel'
);

select is(
  (select p.status from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'The Duel'
     and p.user_id = '22222222-2222-2222-2222-222222222222'),
  'accepted'::public.participant_status,
  'and is recorded as accepted'
);

select is(
  (select p.timezone from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'The Duel'
     and p.user_id = '22222222-2222-2222-2222-222222222222'),
  'Europe/Lisbon',
  'with his own timezone frozen, not the creator''s (D5)'
);

select ok(
  (select p.responded_at is not null from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'The Duel'
     and p.user_id = '22222222-2222-2222-2222-222222222222'),
  'and responded_at stamped by the trigger rather than by the caller'
);

select lives_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Duel'),
       'c0000001-0000-0000-0000-000000000001', 'Europe/Lisbon') $$,
  'accepting twice is not an error'
);

-- ---------------------------------------------------------------------------
-- The cap, at acceptance
-- ---------------------------------------------------------------------------
-- The Group Contest is capped at two, and alice plus carol fill it. Dave's
-- roster row below is inserted directly, which is the one thing the RPC will not
-- let a creator do — invitations count against the cap, so a third person could
-- never be invited to it. That is exactly the state a lost race would produce,
-- which is why acceptance re-checks the cap instead of trusting invitation to
-- have done it. What makes the real thing race-safe is the FOR UPDATE on the
-- contest row, and a single-transaction test cannot demonstrate that part.
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select public.accept_contest_invitation(
  (select id from public.contests where title = 'The Group Contest'),
  'c0000001-0000-0000-0000-000000000001', 'UTC');

reset role;
insert into public.contest_participants (contest_id, user_id, status) values
  ((select id from public.contests where title = 'The Group Contest'),
   '44444444-4444-4444-4444-444444444444', 'invited');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
select throws_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'The Group Contest'),
       'c0000001-0000-0000-0000-000000000001', 'UTC') $$,
  '23001',
  null,
  'acceptance is refused once the accepted count has reached the cap'
);

-- ---------------------------------------------------------------------------
-- Declining is terminal
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select public.create_contest(
  p_kind => 'duel', p_title => 'Declined Duel',
  p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
  p_starts_at => now() + interval '1 day',
  p_ends_at => now() + interval '8 days',
  p_stake_amount_cents => 2500,
  p_charity_id => 'c0000001-0000-0000-0000-000000000001',
  p_timezone => 'America/New_York');
select public.invite_to_contest(
  (select id from public.contests where title = 'Declined Duel'),
  '77777777-7777-7777-7777-777777777777');

select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777"}', true);
select lives_ok(
  $$ select public.decline_contest_invitation(
       (select id from public.contests where title = 'Declined Duel')) $$,
  'frank declines'
);

select lives_ok(
  $$ select public.decline_contest_invitation(
       (select id from public.contests where title = 'Declined Duel')) $$,
  'and declining twice is not an error'
);

select throws_ok(
  $$ select public.accept_contest_invitation(
       (select id from public.contests where title = 'Declined Duel'),
       'c0000001-0000-0000-0000-000000000001', 'UTC') $$,
  '23001',
  null,
  'a declined invitation cannot be accepted after the fact'
);

-- No re-invitation. The way to stop being asked again is a block, which the
-- other person can see they made; a resettable state machine would instead give
-- the creator an unlimited nag.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is(
  public.invite_to_contest(
    (select id from public.contests where title = 'Declined Duel'),
    '77777777-7777-7777-7777-777777777777'),
  'declined'::public.participant_status,
  're-inviting somebody who declined reports the refusal rather than resetting it'
);

-- A declined invitation buys no profile visibility either. Asserted on the
-- predicate directly, since the RLS path is already covered below.
select ok(
  not app.shares_contest('11111111-1111-1111-1111-111111111111',
                         '77777777-7777-7777-7777-777777777777'),
  'and buys no visibility: a declined roster row is not co-participation'
);

-- ---------------------------------------------------------------------------
-- Withdrawal, and its boundary
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select public.withdraw_from_contest(
       (select id from public.contests where title = 'The Duel')) $$,
  '23001',
  null,
  'the creator cancels a contest rather than withdrawing from it'
);

select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select lives_ok(
  $$ select public.withdraw_from_contest(
       (select id from public.contests where title = 'The Group Contest')) $$,
  'carol withdraws before the start'
);

select is(
  (select p.status from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'The Group Contest'
     and p.user_id = '33333333-3333-3333-3333-333333333333'),
  'withdrawn'::public.participant_status,
  'and the row records it rather than disappearing'
);

-- After the start this is a forfeit, which is a loss with a settlement attached
-- and therefore M7's business, not a withdrawal.
reset role;
insert into public.contests
  (id, kind, created_by, title, metric, cadence, target_value, status,
   starts_at, ends_at, stake_amount_cents, max_participants, activated_at)
values
  ('aaaaaaa5-0000-0000-0000-000000000005', 'duel',
   '11111111-1111-1111-1111-111111111111', 'Running Now',
   'steps', 'total', 50000, 'active',
   now() - interval '1 hour', now() + interval '6 days', 2500, 2,
   now() - interval '1 hour');
insert into public.contest_participants
  (contest_id, user_id, status, charity_id, timezone, responded_at)
values
  ('aaaaaaa5-0000-0000-0000-000000000005',
   '11111111-1111-1111-1111-111111111111', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now()),
  ('aaaaaaa5-0000-0000-0000-000000000005',
   '66666666-6666-6666-6666-666666666666', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'Europe/Lisbon', now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-6666-6666-6666-666666666666"}', true);
select throws_ok(
  $$ select public.withdraw_from_contest(
       'aaaaaaa5-0000-0000-0000-000000000005') $$,
  '23001',
  null,
  'withdrawal is refused once the contest is running: leaving then is a forfeit'
);

-- ---------------------------------------------------------------------------
-- The participant machine is an allow-list
-- ---------------------------------------------------------------------------
reset role;

select throws_ok(
  $$ update public.contest_participants set status = 'withdrawn'
     where contest_id = (select id from public.contests where title = 'Declined Duel')
       and user_id = '77777777-7777-7777-7777-777777777777' $$,
  '23001',
  null,
  'nothing leaves declined'
);

select throws_ok(
  $$ update public.contest_participants set status = 'declined'
     where contest_id = 'aaaaaaa5-0000-0000-0000-000000000005'
       and user_id = '66666666-6666-6666-6666-666666666666' $$,
  '23001',
  null,
  'and an accepted participant cannot retroactively decline'
);

select lives_ok(
  $$ update public.contest_participants set status = 'forfeited'
     where contest_id = 'aaaaaaa5-0000-0000-0000-000000000005'
       and user_id = '66666666-6666-6666-6666-666666666666' $$,
  'accepted to forfeited is legal, and is where M7 picks the machine up'
);

-- ---------------------------------------------------------------------------
-- A participant's own two terms freeze at the start, not at acceptance
-- ---------------------------------------------------------------------------
-- Before the start, changing your mind about a charity harms nobody. After it,
-- D5's concern is live: a movable day boundary lets somebody roll their day back
-- to reopen a day they had already lost, and a movable charity turns a
-- nomination into a bait-and-switch once the result is visible.
select lives_ok(
  $$ update public.contest_participants set timezone = 'Asia/Tokyo'
     where contest_id = (select id from public.contests where title = 'The Duel')
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  'a participant''s timezone can still change while the contest is open'
);

select throws_ok(
  $$ update public.contest_participants set timezone = 'Asia/Tokyo'
     where contest_id = 'aaaaaaa5-0000-0000-0000-000000000005'
       and user_id = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'but is frozen once the contest is running'
);

select throws_ok(
  $$ update public.contest_participants
     set charity_id = 'c0000002-0000-0000-0000-000000000002'
     where contest_id = 'aaaaaaa5-0000-0000-0000-000000000005'
       and user_id = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'and so is the charity, which closes a bait-and-switch once a result is visible'
);

-- ---------------------------------------------------------------------------
-- Co-participation is the third route to a profile
-- ---------------------------------------------------------------------------
-- M1 left a note that this is where it would be needed. The interesting case is
-- not a duel between strangers — a duel invitation requires a friendship — but a
-- duel whose friendship went away afterwards. Alice and erin share no group, so
-- once the friendship is gone, co-participation is the only route left.
delete from public.friendships
where user_a = '11111111-1111-1111-1111-111111111111'
  and user_b = '66666666-6666-6666-6666-666666666666';

select ok(
  not app.is_friend('11111111-1111-1111-1111-111111111111',
                    '66666666-6666-6666-6666-666666666666'),
  'alice and erin are no longer friends'
);
select ok(
  not app.shares_group('11111111-1111-1111-1111-111111111111',
                       '66666666-6666-6666-6666-666666666666'),
  'and share no group'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-6666-6666-6666-666666666666"}', true);
select is(
  (select count(*) from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'yet erin can still see her opponent, because the contest is still running'
);

-- And now the case the contest route is deliberately placed outside the block
-- check for. Alice blocks erin mid-contest. Under the friend and group routes a
-- block hides both profiles — but doing that here would replace a live opponent
-- with an unknown user in erin's app, which announces the block to exactly the
-- person D19 went out of its way not to tell. The pledge does not care how they
-- feel about each other.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
insert into public.blocks (blocker_id, blocked_id) values
  ('11111111-1111-1111-1111-111111111111',
   '66666666-6666-6666-6666-666666666666');

select set_config('request.jwt.claims',
  '{"sub":"66666666-6666-6666-6666-666666666666"}', true);
select is(
  (select count(*) from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'a block placed after the invitation does not blank out the opponent'
);

-- The block is still doing its work everywhere it can without leaking: no new
-- invitations, and no discovery.
select is(
  (select count(*) from public.find_profile_by_handle('alice')),
  0::bigint,
  'while still removing her from handle discovery'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select public.create_contest(
  p_kind => 'duel', p_title => 'Post Block Duel',
  p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
  p_starts_at => now() + interval '1 day',
  p_ends_at => now() + interval '8 days',
  p_stake_amount_cents => 2500,
  p_charity_id => 'c0000001-0000-0000-0000-000000000001',
  p_timezone => 'America/New_York');

select throws_ok(
  $$ select public.invite_to_contest(
       (select id from public.contests where title = 'Post Block Duel'),
       '66666666-6666-6666-6666-666666666666') $$,
  '42501',
  null,
  'and refusing a fresh invitation, the friendship having been severed by the block'
);

reset role;
select * from finish();
rollback;
