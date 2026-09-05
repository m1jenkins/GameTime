-- M7: real two-session execution proves the trusted loader/recorder lock order
-- serializes concurrent assessment attempts and returns one immutable id.

begin;
select plan(13);

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the test-only multi-session driver'
);

create function pg_temp.wait_for_m7_blocked_backend(
  p_application_name text,
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
    if exists (
      select 1
      from pg_catalog.pg_stat_activity activity
      where activity.application_name = p_application_name
        and pg_catalog.cardinality(
          pg_catalog.pg_blocking_pids(activity.pid)
        ) > 0
    ) then
      return true;
    end if;

    exit when pg_catalog.clock_timestamp() >= v_deadline;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
  return false;
end;
$$;

select extensions.dblink_connect(
  'm7_setup',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'm7_first',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'm7_second',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'm7_first',
  $$ set application_name = 'gametime_m7_assessment_first' $$
);
select extensions.dblink_exec(
  'm7_second',
  $$ set application_name = 'gametime_m7_assessment_second' $$
);

-- A test-only service-role wrapper composes the public load and record APIs.
-- It is committed with the fixture so both remote sessions can call it.
select extensions.dblink_exec(
  'm7_setup',
  $setup$
    insert into auth.users (id) values
      ('b7111111-1111-1111-1111-111111111111'),
      ('b7222222-2222-2222-2222-222222222222');

    insert into public.profiles (id, handle, display_name) values
      (
        'b7111111-1111-1111-1111-111111111111',
        'm7concurrentalice',
        'M7 Concurrent Alice'
      ),
      (
        'b7222222-2222-2222-2222-222222222222',
        'm7concurrentbob',
        'M7 Concurrent Bob'
      );

    insert into public.charities (id, name, ein, slug) values (
      'b7c00001-0000-0000-0000-000000000001',
      'M7 Concurrency Fund',
      '97-0000002',
      'm7-concurrency-fund'
    );

    alter table public.contests disable trigger contests_assert_future_window;

    insert into public.contests (
      id, title, created_by, metric, cadence, target_value,
      stake_amount_cents, tie_break, starts_at, ends_at, max_participants
    ) values (
      'b7000001-0000-0000-0000-000000000001',
      'M7 concurrent assessment',
      'b7111111-1111-1111-1111-111111111111',
      'steps',
      'cumulative',
      10000,
      100,
      'void',
      date_trunc('hour', clock_timestamp()) - interval '2 days',
      date_trunc('hour', clock_timestamp()) - interval '7 hours',
      2
    );

    alter table public.contests enable trigger contests_assert_future_window;

    insert into public.contest_participants (
      contest_id, user_id, status, timezone, charity_id
    ) values (
      'b7000001-0000-0000-0000-000000000001',
      'b7111111-1111-1111-1111-111111111111',
      'accepted',
      'UTC',
      'b7c00001-0000-0000-0000-000000000001'
    );

    insert into public.contest_participants (
      contest_id, user_id, status, invited_by
    ) values (
      'b7000001-0000-0000-0000-000000000001',
      'b7222222-2222-2222-2222-222222222222',
      'invited',
      'b7111111-1111-1111-1111-111111111111'
    );

    update public.contest_participants
    set status = 'accepted',
        timezone = 'UTC',
        charity_id = 'b7c00001-0000-0000-0000-000000000001'
    where contest_id = 'b7000001-0000-0000-0000-000000000001'
      and user_id = 'b7222222-2222-2222-2222-222222222222';

    update public.contests
    set status = 'active',
        activated_at = clock_timestamp()
    where id = 'b7000001-0000-0000-0000-000000000001';

    create function public.m7_test_record_clean_assessment(
      p_contest_id uuid
    )
    returns uuid
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    declare
      v_loaded jsonb;
      v_standings jsonb;
      v_outcome jsonb;
      v_document jsonb;
    begin
      v_loaded := public.load_contest_integrity_input_v1(p_contest_id);

      select jsonb_agg(jsonb_build_object(
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
        'rationale', jsonb_build_array(jsonb_build_object(
          'code', 'clean_evidence',
          'summary', 'No scored integrity deductions.',
          'points', 0
        ))
      ) order by ordinal)
        into v_standings
      from jsonb_array_elements(v_loaded #> '{input,roster}')
        with ordinality roster_entry(roster, ordinal);

      v_outcome := jsonb_build_object(
        'kind', 'void',
        'reason', 'no_qualifying_participant'
      );

      v_document := jsonb_build_object(
        'schema_version', 'm7-integrity-assessment-v1',
        'contest_id', p_contest_id,
        'evidence_cutoff', v_loaded ->> 'evidenceCutoff',
        'scoring_version', 'm4-v1',
        'integrity_configuration_version', 'm6-v1',
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
          'quarantine_state',
            jsonb_array_length(v_loaded #> '{input,quarantineState}'),
          'checkin_integrity',
            jsonb_array_length(v_loaded #> '{input,checkIns}'),
          'trusted_locations',
            jsonb_array_length(v_loaded #> '{input,locations}')
        ),
        'quarantine_observation', jsonb_build_object(
          'total', 0,
          'pending', 0,
          'approved', 0,
          'rejected', 0
        ),
        'required_quarantine_count', 0,
        'clean_zero_quarantines', true,
        'standings', v_standings,
        'outcome', v_outcome,
        'integrity', (
          select jsonb_agg(jsonb_build_object(
            'participant_id', standing ->> 'participant_id',
            'score', 100,
            'total_penalty', 0,
            'penalties', '{}'::jsonb,
            'flags', '[]'::jsonb
          ) order by (standing ->> 'display_order')::integer)
          from jsonb_array_elements(v_standings) standing
        )
      );

      return public.record_contest_integrity_assessment_v1(
        p_contest_id,
        (v_loaded ->> 'evidenceCutoff')::timestamptz,
        'm4-v1',
        'm6-v1',
        decode(v_loaded ->> 'evidenceDigest', 'hex'),
        decode(v_loaded ->> 'inputDigest', 'hex'),
        v_document,
        '[]'::jsonb
      );
    end;
    $function$;

    revoke all on function public.m7_test_record_clean_assessment(uuid)
      from public, anon, authenticated;
    grant execute on function
      public.m7_test_record_clean_assessment(uuid)
      to service_role;
  $setup$
);

select is(
  extensions.dblink_exec('m7_first', 'begin'),
  'BEGIN',
  'the first assessor begins a transaction that retains its locks'
);

select extensions.dblink_exec('m7_first', 'set local role service_role');

create temporary table t_m7_first_result as
select id
from extensions.dblink(
  'm7_first',
  $$ select public.m7_test_record_clean_assessment(
       'b7000001-0000-0000-0000-000000000001'
     ) $$
) as result(id uuid);

select ok(
  (select id is not null from t_m7_first_result),
  'the first assessor creates one complete assessment'
);

select is(
  extensions.dblink_send_query(
    'm7_second',
    $$ set role service_role;
       select public.m7_test_record_clean_assessment(
         'b7000001-0000-0000-0000-000000000001'
       ) $$
  ),
  1,
  'the competing assessor starts asynchronously'
);

select ok(
  pg_temp.wait_for_m7_blocked_backend(
    'gametime_m7_assessment_second'
  ),
  'the competing assessor waits on the first assessment lock'
);

select is(
  extensions.dblink_exec('m7_first', 'commit'),
  'COMMIT',
  'committing the first assessment releases the serialization point'
);

-- dblink_get_result first returns the SET status, then the SELECT row.
select *
from extensions.dblink_get_result('m7_second') as status(result text);

create temporary table t_m7_second_result as
select id
from extensions.dblink_get_result('m7_second') as result(id uuid);

select is(
  (select id from t_m7_second_result),
  (select id from t_m7_first_result),
  'the concurrent retry returns the exact first assessment id'
);

select is(
  (
    select assessment_count
    from extensions.dblink(
      'm7_setup',
      $$ select count(*)::bigint
         from app.contest_integrity_assessments
         where contest_id =
           'b7000001-0000-0000-0000-000000000001' $$
    ) as result(assessment_count bigint)
  ),
  1::bigint,
  'concurrent execution persists exactly one assessment'
);

select is(
  (
    select quarantine_count
    from extensions.dblink(
      'm7_setup',
      $$ select cardinality(materialized_quarantine_ids)
         from app.contest_integrity_assessments
         where contest_id =
           'b7000001-0000-0000-0000-000000000001' $$
    ) as result(quarantine_count integer)
  ),
  0,
  'the concurrent clean assessment remains an explicit zero-quarantine fact'
);

select is(
  (
    select clean
    from extensions.dblink(
      'm7_setup',
      $$ select (
           assessment_document ->> 'clean_zero_quarantines'
         )::boolean
         from app.contest_integrity_assessments
         where contest_id =
           'b7000001-0000-0000-0000-000000000001' $$
    ) as result(clean boolean)
  ),
  true,
  'the winning assessment retained the complete clean document'
);

-- Every committed fixture is targeted and removed after both sessions finish.
select extensions.dblink_exec(
  'm7_setup',
  $cleanup$
    set session_replication_role = replica;

    drop function public.m7_test_record_clean_assessment(uuid);

    delete from app.contest_integrity_assessments
    where contest_id = 'b7000001-0000-0000-0000-000000000001';

    delete from public.notification_intents
    where recipient_user_id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    )
       or entity_id = 'b7000001-0000-0000-0000-000000000001';

    delete from app.account_capabilities
    where actor_id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    )
       or (
         scope_kind = 'contest_lineage'
         and scope_id = 'b7000001-0000-0000-0000-000000000001'
       );

    delete from app.workflow_scope_actors
    where scope_id = 'b7000001-0000-0000-0000-000000000001'
       or actor_id in (
         'b7111111-1111-1111-1111-111111111111',
         'b7222222-2222-2222-2222-222222222222'
       );

    delete from app.workflow_scopes
    where contest_id = 'b7000001-0000-0000-0000-000000000001';

    delete from public.contest_participants
    where contest_id = 'b7000001-0000-0000-0000-000000000001';

    delete from public.contests
    where id = 'b7000001-0000-0000-0000-000000000001';

    delete from app.profile_handle_claims
    where actor_id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    );

    delete from public.profiles
    where id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    );

    delete from auth.users
    where id in (
      'b7111111-1111-1111-1111-111111111111',
      'b7222222-2222-2222-2222-222222222222'
    );

    delete from public.charities
    where id = 'b7c00001-0000-0000-0000-000000000001';

    set session_replication_role = origin;
  $cleanup$
);

select is(
  (
    select remaining
    from extensions.dblink(
      'm7_setup',
      $$ select count(*)::bigint
         from public.contests
         where id = 'b7000001-0000-0000-0000-000000000001' $$
    ) as result(remaining bigint)
  ),
  0::bigint,
  'the external concurrency fixture is removed after verification'
);

select is(
  extensions.dblink_disconnect('m7_first'),
  'OK',
  'the first assessment session disconnects cleanly'
);

select is(
  extensions.dblink_disconnect('m7_second'),
  'OK',
  'the second assessment session disconnects cleanly'
);

select extensions.dblink_disconnect('m7_setup');

select * from finish();
rollback;
