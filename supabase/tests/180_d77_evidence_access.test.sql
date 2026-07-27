-- D77 / P0: raw health evidence is owner-only. A rival receives only the
-- bounded claim needed to review one pending quarantine in the exact contest
-- they accepted, with phase labels and identifying audit material removed.

begin;
select plan(47);

-- ---------------------------------------------------------------------------
-- API and policy shape
-- ---------------------------------------------------------------------------

select has_function(
  'public', 'list_my_evidence_quarantines', array['uuid'],
  'subjects have a contest-scoped quarantine status surface'
);
select has_function(
  'public', 'list_contest_quarantine_reviews', array['uuid'],
  'reviewers have a contest-scoped redacted inbox'
);
select has_function(
  'public', 'get_quarantine_revision_history', array['uuid'],
  'reviewers have a separately authorized redacted revision surface'
);

select ok(
  (select bool_and(routine.prosecdef)
   from pg_proc routine
   where routine.oid in (
     'public.list_my_evidence_quarantines(uuid)'::regprocedure,
     'public.list_contest_quarantine_reviews(uuid)'::regprocedure,
     'public.get_quarantine_revision_history(uuid)'::regprocedure
   )),
  'the bounded APIs can intentionally read through owner-only base RLS'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.list_my_evidence_quarantines(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_contest_quarantine_reviews(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_quarantine_revision_history(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.list_contest_quarantine_reviews(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.list_contest_quarantine_reviews(uuid)',
    'execute'
  ),
  'only authenticated clients execute the D77 read surfaces'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.evidence_quarantine_status',
    'select'
  )
  and has_table_privilege(
    'service_role',
    'public.evidence_quarantine_status',
    'select'
  ),
  'the full status view is trusted-code-only'
);

select set_eq(
  $$ select tablename || ':' || policyname || ':' || permissive || ':' || cmd
     from pg_policies
     where schemaname = 'public'
       and tablename in (
         'ingest_batches',
         'metric_snapshots',
         'evidence_quarantines',
         'evidence_quarantine_reviews'
       ) $$,
  array[
    'evidence_quarantine_reviews:active_actor_only:RESTRICTIVE:ALL',
    'evidence_quarantine_reviews:evidence_quarantine_reviews_select_own:PERMISSIVE:SELECT',
    'evidence_quarantines:active_actor_only:RESTRICTIVE:ALL',
    'evidence_quarantines:evidence_quarantines_select_own:PERMISSIVE:SELECT',
    'ingest_batches:active_actor_only:RESTRICTIVE:ALL',
    'ingest_batches:ingest_batches_select_own:PERMISSIVE:SELECT',
    'metric_snapshots:active_actor_only:RESTRICTIVE:ALL',
    'metric_snapshots:metric_snapshots_select_own:PERMISSIVE:SELECT'
  ],
  'raw audit policies are owner-only plus the restrictive active-actor guard'
);

-- ---------------------------------------------------------------------------
-- Cross-contest fixture
-- ---------------------------------------------------------------------------
-- A: Alice, Bob, Dave, and Erin share a live contest.
-- B: Alice and Carol share a different live contest.
-- C/D/E exercise awaiting-ingest, under-review, and finalized phases.

insert into auth.users (id) values
  ('81111111-1111-1111-1111-111111111111'), -- alice
  ('82222222-2222-2222-2222-222222222222'), -- bob
  ('83333333-3333-3333-3333-333333333333'), -- carol
  ('84444444-4444-4444-4444-444444444444'), -- dave
  ('85555555-5555-5555-5555-555555555555'); -- erin

insert into public.profiles (id, handle, display_name) values
  ('81111111-1111-1111-1111-111111111111', 'd77alice', 'D77 Alice'),
  ('82222222-2222-2222-2222-222222222222', 'd77bob',   'D77 Bob'),
  ('83333333-3333-3333-3333-333333333333', 'd77carol', 'D77 Carol'),
  ('84444444-4444-4444-4444-444444444444', 'd77dave',  'D77 Dave'),
  ('85555555-5555-5555-5555-555555555555', 'd77erin',  'D77 Erin');

insert into public.charities (id, name, ein, slug) values (
  '8c000001-0000-0000-0000-000000000001',
  'D77 Trail Fund',
  '98-7654321',
  'd77-trail-fund'
);

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id, title, created_by, metric, cadence, target_value, stake_amount_cents,
  starts_at, ends_at, max_participants
) values
  (
    '8a000001-0000-0000-0000-000000000001', 'D77 live A',
    '81111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 1000, 100,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) + interval '2 days', 8
  ),
  (
    '8a000002-0000-0000-0000-000000000002', 'D77 live B',
    '81111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 1000, 100,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) + interval '2 days', 8
  ),
  (
    '8a000003-0000-0000-0000-000000000003', 'D77 awaiting ingest',
    '81111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 1000, 100,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) - interval '1 hour', 8
  ),
  (
    '8a000004-0000-0000-0000-000000000004', 'D77 under review',
    '81111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 1000, 100,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) - interval '7 hours', 8
  ),
  (
    '8a000005-0000-0000-0000-000000000005', 'D77 finalized',
    '81111111-1111-1111-1111-111111111111',
    'steps', 'cumulative', 1000, 100,
    date_trunc('hour', now()) - interval '3 days',
    date_trunc('hour', now()) + interval '2 days', 8
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id, user_id, status, invited_by, timezone, charity_id
) values
  -- Alice authored and accepted every contest.
  ('8a000001-0000-0000-0000-000000000001',
   '81111111-1111-1111-1111-111111111111', 'accepted', null, 'UTC',
   '8c000001-0000-0000-0000-000000000001'),
  ('8a000002-0000-0000-0000-000000000002',
   '81111111-1111-1111-1111-111111111111', 'accepted', null, 'UTC',
   '8c000001-0000-0000-0000-000000000001'),
  ('8a000003-0000-0000-0000-000000000003',
   '81111111-1111-1111-1111-111111111111', 'accepted', null, 'UTC',
   '8c000001-0000-0000-0000-000000000001'),
  ('8a000004-0000-0000-0000-000000000004',
   '81111111-1111-1111-1111-111111111111', 'accepted', null, 'UTC',
   '8c000001-0000-0000-0000-000000000001'),
  ('8a000005-0000-0000-0000-000000000005',
   '81111111-1111-1111-1111-111111111111', 'accepted', null, 'UTC',
   '8c000001-0000-0000-0000-000000000001'),
  -- A's reviewers.
  ('8a000001-0000-0000-0000-000000000001',
   '82222222-2222-2222-2222-222222222222', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  ('8a000001-0000-0000-0000-000000000001',
   '84444444-4444-4444-4444-444444444444', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  ('8a000001-0000-0000-0000-000000000001',
   '85555555-5555-5555-5555-555555555555', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  -- B's reviewer.
  ('8a000002-0000-0000-0000-000000000002',
   '83333333-3333-3333-3333-333333333333', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  -- Bob also accepted C/D/E so each phase is independently authorized.
  ('8a000003-0000-0000-0000-000000000003',
   '82222222-2222-2222-2222-222222222222', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  ('8a000004-0000-0000-0000-000000000004',
   '82222222-2222-2222-2222-222222222222', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null),
  ('8a000005-0000-0000-0000-000000000005',
   '82222222-2222-2222-2222-222222222222', 'invited',
   '81111111-1111-1111-1111-111111111111', null, null);

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = '8c000001-0000-0000-0000-000000000001'
where status = 'invited'
  and contest_id between
    '8a000001-0000-0000-0000-000000000001'::uuid
    and '8a000005-0000-0000-0000-000000000005'::uuid;

update public.contests
set status = 'active', activated_at = now()
where id between
  '8a000001-0000-0000-0000-000000000001'::uuid
  and '8a000005-0000-0000-0000-000000000005'::uuid;

create or replace function pg_temp.add_d77_evidence(
  p_contest_id uuid,
  p_tag        text,
  p_value      numeric,
  p_recorded   timestamptz
)
returns uuid
language plpgsql
as $$
declare
  v_batch_id    uuid;
  v_snapshot_id uuid;
  v_bucket      timestamptz := date_trunc('hour', now()) - interval '2 days';
begin
  insert into public.ingest_batches (
    contest_id, user_id, client_batch_id, attested, payload_digest,
    observation_count, observed_at, recorded_at
  ) values (
    p_contest_id,
    '81111111-1111-1111-1111-111111111111',
    md5(p_tag)::uuid,
    false,
    extensions.digest('SECRET_PAYLOAD_' || p_tag, 'sha256'),
    1,
    p_recorded,
    p_recorded
  )
  returning id into v_batch_id;

  insert into public.metric_snapshots (
    batch_id, contest_id, user_id, metric, bucket_start,
    local_day, local_hour, value, provenance, sample_count,
    source_bundle_id, device_model, observed_at, recorded_at
  ) values (
    v_batch_id,
    p_contest_id,
    '81111111-1111-1111-1111-111111111111',
    'steps',
    v_bucket,
    (v_bucket at time zone 'UTC')::date,
    extract(hour from v_bucket at time zone 'UTC')::smallint,
    p_value,
    'third_party',
    7,
    'com.secret.source.' || p_tag,
    'SECRET_DEVICE_' || p_tag,
    p_recorded,
    p_recorded
  )
  returning id into v_snapshot_id;

  return v_snapshot_id;
end;
$$;

create temporary table t_d77_snapshots (
  label       text primary key,
  contest_id  uuid not null,
  snapshot_id uuid not null
);

insert into t_d77_snapshots values
  ('a1', '8a000001-0000-0000-0000-000000000001',
   pg_temp.add_d77_evidence(
     '8a000001-0000-0000-0000-000000000001',
     'A1', 100, now() - interval '30 minutes'
   )),
  ('a2', '8a000001-0000-0000-0000-000000000001',
   pg_temp.add_d77_evidence(
     '8a000001-0000-0000-0000-000000000001',
     'A2', 200, now() - interval '15 minutes'
   )),
  ('b', '8a000002-0000-0000-0000-000000000002',
   pg_temp.add_d77_evidence(
     '8a000002-0000-0000-0000-000000000002',
     'B', 300, now() - interval '15 minutes'
   )),
  ('c', '8a000003-0000-0000-0000-000000000003',
   pg_temp.add_d77_evidence(
     '8a000003-0000-0000-0000-000000000003',
     'C', 400, now() - interval '15 minutes'
   )),
  ('e', '8a000005-0000-0000-0000-000000000005',
   pg_temp.add_d77_evidence(
     '8a000005-0000-0000-0000-000000000005',
     'E', 600, now() - interval '15 minutes'
   ));

-- D deliberately models the post-grace/pre-finalization review state. New
-- evidence cannot arrive there; this fixture inserts the historical row that
-- would have arrived before grace closed.
alter table public.metric_snapshots disable trigger metric_snapshots_prepare;
insert into t_d77_snapshots values (
  'd',
  '8a000004-0000-0000-0000-000000000004',
  pg_temp.add_d77_evidence(
    '8a000004-0000-0000-0000-000000000004',
    'D', 500, now() - interval '8 hours'
  )
);
alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

create temporary table t_d77_quarantines as
select
  snapshot.label,
  snapshot.contest_id,
  snapshot.snapshot_id,
  public.record_evidence_quarantine(
    snapshot.snapshot_id,
    'm5-d77',
    'SECRET_SIGNAL_' || upper(snapshot.label),
    3600000,
    jsonb_build_object(
      'private_note',
      'SECRET_DETAILS_' || upper(snapshot.label)
    )
  ) as quarantine_id
from t_d77_snapshots snapshot
where snapshot.label in ('a2', 'b', 'c', 'd', 'e');

grant select on t_d77_quarantines to authenticated;

update public.contests
set status = 'finalized'
where id = '8a000005-0000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- Direct audit access
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (select count(*) = 2 from public.ingest_batches
   where contest_id = '8a000001-0000-0000-0000-000000000001')
  and
  (select count(*) = 2 from public.metric_snapshots
   where contest_id = '8a000001-0000-0000-0000-000000000001')
  and
  (select count(*) = 1 from public.evidence_quarantines
   where contest_id = '8a000001-0000-0000-0000-000000000001'),
  'Alice can inspect her raw audit rows in contest A'
);

select ok(
  (select count(*) = 1 from public.ingest_batches
   where contest_id = '8a000002-0000-0000-0000-000000000002')
  and
  (select count(*) = 1 from public.metric_snapshots
   where contest_id = '8a000002-0000-0000-0000-000000000002')
  and
  (select count(*) = 1 from public.evidence_quarantines
   where contest_id = '8a000002-0000-0000-0000-000000000002'),
  'and her independent raw audit rows in contest B'
);

select is(
  (select count(*) from public.contest_evidence
   where contest_id = '8a000001-0000-0000-0000-000000000001'),
  1::bigint,
  'the security-invoker scoring view remains available to its evidence owner'
);

select is(
  (select source_bundle_id from public.contest_evidence_sources
   where contest_id = '8a000001-0000-0000-0000-000000000001'),
  'com.secret.source.A2',
  'the evidence owner may inspect retained source attribution'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"82222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (select count(*) from public.ingest_batches
   where contest_id = '8a000001-0000-0000-0000-000000000001'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'Bob cannot directly read Alice batches from their shared contest A'
);
select is(
  (select count(*) from public.metric_snapshots
   where contest_id = '8a000001-0000-0000-0000-000000000001'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'Bob cannot directly read Alice hourly snapshots from A'
);
select is(
  (select count(*) from public.evidence_quarantines
   where contest_id = '8a000001-0000-0000-0000-000000000001'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'Bob cannot directly read Alice quarantine rows from A'
);

-- The P0 regression: sharing A must grant nothing from Alice's unrelated B.
select is(
  (select count(*) from public.ingest_batches
   where contest_id = '8a000002-0000-0000-0000-000000000002'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'sharing A does not expose Alice batches belonging to B'
);
select is(
  (select count(*) from public.metric_snapshots
   where contest_id = '8a000002-0000-0000-0000-000000000002'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'sharing A does not expose Alice hourly snapshots belonging to B'
);
select is(
  (select count(*) from public.evidence_quarantines
   where contest_id = '8a000002-0000-0000-0000-000000000002'
     and user_id = '81111111-1111-1111-1111-111111111111'),
  0::bigint,
  'sharing A does not expose Alice quarantine records belonging to B'
);

select is(
  (select count(*) from public.contest_evidence
   where contest_id in (
     '8a000001-0000-0000-0000-000000000001',
     '8a000002-0000-0000-0000-000000000002'
   )),
  0::bigint,
  'the aggregate hourly view is not a rival bypass'
);

select is(
  (select count(*) from public.contest_evidence_sources
   where contest_id in (
     '8a000001-0000-0000-0000-000000000001',
     '8a000002-0000-0000-0000-000000000002'
   )),
  0::bigint,
  'and neither is its source-identifier sidecar'
);

-- ---------------------------------------------------------------------------
-- Exact-contest subject and reviewer surfaces
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);
select is(
  (select count(*) from public.list_my_evidence_quarantines(
    '8a000001-0000-0000-0000-000000000001'
  )),
  1::bigint,
  'Alice sees her own quarantine status for A'
);
select is(
  (select count(*) from public.list_my_evidence_quarantines(
    '8a000002-0000-0000-0000-000000000002'
  )),
  1::bigint,
  'and sees B only when she requests B'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"82222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (select count(*) from public.list_my_evidence_quarantines(
    '8a000002-0000-0000-0000-000000000002'
  )),
  0::bigint,
  'Bob cannot turn the subject surface into cross-contest access'
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  1::bigint,
  'Bob receives the pending claim in accepted contest A'
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000002-0000-0000-0000-000000000002'
  )),
  0::bigint,
  'but requesting Alice contest B returns no claim'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"83333333-3333-3333-3333-333333333333"}',
  true
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000002-0000-0000-0000-000000000002'
  )),
  1::bigint,
  'Carol receives the pending claim in her accepted contest B'
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  0::bigint,
  'but Carol receives nothing from A'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  0::bigint,
  'the evidence subject is never treated as their own reviewer'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"82222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (select count(*) from public.get_quarantine_revision_history(
    (select quarantine_id from t_d77_quarantines where label = 'b')
  )),
  0::bigint,
  'guessing B''s quarantine UUID still returns no revision history'
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (select quarantine_id from t_d77_quarantines where label = 'b'),
       true
     ) $$,
  '42501',
  null,
  'sharing A cannot authorize a vote on Alice evidence from contest B'
);

-- ---------------------------------------------------------------------------
-- Phase-aware disclosure
-- ---------------------------------------------------------------------------

select is(
  (select phase from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  'live'::text,
  'an open contest labels its bounded claim live'
);
select is(
  (select phase from public.list_contest_quarantine_reviews(
    '8a000003-0000-0000-0000-000000000003'
  )),
  'awaiting_ingest'::text,
  'an ended contest inside ingest grace labels the claim awaiting_ingest'
);
select is(
  (select phase from public.list_contest_quarantine_reviews(
    '8a000004-0000-0000-0000-000000000004'
  )),
  'under_review'::text,
  'a post-grace pending claim is under_review'
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000005-0000-0000-0000-000000000005'
  )),
  0::bigint,
  'finalization closes the raw peer-review surface'
);

-- ---------------------------------------------------------------------------
-- Redaction and revision history
-- ---------------------------------------------------------------------------

select set_eq(
  $$ select jsonb_object_keys(to_jsonb(claim))
     from (
       select *
       from public.list_contest_quarantine_reviews(
         '8a000001-0000-0000-0000-000000000001'
       )
       limit 1
     ) claim $$,
  array[
    'bucket_start',
    'contest_id',
    'metric',
    'participant_id',
    'phase',
    'provenance',
    'quarantine_id',
    'recorded_at',
    'reporting_lag_ms',
    'revision_count',
    'rule_code',
    'rule_version',
    'threshold_ms',
    'value'
  ],
  'the reviewer inbox exposes exactly the bounded D77 claim fields'
);

select set_eq(
  $$ select jsonb_object_keys(to_jsonb(revision))
     from (
       select *
       from public.get_quarantine_revision_history(
         (select quarantine_id from t_d77_quarantines where label = 'a2')
       )
       limit 1
     ) revision $$,
  array[
    'bucket_start',
    'contest_id',
    'is_quarantined_revision',
    'metric',
    'participant_id',
    'phase',
    'provenance',
    'quarantine_id',
    'recorded_at',
    'reporting_lag_ms',
    'revision_number',
    'rule_code',
    'rule_version',
    'threshold_ms',
    'value'
  ],
  'revision history exposes no identifiers beyond the bounded claim'
);

select ok(
  (select jsonb_agg(value order by revision_number) = '[100, 200]'::jsonb
          and jsonb_agg(is_quarantined_revision order by revision_number)
              = '[false, true]'::jsonb
   from public.get_quarantine_revision_history(
     (select quarantine_id from t_d77_quarantines where label = 'a2')
   )),
  'the allowed history is ordered and identifies only the quarantined revision'
);

select ok(
  (select coalesce(string_agg(to_jsonb(claim)::text, ''), '')
            not like '%com.secret.source.%'
          and coalesce(string_agg(to_jsonb(claim)::text, ''), '')
            not like '%SECRET_DEVICE_%'
          and coalesce(string_agg(to_jsonb(claim)::text, ''), '')
            not like '%SECRET_SIGNAL_%'
          and coalesce(string_agg(to_jsonb(claim)::text, ''), '')
            not like '%SECRET_DETAILS_%'
   from public.list_contest_quarantine_reviews(
     '8a000001-0000-0000-0000-000000000001'
   ) claim)
  and
  (select coalesce(string_agg(to_jsonb(revision)::text, ''), '')
            not like '%com.secret.source.%'
          and coalesce(string_agg(to_jsonb(revision)::text, ''), '')
            not like '%SECRET_DEVICE_%'
          and coalesce(string_agg(to_jsonb(revision)::text, ''), '')
            not like '%SECRET_SIGNAL_%'
          and coalesce(string_agg(to_jsonb(revision)::text, ''), '')
            not like '%SECRET_DETAILS_%'
   from public.get_quarantine_revision_history(
     (select quarantine_id from t_d77_quarantines where label = 'a2')
   ) revision),
  'source, device, signal, and private-detail sentinels never cross the review API'
);

-- ---------------------------------------------------------------------------
-- The review window closes per caller and at terminal state
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.review_evidence_quarantine(
       (select quarantine_id from t_d77_quarantines where label = 'a2'),
       true
     ) $$,
  'Bob can vote on the visible pending claim'
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  0::bigint,
  'Bob loses the bounded evidence surface after casting his vote'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"84444444-4444-4444-4444-444444444444"}',
  true
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  1::bigint,
  'Dave still sees the claim while his vote is required'
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (select quarantine_id from t_d77_quarantines where label = 'a2'),
       true
     ) $$,
  'Dave can supply the approval that resolves the claim'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);
select ok(
  (select reviewer_count = 3
          and approvals_required = 2
          and approval_count = 2
          and state = 'approved'::public.evidence_quarantine_state
   from public.list_my_evidence_quarantines(
     '8a000001-0000-0000-0000-000000000001'
   )),
  'the subject sees correct aggregate approval state without reviewer identities'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"85555555-5555-5555-5555-555555555555"}',
  true
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (select quarantine_id from t_d77_quarantines where label = 'a2'),
       true
     ) $$,
  '23001',
  null,
  'a new reviewer vote is refused after the claim resolves'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"84444444-4444-4444-4444-444444444444"}',
  true
);
select is(
  (select count(*) from public.list_contest_quarantine_reviews(
    '8a000001-0000-0000-0000-000000000001'
  )),
  0::bigint,
  'resolved claims stay absent from every reviewer inbox'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"82222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (select count(*) from public.evidence_quarantine_reviews),
  1::bigint,
  'a reviewer can directly inspect only their own immutable vote'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111"}',
  true
);
select is(
  (select count(*) from public.evidence_quarantine_reviews),
  0::bigint,
  'the evidence subject cannot enumerate reviewer identities'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"82222222-2222-2222-2222-222222222222"}',
  true
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (select quarantine_id from t_d77_quarantines where label = 'a2'),
       true
     ) $$,
  'an identical retry remains idempotent after resolution'
);

reset role;
select * from finish();
rollback;
