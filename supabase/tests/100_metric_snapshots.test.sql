-- The evidence ledger: what may enter it, and what can never leave.
--
-- The properties that matter, in rough order of how much damage getting them
-- wrong would do:
--
--   * an hour that has not finished cannot be reported, or every open contest
--     would accept a winning scoreline for the rest of its window in advance
--   * evidence outside the agreed window is refused, which is the other half of
--     D25 — that rule stops a window being backdated, this one stops the data
--   * a bucket is aligned to a whole hour in the participant's *own* zone, so a
--     +05:30 participant's day boundary is not silently misattributed
--   * a banked figure can be revised up but never down, so "the value for this
--     hour" is one number
--   * a hand-typed sample is stored and never counted
--   * nothing rewrites the ledger — and yet an account can still be deleted,
--     which is the trap D34 was about

begin;
select plan(28);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),   -- alice, author, America/New_York
  ('22222222-2222-2222-2222-222222222222'),   -- bob, Asia/Kolkata (+05:30)
  ('33333333-3333-3333-3333-333333333333');   -- carol, invited, never accepts

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001', 'Trail Fund', '12-3456789', 'trail-fund');

-- ---------------------------------------------------------------------------
-- Fixture: a contest whose window is already open
-- ---------------------------------------------------------------------------
-- create_contest() cannot build this, by design: D25 refuses a window that
-- opens in the past, and a contest that started in the future has no finished
-- hour inside it to report. So the row is built directly with that one trigger
-- off, which is scaffolding rather than a hole — 060_contests.test.sql is what
-- proves the trigger refuses a backdated window, and this suite would be
-- asserting nothing without a live contest to assert against.
--
-- Both boundaries are hour-aligned so that the "wholly inside the window" rule
-- is being tested rather than the alignment of an arbitrary window.
alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values (
  'a0000001-0000-0000-0000-000000000001',
  'Live One', '11111111-1111-1111-1111-111111111111',
  'steps', 'daily', 10000, 2500,
  date_trunc('hour', now()) - interval '3 days',
  date_trunc('hour', now()) + interval '4 days',
  4
);

alter table public.contests enable trigger contests_assert_future_window;

-- The roster is built while the contest is still pending, because M2 freezes it
-- the moment the window opens (D29). Only then is it activated, which is the
-- order a real contest goes through.
insert into public.contest_participants
  (contest_id, user_id, status, invited_by, timezone, charity_id) values
  ('a0000001-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'accepted', null,
   'America/New_York', 'c0000001-0000-0000-0000-000000000001'),
  ('a0000001-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'invited',
   '11111111-1111-1111-1111-111111111111', null, null),
  ('a0000001-0000-0000-0000-000000000001',
   '33333333-3333-3333-3333-333333333333', 'invited',
   '11111111-1111-1111-1111-111111111111', null, null);

update public.contest_participants
set status = 'accepted', timezone = 'Asia/Kolkata',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = 'a0000001-0000-0000-0000-000000000001'
  and user_id = '22222222-2222-2222-2222-222222222222';

update public.contests
set status = 'active', activated_at = now()
where id = 'a0000001-0000-0000-0000-000000000001';

-- One batch per insert path exercised below. Batches are the parent of every
-- snapshot, so the suite needs its own rather than going through
-- record_metric_batch(), whose behaviour 110 owns.
create or replace function pg_temp.new_batch(p_user uuid, p_tag text)
returns uuid
language sql
as $$
  insert into public.ingest_batches (
    contest_id, user_id, client_batch_id, attested, payload_digest,
    observation_count, observed_at
  )
  values (
    'a0000001-0000-0000-0000-000000000001', p_user,
    md5(p_tag)::uuid, false,
    extensions.digest(p_tag, 'sha256'), 1, now()
  )
  returning id;
$$;

-- Alice's zone is a whole number of hours from UTC, so a UTC-aligned hour is
-- also one of her local hours.
create temporary table t_hours as
select
  date_trunc('hour', now()) - interval '2 hours' as ny_bucket,
  (date_trunc('hour', now() at time zone 'Asia/Kolkata') - interval '2 hours')
    at time zone 'Asia/Kolkata' as kolkata_bucket;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('public', 'metric_snapshots', 'public.metric_snapshots exists');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.metric_snapshots'::regclass),
  'row level security is enabled on metric_snapshots'
);

-- No unique constraint across the bucket, and its absence is the design: a
-- revision appends rather than overwriting, which is what keeps *when* a figure
-- was claimed in the record.
select is(
  (select count(*) from pg_constraint
   where conrelid = 'public.metric_snapshots'::regclass
     and contype = 'u'
     and conkey @> (
       select array_agg(attnum) from pg_attribute
       where attrelid = 'public.metric_snapshots'::regclass
         and attname in ('contest_id', 'user_id', 'metric', 'bucket_start'))),
  0::bigint,
  'a bucket is not unique per participant: revisions append'
);

-- ---------------------------------------------------------------------------
-- Who may record evidence
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '33333333-3333-3333-3333-333333333333', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    pg_temp.new_batch('33333333-3333-3333-3333-333333333333', 'carol'),
    (select ny_bucket from t_hours)),
  '23001',
  null,
  'someone who only ever held an invitation cannot record evidence'
);

select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '99999999-9999-9999-9999-999999999999', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'stranger-batch'),
    (select ny_bucket from t_hours)),
  '23503',
  null,
  'and someone who was never on the roster cannot either'
);

-- ---------------------------------------------------------------------------
-- The window, and the future
-- ---------------------------------------------------------------------------
create temporary table t_alice_batches as
select pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a1') as b1,
       pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a2') as b2,
       pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a3') as b3,
       pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a4') as b4,
       pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a5') as b5,
       pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'a6') as b6;

select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    (select b1 from t_alice_batches),
    (select date_trunc('hour', now()) - interval '10 days')),
  '22023',
  null,
  'a bucket before the window opened is refused'
);

-- The one that matters most in this section. Every hour from now until the
-- window closes is inside the agreed window, so without a separate rule a
-- client could bank a complete winning scoreline for a contest that has four
-- days left to run.
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    (select b2 from t_alice_batches),
    (select date_trunc('hour', now()) + interval '2 hours')),
  '22023',
  null,
  'a bucket inside the window but still in the future is refused'
);

-- The hour containing `now()` has not finished either, which is the boundary
-- case the rule is actually about.
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    (select b3 from t_alice_batches),
    (select date_trunc('hour', now()))),
  '22023',
  null,
  'the hour currently in progress is refused: it has not finished'
);

select lives_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 800, 'device', 6, now(), 'epoch', 0) $$,
    (select b4 from t_alice_batches),
    (select ny_bucket from t_hours)),
  'a finished hour inside the window is accepted'
);

-- ---------------------------------------------------------------------------
-- Alignment, and the local day
-- ---------------------------------------------------------------------------
-- This is the assertion the whole bucketing scheme exists for. Bob is in
-- Asia/Kolkata, which is +05:30, so his local hours fall at :30 past the UTC
-- hour. A UTC-aligned bucket straddles his local day boundary, and if it were
-- accepted then daily cadence would attribute part of his Tuesday to Monday —
-- silently, and for about a fifth of the world's population.
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    pg_temp.new_batch('22222222-2222-2222-2222-222222222222', 'bob-misaligned'),
    (select ny_bucket from t_hours)),
  '22023',
  null,
  'a UTC-aligned bucket is refused for a participant whose zone is +05:30'
);

select lives_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'steps',
             %L, 500, 'device', 1, now(), 'epoch', 0) $$,
    pg_temp.new_batch('22222222-2222-2222-2222-222222222222', 'bob-aligned'),
    (select kolkata_bucket from t_hours)),
  'and the same hour aligned to *his* local hour is accepted'
);

-- The local day and hour are the server's reading, taken from the frozen zone.
-- A client supplied 'epoch' and 0 above in both cases; neither survived.
select is(
  (select local_day from public.metric_snapshots
   where user_id = '22222222-2222-2222-2222-222222222222'),
  (select (kolkata_bucket at time zone 'Asia/Kolkata')::date from t_hours),
  'local_day is stamped from the participant''s zone, not taken from the client'
);

select is(
  (select local_hour from public.metric_snapshots
   where user_id = '22222222-2222-2222-2222-222222222222'),
  (select extract(hour from kolkata_bucket at time zone 'Asia/Kolkata')::smallint
   from t_hours),
  'and so is local_hour'
);

select isnt(
  (select local_day from public.metric_snapshots
   where user_id = '22222222-2222-2222-2222-222222222222'),
  'epoch'::date,
  'the client''s own local_day was discarded rather than trusted'
);

-- ---------------------------------------------------------------------------
-- Monotonicity
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 700, 'device', 1, now(), 'epoch', 0) $$,
    (select b5 from t_alice_batches),
    (select ny_bucket from t_hours)),
  '23001',
  null,
  'a banked figure cannot be revised downward'
);

select lives_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     values (%L, 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             %L, 950, 'device', 8, now(), 'epoch', 0) $$,
    (select b5 from t_alice_batches),
    (select ny_bucket from t_hours)),
  'but it can be revised upward, which is what a late sync looks like'
);

select is(
  (select count(*) from public.metric_snapshots
   where user_id = '11111111-1111-1111-1111-111111111111'
     and bucket_start = (select ny_bucket from t_hours)),
  2::bigint,
  'and the revision appended rather than overwriting: both observations survive'
);

-- A single statement inserting a decrease alongside an increase must not get
-- past the trigger by ordering — rows written earlier in the same statement are
-- visible to it.
select throws_ok(
  format($$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour)
     select %L, 'a0000001-0000-0000-0000-000000000001',
            '11111111-1111-1111-1111-111111111111', 'distance_meters',
            %L, v, 'device', 1, now(), 'epoch', 0
     from (values (5000::numeric), (10::numeric)) as t(v) $$,
    (select b6 from t_alice_batches),
    (select ny_bucket from t_hours)),
  '23001',
  null,
  'a decrease cannot be smuggled in behind an increase in one statement'
);

-- ---------------------------------------------------------------------------
-- Admissibility
-- ---------------------------------------------------------------------------
-- The client reports what HealthKit told it and the server decides what counts.
-- A hand-typed figure is stored, because the attempt is itself a fact about the
-- participant, and it is never admissible.
insert into public.metric_snapshots
  (batch_id, contest_id, user_id, metric, bucket_start, value,
   provenance, sample_count, observed_at, local_day, local_hour)
select pg_temp.new_batch('11111111-1111-1111-1111-111111111111', 'manual'),
       'a0000001-0000-0000-0000-000000000001',
       '11111111-1111-1111-1111-111111111111', 'exercise_minutes',
       ny_bucket, 20000, 'manual', 1, now(), 'epoch', 0
from t_hours;

-- Scoped to this suite's contest. The seed carries a hand-typed observation of
-- its own, deliberately, so an unscoped count here would be counting it.
select is(
  (select count(*) from public.metric_snapshots
   where provenance = 'manual'
     and contest_id = 'a0000001-0000-0000-0000-000000000001'),
  1::bigint,
  'a hand-typed observation is stored rather than refused'
);

select is(
  (select is_admissible from public.metric_snapshots
   where provenance = 'manual'
     and contest_id = 'a0000001-0000-0000-0000-000000000001'),
  false,
  'and it is inadmissible'
);

select is(
  (select bool_and(is_admissible) from public.metric_snapshots
   where provenance in ('device', 'third_party')
     and contest_id = 'a0000001-0000-0000-0000-000000000001'),
  true,
  'device and third-party observations are admissible'
);

-- Generated, so there is no way to store a row whose flag disagrees with the
-- provenance it derives from.
select throws_ok(
  $$ insert into public.metric_snapshots
       (batch_id, contest_id, user_id, metric, bucket_start, value,
        provenance, sample_count, observed_at, local_day, local_hour,
        is_admissible)
     values (gen_random_uuid(), 'a0000001-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'steps',
             now(), 1, 'manual', 1, now(), 'epoch', 0, true) $$,
  '428C9',
  null,
  'is_admissible cannot be written: it is generated from provenance'
);

-- ---------------------------------------------------------------------------
-- Append-only
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.metric_snapshots set value = 99999 $$,
  '23001',
  null,
  'the ledger refuses UPDATE, even to superuser'
);

select throws_ok(
  $$ update public.ingest_batches set observation_count = 99 $$,
  '23001',
  null,
  'and so does the batch record'
);

-- ---------------------------------------------------------------------------
-- The trap: append-only must not make an account undeletable (D34)
-- ---------------------------------------------------------------------------
-- A referential action is a real statement. This ledger cascades from
-- ingest_batches, which cascades from contest_participants, which cascades from
-- profiles, which cascades from auth.users — so deleting an account issues a
-- genuine DELETE here. A blanket BEFORE DELETE prohibition would refuse it and
-- take the account deletion down with it, which is precisely the bug that had
-- been live in M1 since it shipped.
--
-- This assertion is the regression guard. If someone adds a DELETE trigger to
-- metric_snapshots later, believing append-only demands one, this fails.
select isnt_empty(
  $$ select 1 from public.metric_snapshots
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'alice has banked evidence before the deletion'
);

select lives_ok(
  $$ delete from auth.users where id = '11111111-1111-1111-1111-111111111111' $$,
  'an account with banked evidence can still be deleted'
);

select is_empty(
  $$ select 1 from public.metric_snapshots
     where user_id = '11111111-1111-1111-1111-111111111111' $$,
  'and the cascade reached the ledger'
);

-- Bob is untouched, so the cascade was scoped rather than a truncation.
select isnt_empty(
  $$ select 1 from public.metric_snapshots
     where user_id = '22222222-2222-2222-2222-222222222222' $$,
  'the other participant''s evidence survived'
);

select * from finish();
rollback;
