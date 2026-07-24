-- profiles: shape, constraints, immutability, RLS, and handle discovery.
--
-- Fixture UUIDs are fixed and ordered (alice < bob < carol) because friendship
-- rows are stored under a canonical `user_a < user_b` ordering and predictable
-- ordering makes those assertions readable rather than a puzzle.

begin;
select plan(40);

-- ---------------------------------------------------------------------------
-- Fixtures, created as superuser. RLS is asserted further down by switching to
-- the `authenticated` role — superuser bypasses policies entirely.
-- ---------------------------------------------------------------------------
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- alice
  ('22222222-2222-2222-2222-222222222222'),  -- bob
  ('33333333-3333-3333-3333-333333333333'),  -- carol
  ('44444444-4444-4444-4444-444444444444');  -- dave, never onboards

insert into public.profiles (id, handle, display_name, timezone) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice', 'America/New_York'),
  ('22222222-2222-2222-2222-222222222222', 'MikeJ', 'Bob',   'Europe/Berlin'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol', 'UTC');

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'profiles', 'public.profiles exists');
select col_type_is('public', 'profiles', 'handle', 'extensions.citext',
  'handle is citext, so uniqueness is case-insensitive');
select col_is_pk('public', 'profiles', 'id', 'id is the primary key');
select col_not_null('public', 'profiles', 'display_name', 'display_name is required');
select col_default_is('public', 'profiles', 'timezone', 'UTC', 'timezone defaults to UTC');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'row level security is enabled on profiles'
);

-- id references auth.users, so a profile cannot exist without an identity.
select col_is_fk('public', 'profiles', 'id', 'id is a foreign key to auth.users');

-- ---------------------------------------------------------------------------
-- Handle rules
-- ---------------------------------------------------------------------------
-- Case-insensitive uniqueness is the property the whole discovery flow rests on.
select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'ALICE', 'Impostor') $$,
  '23505',
  null,
  'handle uniqueness is case-insensitive: ALICE collides with alice'
);

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'ab', 'Too Short') $$,
  '23514',
  null,
  'handle must be at least 3 characters'
);

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', '9lives', 'Leading Digit') $$,
  '23514',
  null,
  'handle must start with a letter'
);

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'has spaces', 'Spacey') $$,
  '23514',
  null,
  'handle rejects characters outside [A-Za-z0-9_]'
);

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'Support', 'Phisher') $$,
  '23514',
  null,
  'reserved handles are rejected regardless of case'
);

select lives_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'Dave_99', 'Dave') $$,
  'a well-formed mixed-case handle with an underscore is accepted'
);
delete from public.profiles where handle = 'Dave_99';

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'dave', '') $$,
  '23514',
  null,
  'display_name cannot be empty'
);

-- ---------------------------------------------------------------------------
-- Timezone validation
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.profiles set timezone = 'Mars/Olympus_Mons'
     where handle = 'alice' $$,
  '22023',
  null,
  'an unknown IANA zone is rejected'
);

select lives_ok(
  $$ update public.profiles set timezone = 'Asia/Tokyo' where handle = 'alice' $$,
  'a real IANA zone is accepted'
);

-- ---------------------------------------------------------------------------
-- Immutable columns
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.profiles set created_at = now() - interval '1 year'
     where handle = 'alice' $$,
  '23001',
  null,
  'created_at is immutable'
);

select throws_ok(
  $$ update public.profiles
     set id = '44444444-4444-4444-4444-444444444444' where handle = 'alice' $$,
  '23001',
  null,
  'id is immutable'
);

-- updated_at is maintained, not frozen — and not the client's to set. Asserted
-- by trying to backdate it: the trigger restamps from the transaction clock.
-- (It cannot be asserted as `updated_at > created_at`, because set_updated_at()
-- uses now(), which is fixed for the whole transaction a pgTAP test runs in.)
update public.profiles set updated_at = '2020-01-01T00:00:00Z' where handle = 'carol';
select ok(
  (select updated_at from public.profiles where handle = 'carol') > '2021-01-01T00:00:00Z',
  'set_updated_at overrides a client-supplied updated_at'
);

-- ---------------------------------------------------------------------------
-- Privileges: anon holds nothing, and the withheld verbs are withheld
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('anon', 'public.profiles', 'select'),
  'anon cannot select profiles'
);
select ok(
  not has_table_privilege('anon', 'public.profiles', 'insert'),
  'anon cannot insert profiles'
);
select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'delete'),
  'authenticated is not granted DELETE on profiles'
);
select ok(
  has_table_privilege('authenticated', 'public.profiles', 'update'),
  'authenticated is granted UPDATE on profiles'
);
select ok(
  not has_function_privilege('anon', 'public.find_profile_by_handle(text)', 'execute'),
  'anon cannot execute find_profile_by_handle'
);
select ok(
  has_function_privilege('authenticated', 'public.find_profile_by_handle(text)', 'execute'),
  'authenticated can execute find_profile_by_handle'
);

-- ---------------------------------------------------------------------------
-- RLS: profile visibility
-- ---------------------------------------------------------------------------
-- alice and bob are friends. carol is a stranger to both.
insert into public.friendships (user_a, user_b, requested_by, status) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'accepted'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select is(
  (select count(*) from public.profiles),
  2::bigint,
  'alice sees exactly two profiles: herself and her friend bob'
);

select is(
  (select display_name from public.profiles
   where id = '22222222-2222-2222-2222-222222222222'),
  'Bob',
  'alice can read a friend''s profile'
);

select is_empty(
  $$ select 1 from public.profiles
     where id = '33333333-3333-3333-3333-333333333333' $$,
  'alice cannot read a stranger''s profile'
);

-- A pending request confers no visibility — only an accepted friendship does.
reset role;
update public.friendships set status = 'pending'
  where user_a = '11111111-1111-1111-1111-111111111111';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'a pending friend request does not make a profile visible'
);

reset role;
update public.friendships set status = 'accepted'
  where user_a = '11111111-1111-1111-1111-111111111111';

-- ---------------------------------------------------------------------------
-- RLS: writing your own profile only
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select lives_ok(
  $$ update public.profiles set display_name = 'Alice A.'
     where id = '11111111-1111-1111-1111-111111111111' $$,
  'alice can update her own profile'
);

-- Not an error: RLS filters the row out, so the UPDATE simply matches nothing.
update public.profiles set display_name = 'Hacked'
  where id = '22222222-2222-2222-2222-222222222222';
reset role;
select is(
  (select display_name from public.profiles
   where id = '22222222-2222-2222-2222-222222222222'),
  'Bob',
  'alice cannot update a friend''s profile'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values ('44444444-4444-4444-4444-444444444444', 'notdave', 'Not Dave') $$,
  '42501',
  null,
  'a user cannot create a profile for somebody else'
);

-- ---------------------------------------------------------------------------
-- Discovery by exact handle
-- ---------------------------------------------------------------------------
-- The regression that matters. bob's handle is stored 'MikeJ'; a lookup for
-- 'mikej' must find it. If the citext `=` operator were used inside a
-- search_path='' function this returns zero rows and friend-adding is broken
-- for anyone with a capital letter in their handle. See DECISIONS.md D14.
select is(
  (select count(*) from public.find_profile_by_handle('mikej')),
  1::bigint,
  'handle lookup is case-insensitive: mikej finds MikeJ'
);

select is(
  (select id from public.find_profile_by_handle('MIKEJ')),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'handle lookup is case-insensitive in the other direction too'
);

-- Discovery deliberately reaches past the profiles RLS policy: carol is a
-- stranger to alice and still resolvable by exact handle. That is the point of
-- the function, and the reason it is exact-match only.
select is(
  (select count(*) from public.find_profile_by_handle('carol')),
  1::bigint,
  'a stranger is discoverable by exact handle'
);

select is_empty(
  $$ select * from public.find_profile_by_handle('car') $$,
  'lookup does not prefix-match, so the directory is not enumerable'
);

select is_empty(
  $$ select * from public.find_profile_by_handle('%') $$,
  'lookup does not treat input as a pattern'
);

select is_empty(
  $$ select * from public.find_profile_by_handle('nobody') $$,
  'an unused handle resolves to nothing'
);

-- The card is minimal: an id to befriend, and enough to render the row. Pinned
-- because widening it later is how a discovery endpoint quietly turns into an
-- information leak — timezone and created_at are nobody else's business.
select set_eq(
  $$ select a.name::text
     from pg_proc p, unnest(p.proargnames, p.proargmodes) as a(name, mode)
     where p.pronamespace = 'public'::regnamespace
       and p.proname = 'find_profile_by_handle'
       and a.mode = 't' $$,
  array['id', 'handle', 'display_name', 'avatar_path'],
  'the lookup card exposes only id, handle, display_name, avatar_path'
);

-- Unauthenticated callers get nothing even if they reach the function.
select set_config('request.jwt.claims', '', true);
select is_empty(
  $$ select * from public.find_profile_by_handle('carol') $$,
  'an unauthenticated caller resolves no handles'
);

reset role;
select * from finish();
rollback;
