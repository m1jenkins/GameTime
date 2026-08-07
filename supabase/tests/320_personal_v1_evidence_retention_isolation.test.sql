-- Personal V1 keeps flagged evidence in a service/operator workflow, never in
-- social peer review, and freezes completed progress before D81 raw pruning.

begin;
select plan(39);

set local timezone = 'UTC';

select has_table(
  'app', 'personal_quarantine_resolutions',
  'personal evidence flags have a dedicated terminal-resolution ledger'
);

select has_function(
  'public', 'resolve_personal_evidence_quarantine_v1',
  array['uuid', 'uuid', 'public.personal_quarantine_resolution', 'text', 'bytea'],
  'trusted personal flag resolution has a versioned RPC'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_personal_evidence_quarantine_v1(uuid,uuid,public.personal_quarantine_resolution,text,bytea)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.resolve_personal_evidence_quarantine_v1(uuid,uuid,public.personal_quarantine_resolution,text,bytea)',
    'execute'
  )
  and not has_table_privilege(
    'service_role', 'app.personal_quarantine_resolutions', 'select'
  ),
  'the resolution path is service-RPC-only with no direct table surface'
);

select ok(
  (
    select
      strpos(definition, 'if v_existing.id is not null then')
        < strpos(definition, 'perform app.consume_trusted_personal_assertion(')
      and strpos(
        split_part(
          definition,
          'perform app.consume_trusted_personal_assertion(',
          2
        ),
        'v_now := clock_timestamp();'
      ) > 0
      and strpos(
        split_part(
          definition,
          'perform app.consume_trusted_personal_assertion(',
          2
        ),
        'v_now >= v_terms.evidence_cutoff'
      ) > 0
    from (
      select pg_get_functiondef(
        'app.record_personal_sync_coverage_v1_unchecked(uuid,uuid,uuid,bytea,timestamptz,jsonb,bytea,bigint)'::regprocedure
      ) as definition
    ) source
  )
  and (
    select
      strpos(definition, 'if v_existing.id is not null then')
        < strpos(definition, 'perform app.consume_trusted_personal_assertion(')
      and strpos(
        split_part(
          definition,
          'perform app.consume_trusted_personal_assertion(',
          2
        ),
        'v_now := clock_timestamp();'
      ) > 0
      and strpos(
        split_part(
          definition,
          'perform app.consume_trusted_personal_assertion(',
          2
        ),
        'p_observed_at < v_now - interval ''15 minutes'''
      ) > 0
    from (
      select pg_get_functiondef(
        'app.record_trusted_personal_diagnostic_v1_unchecked(uuid,uuid,bytea,timestamptz,timestamptz,timestamptz,integer,bytea,bigint)'::regprocedure
      ) as definition
    ) source
  ),
  'coverage cutoff and diagnostic freshness are rechecked after the device lock while exact retries remain first'
);

select ok(
  obj_description(
    'public.personal_sync_coverage_buckets'::regclass,
    'pg_class'
  ) like '%retained derived fact%'
  and obj_description(
    'public.personal_trusted_diagnostics'::regclass,
    'pg_class'
  ) like '%retained derived facts%',
  'coverage keys and diagnostic aggregates are explicitly classified as retained derived audit facts'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.contype = 'f'
      and constraint_row.confrelid = 'public.device_attestations'::regclass
      and constraint_row.conrelid in (
        'public.personal_sync_coverage_batches'::regclass,
        'public.personal_trusted_diagnostics'::regclass
      )
  ),
  'retained personal audit facts keep a key fingerprint without pinning the operational device row'
);

insert into auth.users (id) values
  ('ac111111-1111-1111-1111-111111111111'),
  ('ac222222-2222-2222-2222-222222222222'),
  ('ac333333-3333-3333-3333-333333333333'),
  ('ac444444-4444-4444-4444-444444444444'),
  ('ac555555-5555-5555-5555-555555555555');

insert into public.profiles (id, handle, display_name, timezone) values
  ('ac111111-1111-1111-1111-111111111111', 'personalclear', 'Personal Clear', 'UTC'),
  ('ac222222-2222-2222-2222-222222222222', 'personalunresolved', 'Personal Unresolved', 'UTC'),
  ('ac333333-3333-3333-3333-333333333333', 'personallive', 'Personal Live', 'UTC'),
  ('ac444444-4444-4444-4444-444444444444', 'personaldeleting', 'Personal Deleting', 'UTC'),
  ('ac555555-5555-5555-5555-555555555555', 'personalactivedelete', 'Personal Active Delete', 'UTC');

create function pg_temp.make_personal(
  p_challenge_id uuid,
  p_user_id uuid,
  p_first_date date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_start timestamptz := p_first_date::timestamp at time zone 'UTC';
  v_end timestamptz := (p_first_date + 7)::timestamp at time zone 'UTC';
begin
  insert into public.contests (
    id, title, created_by, challenge_model, metric, cadence, target_value,
    stake_amount_cents, tie_break, starts_at, ends_at, max_participants
  ) values (
    p_challenge_id, 'Personal evidence isolation', p_user_id,
    'personal_accountability', 'steps', 'cumulative', 100,
    1000, 'void', v_start, v_end, 1
  );

  insert into public.contest_participants (
    contest_id, user_id, status, timezone, charity_id
  ) values (p_challenge_id, p_user_id, 'accepted', 'UTC', null);

  insert into public.personal_challenge_terms (
    challenge_id, user_id, cadence, target_steps,
    commitment_amount_minor, timezone, agreed_at, evidence_cutoff
  ) values (
    p_challenge_id, p_user_id, 'cumulative', 100,
    1000, 'UTC', v_start - interval '1 day', v_end + interval '24 hours'
  );
end;
$$;

alter table public.contests disable trigger contests_assert_future_window;

select pg_temp.make_personal(
  'ac000000-0000-0000-0000-000000000001',
  'ac111111-1111-1111-1111-111111111111',
  (clock_timestamp() at time zone 'UTC')::date - 9
);
select pg_temp.make_personal(
  'ac000000-0000-0000-0000-000000000002',
  'ac222222-2222-2222-2222-222222222222',
  (clock_timestamp() at time zone 'UTC')::date - 9
);
select pg_temp.make_personal(
  'ac000000-0000-0000-0000-000000000003',
  'ac333333-3333-3333-3333-333333333333',
  (clock_timestamp() at time zone 'UTC')::date - 1
);
select pg_temp.make_personal(
  'ac000000-0000-0000-0000-000000000004',
  'ac555555-5555-5555-5555-555555555555',
  (clock_timestamp() at time zone 'UTC')::date - 9
);

alter table public.contests enable trigger contests_assert_future_window;

create temporary table t_activation as
select * from app.activate_due_contests(clock_timestamp());

select is(
  (
    select count(*) from t_activation
    where outcome = 'active'
      and contest_id::text like 'ac000000-0000-0000-0000-00000000000%'
  ),
  4::bigint,
  'personal evidence fixtures activate with one owner each'
);

create temporary table t_keys as
select
  ('\x04' || repeat('c1', 64))::bytea as key1,
  extensions.digest(('\x04' || repeat('c1', 64))::bytea, 'sha256') as key1_id,
  ('\x04' || repeat('c2', 64))::bytea as key2,
  extensions.digest(('\x04' || repeat('c2', 64))::bytea, 'sha256') as key2_id,
  ('\x04' || repeat('c3', 64))::bytea as key3,
  extensions.digest(('\x04' || repeat('c3', 64))::bytea, 'sha256') as key3_id;

insert into public.device_attestations (key_id, user_id, public_key, environment)
select key1_id, 'ac111111-1111-1111-1111-111111111111'::uuid, key1, 'production'::public.attestation_environment from t_keys
union all
select key2_id, 'ac222222-2222-2222-2222-222222222222'::uuid, key2, 'production'::public.attestation_environment from t_keys
union all
select key3_id, 'ac333333-3333-3333-3333-333333333333'::uuid, key3, 'production'::public.attestation_environment from t_keys;

create function pg_temp.cover_all(
  p_challenge_id uuid,
  p_user_id uuid,
  p_key_id bytea,
  p_batch_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
  v_ends_at timestamptz;
begin
  select contest.ends_at into v_ends_at
  from public.contests contest where contest.id = p_challenge_id;

  select count(*)::integer into v_count
  from app.personal_expected_coverage_buckets_v1(p_challenge_id, 'infinity');

  insert into public.personal_sync_coverage_batches (
    id, challenge_id, user_id, client_coverage_id, key_id, sign_count,
    payload_digest, observed_at, covered_bucket_count
  ) values (
    p_batch_id, p_challenge_id, p_user_id, p_batch_id, p_key_id, 1,
    extensions.digest(p_batch_id::text, 'sha256'), v_ends_at, v_count
  );

  insert into public.personal_sync_coverage_buckets (
    coverage_batch_id, challenge_id, user_id, bucket_start
  )
  select p_batch_id, p_challenge_id, p_user_id, expected.bucket_start
  from app.personal_expected_coverage_buckets_v1(p_challenge_id, 'infinity') expected;
end;
$$;

select pg_temp.cover_all(
  'ac000000-0000-0000-0000-000000000001',
  'ac111111-1111-1111-1111-111111111111',
  (select key1_id from t_keys),
  'ac100000-0000-0000-0000-000000000001'
);
select pg_temp.cover_all(
  'ac000000-0000-0000-0000-000000000002',
  'ac222222-2222-2222-2222-222222222222',
  (select key2_id from t_keys),
  'ac200000-0000-0000-0000-000000000001'
);

insert into public.ingest_batches (
  id, contest_id, user_id, client_batch_id, key_id, sign_count, attested,
  payload_digest, observation_count, observed_at
) values
  (
    'ac100000-0000-0000-0000-000000000002',
    'ac000000-0000-0000-0000-000000000001',
    'ac111111-1111-1111-1111-111111111111',
    'ac100000-0000-0000-0000-000000000002',
    (select key1_id from t_keys), 1, true,
    extensions.digest('personal-clear-ingest', 'sha256'), 1,
    clock_timestamp()
  ),
  (
    'ac200000-0000-0000-0000-000000000002',
    'ac000000-0000-0000-0000-000000000002',
    'ac222222-2222-2222-2222-222222222222',
    'ac200000-0000-0000-0000-000000000002',
    (select key2_id from t_keys), 1, true,
    extensions.digest('personal-unresolved-ingest', 'sha256'), 2,
    clock_timestamp()
  ),
  (
    'ac300000-0000-0000-0000-000000000002',
    'ac000000-0000-0000-0000-000000000003',
    'ac333333-3333-3333-3333-333333333333',
    'ac300000-0000-0000-0000-000000000002',
    (select key3_id from t_keys), 1, true,
    extensions.digest('personal-live-ingest', 'sha256'), 1,
    clock_timestamp()
  );

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  id, batch_id, contest_id, user_id, metric, bucket_start,
  local_day, local_hour, value, provenance, sample_count,
  observed_at, recorded_at
)
select
  'ac110000-0000-0000-0000-000000000001',
  'ac100000-0000-0000-0000-000000000002', contest.id,
  'ac111111-1111-1111-1111-111111111111', 'steps', contest.starts_at,
  (contest.starts_at at time zone 'UTC')::date, 0, 100, 'device', 1,
  contest.ends_at, clock_timestamp()
from public.contests contest
where contest.id = 'ac000000-0000-0000-0000-000000000001';

insert into public.metric_snapshots (
  id, batch_id, contest_id, user_id, metric, bucket_start,
  local_day, local_hour, value, provenance, sample_count,
  observed_at, recorded_at
)
select
  snapshot_id, 'ac200000-0000-0000-0000-000000000002', contest.id,
  'ac222222-2222-2222-2222-222222222222', 'steps',
  contest.starts_at + hour_offset * interval '1 hour',
  (contest.starts_at at time zone 'UTC')::date,
  hour_offset::smallint, case when hour_offset = 0 then 60 else 40 end,
  'device', 1, contest.ends_at, clock_timestamp()
from public.contests contest
cross join (
  values
    (0, 'ac220000-0000-0000-0000-000000000001'::uuid),
    (1, 'ac220000-0000-0000-0000-000000000002'::uuid)
) fixture(hour_offset, snapshot_id)
where contest.id = 'ac000000-0000-0000-0000-000000000002';

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

select throws_ok(
  $$ insert into public.metric_snapshots (
       batch_id, contest_id, user_id, metric, bucket_start,
       local_day, local_hour, value, provenance, sample_count, observed_at
     )
     select
       'ac300000-0000-0000-0000-000000000002', contest.id,
       'ac333333-3333-3333-3333-333333333333', 'steps', contest.starts_at,
       (contest.starts_at at time zone 'UTC')::date, 0, 100,
       'third_party', 1, clock_timestamp()
     from public.contests contest
     where contest.id = 'ac000000-0000-0000-0000-000000000003' $$,
  '23001',
  'personal accountability accepts first-party device evidence only',
  'an attested personal upload still cannot score third-party provenance'
);

create temporary table t_quarantines as
select 'cleared'::text as fixture,
       public.record_evidence_quarantine(
         'ac110000-0000-0000-0000-000000000001',
         'personal-v1', 'cleared-flag', 1, '{}'::jsonb
       ) as id
union all
select 'unresolved', public.record_evidence_quarantine(
  'ac220000-0000-0000-0000-000000000001',
  'personal-v1', 'unresolved-flag', 1, '{}'::jsonb
)
union all
select 'rejected', public.record_evidence_quarantine(
  'ac220000-0000-0000-0000-000000000002',
  'personal-v1', 'rejected-flag', 1, '{}'::jsonb
);

create temporary table t_clear_resolution as
select public.resolve_personal_evidence_quarantine_v1(
  (select id from t_quarantines where fixture = 'cleared'),
  'ac100000-0000-0000-0000-000000000010',
  'cleared', 'trusted_operator_review',
  extensions.digest('clear-resolution', 'sha256')
) as id;

select is(
  public.resolve_personal_evidence_quarantine_v1(
    (select id from t_quarantines where fixture = 'cleared'),
    'ac100000-0000-0000-0000-000000000010',
    'cleared', 'trusted_operator_review',
    extensions.digest('clear-resolution', 'sha256')
  ),
  (select id from t_clear_resolution),
  'an exact personal operator-resolution retry returns the first ledger row'
);

select throws_ok(
  format(
    'select public.resolve_personal_evidence_quarantine_v1(%L, %L, %L, %L, extensions.digest(%L, %L))',
    (select id from t_quarantines where fixture = 'cleared'),
    'ac100000-0000-0000-0000-000000000010',
    'rejected', 'changed_review', 'changed-resolution', 'sha256'
  ),
  '23505', null,
  'a resolution request cannot change its terminal personal decision'
);

select throws_ok(
  $$ update app.personal_quarantine_resolutions
     set reason_code = 'rewritten'
     where id = (select id from t_clear_resolution) $$,
  '23001', null,
  'personal operator resolutions are append-only'
);

select public.resolve_personal_evidence_quarantine_v1(
  (select id from t_quarantines where fixture = 'rejected'),
  'ac200000-0000-0000-0000-000000000010',
  'rejected', 'evidence_not_trusted',
  extensions.digest('rejected-resolution', 'sha256')
);

grant select on t_quarantines to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ac111111-1111-1111-1111-111111111111"}',
  true
);

select is(
  (
    select count(*) from public.metric_snapshots
    where contest_id = 'ac000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'a personal owner can read their underlying step observation'
);

select is(
  (
    select count(*) from public.ingest_batches
    where contest_id = 'ac000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'a personal owner can read their underlying trusted ingest activity'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ac222222-2222-2222-2222-222222222222"}',
  true
);

select is(
  (
    select count(*) from public.metric_snapshots
    where contest_id = 'ac000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'a second user cannot read another personal owner step observations'
);

select is(
  (
    select count(*) from public.ingest_batches
    where contest_id = 'ac000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'a second user cannot read another personal owner ingest activity'
);

select is(
  (
    select count(*)
    from public.list_my_evidence_quarantines(
      'ac000000-0000-0000-0000-000000000002'
    )
  ),
  0::bigint,
  'the personal owner receives no legacy peer-review state'
);

select is(
  (
    select count(*)
    from public.list_contest_quarantine_reviews(
      'ac000000-0000-0000-0000-000000000002'
    )
  ),
  0::bigint,
  'the inherited peer-review inbox has no personal row'
);

select is(
  (
    select count(*)
    from public.get_quarantine_revision_history(
      (select id from t_quarantines where fixture = 'unresolved')
    )
  ),
  0::bigint,
  'the inherited peer revision route exposes no personal history'
);

select throws_ok(
  format(
    'select public.review_evidence_quarantine(%L, true)',
    (select id from t_quarantines where fixture = 'unresolved')
  ),
  '42501', 'quarantine not found',
  'personal evidence categorically rejects an inherited peer vote'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

select throws_ok(
  format(
    'select public.clear_evidence_quarantine_v1(%L, %L)',
    'ac200000-0000-0000-0000-000000000011',
    (select id from t_quarantines where fixture = 'unresolved')
  ),
  '23001', null,
  'the legacy operator-clearance endpoint rejects a personal flag'
);

select throws_ok(
  $$ select public.load_contest_integrity_input_v1(
       'ac000000-0000-0000-0000-000000000002'
     ) $$,
  '23001', null,
  'the legacy social integrity loader rejects a personal challenge'
);

select throws_ok(
  format(
    'select app.ensure_evidence_quarantine_adjudication(%L, %L, clock_timestamp() + interval %L)',
    (select id from t_quarantines where fixture = 'unresolved'),
    'peer_review_timeout', '4 days'
  ),
  '23001', null,
  'the inherited adjudication ledger rejects a personal escalation'
);

create temporary table t_deadline_sweep as
select * from app.process_evidence_quarantine_deadlines_at(
  clock_timestamp() + interval '4 days', 100
);

select ok(
  (
    select quarantines_escalated = 0 and contests_timed_out = 0
    from t_deadline_sweep
  )
  and not exists (
    select 1 from app.evidence_quarantine_adjudications adjudication
    where adjudication.contest_id = 'ac000000-0000-0000-0000-000000000002'
  ),
  'the legacy deadline worker skips personal flags instead of poisoning its sweep'
);

create temporary table t_clear_assessment as
select public.record_personal_assessment_v1(
  'ac000000-0000-0000-0000-000000000001',
  'ac100000-0000-0000-0000-000000000020',
  'complete', 'personal-v1',
  extensions.digest('cleared-assessment', 'sha256'), null
) as id;

create temporary table t_clear_result as
select public.publish_personal_result_v1(
  'ac000000-0000-0000-0000-000000000001',
  (select id from t_clear_assessment)
) as id;

select ok(
  (
    select outcome = 'met_goal'
       and reason = 'target_reached'
       and total_steps = 100
       and not commitment_waived
    from public.personal_challenge_results
    where id = (select id from t_clear_result)
  ),
  'operator-cleared flagged evidence can complete and meet the personal goal'
);

select ok(
  (
    select not workflow_open
       and user_terminal_at = (select published_at from public.personal_challenge_results where id = (select id from t_clear_result))
       and operator_open_until >= user_terminal_at + interval '90 days'
    from app.workflow_scopes
    where scope_kind = 'contest_lineage'
      and scope_id = 'ac000000-0000-0000-0000-000000000001'
  ),
  'personal publication closes the D81 contest-lineage scope at user finality'
);

select throws_ok(
  $$ select public.record_personal_assessment_v1(
       'ac000000-0000-0000-0000-000000000002',
       'ac200000-0000-0000-0000-000000000020',
       'complete', 'personal-v1',
       extensions.digest('unsafe-complete', 'sha256'), null
     ) $$,
  '23001',
  'unresolved or rejected personal evidence cannot be assessed as complete',
  'unresolved and rejected personal flags fail closed'
);

create temporary table t_unresolved_assessment as
select public.record_personal_assessment_v1(
  'ac000000-0000-0000-0000-000000000002',
  'ac200000-0000-0000-0000-000000000021',
  'quarantined', 'personal-v1',
  extensions.digest('deadline-unresolved', 'sha256'), null
) as id;

create temporary table t_unresolved_result as
select public.publish_personal_result_v1(
  'ac000000-0000-0000-0000-000000000002',
  (select id from t_unresolved_assessment)
) as id;

select ok(
  (
    select outcome = 'inconclusive'
       and reason = 'quarantined_evidence'
       and commitment_waived
    from public.personal_challenge_results
    where id = (select id from t_unresolved_result)
  )
  and not exists (
    select 1 from public.personal_eligibility_holds
    where challenge_id = 'ac000000-0000-0000-0000-000000000002'
  ),
  'a personal flag unresolved at result time becomes inconclusive and waived without a hold'
);

select is(
  (
    select count(*) from public.contest_results
    where contest_id in (
      'ac000000-0000-0000-0000-000000000001',
      'ac000000-0000-0000-0000-000000000002'
    )
  ),
  0::bigint,
  'personal flag resolution creates no legacy winner result'
);

insert into public.personal_trusted_diagnostics (
  user_id, client_diagnostic_id, key_id, sign_count, payload_digest,
  observed_at, query_started_at, query_ended_at,
  trusted_device_sample_count
)
select
  'ac111111-1111-1111-1111-111111111111',
  'ac100000-0000-0000-0000-000000000030',
  key1_id, 2, extensions.digest('retained-diagnostic', 'sha256'),
  clock_timestamp(), clock_timestamp() - interval '2 minutes',
  clock_timestamp() - interval '1 minute', 1
from t_keys;

update public.device_attestations device
set revoked_at = clock_timestamp()
where device.key_id = (select key1_id from t_keys);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ac111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (
    select total_steps = 100
       and outcome = 'met_goal'
       and (
         select sum((day ->> 'trusted_steps')::numeric)
         from jsonb_array_elements(daily_progress) day
       ) = 100
    from public.get_my_accountability_challenge_v1(
      'ac000000-0000-0000-0000-000000000001'
    )
  ),
  'completed personal history initially renders its frozen result totals'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

create temporary table t_retention as
select * from app.run_raw_evidence_retention(
  clock_timestamp() + interval '200 days', 5000
);

select ok(
  (select metric_rows_pruned >= 3 from t_retention)
  and not exists (
    select 1 from public.metric_snapshots
    where contest_id in (
      'ac000000-0000-0000-0000-000000000001',
      'ac000000-0000-0000-0000-000000000002'
    )
  ),
  'D81 prunes terminal personal raw metric observations after the policy horizon'
);

select ok(
  (select device_rows_pruned >= 1 from t_retention)
  and not exists (
    select 1 from public.device_attestations
    where key_id = (select key1_id from t_keys)
  )
  and exists (
    select 1 from public.personal_sync_coverage_batches
    where key_id = (select key1_id from t_keys)
  )
  and exists (
    select 1 from public.personal_trusted_diagnostics
    where key_id = (select key1_id from t_keys)
  ),
  'D81 can prune a revoked device while personal coverage and diagnostic audit facts retain only its fingerprint'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ac111111-1111-1111-1111-111111111111"}',
  true
);

select ok(
  (
    select total_steps = 100
       and outcome = 'met_goal'
       and (
         select sum((day ->> 'trusted_steps')::numeric)
         from jsonb_array_elements(daily_progress) day
       ) = 100
    from public.get_my_accountability_challenge_v1(
      'ac000000-0000-0000-0000-000000000001'
    )
  ),
  'completed history remains identical after its raw metric rows are pruned'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ac444444-4444-4444-4444-444444444444"}',
  true
);

create temporary table t_pending_delete as
select public.create_personal_challenge_v1(
  'ac400000-0000-0000-0000-000000000001',
  'daily', 10000, 1000, 'UTC'
) as id;

reset role;
select set_config('request.jwt.claims', '{}', true);

select lives_ok(
  $$ select public.delete_account(
       'ac444444-4444-4444-4444-444444444444'
     ) $$,
  'account deletion can atomically cancel a pending personal challenge'
);

select ok(
  (
    select contest.status = 'cancelled'
       and terms.closed_at = contest.cancelled_at
       and terms.closed_at is not null
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.id = (select id from t_pending_delete)
  ),
  'pending personal terms close at the account-deletion cancellation boundary'
);

select is(
  (
    select count(*) from app.workflow_scopes
    where scope_kind = 'contest_lineage'
      and scope_id = (select id from t_pending_delete)
  ),
  0::bigint,
  'a never-activated personal cancellation does not leave an open retention scope'
);

select throws_ok(
  $$ update public.contests
     set status = 'cancelled',
         cancellation_reason = 'creator_cancelled',
         cancelled_at = clock_timestamp()
     where id = 'ac000000-0000-0000-0000-000000000004' $$,
  '23001', null,
  'an active personal challenge cannot be cancelled outside account deletion'
);

select lives_ok(
  $$ select public.delete_account(
       'ac555555-5555-5555-5555-555555555555'
     ) $$,
  'account deletion preserves an active personal challenge for retained service finalization'
);

select ok(
  (
    select contest.status = 'active'
       and contest.cancelled_at is null
       and terms.closed_at is null
       and scope.workflow_open
       and scope.user_terminal_at is null
       and exists (
         select 1
         from app.account_capabilities capability
         where capability.actor_id = contest.created_by
           and capability.scope_kind = 'contest_lineage'
           and capability.scope_id = contest.id
           and capability.revoked_at is null
       )
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    join app.workflow_scopes scope
      on scope.scope_kind = 'contest_lineage'
     and scope.scope_id = contest.id
    where contest.id = 'ac000000-0000-0000-0000-000000000004'
  ),
  'active deletion does not violate the post-start cancellation lock and retains scoped service continuity'
);

create temporary table t_deleted_assessment as
select public.record_personal_assessment_v1(
  'ac000000-0000-0000-0000-000000000004',
  'ac500000-0000-0000-0000-000000000020',
  'user_device_sync_failure', 'personal-v1',
  extensions.digest('deleted-device-unavailable', 'sha256'), null
) as id;

create temporary table t_deleted_result as
select public.publish_personal_result_v1(
  'ac000000-0000-0000-0000-000000000004',
  (select id from t_deleted_assessment)
) as id;

select ok(
  (
    select contest.status = 'finalized'
       and terms.closed_at = result.published_at
       and result.outcome = 'inconclusive'
       and result.reason = 'user_device_sync_failure'
       and result.commitment_waived
       and not scope.workflow_open
       and scope.user_terminal_at = result.published_at
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    join public.personal_challenge_results result
      on result.challenge_id = contest.id
    join app.workflow_scopes scope
      on scope.scope_kind = 'contest_lineage'
     and scope.scope_id = contest.id
    where result.id = (select id from t_deleted_result)
  )
  and not exists (
    select 1 from public.personal_eligibility_holds
    where challenge_id = 'ac000000-0000-0000-0000-000000000004'
  ),
  'retained service finalization waives deleted-owner sync failure, closes scope, and creates no unusable hold'
);

select * from finish();
rollback;
