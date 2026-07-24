-- friendships: the pair invariant and the request/accept state machine.
--
-- The two properties worth the most here:
--   * exactly one row per pair, whichever order the two requests arrive in
--   * only the recipient can accept, and accepted never walks back to pending

begin;
select plan(30);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice
  ('22222222-2222-2222-2222-222222222222'),  -- bob
  ('33333333-3333-3333-3333-333333333333');  -- carol

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol');

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'friendships', 'public.friendships exists');
select col_is_pk('public', 'friendships', array['user_a', 'user_b'],
  'the pair is the primary key');
select has_type('public', 'friendship_status', 'friendship_status enum exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.friendships'::regclass),
  'row level security is enabled on friendships'
);
select has_index('public', 'friendships', 'friendships_user_b_idx',
  'user_b is indexed for the reverse lookup');

-- ---------------------------------------------------------------------------
-- The pair invariant
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '22222222-2222-2222-2222-222222222222',
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222') $$,
  '23514',
  null,
  'a non-canonically-ordered pair is rejected'
);

select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '11111111-1111-1111-1111-111111111111',
       '11111111-1111-1111-1111-111111111111') $$,
  '23514',
  null,
  'you cannot befriend yourself: user_a < user_b excludes equality'
);

select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '33333333-3333-3333-3333-333333333333') $$,
  '23514',
  null,
  'a third party cannot be recorded as the requester'
);

insert into public.friendships (user_a, user_b, requested_by) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111');

-- Canonical ordering plus the primary key is what makes the duplicate
-- impossible. Without the ordering constraint this second row would be a
-- distinct, legal row and the pair would have two friendships.
select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '22222222-2222-2222-2222-222222222222') $$,
  '23505',
  null,
  'a crossing request from the other party collides instead of duplicating'
);

-- ---------------------------------------------------------------------------
-- accepted_at is derived, never supplied
-- ---------------------------------------------------------------------------
select is(
  (select accepted_at from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  null,
  'a pending friendship has no accepted_at'
);

update public.friendships set status = 'accepted'
  where user_a = '11111111-1111-1111-1111-111111111111';

select isnt(
  (select accepted_at from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  null,
  'accepting stamps accepted_at without the caller setting it'
);

update public.friendships set status = 'pending'
  where user_a = '11111111-1111-1111-1111-111111111111';

select is(
  (select accepted_at from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  null,
  'reverting to pending clears accepted_at, so the check constraint holds'
);

-- The trigger derives accepted_at, so a client-supplied value cannot desync it
-- from status. Asserted by supplying a deliberately wrong one.
update public.friendships
  set status = 'pending', accepted_at = now()
  where user_a = '11111111-1111-1111-1111-111111111111';
select is(
  (select accepted_at from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  null,
  'a client-supplied accepted_at on a pending row is discarded'
);

-- ---------------------------------------------------------------------------
-- Immutable columns
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.friendships
     set requested_by = '22222222-2222-2222-2222-222222222222'
     where user_a = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'requested_by is immutable, so nobody can reassign who asked'
);

select throws_ok(
  $$ update public.friendships
     set user_b = '33333333-3333-3333-3333-333333333333'
     where user_a = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'the pair itself is immutable'
);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('anon', 'public.friendships', 'select'),
  'anon cannot select friendships'
);
select ok(
  has_table_privilege('authenticated', 'public.friendships', 'delete'),
  'authenticated may delete friendships, which is how declining works'
);

-- ---------------------------------------------------------------------------
-- RLS: the state machine
-- ---------------------------------------------------------------------------
delete from public.friendships;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select lives_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '11111111-1111-1111-1111-111111111111') $$,
  'alice can open a request to bob'
);

select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '22222222-2222-2222-2222-222222222222',
       '33333333-3333-3333-3333-333333333333',
       '22222222-2222-2222-2222-222222222222') $$,
  '42501',
  null,
  'alice cannot fabricate a request between two other people'
);

select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '33333333-3333-3333-3333-333333333333',
       '33333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'alice cannot forge a request as if carol had sent it'
);

-- The whole point of requested_by: an inbound request must not be
-- self-acceptable, or a request is just a unilateral friendship.
update public.friendships set status = 'accepted'
  where user_a = '11111111-1111-1111-1111-111111111111';
reset role;
select is(
  (select status::text from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  'pending',
  'the requester cannot accept her own request'
);

-- A request the recipient has not seen is still visible to them, which is what
-- makes an inbox possible.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

select is(
  (select count(*) from public.friendships),
  1::bigint,
  'bob sees the inbound request'
);

select lives_ok(
  $$ update public.friendships set status = 'accepted'
     where user_a = '11111111-1111-1111-1111-111111111111' $$,
  'the recipient can accept'
);

reset role;
select is(
  (select status::text from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  'accepted',
  'acceptance persisted'
);

-- Once accepted, the row is terminal: the only way out is deletion. Walking it
-- back to pending would let either party reset the relationship silently.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

update public.friendships set status = 'pending'
  where user_a = '11111111-1111-1111-1111-111111111111';
reset role;
select is(
  (select status::text from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'),
  'accepted',
  'an accepted friendship cannot be reverted to pending'
);

-- A stranger sees nothing and can change nothing.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);

select is(
  (select count(*) from public.friendships),
  0::bigint,
  'carol cannot see a friendship she is not party to'
);

delete from public.friendships;
reset role;
select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '22222222-2222-2222-2222-222222222222'),
  1::bigint,
  'carol cannot delete somebody else''s friendship'
);

-- Either party may unfriend.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
delete from public.friendships;
reset role;
select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '22222222-2222-2222-2222-222222222222'),
  0::bigint,
  'either party can unfriend'
);

-- ---------------------------------------------------------------------------
-- Blocks gate new requests
-- ---------------------------------------------------------------------------
insert into public.blocks (blocker_id, blocked_id) values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

-- alice does not know she is blocked; the insert simply fails the policy.
select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'a blocked user cannot send a request to whoever blocked them'
);

reset role;
delete from public.blocks;

insert into public.blocks (blocker_id, blocked_id) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ insert into public.friendships (user_a, user_b, requested_by) values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'and cannot send one to somebody they have blocked themselves'
);

reset role;
select * from finish();
rollback;
