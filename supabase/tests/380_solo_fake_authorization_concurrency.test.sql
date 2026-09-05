-- Real database sessions prove atomic fake-authorization linkage and exactly
-- one terminal authorization event under create and settlement races.

begin;
select no_plan();

select has_extension(
  'extensions', 'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_solo_fake_blocked(
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
  'solo_fake_setup',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_fake_gate',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_fake_one',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'solo_fake_two',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'solo_fake_setup',
  $setup$
    insert into auth.users (id)
    values
      ('d8111111-1111-1111-1111-111111111111'),
      ('d8222222-2222-2222-2222-222222222222'),
      ('d8333333-3333-3333-3333-333333333333'),
      ('d8444444-4444-4444-4444-444444444444');

    insert into public.profiles (id, handle, display_name, timezone)
    values
      (
        'd8111111-1111-1111-1111-111111111111',
        'solofakesamerace',
        'Solo Fake Same Race',
        'UTC'
      ),
      (
        'd8222222-2222-2222-2222-222222222222',
        'solofakedifferentrace',
        'Solo Fake Different Race',
        'UTC'
      ),
      (
        'd8333333-3333-3333-3333-333333333333',
        'solofakesamesettle',
        'Solo Fake Same Settle',
        'UTC'
      ),
      (
        'd8444444-4444-4444-4444-444444444444',
        'solofakedifferentsettle',
        'Solo Fake Different Settle',
        'UTC'
      );

    do $block$
    begin
      perform public.set_solo_beta_eligibility_v1(
        'd8000000-0000-0000-0000-000000000001',
        'd8111111-1111-1111-1111-111111111111',
        true
      );
      perform public.set_solo_beta_eligibility_v1(
        'd8000000-0000-0000-0000-000000000002',
        'd8222222-2222-2222-2222-222222222222',
        true
      );
      perform public.set_solo_beta_eligibility_v1(
        'd8000000-0000-0000-0000-000000000003',
        'd8333333-3333-3333-3333-333333333333',
        true
      );
      perform public.set_solo_beta_eligibility_v1(
        'd8000000-0000-0000-0000-000000000004',
        'd8444444-4444-4444-4444-444444444444',
        true
      );
      perform public.set_solo_contract_runtime_v1(
        'd8000000-0000-0000-0000-000000000005',
        true,
        'solo-test-v1'
      );
    end;
    $block$;
  $setup$
);

-- Each worker owns session-local wrappers. Even if this test aborts before its
-- cleanup block, no persistent public SECURITY DEFINER surface can remain.
do $block$
declare
  v_helpers text := $helpers$
    create function pg_temp.solo_fake_test_create_result(
      p_request_id uuid,
      p_commitment_amount_minor integer,
      p_start_date date
    )
    returns jsonb
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      return public.create_solo_contract_with_fake_authorization_v2(
        p_request_id,
        'solo-test-v1',
        'daily',
        10000,
        p_commitment_amount_minor,
        'UTC',
        p_start_date,
        1::smallint
      );
    exception
      when others then
        return pg_catalog.jsonb_build_object('sqlstate', sqlstate);
    end;
    $function$;

    create function pg_temp.solo_fake_test_settle_result(
      p_contract_id uuid,
      p_request_id uuid,
      p_test_now timestamptz
    )
    returns jsonb
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    begin
      return pg_catalog.jsonb_build_object(
        'contract_id',
        app.settle_solo_contract_at_v1(
          p_contract_id,
          p_request_id,
          p_test_now
        )
      );
    exception
      when others then
        return pg_catalog.jsonb_build_object('sqlstate', sqlstate);
    end;
    $function$;

    revoke all on function pg_temp.solo_fake_test_create_result(
                              uuid, integer, date
                            ),
                            pg_temp.solo_fake_test_settle_result(
                              uuid, uuid, timestamptz
                            )
      from public, anon, authenticated, service_role;
    grant execute on function pg_temp.solo_fake_test_create_result(
                                uuid, integer, date
                              ),
                              pg_temp.solo_fake_test_settle_result(
                                uuid, uuid, timestamptz
                              )
      to authenticated;
  $helpers$;
begin
  perform extensions.dblink_exec('solo_fake_one', v_helpers);
  perform extensions.dblink_exec('solo_fake_two', v_helpers);
end;
$block$;

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'solo_fake_test_create_result',
        'solo_fake_test_settle_result'
      )
  ),
  0::bigint,
  'concurrency wrappers never create a persistent public function'
);

select extensions.dblink_exec(
  'solo_fake_gate',
  $$ set app.solo_write_path = 'runtime_v1' $$
);
select extensions.dblink_exec(
  'solo_fake_one',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_fake_two',
  'set role authenticated'
);

-- ---------------------------------------------------------------------------
-- The same simultaneous v2 request returns one committed linked aggregate
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('solo_fake_gate', 'begin');
select extensions.dblink_exec(
  'solo_fake_gate',
  $$ update app.solo_contract_runtime
     set updated_at = updated_at
     where singleton $$
);

select extensions.dblink_exec(
  'solo_fake_one',
  $$ set application_name = 'gametime_solo_fake_same_one' $$
);
select extensions.dblink_exec(
  'solo_fake_one',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8111111-1111-1111-1111-111111111111"}'$claim$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $$ set application_name = 'gametime_solo_fake_same_two' $$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8111111-1111-1111-1111-111111111111"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'solo_fake_one',
    $$ select pg_temp.solo_fake_test_create_result(
         'd8000000-0000-0000-0000-000000000010',
         1000,
         '2098-11-01'
       ) $$
  ) = 1,
  'the first same-request v2 creation starts asynchronously'
);
select ok(
  extensions.dblink_send_query(
    'solo_fake_two',
    $$ select pg_temp.solo_fake_test_create_result(
         'd8000000-0000-0000-0000-000000000010',
         1000,
         '2098-11-01'
       ) $$
  ) = 1,
  'the second same-request v2 creation starts asynchronously'
);

select ok(
  pg_temp.wait_for_solo_fake_blocked(
    array[
      'gametime_solo_fake_same_one',
      'gametime_solo_fake_same_two'
    ]
  ),
  'both same-request creators wait on the authoritative runtime row'
);

select is(
  extensions.dblink_exec('solo_fake_gate', 'commit'),
  'COMMIT',
  'releasing the runtime row lets same-request creators serialize'
);

create temporary table t_solo_fake_same_create_one as
select result
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);

create temporary table t_solo_fake_same_create_two as
select result
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

-- dblink's async API requires one final empty result drain before reuse.
select count(*)
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);
select count(*)
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select is(
  (select result from t_solo_fake_same_create_one),
  (select result from t_solo_fake_same_create_two),
  'simultaneous exact retries return the same contract and authorization IDs'
);
select is(
  (
    select result ->> 'outcome'
    from t_solo_fake_same_create_one
  ),
  'authorized',
  'the shared same-request result is an authorized fake outcome'
);

select ok(
  (
    select contract_count = 1
       and authorization_count = 1
       and event_count = 1
       and initial_event_count = 1
       and v1_request_count = 1
       and v2_request_count = 1
       and unlinked_contract_count = 0
    from extensions.dblink(
      'solo_fake_setup',
      $query$
        select
          (
            select count(*)::bigint
            from public.solo_contracts contract
            where contract.owner_id =
              'd8111111-1111-1111-1111-111111111111'
          ),
          (
            select count(*)::bigint
            from app.solo_authorizations authorization_row
            where authorization_row.owner_id =
              'd8111111-1111-1111-1111-111111111111'
          ),
          (
            select count(*)::bigint
            from app.solo_authorization_events event
            where event.owner_id =
              'd8111111-1111-1111-1111-111111111111'
          ),
          (
            select count(*)::bigint
            from app.solo_authorization_events event
            where event.owner_id =
                  'd8111111-1111-1111-1111-111111111111'
              and event.sequence_number = 1
              and event.event_kind = 'authorized'
          ),
          (
            select count(*)::bigint
            from app.solo_rpc_requests request
            where request.operation = 'create_solo_contract_v1'
              and request.request_scope =
                'd8111111-1111-1111-1111-111111111111'
          ),
          (
            select count(*)::bigint
            from app.solo_rpc_requests request
            where request.operation =
                    'create_solo_contract_with_fake_authorization_v2'
              and request.request_scope =
                'd8111111-1111-1111-1111-111111111111'
          ),
          (
            select count(*)::bigint
            from public.solo_contracts contract
            left join app.solo_authorizations authorization_row
              on authorization_row.contract_id = contract.id
            where contract.owner_id =
                  'd8111111-1111-1111-1111-111111111111'
              and authorization_row.id is null
          )
      $query$
    ) as state(
      contract_count bigint,
      authorization_count bigint,
      event_count bigint,
      initial_event_count bigint,
      v1_request_count bigint,
      v2_request_count bigint,
      unlinked_contract_count bigint
    )
  ),
  'the same-request race commits one contract, authorization, initial event, and exact-request pair'
);

-- ---------------------------------------------------------------------------
-- Distinct simultaneous v2 requests have one winner and no half-link
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('solo_fake_gate', 'begin');
select extensions.dblink_exec(
  'solo_fake_gate',
  $$ update app.solo_contract_runtime
     set updated_at = updated_at
     where singleton $$
);

select extensions.dblink_exec(
  'solo_fake_one',
  $$ set application_name = 'gametime_solo_fake_distinct_one' $$
);
select extensions.dblink_exec(
  'solo_fake_one',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8222222-2222-2222-2222-222222222222"}'$claim$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $$ set application_name = 'gametime_solo_fake_distinct_two' $$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8222222-2222-2222-2222-222222222222"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'solo_fake_one',
    $$ select pg_temp.solo_fake_test_create_result(
         'd8000000-0000-0000-0000-000000000020',
         2000,
         '2098-12-01'
       ) $$
  ) = 1,
  'the first distinct v2 creation starts asynchronously'
);
select ok(
  extensions.dblink_send_query(
    'solo_fake_two',
    $$ select pg_temp.solo_fake_test_create_result(
         'd8000000-0000-0000-0000-000000000021',
         2000,
         '2098-12-01'
       ) $$
  ) = 1,
  'the second distinct v2 creation starts asynchronously'
);

select ok(
  pg_temp.wait_for_solo_fake_blocked(
    array[
      'gametime_solo_fake_distinct_one',
      'gametime_solo_fake_distinct_two'
    ]
  ),
  'both distinct creators wait on the authoritative runtime row'
);

select is(
  extensions.dblink_exec('solo_fake_gate', 'commit'),
  'COMMIT',
  'releasing the runtime row lets distinct creators serialize'
);

create temporary table t_solo_fake_distinct_create_one as
select result
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);

create temporary table t_solo_fake_distinct_create_two as
select result
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select count(*)
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);
select count(*)
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select is(
  (
    select count(*)
    from (
      select result from t_solo_fake_distinct_create_one
      union all
      select result from t_solo_fake_distinct_create_two
    ) outcome
    where outcome.result ->> 'outcome' = 'authorized'
  ),
  1::bigint,
  'exactly one distinct request wins fake authorization'
);
select is(
  (
    select count(*)
    from (
      select result from t_solo_fake_distinct_create_one
      union all
      select result from t_solo_fake_distinct_create_two
    ) outcome
    where outcome.result ->> 'sqlstate' = '23505'
  ),
  1::bigint,
  'the losing distinct request receives the one-unsettled conflict'
);

select ok(
  (
    select contract_count = 1
       and authorization_count = 1
       and event_count = 1
       and initial_event_count = 1
       and v1_request_count = 1
       and v2_request_count = 1
       and unlinked_contract_count = 0
    from extensions.dblink(
      'solo_fake_setup',
      $query$
        select
          (
            select count(*)::bigint
            from public.solo_contracts contract
            where contract.owner_id =
              'd8222222-2222-2222-2222-222222222222'
          ),
          (
            select count(*)::bigint
            from app.solo_authorizations authorization_row
            where authorization_row.owner_id =
              'd8222222-2222-2222-2222-222222222222'
          ),
          (
            select count(*)::bigint
            from app.solo_authorization_events event
            where event.owner_id =
              'd8222222-2222-2222-2222-222222222222'
          ),
          (
            select count(*)::bigint
            from app.solo_authorization_events event
            where event.owner_id =
                  'd8222222-2222-2222-2222-222222222222'
              and event.sequence_number = 1
              and event.event_kind = 'authorized'
          ),
          (
            select count(*)::bigint
            from app.solo_rpc_requests request
            where request.operation = 'create_solo_contract_v1'
              and request.request_scope =
                'd8222222-2222-2222-2222-222222222222'
          ),
          (
            select count(*)::bigint
            from app.solo_rpc_requests request
            where request.operation =
                    'create_solo_contract_with_fake_authorization_v2'
              and request.request_scope =
                'd8222222-2222-2222-2222-222222222222'
          ),
          (
            select count(*)::bigint
            from public.solo_contracts contract
            left join app.solo_authorizations authorization_row
              on authorization_row.contract_id = contract.id
            where contract.owner_id =
                  'd8222222-2222-2222-2222-222222222222'
              and authorization_row.id is null
          )
      $query$
    ) as state(
      contract_count bigint,
      authorization_count bigint,
      event_count bigint,
      initial_event_count bigint,
      v1_request_count bigint,
      v2_request_count bigint,
      unlinked_contract_count bigint
    )
  ),
  'the distinct-request race leaves one fully linked aggregate and no losing ledger row'
);

-- ---------------------------------------------------------------------------
-- Build two linked contracts ready for logical release
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'solo_fake_setup',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_fake_setup',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8333333-3333-3333-3333-333333333333"}'$claim$
);

create temporary table t_solo_fake_same_settle_contract as
select (result ->> 'contract_id')::uuid as contract_id
from extensions.dblink(
  'solo_fake_setup',
  $$ select public.create_solo_contract_with_fake_authorization_v2(
       'd8000000-0000-0000-0000-000000000030',
       'solo-test-v1',
       'daily',
       10000,
       3000,
       'UTC',
       '2099-01-01',
       1::smallint
     ) $$
) as response(result jsonb);

select extensions.dblink_exec(
  'solo_fake_setup',
  'reset role'
);

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_fake_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_fake_same_settle_contract),
        'd8000000-0000-0000-0000-000000000031',
        'active',
        '2099-01-01T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_fake_same_settle_contract),
  'the same-request settlement fixture advances to active'
);
select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_fake_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_fake_same_settle_contract),
        'd8000000-0000-0000-0000-000000000032',
        'awaiting_evaluation',
        '2099-01-03T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_fake_same_settle_contract),
  'the same-request settlement fixture reaches its evidence cutoff'
);
select ok(
  (
    select evaluation_id is not null
    from extensions.dblink(
      'solo_fake_setup',
      format(
        $query$
          select app.record_solo_evaluation_at_v1(
            %L,
            %L,
            'passed',
            'target_met',
            'solo-evaluator-v1',
            pg_catalog.decode(pg_catalog.repeat('33', 32), 'hex'),
            %L
          )
        $query$,
        (select contract_id from t_solo_fake_same_settle_contract),
        'd8000000-0000-0000-0000-000000000033',
        '2099-01-03T00:01:00Z'
      )
    ) as result(evaluation_id uuid)
  ),
  'the same-request settlement fixture is ready to settle'
);

select extensions.dblink_exec(
  'solo_fake_setup',
  'set role authenticated'
);
select extensions.dblink_exec(
  'solo_fake_setup',
  $claim$set "request.jwt.claims" =
    '{"sub":"d8444444-4444-4444-4444-444444444444"}'$claim$
);

create temporary table t_solo_fake_distinct_settle_contract as
select (result ->> 'contract_id')::uuid as contract_id
from extensions.dblink(
  'solo_fake_setup',
  $$ select public.create_solo_contract_with_fake_authorization_v2(
       'd8000000-0000-0000-0000-000000000040',
       'solo-test-v1',
       'daily',
       10000,
       4000,
       'UTC',
       '2099-02-01',
       1::smallint
     ) $$
) as response(result jsonb);

select extensions.dblink_exec(
  'solo_fake_setup',
  'reset role'
);

select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_fake_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_fake_distinct_settle_contract),
        'd8000000-0000-0000-0000-000000000041',
        'active',
        '2099-02-01T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_fake_distinct_settle_contract),
  'the distinct-request settlement fixture advances to active'
);
select is(
  (
    select contract_id
    from extensions.dblink(
      'solo_fake_setup',
      format(
        'select app.advance_solo_contract_at_v1(%L, %L, %L, %L)',
        (select contract_id from t_solo_fake_distinct_settle_contract),
        'd8000000-0000-0000-0000-000000000042',
        'awaiting_evaluation',
        '2099-02-03T00:00:01Z'
      )
    ) as result(contract_id uuid)
  ),
  (select contract_id from t_solo_fake_distinct_settle_contract),
  'the distinct-request settlement fixture reaches its evidence cutoff'
);
select ok(
  (
    select evaluation_id is not null
    from extensions.dblink(
      'solo_fake_setup',
      format(
        $query$
          select app.record_solo_evaluation_at_v1(
            %L,
            %L,
            'passed',
            'target_met',
            'solo-evaluator-v1',
            pg_catalog.decode(pg_catalog.repeat('44', 32), 'hex'),
            %L
          )
        $query$,
        (select contract_id from t_solo_fake_distinct_settle_contract),
        'd8000000-0000-0000-0000-000000000043',
        '2099-02-03T00:01:00Z'
      )
    ) as result(evaluation_id uuid)
  ),
  'the distinct-request settlement fixture is ready to settle'
);

-- ---------------------------------------------------------------------------
-- Simultaneous exact settlement retries append one terminal event
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('solo_fake_gate', 'begin');
select locked_id
from extensions.dblink(
  'solo_fake_gate',
  $$ select id::text
     from public.profiles
     where id = 'd8333333-3333-3333-3333-333333333333'
     for update $$
) as result(locked_id text);

select extensions.dblink_exec(
  'solo_fake_one',
  $$ set application_name = 'gametime_solo_fake_settle_same_one' $$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $$ set application_name = 'gametime_solo_fake_settle_same_two' $$
);

select ok(
  extensions.dblink_send_query(
    'solo_fake_one',
    format(
      'select pg_temp.solo_fake_test_settle_result(%L, %L, %L)',
      (select contract_id from t_solo_fake_same_settle_contract),
      'd8000000-0000-0000-0000-000000000034',
      '2099-01-03T00:02:00Z'
    )
  ) = 1,
  'the first exact settlement retry starts asynchronously'
);
select ok(
  extensions.dblink_send_query(
    'solo_fake_two',
    format(
      'select pg_temp.solo_fake_test_settle_result(%L, %L, %L)',
      (select contract_id from t_solo_fake_same_settle_contract),
      'd8000000-0000-0000-0000-000000000034',
      '2099-01-03T00:02:00Z'
    )
  ) = 1,
  'the second exact settlement retry starts asynchronously'
);

select ok(
  pg_temp.wait_for_solo_fake_blocked(
    array[
      'gametime_solo_fake_settle_same_one',
      'gametime_solo_fake_settle_same_two'
    ]
  ),
  'both exact settlement retries wait on the owner finality lock'
);

select is(
  extensions.dblink_exec('solo_fake_gate', 'commit'),
  'COMMIT',
  'releasing the owner lets exact settlement retries serialize'
);

create temporary table t_solo_fake_same_settle_one as
select result
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);

create temporary table t_solo_fake_same_settle_two as
select result
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select count(*)
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);
select count(*)
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select is(
  (select result from t_solo_fake_same_settle_one),
  (select result from t_solo_fake_same_settle_two),
  'simultaneous exact settlement retries return the same contract ID'
);
select is(
  (
    select count(*)
    from (
      select result from t_solo_fake_same_settle_one
      union all
      select result from t_solo_fake_same_settle_two
    ) outcome
    where outcome.result ->> 'contract_id' = (
      select contract_id::text
      from t_solo_fake_same_settle_contract
    )
  ),
  2::bigint,
  'both exact settlement callers recover the committed result'
);

select ok(
  (
    select contract_status = 'settled'
       and disposition = 'released'
       and event_count = 2
       and terminal_event_count = 1
       and terminal_kind = 'released'
       and settlement_request_count = 1
    from extensions.dblink(
      'solo_fake_setup',
      format(
        $query$
          select
            contract.status::text,
            contract.settlement_disposition::text,
            (
              select count(*)::bigint
              from app.solo_authorization_events event
              where event.contract_id = contract.id
            ),
            (
              select count(*)::bigint
              from app.solo_authorization_events event
              where event.contract_id = contract.id
                and event.sequence_number = 2
            ),
            (
              select event.event_kind::text
              from app.solo_authorization_events event
              where event.contract_id = contract.id
                and event.sequence_number = 2
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
        (select contract_id from t_solo_fake_same_settle_contract)
      )
    ) as state(
      contract_status text,
      disposition text,
      event_count bigint,
      terminal_event_count bigint,
      terminal_kind text,
      settlement_request_count bigint
    )
  ),
  'exact settlement retries append one release event and one ledger row'
);

-- ---------------------------------------------------------------------------
-- Distinct simultaneous settlement requests cannot double-resolve
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('solo_fake_gate', 'begin');
select locked_id
from extensions.dblink(
  'solo_fake_gate',
  $$ select id::text
     from public.profiles
     where id = 'd8444444-4444-4444-4444-444444444444'
     for update $$
) as result(locked_id text);

select extensions.dblink_exec(
  'solo_fake_one',
  $$ set application_name = 'gametime_solo_fake_settle_distinct_one' $$
);
select extensions.dblink_exec(
  'solo_fake_two',
  $$ set application_name = 'gametime_solo_fake_settle_distinct_two' $$
);

select ok(
  extensions.dblink_send_query(
    'solo_fake_one',
    format(
      'select pg_temp.solo_fake_test_settle_result(%L, %L, %L)',
      (select contract_id from t_solo_fake_distinct_settle_contract),
      'd8000000-0000-0000-0000-000000000044',
      '2099-02-03T00:02:00Z'
    )
  ) = 1,
  'the first distinct settlement request starts asynchronously'
);
select ok(
  extensions.dblink_send_query(
    'solo_fake_two',
    format(
      'select pg_temp.solo_fake_test_settle_result(%L, %L, %L)',
      (select contract_id from t_solo_fake_distinct_settle_contract),
      'd8000000-0000-0000-0000-000000000045',
      '2099-02-03T00:02:00Z'
    )
  ) = 1,
  'the second distinct settlement request starts asynchronously'
);

select ok(
  pg_temp.wait_for_solo_fake_blocked(
    array[
      'gametime_solo_fake_settle_distinct_one',
      'gametime_solo_fake_settle_distinct_two'
    ]
  ),
  'both distinct settlement requests wait on the owner finality lock'
);

select is(
  extensions.dblink_exec('solo_fake_gate', 'commit'),
  'COMMIT',
  'releasing the owner lets distinct settlement requests serialize'
);

create temporary table t_solo_fake_distinct_settle_one as
select result
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);

create temporary table t_solo_fake_distinct_settle_two as
select result
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select count(*)
from extensions.dblink_get_result(
  'solo_fake_one'
) as response(result jsonb);
select count(*)
from extensions.dblink_get_result(
  'solo_fake_two'
) as response(result jsonb);

select is(
  (
    select count(*)
    from (
      select result from t_solo_fake_distinct_settle_one
      union all
      select result from t_solo_fake_distinct_settle_two
    ) outcome
    where outcome.result ->> 'contract_id' = (
      select contract_id::text
      from t_solo_fake_distinct_settle_contract
    )
  ),
  1::bigint,
  'exactly one distinct settlement request wins finality'
);
select is(
  (
    select count(*)
    from (
      select result from t_solo_fake_distinct_settle_one
      union all
      select result from t_solo_fake_distinct_settle_two
    ) outcome
    where outcome.result ->> 'sqlstate' = '23001'
  ),
  1::bigint,
  'the losing distinct settlement request is rejected after serialization'
);

select ok(
  (
    select contract_status = 'settled'
       and disposition = 'released'
       and event_count = 2
       and terminal_event_count = 1
       and terminal_kind = 'released'
       and settlement_request_count = 1
    from extensions.dblink(
      'solo_fake_setup',
      format(
        $query$
          select
            contract.status::text,
            contract.settlement_disposition::text,
            (
              select count(*)::bigint
              from app.solo_authorization_events event
              where event.contract_id = contract.id
            ),
            (
              select count(*)::bigint
              from app.solo_authorization_events event
              where event.contract_id = contract.id
                and event.sequence_number = 2
            ),
            (
              select event.event_kind::text
              from app.solo_authorization_events event
              where event.contract_id = contract.id
                and event.sequence_number = 2
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
        (select contract_id from t_solo_fake_distinct_settle_contract)
      )
    ) as state(
      contract_status text,
      disposition text,
      event_count bigint,
      terminal_event_count bigint,
      terminal_kind text,
      settlement_request_count bigint
    )
  ),
  'the distinct settlement race appends one release event and one ledger row'
);

-- ---------------------------------------------------------------------------
-- Drain, disconnect, and remove every externally committed fixture
-- ---------------------------------------------------------------------------

select is(
  extensions.dblink_disconnect('solo_fake_one'),
  'OK',
  'the first fake-authorization worker disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_fake_two'),
  'OK',
  'the second fake-authorization worker disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('solo_fake_gate'),
  'OK',
  'the fake-authorization gate disconnects cleanly'
);

select extensions.dblink_exec(
  'solo_fake_setup',
  $cleanup$
    set session_replication_role = replica;

    delete from app.solo_authorization_events
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.solo_authorizations
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.solo_rpc_requests
    where request_id::text like 'd8000000-%';

    delete from public.solo_appeals
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from public.solo_evaluations
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from public.solo_contracts
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.solo_beta_eligibility
    where owner_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    update app.solo_contract_runtime
    set contract_creation_enabled = false,
        active_policy_version = 'solo-test-v1',
        updated_at = pg_catalog.clock_timestamp()
    where singleton;

    delete from app.account_capabilities
    where actor_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.workflow_scope_actors
    where actor_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.profile_handle_claims
    where actor_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from public.profiles
    where id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    delete from auth.users
    where id in (
      'd8111111-1111-1111-1111-111111111111',
      'd8222222-2222-2222-2222-222222222222',
      'd8333333-3333-3333-3333-333333333333',
      'd8444444-4444-4444-4444-444444444444'
    );

    set session_replication_role = origin;
  $cleanup$
);

select ok(
  (
    select contract_count = 0
       and authorization_count = 0
       and event_count = 0
       and user_count = 0
       and beta_count = 0
       and not creation_enabled
    from extensions.dblink(
      'solo_fake_setup',
      $query$
        select
          (
            select count(*)::bigint
            from public.solo_contracts
            where owner_id in (
              'd8111111-1111-1111-1111-111111111111',
              'd8222222-2222-2222-2222-222222222222',
              'd8333333-3333-3333-3333-333333333333',
              'd8444444-4444-4444-4444-444444444444'
            )
          ),
          (
            select count(*)::bigint
            from app.solo_authorizations
            where owner_id in (
              'd8111111-1111-1111-1111-111111111111',
              'd8222222-2222-2222-2222-222222222222',
              'd8333333-3333-3333-3333-333333333333',
              'd8444444-4444-4444-4444-444444444444'
            )
          ),
          (
            select count(*)::bigint
            from app.solo_authorization_events
            where owner_id in (
              'd8111111-1111-1111-1111-111111111111',
              'd8222222-2222-2222-2222-222222222222',
              'd8333333-3333-3333-3333-333333333333',
              'd8444444-4444-4444-4444-444444444444'
            )
          ),
          (
            select count(*)::bigint
            from auth.users
            where id in (
              'd8111111-1111-1111-1111-111111111111',
              'd8222222-2222-2222-2222-222222222222',
              'd8333333-3333-3333-3333-333333333333',
              'd8444444-4444-4444-4444-444444444444'
            )
          ),
          (
            select count(*)::bigint
            from app.solo_beta_eligibility
          ),
          (
            select contract_creation_enabled
            from app.solo_contract_runtime
            where singleton
          )
      $query$
    ) as state(
      contract_count bigint,
      authorization_count bigint,
      event_count bigint,
      user_count bigint,
      beta_count bigint,
      creation_enabled boolean
    )
  ),
  'external fake-authorization fixtures are removed, the allowlist is empty, and creation is disabled'
);

select is(
  extensions.dblink_disconnect('solo_fake_setup'),
  'OK',
  'the fake-authorization setup session disconnects cleanly'
);

select * from finish();
rollback;
