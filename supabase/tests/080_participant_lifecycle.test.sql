-- The participant state machine, activation, and the roster freeze.
--
-- The properties that matter, in rough order of how much damage getting them
-- wrong would do:
--
--   * once the window opens, nothing about the roster moves — which is what
--     makes blocking your opponent useless as an escape route
--   * a timezone is frozen at accept, so a day already lost cannot be reopened
--   * accepting means naming a charity, so every pledge has a visible destination
--   * a contest nobody joined voids itself rather than running with one person
--   * 'lapsed' means the system closed an invitation, and a client cannot forge it

begin;
select plan(37);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice, author of everything here
  ('22222222-2222-2222-2222-222222222222'),  -- bob
  ('33333333-3333-3333-3333-333333333333'),  -- carol, declines
  ('44444444-4444-4444-4444-444444444444'),  -- dave, accepts then withdraws
  ('55555555-5555-5555-5555-555555555555'),  -- erin
  ('66666666-6666-6666-6666-666666666666'),  -- frank, blocks while pending
  ('77777777-7777-7777-7777-777777777777');  -- grace, blocks while active

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol'),
  ('44444444-4444-4444-4444-444444444444', 'dave',  'Dave'),
  ('55555555-5555-5555-5555-555555555555', 'erin',  'Erin'),
  ('66666666-6666-6666-6666-666666666666', 'frank', 'Frank'),
  ('77777777-7777-7777-7777-777777777777', 'grace', 'Grace');

insert into public.friendships (user_a, user_b, requested_by, status)
select '11111111-1111-1111-1111-111111111111', p.id,
       '11111111-1111-1111-1111-111111111111', 'accepted'
from public.profiles p
where p.id <> '11111111-1111-1111-1111-111111111111';

insert into public.charities (id, name, ein, slug, is_active) values
  ('c0000001-0000-0000-0000-000000000001', 'Trail Fund',   '12-3456789', 'trail-fund',   true),
  ('c0000002-0000-0000-0000-000000000002', 'Retired Fund', '66-3456789', 'retired-fund', false),
  ('c0000003-0000-0000-0000-000000000003', 'River Fund',   '77-3456789', 'river-fund',   true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

-- Answering: bob, carol, and dave each take a different route out of 'invited'.
create temporary table t_answers as
select public.create_contest(
  'Answer Rules', 'steps', 'cumulative', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'America/New_York', 'c0000001-0000-0000-0000-000000000001', 4::smallint
) as id;

-- Nobody joins this one.
create temporary table t_quorum as
select public.create_contest(
  'Quorum Of One', 'steps', 'cumulative', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001', 2::smallint
) as id;

-- Reaches a quorum, with one invitation left unanswered at the bell.
create temporary table t_running as
select public.create_contest(
  'Lapse And Run', 'steps', 'cumulative', 10000, 2500,
  now() + interval '1 day', now() + interval '8 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001', 4::smallint
) as id;

-- Still a month out, so the activation sweep must leave it alone.
create temporary table t_future as
select public.create_contest(
  'Not Yet Due', 'steps', 'cumulative', 10000, 2500,
  now() + interval '30 days', now() + interval '40 days',
  'UTC', 'c0000001-0000-0000-0000-000000000001', 2::smallint
) as id;

reset role;

insert into public.contest_participants (contest_id, user_id, invited_by)
values
  ((select id from t_answers), '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_answers), '33333333-3333-3333-3333-333333333333',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_answers), '44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_running), '55555555-5555-5555-5555-555555555555',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_running), '77777777-7777-7777-7777-777777777777',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_running), '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111'),
  ((select id from t_future),  '66666666-6666-6666-6666-666666666666',
   '11111111-1111-1111-1111-111111111111');

-- ===========================================================================
-- Accepting
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- Accepting is agreeing to pledge money, so it cannot be done without naming
-- where that money would go. The constraint is one-directional: it demands both
-- fields of an accepted row and says nothing about the other states.
select throws_ok(
  $$ update public.contest_participants set status = 'accepted'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23514',
  null,
  'accepting without a timezone and a charity is refused'
);

select throws_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'Mars/Olympus',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  '22023',
  null,
  'and not with a timezone Postgres does not recognise'
);

select lives_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'Europe/London',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  'bob accepts, naming his zone and his charity'
);

select ok(
  (select accepted_at is not null from public.contest_participants
   where contest_id = (select id from t_answers)
     and user_id = '22222222-2222-2222-2222-222222222222'),
  'and the acceptance is stamped'
);

-- D5: a live timezone would let a participant walk their day boundary backwards
-- to reopen a day they had already lost, which defeats daily cadence outright.
select throws_ok(
  $$ update public.contest_participants set timezone = 'Pacific/Auckland'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23001',
  null,
  'the timezone is frozen at accept and cannot be moved afterwards'
);

-- The charity is a different matter: it is this participant's own nomination,
-- and changing where their winnings would go harms nobody.
select lives_ok(
  $$ update public.contest_participants
     set charity_id = 'c0000003-0000-0000-0000-000000000003'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  'but the charity may still be changed while the contest is pending'
);

select throws_ok(
  $$ update public.contest_participants
     set charity_id = 'c0000002-0000-0000-0000-000000000002'
     where contest_id = (select id from t_answers)
       and user_id = '22222222-2222-2222-2222-222222222222' $$,
  '22023',
  null,
  'though not to a charity that has been retired'
);

-- ===========================================================================
-- Declining, and the difference from lapsing
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);

-- 'lapsed' is the system's word for an invitation that went unanswered. If a
-- client could write it, an invitee could file their own refusal as silence and
-- 'declined' would stop meaning anything M7's reliability score can read.
select throws_ok(
  $$ update public.contest_participants set status = 'lapsed'
     where contest_id = (select id from t_answers)
       and user_id = '33333333-3333-3333-3333-333333333333' $$,
  '42501',
  null,
  'an invitee cannot file their own refusal as silence'
);

select lives_ok(
  $$ update public.contest_participants set status = 'declined'
     where contest_id = (select id from t_answers)
       and user_id = '33333333-3333-3333-3333-333333333333' $$,
  'carol declines'
);

select ok(
  (select accepted_at is null from public.contest_participants
   where contest_id = (select id from t_answers)
     and user_id = '33333333-3333-3333-3333-333333333333'),
  'and declining leaves no acceptance stamp behind'
);

select throws_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'UTC',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_answers)
       and user_id = '33333333-3333-3333-3333-333333333333' $$,
  '23001',
  null,
  'a decline is final; there is no route back to accepted'
);

-- ===========================================================================
-- Withdrawing before the window opens
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444"}', true);

update public.contest_participants
set status = 'accepted', timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = (select id from t_answers)
  and user_id = '44444444-4444-4444-4444-444444444444';

select lives_ok(
  $$ update public.contest_participants set status = 'withdrawn'
     where contest_id = (select id from t_answers)
       and user_id = '44444444-4444-4444-4444-444444444444' $$,
  'nothing is at stake before the window opens, so dave may still step out'
);

-- The terms he agreed to stay on the row. They are the record of what he
-- accepted, not live configuration.
select ok(
  (select timezone is not null and charity_id is not null
   from public.contest_participants
   where contest_id = (select id from t_answers)
     and user_id = '44444444-4444-4444-4444-444444444444'),
  'and what he had agreed to stays on the row'
);

select throws_ok(
  $$ update public.contest_participants
     set status = 'accepted', timezone = 'UTC',
         charity_id = 'c0000001-0000-0000-0000-000000000001'
     where contest_id = (select id from t_answers)
       and user_id = '44444444-4444-4444-4444-444444444444' $$,
  '23001',
  null,
  'but withdrawing is final too'
);

-- The author is enrolled from the first instant and cannot quietly leave. The
-- way out of a contest you wrote is to cancel it, which is a decision about the
-- whole contest rather than an exit from it.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ update public.contest_participants set status = 'withdrawn'
     where contest_id = (select id from t_answers)
       and user_id = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'the author of a contest cannot withdraw from it'
);

-- Answering on someone else's behalf is filtered by the policy rather than
-- raised, so the assertion is on the row.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
update public.contest_participants set status = 'declined'
where contest_id = (select id from t_answers)
  and user_id = '44444444-4444-4444-4444-444444444444';

reset role;
select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_answers)
     and user_id = '44444444-4444-4444-4444-444444444444'),
  'withdrawn',
  'and nobody can answer an invitation that is not theirs'
);

-- ===========================================================================
-- A block while the contest is still pending
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-6666-6666-6666-666666666666"}', true);

select is(
  (select count(*) from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'frank can see the author who invited him'
);

insert into public.blocks (blocker_id, blocked_id)
values ('66666666-6666-6666-6666-666666666666',
        '11111111-1111-1111-1111-111111111111');

-- Nothing has opened yet, so the block wins: the only routes to visibility were
-- the friendship it just severed and a shared group they do not have.
select is(
  (select count(*) from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  0::bigint,
  'and blocking her while the contest is only pending hides her again'
);

-- The invitation is not retracted by the block, though. It simply goes
-- unanswered, and will lapse.
reset role;
select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_future)
     and user_id = '66666666-6666-6666-6666-666666666666'),
  'invited',
  'the roster row survives the block rather than being retracted'
);

-- ===========================================================================
-- Activation
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}', true);
update public.contest_participants
set status = 'accepted', timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = (select id from t_running)
  and user_id = '55555555-5555-5555-5555-555555555555';

select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777"}', true);
update public.contest_participants
set status = 'accepted', timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = (select id from t_running)
  and user_id = '77777777-7777-7777-7777-777777777777';

reset role;

-- The clock is a parameter so the suite can drive it; cron calls this with no
-- arguments.
select ok(
  (select count(*) from app.activate_due_contests(now() + interval '2 days')) >= 3,
  'the sweep reports on every contest that had come due'
);

-- A contest is a comparison, and there is nothing to compare one person against.
select is(
  (select status::text from public.contests where id = (select id from t_quorum)),
  'cancelled',
  'a contest nobody joined voids itself rather than running with one participant'
);
select is(
  (select cancellation_reason::text from public.contests
   where id = (select id from t_quorum)),
  'insufficient_participants',
  'and says so, rather than looking like the author called it off'
);

select is(
  (select status::text from public.contests where id = (select id from t_running)),
  'active',
  'a contest with a quorum opens'
);
select ok(
  (select activated_at is not null from public.contests
   where id = (select id from t_running)),
  'and records when it did'
);

select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_running)
     and user_id = '22222222-2222-2222-2222-222222222222'),
  'lapsed',
  'the invitation nobody answered lapses at the bell'
);

select is(
  (select status::text from public.contests where id = (select id from t_future)),
  'pending',
  'and a contest that is not due yet is left alone'
);

-- ===========================================================================
-- The roster freeze, and why a block is not a way out
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777"}', true);

select throws_ok(
  $$ update public.contest_participants set status = 'withdrawn'
     where contest_id = (select id from t_running)
       and user_id = '77777777-7777-7777-7777-777777777777' $$,
  '23001',
  null,
  'once the window is open there is no way off the roster'
);

select throws_ok(
  $$ update public.contest_participants
     set charity_id = 'c0000003-0000-0000-0000-000000000003'
     where contest_id = (select id from t_running)
       and user_id = '77777777-7777-7777-7777-777777777777' $$,
  '23001',
  null,
  'and nothing else on the row moves either'
);

-- This is the one that matters. grace blocks the author mid-contest: the block
-- takes effect as a block — the friendship is severed — and changes nothing
-- about the contest. If it ejected her, or hid the counterparty she may owe a
-- donation to, then blocking would be the cheapest way to walk away from a
-- contest you are losing.
insert into public.blocks (blocker_id, blocked_id)
values ('77777777-7777-7777-7777-777777777777',
        '11111111-1111-1111-1111-111111111111');

select is(
  (select count(*) from public.profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'blocking a counterparty in a live contest does not hide them'
);

reset role;
select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '77777777-7777-7777-7777-777777777777'),
  0::bigint,
  'even though the block did sever the friendship, as blocks do'
);

select is(
  (select status::text from public.contest_participants
   where contest_id = (select id from t_running)
     and user_id = '77777777-7777-7777-7777-777777777777'),
  'accepted',
  'and she is still on the roster, still owing whatever the result says'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select throws_ok(
  $$ insert into public.contest_participants (contest_id, user_id, invited_by)
     values ((select id from t_running),
             '33333333-3333-3333-3333-333333333333',
             '11111111-1111-1111-1111-111111111111') $$,
  '23001',
  null,
  'and the author cannot add anyone to a contest already under way'
);

-- ===========================================================================
-- Privileges
-- ===========================================================================
reset role;
select ok(
  has_column_privilege('authenticated', 'public.contest_participants',
                       'status', 'update'),
  'a participant may write their own status, which is how answering works'
);
select ok(
  not has_column_privilege('authenticated', 'public.contest_participants',
                           'invited_by', 'update'),
  'but not who invited them'
);
select ok(
  not has_column_privilege('authenticated', 'public.contest_participants',
                           'accepted_at', 'update'),
  'nor when they accepted, which the trigger derives'
);

-- Unlike M1's predicates, this one is not called from any policy, so it can be
-- taken away from `authenticated` — and it must be. Postgres grants EXECUTE to
-- PUBLIC by default and the baseline migration gives `authenticated` USAGE on
-- the app schema, so left as created this security-definer function would let
-- any signed-in user open contests early or void them for want of a quorum.
select ok(
  not has_function_privilege('authenticated',
    'app.activate_due_contests(timestamptz)', 'execute'),
  'a client cannot run the activation sweep'
);
select ok(
  has_function_privilege('service_role',
    'app.activate_due_contests(timestamptz)', 'execute'),
  'only the role cron runs as can'
);

select * from finish();
rollback;
