-- charities: curated reference data with no client write path.
--
-- The property that matters is negative. A participant nominates a charity, and
-- the loser's pledge is directed there — so if a client could add a row to this
-- table, "donate to charity" would become "pay an arbitrary payee of the
-- winner's invention". The assertions below are mostly about verbs that are not
-- granted rather than rows that are not visible.

begin;
select plan(21);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'charities', 'public.charities exists');
select col_is_pk('public', 'charities', 'id', 'charities is keyed by a surrogate id');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.charities'::regclass),
  'row level security is enabled on charities'
);

-- ein and donation_slug are globally unique, which makes charities the first
-- table where a fixture can collide with seed.sql rather than merely coexist
-- with it. The repo's rule is that no test may *depend* on the seed; the
-- corollary is that no test may *collide* with it either. Fixtures therefore
-- take the 00-9xxxxxx EIN range and `fixture-` slugs, which the seed never uses.
insert into public.charities (id, name, ein, donation_slug, mission) values
  ('c0000001-0000-0000-0000-000000000001',
   'Fixture Food Bank', '00-9000001', 'fixture-food-bank',
   'Placeholder fixture, not a real organization.'),
  ('c0000002-0000-0000-0000-000000000002',
   'Fixture Animal Rescue', '00-9000002', 'fixture-animal-rescue', null);

-- ---------------------------------------------------------------------------
-- Identifier formats
-- ---------------------------------------------------------------------------
-- The EIN is stored formatted because that is how it appears on an
-- acknowledgement letter: a donor comparing a receipt against the app should be
-- reading the same string, not a normalized variant of it.
select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Unformatted', '000000003', 'unformatted') $$,
  '23514',
  null,
  'an EIN without its hyphen is refused'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Too Short', '00-000004', 'too-short') $$,
  '23514',
  null,
  'an EIN with too few digits is refused'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Duplicate EIN', '00-9000001', 'duplicate-ein') $$,
  '23505',
  null,
  'the same EIN cannot be listed twice'
);

-- The slug goes into a donation URL untouched, so it is constrained to
-- characters that survive that without escaping.
select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Shouty', '00-9000005', 'Example-Shouty') $$,
  '23514',
  null,
  'an uppercase donation slug is refused'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Trailing', '00-9000006', 'trailing-') $$,
  '23514',
  null,
  'a donation slug cannot end in a hyphen'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Spacey', '00-9000007', 'has space') $$,
  '23514',
  null,
  'a donation slug cannot contain a space'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Duplicate slug', '00-9000008', 'fixture-food-bank') $$,
  '23505',
  null,
  'two charities cannot share a donation slug'
);

select lives_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Single', '00-9000009', 'x') $$,
  'a one-character slug is well-formed'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('', '00-9000010', 'empty-name') $$,
  '23514',
  null,
  'a charity must have a name'
);

-- ---------------------------------------------------------------------------
-- Privileges: the whole point of the table
-- ---------------------------------------------------------------------------
select ok(
  has_table_privilege('authenticated', 'public.charities', 'select'),
  'authenticated may read the charity list'
);
select ok(
  not has_table_privilege('authenticated', 'public.charities', 'insert'),
  'authenticated cannot add a charity, so a nomination cannot invent its payee'
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
  'anon cannot read the charity list'
);

-- ---------------------------------------------------------------------------
-- Retirement is not deletion
-- ---------------------------------------------------------------------------
-- A contest that nominated a charity before it was retired still has to render
-- its name, so the read policy covers inactive rows too and filtering is the
-- picker's job.
update public.charities
set is_active = false
where id = 'c0000002-0000-0000-0000-000000000002';

insert into auth.users (id) values ('11111111-1111-1111-1111-111111111111');
insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}', true);

select is(
  (select count(*) from public.charities
   where id in ('c0000001-0000-0000-0000-000000000001',
                'c0000002-0000-0000-0000-000000000002')),
  2::bigint,
  'a retired charity is still readable, so historic nominations still render'
);

select is(
  (select count(*) from public.charities
   where is_active
     and id in ('c0000001-0000-0000-0000-000000000001',
                'c0000002-0000-0000-0000-000000000002')),
  1::bigint,
  'and is_active is what a picker filters on'
);

select throws_ok(
  $$ insert into public.charities (name, ein, donation_slug)
     values ('Rogue', '00-9000099', 'rogue') $$,
  '42501',
  null,
  'a client attempting to add a charity is refused by the missing grant'
);

select throws_ok(
  $$ update public.charities set name = 'Renamed'
     where id = 'c0000001-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'and cannot rename one either'
);

reset role;
select * from finish();
rollback;
