-- charities: curated reference data, and the fact that clients cannot write it.
--
-- There is not much behaviour here, which is the point — a charity row is the
-- destination of a real donation obligation, so the interesting assertions are
-- about the verbs nobody holds.

begin;
select plan(19);

-- D81 composes the reference-data read policy with active_actor_only, so RLS
-- checks need a real, non-tombstoned authenticated actor.
insert into auth.users (id)
values ('11111111-1111-1111-1111-111111111111');
insert into public.profiles (id, handle, display_name)
values ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice');

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'charities', 'public.charities exists');
select col_is_pk('public', 'charities', 'id', 'charities is keyed by a surrogate id');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.charities'::regclass),
  'row level security is enabled on charities'
);

insert into public.charities (id, name, ein, slug, url) values
  ('c0000001-0000-0000-0000-000000000001',
   'Test Trail Fund', '12-3456789', 'test-trail-fund',
   'https://example.test/trail');

select is(
  (select is_active from public.charities
   where id = 'c0000001-0000-0000-0000-000000000001'),
  true,
  'a charity is active unless retired'
);

-- ---------------------------------------------------------------------------
-- Format constraints
-- ---------------------------------------------------------------------------
-- The EIN is stored as it appears on a receipt, so the separator is part of the
-- format rather than something the client is free to omit.
select throws_ok(
  $$ insert into public.charities (name, ein, slug)
     values ('Bad EIN', '123456789', 'bad-ein') $$,
  '23514',
  null,
  'an unformatted EIN is refused'
);

select throws_ok(
  $$ insert into public.charities (name, ein, slug)
     values ('Bad Slug', '22-3456789', 'Not_A_Slug') $$,
  '23514',
  null,
  'a slug must be lowercase and hyphenated'
);

-- A donation link that is not https is a downgrade attack on the one URL in
-- this schema a user might follow to give money away.
select throws_ok(
  $$ insert into public.charities (name, ein, slug, url)
     values ('Insecure', '33-3456789', 'insecure', 'http://example.test') $$,
  '23514',
  null,
  'a charity URL must be https'
);

select throws_ok(
  $$ insert into public.charities (name, ein, slug)
     values ('', '44-3456789', 'empty-name') $$,
  '23514',
  null,
  'a charity needs a name'
);

select throws_ok(
  $$ insert into public.charities (name, ein, slug)
     values ('Duplicate EIN', '12-3456789', 'other-slug') $$,
  '23505',
  null,
  'an EIN identifies one charity'
);

select throws_ok(
  $$ insert into public.charities (name, ein, slug)
     values ('Duplicate Slug', '55-3456789', 'test-trail-fund') $$,
  '23505',
  null,
  'a slug identifies one charity'
);

-- ---------------------------------------------------------------------------
-- citext on slug
-- ---------------------------------------------------------------------------
-- The format constraint already forces lowercase storage, so the reason this
-- column is citext is the *lookup*: a slug travels in a URL and comes back
-- however it was typed. Written with the operator schema-qualified rather than
-- relying on `extensions` sitting in the session search_path, which is the same
-- discipline D14 requires inside functions.
select is(
  (select count(*) from public.charities
   where slug operator(extensions.=) 'Test-Trail-FUND'::extensions.citext),
  1::bigint,
  'a mixed-case slug still resolves to the charity'
);

-- ---------------------------------------------------------------------------
-- Privileges: read, and nothing else
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.charities', 'select'),
  'authenticated may read the charity list'
);
select ok(
  not has_table_privilege('authenticated', 'public.charities', 'insert'),
  'authenticated cannot add a charity'
);
select ok(
  not has_table_privilege('authenticated', 'public.charities', 'update'),
  'authenticated cannot edit a charity'
);
select ok(
  not has_table_privilege('authenticated', 'public.charities', 'delete'),
  'authenticated cannot remove a charity'
);
select ok(
  not has_table_privilege('anon', 'public.charities', 'select'),
  'anon cannot read the charity list either'
);

-- ---------------------------------------------------------------------------
-- A retired charity stays readable
-- ---------------------------------------------------------------------------
-- Retiring a charity must not blank out the nomination on a contest that is
-- already under way, so the read policy does not filter on is_active. What
-- is_active gates is new nominations, which is asserted in 080.
insert into public.charities (id, name, ein, slug, is_active) values
  ('c0000002-0000-0000-0000-000000000002',
   'Retired Fund', '66-3456789', 'retired-fund', false);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (select count(*) from public.charities
   where id = 'c0000002-0000-0000-0000-000000000002'),
  1::bigint,
  'a retired charity is still readable, so existing nominations render'
);

select is(
  (select count(*) from public.charities
   where id = 'c0000001-0000-0000-0000-000000000001'),
  1::bigint,
  'and so is an active one'
);

-- The feature policy remains `using (true)` reference-data access, but D81's
-- restrictive policy makes it available only to a currently active actor.
reset role;
select set_eq(
  $$ select policyname || ':' || permissive || ':' || cmd
     from pg_policies
     where schemaname = 'public' and tablename = 'charities' $$,
  array[
    'active_actor_only:RESTRICTIVE:ALL',
    'charities_select_all:PERMISSIVE:SELECT'
  ],
  'charities composes reference-data reads with the restrictive active-actor guard'
);

select * from finish();
rollback;
