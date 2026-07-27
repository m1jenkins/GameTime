-- M5: source reputation reads M3 provenance metadata beside scoring evidence.
-- Known, unrecognized, missing, and malformed third-party identifiers all
-- remain admissible; the TypeScript integrity sidecar decides their penalties.

begin;
select plan(23);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), -- alice, evidence owner
  ('22222222-2222-2222-2222-222222222222'), -- bob, opponent
  ('33333333-3333-3333-3333-333333333333'); -- carol, unrelated

insert into public.profiles (id, handle, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'alice', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'bob',   'Bob'),
  ('33333333-3333-3333-3333-333333333333', 'carol', 'Carol');

insert into public.charities (id, name, ein, slug) values
  ('c0000001-0000-0000-0000-000000000001',
   'Trail Fund', '12-3456789', 'trail-fund');

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values (
  'a0000001-0000-0000-0000-000000000001',
  'Source Reputation', '11111111-1111-1111-1111-111111111111',
  'steps', 'cumulative', 10000, 2500,
  date_trunc('hour', now()) - interval '6 days',
  date_trunc('hour', now()) + interval '1 day',
  4
);

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants
  (contest_id, user_id, status, invited_by, timezone, charity_id) values
  ('a0000001-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'accepted', null,
   'UTC', 'c0000001-0000-0000-0000-000000000001'),
  ('a0000001-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'invited',
   '11111111-1111-1111-1111-111111111111', null, null);

update public.contest_participants
set status = 'accepted', timezone = 'UTC',
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where contest_id = 'a0000001-0000-0000-0000-000000000001'
  and user_id = '22222222-2222-2222-2222-222222222222';

update public.contests
set status = 'active', activated_at = now()
where id = 'a0000001-0000-0000-0000-000000000001';

create temporary table t_sources (
  label            text primary key,
  snapshot_id      uuid not null,
  batch_id         uuid not null,
  bucket_start     timestamptz not null,
  value            numeric not null,
  provenance       public.metric_provenance not null,
  source_bundle_id text
);

insert into t_sources values
  ('device',       gen_random_uuid(), gen_random_uuid(),
   date_trunc('hour', now()) - interval '5 days',             100,
   'device',      'com.apple.health'),
  ('known',        gen_random_uuid(), gen_random_uuid(),
   date_trunc('hour', now()) - interval '5 days' + interval '1 hour', 200,
   'third_party', 'com.strava.stravaride'),
  ('unrecognized', gen_random_uuid(), gen_random_uuid(),
   date_trunc('hour', now()) - interval '5 days' + interval '2 hours', 300,
   'third_party', 'com.example.unreviewed'),
  ('missing',      gen_random_uuid(), gen_random_uuid(),
   date_trunc('hour', now()) - interval '5 days' + interval '3 hours', 400,
   'third_party', null),
  ('malformed',    gen_random_uuid(), gen_random_uuid(),
   date_trunc('hour', now()) - interval '5 days' + interval '4 hours', 500,
   'third_party', 'not a bundle id');

insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, attested, payload_digest,
  observation_count, observed_at
)
select
  batch_id,
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  gen_random_uuid(),
  false,
  extensions.digest(label, 'sha256'),
  1,
  now()
from t_sources;

insert into public.metric_snapshots (
  id, batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, source_bundle_id, observed_at, recorded_at
)
select
  snapshot_id,
  batch_id,
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'steps',
  bucket_start,
  current_date,
  0,
  value,
  provenance,
  4,
  source_bundle_id,
  now(),
  now()
from t_sources;

-- A second observation with the same current value and source is a retry-like
-- revision. The ledger keeps it; both sidecar views reduce it deterministically.
create temporary table t_retry as
select gen_random_uuid() as batch_id, gen_random_uuid() as snapshot_id;

insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, attested, payload_digest,
  observation_count, observed_at
) values (
  (select batch_id from t_retry),
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  gen_random_uuid(), false, extensions.digest('source-retry', 'sha256'),
  1, now()
);

insert into public.metric_snapshots (
  id, batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, source_bundle_id, observed_at, recorded_at
)
select
  (select snapshot_id from t_retry),
  (select batch_id from t_retry),
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'steps',
  bucket_start,
  current_date,
  0,
  value,
  provenance,
  4,
  source_bundle_id,
  now(),
  now()
from t_sources
where label = 'unrecognized';

-- ---------------------------------------------------------------------------
-- Shape and least privilege
-- ---------------------------------------------------------------------------

select has_view(
  'public', 'contest_evidence_sources',
  'source reputation has a dedicated M3 metadata sidecar'
);
select ok(
  (select 'security_invoker=true' = any(reloptions)
   from pg_class where oid = 'public.contest_evidence_sources'::regclass),
  'the source sidecar invokes metric_snapshots RLS'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.contest_evidence_sources', 'select'
  ),
  'authenticated participants may read visible source metadata'
);
select ok(
  not has_table_privilege('anon', 'public.contest_evidence_sources', 'select'),
  'anonymous callers cannot read source metadata'
);

-- ---------------------------------------------------------------------------
-- Every source shape remains evidence
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from public.contest_evidence_sources
   where contest_id = 'a0000001-0000-0000-0000-000000000001'),
  5::bigint,
  'five current provenance contributions produce five sidecar rows'
);
select is(
  (select source_bundle_id from public.contest_evidence_sources
   where bucket_start = (select bucket_start from t_sources where label = 'known')),
  'com.strava.stravaride'::text,
  'a reviewed bundle identifier is preserved exactly'
);
select is(
  (select source_bundle_id from public.contest_evidence_sources
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  'com.example.unreviewed'::text,
  'an unknown but well-formed bundle identifier is preserved'
);
select is(
  (select source_bundle_id from public.contest_evidence_sources
   where bucket_start = (select bucket_start from t_sources where label = 'missing')),
  null::text,
  'missing source attribution stays explicitly null'
);
select is(
  (select source_bundle_id from public.contest_evidence_sources
   where bucket_start = (
     select bucket_start from t_sources where label = 'malformed'
   )),
  'not a bundle id'::text,
  'malformed syntax remains visible for TypeScript to flag'
);
select is(
  (select provenance from public.contest_evidence_sources
   where bucket_start = (select bucket_start from t_sources where label = 'device')),
  'device'::public.metric_provenance,
  'device and third-party provenance stay distinguishable'
);
select ok(
  (select bool_and(snapshot.is_admissible)
   from public.metric_snapshots snapshot
   join t_sources source on source.snapshot_id = snapshot.id),
  'known, unrecognized, missing, malformed, and device rows remain admissible'
);
select is(
  (select count(*) from public.contest_evidence
   where contest_id = 'a0000001-0000-0000-0000-000000000001'),
  5::bigint,
  'source reputation removes no rows from contest_evidence'
);
select is(
  (select sum(value) from public.contest_evidence
   where contest_id = 'a0000001-0000-0000-0000-000000000001'),
  1500::numeric,
  'and it changes none of the values M4 scores'
);

-- ---------------------------------------------------------------------------
-- Deterministic retries
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from public.contest_evidence_sources
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  1::bigint,
  'an identical current observation does not duplicate the source signal'
);
select is(
  (select source_bundle_id from public.contest_evidence_sources
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  'com.example.unreviewed'::text,
  'the retry resolves to the same source identifier'
);
select is(
  (select count(*) from public.metric_snapshots
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  2::bigint,
  'the append-only ledger still retains both observations'
);
select is(
  (select observation_count from public.contest_evidence
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  2,
  'the scoring view reports both observations without double-counting the value'
);
select is(
  (select value from public.contest_evidence
   where bucket_start = (
     select bucket_start from t_sources where label = 'unrecognized'
   )),
  300::numeric,
  'the retry leaves the scored value deterministic'
);
select isnt_empty(
  $$ select 1 from public.contest_evidence
     where bucket_start = (
       select bucket_start from t_sources where label = 'malformed'
     ) $$,
  'malformed third-party source evidence still scores'
);
select isnt_empty(
  $$ select 1 from public.contest_evidence
     where bucket_start = (
       select bucket_start from t_sources where label = 'missing'
     ) $$,
  'missing third-party source evidence still scores'
);

-- ---------------------------------------------------------------------------
-- RLS follows the evidence ledger
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select is_empty(
  $$ select 1 from public.contest_evidence_sources
     where contest_id = 'a0000001-0000-0000-0000-000000000001' $$,
  'an unrelated account cannot enumerate source reputation metadata'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (select count(*) from public.contest_evidence_sources
   where contest_id = 'a0000001-0000-0000-0000-000000000001'),
  0::bigint,
  'an accepted opponent cannot inspect source identifiers'
);
select is(
  (select count(*) from public.contest_evidence
   where contest_id = 'a0000001-0000-0000-0000-000000000001'),
  0::bigint,
  'or bypass D77 through the hourly scoring view'
);
reset role;

select * from finish();
rollback;
