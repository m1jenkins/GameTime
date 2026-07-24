-- Local development seed. Applied by `supabase db reset`.
--
-- Rule for this file: seed data is for local development and CI only. It must
-- never be required for correctness of a test — pgTAP tests build the rows they
-- assert on, inside their own rolled-back transaction. Deleting everything below
-- must leave the suite green.
--
-- What this gives you is a social graph you can click around in Studio, and three
-- identities you can impersonate to exercise RLS by hand:
--
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     '{"sub":"a1111111-1111-1111-1111-111111111111"}', true);
--   select * from public.profiles;   -- now filtered as @runner sees it
--
-- These are not sign-in-able accounts. Signup is Sign in with Apple only
-- (DECISIONS.md D12), which cannot be satisfied locally, so these rows exist to
-- satisfy the foreign key from public.profiles and nothing more.

-- The whole seed is guarded. auth.users belongs to GoTrue, not to this repo, and
-- its column set moves with the platform; a mismatch here must not be able to
-- fail `db reset` and take the entire pgTAP suite down with it. Given the rule
-- above — no test may depend on this data — a warning that the fixtures are
-- missing is the correct failure mode.
do $$
begin
  insert into auth.users (
    id, instance_id, aud, role, email,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  )
  values
    ('a1111111-1111-1111-1111-111111111111',
     '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'runner@example.test',
     '{"provider":"apple","providers":["apple"]}'::jsonb, '{}'::jsonb,
     now(), now()),
    ('b2222222-2222-2222-2222-222222222222',
     '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'cyclist@example.test',
     '{"provider":"apple","providers":["apple"]}'::jsonb, '{}'::jsonb,
     now(), now()),
    ('c3333333-3333-3333-3333-333333333333',
     '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'lifter@example.test',
     '{"provider":"apple","providers":["apple"]}'::jsonb, '{}'::jsonb,
     now(), now())
  on conflict (id) do nothing;

  -- Deliberately spread across timezones: daily-cadence goals are scored in each
  -- participant's own zone (DECISIONS.md D5), and a seed where everybody sits in
  -- UTC is a seed that never surfaces a day-boundary bug.
  --
  -- @Lifter carries a capital L on purpose. It keeps a mixed-case handle in front
  -- of anyone testing discovery by hand, which is where the citext case-folding
  -- trap in DECISIONS.md D14 would otherwise resurface unnoticed.
  insert into public.profiles (id, handle, display_name, timezone) values
    ('a1111111-1111-1111-1111-111111111111', 'runner',  'Dana R.', 'America/New_York'),
    ('b2222222-2222-2222-2222-222222222222', 'cyclist', 'Sam P.',  'Europe/Lisbon'),
    ('c3333333-3333-3333-3333-333333333333', 'Lifter',  'Kai M.',  'Asia/Tokyo')
  on conflict (id) do nothing;

  -- One settled friendship and one inbound request, so both halves of the
  -- lifecycle are visible without having to create anything.
  insert into public.friendships (user_a, user_b, requested_by, status) values
    ('a1111111-1111-1111-1111-111111111111',
     'b2222222-2222-2222-2222-222222222222',
     'a1111111-1111-1111-1111-111111111111',
     'accepted'),
    ('a1111111-1111-1111-1111-111111111111',
     'c3333333-3333-3333-3333-333333333333',
     'c3333333-3333-3333-3333-333333333333',
     'pending')
  on conflict do nothing;

  -- A fixed join code, unlike the generated ones, so it can be typed from memory
  -- when testing the join flow. It still satisfies the format constraint.
  insert into public.groups (id, name, join_code, created_by) values
    ('d4444444-4444-4444-4444-444444444444',
     'Dev Crew',
     'DEVCREW2',
     'a1111111-1111-1111-1111-111111111111')
  on conflict (id) do nothing;

  -- The creator is added by app.add_group_creator_as_member(); these are the
  -- other two. Inserted directly rather than through join_group_by_code(), which
  -- needs a request-scoped auth.uid() that a seed script does not have.
  insert into public.group_members (group_id, user_id) values
    ('d4444444-4444-4444-4444-444444444444', 'b2222222-2222-2222-2222-222222222222'),
    ('d4444444-4444-4444-4444-444444444444', 'c3333333-3333-3333-3333-333333333333')
  on conflict do nothing;

exception when others then
  raise warning 'seed skipped: % (%). Migrations and tests are unaffected.',
    sqlerrm, sqlstate;
end $$;
