-- blocks: one-sided visibility, and the reach of a block across the rest of the
-- social graph.
--
-- A block is only worth having if it cannot be routed around. The assertions
-- here are mostly about the routes: friendship, profile visibility, discovery,
-- and joining a group the other party is already in.

begin;
select plan(25);

-- Counts made after `reset role` run as superuser, so RLS is not narrowing them
-- and they would otherwise also see whatever seed.sql left in the database.
-- Those assertions are scoped to the fixture rows explicitly.

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
select has_table('public', 'blocks', 'public.blocks exists');
select col_is_pk('public', 'blocks', array['blocker_id', 'blocked_id'],
  'a block is keyed by the directed pair');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.blocks'::regclass),
  'row level security is enabled on blocks'
);
select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id) values (
       '11111111-1111-1111-1111-111111111111',
       '11111111-1111-1111-1111-111111111111') $$,
  '23514',
  null,
  'you cannot block yourself'
);
select ok(
  not has_table_privilege('authenticated', 'public.blocks', 'update'),
  'blocks cannot be updated; unblocking is a delete'
);
select ok(
  not has_table_privilege('anon', 'public.blocks', 'select'),
  'anon cannot select blocks'
);

-- Directed, so both directions can coexist and each is its own row.
insert into public.blocks (blocker_id, blocked_id) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.blocks),
  2::bigint,
  'blocks are directed, so a mutual block is two rows'
);
delete from public.blocks;

-- ---------------------------------------------------------------------------
-- Blocking severs an existing friendship
-- ---------------------------------------------------------------------------
insert into public.friendships (user_a, user_b, requested_by, status) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'accepted');

select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '22222222-2222-2222-2222-222222222222'),
  1::bigint,
  'alice and bob start out friends'
);

insert into public.blocks (blocker_id, blocked_id) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222');

select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '22222222-2222-2222-2222-222222222222'),
  0::bigint,
  'blocking severs the friendship immediately'
);

-- The reverse direction has to work identically, since the friendship row is
-- stored under a canonical ordering that does not track who blocked whom.
delete from public.blocks;
insert into public.friendships (user_a, user_b, requested_by, status) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'accepted');
insert into public.blocks (blocker_id, blocked_id) values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.friendships
   where user_a = '11111111-1111-1111-1111-111111111111'
     and user_b = '22222222-2222-2222-2222-222222222222'),
  0::bigint,
  'severing works whichever party blocks, despite the canonical ordering'
);
delete from public.blocks;

-- ---------------------------------------------------------------------------
-- One-sided visibility
-- ---------------------------------------------------------------------------
-- Being blocked must not be observable, or the block itself becomes a message.
insert into public.blocks (blocker_id, blocked_id) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is(
  (select count(*) from public.blocks),
  1::bigint,
  'the blocker can see the block they created'
);

select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select is(
  (select count(*) from public.blocks),
  0::bigint,
  'the blocked party cannot see that they were blocked'
);

-- Nor can they remove it.
delete from public.blocks;
reset role;
select is(
  (select count(*) from public.blocks),
  1::bigint,
  'the blocked party cannot delete the block'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id) values (
       '11111111-1111-1111-1111-111111111111',
       '33333333-3333-3333-3333-333333333333') $$,
  '42501',
  null,
  'nobody can create a block on somebody else''s behalf'
);

-- Unblocking is available to the blocker.
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select lives_ok(
  $$ delete from public.blocks $$,
  'the blocker can unblock'
);
reset role;
select is(
  (select count(*) from public.blocks),
  0::bigint,
  'and the block is gone'
);

-- ---------------------------------------------------------------------------
-- A block hides profiles that were previously visible
-- ---------------------------------------------------------------------------
-- Route in via a shared group rather than friendship, so this is not just
-- re-testing the severing trigger: the friendship is gone either way, but group
-- co-membership survives a block and visibility must still be revoked.
insert into public.groups (id, name, created_by) values (
  '99999999-9999-9999-9999-999999999999',
  'Shared Crew',
  '11111111-1111-1111-1111-111111111111');
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is(
  (select count(*) from public.profiles),
  2::bigint,
  'alice sees bob through their shared group'
);

reset role;
insert into public.blocks (blocker_id, blocked_id) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'after blocking, alice no longer sees bob despite the shared group'
);

-- Symmetric: the blocked party loses visibility too, without being told why.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'and bob no longer sees alice either'
);

-- ---------------------------------------------------------------------------
-- A block removes the pair from discovery
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select * from public.find_profile_by_handle('alice') $$,
  'a blocked user cannot resolve the blocker''s handle'
);

select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
select is_empty(
  $$ select * from public.find_profile_by_handle('bob') $$,
  'and the blocker cannot resolve theirs'
);

select is(
  (select count(*) from public.find_profile_by_handle('carol')),
  1::bigint,
  'discovery of unrelated users is unaffected'
);

-- ---------------------------------------------------------------------------
-- A block cannot be routed around by joining a group
-- ---------------------------------------------------------------------------
reset role;
delete from public.blocks;
delete from public.group_members
  where user_id = '22222222-2222-2222-2222-222222222222';

-- carol blocks bob, then joins a group. bob is already in it.
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222');
insert into public.blocks (blocker_id, blocked_id) values (
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222');

create temporary table code_holder as
  select join_code::text as code from public.groups
  where id = '99999999-9999-9999-9999-999999999999';
grant select on code_holder to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select throws_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  '42501',
  null,
  'you cannot join a group containing somebody you blocked'
);

-- And the same in the other direction: bob, who was blocked, must not be able
-- to join a group carol is in either.
reset role;
delete from public.blocks;
delete from public.group_members
  where user_id = '22222222-2222-2222-2222-222222222222';
insert into public.group_members (group_id, user_id) values
  ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333');
insert into public.blocks (blocker_id, blocked_id) values (
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select throws_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  '42501',
  null,
  'and cannot join a group containing somebody who blocked you'
);

-- Note the refusal above is 42501, distinct from the P0002 a wrong code gives.
-- That is deliberate: the caller already holds a valid code, so the only thing
-- the distinction reveals is that somebody in their own block list is present,
-- which is exactly what they need to know to understand the refusal. The oracle
-- the RPC does close is malformed-versus-unused code, which share P0002.
reset role;
delete from public.blocks;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select lives_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  'unblocking restores the ability to join'
);

reset role;
select * from finish();
rollback;
