-- Real database sessions prove the one-unsettled create boundary and both
-- commit orders at the appeal-deadline settlement race.

begin;
select no_plan();

select has_extension(
  'extensions', 'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_solo_blocked(
  p_application_names text[],
  p_timeout_seconds double precision default 5
)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deadline timestamptz := pg_catalog.clock_timestamp()
    + pg_catalog.make_interval(secs => p_timeout_seconds);
begin
  loop
    -- PostgreSQL otherwise reuses one statistics snapshot for this transaction,
    -- which can hide a worker that begins waiting after the first poll.
    perform pg_catalog.pg_stat_clear_snapshot();

    if (
      select count(*) = pg_catalog.cardinality(p_application_names)
      from pg_catalog.pg_stat_activity activity
      where activity.application_name = any (p_application_names)
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
  'solo_concurrency_setup',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_create_gate',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_create_one',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_create_two',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_appeal_first',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_settle_after_appeal',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_settle_first',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_appeal_after_settle',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'solo_concurrency_setup',
  $setup$
    insert into auth.users (id)
    values
      ('c5111111-1111-1111-1111-111111111111'),
      ('c5222222-2222-2222-2222-222222222222'),
      ('c5333333-3333-3333-3333-333333333333');

    insert into public.profiles (id, handle, display_name, timezone)
    values
      (
        'c5111111-1111-1111-1111-111111111111',
        'solocreaterace',
        'Solo Create Race',
        'UTC'
      ),
      (
        'c5222222-2222-2222-2222-222222222222',
        'soloappealwins',
        'Solo Appeal Wins',
        'UTC'
      ),
      (
        'c5333333-3333-3333-3333-333333333333',
        'solosettlewins',
        'Solo Settlement Wins',
        'UTC'
      );

    create function public.solo_test_create_result(p_request_id uuid)
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      return public.create_solo_contract_v1(
        p_request_id,
        'solo-test-v1',
        'daily',
        10000,
        1000,
        'UTC',
        '2098-08-01',
        1::smallint
      )::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create function public.solo_test_appeal_at_result(
      p_contract_id uuid,
      p_evaluation_id uuid,
      p_request_id uuid,
      p_test_now timestamptz
    )
    returns text
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    begin
      return app.file_solo_appeal_at_v1(
        p_contract_id,
        p_evaluation_id,
        p_request_id,
        'Please review the complete evidence.',
        p_test_now
      )::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create function public.solo_test_settle_at_result(
      p_contract_id uuid,
      p_request_id uuid,
      p_test_now timestamptz
    )
    returns text
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    begin
      return app.settle_solo_contract_at_v1(
        p_contract_id,
        p_request_id,
        p_test_now
      )::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    grant execute on function public.solo_test_create_result(uuid),
                              public.solo_test_appeal_at_result(
                                uuid, uuid, uuid, timestamptz
                              )
      to authenticated;

    do $block$
    begin
      perform public.set_solo_beta_eligibility_v1(
        'c5000000-0000-0000-0000-000000000001',
        'c5111111-1111-1111-1111-111111111111',
        true
      );
      perform public.set_solo_beta_eligibility_v1(
        'c5000000-0000-0000-0000-000000000002',
        'c5222222-2222-2222-2222-222222222222',
        true
      );
      perform public.set_solo_beta_eligibility_v1(
        'c5000000-0000-0000-0000-000000000003',
        'c5333333-3333-3333-3333-333333333333',
        true
      );
      perform public.set_solo_contract_runtime_v1(
        'c5000000-0000-0000-0000-000000000004',
        true,
        'solo-test-v1'
      );
    end;
    $block$;
  $setup$
);

-- ---------------------------------------------------------------------------
-- Two distinct create requests serialize and consume one open slot
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'solo_create_gate',
  $$ set application_name = 'gametime_solo_create_gate' $$
);
select extensions.dblink_exec('solo_create_gate', 'begin');
select extensions.dblink_exec(
  'solo_create_gate',
  $$ set app.solo_write_path = 'runtime_v1' $$
);
select extensions.dblink_exec(
  'solo_create_gate',
  $$ update app.solo_contract_runtime
     set updated_at = updated_at
     where singleton $$
);

select extensions.dblink_exec(
  'solo_create_one',
  $$ set application_name = 'gametime_solo_create_one' $$
);
select extensions.dblink_exec('solo_create_one', 'set role authenticated');
select extensions.dblink_exec(
  'solo_create_one',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5111111-1111-1111-1111-111111111111"}'$claim$
);

select extensions.dblink_exec(
  'solo_create_two',
  $$ set application_name = 'gametime_solo_create_two' $$
);
select extensions.dblink_exec('solo_create_two', 'set role authenticated');
select extensions.dblink_exec(
  'solo_create_two',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5111111-1111-1111-1111-111111111111"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'solo_create_one',
    $$ select public.solo_test_create_result(
         'c5000000-0000-0000-0000-000000000010'
       ) $$
  ) = 1,
  'the first distinct Solo create request starts asynchronously'
);

select ok(
  extensions.dblink_send_query(
    'solo_create_two',
    $$ select public.solo_test_create_result(
         'c5000000-0000-0000-0000-000000000011'
       ) $$
  ) = 1,
  'the second distinct Solo create request starts asynchronously'
);

select ok(
  pg_temp.wait_for_solo_blocked(
    array['gametime_solo_create_one', 'gametime_solo_create_two']
  ),
  'both create callers are visibly blocked on the authoritative runtime row'
);

select is(
  extensions.dblink_exec('solo_create_gate', 'commit'),
  'COMMIT',
  'releasing the runtime row lets the two creation transactions serialize'
);

create temporary table t_solo_create_one as
select result
from extensions.dblink_get_result(
  'solo_create_one'
) as response(result text);

create temporary table t_solo_create_two as
select result
from extensions.dblink_get_result(
  'solo_create_two'
) as response(result text);

-- dblink's async API requires a final empty drain before reuse/disconnect.
select count(*)
from extensions.dblink_get_result(
  'solo_create_one'
) as response(result text);
select count(*)
from extensions.dblink_get_result(
  'solo_create_two'
) as response(result text);

select is(
  (
    select count(*)
    from (
      select result from t_solo_create_one
      union all
      select result from t_solo_create_two
    ) outcome
    where outcome.result
      ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ),
  1::bigint,
  'exactly one simultaneous distinct request creates a Solo contract'
);

select is(
  (
    select count(*)
    from (
      select result from t_solo_create_one
      union all
      select result from t_solo_create_two
    ) outcome
    where outcome.result = '23505'
  ),
  1::bigint,
  'the competing distinct request receives the one-unsettled conflict'
);

select is(
  (
    select contract_count
    from extensions.dblink(
      'solo_concurrency_setup',
      $$ select count(*)::bigint
         from public.solo_contracts
         where owner_id = 'c5111111-1111-1111-1111-111111111111'
           and closed_at is null $$
    ) as result(contract_count bigint)
  ),
  1::bigint,
  'the create race commits one unsettled contract'
);

select is(
  (
    select request_count
    from extensions.dblink(
      'solo_concurrency_setup',
      $$ select count(*)::bigint
         from app.solo_rpc_requests
         where operation = 'create_solo_contract_v1'
           and request_scope = 'c5111111-1111-1111-1111-111111111111' $$
    ) as result(request_count bigint)
  ),
  1::bigint,
  'only the winning creation request reaches the exact-request ledger'
);

-- ---------------------------------------------------------------------------
-- Build two preliminary failures with deterministic synthetic clocks
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'solo_concurrency_setup',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_concurrency_setup',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5222222-2222-2222-2222-222222222222"}'$claim$
);

create temporary table t_solo_appeal_contract as
select contract_id
from extensions.dblink(
  'solo_concurrency_setup',
  $$ select public.create_solo_contract_v1(
       'c5000000-0000-0000-0000-000000000020',
       'solo-test-v1',
       'daily',
       10000,
       2000,
       'UTC',
       '2098-09-01',
       1::smallint
     ) $$
) as result(contract_id uuid);

select extensions.dblink_exec(
  'solo_concurrency_setup',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5333333-3333-3333-3333-333333333333"}'$claim$
);

create temporary table t_solo_settle_contract as
select contract_id
from extensions.dblink(
  'solo_concurrency_setup',
  $$ select public.create_solo_contract_v1(
       'c5000000-0000-0000-0000-000000000030',
       'solo-test-v1',
       'daily',
       10000,
       3000,
       'UTC',
       '2098-10-01',
       1::smallint
     ) $$
) as result(contract_id uuid);

select extensions.dblink_exec('solo_concurrency_setup', 'reset role');

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_appeal_contract),
        'c5000000-0000-0000-0000-000000000021',
        'active',
        '2098-09-01T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_appeal_contract),
  'the appeal-first fixture advances to active under a synthetic clock'
);

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_appeal_contract),
        'c5000000-0000-0000-0000-000000000022',
        'awaiting_evaluation',
        '2098-09-03T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_appeal_contract),
  'the appeal-first fixture reaches its evidence cutoff'
);

create temporary table t_solo_appeal_evaluation as
select evaluation_id
from extensions.dblink(
  'solo_concurrency_setup',
  format(
    $query$
      select app.record_solo_evaluation_at_v1(
        %L,
        %L,
        'failed',
        'target_missed',
        'solo-evaluator-v1',
        pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'),
        %L
      )
    $query$,
    (select contract_id from t_solo_appeal_contract),
    'c5000000-0000-0000-0000-000000000023',
    '2098-09-03T00:01:00Z'
  )
) as result(evaluation_id uuid);

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_settle_contract),
        'c5000000-0000-0000-0000-000000000031',
        'active',
        '2098-10-01T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_settle_contract),
  'the settlement-first fixture advances to active under a synthetic clock'
);

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_settle_contract),
        'c5000000-0000-0000-0000-000000000032',
        'awaiting_evaluation',
        '2098-10-03T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_settle_contract),
  'the settlement-first fixture reaches its evidence cutoff'
);

create temporary table t_solo_settle_evaluation as
select evaluation_id
from extensions.dblink(
  'solo_concurrency_setup',
  format(
    $query$
      select app.record_solo_evaluation_at_v1(
        %L,
        %L,
        'failed',
        'target_missed',
        'solo-evaluator-v1',
        pg_catalog.decode(pg_catalog.repeat('22', 32), 'hex'),
        %L
      )
    $query$,
    (select contract_id from t_solo_settle_contract),
    'c5000000-0000-0000-0000-000000000033',
    '2098-10-03T00:01:00Z'
  )
) as result(evaluation_id uuid);

select is(
  (
    select count(*)
    from t_solo_appeal_evaluation
    where evaluation_id is not null
  )
  + (
    select count(*)
    from t_solo_settle_evaluation
    where evaluation_id is not null
  ),
  2::bigint,
  'both fixtures have one committed preliminary failure'
);

-- ---------------------------------------------------------------------------
-- Commit order one: the timely appeal commits before deadline settlement
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'solo_appeal_first',
  $$ set application_name = 'gametime_solo_appeal_first' $$
);
select extensions.dblink_exec(
  'solo_appeal_first',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_appeal_first',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5222222-2222-2222-2222-222222222222"}'$claim$
);
select extensions.dblink_exec('solo_appeal_first', 'begin');

create temporary table t_solo_appeal_first_result as
select result
from extensions.dblink(
  'solo_appeal_first',
  format(
    'select public.solo_test_appeal_at_result(%L, %L, %L, %L)',
    (select contract_id from t_solo_appeal_contract),
    (select evaluation_id from t_solo_appeal_evaluation),
    'c5000000-0000-0000-0000-000000000024',
    '2098-09-10T00:00:59Z'
  )
) as response(result text);

select extensions.dblink_exec(
  'solo_settle_after_appeal',
  $$ set application_name = 'gametime_solo_settle_after_appeal' $$
);

select ok(
  extensions.dblink_send_query(
    'solo_settle_after_appeal',
    format(
      'select public.solo_test_settle_at_result(%L, %L, %L)',
      (select contract_id from t_solo_appeal_contract),
      'c5000000-0000-0000-0000-000000000025',
      '2098-09-10T00:01:00Z'
    )
  ) = 1,
  'deadline settlement starts while the timely appeal is uncommitted'
);

select ok(
  pg_temp.wait_for_solo_blocked(
    array['gametime_solo_settle_after_appeal']
  ),
  'pg_blocking_pids observes settlement waiting on the appeal transaction'
);

select is(
  extensions.dblink_exec('solo_appeal_first', 'commit'),
  'COMMIT',
  'the timely appeal commits before deadline settlement'
);

create temporary table t_solo_settle_after_appeal_result as
select result
from extensions.dblink_get_result(
  'solo_settle_after_appeal'
) as response(result text);

select count(*)
from extensions.dblink_get_result(
  'solo_settle_after_appeal'
) as response(result text);

select ok(
  (select result from t_solo_appeal_first_result)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  'the winning appeal returns its immutable filing UUID'
);

select is(
  (select result from t_solo_settle_after_appeal_result),
  '23001',
  'settlement rechecks state after the lock and rejects an appeal-pending contract'
);

select ok(
  (
    select contract_status = 'appeal_pending'
       and disposition is null
       and appeal_count = 1
       and settlement_request_count = 0
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        $query$
          select
            contract.status::text,
            contract.settlement_disposition::text,
            (
              select count(*)::bigint
              from public.solo_appeals appeal
              where appeal.contract_id = contract.id
                and appeal.event_kind = 'filed'
            ),
            (
              select count(*)::bigint
              from app.solo_rpc_requests request
              where request.operation = 'settle_solo_contract_v1'
                and request.request_scope = contract.id
            )
          from public.solo_contracts contract
          where contract.id = %L
        $query$,
        (select contract_id from t_solo_appeal_contract)
      )
    ) as state(
      contract_status text,
      disposition text,
      appeal_count bigint,
      settlement_request_count bigint
    )
  ),
  'appeal-first serialization leaves one filing, no settlement, and no failed settlement ledger row'
);

-- ---------------------------------------------------------------------------
-- Commit order two: deadline settlement commits before the late appeal
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'solo_settle_first',
  $$ set application_name = 'gametime_solo_settle_first' $$
);
select extensions.dblink_exec('solo_settle_first', 'begin');

create temporary table t_solo_settle_first_result as
select result
from extensions.dblink(
  'solo_settle_first',
  format(
    'select public.solo_test_settle_at_result(%L, %L, %L)',
    (select contract_id from t_solo_settle_contract),
    'c5000000-0000-0000-0000-000000000034',
    '2098-10-10T00:01:00Z'
  )
) as response(result text);

select extensions.dblink_exec(
  'solo_appeal_after_settle',
  $$ set application_name = 'gametime_solo_appeal_after_settle' $$
);
select extensions.dblink_exec(
  'solo_appeal_after_settle',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_appeal_after_settle',
  $claim$set "request.jwt.claims" =
    '{"sub":"c5333333-3333-3333-3333-333333333333"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'solo_appeal_after_settle',
    format(
      'select public.solo_test_appeal_at_result(%L, %L, %L, %L)',
      (select contract_id from t_solo_settle_contract),
      (select evaluation_id from t_solo_settle_evaluation),
      'c5000000-0000-0000-0000-000000000035',
      '2098-10-10T00:00:59Z'
    )
  ) = 1,
  'the timely appeal starts while deadline settlement is uncommitted'
);

select ok(
  pg_temp.wait_for_solo_blocked(
    array['gametime_solo_appeal_after_settle']
  ),
  'pg_blocking_pids observes the appeal waiting on the settlement transaction'
);

select is(
  extensions.dblink_exec('solo_settle_first', 'commit'),
  'COMMIT',
  'deadline settlement commits before the competing appeal'
);

create temporary table t_solo_appeal_after_settle_result as
select result
from extensions.dblink_get_result(
  'solo_appeal_after_settle'
) as response(result text);

select count(*)
from extensions.dblink_get_result(
  'solo_appeal_after_settle'
) as response(result text);

select ok(
  (select result from t_solo_settle_first_result)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  'the winning settlement returns its contract UUID'
);

select is(
  (select result from t_solo_appeal_after_settle_result),
  '23001',
  'the appeal rechecks state after the lock and rejects a settled contract'
);

select ok(
  (
    select contract_status = 'settled'
       and disposition = 'forfeited'
       and appeal_count = 0
       and settlement_request_count = 1
    from extensions.dblink(
      'solo_concurrency_setup',
      format(
        $query$
          select
            contract.status::text,
            contract.settlement_disposition::text,
            (
              select count(*)::bigint
              from public.solo_appeals appeal
              where appeal.contract_id = contract.id
                and appeal.event_kind = 'filed'
            ),
            (
              select count(*)::bigint
              from app.solo_rpc_requests request
              where request.operation = 'settle_solo_contract_v1'
                and request.request_scope = contract.id
            )
          from public.solo_contracts contract
          where contract.id = %L
        $query$,
        (select contract_id from t_solo_settle_contract)
      )
    ) as state(
      contract_status text,
      disposition text,
      appeal_count bigint,
      settlement_request_count bigint
    )
  ),
  'settlement-first serialization forfeits logically, writes one ledger row, and creates no appeal'
);

-- ---------------------------------------------------------------------------
-- Disconnect workers, then remove every externally committed fixture
-- ---------------------------------------------------------------------------

select is(
  extensions.dblink_disconnect('solo_create_one'),
  'OK',
  'the first create caller disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_create_two'),
  'OK',
  'the second create caller disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_create_gate'),
  'OK',
  'the create gate disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_appeal_first'),
  'OK',
  'the appeal-first caller disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_settle_after_appeal'),
  'OK',
  'the blocked settlement caller disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_settle_first'),
  'OK',
  'the settlement-first caller disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_appeal_after_settle'),
  'OK',
  'the blocked appeal caller disconnects cleanly'
);

select extensions.dblink_exec(
  'solo_concurrency_setup',
  $cleanup$
    set session_replication_role = replica;

    drop function public.solo_test_create_result(uuid);
    drop function public.solo_test_appeal_at_result(
      uuid, uuid, uuid, timestamptz
    );
    drop function public.solo_test_settle_at_result(
      uuid, uuid, timestamptz
    );

    delete from app.solo_rpc_requests
    where request_id::text like 'c5000000-%';

    delete from public.solo_appeals
    where owner_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from public.solo_evaluations
    where owner_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from public.solo_contracts
    where owner_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from app.solo_beta_eligibility
    where owner_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    update app.solo_contract_runtime
    set contract_creation_enabled = false,
        active_policy_version = 'solo-test-v1',
        updated_at = pg_catalog.clock_timestamp()
    where singleton;

    delete from app.account_capabilities
    where actor_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from app.workflow_scope_actors
    where actor_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from app.profile_handle_claims
    where actor_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from public.profiles
    where id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    delete from auth.users
    where id in (
      'c5111111-1111-1111-1111-111111111111',
      'c5222222-2222-2222-2222-222222222222',
      'c5333333-3333-3333-3333-333333333333'
    );

    set session_replication_role = origin;
  $cleanup$
);

select ok(
  (
    select contract_count = 0
       and user_count = 0
       and not creation_enabled
    from extensions.dblink(
      'solo_concurrency_setup',
      $$ select
           (
             select count(*)::bigint
             from public.solo_contracts
             where owner_id in (
               'c5111111-1111-1111-1111-111111111111',
               'c5222222-2222-2222-2222-222222222222',
               'c5333333-3333-3333-3333-333333333333'
             )
           ),
           (
             select count(*)::bigint
             from auth.users
             where id in (
               'c5111111-1111-1111-1111-111111111111',
               'c5222222-2222-2222-2222-222222222222',
               'c5333333-3333-3333-3333-333333333333'
             )
           ),
           (
             select contract_creation_enabled
             from app.solo_contract_runtime
             where singleton
           ) $$
    ) as state(
      contract_count bigint,
      user_count bigint,
      creation_enabled boolean
    )
  ),
  'external Solo concurrency fixtures are removed and the creation switch is restored'
);

select is(
  extensions.dblink_disconnect('solo_concurrency_setup'),
  'OK',
  'the setup session disconnects cleanly'
);

select * from finish();
rollback;
