-- groups and group_members: flat membership, join-by-code, and the lifecycle
-- rules that follow from having no owner.
--
-- The properties that matter:
--   * a group is never memberless, and disappears when the last member leaves
--   * membership is only ever self-service: you join with a code, you leave
--   * nobody can remove anybody else, because nobody holds a role that would

begin;
select plan(42);

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
select has_table('public', 'groups', 'public.groups exists');
select has_table('public', 'group_members', 'public.group_members exists');
select col_is_pk('public', 'group_members', array['group_id', 'user_id'],
  'membership is keyed by the pair, so it cannot be duplicated');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.groups'::regclass),
  'row level security is enabled on groups'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.group_members'::regclass),
  'row level security is enabled on group_members'
);

-- D81 retains created_by as pseudonymous history: the durable actor row and the
-- group must both survive authentication deletion.
select ok(
  (select confdeltype = 'r'  -- 'r' = RESTRICT
   from pg_constraint
   where conrelid = 'public.groups'::regclass
     and confrelid = 'public.profiles'::regclass),
  'created_by retains the durable founder rather than nulling or cascading'
);

-- ---------------------------------------------------------------------------
-- Join codes
-- ---------------------------------------------------------------------------
-- Explicit id so later assertions can name this group without re-deriving it
-- from a row the acting user may not be able to see.
insert into public.groups (id, name, created_by) values
  ('99999999-9999-9999-9999-999999999999',
   'Morning Runners',
   '11111111-1111-1111-1111-111111111111');

select matches(
  (select join_code::text from public.groups where name = 'Morning Runners'),
  '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$',
  'a join code is 8 characters from the unambiguous alphabet'
);

select is(
  (select count(distinct join_code) from (
     select app.generate_join_code() as join_code
     from generate_series(1, 50)
   ) s),
  50::bigint,
  '50 generated codes are all distinct'
);

-- The code is a bearer capability, so it must not be derivable from the row.
select isnt(
  (select join_code::text from public.groups where name = 'Morning Runners'),
  (select upper(substr(replace(id::text, '-', ''), 1, 8))
   from public.groups where name = 'Morning Runners'),
  'the join code is not derived from the group id'
);

-- ---------------------------------------------------------------------------
-- A group is never memberless
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.group_members m
   join public.groups g on g.id = m.group_id
   where g.name = 'Morning Runners'),
  1::bigint,
  'creating a group seeds the creator as its first member'
);

select is(
  (select m.user_id from public.group_members m
   join public.groups g on g.id = m.group_id
   where g.name = 'Morning Runners'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'and that member is the creator'
);

-- ---------------------------------------------------------------------------
-- Privileges: the withheld verbs
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('authenticated', 'public.groups', 'delete'),
  'authenticated cannot DELETE a group; the last-one-out trigger owns that'
);
select ok(
  not has_table_privilege('authenticated', 'public.group_members', 'insert'),
  'authenticated cannot INSERT membership directly; joining goes through the RPC'
);
select ok(
  not has_table_privilege('authenticated', 'public.group_members', 'update'),
  'authenticated cannot UPDATE membership, so joined_at cannot be rewritten'
);
select ok(
  has_table_privilege('authenticated', 'public.group_members', 'delete'),
  'authenticated may DELETE membership, which is how leaving works'
);
select ok(
  not has_table_privilege('anon', 'public.groups', 'select'),
  'anon cannot select groups'
);
select ok(
  not has_function_privilege('anon', 'public.join_group_by_code(text)', 'execute'),
  'anon cannot execute join_group_by_code'
);

-- ---------------------------------------------------------------------------
-- Joining
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- Before joining, bob cannot see the group at all — not even to confirm it
-- exists. The code is the only way in.
select is(
  (select count(*) from public.groups),
  0::bigint,
  'a non-member cannot see a group'
);

select throws_ok(
  $$ select public.join_group_by_code('NOTACODE') $$,
  'P0002',
  null,
  'an unused join code is refused'
);

-- Stash the code out of band. A prospective member learns it from a shared
-- link, not from the table — they cannot read the group row until they are in.
reset role;
create temporary table code_holder as
  select join_code::text as code from public.groups where name = 'Morning Runners';
grant select on code_holder to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

select lives_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  'bob joins with the code'
);

select is(
  (select count(*) from public.groups),
  1::bigint,
  'and can now see the group'
);

select is(
  (select count(*) from public.group_members),
  2::bigint,
  'and sees the full roster, including alice'
);

-- Idempotent: the mobile client will retry this on a flaky connection.
select lives_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  'joining twice is not an error'
);

select is(
  (select count(*) from public.group_members),
  2::bigint,
  'and does not duplicate the membership row'
);

-- Codes are case-insensitive so they survive being typed by a human.
reset role;
delete from public.group_members
  where user_id = '22222222-2222-2222-2222-222222222222';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);
select lives_ok(
  $$ select public.join_group_by_code((select lower(code) from code_holder)) $$,
  'a lowercased join code still works'
);

-- ---------------------------------------------------------------------------
-- Group membership makes profiles mutually visible
-- ---------------------------------------------------------------------------
-- alice and bob are not friends; sharing a group is the other route to
-- visibility, and it is what lets a group contest render its participants.
select is(
  (select count(*) from public.profiles),
  2::bigint,
  'sharing a group makes co-members visible to each other'
);

select is(
  (select count(*) from public.profiles
   where id = '33333333-3333-3333-3333-333333333333'),
  0::bigint,
  'and does not make unrelated users visible'
);

-- ---------------------------------------------------------------------------
-- Flat membership: any member administers, nobody commands
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ update public.groups set name = 'Evening Runners' $$,
  'any member can rename the group'
);

-- The code is a capability, so a member may replace it but not choose it.
-- 'AAAAAAAA' satisfies the format constraint and is still refused, because the
-- column-level grant stops the write before any constraint is consulted.
select throws_ok(
  $$ update public.groups set join_code = 'AAAAAAAA' $$,
  '42501',
  null,
  'a member cannot set the join code directly, however well-formed'
);

select matches(
  public.rotate_group_join_code((select id from public.groups)),
  '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$',
  'a member can rotate the code and receives a generated replacement'
);

select isnt(
  (select join_code::text from public.groups),
  (select code from code_holder),
  'rotation retires the previous code'
);

-- Rotation is the one administrative action that could lock others out, so
-- non-membership has to be checked inside the function rather than left to RLS.
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);
select throws_ok(
  $$ select public.rotate_group_join_code(
       '99999999-9999-9999-9999-999999999999') $$,
  '42501',
  null,
  'a non-member cannot rotate a group''s join code'
);
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- No roles means no removal. bob attempting to eject alice is filtered out by
-- the delete policy rather than erroring, so the assertion is on the roster.
delete from public.group_members
  where user_id = '11111111-1111-1111-1111-111111111111';
reset role;
select is(
  (select count(*) from public.group_members
   where user_id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'a member cannot remove another member'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- Two layers, and they fail differently on purpose: a client is stopped by the
-- column grant before any trigger runs, and a privileged writer that gets past
-- the grant is still stopped by the immutability trigger.
select throws_ok(
  $$ update public.groups
     set created_by = '22222222-2222-2222-2222-222222222222' $$,
  '42501',
  null,
  'a client cannot claim authorship: UPDATE on created_by is not granted'
);

reset role;
select throws_ok(
  $$ update public.groups
     set created_by = '22222222-2222-2222-2222-222222222222'
     where id = '99999999-9999-9999-9999-999999999999' $$,
  '23001',
  null,
  'and created_by is immutable even to a writer holding the privilege'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

-- ---------------------------------------------------------------------------
-- Leaving, and the last one out
-- ---------------------------------------------------------------------------
delete from public.group_members
  where user_id = '22222222-2222-2222-2222-222222222222';
reset role;

-- Scoped to the fixture group. These assertions run as superuser, so RLS is not
-- narrowing them and an unscoped count would also see whatever seed.sql left in
-- the database.
select is(
  (select count(*) from public.group_members
   where group_id = '99999999-9999-9999-9999-999999999999'),
  1::bigint,
  'bob can leave'
);
select is(
  (select count(*) from public.groups
   where id = '99999999-9999-9999-9999-999999999999'),
  1::bigint,
  'and the group survives while alice remains'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);
delete from public.group_members
  where user_id = '11111111-1111-1111-1111-111111111111';
reset role;

select is(
  (select count(*) from public.groups
   where id = '99999999-9999-9999-9999-999999999999'),
  0::bigint,
  'the last member leaving reaps the group'
);
select is(
  (select count(*) from public.group_members
   where group_id = '99999999-9999-9999-9999-999999999999'),
  0::bigint,
  'and leaves no orphaned membership rows'
);

-- Deleting a group directly must not recurse through the reaping trigger:
-- the cascade empties group_members, which fires the trigger, which tries to
-- delete the already-deleted group.
insert into public.groups (name, created_by) values
  ('Cascade Check', '11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ delete from public.groups where name = 'Cascade Check' $$,
  'deleting a group directly does not recurse through the reaping trigger'
);

-- ---------------------------------------------------------------------------
-- Onboarding is a precondition for joining
-- ---------------------------------------------------------------------------
insert into auth.users (id) values ('55555555-5555-5555-5555-555555555555');
insert into public.groups (name, created_by) values
  ('Gatekeeping', '11111111-1111-1111-1111-111111111111');

-- Read the code as superuser and inline it. Reading it as the acting user would
-- return NULL under RLS, and this test would then pass on a bad join code
-- rather than on the onboarding gate it is meant to be checking.
drop table code_holder;
create temporary table code_holder as
  select join_code::text as code from public.groups where name = 'Gatekeeping';
grant select on code_holder to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555"}', true);

select throws_ok(
  $$ select public.join_group_by_code((select code from code_holder)) $$,
  '42501',
  null,
  'a user with a valid code but no profile cannot join a group'
);

-- ---------------------------------------------------------------------------
-- created_by must actually survive authentication deletion
-- ---------------------------------------------------------------------------
-- A preceding no-profile denial intentionally left that actor in the JWT GUC.
-- Clear it before privileged fixture setup, then carry the departing actor's
-- valid JWT through the mutations so D81's actor-locking triggers are exercised.
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into auth.users (id) values ('a8888888-8888-8888-8888-888888888888');
insert into public.profiles (id, handle, display_name) values
  ('a8888888-8888-8888-8888-888888888888', 'departing', 'Departing');
select set_config(
  'request.jwt.claims',
  '{"sub":"a8888888-8888-8888-8888-888888888888"}',
  true
);
insert into public.groups (id, name, created_by) values
  ('b8888888-8888-8888-8888-888888888888', 'Outlives Its Founder',
   'a8888888-8888-8888-8888-888888888888');
insert into public.group_members (group_id, user_id) values
  ('b8888888-8888-8888-8888-888888888888',
   '11111111-1111-1111-1111-111111111111');

select public.delete_account('a8888888-8888-8888-8888-888888888888');
select is(
  (
    select created_by
    from public.groups
    where id = 'b8888888-8888-8888-8888-888888888888'
  ),
  'a8888888-8888-8888-8888-888888888888'::uuid,
  'account deletion retains the founder UUID as durable pseudonymous history'
);

select * from finish();
rollback;
