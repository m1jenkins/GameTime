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

  -- -------------------------------------------------------------------------
  -- M2 — charities and a contest
  -- -------------------------------------------------------------------------
  -- These charities are invented, and the EINs and hosts are deliberately not
  -- real: `.test` is reserved by RFC 2606 and cannot resolve. A nominated
  -- charity is where a real donation is meant to go, so a plausible-looking
  -- wrong EIN in a fixture is worse than an obviously fake one.
  --
  -- Note this is the *seed*, which never runs in production. The production list
  -- is an owner action, not a code change we can make here — see DECISIONS.md
  -- D26 for why it is not shipped as a data migration full of guessed EINs.
  insert into public.charities (id, name, ein, slug, url) values
    ('e5555555-5555-5555-5555-555555555551',
     'Example Trail Conservancy', '00-0000001', 'example-trail', 'https://trail.example.test'),
    ('e5555555-5555-5555-5555-555555555552',
     'Example Food Bank', '00-0000002', 'example-food-bank', 'https://food.example.test'),
    ('e5555555-5555-5555-5555-555555555553',
     'Example Retired Fund', '00-0000003', 'example-retired', null)
  on conflict (id) do nothing;

  -- Retired, so the "an active charity is required to nominate" path has
  -- something to fail against without editing anything.
  update public.charities set is_active = false
  where id = 'e5555555-5555-5555-5555-555555555553';

  -- Inserted directly rather than through public.create_contest(), for the same
  -- reason group_members is: that function reads auth.uid(), which a seed script
  -- has no request context to supply.
  --
  -- One contest carrying all three interesting roster states at once — accepted
  -- author, accepted invitee, and an invitation still outstanding — so the
  -- client has something to render for each without setting anything up.
  insert into public.contests (
    id, title, group_id, created_by, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  ) values (
    'f6666666-6666-6666-6666-666666666666',
    'Dev Crew Step Challenge',
    'd4444444-4444-4444-4444-444444444444',
    'a1111111-1111-1111-1111-111111111111',
    'steps', 'daily', 10000, 2500, 'integrity_score',
    now() + interval '2 days', now() + interval '9 days',
    4
  )
  on conflict (id) do nothing;

  -- Two steps, because the schema will not accept a shortcut: only the author
  -- may come into being already accepted, and everyone else has to arrive as
  -- invited and then answer. That is the state machine working, so the seed
  -- follows the same path a client does rather than trying to route around it.
  insert into public.contest_participants
    (contest_id, user_id, status, invited_by, timezone, charity_id) values
    ('f6666666-6666-6666-6666-666666666666',
     'a1111111-1111-1111-1111-111111111111', 'accepted', null,
     'America/New_York', 'e5555555-5555-5555-5555-555555555551'),
    ('f6666666-6666-6666-6666-666666666666',
     'b2222222-2222-2222-2222-222222222222', 'invited',
     'a1111111-1111-1111-1111-111111111111', null, null),
    ('f6666666-6666-6666-6666-666666666666',
     'c3333333-3333-3333-3333-333333333333', 'invited',
     'a1111111-1111-1111-1111-111111111111', null, null)
  on conflict do nothing;

  update public.contest_participants
  set status = 'accepted',
      timezone = 'Europe/Lisbon',
      charity_id = 'e5555555-5555-5555-5555-555555555552'
  where contest_id = 'f6666666-6666-6666-6666-666666666666'
    and user_id = 'b2222222-2222-2222-2222-222222222222'
    and status = 'invited';

  -- -------------------------------------------------------------------------
  -- M3 — a live contest with evidence in it
  -- -------------------------------------------------------------------------
  -- The contest above starts in two days, which means it has no finished hour
  -- inside its window and therefore cannot hold any evidence. So there is a
  -- second one, already running, purely so that `metric_snapshots` and
  -- `contest_evidence` have something in them to click around in.
  --
  -- Its window is in the past, which create_contest() refuses (D25), so the row
  -- is built directly with that trigger off. That is a seed convenience and not
  -- a route a client has: 060_contests.test.sql is what proves the trigger
  -- refuses a backdated window.
  --
  -- Both participants are in whole-hour zones on purpose. A bucket is aligned to
  -- a whole hour in the participant's *own* zone (D36), so a seed that put
  -- @cyclist in Asia/Kolkata would need :30-past buckets for him and on-the-hour
  -- ones for @runner, which is the right behaviour and the wrong thing for a
  -- fixture to be teaching.
  alter table public.contests disable trigger contests_assert_future_window;

  insert into public.contests (
    id, title, created_by, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  ) values (
    'f7777777-7777-7777-7777-777777777777',
    'Live Duel',
    'a1111111-1111-1111-1111-111111111111',
    'steps', 'daily', 8000, 1000, 'integrity_score',
    date_trunc('hour', now()) - interval '2 days',
    date_trunc('hour', now()) + interval '5 days',
    2
  )
  on conflict (id) do nothing;

  alter table public.contests enable trigger contests_assert_future_window;

  -- The roster is built while it is still pending, because M2 freezes it the
  -- moment the window opens (D29), and only then is it activated.
  insert into public.contest_participants
    (contest_id, user_id, status, invited_by, timezone, charity_id) values
    ('f7777777-7777-7777-7777-777777777777',
     'a1111111-1111-1111-1111-111111111111', 'accepted', null,
     'America/New_York', 'e5555555-5555-5555-5555-555555555551'),
    ('f7777777-7777-7777-7777-777777777777',
     'b2222222-2222-2222-2222-222222222222', 'invited',
     'a1111111-1111-1111-1111-111111111111', null, null)
  on conflict do nothing;

  update public.contest_participants
  set status = 'accepted', timezone = 'Europe/Lisbon',
      charity_id = 'e5555555-5555-5555-5555-555555555552'
  where contest_id = 'f7777777-7777-7777-7777-777777777777'
    and user_id = 'b2222222-2222-2222-2222-222222222222'
    and status = 'invited';

  update public.contests
  set status = 'active', activated_at = now()
  where id = 'f7777777-7777-7777-7777-777777777777'
    and status = 'pending';

  -- A device key for @runner. The public key is nonsense — nothing here does
  -- elliptic-curve arithmetic — but the *shape* has to be right, because the
  -- table holds key_id to the digest of public_key with a CHECK, and public_key
  -- to an uncompressed P-256 point.
  --
  -- The byte pattern is 0x5e repeated, distinct from anything a suite uses. A
  -- key id is the digest of its key, so a seed and a fixture that pick the same
  -- filler bytes collide on the primary key — which is the seed breaking a test,
  -- the one direction this file is supposed to make impossible.
  perform public.register_device_key(
    'a1111111-1111-1111-1111-111111111111',
    extensions.digest(('\x04' || repeat('5e', 64))::bytea, 'sha256'),
    ('\x04' || repeat('5e', 64))::bytea,
    'development'
  );

  -- Through record_metric_batch() rather than by inserting rows, so the seed
  -- takes the same path a client does and the fixtures cannot drift into a shape
  -- the real path would refuse.
  --
  -- @runner's hour carries three sources at once, which is the case worth having
  -- in front of anyone browsing: the watch and a third-party app both count and
  -- add, and the hand-typed figure is stored and does not. Look at
  -- metric_snapshots and then at contest_evidence for the same hour.
  perform public.record_metric_batch(
    'a1111111-1111-1111-1111-111111111111',
    'f7777777-7777-7777-7777-777777777777',
    '99999999-0000-0000-0000-000000000001',
    extensions.digest('seed-runner-batch-1', 'sha256'),
    now(),
    jsonb_build_array(
      jsonb_build_object(
        'metric', 'steps',
        'bucket_start', date_trunc('hour', now()) - interval '3 hours',
        'value', 2400, 'provenance', 'device', 'sample_count', 11,
        'source_bundle_id', 'com.apple.health', 'device_model', 'Watch'),
      jsonb_build_object(
        'metric', 'steps',
        'bucket_start', date_trunc('hour', now()) - interval '3 hours',
        'value', 180, 'provenance', 'third_party', 'sample_count', 2,
        'source_bundle_id', 'com.example.runner'),
      jsonb_build_object(
        'metric', 'steps',
        'bucket_start', date_trunc('hour', now()) - interval '3 hours',
        'value', 9000, 'provenance', 'manual', 'sample_count', 1),
      jsonb_build_object(
        'metric', 'steps',
        'bucket_start', date_trunc('hour', now()) - interval '2 hours',
        'value', 1750, 'provenance', 'device', 'sample_count', 8,
        'source_bundle_id', 'com.apple.health', 'device_model', 'Watch')),
    extensions.digest(('\x04' || repeat('5e', 64))::bytea, 'sha256'),
    1::bigint
  );

  -- @cyclist's batch arrives with no key at all, which is what the App Attest
  -- development bypass looks like on the wire (D11). It lands with
  -- `attested = false` and stays distinguishable forever.
  perform public.record_metric_batch(
    'b2222222-2222-2222-2222-222222222222',
    'f7777777-7777-7777-7777-777777777777',
    '99999999-0000-0000-0000-000000000002',
    extensions.digest('seed-cyclist-batch-1', 'sha256'),
    now(),
    jsonb_build_array(
      jsonb_build_object(
        'metric', 'steps',
        'bucket_start', date_trunc('hour', now()) - interval '3 hours',
        'value', 3100, 'provenance', 'device', 'sample_count', 14,
        'source_bundle_id', 'com.apple.health', 'device_model', 'iPhone'),
      jsonb_build_object(
        'metric', 'distance_meters',
        'bucket_start', date_trunc('hour', now()) - interval '3 hours',
        'value', 2350.75, 'provenance', 'device', 'sample_count', 14,
        'source_bundle_id', 'com.apple.health', 'device_model', 'iPhone'))
  );

exception when others then
  raise warning 'seed skipped: % (%). Migrations and tests are unaffected.',
    sqlerrm, sqlstate;
end $$;
