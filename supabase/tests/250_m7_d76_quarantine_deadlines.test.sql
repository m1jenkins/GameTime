-- M7 / D76: immutable grace-anchored peer deadlines, immediate rejection
-- escalation, explicit service-only clearance, and fail-closed review timeout.

begin;
select no_plan();

-- ---------------------------------------------------------------------------
-- Shape, timer registry, and least privilege
-- ---------------------------------------------------------------------------

select has_column(
  'public',
  'evidence_quarantines',
  'review_deadline',
  'each quarantine stores one immutable peer-review deadline'
);
select is(
  app.evidence_quarantine_peer_review_period(),
  interval '72 hours',
  'the peer-review duration is one named 72-hour server setting'
);
select is(
  app.evidence_quarantine_adjudication_period(),
  interval '7 days',
  'the adjudication duration is one named seven-day server setting'
);
select has_table(
  'app',
  'evidence_quarantine_adjudications',
  'escalations have a private durable ledger'
);
select has_table(
  'app',
  'evidence_quarantine_adjudication_events',
  'terminal adjudication decisions have a separate append-only ledger'
);
select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'app.evidence_quarantine_adjudications'::regclass
  )
  and (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid =
      'app.evidence_quarantine_adjudication_events'::regclass
  ),
  'both private D76 ledgers have RLS defense in depth'
);
select ok(
  not has_table_privilege(
    'anon',
    'app.evidence_quarantine_adjudications',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'app.evidence_quarantine_adjudications',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'app.evidence_quarantine_adjudications',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'app.evidence_quarantine_adjudication_events',
    'insert'
  ),
  'application roles cannot inspect or forge private adjudication history'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.clear_evidence_quarantine_v1(uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.clear_evidence_quarantine_v1(uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.clear_evidence_quarantine_v1(uuid,uuid)',
    'execute'
  ),
  'explicit clearance is service_role-only'
);
select ok(
  has_function_privilege(
    'service_role',
    'app.process_evidence_quarantine_deadlines()',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'app.process_evidence_quarantine_deadlines()',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.process_evidence_quarantine_deadlines()',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'app.process_evidence_quarantine_deadlines_at(timestamptz,integer)',
    'execute'
  ),
  'service_role gets only the real-clock worker, not its test-time helper'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_evidence_quarantine_resolution_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_evidence_quarantine_resolution_v1(uuid)',
    'execute'
  ),
  'signed-in participants receive only the bounded resolution RPC'
);
select is(
  (
    select count(*)
    from cron.job
    where jobname = 'gametime-process-quarantine-review-deadlines'
  ),
  1::bigint,
  'the D76 worker has one named scheduler-registry entry'
);
select is(
  (
    select schedule
    from cron.job
    where jobname = 'gametime-process-quarantine-review-deadlines'
  ),
  '* * * * *',
  'the D76 worker follows the one-minute timer convention'
);
select is(
  (
    select command
    from cron.job
    where jobname = 'gametime-process-quarantine-review-deadlines'
  ),
  'select app.process_evidence_quarantine_deadlines();',
  'the registry calls only the real-clock service worker'
);
select ok(
  (
    select active
    from cron.job
    where jobname = 'gametime-process-quarantine-review-deadlines'
  ),
  'the named D76 job is enabled'
);

-- ---------------------------------------------------------------------------
-- Reusable contest/evidence/assessment fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('d7111111-1111-1111-1111-111111111111'),
  ('d7222222-2222-2222-2222-222222222222'),
  ('d7333333-3333-3333-3333-333333333333');

insert into public.profiles (id, handle, display_name) values
  (
    'd7111111-1111-1111-1111-111111111111',
    'd76alice',
    'D76 Alice'
  ),
  (
    'd7222222-2222-2222-2222-222222222222',
    'd76bob',
    'D76 Bob'
  ),
  (
    'd7333333-3333-3333-3333-333333333333',
    'd76outsider',
    'D76 Outsider'
  );

insert into public.charities (id, name, ein, slug) values (
  'd7c00001-0000-0000-0000-000000000001',
  'D76 Review Fund',
  '97-0000003',
  'd76-review-fund'
);

create temporary table t_d76_cases (
  label        text primary key,
  contest_id   uuid not null unique,
  batch_id     uuid not null unique,
  snapshot_id  uuid not null unique
);

insert into t_d76_cases values
  (
    'pre_grace',
    'd7000001-0000-0000-0000-000000000001',
    'd7b00001-0000-0000-0000-000000000001',
    'd7e00001-0000-0000-0000-000000000001'
  ),
  (
    'approved',
    'd7000002-0000-0000-0000-000000000002',
    'd7b00002-0000-0000-0000-000000000002',
    'd7e00002-0000-0000-0000-000000000002'
  ),
  (
    'cleared',
    'd7000003-0000-0000-0000-000000000003',
    'd7b00003-0000-0000-0000-000000000003',
    'd7e00003-0000-0000-0000-000000000003'
  ),
  (
    'peer_timeout',
    'd7000004-0000-0000-0000-000000000004',
    'd7b00004-0000-0000-0000-000000000004',
    'd7e00004-0000-0000-0000-000000000004'
  ),
  (
    'deleted_timeout',
    'd7000005-0000-0000-0000-000000000005',
    'd7b00005-0000-0000-0000-000000000005',
    'd7e00005-0000-0000-0000-000000000005'
  ),
  (
    'boundary_timeout',
    'd7000006-0000-0000-0000-000000000006',
    'd7b00006-0000-0000-0000-000000000006',
    'd7e00006-0000-0000-0000-000000000006'
  );

alter table public.contests disable trigger contests_assert_future_window;

insert into public.contests (
  id,
  title,
  created_by,
  metric,
  cadence,
  target_value,
  stake_amount_cents,
  tie_break,
  starts_at,
  ends_at,
  max_participants
)
select
  fixture.contest_id,
  'D76 ' || fixture.label,
  'd7111111-1111-1111-1111-111111111111',
  'steps',
  'cumulative',
  10000,
  100,
  'void',
  date_trunc('hour', clock_timestamp()) - interval '3 days',
  case
    when fixture.label = 'pre_grace'
      then date_trunc('hour', clock_timestamp()) + interval '30 days'
    else date_trunc('hour', clock_timestamp()) - interval '7 hours'
  end,
  2
from t_d76_cases fixture;

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  timezone,
  charity_id
)
select
  fixture.contest_id,
  'd7111111-1111-1111-1111-111111111111',
  'accepted',
  'UTC',
  'd7c00001-0000-0000-0000-000000000001'
from t_d76_cases fixture;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by
)
select
  fixture.contest_id,
  'd7222222-2222-2222-2222-222222222222',
  'invited',
  'd7111111-1111-1111-1111-111111111111'
from t_d76_cases fixture;

update public.contest_participants
set status = 'accepted',
    timezone = 'UTC',
    charity_id = 'd7c00001-0000-0000-0000-000000000001'
where user_id = 'd7222222-2222-2222-2222-222222222222'
  and contest_id in (select contest_id from t_d76_cases);

update public.contests
set status = 'active',
    activated_at = clock_timestamp()
where id in (select contest_id from t_d76_cases);

insert into public.ingest_batches (
  id,
  contest_id,
  user_id,
  client_batch_id,
  attested,
  payload_digest,
  observation_count,
  observed_at
)
select
  fixture.batch_id,
  fixture.contest_id,
  'd7111111-1111-1111-1111-111111111111',
  gen_random_uuid(),
  false,
  extensions.digest('d76-' || fixture.label, 'sha256'),
  1,
  clock_timestamp()
from t_d76_cases fixture;

alter table public.metric_snapshots disable trigger metric_snapshots_prepare;

insert into public.metric_snapshots (
  id,
  batch_id,
  contest_id,
  user_id,
  metric,
  bucket_start,
  local_day,
  local_hour,
  value,
  provenance,
  sample_count,
  observed_at,
  recorded_at
)
select
  fixture.snapshot_id,
  fixture.batch_id,
  fixture.contest_id,
  'd7111111-1111-1111-1111-111111111111',
  'steps',
  date_trunc('hour', clock_timestamp()) - interval '2 days',
  current_date - 2,
  0,
  5000,
  'device',
  1,
  date_trunc('hour', clock_timestamp()) - interval '2 days',
  clock_timestamp()
from t_d76_cases fixture;

alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

create temporary table t_d76_quarantines as
select
  fixture.label,
  fixture.contest_id,
  public.record_evidence_quarantine(
    fixture.snapshot_id,
    'm7-integrity-v1',
    'd76:' || fixture.label,
    3600000,
    jsonb_build_object(
      'disposition',
      'review_required',
      'evidenceStillScores',
      true
    )
  ) as quarantine_id
from t_d76_cases fixture;

grant select on t_d76_cases, t_d76_quarantines
  to authenticated, service_role;

create function pg_temp.d76_standings(p_contest_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.user_id,
      'display_order', participant.ordinality,
      'rank', 1,
      'qualified', false,
      'total', 0,
      'qualifying_days', 0,
      'scoreable_days', 0,
      'day_rate', 0,
      'reached_target_at', null,
      'integrity_score', 100,
      'integrity_flags', '[]'::jsonb,
      'rationale', jsonb_build_array(
        jsonb_build_object(
          'code', 'clean_evidence',
          'summary', 'No scored integrity deductions.',
          'points', 0
        )
      )
    )
    order by participant.ordinality
  )
  from (
    select
      roster.user_id,
      row_number() over (order by roster.user_id)::integer as ordinality
    from public.contest_participants roster
    where roster.contest_id = p_contest_id
      and roster.status = 'accepted'
  ) participant;
$$;

create function pg_temp.d76_assess(p_contest_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_loaded             jsonb;
  v_cutoff             timestamptz;
  v_evidence_digest    bytea;
  v_input_digest       bytea;
  v_quarantine_count   integer;
  v_pending_count      integer;
  v_approved_count     integer;
  v_rejected_count     integer;
  v_standings          jsonb;
  v_outcome            jsonb;
  v_document           jsonb;
begin
  v_loaded := app.build_contest_integrity_input_v1(p_contest_id);
  v_standings := pg_temp.d76_standings(p_contest_id);
  v_outcome := jsonb_build_object(
    'kind',
    'void',
    'reason',
    'no_qualifying_participant'
  );

  select contest.ends_at + app.ingest_grace_period()
    into v_cutoff
  from public.contests contest
  where contest.id = p_contest_id;

  v_evidence_digest := extensions.digest(
    jsonb_build_object(
      'schemaVersion', 'm7-integrity-input-v1',
      'input', (v_loaded -> 'input') - 'quarantineState',
      'quarantineCandidates', v_loaded -> 'quarantineCandidates'
    )::text,
    'sha256'
  );
  v_input_digest := extensions.digest(
    jsonb_build_object(
      'schemaVersion', 'm7-integrity-input-v1',
      'input', v_loaded -> 'input',
      'quarantineCandidates', v_loaded -> 'quarantineCandidates'
    )::text,
    'sha256'
  );

  v_quarantine_count :=
    jsonb_array_length(v_loaded #> '{input,quarantineState}');
  select
    count(*) filter (where row ->> 'state' = 'pending')::integer,
    count(*) filter (where row ->> 'state' = 'approved')::integer,
    count(*) filter (where row ->> 'state' = 'rejected')::integer
    into v_pending_count, v_approved_count, v_rejected_count
  from jsonb_array_elements(v_loaded #> '{input,quarantineState}') row;

  v_document := jsonb_build_object(
    'schema_version', 'm7-integrity-assessment-v1',
    'contest_id', p_contest_id,
    'evidence_cutoff', v_cutoff,
    'scoring_version', 'm4-v1',
    'integrity_configuration_version', 'm7-integrity-v1',
    'evidence_digest', encode(v_evidence_digest, 'hex'),
    'input_digest', encode(v_input_digest, 'hex'),
    'input_counts', jsonb_build_object(
      'roster', jsonb_array_length(v_loaded #> '{input,roster}'),
      'contest_evidence',
        jsonb_array_length(v_loaded #> '{input,evidence}'),
      'source_reputation',
        jsonb_array_length(v_loaded #> '{input,sourceEvidence}'),
      'timezone_events',
        jsonb_array_length(v_loaded #> '{input,timezoneChanges}'),
      'quarantine_state', v_quarantine_count,
      'checkin_integrity',
        jsonb_array_length(v_loaded #> '{input,checkIns}'),
      'trusted_locations',
        jsonb_array_length(v_loaded #> '{input,locations}')
    ),
    'quarantine_observation', jsonb_build_object(
      'total', v_quarantine_count,
      'pending', v_pending_count,
      'approved', v_approved_count,
      'rejected', v_rejected_count
    ),
    'required_quarantine_count', 0,
    'clean_zero_quarantines', false,
    'standings', v_standings,
    'outcome', v_outcome,
    'integrity', (
      select jsonb_agg(
        jsonb_build_object(
          'participant_id', standing ->> 'participant_id',
          'score', standing -> 'integrity_score',
          'total_penalty', 0,
          'penalties', '{}'::jsonb,
          'flags', '[]'::jsonb
        )
        order by (standing ->> 'display_order')::integer
      )
      from jsonb_array_elements(v_standings) standing
    )
  );

  return public.record_contest_integrity_assessment_v1(
    p_contest_id,
    v_cutoff,
    'm4-v1',
    'm7-integrity-v1',
    v_evidence_digest,
    v_input_digest,
    v_document,
    '[]'::jsonb
  );
end;
$$;

create function pg_temp.d76_publish_assessed(p_contest_id uuid)
returns uuid
language sql
volatile
security definer
set search_path = ''
as $$
  select public.publish_contest_standings_v1(
    assessment.contest_id,
    clock_timestamp(),
    assessment.scoring_version,
    assessment.integrity_configuration_version,
    assessment.assessment_document -> 'standings',
    assessment.assessment_document -> 'outcome',
    assessment.evidence_cutoff
  )
  from app.contest_integrity_assessments assessment
  where assessment.contest_id = p_contest_id
  order by assessment.assessed_at desc, assessment.id desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Deadline anchoring and inclusive peer boundary
-- ---------------------------------------------------------------------------

select is(
  (
    select quarantine.review_deadline
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'pre_grace'
    )
  ),
  (
    select
      contest.ends_at
      + app.ingest_grace_period()
      + app.evidence_quarantine_peer_review_period()
    from public.contests contest
    where contest.id = (
      select contest_id from t_d76_cases where label = 'pre_grace'
    )
  ),
  'a quarantine created before grace anchors its full peer window at grace close'
);
select is(
  (
    select quarantine.review_deadline
    from public.evidence_quarantines quarantine
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  (
    select
      quarantine.created_at
      + app.evidence_quarantine_peer_review_period()
    from public.evidence_quarantines quarantine
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  'a quarantine created after grace receives a full window from creation'
);
select ok(
  not exists (
    select 1
    from public.evidence_quarantines quarantine
    join public.contests contest on contest.id = quarantine.contest_id
    where quarantine.review_deadline <
      contest.ends_at
      + app.ingest_grace_period()
      + app.evidence_quarantine_peer_review_period()
  ),
  'no quarantine deadline is anchored before ingest-grace close'
);

-- ---------------------------------------------------------------------------
-- Peer approval versus immediate rejection escalation
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d7222222-2222-2222-2222-222222222222"}',
  true
);

select lives_ok(
  $$ select public.review_evidence_quarantine(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'approved'
       ),
       true
     ) $$,
  'a peer may approve strictly before the deadline'
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'cleared'
       ),
       false
     ) $$,
  'a peer may reject strictly before the deadline'
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'deleted_timeout'
       ),
       false
     ) $$,
  'a second early rejection uses the same escalation path'
);
select lives_ok(
  $$ select public.review_evidence_quarantine(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'boundary_timeout'
       ),
       false
     ) $$,
  'the boundary fixture also escalates from a real peer rejection'
);

reset role;

select is(
  (
    select status.peer_state
    from public.evidence_quarantine_status status
    where status.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'approved'
    )
  ),
  'approved'::public.evidence_quarantine_state,
  'peer approval remains an immutable peer result'
);
select is(
  (
    select count(*)
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'approved'
    )
  ),
  0::bigint,
  'an approved peer review never escalates'
);
select is(
  (
    select status.peer_state
    from public.evidence_quarantine_status status
    where status.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  ),
  'rejected'::public.evidence_quarantine_state,
  'rejection remains visible as the peer decision'
);
select is(
  (
    select adjudication.escalation_reason
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  ),
  'early_rejection'::app.evidence_quarantine_escalation_reason,
  'the rejecting vote appends adjudication in the same transaction'
);
select is(
  (
    select adjudication.adjudication_deadline
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  ),
  (
    select
      greatest(
        contest.ends_at + app.ingest_grace_period(),
        adjudication.escalated_at
      ) + app.evidence_quarantine_adjudication_period()
    from app.evidence_quarantine_adjudications adjudication
    join public.contests contest on contest.id = adjudication.contest_id
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  ),
  'the operator deadline is seven days after the grace-anchored escalation'
);
select is(
  (
    select count(*)
    from public.notification_intents intent
    where intent.event_type = 'quarantine_review_escalated'
      and intent.entity_id = (
        select quarantine_id
        from t_d76_quarantines
        where label = 'cleared'
      )
  ),
  2::bigint,
  'early escalation emits one payload-free intent per accepted participant'
);

-- All post-grace fixtures now freeze the peer state they actually observed.
select lives_ok(
  $$ select pg_temp.d76_assess(
       (select contest_id from t_d76_cases where label = 'approved')
     ) $$,
  'the approved fixture records its complete frozen assessment'
);
select lives_ok(
  $$ select pg_temp.d76_assess(
       (select contest_id from t_d76_cases where label = 'cleared')
     ) $$,
  'the rejected fixture records its complete frozen assessment before clearance'
);
select lives_ok(
  $$ select pg_temp.d76_assess(
       (select contest_id from t_d76_cases where label = 'peer_timeout')
     ) $$,
  'the silent-review fixture records its complete frozen assessment'
);
select lives_ok(
  $$ select pg_temp.d76_assess(
       (select contest_id from t_d76_cases where label = 'deleted_timeout')
     ) $$,
  'the tombstone fixture records its complete frozen assessment'
);
select lives_ok(
  $$ select pg_temp.d76_assess(
       (select contest_id from t_d76_cases where label = 'boundary_timeout')
     ) $$,
  'the exact-boundary fixture records its complete frozen assessment'
);

-- ---------------------------------------------------------------------------
-- Explicit clearance, same-request retry, and normal final publication
-- ---------------------------------------------------------------------------

create temporary table t_d76_clearance_events (
  attempt text primary key,
  event_id uuid not null
);
grant select, insert on t_d76_clearance_events to service_role;

set local role service_role;

insert into t_d76_clearance_events
select
  'first',
  public.clear_evidence_quarantine_v1(
    'd7a00001-0000-0000-0000-000000000001',
    (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  );

insert into t_d76_clearance_events
select
  'retry',
  public.clear_evidence_quarantine_v1(
    'd7a00001-0000-0000-0000-000000000001',
    (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  );

select throws_ok(
  $$ select public.clear_evidence_quarantine_v1(
       'd7a00001-0000-0000-0000-000000000001',
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'boundary_timeout'
       )
     ) $$,
  '23505',
  null,
  'one request UUID cannot clear a different quarantine'
);

reset role;

select is(
  (
    select event_id
    from t_d76_clearance_events
    where attempt = 'first'
  ),
  (
    select event_id
    from t_d76_clearance_events
    where attempt = 'retry'
  ),
  'same-request clearance retry returns the first event id'
);
select is(
  (
    select count(*)
    from app.evidence_quarantine_adjudication_events terminal
    where terminal.request_id =
      'd7a00001-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'same-request retry appends exactly one clearance event'
);
select ok(
  (
    select
      status.peer_state = 'rejected'
      and status.state = 'approved'
      and status.adjudication_resolution = 'cleared'
    from public.evidence_quarantine_status status
    where status.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'cleared'
    )
  ),
  'clearance opens the gate without rewriting the rejected peer vote'
);
select is(
  (
    select count(*)
    from public.notification_intents intent
    where intent.event_type = 'quarantine_review_resolved'
      and intent.entity_id = (
        select quarantine_id
        from t_d76_quarantines
        where label = 'cleared'
      )
  ),
  2::bigint,
  'clearance emits one generic resolution intent per accepted participant'
);

set local role service_role;
select lives_ok(
  $$ select pg_temp.d76_publish_assessed(
       (select contest_id from t_d76_cases where label = 'approved')
     ) $$,
  'peer approval permits the unchanged assessment outcome to finalize'
);
select lives_ok(
  $$ select pg_temp.d76_publish_assessed(
       (select contest_id from t_d76_cases where label = 'cleared')
     ) $$,
  'explicit clearance permits the unchanged assessment outcome to finalize'
);
reset role;

select is(
  (
    select result.kind
    from public.contest_results result
    where result.contest_id = (
      select contest_id from t_d76_cases where label = 'cleared'
    )
  ),
  'void'::public.contest_result_kind,
  'clearance does not fabricate a winner or rewrite the assessment outcome'
);
select is(
  (
    select count(*)
    from public.donation_obligations obligation
    where obligation.contest_id = (
      select contest_id from t_d76_cases where label = 'cleared'
    )
  ),
  0::bigint,
  'the cleared void assessment creates no actionable obligation'
);

-- ---------------------------------------------------------------------------
-- Peer-deadline and adjudication-deadline boundaries
-- ---------------------------------------------------------------------------

create temporary table t_d76_worker_runs (
  run text primary key,
  quarantines_escalated integer not null,
  contests_timed_out integer not null
);

insert into t_d76_worker_runs
select
  'peer_before',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select quarantine.review_deadline - interval '1 microsecond'
    from public.evidence_quarantines quarantine
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  100
) worker;

select is(
  (
    select quarantines_escalated
    from t_d76_worker_runs
    where run = 'peer_before'
  ),
  0,
  'one microsecond before the peer deadline does not escalate silence'
);

insert into t_d76_worker_runs
select
  'peer_exact',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select quarantine.review_deadline
    from public.evidence_quarantines quarantine
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  100
) worker;

select is(
  (
    select quarantines_escalated
    from t_d76_worker_runs
    where run = 'peer_exact'
  ),
  1,
  'the inclusive peer deadline escalates one still-pending quarantine'
);
select is(
  (
    select adjudication.escalation_reason
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  'peer_review_timeout'::app.evidence_quarantine_escalation_reason,
  'peer silence is recorded as timeout escalation, never approval'
);

insert into t_d76_worker_runs
select
  'peer_duplicate',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select quarantine.review_deadline
    from public.evidence_quarantines quarantine
    where quarantine.id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  100
) worker;

select ok(
  (
    select
      quarantines_escalated = 0
      and contests_timed_out = 0
    from t_d76_worker_runs
    where run = 'peer_duplicate'
  ),
  'duplicate execution at the same peer instant is a no-op'
);
select is(
  (
    select count(*)
    from public.notification_intents intent
    where intent.event_type = 'quarantine_review_escalated'
      and intent.entity_id = (
        select quarantine_id
        from t_d76_quarantines
        where label = 'peer_timeout'
      )
  ),
  2::bigint,
  'duplicate worker execution cannot duplicate escalation intents'
);

select throws_ok(
  $$ select app.clear_evidence_quarantine_adjudication_at(
       'd7a00002-0000-0000-0000-000000000002',
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'boundary_timeout'
       ),
       (
         select adjudication.adjudication_deadline
         from app.evidence_quarantine_adjudications adjudication
         where adjudication.quarantine_id = (
           select quarantine_id
           from t_d76_quarantines
           where label = 'boundary_timeout'
         )
       )
     ) $$,
  '23001',
  null,
  'clearance loses at the exact adjudication deadline'
);

-- Delete the evidence subject after the assessment and escalation. D81 keeps
-- the accepted roster/quarantine/adjudication lineage and removes only active
-- authentication.
create temporary table t_d76_deletion (result jsonb not null);
grant insert on t_d76_deletion to service_role;
set local role service_role;
insert into t_d76_deletion
select public.delete_account(
  'd7111111-1111-1111-1111-111111111111'
);
reset role;

select ok(
  exists (
    select 1
    from public.profiles profile
    where profile.id = 'd7111111-1111-1111-1111-111111111111'
      and profile.deleted_at is not null
  )
  and exists (
    select 1
    from public.contest_participants participant
    where participant.contest_id = (
      select contest_id
      from t_d76_cases
      where label = 'deleted_timeout'
    )
      and participant.user_id =
        'd7111111-1111-1111-1111-111111111111'
      and participant.status = 'accepted'
  ),
  'account deletion tombstones identity without erasing the accepted review lineage'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d7111111-1111-1111-1111-111111111111"}',
  true
);
select throws_ok(
  $$ select *
     from public.get_evidence_quarantine_resolution_v1(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'deleted_timeout'
       )
     ) $$,
  '42501',
  null,
  'a stale JWT for the tombstoned participant cannot read D76 state'
);
select throws_ok(
  $$ select public.review_evidence_quarantine(
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'peer_timeout'
       ),
       true
     ) $$,
  '42501',
  null,
  'a stale JWT cannot append a late peer review'
);
select throws_ok(
  $$ select public.clear_evidence_quarantine_v1(
       gen_random_uuid(),
       (
         select quarantine_id
         from t_d76_quarantines
         where label = 'peer_timeout'
       )
     ) $$,
  '42501',
  null,
  'an authenticated caller cannot invoke the service-only clearance RPC'
);
reset role;

insert into t_d76_worker_runs
select
  'early_timeouts',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select max(adjudication.adjudication_deadline)
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id in (
      select quarantine_id
      from t_d76_quarantines
      where label in ('deleted_timeout', 'boundary_timeout')
    )
  ),
  100
) worker;

select is(
  (
    select contests_timed_out
    from t_d76_worker_runs
    where run = 'early_timeouts'
  ),
  2,
  'operator silence after two early rejections terminalizes both contests'
);

insert into t_d76_worker_runs
select
  'peer_timeout_final',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select adjudication.adjudication_deadline
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.quarantine_id = (
      select quarantine_id
      from t_d76_quarantines
      where label = 'peer_timeout'
    )
  ),
  100
) worker;

select is(
  (
    select contests_timed_out
    from t_d76_worker_runs
    where run = 'peer_timeout_final'
  ),
  1,
  'operator silence after a peer-review timeout terminalizes that contest'
);

insert into t_d76_worker_runs
select
  'all_duplicate',
  worker.*
from app.process_evidence_quarantine_deadlines_at(
  (
    select max(adjudication.adjudication_deadline) + interval '1 day'
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'cleared',
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
  ),
  100
) worker;

select ok(
  (
    select
      quarantines_escalated = 0
      and contests_timed_out = 0
    from t_d76_worker_runs
    where run = 'all_duplicate'
  ),
  'a later duplicate sweep finds no transition left to perform'
);

-- ---------------------------------------------------------------------------
-- Fail-closed final results, exact assessment binding, and outbox idempotency
-- ---------------------------------------------------------------------------

select is(
  (
    select count(*)
    from public.contest_results result
    where result.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
      and result.kind = 'inconclusive'
      and result.reason = 'review_timeout'
  ),
  3::bigint,
  'peer-silence and rejection adjudication timeouts all end inconclusive'
);
select is(
  (
    select count(*)
    from public.contest_results result
    where result.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
      and result.integrity_assessment_id is not null
  ),
  3::bigint,
  'every review_timeout result remains bound to one frozen assessment'
);
select is(
  (
    select count(*)
    from public.contest_standing_snapshots snapshot
    where snapshot.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
      and snapshot.phase = 'final'
  ),
  3::bigint,
  'each timeout publishes one final snapshot from the frozen assessment'
);
select is(
  (
    select count(*)
    from public.contest_standing_entries entry
    where entry.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
  ),
  6::bigint,
  'timeout finality preserves the complete accepted roster'
);
select is(
  (
    select count(*)
    from public.donation_obligations obligation
    where obligation.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
  ),
  0::bigint,
  'review_timeout never creates an actionable settlement obligation'
);
select is(
  (
    select count(*)
    from public.contest_results result
    where result.contest_id in (
      select contest_id
      from t_d76_cases
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
  ),
  3::bigint,
  'duplicate workers cannot append a second first result'
);
select is(
  (
    select count(*)
    from app.evidence_quarantine_adjudication_events terminal
    where terminal.quarantine_id in (
      select quarantine_id
      from t_d76_quarantines
      where label in (
        'peer_timeout',
        'deleted_timeout',
        'boundary_timeout'
      )
    )
      and terminal.resolution = 'review_timeout'
  ),
  3::bigint,
  'each due adjudication records exactly one timeout event'
);
select is(
  (
    select count(*)
    from public.notification_intents intent
    where intent.event_type = 'contest_finalized'
      and intent.entity_id in (
        select contest_id
        from t_d76_cases
        where label in (
          'peer_timeout',
          'deleted_timeout',
          'boundary_timeout'
        )
      )
  ),
  6::bigint,
  'timeout finality emits exactly one generic result intent per retained participant'
);
select is(
  (
    select count(*)
    from public.notification_intents intent
    where intent.event_type = 'quarantine_review_resolved'
      and intent.entity_id in (
        select quarantine_id
        from t_d76_quarantines
        where label in (
          'peer_timeout',
          'deleted_timeout',
          'boundary_timeout'
        )
      )
  ),
  6::bigint,
  'timeout resolution intents are exactly once even for a tombstoned recipient'
);
select ok(
  not exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'notification_intents'
      and column_info.column_name in (
        'payload',
        'details',
        'health_value',
        'location',
        'operator_note'
      )
  ),
  'D76 reuses the payload-free outbox shape'
);
select ok(
  exists (
    select 1
    from public.notification_intents intent
    where intent.recipient_user_id =
      'd7111111-1111-1111-1111-111111111111'
      and intent.event_type = 'contest_finalized'
      and intent.entity_id = (
        select contest_id
        from t_d76_cases
        where label = 'deleted_timeout'
      )
  ),
  'tombstoning cannot erase the retained participant timeout intent'
);

select throws_ok(
  $$ update app.evidence_quarantine_adjudications
     set escalation_reason = 'peer_review_timeout'
     where quarantine_id = (
       select quarantine_id
       from t_d76_quarantines
       where label = 'cleared'
     ) $$,
  '23001',
  null,
  'adjudication requests are append-only'
);
select throws_ok(
  $$ delete from app.evidence_quarantine_adjudication_events
     where quarantine_id = (
       select quarantine_id
       from t_d76_quarantines
       where label = 'peer_timeout'
     ) $$,
  '23001',
  null,
  'adjudication terminal events are append-only'
);

select * from finish();
rollback;
