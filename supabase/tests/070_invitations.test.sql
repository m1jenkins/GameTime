-- Invitations: how far a contest invitation can reach, and who may send one.
--
-- The property this file is really about: an invitation carries a money pledge,
-- so it must not reach anyone the social graph does not already let you reach.
-- M1 kept profiles non-enumerable precisely so that knowing a handle is not a
-- route to a stranger; an invitation sendable by handle would hand that back.

begin;
select plan(26);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice, the author
  ('22222222-2222-2222-2222-222222222222'),  -- bob, her friend
  ('33333333-3333-3333-3333-333333333333'),  -- carol, group co-member only
  ('44444444-4444-4444-4444-444444444444'),  -- dave, a stranger
  ('55555555-5555-5555-5555-555555555555'),  -- erin, blocked by alice
  ('66666666-6666-6666-6666-666666666666'),  -- frank, blocks alice
  ('77777777-7777-7777-7777-777777777777');  -- grace, another friend

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol'),
  ('44444444-4444-4444-4444-444444444444', 'dave',  'Dave'),
  ('55555555-5555-5555-5555-555555555555', 'erin',  'Erin'),
  ('66666666-6666-6666-6666-666666666666', 'frank', 'Frank'),
  ('77777777-7777-7777-7777-777777777777', 'grace', 'Grace');

-- alice is friends with bob, erin, frank, and grace. Not with carol or dave.
insert into public.friendships (user_a, user_b, requested_by, status) values
  ('11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111',
   '55555555-5555-5555-5555-555555555555',
   '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111',
   '66666666-6666-6666-6666-666666666666',
   '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111',
   '77777777-7777-7777-7777-777777777777',
   '11111111-1111-1111-1111-111111111111', 'accepted');

insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999999', 'Crew',
   '11111111-1111-1111-1111-111111111111');
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999',
   '33333333-3333-3333-3333-333333333333');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001', 'Trail Fund', '12-3456789', 'trail-fund');

-- The blocks. Directed, in opposite directions, so both sides of the check get
-- exercised: alice blocked erin, and frank blocked alice.
insert into public.blocks (blocker_id, blocked_id) values
  ('11111111-1111-1111-1111-111111111111',
   '55555555-5555-5555-5555-555555555555'),
  ('66666666-6666-6666-6666-666666666666',
   '11111111-1111-1111-1111-111111111111');

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'contest_participants', 'public.contest_participants exists');
select col_is_pk('public', 'contest_participants', array['contest_id', 'user_id'],
  'a person appears on a roster at most once, so re-inviting cannot duplicate');
select ok(
  (select relrowsecurity
   from pg_class where oid = 'public.contest_participants'::regclass),
  'row level security is enabled on contest_participants'
);

-- ---------------------------------------------------------------------------
-- Two contests: one unscoped, one scoped to the group
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

create temporary table t_open as
select public.create_contest(
  'Open Duel', 'steps', 'cumulative', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001', 2::smallint
) as id;

create temporary table t_crew as
select public.create_contest(
  'Crew Contest', 'steps', 'cumulative', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001',
  4::smallint, 'integrity_score', '99999999-9999-9999-9999-999999999999'
) as id;

-- ---------------------------------------------------------------------------
-- Reach
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111') $$,
  'the author may invite a friend'
);

select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_open)
     and user_id = '22222222-2222-2222-2222-222222222222'),
  'invited',
  'and the row lands as invited, not accepted'
);

-- dave is reachable by neither route. This is the assertion that keeps contest
-- invitations from becoming a channel to arbitrary users.
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '44444444-4444-4444-4444-444444444444',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'a stranger cannot be invited, however well known their handle'
);

-- carol is reachable only through the group, so only the scoped contest can
-- reach her. The group is the reach; it is not a general-purpose introduction.
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '33333333-3333-3333-3333-333333333333',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'a group co-member cannot be invited to a contest not scoped to that group'
);

select lives_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_crew),
             '33333333-3333-3333-3333-333333333333',
             '11111111-1111-1111-1111-111111111111') $$,
  'but may be invited to one that is'
);

-- ---------------------------------------------------------------------------
-- Blocks close the invite path in both directions
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_crew),
             '55555555-5555-5555-5555-555555555555',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'someone the author has blocked cannot be invited'
);

-- And the other direction, which the author cannot even observe: frank blocked
-- alice, and alice has no way to tell that from frank simply not answering.
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_crew),
             '66666666-6666-6666-6666-666666666666',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'someone who has blocked the author cannot be invited either'
);

-- ---------------------------------------------------------------------------
-- Who may invite, and as whom
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '11111111-1111-1111-1111-111111111111',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'the author cannot invite themselves; they are already on the roster'
);

-- A new participant joins as invited and accepts afterwards. Self-inserting as
-- accepted would be agreeing on someone else's behalf.
select throws_ok(
  $$ insert into public.contest_participants
       (contest_id, user_id, status, invited_by, timezone, charity_id)
     values ((select id from t_crew),
             '22222222-2222-2222-2222-222222222222', 'accepted',
             '11111111-1111-1111-1111-111111111111',
             'UTC', 'c0000001-0000-0000-0000-000000000001') $$,
  -- The trigger, not the policy: a BEFORE ROW trigger runs ahead of the RLS
  -- WITH CHECK, so the specific complaint wins over a generic 42501. That is
  -- the better error to surface, and it is asserted here so a later reordering
  -- of the triggers cannot quietly turn it back into "permission denied".
  '23001',
  null,
  'an invitation cannot be inserted already accepted'
);

-- bob is on the roster of t_open but did not author it. Unlike a group, where
-- flat membership means every member administers (D17), growing a contest is
-- the author's alone: it changes the odds for everyone who already agreed.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '44444444-4444-4444-4444-444444444444',
             '22222222-2222-2222-2222-222222222222') $$,
  '42501',
  null,
  'a participant who is not the author cannot invite anyone'
);

select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '44444444-4444-4444-4444-444444444444',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'and cannot forge the author as the inviter to get around that'
);

-- ---------------------------------------------------------------------------
-- What an invitee can see
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.contests where id = (select id from t_open)),
  1::bigint,
  'an invitee can read the contest, which they must in order to decide'
);

select is(
  (select count(*) from public.contest_participants
   where contest_id = (select id from t_open)),
  2::bigint,
  'and the whole roster, so they can see who else is in'
);

select is(
  (select count(*) from public.contest_participants
   where contest_id = (select id from t_crew)),
  0::bigint,
  'but nothing about a contest they are not on'
);

-- ---------------------------------------------------------------------------
-- The roster closes when the contest leaves pending
-- ---------------------------------------------------------------------------
reset role;
insert into public.contests
  (id, title, created_by, metric, cadence, target_value,
   stake_amount_cents, starts_at, ends_at, status)
values
  ('d0000001-0000-0000-0000-000000000001', 'Already Running',
   '11111111-1111-1111-1111-111111111111', 'steps', 'cumulative', 100, 1000,
   now() + interval '1 day', now() + interval '2 days', 'active'),
  ('d0000002-0000-0000-0000-000000000002', 'Called Off',
   '11111111-1111-1111-1111-111111111111', 'steps', 'cumulative', 100, 1000,
   now() + interval '1 day', now() + interval '2 days', 'pending');

update public.contests
set status = 'cancelled', cancellation_reason = 'creator_cancelled',
    cancelled_at = now()
where id = 'd0000002-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ('d0000001-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111') $$,
  '23001',
  null,
  'nobody can be added to a contest that has already opened'
);

select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ('d0000002-0000-0000-0000-000000000002',
             '22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111') $$,
  '23001',
  null,
  'or to one that was called off'
);

select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111') $$,
  '23505',
  null,
  'and re-inviting someone already on the roster collides on the key'
);

-- ---------------------------------------------------------------------------
-- Capacity: invitations are not capped, acceptances are
-- ---------------------------------------------------------------------------
-- t_open is a duel: two places, and the author holds one. Over-inviting is
-- allowed on purpose — a decline would otherwise shrink the contest permanently,
-- since nothing reclaims the slot. The places go to whoever answers first.
select lives_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_open),
             '77777777-7777-7777-7777-777777777777',
             '11111111-1111-1111-1111-111111111111') $$,
  'a duel may hold more invitations than it has places'
);

select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select lives_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'Europe/London',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_open)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  'the first invitee to answer takes the second place'
);

-- The ceiling is enforced on acceptance, under a lock on the contest row, so
-- this is the check that stops a duel becoming a three-way.
select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777"}', true);
select throws_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'UTC',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_open)
       and user_id = '77777777-7777-7777-7777-777777777777' $$,
  '23001',
  null,
  'and whoever answers next finds the contest full'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
reset role;
select ok(
  has_table_privilege('authenticated', 'public.contest_participants', 'insert'),
  'authenticated may INSERT, which is how an invitation is sent'
);
select ok(
  not has_table_privilege('authenticated', 'public.contest_participants', 'delete'),
  'authenticated cannot DELETE a roster row; withdrawal is a status, not an erasure'
);
select ok(
  not has_table_privilege('anon', 'public.contest_participants', 'select'),
  'anon cannot read rosters'
);

select * from finish();
rollback;
