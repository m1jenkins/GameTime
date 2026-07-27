-- M5: retroactive evidence is flagged for review without being silently
-- disqualified. Threshold judgment is TypeScript's; this suite proves the
-- durable quarantine workflow and the unchanged evidence semantics.

begin;
select plan(36);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), -- alice, evidence owner
  ('22222222-2222-2222-2222-222222222222'), -- bob, opponent/reviewer
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
  'Late Sync Review', '11111111-1111-1111-1111-111111111111',
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

create temporary table t_fixture as
select
  gen_random_uuid() as batch_id,
  gen_random_uuid() as snapshot_id,
  date_trunc('hour', now()) - interval '5 days' as bucket_start;

insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, attested, payload_digest,
  observation_count, observed_at
) values (
  (select batch_id from t_fixture),
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  gen_random_uuid(), false, extensions.digest('late-batch', 'sha256'),
  1, now()
);

insert into public.metric_snapshots (
  id, batch_id, contest_id, user_id, metric, bucket_start, local_day, local_hour,
  value, provenance, sample_count, observed_at, recorded_at
) values (
  (select snapshot_id from t_fixture),
  (select batch_id from t_fixture),
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'steps', (select bucket_start from t_fixture), current_date, 0,
  20000, 'device', 20, now(), now()
);

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------

select has_table(
  'public', 'evidence_quarantines',
  'retroactive quarantines have durable state'
);
select has_column(
  'public', 'evidence_quarantines', 'required_reviewer_count',
  'each quarantine snapshots its immutable review denominator'
);
select has_table(
  'public', 'evidence_quarantine_reviews',
  'and reviews are a separate append-only ledger'
);
select has_view(
  'public', 'evidence_quarantine_status',
  'review state is computed rather than overwritten'
);
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.evidence_quarantines'::regclass),
  'quarantines have RLS enabled'
);
select ok(
  not has_table_privilege('authenticated', 'public.evidence_quarantines', 'insert')
  and not has_table_privilege('authenticated', 'public.evidence_quarantines', 'update')
  and not has_table_privilege('authenticated', 'public.evidence_quarantines', 'delete'),
  'clients cannot create, rewrite, or delete quarantine facts'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.evidence_quarantine_reviews', 'insert'
  ),
  'clients cannot bypass review eligibility with a direct insert'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_evidence_quarantine(uuid,text,text,bigint,jsonb)',
    'execute'
  ),
  'only the trusted evaluator can record a quarantine'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.record_evidence_quarantine(uuid,text,text,bigint,jsonb)',
    'execute'
  ),
  'the evaluator reaches quarantine creation as service_role'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.review_evidence_quarantine(uuid,boolean)',
    'execute'
  ),
  'signed-in participants can use the guarded review function'
);
select ok(
  not has_table_privilege(
    'service_role', 'public.evidence_quarantines', 'insert'
  )
  and not has_table_privilege(
    'service_role', 'public.evidence_quarantines', 'update'
  )
  and not has_table_privilege(
    'service_role', 'public.evidence_quarantines', 'delete'
  )
  and not has_table_privilege(
    'service_role', 'public.evidence_quarantine_reviews', 'insert'
  )
  and not has_function_privilege(
    'service_role',
    'public.review_evidence_quarantine(uuid,boolean)',
    'execute'
  ),
  'service_role must use the recorder and cannot forge review state directly'
);

-- ---------------------------------------------------------------------------
-- Recording a flag never changes evidence
-- ---------------------------------------------------------------------------

create temporary table t_quarantine as
select public.record_evidence_quarantine(
  (select snapshot_id from t_fixture),
  'm5-v1',
  'steps:' || (select bucket_start::text from t_fixture),
  (3 * 86400000)::bigint,
  '{"disposition":"review_required","evidenceStillScores":true}'::jsonb
) as id;

select is(
  (select count(*) from public.evidence_quarantines
   where id = (select id from t_quarantine)),
  1::bigint,
  'a qualifying late observation gets one quarantine row'
);
select ok(
  (select reporting_lag_ms >= threshold_ms
   from public.evidence_quarantines
   where id = (select id from t_quarantine)),
  'reporting lag is derived by the server and meets the recorded threshold'
);
select is(
  (select user_id from public.evidence_quarantines
   where id = (select id from t_quarantine)),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'the evidence owner is copied from the snapshot, not trusted from a caller'
);
select is(
  (select is_admissible from public.metric_snapshots
   where id = (select snapshot_id from t_fixture)),
  true,
  'quarantine does not rewrite generated admissibility'
);
select is(
  (select value from public.contest_evidence
   where contest_id = 'a0000001-0000-0000-0000-000000000001'
     and user_id = '11111111-1111-1111-1111-111111111111'
     and metric = 'steps'
     and bucket_start = (select bucket_start from t_fixture)),
  20000::numeric,
  'and the exact same value remains in the M4 scoring view'
);
select is(
  (select state from public.evidence_quarantine_status
   where id = (select id from t_quarantine)),
  'pending'::public.evidence_quarantine_state,
  'silence leaves retroactive evidence visibly pending'
);
select is(
  (select approvals_required from public.evidence_quarantine_status
   where id = (select id from t_quarantine)),
  1,
  'a duel requires its one opponent'
);

select is(
  public.record_evidence_quarantine(
    (select snapshot_id from t_fixture),
    'm5-v1',
    'steps:' || (select bucket_start::text from t_fixture),
    (3 * 86400000)::bigint,
    '{"disposition":"review_required","evidenceStillScores":true}'::jsonb
  ),
  (select id from t_quarantine),
  'retrying the identical evaluator write is idempotent'
);
select ok(
  (
    select count(*) = 1
       and bool_and(
         recipient_user_id = '22222222-2222-2222-2222-222222222222'
       )
    from public.notification_intents
    where event_type = 'quarantine_review_requested'
      and entity_id = (select id from t_quarantine)
  ),
  'the quarantine and its one opponent-review intent are idempotent together'
);
select throws_ok(
  $$ select public.record_evidence_quarantine(
       (select snapshot_id from t_fixture), 'm5-v1', 'different-signal',
       (3 * 86400000)::bigint, '{}'::jsonb) $$,
  '23505',
  null,
  'the same rule version cannot silently change what it claimed'
);
select throws_ok(
  $$ select public.record_evidence_quarantine(
       (select snapshot_id from t_fixture), 'too-high', 'late',
       (10 * 86400000)::bigint, '{}'::jsonb) $$,
  '22023',
  null,
  'a threshold the observation did not cross cannot manufacture a quarantine'
);

-- ---------------------------------------------------------------------------
-- Review eligibility and immutable votes
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (select id from t_quarantine), true) $$,
  '42501',
  null,
  'the evidence owner cannot approve their own retroactive evidence'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (select id from t_quarantine), true) $$,
  '42501',
  null,
  'an unrelated account cannot review it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (select id from t_quarantine), true) $$,
  'the accepted opponent can approve it'
);
select is(
  (select state from public.evidence_quarantine_status
   where id = (select id from t_quarantine)),
  'approved'::public.evidence_quarantine_state,
  'one opponent approval resolves a duel quarantine'
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (select id from t_quarantine), true) $$,
  'retrying the same vote is idempotent'
);
select ok(
  (
    select count(*) = 1
       and bool_and(
         recipient_user_id = '11111111-1111-1111-1111-111111111111'
       )
    from public.notification_intents
    where event_type = 'quarantine_review_resolved'
      and entity_id = (select id from t_quarantine)
  ),
  'approval and its one subject-resolution intent are idempotent together'
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (select id from t_quarantine), false) $$,
  '23001',
  null,
  'a reviewer cannot reverse a recorded vote'
);

reset role;
select throws_ok(
  $$ update public.evidence_quarantines
     set rule_version = 'rewritten'
     where id = (select id from t_quarantine) $$,
  '23001',
  null,
  'quarantine facts are immutable even to a privileged writer'
);
select throws_ok(
  $$ update public.evidence_quarantine_reviews
     set approved = false
     where quarantine_id = (select id from t_quarantine) $$,
  '23001',
  null,
  'review votes are immutable even to a privileged writer'
);

-- ---------------------------------------------------------------------------
-- RLS visibility follows the evidence ledger
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
select is(
  (select count(*) from public.evidence_quarantines),
  1::bigint,
  'the evidence owner sees the quarantine'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (select count(*) from public.evidence_quarantines),
  0::bigint,
  'their accepted opponent cannot bypass the bounded review surface'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select is(
  (select count(*) from public.evidence_quarantines),
  0::bigint,
  'an unrelated account cannot enumerate integrity flags'
);
reset role;

select lives_ok(
  $$ select public.delete_account(
       '22222222-2222-2222-2222-222222222222'::uuid
     ) $$,
  'reviewer account deletion retains a pseudonymous quarantine vote'
);
select ok(
  (select count(*) = 1
   from public.evidence_quarantine_reviews
   where quarantine_id = (select id from t_quarantine))
  and
  (select reviewer_count = 1
          and state = 'approved'::public.evidence_quarantine_state
   from public.evidence_quarantine_status
   where id = (select id from t_quarantine)),
  'account deletion cannot shrink the denominator or reopen approval'
);

select * from finish();
rollback;
