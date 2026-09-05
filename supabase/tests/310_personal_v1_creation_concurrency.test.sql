-- Two real database sessions prove distinct simultaneous personal-create
-- requests serialize on the active owner and cannot consume two open slots.

begin;
select plan(17);

select has_extension(
  'extensions', 'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_personal_create_block(
  p_timeout_seconds double precision default 5
)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deadline timestamptz := clock_timestamp()
    + make_interval(secs => p_timeout_seconds);
begin
  loop
    if (
      select count(*) = 2
      from pg_catalog.pg_stat_activity activity
      where activity.application_name in (
        'gametime_personal_create_one',
        'gametime_personal_create_two'
      )
        and cardinality(pg_catalog.pg_blocking_pids(activity.pid)) > 0
    ) then
      return true;
    end if;

    exit when clock_timestamp() >= v_deadline;
    perform pg_sleep(0.01);
  end loop;
  return false;
end;
$$;

select extensions.dblink_connect(
  'personal_setup',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'personal_gate',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'personal_one',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'personal_two',
  'host=' || host(inet_server_addr()) || ' port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'personal_setup',
  $setup$
    insert into auth.users (id) values (
      'fa111111-1111-1111-1111-111111111111'
    );
    insert into public.profiles (id, handle, display_name, timezone) values (
      'fa111111-1111-1111-1111-111111111111',
      'personalrace', 'Personal Race', 'UTC'
    );

    create function public.personal_test_create_result(p_request_id uuid)
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      return public.create_personal_challenge_v1(
        p_request_id, 'daily', 10000, 1000, 'UTC'
      )::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    grant execute on function public.personal_test_create_result(uuid)
      to authenticated;
  $setup$
);

select extensions.dblink_exec('personal_gate', 'begin');
select extensions.dblink_exec(
  'personal_gate',
  $$ update public.profiles set display_name = display_name
     where id = 'fa111111-1111-1111-1111-111111111111' $$
);

select extensions.dblink_exec(
  'personal_one',
  $$ set application_name = 'gametime_personal_create_one' $$
);
select extensions.dblink_exec('personal_one', 'set role authenticated');
select extensions.dblink_exec(
  'personal_one',
  $claim$set "request.jwt.claims" =
    '{"sub":"fa111111-1111-1111-1111-111111111111"}'$claim$
);

select extensions.dblink_exec(
  'personal_two',
  $$ set application_name = 'gametime_personal_create_two' $$
);
select extensions.dblink_exec('personal_two', 'set role authenticated');
select extensions.dblink_exec(
  'personal_two',
  $claim$set "request.jwt.claims" =
    '{"sub":"fa111111-1111-1111-1111-111111111111"}'$claim$
);

select ok(
  extensions.dblink_send_query(
    'personal_one',
    $$ select public.personal_test_create_result(
         'fa000000-0000-0000-0000-000000000001'
       ) $$
  ) = 1,
  'the first distinct create request starts asynchronously'
);

select ok(
  extensions.dblink_send_query(
    'personal_two',
    $$ select public.personal_test_create_result(
         'fa000000-0000-0000-0000-000000000002'
       ) $$
  ) = 1,
  'the second distinct create request starts asynchronously'
);

select ok(
  pg_temp.wait_for_personal_create_block(),
  'both callers wait on the same owner serialization lock'
);

select is(
  extensions.dblink_exec('personal_gate', 'commit'),
  'COMMIT',
  'releasing the gate lets the two create transactions race'
);

create temporary table t_create_one as
select result
from extensions.dblink_get_result('personal_one') as response(result text);

create temporary table t_create_two as
select result
from extensions.dblink_get_result('personal_two') as response(result text);

-- dblink's async API requires one final empty drain before the same named
-- connection can accept another command.
select count(*)
from extensions.dblink_get_result('personal_one') as response(result text);
select count(*)
from extensions.dblink_get_result('personal_two') as response(result text);

select is(
  (
    select count(*)
    from (
      select result from t_create_one
      union all
      select result from t_create_two
    ) outcomes
    where result ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ),
  1::bigint,
  'exactly one simultaneous distinct request creates a challenge'
);

select is(
  (
    select count(*)
    from (
      select result from t_create_one
      union all
      select result from t_create_two
    ) outcomes
    where result = '23505'
  ),
  1::bigint,
  'the competing distinct request gets the one-open unique conflict'
);

select is(
  (
    select contest_count
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint from public.contests
         where created_by = 'fa111111-1111-1111-1111-111111111111'
           and challenge_model = 'personal_accountability'
           and status in ('pending', 'active') $$
    ) as result(contest_count bigint)
  ),
  1::bigint,
  'the race commits one open personal challenge'
);

select is(
  (
    select participant_count
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint
         from public.contest_participants participant
         join public.contests contest on contest.id = participant.contest_id
         where contest.created_by = 'fa111111-1111-1111-1111-111111111111'
           and contest.challenge_model = 'personal_accountability' $$
    ) as result(participant_count bigint)
  ),
  1::bigint,
  'the winning transaction commits exactly one owner participant'
);

select is(
  (
    select terms_count
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint
         from public.personal_challenge_terms
         where user_id = 'fa111111-1111-1111-1111-111111111111' $$
    ) as result(terms_count bigint)
  ),
  1::bigint,
  'the winning transaction commits exactly one frozen terms row'
);

select is(
  (
    select request_count
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint
         from app.personal_challenge_creation_requests
         where actor_id = 'fa111111-1111-1111-1111-111111111111' $$
    ) as result(request_count bigint)
  ),
  1::bigint,
  'only the winning request reaches the idempotency ledger'
);

create temporary table t_retry_one as
select result
from extensions.dblink(
  'personal_one',
  $$ select public.personal_test_create_result(
       'fa000000-0000-0000-0000-000000000001'
     ) $$
) as response(result text);

create temporary table t_retry_two as
select result
from extensions.dblink(
  'personal_two',
  $$ select public.personal_test_create_result(
       'fa000000-0000-0000-0000-000000000002'
     ) $$
) as response(result text);

select ok(
  (select result from t_retry_one) = (select result from t_create_one)
  and (select result from t_retry_two) = (select result from t_create_two),
  'the winner retries to its UUID while the loser remains a slot conflict'
);

select is(
  (
    select contest_count
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint from public.contests
         where created_by = 'fa111111-1111-1111-1111-111111111111'
           and challenge_model = 'personal_accountability' $$
    ) as result(contest_count bigint)
  ),
  1::bigint,
  'retries still cannot create a second personal challenge'
);

select is(extensions.dblink_disconnect('personal_one'), 'OK',
  'the first caller disconnects cleanly');
select is(extensions.dblink_disconnect('personal_two'), 'OK',
  'the second caller disconnects cleanly');
select extensions.dblink_disconnect('personal_gate');

select extensions.dblink_exec(
  'personal_setup',
  $cleanup$
    set session_replication_role = replica;

    drop function public.personal_test_create_result(uuid);

    delete from app.personal_challenge_creation_requests
    where actor_id = 'fa111111-1111-1111-1111-111111111111';

    delete from public.personal_challenge_terms
    where user_id = 'fa111111-1111-1111-1111-111111111111';

    delete from public.contest_participants
    where user_id = 'fa111111-1111-1111-1111-111111111111';

    delete from public.notification_intents
    where recipient_user_id = 'fa111111-1111-1111-1111-111111111111';

    delete from app.account_capabilities
    where actor_id = 'fa111111-1111-1111-1111-111111111111';

    delete from app.workflow_scope_actors
    where actor_id = 'fa111111-1111-1111-1111-111111111111';

    delete from app.workflow_scopes
    where contest_id in (
      select id from public.contests
      where created_by = 'fa111111-1111-1111-1111-111111111111'
    );

    delete from public.contests
    where created_by = 'fa111111-1111-1111-1111-111111111111';

    delete from app.profile_handle_claims
    where actor_id = 'fa111111-1111-1111-1111-111111111111';

    delete from app.active_profile_auth_bindings
    where actor_id = 'fa111111-1111-1111-1111-111111111111';

    delete from public.profiles
    where id = 'fa111111-1111-1111-1111-111111111111';

    delete from auth.users
    where id = 'fa111111-1111-1111-1111-111111111111';

    set session_replication_role = origin;
  $cleanup$
);

select is(
  (
    select remaining
    from extensions.dblink(
      'personal_setup',
      $$ select count(*)::bigint from public.contests
         where created_by = 'fa111111-1111-1111-1111-111111111111' $$
    ) as result(remaining bigint)
  ),
  0::bigint,
  'the committed external concurrency fixture is removed'
);

select is(extensions.dblink_disconnect('personal_setup'), 'OK',
  'the setup session disconnects cleanly');

select * from finish();
rollback;
