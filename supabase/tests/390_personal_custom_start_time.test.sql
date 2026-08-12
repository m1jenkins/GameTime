-- Personal V1 chosen start day and hour: the default is unchanged, a chosen
-- start may also mean now on the current local date, and the seven scored
-- local dates still contain every expected coverage bucket.

begin;
select plan(21);

insert into auth.users (id) values
  ('ec111111-1111-1111-1111-111111111111'), -- omitted start, unchanged default
  ('ec222222-2222-2222-2222-222222222222'), -- chosen mid-afternoon start
  ('ec333333-3333-3333-3333-333333333333'), -- half-hour zone alignment
  ('ec444444-4444-4444-4444-444444444444'), -- refusals and retry identity
  ('ec555555-5555-5555-5555-555555555555'); -- start now and count today

insert into public.profiles (id, handle, display_name, timezone) values
  ('ec111111-1111-1111-1111-111111111111', 'csdefault', 'CS Default', 'UTC'),
  ('ec222222-2222-2222-2222-222222222222', 'cschosen', 'CS Chosen', 'UTC'),
  ('ec333333-3333-3333-3333-333333333333', 'cskolkata', 'CS Kolkata', 'Asia/Kolkata'),
  ('ec444444-4444-4444-4444-444444444444', 'csrefuse', 'CS Refuse', 'UTC'),
  ('ec555555-5555-5555-5555-555555555555', 'csnow', 'CS Now', 'UTC');

-- Every expectation is derived from the clock the suite runs on, so the
-- assertions hold on any day rather than only on the day they were written.
create function pg_temp.utc_local_date()
returns date
language sql
stable
as $$ select (now() at time zone 'UTC')::date $$;

create function pg_temp.utc_instant(p_date date, p_hours integer)
returns timestamptz
language sql
stable
as $$
  select (p_date::timestamp + (p_hours * interval '1 hour'))
           at time zone 'UTC'
$$;

-- ---------------------------------------------------------------------------
-- An omitted start is exactly what it was before the parameter existed
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec111111-1111-1111-1111-111111111111"}',
  true
);

create temporary table t_default as
select public.create_personal_challenge_v1(
  'ec100000-0000-0000-0000-000000000001',
  'daily', 10000, 1000, 'UTC'
) as id;

reset role;

select is(
  (select starts_at from public.contests where id = (select id from t_default)),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 1, 0),
  'an omitted start still opens at the next local midnight'
);

select is(
  (select ends_at from public.contests where id = (select id from t_default)),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 8, 0),
  'an omitted start still closes seven local dates later'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  public.create_personal_challenge_v1(
    'ec100000-0000-0000-0000-000000000001',
    'daily', 10000, 1000, 'UTC'
  ),
  (select id from t_default),
  'an omitted-start retry still hashes to the same committed request'
);

reset role;

-- ---------------------------------------------------------------------------
-- Start now activates immediately and scores from today's local midnight
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec555555-5555-5555-5555-555555555555"}',
  true
);

create temporary table t_start_now as
select
  date_trunc('minute', now()) as requested_at,
  public.create_personal_challenge_v2(
    'ec500000-0000-0000-0000-000000000001',
    'daily', 10000, 1000, 'UTC', date_trunc('minute', now())
  ) as id;

reset role;

select is(
  (select starts_at from public.contests where id = (select id from t_start_now)),
  pg_temp.utc_instant(pg_temp.utc_local_date(), 0),
  'start now opens the scored window at today''s local midnight'
);

select is(
  (select ends_at from public.contests where id = (select id from t_start_now)),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 7, 0),
  'start now still closes after seven scored local dates'
);

select is(
  (select status::text from public.contests where id = (select id from t_start_now)),
  'active',
  'start now activates the challenge before creation returns'
);

select is(
  (
    select terms.step_data_policy::text
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select id from t_start_now)
  ),
  'healthkit_nonmanual_daily_v1',
  'main-mode start now freezes the current Health snapshot policy'
);

select is(
  (
    select min(bucket.bucket_start)
    from app.personal_expected_coverage_buckets_v1(
      (select id from t_start_now),
      'infinity'::timestamptz
    ) bucket
  ),
  pg_temp.utc_instant(pg_temp.utc_local_date(), 0),
  'start now expects coverage beginning at midnight so earlier steps can count'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec555555-5555-5555-5555-555555555555"}',
  true
);

select is(
  public.create_personal_challenge_v2(
    'ec500000-0000-0000-0000-000000000001',
    'daily', 10000, 1000, 'UTC',
    (select requested_at from t_start_now)
  ),
  (select id from t_start_now),
  'an exact start-now retry returns the same active challenge'
);

reset role;

-- ---------------------------------------------------------------------------
-- A chosen future whole hour
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec222222-2222-2222-2222-222222222222"}',
  true
);

create temporary table t_chosen as
select public.create_personal_challenge_v1(
  'ec200000-0000-0000-0000-000000000001',
  'daily', 10000, 1000, 'UTC',
  pg_temp.utc_instant(pg_temp.utc_local_date() + 2, 15)
) as id;

reset role;

select is(
  (select starts_at from public.contests where id = (select id from t_chosen)),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 2, 15),
  'a chosen start opens the window on exactly that instant'
);

select is(
  (select ends_at from public.contests where id = (select id from t_chosen)),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 9, 0),
  'the seventh local date still closes at local midnight'
);

select is(
  (
    select terms.evidence_cutoff
    from public.personal_challenge_terms terms
    where terms.challenge_id = (select id from t_chosen)
  ),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 10, 0),
  'the frozen evidence cutoff stays 24 hours after the seventh day'
);

-- The first day is short, and that is the whole visible consequence.
select is(
  (
    select count(*)::integer
    from app.personal_expected_coverage_buckets_v1(
      (select id from t_chosen),
      'infinity'::timestamptz
    ) bucket
    where bucket.local_day = pg_temp.utc_local_date() + 2
  ),
  9,
  'a 15:00 start expects only the nine completed hours left in day one'
);

select is(
  (
    select min(bucket.bucket_start)
    from app.personal_expected_coverage_buckets_v1(
      (select id from t_chosen),
      'infinity'::timestamptz
    ) bucket
  ),
  pg_temp.utc_instant(pg_temp.utc_local_date() + 2, 15),
  'the first expected bucket is the chosen hour itself, not a partial one'
);

-- This is the invariant the migration rests on: every expected bucket falls
-- inside the seven local dates `app.personal_daily_progress_v1` generates, so
-- the aggregate coverage count cannot drift away from the per-day counts.
select is(
  (
    select array[count(*)::integer, count(distinct bucket.local_day)::integer]
    from app.personal_expected_coverage_buckets_v1(
      (select id from t_chosen),
      'infinity'::timestamptz
    ) bucket
  ),
  array[153, 7],
  'every expected bucket lands in exactly the seven scored local dates'
);

-- ---------------------------------------------------------------------------
-- Alignment is judged in the frozen timezone, not in UTC
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec333333-3333-3333-3333-333333333333"}',
  true
);

select ok(
  public.create_personal_challenge_v1(
    'ec300000-0000-0000-0000-000000000001',
    'cumulative', 70000, 1000, 'Asia/Kolkata',
    (
      ((now() at time zone 'Asia/Kolkata')::date + 2)::timestamp
        + interval '10 hours'
    ) at time zone 'Asia/Kolkata'
  ) is not null,
  'a whole local hour in a +05:30 zone is accepted though it is :30 in UTC'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'ec300000-0000-0000-0000-000000000002',
       'cumulative', 70000, 1000, 'Asia/Kolkata',
       (
         ((now() at time zone 'Asia/Kolkata')::date + 2)::timestamp
           + interval '10 hours 30 minutes'
       ) at time zone 'Asia/Kolkata'
     ) $$,
  '22023',
  null,
  'a whole UTC hour that is :30 locally is refused in a +05:30 zone'
);

reset role;

-- ---------------------------------------------------------------------------
-- Refusals and retry identity
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ec444444-4444-4444-4444-444444444444"}',
  true
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'ec400000-0000-0000-0000-000000000001',
       'daily', 10000, 1000, 'UTC',
       date_trunc('minute', now() - interval '1 day')
     ) $$,
  '22023',
  null,
  'a start from an earlier local date is refused'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'ec400000-0000-0000-0000-000000000002',
       'daily', 10000, 1000, 'UTC',
       (
         ((now() at time zone 'UTC')::date + 91)::timestamp
       ) at time zone 'UTC'
     ) $$,
  '22023',
  null,
  'a start beyond ninety days is refused'
);

create temporary table t_retry as
select public.create_personal_challenge_v1(
  'ec400000-0000-0000-0000-000000000003',
  'daily', 10000, 1000, 'UTC',
  pg_temp.utc_instant(pg_temp.utc_local_date() + 3, 8)
) as id;

select is(
  public.create_personal_challenge_v1(
    'ec400000-0000-0000-0000-000000000003',
    'daily', 10000, 1000, 'UTC',
    pg_temp.utc_instant(pg_temp.utc_local_date() + 3, 8)
  ),
  (select id from t_retry),
  'an exact retry of a chosen start returns the same challenge'
);

select throws_ok(
  $$ select public.create_personal_challenge_v1(
       'ec400000-0000-0000-0000-000000000003',
       'daily', 10000, 1000, 'UTC',
       (
         ((now() at time zone 'UTC')::date + 3)::timestamp + interval '9 hours'
       ) at time zone 'UTC'
     ) $$,
  '22023',
  null,
  'the same request UUID with a different start is refused, not silently reused'
);

reset role;

select * from finish();
rollback;
