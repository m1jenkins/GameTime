-- M7 / D76: real two-session races prove that review, clearance, and timeout
-- transitions serialize without implicit approval or duplicate finality.

begin;
select no_plan();

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the test-only multi-session driver'
);

create function pg_temp.wait_for_d76_backend(
  p_application_name text,
  p_expect_blocked boolean,
  p_timeout_seconds double precision default 5
)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deadline timestamptz :=
    pg_catalog.clock_timestamp()
    + pg_catalog.make_interval(secs => p_timeout_seconds);
  v_blocked boolean;
begin
  loop
    select
      pg_catalog.cardinality(
        pg_catalog.pg_blocking_pids(activity.pid)
      ) > 0
      into v_blocked
    from pg_catalog.pg_stat_activity activity
    where activity.application_name = p_application_name;

    if coalesce(v_blocked, false) = p_expect_blocked then
      return true;
    end if;

    exit when pg_catalog.clock_timestamp() >= v_deadline;
    perform pg_catalog.pg_sleep(0.01);
  end loop;

  return false;
end;
$$;

create function pg_temp.wait_for_d76_query(
  p_connection text,
  p_timeout_seconds double precision default 5
)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deadline timestamptz :=
    pg_catalog.clock_timestamp()
    + pg_catalog.make_interval(secs => p_timeout_seconds);
begin
  loop
    if extensions.dblink_is_busy(p_connection) = 0 then
      return true;
    end if;

    exit when pg_catalog.clock_timestamp() >= v_deadline;
    perform pg_catalog.pg_sleep(0.01);
  end loop;

  return false;
end;
$$;

select extensions.dblink_connect(
  'd76c_setup',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'd76c_first',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'd76c_second',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'd76c_first',
  $$ set application_name = 'gametime_d76_concurrency_first' $$
);
select extensions.dblink_exec(
  'd76c_second',
  $$ set application_name = 'gametime_d76_concurrency_second' $$
);

-- Three committed fixtures isolate the three meaningful lock orders:
-- reviewer first, clearance first, and timer first.
select extensions.dblink_exec(
  'd76c_setup',
  $setup$
    insert into auth.users (id) values
      ('c7111111-1111-1111-1111-111111111111'),
      ('c7222222-2222-2222-2222-222222222222');

    insert into public.profiles (id, handle, display_name) values
      (
        'c7111111-1111-1111-1111-111111111111',
        'd76concurrencyalice',
        'D76 Concurrency Alice'
      ),
      (
        'c7222222-2222-2222-2222-222222222222',
        'd76concurrencybob',
        'D76 Concurrency Bob'
      );

    insert into public.charities (id, name, ein, slug) values (
      'c7c00001-0000-0000-0000-000000000001',
      'D76 Concurrency Fund',
      '97-0000004',
      'd76-concurrency-fund'
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
      'D76 concurrency ' || fixture.label,
      'c7111111-1111-1111-1111-111111111111',
      'steps',
      'cumulative',
      10000,
      100,
      'void',
      date_trunc('hour', clock_timestamp()) - interval '3 days',
      date_trunc('hour', clock_timestamp()) - interval '7 hours',
      2
    from (
      values
        (
          'review_first',
          'c7000001-0000-0000-0000-000000000001'::uuid
        ),
        (
          'clearance_first',
          'c7000002-0000-0000-0000-000000000002'::uuid
        ),
        (
          'timeout_first',
          'c7000003-0000-0000-0000-000000000003'::uuid
        )
    ) fixture(label, contest_id);

    alter table public.contests enable trigger contests_assert_future_window;

    insert into public.contest_participants (
      contest_id,
      user_id,
      status,
      timezone,
      charity_id
    )
    select
      contest.id,
      'c7111111-1111-1111-1111-111111111111',
      'accepted',
      'UTC',
      'c7c00001-0000-0000-0000-000000000001'
    from public.contests contest
    where contest.id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    insert into public.contest_participants (
      contest_id,
      user_id,
      status,
      invited_by
    )
    select
      contest.id,
      'c7222222-2222-2222-2222-222222222222',
      'invited',
      'c7111111-1111-1111-1111-111111111111'
    from public.contests contest
    where contest.id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    update public.contest_participants
    set status = 'accepted',
        timezone = 'UTC',
        charity_id = 'c7c00001-0000-0000-0000-000000000001'
    where user_id = 'c7222222-2222-2222-2222-222222222222'
      and contest_id in (
        'c7000001-0000-0000-0000-000000000001',
        'c7000002-0000-0000-0000-000000000002',
        'c7000003-0000-0000-0000-000000000003'
      );

    update public.contests
    set status = 'active',
        activated_at = clock_timestamp()
    where id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

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
      'c7111111-1111-1111-1111-111111111111',
      gen_random_uuid(),
      false,
      extensions.digest(fixture.label, 'sha256'),
      1,
      clock_timestamp()
    from (
      values
        (
          'review_first',
          'c7000001-0000-0000-0000-000000000001'::uuid,
          'c7b00001-0000-0000-0000-000000000001'::uuid
        ),
        (
          'clearance_first',
          'c7000002-0000-0000-0000-000000000002'::uuid,
          'c7b00002-0000-0000-0000-000000000002'::uuid
        ),
        (
          'timeout_first',
          'c7000003-0000-0000-0000-000000000003'::uuid,
          'c7b00003-0000-0000-0000-000000000003'::uuid
        )
    ) fixture(label, contest_id, batch_id);

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
      'c7111111-1111-1111-1111-111111111111',
      'steps',
      date_trunc('hour', clock_timestamp()) - interval '2 days',
      current_date - 2,
      0,
      5000,
      'device',
      1,
      date_trunc('hour', clock_timestamp()) - interval '2 days',
      clock_timestamp()
    from (
      values
        (
          'c7000001-0000-0000-0000-000000000001'::uuid,
          'c7b00001-0000-0000-0000-000000000001'::uuid,
          'c7e00001-0000-0000-0000-000000000001'::uuid
        ),
        (
          'c7000002-0000-0000-0000-000000000002'::uuid,
          'c7b00002-0000-0000-0000-000000000002'::uuid,
          'c7e00002-0000-0000-0000-000000000002'::uuid
        ),
        (
          'c7000003-0000-0000-0000-000000000003'::uuid,
          'c7b00003-0000-0000-0000-000000000003'::uuid,
          'c7e00003-0000-0000-0000-000000000003'::uuid
        )
    ) fixture(contest_id, batch_id, snapshot_id);

    alter table public.metric_snapshots enable trigger metric_snapshots_prepare;

    do $block$
    declare
      fixture record;
    begin
      for fixture in
        select *
        from (
          values
            (
              1,
              'review_first',
              'c7e00001-0000-0000-0000-000000000001'::uuid
            ),
            (
              2,
              'clearance_first',
              'c7e00002-0000-0000-0000-000000000002'::uuid
            ),
            (
              3,
              'timeout_first',
              'c7e00003-0000-0000-0000-000000000003'::uuid
            )
        ) rows(ordinal, label, snapshot_id)
        order by rows.ordinal
      loop
        perform public.record_evidence_quarantine(
          fixture.snapshot_id,
          'm7-integrity-v1',
          'd76-concurrency:' || fixture.label,
          3600000,
          jsonb_build_object(
            'disposition',
            'review_required',
            'evidenceStillScores',
            true
          )
        );
        perform pg_catalog.pg_sleep(0.01);
      end loop;
    end;
    $block$;

    -- All rows created inside this one fixture transaction intentionally share
    -- PostgreSQL transaction time. Space only these test deadlines so a sweep
    -- aimed at an earlier staged race cannot also claim timeout_first. The
    -- functional D76 suite separately proves the production derivation
    -- formula; this file proves only lock ordering.
    set session_replication_role = replica;
    update public.evidence_quarantines
    set review_deadline =
      review_deadline
      + case contest_id
          when 'c7000002-0000-0000-0000-000000000002'::uuid
            then interval '1 minute'
          when 'c7000003-0000-0000-0000-000000000003'::uuid
            then interval '8 days'
          else interval '0 minutes'
        end
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );
    set session_replication_role = origin;

    create function public.d76c_test_record_assessment(
      p_contest_id uuid
    )
    returns uuid
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    declare
      v_loaded            jsonb;
      v_standings         jsonb;
      v_outcome           jsonb;
      v_document          jsonb;
      v_quarantine_count  integer;
      v_pending_count     integer;
      v_approved_count    integer;
      v_rejected_count    integer;
    begin
      v_loaded := public.load_contest_integrity_input_v1(p_contest_id);

      select jsonb_agg(
        jsonb_build_object(
          'participant_id', roster ->> 'userId',
          'display_order', ordinal::integer,
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
        order by ordinal
      )
        into v_standings
      from jsonb_array_elements(v_loaded #> '{input,roster}')
        with ordinality roster_entry(roster, ordinal);

      v_outcome := jsonb_build_object(
        'kind',
        'void',
        'reason',
        'no_qualifying_participant'
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
        'evidence_cutoff', v_loaded ->> 'evidenceCutoff',
        'scoring_version', 'm4-v1',
        'integrity_configuration_version', 'm7-integrity-v1',
        'evidence_digest', v_loaded ->> 'evidenceDigest',
        'input_digest', v_loaded ->> 'inputDigest',
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
              'score', 100,
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
        (v_loaded ->> 'evidenceCutoff')::timestamptz,
        'm4-v1',
        'm7-integrity-v1',
        decode(v_loaded ->> 'evidenceDigest', 'hex'),
        decode(v_loaded ->> 'inputDigest', 'hex'),
        v_document,
        '[]'::jsonb
      );
    end;
    $function$;

    create function public.d76c_test_review_result(
      p_quarantine_id uuid,
      p_approved boolean
    )
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      perform public.review_evidence_quarantine(
        p_quarantine_id,
        p_approved
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create function public.d76c_test_clear_result(
      p_request_id uuid,
      p_quarantine_id uuid
    )
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    declare
      v_event_id uuid;
    begin
      v_event_id := public.clear_evidence_quarantine_v1(
        p_request_id,
        p_quarantine_id
      );
      return v_event_id::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    revoke all on function
      public.d76c_test_record_assessment(uuid),
      public.d76c_test_review_result(uuid, boolean),
      public.d76c_test_clear_result(uuid, uuid)
      from public, anon, authenticated;
    grant execute on function
      public.d76c_test_review_result(uuid, boolean)
      to authenticated;
    grant execute on function
      public.d76c_test_clear_result(uuid, uuid)
      to service_role;
  $setup$
);

create temporary table t_d76c_quarantines as
select remote.*
from extensions.dblink(
  'd76c_setup',
  $query$
    select
      quarantine.contest_id,
      quarantine.id,
      quarantine.review_deadline
    from public.evidence_quarantines quarantine
    where quarantine.contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    )
    order by quarantine.contest_id
  $query$
) as remote(
  contest_id uuid,
  quarantine_id uuid,
  review_deadline timestamptz
);

-- Reject the clearance-first fixture before the races. The rejection trigger
-- must synchronously create its adjudication, then the trusted boundary freezes
-- that peer state. The timeout-first fixture remains pending so the worker-first
-- review race can exercise the opposite commit order below.
select extensions.dblink_exec('d76c_setup', 'set role authenticated');
select extensions.dblink_exec(
  'd76c_setup',
  $claim$set "request.jwt.claims" =
    '{"sub":"c7222222-2222-2222-2222-222222222222"}'$claim$
);

create temporary table t_d76c_rejections as
select
  'c7000002-0000-0000-0000-000000000002'::uuid as contest_id,
  remote.result
from extensions.dblink(
  'd76c_setup',
  format(
    'select public.d76c_test_review_result(%L::uuid, false)',
    (
      select quarantine_id
      from t_d76c_quarantines
      where contest_id =
        'c7000002-0000-0000-0000-000000000002'
    )
  )
) as remote(result text);

select is(
  (select count(*) from t_d76c_rejections where result = 'ok'),
  1::bigint,
  'the clearance race escalates from a committed peer rejection'
);

select extensions.dblink_exec('d76c_setup', 'reset role');
select extensions.dblink_exec(
  'd76c_setup',
  'reset "request.jwt.claims"'
);
select extensions.dblink_exec(
  'd76c_setup',
  $assess$
    do $block$
    begin
      perform public.d76c_test_record_assessment(
        'c7000002-0000-0000-0000-000000000002'
      );
    end;
    $block$;
  $assess$
);

create temporary table t_d76c_adjudications as
select remote.*
from extensions.dblink(
  'd76c_setup',
  $query$
    select
      adjudication.contest_id,
      adjudication.quarantine_id,
      adjudication.adjudication_deadline
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.contest_id =
      'c7000002-0000-0000-0000-000000000002'
    order by adjudication.contest_id
  $query$
) as remote(
  contest_id uuid,
  quarantine_id uuid,
  adjudication_deadline timestamptz
);

-- ---------------------------------------------------------------------------
-- Reviewer commits first: SKIP LOCKED leaves the in-flight review alone.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('d76c_first', 'set role authenticated');
select extensions.dblink_exec(
  'd76c_first',
  $claim$set "request.jwt.claims" =
    '{"sub":"c7222222-2222-2222-2222-222222222222"}'$claim$
);
select is(
  extensions.dblink_exec('d76c_first', 'begin'),
  'BEGIN',
  'the peer reviewer begins a lock-retaining transaction'
);

create temporary table t_d76c_review_first as
select remote.result
from extensions.dblink(
  'd76c_first',
  format(
    'select public.d76c_test_review_result(%L::uuid, true)',
    (
      select quarantine_id
      from t_d76c_quarantines
      where contest_id =
        'c7000001-0000-0000-0000-000000000001'
    )
  )
) as remote(result text);

select is(
  (select result from t_d76c_review_first),
  'ok',
  'the peer approval succeeds while retaining the quarantine lock'
);

select is(
  extensions.dblink_send_query(
    'd76c_second',
    format(
      'select * from app.process_evidence_quarantine_deadlines_at(%L::timestamptz, 100)',
      (
        select review_deadline
        from t_d76c_quarantines
        where contest_id =
          'c7000001-0000-0000-0000-000000000001'
      )
    )
  ),
  1,
  'the exact-boundary deadline sweep starts concurrently'
);
select ok(
  pg_temp.wait_for_d76_query('d76c_second'),
  'the deadline sweep skips rather than waits on the in-flight review'
);

create temporary table t_d76c_review_worker as
select remote.*
from extensions.dblink_get_result('d76c_second') as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);
select *
from extensions.dblink_get_result('d76c_second') as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);

select ok(
  (
    select
      quarantines_escalated = 0
      and contests_timed_out = 0
    from t_d76c_review_worker
  ),
  'the skipped row creates no speculative adjudication or result'
);
select is(
  extensions.dblink_exec('d76c_first', 'commit'),
  'COMMIT',
  'the peer approval commits after the non-blocking sweep'
);
select extensions.dblink_exec('d76c_first', 'reset role');
select extensions.dblink_exec(
  'd76c_first',
  'reset "request.jwt.claims"'
);

select ok(
  (
    select approved
    from extensions.dblink(
      'd76c_setup',
      $query$
        select
          status.peer_state = 'approved'
          and status.adjudication_id is null
        from public.evidence_quarantine_status status
        where status.contest_id =
          'c7000001-0000-0000-0000-000000000001'
      $query$
    ) as remote(approved boolean)
  ),
  'the committed approval remains approved with no adjudication'
);

-- ---------------------------------------------------------------------------
-- Clearance commits first: a waiting timer rechecks and becomes a no-op.
-- ---------------------------------------------------------------------------

select is(
  extensions.dblink_exec('d76c_first', 'begin'),
  'BEGIN',
  'the service clearance begins a lock-retaining transaction'
);
select extensions.dblink_exec('d76c_first', 'set local role service_role');

create temporary table t_d76c_clearance_first as
select remote.result
from extensions.dblink(
  'd76c_first',
  format(
    'select public.d76c_test_clear_result(%L::uuid, %L::uuid)',
    'c7a00001-0000-0000-0000-000000000001',
    (
      select quarantine_id
      from t_d76c_adjudications
      where contest_id =
        'c7000002-0000-0000-0000-000000000002'
    )
  )
) as remote(result text);

select matches(
  (select result from t_d76c_clearance_first),
  '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  'the service clearance appends one event before its deadline'
);

select is(
  extensions.dblink_send_query(
    'd76c_second',
    format(
      'select * from app.process_evidence_quarantine_deadlines_at(%L::timestamptz, 100)',
      (
        select adjudication_deadline
        from t_d76c_adjudications
        where contest_id =
          'c7000002-0000-0000-0000-000000000002'
      )
    )
  ),
  1,
  'the competing timeout sweep starts while clearance is uncommitted'
);
select ok(
  pg_temp.wait_for_d76_backend(
    'gametime_d76_concurrency_second',
    true
  ),
  'the timeout waits at the clearance serialization lock'
);
select is(
  extensions.dblink_exec('d76c_first', 'commit'),
  'COMMIT',
  'committing clearance releases the timeout worker'
);

create temporary table t_d76c_clearance_worker as
select remote.*
from extensions.dblink_get_result('d76c_second') as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);
select *
from extensions.dblink_get_result('d76c_second') as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);

select ok(
  (
    select
      quarantines_escalated = 0
      and contests_timed_out = 0
    from t_d76c_clearance_worker
  ),
  'the waiting timer rechecks clearance and reports no timeout transition'
);
select ok(
  (
    select safe
    from extensions.dblink(
      'd76c_setup',
      $query$
        select
          contest.status = 'active'
          and terminal.resolution = 'cleared'
          and not exists (
            select 1
            from public.contest_results result
            where result.contest_id = contest.id
          )
        from public.contests contest
        join app.evidence_quarantine_adjudication_events terminal
          on terminal.contest_id = contest.id
        where contest.id =
          'c7000002-0000-0000-0000-000000000002'
      $query$
    ) as remote(safe boolean)
  ),
  'clearance wins without fabricating a result or finalizing the contest'
);

-- ---------------------------------------------------------------------------
-- Escalation commits first: a waiting peer review rechecks and is rejected.
-- ---------------------------------------------------------------------------

select is(
  extensions.dblink_exec('d76c_first', 'begin'),
  'BEGIN',
  'the exact-boundary escalation worker begins a lock-retaining transaction'
);

create temporary table t_d76c_escalation_first as
select remote.*
from extensions.dblink(
  'd76c_first',
  format(
    'select * from app.process_evidence_quarantine_deadlines_at(%L::timestamptz, 100)',
    (
      select review_deadline
      from t_d76c_quarantines
      where contest_id =
        'c7000003-0000-0000-0000-000000000003'
    )
  )
) as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);

select ok(
  (
    select
      quarantines_escalated = 1
      and contests_timed_out = 0
    from t_d76c_escalation_first
  ),
  'the exact peer boundary creates one adjudication and no result'
);

select extensions.dblink_exec('d76c_second', 'set role authenticated');
select extensions.dblink_exec(
  'd76c_second',
  $claim$set "request.jwt.claims" =
    '{"sub":"c7222222-2222-2222-2222-222222222222"}'$claim$
);
select is(
  extensions.dblink_send_query(
    'd76c_second',
    format(
      'select public.d76c_test_review_result(%L::uuid, true)',
      (
        select quarantine_id
        from t_d76c_quarantines
        where contest_id =
          'c7000003-0000-0000-0000-000000000003'
      )
    )
  ),
  1,
  'a competing peer approval starts while escalation is uncommitted'
);
select ok(
  pg_temp.wait_for_d76_backend(
    'gametime_d76_concurrency_second',
    true
  ),
  'the peer approval waits at the escalation serialization lock'
);
select is(
  extensions.dblink_exec('d76c_first', 'commit'),
  'COMMIT',
  'committing escalation releases the late peer review'
);

create temporary table t_d76c_late_review as
select remote.result
from extensions.dblink_get_result('d76c_second') as remote(result text);
select *
from extensions.dblink_get_result('d76c_second') as remote(result text);

select is(
  (select result from t_d76c_late_review),
  '23001',
  'the late peer approval rechecks and cannot overtake adjudication'
);
select extensions.dblink_exec('d76c_second', 'reset role');
select extensions.dblink_exec(
  'd76c_second',
  'reset "request.jwt.claims"'
);

select extensions.dblink_exec(
  'd76c_setup',
  $assess$
    do $block$
    begin
      perform public.d76c_test_record_assessment(
        'c7000003-0000-0000-0000-000000000003'
      );
    end;
    $block$;
  $assess$
);

insert into t_d76c_adjudications
select remote.*
from extensions.dblink(
  'd76c_setup',
  $query$
    select
      adjudication.contest_id,
      adjudication.quarantine_id,
      adjudication.adjudication_deadline
    from app.evidence_quarantine_adjudications adjudication
    where adjudication.contest_id =
      'c7000003-0000-0000-0000-000000000003'
  $query$
) as remote(
  contest_id uuid,
  quarantine_id uuid,
  adjudication_deadline timestamptz
);

select ok(
  (
    select frozen
    from extensions.dblink(
      'd76c_setup',
      $query$
        select
          status.peer_state = 'pending'
          and status.adjudication_id is not null
          and exists (
            select 1
            from app.contest_integrity_assessments assessment
            where assessment.contest_id = status.contest_id
          )
        from public.evidence_quarantine_status status
        where status.contest_id =
          'c7000003-0000-0000-0000-000000000003'
      $query$
    ) as remote(frozen boolean)
  ),
  'worker-first escalation preserves peer silence and freezes an assessment'
);

-- ---------------------------------------------------------------------------
-- Timer commits first: late clearance blocks, rechecks, and is rejected.
-- ---------------------------------------------------------------------------

select is(
  extensions.dblink_exec('d76c_first', 'begin'),
  'BEGIN',
  'the terminal timeout worker begins a lock-retaining transaction'
);

create temporary table t_d76c_timeout_first as
select remote.*
from extensions.dblink(
  'd76c_first',
  format(
    'select * from app.process_evidence_quarantine_deadlines_at(%L::timestamptz, 100)',
    (
      select adjudication_deadline
      from t_d76c_adjudications
      where contest_id =
        'c7000003-0000-0000-0000-000000000003'
    )
  )
) as remote(
  quarantines_escalated integer,
  contests_timed_out integer
);

select ok(
  (
    select
      quarantines_escalated = 0
      and contests_timed_out = 1
    from t_d76c_timeout_first
  ),
  'the due timer creates one fail-closed result while retaining its locks'
);

select extensions.dblink_exec('d76c_second', 'set role service_role');
select is(
  extensions.dblink_send_query(
    'd76c_second',
    format(
      'select public.d76c_test_clear_result(%L::uuid, %L::uuid)',
      'c7a00002-0000-0000-0000-000000000002',
      (
        select quarantine_id
        from t_d76c_adjudications
        where contest_id =
          'c7000003-0000-0000-0000-000000000003'
      )
    )
  ),
  1,
  'a competing service clearance starts while timeout is uncommitted'
);
select ok(
  pg_temp.wait_for_d76_backend(
    'gametime_d76_concurrency_second',
    true
  ),
  'late clearance waits at the timeout serialization lock'
);
select is(
  extensions.dblink_exec('d76c_first', 'commit'),
  'COMMIT',
  'committing timeout releases the late clearance'
);

create temporary table t_d76c_late_clearance as
select remote.result
from extensions.dblink_get_result('d76c_second') as remote(result text);
select *
from extensions.dblink_get_result('d76c_second') as remote(result text);

select is(
  (select result from t_d76c_late_clearance),
  '23001',
  'the late clearance rechecks and rejects the already-terminal contest'
);
select extensions.dblink_exec('d76c_second', 'reset role');

select ok(
  (
    select terminal
    from extensions.dblink(
      'd76c_setup',
      $query$
        select
          contest.status = 'finalized'
          and result.kind = 'inconclusive'
          and result.reason = 'review_timeout'
          and terminal.resolution = 'review_timeout'
          and not exists (
            select 1
            from public.donation_obligations obligation
            where obligation.contest_id = contest.id
          )
        from public.contests contest
        join public.contest_results result
          on result.contest_id = contest.id
        join app.evidence_quarantine_adjudication_events terminal
          on terminal.contest_id = contest.id
        where contest.id =
          'c7000003-0000-0000-0000-000000000003'
      $query$
    ) as remote(terminal boolean)
  ),
  'timeout wins only as inconclusive review_timeout with no obligation'
);

-- Every committed fixture and test-only helper is removed after both sessions
-- finish, because the outer pgTAP rollback cannot see across dblink commits.
select extensions.dblink_exec(
  'd76c_setup',
  $cleanup$
    set session_replication_role = replica;

    drop function public.d76c_test_record_assessment(uuid);
    drop function public.d76c_test_review_result(uuid, boolean);
    drop function public.d76c_test_clear_result(uuid, uuid);

    delete from public.donation_obligations
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.contest_standing_entries
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.contest_standing_snapshots
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.contest_results
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from app.contest_integrity_assessments
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from app.evidence_quarantine_adjudication_events
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from app.evidence_quarantine_adjudications
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.evidence_quarantine_reviews
    where quarantine_id in (
      select quarantine.id
      from public.evidence_quarantines quarantine
      where quarantine.contest_id in (
        'c7000001-0000-0000-0000-000000000001',
        'c7000002-0000-0000-0000-000000000002',
        'c7000003-0000-0000-0000-000000000003'
      )
    );

    delete from public.evidence_quarantines
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.metric_snapshots
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.ingest_batches
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.notification_intents
    where recipient_user_id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    )
       or entity_id in (
         'c7000001-0000-0000-0000-000000000001',
         'c7000002-0000-0000-0000-000000000002',
         'c7000003-0000-0000-0000-000000000003'
       );

    delete from app.account_capabilities
    where actor_id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    )
       or (
         scope_kind = 'contest_lineage'
         and scope_id in (
           'c7000001-0000-0000-0000-000000000001',
           'c7000002-0000-0000-0000-000000000002',
           'c7000003-0000-0000-0000-000000000003'
         )
       );

    delete from app.workflow_scope_actors
    where scope_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    )
       or actor_id in (
         'c7111111-1111-1111-1111-111111111111',
         'c7222222-2222-2222-2222-222222222222'
       );

    delete from app.workflow_scopes
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.contest_participants
    where contest_id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from public.contests
    where id in (
      'c7000001-0000-0000-0000-000000000001',
      'c7000002-0000-0000-0000-000000000002',
      'c7000003-0000-0000-0000-000000000003'
    );

    delete from app.profile_handle_claims
    where actor_id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    );

    delete from public.profiles
    where id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    );

    delete from auth.users
    where id in (
      'c7111111-1111-1111-1111-111111111111',
      'c7222222-2222-2222-2222-222222222222'
    );

    delete from public.charities
    where id = 'c7c00001-0000-0000-0000-000000000001';

    set session_replication_role = origin;
  $cleanup$
);

select is(
  (
    select remaining
    from extensions.dblink(
      'd76c_setup',
      $query$
        select count(*)::bigint
        from public.contests
        where id in (
          'c7000001-0000-0000-0000-000000000001',
          'c7000002-0000-0000-0000-000000000002',
          'c7000003-0000-0000-0000-000000000003'
        )
      $query$
    ) as remote(remaining bigint)
  ),
  0::bigint,
  'the committed concurrency fixtures are removed after verification'
);

select is(
  extensions.dblink_disconnect('d76c_first'),
  'OK',
  'the first concurrency session disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('d76c_second'),
  'OK',
  'the second concurrency session disconnects cleanly'
);
select extensions.dblink_disconnect('d76c_setup');

select * from finish();
rollback;
