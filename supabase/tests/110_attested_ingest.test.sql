-- Attested ingest: record_metric_batch(), the batch record, and the view M4 reads.
--
-- The properties that matter, in rough order of how much damage getting them
-- wrong would do:
--
--   * there is no route into the ledger that a client can take, at all
--   * an assertion counter is consumed exactly once, atomically with the write
--   * a retry of a request that already succeeded is not punished for carrying
--     a counter it already spent
--   * the same batch id with different contents is refused rather than silently
--     dropping one of them
--   * contest_evidence respects RLS, which it would not if it were left as an
--     ordinary view
--   * a batch either lands whole or not at all

begin;
select plan(47);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),   -- alice
  ('22222222-2222-2222-2222-222222222222'),   -- bob, her rival
  ('33333333-3333-3333-3333-333333333333');   -- carol, in a different contest

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001', 'Trail Fund', '12-3456789', 'trail-fund');

-- See 100 for why the future-window trigger comes off for the fixture.
alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values
  ('a0000001-0000-0000-0000-000000000001',
   'Alice vs Bob', '11111111-1111-1111-1111-111111111111',
   'steps', 'daily', 10000, 2500,
   date_trunc('hour', now()) - interval '3 days',
   date_trunc('hour', now()) + interval '4 days', 4),
  -- Carol's own contest, so that the visibility assertions have a participant
  -- who is signed in and legitimate but has no business reading Alice's hours.
  ('a0000002-0000-0000-0000-000000000002',
   'Carol Solo', '33333333-3333-3333-3333-333333333333',
   'steps', 'cumulative', 10000, 2500,
   date_trunc('hour', now()) - interval '3 days',
   date_trunc('hour', now()) + interval '4 days', 4);

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants
  (contest_id, user_id, status, invited_by, timezone, charity_id) values
  ('a0000001-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'accepted', null,
   'America/New_York', 'c0000001-0000-0000-0000-000000000001'),
  ('a0000001-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'invited',
   '11111111-1111-1111-1111-111111111111', null, null),
  ('a0000002-0000-0000-0000-000000000002',
   '33333333-3333-3333-3333-333333333333', 'accepted', null,
   'America/New_York', 'c0000001-0000-0000-0000-000000000001');

update public.contest_participants
set status = 'accepted', timezone = 'America/New_York',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = 'a0000001-0000-0000-0000-000000000001'
  and user_id = '22222222-2222-2222-2222-222222222222';

update public.contests
set status = 'active', activated_at = now()
where id in ('a0000001-0000-0000-0000-000000000001',
             'a0000002-0000-0000-0000-000000000002');

create temporary table t_keys as
select
  ('\x04' || repeat('a1', 64))::bytea as alice_key,
  extensions.digest(('\x04' || repeat('a1', 64))::bytea, 'sha256') as alice_key_id,
  ('\x04' || repeat('b2', 64))::bytea as bob_key,
  extensions.digest(('\x04' || repeat('b2', 64))::bytea, 'sha256') as bob_key_id;

select public.register_device_key(
  '11111111-1111-1111-1111-111111111111',
  (select alice_key_id from t_keys), (select alice_key from t_keys), 'production');
select public.register_device_key(
  '22222222-2222-2222-2222-222222222222',
  (select bob_key_id from t_keys), (select bob_key from t_keys), 'production');

create temporary table t_hours as
select date_trunc('hour', now()) - interval '2 hours' as h2,
       date_trunc('hour', now()) - interval '3 hours' as h3,
       date_trunc('hour', now()) - interval '4 hours' as h4;

-- One observation, as the client would send it.
create or replace function pg_temp.obs(p_bucket timestamptz, p_value numeric,
                                       p_prov text default 'device')
returns jsonb
language sql
as $$
  select jsonb_build_array(jsonb_build_object(
    'metric', 'steps',
    'bucket_start', p_bucket,
    'value', p_value,
    'provenance', p_prov,
    'sample_count', 4,
    'source_bundle_id', 'com.apple.health',
    'device_model', 'Watch'));
$$;

-- ---------------------------------------------------------------------------
-- No client route into the ledger
-- ---------------------------------------------------------------------------
-- This is the whole milestone in five assertions. What authorises a write here
-- is an ECDSA signature over the payload, and RLS cannot check a signature — so
-- there is no policy that could express the rule and therefore no grant either.
select ok(
  not has_table_privilege('authenticated', 'public.metric_snapshots', 'insert'),
  'authenticated cannot insert into the ledger'
);
select ok(
  not has_table_privilege('authenticated', 'public.metric_snapshots', 'update'),
  'nor update it'
);
select ok(
  not has_table_privilege('authenticated', 'public.metric_snapshots', 'delete'),
  'nor delete from it'
);
select ok(
  not has_table_privilege('authenticated', 'public.ingest_batches', 'insert'),
  'and it cannot forge a batch record either'
);
select ok(
  has_table_privilege('authenticated', 'public.metric_snapshots', 'select'),
  'reading is the only verb a client holds'
);

-- Postgres grants EXECUTE on a new function to PUBLIC. Without the revoke this
-- definer function would let any signed-in user write any other user's
-- evidence, unattested, by passing their uuid — which is D32's trap, in the one
-- place it would cost the most.
select ok(
  not has_function_privilege('authenticated',
    'public.record_metric_batch(uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint)',
    'execute'),
  'authenticated cannot call record_metric_batch'
);
select ok(
  has_function_privilege('service_role',
    'public.record_metric_batch(uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint)',
    'execute'),
  'service_role can, which is how the Edge Function reaches it'
);
select ok(
  not has_function_privilege('authenticated',
    'app.ingest_grace_period()', 'execute'),
  'the grace period is not a client-callable function either'
);

-- ---------------------------------------------------------------------------
-- A batch lands
-- ---------------------------------------------------------------------------
create temporary table t_first as
select * from public.record_metric_batch(
  '11111111-1111-1111-1111-111111111111',
  'a0000001-0000-0000-0000-000000000001',
  'b0000001-0000-0000-0000-000000000001',
  extensions.digest('payload-1', 'sha256'),
  now(),
  pg_temp.obs((select h2 from t_hours), 800),
  (select alice_key_id from t_keys),
  1::bigint
);

select is((select observation_count from t_first), 1,
  'the batch reports what it recorded');
select is((select replayed from t_first), false,
  'and it is not a replay');

select is(
  (select attested from public.ingest_batches where id = (select batch_id from t_first)),
  true,
  'a batch carrying a key and a counter is recorded as attested'
);

select is(
  (select sign_count from public.device_attestations
   where key_id = (select alice_key_id from t_keys)),
  1::bigint,
  'and the assertion counter was consumed'
);

-- ---------------------------------------------------------------------------
-- Idempotency, and why it is checked before the counter
-- ---------------------------------------------------------------------------
-- A phone that times out mid-request retries with the same batch and the same
-- assertion. The counter for that assertion has already been spent, so a
-- naive implementation that checked the counter first would turn every timed-out
-- retry into a permanent failure — the client can never make progress, and the
-- day's evidence is lost through no fault of its own.
create temporary table t_replay as
select * from public.record_metric_batch(
  '11111111-1111-1111-1111-111111111111',
  'a0000001-0000-0000-0000-000000000001',
  'b0000001-0000-0000-0000-000000000001',
  extensions.digest('payload-1', 'sha256'),
  now(),
  pg_temp.obs((select h2 from t_hours), 800),
  (select alice_key_id from t_keys),
  1::bigint
);

select is((select replayed from t_replay), true,
  'a retry of the same batch is reported as a replay');

select is(
  (select batch_id from t_replay),
  (select batch_id from t_first),
  'and it returns the original batch rather than making a second one'
);

select is(
  (select count(*) from public.metric_snapshots
   where user_id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'the retry did not double-count the evidence'
);

select is(
  (select sign_count from public.device_attestations
   where key_id = (select alice_key_id from t_keys)),
  1::bigint,
  'and it did not consume a second counter value'
);

-- Same idempotency key, different contents. Returning the first result would
-- silently discard the second batch's evidence, so this has to be an error.
select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000001-0000-0000-0000-000000000001',
       extensions.digest('a-different-payload', 'sha256'),
       now(),
       pg_temp.obs((select h3 from t_hours), 900),
       (select alice_key_id from t_keys),
       2::bigint) $$,
  '23505',
  null,
  'one batch id with two different payloads is refused, not quietly deduplicated'
);

-- ---------------------------------------------------------------------------
-- The replay counter
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000002-0000-0000-0000-000000000002',
       extensions.digest('payload-2', 'sha256'),
       now(),
       pg_temp.obs((select h3 from t_hours), 900),
       (select alice_key_id from t_keys),
       1::bigint) $$,
  '23001',
  null,
  'a fresh batch replaying a spent counter is refused'
);

select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000003-0000-0000-0000-000000000003',
       extensions.digest('payload-3', 'sha256'),
       now(),
       pg_temp.obs((select h3 from t_hours), 900),
       (select alice_key_id from t_keys),
       0::bigint) $$,
  '23001',
  null,
  'and so is one that winds the counter backward'
);

select lives_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000004-0000-0000-0000-000000000004',
       extensions.digest('payload-4', 'sha256'),
       now(),
       pg_temp.obs((select h3 from t_hours), 900),
       (select alice_key_id from t_keys),
       2::bigint) $$,
  'a counter that has advanced is accepted'
);

-- Signing with someone else's key. The error is deliberately the same as for a
-- key that does not exist, so this cannot be used to find out which keys are
-- registered.
select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000005-0000-0000-0000-000000000005',
       extensions.digest('payload-5', 'sha256'),
       now(),
       pg_temp.obs((select h4 from t_hours), 100),
       (select bob_key_id from t_keys),
       50::bigint) $$,
  '42501',
  null,
  'a batch cannot be signed with another account''s key'
);

select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000006-0000-0000-0000-000000000006',
       extensions.digest('payload-6', 'sha256'),
       now(),
       pg_temp.obs((select h4 from t_hours), 100),
       extensions.digest('not-a-real-key'::bytea, 'sha256'),
       1::bigint) $$,
  '42501',
  null,
  'and an unknown key gives exactly the same error'
);

update public.device_attestations set revoked_at = now()
where key_id = (select bob_key_id from t_keys);

select throws_ok(
  $$ select public.record_metric_batch(
       '22222222-2222-2222-2222-222222222222',
       'a0000001-0000-0000-0000-000000000001',
       'b0000007-0000-0000-0000-000000000007',
       extensions.digest('payload-7', 'sha256'),
       now(),
       pg_temp.obs((select h4 from t_hours), 100),
       (select bob_key_id from t_keys),
       1::bigint) $$,
  '42501',
  null,
  'a revoked key cannot sign a batch'
);

update public.device_attestations set revoked_at = null
where key_id = (select bob_key_id from t_keys);

-- ---------------------------------------------------------------------------
-- All or nothing
-- ---------------------------------------------------------------------------
-- Twenty good observations and one for an hour that has not happened. Partial
-- acceptance would leave the client believing it had synced while quietly
-- dropping part of the day, so the whole batch fails and the error names why.
select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000008-0000-0000-0000-000000000008',
       extensions.digest('payload-8', 'sha256'),
       now(),
       pg_temp.obs((select h4 from t_hours), 100)
         || pg_temp.obs(date_trunc('hour', now()) + interval '5 hours', 9999),
       (select alice_key_id from t_keys),
       3::bigint) $$,
  '22023',
  null,
  'one bad observation fails the whole batch'
);

select is_empty(
  $$ select 1 from public.ingest_batches
     where client_batch_id = 'b0000008-0000-0000-0000-000000000008' $$,
  'and no batch record is left behind'
);

select is_empty(
  $$ select 1 from public.metric_snapshots
     where bucket_start = (select h4 from t_hours) $$,
  'nor any of its good observations'
);

-- An empty batch is a client bug rather than a no-op worth recording.
select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b0000009-0000-0000-0000-000000000009',
       extensions.digest('payload-9', 'sha256'),
       now(), '[]'::jsonb,
       (select alice_key_id from t_keys), 4::bigint) $$,
  '22023',
  null,
  'an empty batch is refused'
);

select throws_ok(
  $$ select public.record_metric_batch(
       '11111111-1111-1111-1111-111111111111',
       'a0000001-0000-0000-0000-000000000001',
       'b000000a-0000-0000-0000-00000000000a',
       extensions.digest('payload-a', 'sha256'),
       now(), '{"metric":"steps"}'::jsonb,
       (select alice_key_id from t_keys), 4::bigint) $$,
  '22023',
  null,
  'and so is an observation list that is not a list'
);

-- ---------------------------------------------------------------------------
-- The development bypass leaves a permanent mark
-- ---------------------------------------------------------------------------
-- D11 makes the bypass impossible to enable in staging or production, and this
-- is the other half: a batch that arrived unattested says so forever, so
-- `select count(*) from ingest_batches where not attested` is a real audit.
select lives_ok(
  $$ select public.record_metric_batch(
       '22222222-2222-2222-2222-222222222222',
       'a0000001-0000-0000-0000-000000000001',
       'b000000b-0000-0000-0000-00000000000b',
       extensions.digest('payload-b', 'sha256'),
       now(),
       pg_temp.obs((select h2 from t_hours), 600)) $$,
  'a batch with no key at all is accepted, which is the bypass path'
);

select is(
  (select attested from public.ingest_batches
   where client_batch_id = 'b000000b-0000-0000-0000-00000000000b'),
  false,
  'and it is permanently marked unattested'
);

-- A batch cannot claim to be attested by nothing: the CHECK ties the flag to
-- the key and the counter, so no code path can produce that row.
select throws_ok(
  $$ insert into public.ingest_batches
       (contest_id, user_id, client_batch_id, attested, payload_digest,
        observation_count, observed_at)
     values ('a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111',
             'b000000c-0000-0000-0000-00000000000c', true,
             extensions.digest('x', 'sha256'), 1, now()) $$,
  '23514',
  null,
  'a batch cannot be marked attested without a key and a counter'
);

-- ---------------------------------------------------------------------------
-- contest_evidence
-- ---------------------------------------------------------------------------
-- Alice's h2 bucket now has one observation at 800; add a revision at 950 so
-- the reduction has something to reduce.
select public.record_metric_batch(
  '11111111-1111-1111-1111-111111111111',
  'a0000001-0000-0000-0000-000000000001',
  'b000000d-0000-0000-0000-00000000000d',
  extensions.digest('payload-d', 'sha256'),
  now(),
  pg_temp.obs((select h2 from t_hours), 950),
  (select alice_key_id from t_keys),
  5::bigint
);

-- And a hand-typed one, which must not appear in the view at all.
select public.record_metric_batch(
  '11111111-1111-1111-1111-111111111111',
  'a0000001-0000-0000-0000-000000000001',
  'b000000e-0000-0000-0000-00000000000e',
  extensions.digest('payload-e', 'sha256'),
  now(),
  pg_temp.obs((select h4 from t_hours), 30000, 'manual'),
  (select alice_key_id from t_keys),
  6::bigint
);

select is(
  (select value from public.contest_evidence
   where user_id = '11111111-1111-1111-1111-111111111111'
     and bucket_start = (select h2 from t_hours)),
  950::numeric,
  'the view reports the highest observation for a bucket'
);

select is(
  (select observation_count from public.contest_evidence
   where user_id = '11111111-1111-1111-1111-111111111111'
     and bucket_start = (select h2 from t_hours)),
  2,
  'and says how many observations it came from'
);

select is_empty(
  $$ select 1 from public.contest_evidence
     where user_id = '11111111-1111-1111-1111-111111111111'
       and bucket_start = (select h4 from t_hours) $$,
  'a bucket whose only observation was hand-typed is absent from the view'
);

select isnt_empty(
  $$ select 1 from public.metric_snapshots
     where user_id = '11111111-1111-1111-1111-111111111111'
       and bucket_start = (select h4 from t_hours) $$,
  'though the ledger still holds it, because the attempt is itself a fact'
);

-- ---------------------------------------------------------------------------
-- The view respects RLS, which it would not by default
-- ---------------------------------------------------------------------------
-- A view runs with its *owner's* privileges unless security_invoker is set, and
-- the owner here owns the underlying table and is therefore exempt from its
-- policies. Left as an ordinary view this would hand every signed-in user the
-- entire ledger — every participant's hourly movements — with RLS switched on
-- and doing nothing. Asserted rather than reviewed.
select ok(
  (select 'security_invoker=true' = any(reloptions)
   from pg_class where oid = 'public.contest_evidence'::regclass),
  'contest_evidence is declared security_invoker'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}', true);

select is_empty(
  $$ select 1 from public.contest_evidence
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'carol cannot read alice''s evidence through the view'
);

select is_empty(
  $$ select 1 from public.metric_snapshots
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'nor through the table'
);

-- Bob is Alice's opponent in an opened contest they both accepted, which is the
-- one relationship that grants a view of somebody else's hours — and it has to,
-- because it is the evidence he is being judged against.
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}', true);

select isnt_empty(
  $$ select 1 from public.contest_evidence
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'her opponent can, because a settlement he may owe rests on it'
);

select isnt_empty(
  $$ select 1 from public.ingest_batches
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'and can see how her batches arrived, which is what a dispute needs'
);

reset role;

select is(
  (select count(*) from pg_policies
   where schemaname = 'public'
     and tablename in ('metric_snapshots', 'ingest_batches', 'device_attestations')),
  3::bigint,
  'three tables, three policies, all of them read-only'
);

-- ---------------------------------------------------------------------------
-- One hour, several sources
-- ---------------------------------------------------------------------------
-- The case the provenance-keyed ledger exists for. A real hour routinely holds
-- samples from more than one source: an iPhone's pedometer, a watch, a running
-- app, and sometimes a figure typed into the Health app years ago. Collapsing
-- those into one row would mean picking one provenance for the hour, and the
-- only safe pick is the least trusted present — which would let one stray
-- hand-typed step discard thousands of genuine ones.
select lives_ok(
  $$ select public.record_metric_batch(
       '22222222-2222-2222-2222-222222222222',
       'a0000001-0000-0000-0000-000000000001',
       'b000000f-0000-0000-0000-00000000000f',
       extensions.digest('payload-f', 'sha256'),
       now(),
       jsonb_build_array(
         jsonb_build_object('metric', 'steps', 'bucket_start', (select h3 from t_hours),
                            'value', 4000, 'provenance', 'device', 'sample_count', 10),
         jsonb_build_object('metric', 'steps', 'bucket_start', (select h3 from t_hours),
                            'value', 500, 'provenance', 'third_party', 'sample_count', 2),
         jsonb_build_object('metric', 'steps', 'bucket_start', (select h3 from t_hours),
                            'value', 9000, 'provenance', 'manual', 'sample_count', 1)),
       (select bob_key_id from t_keys),
       10::bigint) $$,
  'one batch may carry the same bucket once per source'
);

select is(
  (select count(*) from public.metric_snapshots
   where user_id = '22222222-2222-2222-2222-222222222222'
     and bucket_start = (select h3 from t_hours)),
  3::bigint,
  'all three land, including the hand-typed one'
);

select is(
  (select value from public.contest_evidence
   where user_id = '22222222-2222-2222-2222-222222222222'
     and bucket_start = (select h3 from t_hours)),
  4500::numeric,
  'the view adds the admissible sources and leaves the hand-typed one out'
);

-- And a revision to one source is a max within that source, not an addition,
-- while the other source is untouched. Getting this backwards in either
-- direction is a scoring bug: summing revisions counts a late sync twice,
-- taking the max across sources discards all but the largest.
select lives_ok(
  $$ select public.record_metric_batch(
       '22222222-2222-2222-2222-222222222222',
       'a0000001-0000-0000-0000-000000000001',
       'b0000010-0000-0000-0000-000000000010',
       extensions.digest('payload-10', 'sha256'),
       now(),
       jsonb_build_array(jsonb_build_object(
         'metric', 'steps', 'bucket_start', (select h3 from t_hours),
         'value', 4200, 'provenance', 'device', 'sample_count', 11)),
       (select bob_key_id from t_keys),
       11::bigint) $$,
  'a late sync revises one source upward'
);

select is(
  (select value from public.contest_evidence
   where user_id = '22222222-2222-2222-2222-222222222222'
     and bucket_start = (select h3 from t_hours)),
  4700::numeric,
  'the revision replaced that source''s figure rather than adding to it'
);

-- Two sources are independent, so a value below the *other* source's figure is
-- not a downward revision and must not be refused.
select lives_ok(
  $$ select public.record_metric_batch(
       '22222222-2222-2222-2222-222222222222',
       'a0000001-0000-0000-0000-000000000001',
       'b0000011-0000-0000-0000-000000000011',
       extensions.digest('payload-11', 'sha256'),
       now(),
       jsonb_build_array(jsonb_build_object(
         'metric', 'steps', 'bucket_start', (select h3 from t_hours),
         'value', 600, 'provenance', 'third_party', 'sample_count', 3)),
       (select bob_key_id from t_keys),
       12::bigint) $$,
  'monotonicity is per source, so a smaller figure from a smaller source is fine'
);

select * from finish();
rollback;
