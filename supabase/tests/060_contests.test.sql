-- contests: the terms, and the lifecycle they live inside.
--
-- The properties that matter:
--   * a contest never exists without its creator on the roster
--   * terms stop being editable the moment somebody else has agreed to them,
--     and that is enforced twice — a narrow policy for clients, a trigger for
--     everybody else
--   * the status machine is an allow-list, so a state is reachable only by an
--     edge somebody wrote down
--   * a contest is never deleted. Cancelling is a status, because the row is
--     the record that people agreed to donate
--
-- A note on time. now() is fixed for the whole transaction, so a contest
-- created through public.create_contest() — which insists on a future start —
-- can never come due inside the same test. Fixtures that need to be *already*
-- due are therefore inserted directly as superuser. That is simulating elapsed
-- time, not working around a rule: create_contest's future-start check is
-- asserted on its own further down.

begin;
select plan(71);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice, creator throughout
  ('22222222-2222-2222-2222-222222222222'),  -- bob, alice's friend
  ('33333333-3333-3333-3333-333333333333'),  -- carol, group co-member only
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
   '11111111-1111-1111-1111-111111111111',
   'accepted');

insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999999', 'Run Club',
   '11111111-1111-1111-1111-111111111111');
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222'),
  ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333');

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
select has_table('public', 'contests', 'public.contests exists');
select col_is_pk('public', 'contests', 'id', 'contests is keyed by a surrogate id');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.contests'::regclass),
  'row level security is enabled on contests'
);

-- The lifecycle is declared whole in M2 even though M7 walks the second half.
-- A later milestone adding a state would be changing the machine, not extending
-- it, so the label set is pinned here.
select enum_has_labels(
  'public', 'contest_status',
  array['open', 'active', 'finalizing', 'settled', 'cancelled', 'voided'],
  'the contest lifecycle is declared whole, M7''s states included'
);
select enum_has_labels(
  'public', 'participant_status',
  array['invited', 'accepted', 'declined', 'withdrawn', 'lapsed', 'forfeited'],
  'and so is the participant lifecycle'
);

-- Shared with M3's metric_snapshots so the terms and the evidence cannot
-- disagree about what was being measured.
select has_type('public', 'metric_kind', 'metric_kind exists for M3 to reuse');

-- ---------------------------------------------------------------------------
-- Terms constraints
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Sprint',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '1 day 1 hour',
             2500, 2) $$,
  '23514',
  null,
  'a window shorter than a day is refused: nothing can be measured in it'
);

select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Forever',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '400 days',
             2500, 2) $$,
  '23514',
  null,
  'and a window longer than a year is refused: a forgotten pledge is not collectable'
);

select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Pennies',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '8 days',
             50, 2) $$,
  '23514',
  null,
  'a stake below the floor is refused'
);

-- The ceiling matters more than it looks: a group of 20 turns one creator's
-- mistyped stake into 19 donation obligations (D4).
select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Fortune',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '8 days',
             500000, 2) $$,
  '23514',
  null,
  'and a stake above the ceiling is refused as a typo guard'
);

select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Zero',
             'steps', 'total', 0,
             now() + interval '1 day', now() + interval '8 days',
             2500, 2) $$,
  '23514',
  null,
  'a target of zero is refused'
);

select throws_ok(
  $$ insert into public.contests
       (kind, group_id, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '99999999-9999-9999-9999-999999999999',
             '11111111-1111-1111-1111-111111111111', 'Grouped Duel',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '8 days',
             2500, 2) $$,
  '23514',
  null,
  'a duel is not attached to a group'
);

select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Crowded Duel',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '8 days',
             2500, 3) $$,
  '23514',
  null,
  'a duel is exactly two people'
);

select throws_ok(
  $$ insert into public.contests
       (kind, group_id, created_by, title, metric, cadence, target_value,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('group', '99999999-9999-9999-9999-999999999999',
             '11111111-1111-1111-1111-111111111111', 'Huge',
             'steps', 'total', 1000,
             now() + interval '1 day', now() + interval '8 days',
             2500, 50) $$,
  '23514',
  null,
  'group size is capped, because n participants create n-1 settlements'
);

-- "First to reach the target" has no meaning when the target resets every day,
-- so the incoherent pairing never becomes a row for M4 to interpret.
select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value, tie_break,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Incoherent',
             'steps', 'daily', 10000, 'earliest_to_target',
             now() + interval '1 day', now() + interval '8 days',
             2500, 2) $$,
  '23514',
  null,
  'earliest_to_target cannot be paired with a daily cadence'
);

select throws_ok(
  $$ insert into public.contests
       (kind, created_by, title, metric, cadence, target_value, stake_currency,
        starts_at, ends_at, stake_amount_cents, max_participants)
     values ('duel', '11111111-1111-1111-1111-111111111111', 'Euros',
             'steps', 'total', 1000, 'EUR',
             now() + interval '1 day', now() + interval '8 days',
             2500, 2) $$,
  '23514',
  null,
  'v1 is single-currency, and widening it is a constraint change not a backfill'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('authenticated', 'public.contests', 'insert'),
  'authenticated cannot INSERT a contest; create_contest() owns that'
);
select ok(
  not has_table_privilege('authenticated', 'public.contests', 'delete'),
  'authenticated cannot DELETE a contest; the row is the record of the agreement'
);
select ok(
  has_column_privilege('authenticated', 'public.contests', 'title', 'update'),
  'a creator may revise the title while the offer stands'
);
select ok(
  not has_column_privilege('authenticated', 'public.contests', 'status', 'update'),
  'but cannot write a status: every transition is a function'
);
select ok(
  not has_column_privilege('authenticated', 'public.contests', 'kind', 'update'),
  'and cannot turn a duel into a group contest, which would change the settlement count'
);
select ok(
  not has_column_privilege('authenticated', 'public.contests', 'created_by', 'update'),
  'and cannot claim authorship of somebody else''s contest'
);
select ok(
  not has_table_privilege('anon', 'public.contests', 'select'),
  'anon cannot read contests'
);
select ok(
  not has_function_privilege('anon', 'public.create_contest(public.contest_kind, text, '
    'public.metric_kind, public.contest_cadence, numeric, timestamptz, timestamptz, '
    'integer, uuid, text, uuid, public.tie_break_rule, smallint)', 'execute'),
  'anon cannot execute create_contest'
);
select ok(
  not has_function_privilege('authenticated', 'app.activate_due_contests()', 'execute'),
  'and no client can run the activation sweep: it acts on contests nobody has a claim to'
);

-- ---------------------------------------------------------------------------
-- create_contest
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}', true);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Premature',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'UTC') $$,
  '42501',
  null,
  'a user with no profile cannot create a contest'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Backdated',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() - interval '1 hour',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'UTC') $$,
  '22023',
  null,
  'a contest must start in the future, which cannot be a CHECK because now() is not immutable'
);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Grouped Duel',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'UTC',
       p_group_id => '99999999-9999-9999-9999-999999999999') $$,
  '22023',
  null,
  'a duel cannot name a group'
);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'group', p_title => 'Groupless',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'UTC') $$,
  '22023',
  null,
  'a group contest requires a group'
);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Bad Charity',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000009-0000-0000-0000-000000000009',
       p_timezone => 'UTC') $$,
  '22023',
  null,
  'an unknown charity is refused'
);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Retired Charity',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000002-0000-0000-0000-000000000002',
       p_timezone => 'UTC') $$,
  '22023',
  null,
  'and a retired one cannot be newly nominated'
);

select throws_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Bad Zone',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'Mars/Olympus_Mons') $$,
  '22023',
  null,
  'and a timezone Postgres does not know is refused, reusing M1''s validator'
);

-- Carol is in the group; dave is not. A group contest is among the group.
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
select throws_ok(
  $$ select public.create_contest(
       p_kind => 'group', p_title => 'Gatecrash',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'UTC',
       p_group_id => '99999999-9999-9999-9999-999999999999') $$,
  '42501',
  null,
  'a non-member cannot start a contest in that group'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select lives_ok(
  $$ select public.create_contest(
       p_kind => 'duel', p_title => 'Step Duel',
       p_metric => 'steps', p_cadence => 'total', p_target_value => 70000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '8 days',
       p_stake_amount_cents => 2500,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'America/New_York') $$,
  'alice creates a duel'
);

select is(
  (select status from public.contests where title = 'Step Duel'),
  'open'::public.contest_status,
  'a new contest opens'
);

-- The creator's enrolment is in the same transaction as the terms, so a contest
-- with an empty roster is not a state any reader can observe.
select is(
  (select count(*) from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'Step Duel'),
  1::bigint,
  'and the creator is on the roster immediately'
);

select is(
  (select p.status from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'Step Duel'),
  'accepted'::public.participant_status,
  'as an accepted participant, because they wrote the terms'
);

select is(
  (select p.timezone from public.contest_participants p
   join public.contests c on c.id = p.contest_id
   where c.title = 'Step Duel'),
  'America/New_York',
  'with their timezone frozen at enrolment (D5)'
);

select is(
  (select max_participants from public.contests where title = 'Step Duel'),
  2::smallint,
  'a duel''s cap is forced to two regardless of what was asked for'
);

select lives_ok(
  $$ select public.create_contest(
       p_kind => 'group', p_title => 'Group Steps',
       p_metric => 'steps', p_cadence => 'daily', p_target_value => 10000,
       p_starts_at => now() + interval '1 day',
       p_ends_at => now() + interval '15 days',
       p_stake_amount_cents => 5000,
       p_charity_id => 'c0000001-0000-0000-0000-000000000001',
       p_timezone => 'America/New_York',
       p_group_id => '99999999-9999-9999-9999-999999999999') $$,
  'and a group contest in a group she belongs to'
);

select is(
  (select max_participants from public.contests where title = 'Group Steps'),
  20::smallint,
  'an unspecified group cap defaults to the schema ceiling'
);

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.contests
   where title in ('Step Duel', 'Group Steps')),
  2::bigint,
  'a participant sees their own contests'
);

select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);
select is(
  (select count(*) from public.contests
   where title in ('Step Duel', 'Group Steps')),
  0::bigint,
  'and a non-participant sees neither, not even to learn they exist'
);

-- Carol is a member of Run Club but was not invited to Group Steps. Group
-- membership is not a route to seeing a contest: the people with something at
-- stake see it, and the rest of the group is not told it happened.
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select is(
  (select count(*) from public.contests where title = 'Group Steps'),
  0::bigint,
  'a group co-member who was not invited cannot see the group contest'
);

-- ---------------------------------------------------------------------------
-- Terms editing, and the freeze
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select lives_ok(
  $$ update public.contests set title = 'Step Duel v2'
     where title = 'Step Duel' $$,
  'the creator may revise terms while nobody else has accepted'
);

select throws_ok(
  $$ update public.contests set status = 'active'
     where title = 'Step Duel v2' $$,
  '42501',
  null,
  'but cannot write a status, however plausible the value'
);

select throws_ok(
  $$ update public.contests
     set starts_at = now() - interval '1 hour'
     where title = 'Step Duel v2' $$,
  '22023',
  null,
  'and cannot backdate the start of an open contest into the past'
);

select throws_ok(
  $$ update public.contests set max_participants = 1
     where title = 'Group Steps' $$,
  '23514',
  null,
  'the cap cannot go below the schema floor of two'
);

-- Three on the Group Steps roster: alice accepted at creation, bob and carol
-- invited. Invitations count against the cap, so shrinking it under the roster
-- would leave an invitee able to be asked but never to accept.
select public.invite_to_contest(
  (select id from public.contests where title = 'Group Steps'),
  '22222222-2222-2222-2222-222222222222');
select public.invite_to_contest(
  (select id from public.contests where title = 'Group Steps'),
  '33333333-3333-3333-3333-333333333333');

select throws_ok(
  $$ update public.contests set max_participants = 2
     where title = 'Group Steps' $$,
  '22023',
  null,
  'nor below the roster already assembled, which would strand an invitation'
);

select lives_ok(
  $$ update public.contests set max_participants = 4
     where title = 'Group Steps' $$,
  'but may still be tightened to something the roster fits inside'
);

-- Bob is outside the update policy, so the row is filtered from his statement
-- rather than rejected by it. Nothing raises, and the assertion has to be on the
-- outcome — the same shape as a member failing to eject another member in M1.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
update public.contests set title = 'Hijacked' where title = 'Step Duel v2';
reset role;
select is(
  (select count(*) from public.contests where title = 'Hijacked'),
  0::bigint,
  'a non-creator revising terms is filtered out by the policy rather than errored'
);
set local role authenticated;

-- Now bob accepts. From this instant the terms are what he agreed to.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select public.invite_to_contest(
  (select id from public.contests where title = 'Step Duel v2'),
  '22222222-2222-2222-2222-222222222222');

select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select public.accept_contest_invitation(
  (select id from public.contests where title = 'Step Duel v2'),
  'c0000001-0000-0000-0000-000000000001',
  'Europe/Lisbon');

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ update public.contests set target_value = 10
     where title = 'Step Duel v2' $$,
  '23001',
  null,
  'once another participant has accepted, the terms are frozen'
);

-- Two layers, failing differently on purpose: the client above was inside its
-- policy and stopped by the trigger; a privileged writer bypassing the policy
-- entirely is stopped by the same trigger.
reset role;
select throws_ok(
  $$ update public.contests set target_value = 10
     where title = 'Step Duel v2' $$,
  '23001',
  null,
  'and frozen even for a writer holding every privilege'
);

-- ---------------------------------------------------------------------------
-- The status machine is an allow-list
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.contests set status = 'settled'
     where title = 'Step Duel v2' $$,
  '23001',
  null,
  'open cannot jump straight to settled'
);

select throws_ok(
  $$ update public.contests set status = 'voided'
     where title = 'Step Duel v2' $$,
  '23001',
  null,
  'nor to voided, which is only reachable from a contest that actually ran'
);

select lives_ok(
  $$ update public.contests set status = 'active'
     where title = 'Step Duel v2' $$,
  'open to active is legal'
);

select ok(
  (select activated_at is not null from public.contests
   where title = 'Step Duel v2'),
  'and activation stamps activated_at rather than trusting the caller for it'
);

select throws_ok(
  $$ update public.contests set status = 'cancelled'
     where title = 'Step Duel v2' $$,
  '23001',
  null,
  'an active contest cannot be cancelled: there are stakes on the table'
);

select lives_ok(
  $$ update public.contests set status = 'finalizing'
     where title = 'Step Duel v2' $$,
  'active to finalizing is legal, and is where M7 picks the machine up'
);

-- ---------------------------------------------------------------------------
-- cancel_contest
-- ---------------------------------------------------------------------------
insert into public.contests
  (id, kind, created_by, title, metric, cadence, target_value,
   starts_at, ends_at, stake_amount_cents, max_participants)
values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'duel',
   '11111111-1111-1111-1111-111111111111', 'To Cancel',
   'steps', 'total', 50000,
   now() + interval '2 days', now() + interval '9 days', 2500, 2);
insert into public.contest_participants
  (contest_id, user_id, status, charity_id, timezone, responded_at)
values
  ('aaaaaaa1-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now());
insert into public.contest_participants (contest_id, user_id, status) values
  ('aaaaaaa1-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'invited');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ select public.cancel_contest('aaaaaaa1-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'only the creator can cancel a contest'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select lives_ok(
  $$ select public.cancel_contest('aaaaaaa1-0000-0000-0000-000000000001') $$,
  'the creator cancels it'
);

select is(
  (select status from public.contests
   where id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  'cancelled'::public.contest_status,
  'and the contest is cancelled rather than deleted'
);

-- 'lapsed', not 'declined': bob never said no. The distinction is visible in
-- the data, because a lapsed row never chose a charity or a timezone.
select is(
  (select status from public.contest_participants
   where contest_id = 'aaaaaaa1-0000-0000-0000-000000000001'
     and user_id = '22222222-2222-2222-2222-222222222222'),
  'lapsed'::public.participant_status,
  'the unanswered invitation lapses rather than being recorded as a refusal'
);

select lives_ok(
  $$ select public.cancel_contest('aaaaaaa1-0000-0000-0000-000000000001') $$,
  'cancelling twice is not an error'
);

select throws_ok(
  $$ delete from public.contests
     where id = 'aaaaaaa1-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'and a cancelled contest still cannot be deleted by a client'
);

-- ---------------------------------------------------------------------------
-- The activation sweep
-- ---------------------------------------------------------------------------
-- Inserted directly with a start already behind us, because now() cannot move
-- inside this transaction. Three fixtures: one that should run, one that has
-- nobody to run against, and one that is not due yet.
reset role;

insert into public.contests
  (id, kind, created_by, title, metric, cadence, target_value,
   starts_at, ends_at, stake_amount_cents, max_participants)
values
  ('aaaaaaa2-0000-0000-0000-000000000002', 'duel',
   '11111111-1111-1111-1111-111111111111', 'Due And Ready',
   'steps', 'total', 50000,
   now() - interval '1 hour', now() + interval '6 days', 2500, 2),
  ('aaaaaaa3-0000-0000-0000-000000000003', 'duel',
   '11111111-1111-1111-1111-111111111111', 'Due And Lonely',
   'steps', 'total', 50000,
   now() - interval '1 hour', now() + interval '6 days', 2500, 2),
  ('aaaaaaa4-0000-0000-0000-000000000004', 'duel',
   '11111111-1111-1111-1111-111111111111', 'Not Due Yet',
   'steps', 'total', 50000,
   now() + interval '3 days', now() + interval '10 days', 2500, 2);

insert into public.contest_participants
  (contest_id, user_id, status, charity_id, timezone, responded_at)
values
  ('aaaaaaa2-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now()),
  ('aaaaaaa2-0000-0000-0000-000000000002',
   '22222222-2222-2222-2222-222222222222', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now()),
  ('aaaaaaa3-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now()),
  ('aaaaaaa4-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111', 'accepted',
   'c0000001-0000-0000-0000-000000000001', 'UTC', now());

-- Carol's invitation to the contest that is about to start and never answered.
insert into public.contest_participants (contest_id, user_id, status) values
  ('aaaaaaa2-0000-0000-0000-000000000002',
   '33333333-3333-3333-3333-333333333333', 'invited');

-- Captured once: the sweep is not idempotent by design, since it moves state.
create temporary table sweep as select * from app.activate_due_contests();

select is(
  (select new_status from sweep
   where contest_id = 'aaaaaaa2-0000-0000-0000-000000000002'),
  'active'::public.contest_status,
  'a due contest with two acceptances activates'
);

select ok(
  (select activated_at is not null from public.contests
   where id = 'aaaaaaa2-0000-0000-0000-000000000002'),
  'and is stamped with the moment it started'
);

select is(
  (select status from public.contest_participants
   where contest_id = 'aaaaaaa2-0000-0000-0000-000000000002'
     and user_id = '33333333-3333-3333-3333-333333333333'),
  'lapsed'::public.participant_status,
  'an invitation still unanswered at the start lapses'
);

-- One acceptance is not a contest. Cancelling is the honest outcome: the
-- alternative is somebody winning a donation by default because nobody showed.
select is(
  (select new_status from sweep
   where contest_id = 'aaaaaaa3-0000-0000-0000-000000000003'),
  'cancelled'::public.contest_status,
  'a due contest with only its creator is cancelled, not won by default'
);

select is(
  (select count(*) from sweep
   where contest_id = 'aaaaaaa4-0000-0000-0000-000000000004'),
  0::bigint,
  'and a contest that has not come due is left alone'
);

select is(
  (select status from public.contests
   where id = 'aaaaaaa4-0000-0000-0000-000000000004'),
  'open'::public.contest_status,
  'still open, waiting for its start'
);

select * from finish();
rollback;
