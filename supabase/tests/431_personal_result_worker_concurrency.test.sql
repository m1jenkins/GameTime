-- Beta workstream 4: a real second database session proves that the automatic
-- result path serializes with the final Personal metric-sync boundary.
--
-- The worker wins this ordering. The late sync must wait on the owner's profile
-- lock, then fail closed after the immutable result commits.

begin;
select plan(11);

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_beta4_block(
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
  'beta4_setup',
  pg_catalog.format(
    'host=supabase_db_gametime port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);
select extensions.dblink_connect(
  'beta4_worker',
  pg_catalog.format(
    'host=supabase_db_gametime port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);
select extensions.dblink_connect(
  'beta4_sync',
  pg_catalog.format(
    'host=supabase_db_gametime port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);

select extensions.dblink_exec(
  'beta4_worker',
  $$ set application_name = 'gametime_beta4_worker' $$
);
select extensions.dblink_exec(
  'beta4_sync',
  $$ set application_name = 'gametime_beta4_late_sync' $$
);

-- These committed fixtures are visible to both external sessions. The helper
-- returns SQLSTATE only so the expected rejection never emits evidence,
-- credentials, or exception text into test output.
select extensions.dblink_exec(
  'beta4_setup',
  $setup$
    insert into auth.users (id)
    values ('fc111111-1111-1111-1111-111111111111');

    insert into public.profiles (id, handle, display_name, timezone)
    values (
      'fc111111-1111-1111-1111-111111111111',
      'beta4concurrency',
      'Beta 4 Concurrency',
      'UTC'
    );

    insert into public.device_attestations (
      key_id,
      user_id,
      public_key,
      environment
    )
    values (
      extensions.digest(
        ('\x04' || repeat('c1', 64))::bytea,
        'sha256'
      ),
      'fc111111-1111-1111-1111-111111111111',
      ('\x04' || repeat('c1', 64))::bytea,
      'production'
    );

    alter table public.contests
      disable trigger contests_assert_future_window;

    insert into public.contests (
      id,
      title,
      created_by,
      challenge_model,
      metric,
      cadence,
      target_value,
      stake_amount_cents,
      tie_break,
      starts_at,
      ends_at,
      max_participants,
      status
    )
    values (
      'fc000000-0000-0000-0000-000000000001',
      'Beta 4 final-sync serialization',
      'fc111111-1111-1111-1111-111111111111',
      'personal_accountability',
      'steps',
      'cumulative',
      100,
      1000,
      'void',
      '2026-07-01T00:00:00Z',
      '2026-07-08T00:00:00Z',
      1,
      'active'
    );

    alter table public.contests
      enable trigger contests_assert_future_window;

    alter table public.contest_participants
      disable trigger contest_participants_apply_transition;

    insert into public.contest_participants (
      contest_id,
      user_id,
      status,
      timezone,
      charity_id,
      accepted_at
    )
    values (
      'fc000000-0000-0000-0000-000000000001',
      'fc111111-1111-1111-1111-111111111111',
      'accepted',
      'UTC',
      null,
      '2026-06-30T00:00:00Z'
    );

    alter table public.contest_participants
      enable trigger contest_participants_apply_transition;

    insert into public.personal_challenge_terms (
      challenge_id,
      user_id,
      cadence,
      target_steps,
      commitment_amount_minor,
      timezone,
      agreed_at,
      evidence_cutoff
    )
    values (
      'fc000000-0000-0000-0000-000000000001',
      'fc111111-1111-1111-1111-111111111111',
      'cumulative',
      100,
      1000,
      'UTC',
      '2026-06-30T00:00:00Z',
      '2026-07-09T00:00:00Z'
    );

    create function public.beta4_test_late_metric_v1()
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      perform public.record_metric_batch(
        'fc111111-1111-1111-1111-111111111111',
        'fc000000-0000-0000-0000-000000000001',
        'fc100000-0000-0000-0000-000000000001',
        extensions.digest('beta4 late metric', 'sha256'),
        '2026-07-08T00:00:00Z',
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'metric', 'steps',
            'bucket_start', '2026-07-01T00:00:00Z',
            'value', 100,
            'provenance', 'device',
            'sample_count', 1,
            'source_bundle_id', 'com.apple.health',
            'device_model', 'iPhone'
          )
        ),
        extensions.digest(
          ('\x04' || repeat('c1', 64))::bytea,
          'sha256'
        ),
        1
      );
      return 'unexpected_success';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    revoke all on function public.beta4_test_late_metric_v1()
      from public, anon, authenticated;
    grant execute on function public.beta4_test_late_metric_v1()
      to service_role;
  $setup$
);

select extensions.dblink_exec('beta4_worker', 'begin');

create temporary table t_beta4_worker_result as
select remote.result_id
from extensions.dblink(
  'beta4_worker',
  $$ select app.publish_due_personal_result_v1(
       'fc000000-0000-0000-0000-000000000001',
       clock_timestamp()
     ) $$
) as remote(result_id uuid);

select ok(
  (select result_id is not null from t_beta4_worker_result),
  'the worker creates one result while retaining its serialization locks'
);

select is(
  extensions.dblink_send_query(
    'beta4_sync',
    $$ set role service_role;
       select public.beta4_test_late_metric_v1() $$
  ),
  1,
  'the final metric sync starts while the result remains uncommitted'
);

select ok(
  pg_temp.wait_for_beta4_block('gametime_beta4_late_sync'),
  'the final metric sync waits on the worker profile lock'
);

select is(
  extensions.dblink_exec('beta4_worker', 'commit'),
  'COMMIT',
  'committing the result releases the final-sync serialization point'
);

-- dblink_get_result first returns the SET status, then the helper row.
select *
from extensions.dblink_get_result('beta4_sync') as status(result text);

create temporary table t_beta4_late_sync as
select result
from extensions.dblink_get_result('beta4_sync') as remote(result text);

select is(
  (select result from t_beta4_late_sync),
  '23001',
  'the waiting metric sync fails closed after immutable publication wins'
);

select count(*)
from extensions.dblink_get_result('beta4_sync') as remote(result text);

select ok(
  (
    select
      contest.status = 'finalized'
      and result.outcome = 'inconclusive'
      and result.reason = 'missing_coverage'
      and result.commitment_waived
    from public.contests contest
    join public.personal_challenge_results result
      on result.challenge_id = contest.id
    where contest.id = 'fc000000-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from public.ingest_batches batch
    where batch.contest_id =
      'fc000000-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from public.metric_snapshots snapshot
    where snapshot.contest_id =
      'fc000000-0000-0000-0000-000000000001'
  ),
  'one terminal result persists and the rejected metric sync persists nothing'
);

select is(
  (
    select result_id
    from extensions.dblink(
      'beta4_setup',
      $$ select app.publish_due_personal_result_v1(
           'fc000000-0000-0000-0000-000000000001',
           clock_timestamp()
         ) $$
    ) as remote(result_id uuid)
  ),
  (select result_id from t_beta4_worker_result),
  'the committed concurrent result remains an exact immutable retry'
);

select extensions.dblink_exec(
  'beta4_setup',
  $cleanup$
    set session_replication_role = replica;

    drop function public.beta4_test_late_metric_v1();

    delete from app.personal_stripe_sandbox_charge_commands
    where challenge_id = 'fc000000-0000-0000-0000-000000000001';

    delete from app.personal_stripe_sandbox_payment_reviews
    where challenge_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.personal_challenge_results
    where challenge_id = 'fc000000-0000-0000-0000-000000000001';

    delete from app.personal_evidence_assessments
    where challenge_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.metric_snapshots
    where contest_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.ingest_batches
    where contest_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.personal_challenge_terms
    where challenge_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.contest_participants
    where contest_id = 'fc000000-0000-0000-0000-000000000001';

    delete from app.workflow_scope_actors
    where scope_kind = 'contest_lineage'
      and scope_id = 'fc000000-0000-0000-0000-000000000001';

    delete from app.workflow_scopes
    where scope_kind = 'contest_lineage'
      and scope_id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.contests
    where id = 'fc000000-0000-0000-0000-000000000001';

    delete from public.device_attestations
    where user_id = 'fc111111-1111-1111-1111-111111111111';

    delete from app.profile_handle_claims
    where actor_id = 'fc111111-1111-1111-1111-111111111111';

    delete from app.active_profile_auth_bindings
    where actor_id = 'fc111111-1111-1111-1111-111111111111';

    delete from public.profiles
    where id = 'fc111111-1111-1111-1111-111111111111';

    delete from auth.users
    where id = 'fc111111-1111-1111-1111-111111111111';

    set session_replication_role = origin;
  $cleanup$
);

select is(
  (
    select remaining
    from extensions.dblink(
      'beta4_setup',
      $$ select count(*)::bigint
         from public.contests
         where id = 'fc000000-0000-0000-0000-000000000001' $$
    ) as remote(remaining bigint)
  ),
  0::bigint,
  'the committed concurrency fixture is removed after verification'
);

select is(
  extensions.dblink_disconnect('beta4_worker'),
  'OK',
  'the worker session disconnects cleanly'
);

select is(
  extensions.dblink_disconnect('beta4_sync'),
  'OK',
  'the final-sync session disconnects cleanly'
);

select extensions.dblink_disconnect('beta4_setup');

select * from finish();
rollback;
