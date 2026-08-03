-- M7 / D81 P0: real multi-session account-deletion races.
--
-- A pgTAP file normally runs in one transaction, which cannot prove lock
-- ordering. These cases use test-only dblink sessions and leave the first
-- operation uncommitted while the competing operation starts. The blocked
-- backend is observed through pg_blocking_pids() before the first transaction
-- commits. Both serial orders are exercised for:
--
--   * D82 scheduled activation,
--   * authenticated invitation acceptance, and
--   * service-only attested metric ingest.
--
-- Every fixture UUID is private to this file. dblink commits outside the
-- pgTAP transaction, so the final section removes those committed fixtures.

begin;
select plan(57);

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the test-only multi-session driver'
);

create function pg_temp.wait_for_blocked_backend(
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
  'p0_setup',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'p0_first',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);
select extensions.dblink_connect(
  'p0_second',
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
);

select extensions.dblink_exec(
  'p0_first',
  $$ set application_name = 'gametime_p0_first' $$
);
select extensions.dblink_exec(
  'p0_second',
  $$ set application_name = 'gametime_p0_second' $$
);

-- The second session uses this invoker-rights wrapper for expected failures.
-- PL/pgSQL's exception block is a subtransaction, so a returned SQLSTATE also
-- proves that every write attempted by the losing statement was rolled back.
select extensions.dblink_exec(
  'p0_second',
  $capture_function$
    create function pg_temp.capture_statement(p_statement text)
    returns jsonb
    language plpgsql
    volatile
    set search_path = ''
    as $capture$
    begin
      execute p_statement;
      return pg_catalog.jsonb_build_object(
        'ok', true,
        'sqlstate', null,
        'message', null
      );
    exception
      when others then
        return pg_catalog.jsonb_build_object(
          'ok', false,
          'sqlstate', sqlstate,
          'message', sqlerrm
        );
    end;
    $capture$
  $capture_function$
);
select extensions.dblink_exec(
  'p0_second',
  $grant_capture$
    grant execute on function pg_temp.capture_statement(text)
      to authenticated, service_role
  $grant_capture$
);

-- ---------------------------------------------------------------------------
-- Committed fixtures visible to every dblink session
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'p0_setup',
  $setup$
    insert into auth.users (id) values
      ('e0000000-0000-0000-0000-000000000001'),
      ('e1000000-0000-0000-0000-000000000001'),
      ('e1000000-0000-0000-0000-000000000002'),
      ('e2000000-0000-0000-0000-000000000001'),
      ('e2000000-0000-0000-0000-000000000002'),
      ('e3000000-0000-0000-0000-000000000001'),
      ('e3000000-0000-0000-0000-000000000002');

    insert into public.profiles (id, handle, display_name) values
      (
        'e0000000-0000-0000-0000-000000000001',
        'p0survivor',
        'P0 Surviving Creator'
      ),
      (
        'e1000000-0000-0000-0000-000000000001',
        'p0activatefirst',
        'P0 Activation First'
      ),
      (
        'e1000000-0000-0000-0000-000000000002',
        'p0activatedelete',
        'P0 Activation Delete First'
      ),
      (
        'e2000000-0000-0000-0000-000000000001',
        'p0acceptfirst',
        'P0 Acceptance First'
      ),
      (
        'e2000000-0000-0000-0000-000000000002',
        'p0acceptdelete',
        'P0 Acceptance Delete First'
      ),
      (
        'e3000000-0000-0000-0000-000000000001',
        'p0ingestfirst',
        'P0 Ingest First'
      ),
      (
        'e3000000-0000-0000-0000-000000000002',
        'p0ingestdelete',
        'P0 Ingest Delete First'
      );

    insert into public.charities (id, name, ein, slug) values (
      'ec000000-0000-0000-0000-000000000001',
      'P0 Concurrency Fund',
      '98-7654321',
      'p0-concurrency-fund'
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
      starts_at,
      ends_at,
      max_participants
    ) values
      (
        'f1000000-0000-0000-0000-000000000001',
        'P0 activation wins',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        '2000-01-01T00:00:00Z',
        '2000-01-03T00:00:00Z',
        2
      ),
      (
        'f1000000-0000-0000-0000-000000000002',
        'P0 deletion wins activation',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        '2000-02-01T00:00:00Z',
        '2000-02-03T00:00:00Z',
        2
      ),
      (
        'f2000000-0000-0000-0000-000000000001',
        'P0 acceptance wins',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        '2099-01-01T00:00:00Z',
        '2099-01-03T00:00:00Z',
        2
      ),
      (
        'f2000000-0000-0000-0000-000000000002',
        'P0 deletion wins acceptance',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        '2099-02-01T00:00:00Z',
        '2099-02-03T00:00:00Z',
        2
      ),
      (
        'f3000000-0000-0000-0000-000000000001',
        'P0 ingest wins',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        pg_catalog.date_trunc('hour', pg_catalog.clock_timestamp())
          - interval '4 hours',
        pg_catalog.date_trunc('hour', pg_catalog.clock_timestamp())
          + interval '4 hours',
        2
      ),
      (
        'f3000000-0000-0000-0000-000000000002',
        'P0 deletion wins ingest',
        'e0000000-0000-0000-0000-000000000001',
        'steps',
        'cumulative',
        10000,
        100,
        pg_catalog.date_trunc('hour', pg_catalog.clock_timestamp())
          - interval '4 hours',
        pg_catalog.date_trunc('hour', pg_catalog.clock_timestamp())
          + interval '4 hours',
        2
      );

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
      'e0000000-0000-0000-0000-000000000001',
      'accepted',
      'UTC',
      'ec000000-0000-0000-0000-000000000001'
    from public.contests contest
    where contest.id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    )
    order by contest.id;

    insert into public.contest_participants (
      contest_id,
      user_id,
      status,
      invited_by
    ) values
      (
        'f1000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      ),
      (
        'f1000000-0000-0000-0000-000000000002',
        'e1000000-0000-0000-0000-000000000002',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      ),
      (
        'f2000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000001',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      ),
      (
        'f2000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000002',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      ),
      (
        'f3000000-0000-0000-0000-000000000001',
        'e3000000-0000-0000-0000-000000000001',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      ),
      (
        'f3000000-0000-0000-0000-000000000002',
        'e3000000-0000-0000-0000-000000000002',
        'invited',
        'e0000000-0000-0000-0000-000000000001'
      );

    update public.contest_participants participant
    set status = 'accepted',
        timezone = 'UTC',
        charity_id = 'ec000000-0000-0000-0000-000000000001'
    where (participant.contest_id, participant.user_id) in (
      (
        'f1000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001'
      ),
      (
        'f1000000-0000-0000-0000-000000000002',
        'e1000000-0000-0000-0000-000000000002'
      ),
      (
        'f3000000-0000-0000-0000-000000000001',
        'e3000000-0000-0000-0000-000000000001'
      ),
      (
        'f3000000-0000-0000-0000-000000000002',
        'e3000000-0000-0000-0000-000000000002'
      )
    );

    update public.contests contest
    set status = 'active',
        activated_at = pg_catalog.clock_timestamp()
    where contest.id in (
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    );

    with key_rows(user_id, public_key) as (
      values
        (
          'e3000000-0000-0000-0000-000000000001'::uuid,
          pg_catalog.decode(
            '04' || pg_catalog.repeat('31', 64),
            'hex'
          )
        ),
        (
          'e3000000-0000-0000-0000-000000000002'::uuid,
          pg_catalog.decode(
            '04' || pg_catalog.repeat('32', 64),
            'hex'
          )
        )
    )
    insert into public.device_attestations (
      key_id,
      user_id,
      public_key,
      environment
    )
    select
      extensions.digest(key_rows.public_key, 'sha256'),
      key_rows.user_id,
      key_rows.public_key,
      'development'
    from key_rows;
  $setup$
);

-- ===========================================================================
-- Race 1: scheduled activation and deletion
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Activation commits first. Deletion must preserve the active agreement.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role service_role');

create temporary table t_activation_first_worker as
select remote.contest_id, remote.outcome
from extensions.dblink(
  'p0_first',
  $activate$
    select activation.contest_id, activation.outcome::text
    from app.activate_due_contests('2000-01-01T00:01:00Z') activation
    where activation.contest_id =
      'f1000000-0000-0000-0000-000000000001'
  $activate$
) as remote(contest_id uuid, outcome text);

select is(
  (select outcome from t_activation_first_worker),
  'active',
  'the scheduled worker makes the due two-person challenge active'
);

select extensions.dblink_exec('p0_second', 'set role service_role');
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $delete$
      select public.delete_account(
        'e1000000-0000-0000-0000-000000000001'
      )
    $delete$
  ) = 1,
  'account deletion starts while activation is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'activation holds the workflow row until its transition and outbox commit'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_activation_first_delete as
select remote.result
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select *
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select extensions.dblink_exec('p0_second', 'reset role');

select ok(
  (
    select
      contest.status = 'active'
      and contest.activated_at = '2000-01-01T00:01:00Z'
      and contest.cancellation_reason is null
      and contest.cancelled_at is null
    from public.contests contest
    where contest.id = 'f1000000-0000-0000-0000-000000000001'
  ),
  'the committed activation cannot be rewritten as cancellation by deletion'
);
select is(
  (
    select participant.status
    from public.contest_participants participant
    where participant.contest_id =
          'f1000000-0000-0000-0000-000000000001'
      and participant.user_id =
          'e1000000-0000-0000-0000-000000000001'
  ),
  'accepted'::public.contest_participant_status,
  'the deleted actor stays on the frozen active roster'
);
select ok(
  (
    select
      profile.deleted_at is not null
      and profile.display_name = 'Deleted member'
      and profile.handle::text ~ '^deleted-[0-9a-f]{20}$'
    from public.profiles profile
    where profile.id = 'e1000000-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = 'e1000000-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from app.active_profile_auth_bindings binding
    where binding.actor_id =
      'e1000000-0000-0000-0000-000000000001'
  ),
  'activation-first deletion removes authentication but keeps the durable actor'
);
select ok(
  (
    select
      pg_catalog.jsonb_array_length(
        deletion.result -> 'capabilities'
      ) = 1
      and deletion.result -> 'capabilities' -> 0 ->> 'kind' =
          'contest_lineage'
      and (
        deletion.result -> 'capabilities' -> 0 ->> 'scopeId'
      )::uuid = 'f1000000-0000-0000-0000-000000000001'
    from t_activation_first_delete deletion
  ),
  'deletion returns one continuation capability for the activated lineage'
);
select ok(
  (
    select capability.secret_hash =
      extensions.digest(
        pg_catalog.convert_to(
          deletion.result -> 'capabilities' -> 0 ->> 'secret',
          'UTF8'
        ),
        'sha256'
      )
    from app.account_capabilities capability
    cross join t_activation_first_delete deletion
    where capability.actor_id =
          'e1000000-0000-0000-0000-000000000001'
      and capability.scope_kind = 'contest_lineage'
      and capability.scope_id =
          'f1000000-0000-0000-0000-000000000001'
  ),
  'only the hash of the activation-first continuation secret is retained'
);
select set_eq(
  $$ select intent.recipient_user_id
     from public.notification_intents intent
     where intent.event_type = 'contest_activated'
       and intent.entity_id =
         'f1000000-0000-0000-0000-000000000001'::uuid $$,
  array[
    'e0000000-0000-0000-0000-000000000001'::uuid,
    'e1000000-0000-0000-0000-000000000001'::uuid
  ],
  'activation and both durable recipient intents commit together'
);
select is_empty(
  $$ select 1
     from app.account_deletion_participant_events event
     where event.actor_id =
       'e1000000-0000-0000-0000-000000000001'::uuid $$,
  'deletion does not manufacture a departure from an active roster'
);

-- ---------------------------------------------------------------------------
-- Deletion commits first. Activation must use the adjusted durable roster.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role service_role');

create temporary table t_activation_delete_first as
select remote.result
from extensions.dblink(
  'p0_first',
  $delete$
    select public.delete_account(
      'e1000000-0000-0000-0000-000000000002'
    )
  $delete$
) as remote(result jsonb);

select ok(
  (
    select pg_catalog.jsonb_array_length(
      deletion.result -> 'capabilities'
    ) = 0
    from t_activation_delete_first deletion
  ),
  'pending deletion issues no active-lineage continuation capability'
);

select extensions.dblink_exec('p0_second', 'set role service_role');
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $activate$
      select activation.contest_id, activation.outcome::text
      from app.activate_due_contests('2000-02-01T00:01:00Z') activation
      where activation.contest_id =
        'f1000000-0000-0000-0000-000000000002'
    $activate$
  ) = 1,
  'the scheduled worker starts while deletion is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'deletion holds the same workflow row before changing participation'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_activation_delete_second as
select remote.contest_id, remote.outcome
from extensions.dblink_get_result('p0_second')
  as remote(contest_id uuid, outcome text);
select *
from extensions.dblink_get_result('p0_second')
  as remote(contest_id uuid, outcome text);
select extensions.dblink_exec('p0_second', 'reset role');

select is(
  (select outcome from t_activation_delete_second),
  'cancelled',
  'the worker deterministically cancels the one-person post-deletion roster'
);
select ok(
  (
    select
      contest.status = 'cancelled'
      and contest.cancellation_reason = 'insufficient_participants'
      and contest.cancelled_at = '2000-02-01T00:01:00Z'
      and contest.activated_at is null
    from public.contests contest
    where contest.id = 'f1000000-0000-0000-0000-000000000002'
  ),
  'deletion-first activation leaves one complete cancellation outcome'
);
select is(
  (
    select participant.status
    from public.contest_participants participant
    where participant.contest_id =
          'f1000000-0000-0000-0000-000000000002'
      and participant.user_id =
          'e1000000-0000-0000-0000-000000000002'
  ),
  'withdrawn'::public.contest_participant_status,
  'deletion records the prior acceptance as withdrawal before activation'
);
select ok(
  (
    select
      pg_catalog.count(*) = 1
      and pg_catalog.bool_and(event.from_status = 'accepted')
      and pg_catalog.bool_and(event.to_status = 'withdrawn')
    from app.account_deletion_participant_events event
    where event.actor_id =
      'e1000000-0000-0000-0000-000000000002'
  ),
  'the deletion-first race retains one immutable accepted-to-withdrawn event'
);
select set_eq(
  $$ select intent.recipient_user_id
     from public.notification_intents intent
     where intent.event_type = 'contest_cancelled'
       and intent.entity_id =
         'f1000000-0000-0000-0000-000000000002'::uuid $$,
  array['e0000000-0000-0000-0000-000000000001'::uuid],
  'only the surviving accepted creator receives the cancellation intent'
);
select is_empty(
  $$ select 1
     from public.notification_intents intent
     where intent.event_type = 'contest_activated'
       and intent.entity_id =
         'f1000000-0000-0000-0000-000000000002'::uuid $$,
  'no activation intent survives the deletion-first cancellation'
);

-- ===========================================================================
-- Race 2: invitation acceptance and deletion
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Acceptance commits first. Deletion observes and records that agreement.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role authenticated');
select extensions.dblink_exec(
  'p0_first',
  $claims$
    set local "request.jwt.claims" =
      '{"sub":"e2000000-0000-0000-0000-000000000001"}'
  $claims$
);
select is(
  extensions.dblink_exec(
    'p0_first',
    $accept$
      update public.contest_participants
      set status = 'accepted',
          timezone = 'UTC',
          charity_id = 'ec000000-0000-0000-0000-000000000001'
      where contest_id = 'f2000000-0000-0000-0000-000000000001'
        and user_id = 'e2000000-0000-0000-0000-000000000001'
    $accept$
  ),
  'UPDATE 1',
  'the active authenticated invitee accepts before deletion commits'
);

select extensions.dblink_exec('p0_second', 'set role service_role');
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $delete$
      select public.delete_account(
        'e2000000-0000-0000-0000-000000000001'
      )
    $delete$
  ) = 1,
  'deletion starts while invitation acceptance is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'accepted participation holds the actor and pending workflow locks'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_acceptance_first_delete as
select remote.result
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select *
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select extensions.dblink_exec('p0_second', 'reset role');

select is(
  (
    select participant.status
    from public.contest_participants participant
    where participant.contest_id =
          'f2000000-0000-0000-0000-000000000001'
      and participant.user_id =
          'e2000000-0000-0000-0000-000000000001'
  ),
  'withdrawn'::public.contest_participant_status,
  'deletion serially converts the committed pending acceptance to withdrawal'
);
select ok(
  (
    select
      participant.accepted_at is null
      and participant.timezone = 'UTC'
      and participant.charity_id =
          'ec000000-0000-0000-0000-000000000001'
    from public.contest_participants participant
    where participant.contest_id =
          'f2000000-0000-0000-0000-000000000001'
      and participant.user_id =
          'e2000000-0000-0000-0000-000000000001'
  ),
  'the durable withdrawn row retains terms but no longer claims active acceptance'
);
select ok(
  (
    select
      pg_catalog.count(*) = 1
      and pg_catalog.bool_and(event.from_status = 'accepted')
      and pg_catalog.bool_and(event.to_status = 'withdrawn')
    from app.account_deletion_participant_events event
    where event.actor_id =
      'e2000000-0000-0000-0000-000000000001'
  ),
  'the immutable departure event proves acceptance committed before deletion'
);
select ok(
  (
    select contest.status = 'pending'
    from public.contests contest
    where contest.id = 'f2000000-0000-0000-0000-000000000001'
  )
  and (
    select pg_catalog.jsonb_array_length(
      deletion.result -> 'capabilities'
    ) = 0
    from t_acceptance_first_delete deletion
  ),
  'the other creator pending contest stays pending and issues no capability'
);
select ok(
  not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = 'e2000000-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.profiles profile
    where profile.id = 'e2000000-0000-0000-0000-000000000001'
      and profile.deleted_at is not null
  ),
  'acceptance-first deletion still removes authentication atomically'
);
select is(
  (
    select pg_catalog.count(*)
    from public.notification_intents intent
    join app.account_deletion_participant_events event
      on event.id = intent.entity_id
    where event.actor_id =
          'e2000000-0000-0000-0000-000000000001'
      and intent.event_type = 'contest_participation_changed'
      and intent.recipient_user_id =
          'e0000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the acceptance-first departure and creator intent commit together'
);

-- ---------------------------------------------------------------------------
-- Deletion commits first. The stale acceptance must fail and roll back.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role service_role');

create temporary table t_acceptance_delete_first as
select remote.result
from extensions.dblink(
  'p0_first',
  $delete$
    select public.delete_account(
      'e2000000-0000-0000-0000-000000000002'
    )
  $delete$
) as remote(result jsonb);

select extensions.dblink_exec('p0_second', 'set role authenticated');
select extensions.dblink_exec(
  'p0_second',
  $claims$
    set "request.jwt.claims" =
      '{"sub":"e2000000-0000-0000-0000-000000000002"}'
  $claims$
);
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $accept$
      select pg_temp.capture_statement(
        $statement$
          update public.contest_participants
          set status = 'accepted',
              timezone = 'UTC',
              charity_id = 'ec000000-0000-0000-0000-000000000001'
          where contest_id = 'f2000000-0000-0000-0000-000000000002'
            and user_id = 'e2000000-0000-0000-0000-000000000002'
        $statement$
      )
    $accept$
  ) = 1,
  'the stale acceptance starts while deletion is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'the stale JWT waits at the actor-deletion serialization lock'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_acceptance_delete_second as
select remote.result
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select *
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select extensions.dblink_exec('p0_second', 'reset role');
select extensions.dblink_exec('p0_second', 'reset "request.jwt.claims"');

select is(
  (
    select (attempt.result ->> 'ok')::boolean
    from t_acceptance_delete_second attempt
  ),
  false,
  'the post-deletion stale acceptance is rejected'
);
select is(
  (
    select attempt.result ->> 'sqlstate'
    from t_acceptance_delete_second attempt
  ),
  '42501',
  'the stale acceptance receives deterministic insufficient-privilege authorization'
);
select ok(
  (
    select
      participant.status = 'lapsed'
      and participant.accepted_at is null
      and participant.timezone is null
      and participant.charity_id is null
    from public.contest_participants participant
    where participant.contest_id =
          'f2000000-0000-0000-0000-000000000002'
      and participant.user_id =
          'e2000000-0000-0000-0000-000000000002'
  ),
  'the rejected acceptance leaves no partial terms or accepted timestamp'
);
select ok(
  (
    select
      pg_catalog.count(*) = 1
      and pg_catalog.bool_and(event.from_status = 'invited')
      and pg_catalog.bool_and(event.to_status = 'lapsed')
    from app.account_deletion_participant_events event
    where event.actor_id =
      'e2000000-0000-0000-0000-000000000002'
  ),
  'only the deletion-authored invited-to-lapsed event survives'
);
select ok(
  (
    select contest.status = 'pending'
    from public.contests contest
    where contest.id = 'f2000000-0000-0000-0000-000000000002'
  )
  and (
    select pg_catalog.jsonb_array_length(
      deletion.result -> 'capabilities'
    ) = 0
    from t_acceptance_delete_first deletion
  ),
  'the failed acceptance neither activates the contest nor creates a capability'
);
select is(
  (
    select pg_catalog.count(*)
    from public.notification_intents intent
    join app.account_deletion_participant_events event
      on event.id = intent.entity_id
    where event.actor_id =
          'e2000000-0000-0000-0000-000000000002'
      and intent.event_type = 'contest_participation_changed'
      and intent.recipient_user_id =
          'e0000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the deletion event has one durable creator intent and no partial duplicate'
);

-- ===========================================================================
-- Race 3: attested metric ingest and deletion
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Ingest commits first. Deletion must retain its attested evidence.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role service_role');

create temporary table t_ingest_first_batch as
select remote.batch_id, remote.observation_count, remote.replayed
from extensions.dblink(
  'p0_first',
  $ingest$
    select batch.batch_id, batch.observation_count, batch.replayed
    from public.record_metric_batch(
      'e3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001',
      'eb300000-0000-0000-0000-000000000001',
      extensions.digest(
        pg_catalog.convert_to('p0-ingest-first', 'UTF8'),
        'sha256'
      ),
      pg_catalog.clock_timestamp(),
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'metric', 'steps',
          'bucket_start',
            pg_catalog.date_trunc(
              'hour',
              pg_catalog.clock_timestamp()
            ) - interval '2 hours',
          'value', 1234,
          'provenance', 'device',
          'sample_count', 1,
          'source_bundle_id', 'com.apple.health',
          'device_model', 'iPhone'
        )
      ),
      extensions.digest(
        pg_catalog.decode(
          '04' || pg_catalog.repeat('31', 64),
          'hex'
        ),
        'sha256'
      ),
      1
    ) batch
  $ingest$
) as remote(
  batch_id uuid,
  observation_count integer,
  replayed boolean
);

select ok(
  (
    select
      batch.observation_count = 1
      and not batch.replayed
    from t_ingest_first_batch batch
  ),
  'the attested batch is complete before its transaction is released'
);

select extensions.dblink_exec('p0_second', 'set role service_role');
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $delete$
      select public.delete_account(
        'e3000000-0000-0000-0000-000000000001'
      )
    $delete$
  ) = 1,
  'deletion starts while the attested batch is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'ingest holds the actor lock through counter, batch, and snapshot writes'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_ingest_first_delete as
select remote.result
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select *
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select extensions.dblink_exec('p0_second', 'reset role');

select ok(
  (
    select
      pg_catalog.jsonb_array_length(
        deletion.result -> 'capabilities'
      ) = 1
      and (
        deletion.result -> 'capabilities' -> 0 ->> 'scopeId'
      )::uuid = 'f3000000-0000-0000-0000-000000000001'
    from t_ingest_first_delete deletion
  ),
  'deletion returns the active lineage capability after ingest commits'
);
select ok(
  (
    select
      device.sign_count = 1
      and device.last_asserted_at is not null
      and device.revoked_at is not null
    from public.device_attestations device
    where device.user_id =
      'e3000000-0000-0000-0000-000000000001'
  ),
  'deletion revokes but does not erase the consumed attestation counter'
);
select ok(
  (
    select
      batch.attested
      and batch.sign_count = 1
      and batch.observation_count = 1
      and batch.id = first_batch.batch_id
    from public.ingest_batches batch
    cross join t_ingest_first_batch first_batch
    where batch.user_id =
      'e3000000-0000-0000-0000-000000000001'
      and batch.client_batch_id =
        'eb300000-0000-0000-0000-000000000001'
  ),
  'the attested ingest audit row survives account deletion intact'
);
select ok(
  (
    select
      pg_catalog.count(*) = 1
      and pg_catalog.bool_and(snapshot.value = 1234)
      and pg_catalog.bool_and(snapshot.provenance = 'device')
      and pg_catalog.bool_and(snapshot.source_bundle_id = 'com.apple.health')
    from public.metric_snapshots snapshot
    where snapshot.user_id =
      'e3000000-0000-0000-0000-000000000001'
      and snapshot.contest_id =
        'f3000000-0000-0000-0000-000000000001'
  ),
  'the one committed metric fact survives with its exact source classification'
);
select ok(
  (
    select participant.status = 'accepted'
    from public.contest_participants participant
    where participant.contest_id =
          'f3000000-0000-0000-0000-000000000001'
      and participant.user_id =
          'e3000000-0000-0000-0000-000000000001'
  )
  and (
    select contest.status = 'active'
    from public.contests contest
    where contest.id = 'f3000000-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.profiles profile
    where profile.id = 'e3000000-0000-0000-0000-000000000001'
      and profile.deleted_at is not null
  )
  and not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = 'e3000000-0000-0000-0000-000000000001'
  ),
  'ingest-first deletion retains the accepted durable actor and active agreement'
);
select ok(
  exists (
    select 1
    from app.account_capabilities capability
    join app.workflow_scopes scope
      on scope.scope_kind = capability.scope_kind
     and scope.scope_id = capability.scope_id
    join app.workflow_scope_actors scope_actor
      on scope_actor.scope_kind = scope.scope_kind
     and scope_actor.scope_id = scope.scope_id
     and scope_actor.actor_id = capability.actor_id
    where capability.actor_id =
          'e3000000-0000-0000-0000-000000000001'
      and scope.contest_id =
          'f3000000-0000-0000-0000-000000000001'
  ),
  'the continuation capability remains attached to its durable actor and scope'
);

-- ---------------------------------------------------------------------------
-- Deletion commits first. Ingest must fail before consuming the counter.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec('p0_first', 'begin');
select extensions.dblink_exec('p0_first', 'set local role service_role');

create temporary table t_ingest_delete_first as
select remote.result
from extensions.dblink(
  'p0_first',
  $delete$
    select public.delete_account(
      'e3000000-0000-0000-0000-000000000002'
    )
  $delete$
) as remote(result jsonb);

select extensions.dblink_exec('p0_second', 'set role service_role');
select ok(
  extensions.dblink_send_query(
    'p0_second',
    $ingest$
      select pg_temp.capture_statement(
        $statement$
          select *
          from public.record_metric_batch(
            'e3000000-0000-0000-0000-000000000002',
            'f3000000-0000-0000-0000-000000000002',
            'eb300000-0000-0000-0000-000000000002',
            extensions.digest(
              pg_catalog.convert_to('p0-delete-first-ingest', 'UTF8'),
              'sha256'
            ),
            pg_catalog.clock_timestamp(),
            pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                'metric', 'steps',
                'bucket_start',
                  pg_catalog.date_trunc(
                    'hour',
                    pg_catalog.clock_timestamp()
                  ) - interval '2 hours',
                'value', 4321,
                'provenance', 'device',
                'sample_count', 1,
                'source_bundle_id', 'com.apple.health',
                'device_model', 'iPhone'
              )
            ),
            extensions.digest(
              pg_catalog.decode(
                '04' || pg_catalog.repeat('32', 64),
                'hex'
              ),
              'sha256'
            ),
            1
          )
        $statement$
      )
    $ingest$
  ) = 1,
  'the attested ingest starts while deletion is still uncommitted'
);
select ok(
  pg_temp.wait_for_blocked_backend('gametime_p0_second'),
  'the metric writer waits at the same active-actor serialization lock'
);

select extensions.dblink_exec('p0_first', 'commit');

create temporary table t_ingest_delete_second as
select remote.result
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select *
from extensions.dblink_get_result('p0_second') as remote(result jsonb);
select extensions.dblink_exec('p0_second', 'reset role');

select is(
  (
    select (attempt.result ->> 'ok')::boolean
    from t_ingest_delete_second attempt
  ),
  false,
  'the post-deletion metric write is rejected'
);
select is(
  (
    select attempt.result ->> 'sqlstate'
    from t_ingest_delete_second attempt
  ),
  '42501',
  'metric ingest receives deterministic insufficient-privilege authorization'
);
select is_empty(
  $$ select 1
     from public.ingest_batches batch
     where batch.user_id =
       'e3000000-0000-0000-0000-000000000002'::uuid
       and batch.client_batch_id =
         'eb300000-0000-0000-0000-000000000002'::uuid $$,
  'the losing ingest transaction leaves no batch record'
);
select is_empty(
  $$ select 1
     from public.metric_snapshots snapshot
     where snapshot.user_id =
       'e3000000-0000-0000-0000-000000000002'::uuid
       and snapshot.contest_id =
         'f3000000-0000-0000-0000-000000000002'::uuid $$,
  'the losing ingest transaction leaves no metric snapshot'
);
select ok(
  (
    select
      device.sign_count = 0
      and device.last_asserted_at is null
      and device.revoked_at is not null
    from public.device_attestations device
    where device.user_id =
      'e3000000-0000-0000-0000-000000000002'
  ),
  'failed ingest consumes no assertion counter before the revoked key is observed'
);
select ok(
  (
    select
      pg_catalog.jsonb_array_length(
        deletion.result -> 'capabilities'
      ) = 1
      and (
        deletion.result -> 'capabilities' -> 0 ->> 'scopeId'
      )::uuid = 'f3000000-0000-0000-0000-000000000002'
    from t_ingest_delete_first deletion
  )
  and (
    select participant.status = 'accepted'
    from public.contest_participants participant
    where participant.contest_id =
          'f3000000-0000-0000-0000-000000000002'
      and participant.user_id =
          'e3000000-0000-0000-0000-000000000002'
  ),
  'deletion-first ingest retains the active agreement and its continuation'
);

-- ===========================================================================
-- Cross-race orphan and transaction-marker audit
-- ===========================================================================

select ok(
  not exists (
    select 1
    from public.contest_participants participant
    left join public.contests contest on contest.id = participant.contest_id
    left join public.profiles profile on profile.id = participant.user_id
    where participant.contest_id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    )
      and (contest.id is null or profile.id is null)
  )
  and not exists (
    select 1
    from app.account_deletion_participant_events event
    left join public.contest_participants participant
      on participant.contest_id = event.contest_id
     and participant.user_id = event.actor_id
    left join public.notification_intents intent
      on intent.entity_id = event.id
     and intent.event_type = 'contest_participation_changed'
    where event.actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
      and (participant.contest_id is null or intent.id is null)
  )
  and not exists (
    select 1
    from public.ingest_batches batch
    left join public.contest_participants participant
      on participant.contest_id = batch.contest_id
     and participant.user_id = batch.user_id
    left join public.profiles profile on profile.id = batch.user_id
    where batch.user_id in (
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
      and (participant.contest_id is null or profile.id is null)
  )
  and not exists (
    select 1
    from public.metric_snapshots snapshot
    left join public.ingest_batches batch on batch.id = snapshot.batch_id
    where snapshot.user_id in (
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
      and batch.id is null
  )
  and not exists (
    select 1
    from app.account_capabilities capability
    left join public.profiles profile on profile.id = capability.actor_id
    left join app.workflow_scopes scope
      on scope.scope_kind = capability.scope_kind
     and scope.scope_id = capability.scope_id
    where capability.actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
      and (profile.id is null or scope.scope_id is null)
  ),
  'all race products retain their participant, actor, outbox, evidence, and scope parents'
);
select is_empty(
  $$ select 1
     from app.account_deletion_transactions deletion
     where deletion.actor_id in (
       'e1000000-0000-0000-0000-000000000001'::uuid,
       'e1000000-0000-0000-0000-000000000002'::uuid,
       'e2000000-0000-0000-0000-000000000001'::uuid,
       'e2000000-0000-0000-0000-000000000002'::uuid,
       'e3000000-0000-0000-0000-000000000001'::uuid,
       'e3000000-0000-0000-0000-000000000002'::uuid
     ) $$,
  'every successful deletion removes its private transaction marker'
);
select ok(
  (
    select pg_catalog.count(*) = 6
    from public.profiles profile
    where profile.id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
      and profile.deleted_at is not null
      and profile.display_name = 'Deleted member'
      and profile.handle::text ~ '^deleted-[0-9a-f]{20}$'
  )
  and not exists (
    select 1
    from auth.users auth_user
    where auth_user.id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
  )
  and not exists (
    select 1
    from app.active_profile_auth_bindings binding
    where binding.actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
  ),
  'all six races end with one durable tombstone and no live authentication'
);

-- ---------------------------------------------------------------------------
-- dblink commits are outside this file's rollback; remove only our fixtures.
-- ---------------------------------------------------------------------------

select extensions.dblink_exec(
  'p0_setup',
  $cleanup$
    set session_replication_role = replica;

    delete from public.metric_snapshots
    where contest_id in (
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    );

    delete from public.ingest_batches
    where user_id in (
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from public.device_attestations
    where user_id in (
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from public.notification_intents
    where recipient_user_id in (
      'e0000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
       or entity_id in (
         'f1000000-0000-0000-0000-000000000001',
         'f1000000-0000-0000-0000-000000000002',
         'f2000000-0000-0000-0000-000000000001',
         'f2000000-0000-0000-0000-000000000002',
         'f3000000-0000-0000-0000-000000000001',
         'f3000000-0000-0000-0000-000000000002'
       );

    delete from app.account_deletion_participant_events
    where actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from app.account_capabilities
    where actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from app.workflow_scope_actors
    where scope_id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    )
       or actor_id in (
         'e1000000-0000-0000-0000-000000000001',
         'e1000000-0000-0000-0000-000000000002',
         'e2000000-0000-0000-0000-000000000001',
         'e2000000-0000-0000-0000-000000000002',
         'e3000000-0000-0000-0000-000000000001',
         'e3000000-0000-0000-0000-000000000002'
       );

    delete from app.workflow_scopes
    where contest_id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    );

    delete from public.contest_participants
    where contest_id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    );

    delete from public.contests
    where id in (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000002'
    );

    delete from app.account_deletion_transactions
    where actor_id in (
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from app.profile_handle_claims
    where actor_id in (
      'e0000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'e0000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from public.profiles
    where id in (
      'e0000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from auth.users
    where id in (
      'e0000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    );

    delete from public.charities
    where id = 'ec000000-0000-0000-0000-000000000001';

    set session_replication_role = origin;
  $cleanup$
);

select extensions.dblink_disconnect('p0_second');
select extensions.dblink_disconnect('p0_first');
select extensions.dblink_disconnect('p0_setup');

select * from finish();
rollback;
