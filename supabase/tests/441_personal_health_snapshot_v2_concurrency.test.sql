-- Real-session serialization for automatic Apple Health whole snapshots.
--
-- Cases: first-insert races, equal-time conflicts, newer whole replacements
-- (including decreases), and an uploader waiting behind terminal publication.

begin;
select no_plan();

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_health_block(
  p_application_name text,
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
    if exists (
      select 1
      from pg_catalog.pg_stat_activity activity
      where activity.application_name = p_application_name
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
  connection_name,
  'host=supabase_db_gametime port=5432 dbname=postgres user=postgres password=postgres'
)
from unnest(array[
  'health_setup', 'health_gate', 'health_one', 'health_two', 'health_worker'
]) connection_name;

select extensions.dblink_exec(
  connection_name,
  format('set application_name = %L', 'gametime_' || connection_name)
)
from unnest(array['health_one', 'health_two', 'health_worker']) connection_name;

select extensions.dblink_exec(
  'health_setup',
  $setup$
    insert into auth.users (id) values
      ('dd111111-1111-1111-1111-111111111111'),
      ('dd222222-2222-2222-2222-222222222222'),
      ('dd333333-3333-3333-3333-333333333333');

    insert into public.profiles (id, handle, display_name, timezone) values
      ('dd111111-1111-1111-1111-111111111111', 'healthraceone', 'Health Race One', 'UTC'),
      ('dd222222-2222-2222-2222-222222222222', 'healthracetwo', 'Health Race Two', 'UTC'),
      ('dd333333-3333-3333-3333-333333333333', 'healthstriprace', 'Health Stripe Race', 'UTC');

    alter table public.contests disable trigger contests_assert_future_window;
    insert into public.contests (
      id, title, created_by, challenge_model, metric, cadence, target_value,
      stake_amount_cents, tie_break, starts_at, ends_at, max_participants, status
    ) values
      (
        'dd000000-0000-0000-0000-000000000001', 'Health upload race',
        'dd111111-1111-1111-1111-111111111111', 'personal_accountability',
        'steps', 'cumulative', 1, 1000, 'void',
        clock_timestamp() - interval '7 days 12 hours',
        clock_timestamp() - interval '12 hours',
        1, 'active'
      ),
      (
        'dd000000-0000-0000-0000-000000000002', 'Health cutoff race',
        'dd222222-2222-2222-2222-222222222222', 'personal_accountability',
        'steps', 'cumulative', 1, 1000, 'void',
        '2026-07-01T00:00:00Z', '2026-07-08T00:00:00Z',
        1, 'active'
      );
    alter table public.contests enable trigger contests_assert_future_window;

    alter table public.contest_participants
      disable trigger contest_participants_apply_transition;
    insert into public.contest_participants (
      contest_id, user_id, status, timezone, charity_id, accepted_at
    ) values
      ('dd000000-0000-0000-0000-000000000001', 'dd111111-1111-1111-1111-111111111111', 'accepted', 'UTC', null, clock_timestamp() - interval '2 days'),
      ('dd000000-0000-0000-0000-000000000002', 'dd222222-2222-2222-2222-222222222222', 'accepted', 'UTC', null, '2026-06-30T00:00:00Z');
    alter table public.contest_participants
      enable trigger contest_participants_apply_transition;

    insert into public.personal_challenge_terms (
      challenge_id, user_id, cadence, target_steps, commitment_amount_minor,
      terms_version, timezone, agreed_at, evidence_cutoff, step_data_policy
    ) values
      (
        'dd000000-0000-0000-0000-000000000001',
        'dd111111-1111-1111-1111-111111111111',
        'cumulative', 1, 1000, 'personal-v2', 'UTC',
        clock_timestamp() - interval '8 days',
        (select contest.ends_at + interval '24 hours'
         from public.contests contest
         where contest.id = 'dd000000-0000-0000-0000-000000000001'),
        'healthkit_nonmanual_daily_v1'
      ),
      (
        'dd000000-0000-0000-0000-000000000002',
        'dd222222-2222-2222-2222-222222222222',
        'cumulative', 1, 1000, 'personal-v2', 'UTC',
        '2026-06-30T00:00:00Z', '2026-07-09T00:00:00Z',
        'healthkit_nonmanual_daily_v1'
      );

    create function public.health_race_upload(
      p_challenge_id uuid,
      p_observed_at timestamptz,
      p_query_through timestamptz,
      p_total integer
    )
    returns text
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    declare
      v_days jsonb;
    begin
      select jsonb_agg(
        jsonb_build_object(
          'local_date', day ->> 'local_date',
          'total_steps', p_total
        ) order by ordinality
      ) into v_days
      from jsonb_array_elements(app.personal_zero_daily_progress_v2(p_challenge_id))
        with ordinality source(day, ordinality);

      perform public.upsert_my_personal_health_snapshot_v2(
        p_challenge_id,
        app.personal_terms_fingerprint_v2(p_challenge_id),
        p_observed_at,
        p_query_through,
        v_days
      );
      return 'ok';
    exception when others then
      return sqlstate;
    end;
    $function$;

    grant execute on function public.health_race_upload(uuid,timestamptz,timestamptz,integer)
      to authenticated;
  $setup$
);

select extensions.dblink_exec('health_one', 'set role authenticated');
select extensions.dblink_exec('health_two', 'set role authenticated');
select extensions.dblink_exec(
  'health_one',
  $$ set "request.jwt.claims" = '{"sub":"dd111111-1111-1111-1111-111111111111"}' $$
);
select extensions.dblink_exec(
  'health_two',
  $$ set "request.jwt.claims" = '{"sub":"dd111111-1111-1111-1111-111111111111"}' $$
);

-- Gate the contest lock so both first inserts are genuinely in flight.
select extensions.dblink_exec('health_gate', 'begin');
select extensions.dblink_exec(
  'health_gate',
  $$ update public.contests set title = title
     where id = 'dd000000-0000-0000-0000-000000000001' $$
);

select is(
  extensions.dblink_send_query(
    'health_one',
    $$ select public.health_race_upload(
         'dd000000-0000-0000-0000-000000000001',
         date_trunc('hour', clock_timestamp()),
         (select ends_at from public.contests
          where id = 'dd000000-0000-0000-0000-000000000001'),
         0
       ) $$
  ),
  1,
  'the first initial upload starts'
);
select is(
  extensions.dblink_send_query(
    'health_two',
    $$ select public.health_race_upload(
         'dd000000-0000-0000-0000-000000000001',
         date_trunc('hour', clock_timestamp()),
         (select ends_at from public.contests
          where id = 'dd000000-0000-0000-0000-000000000001'),
         0
       ) $$
  ),
  1,
  'the second initial upload starts'
);

select ok(
  pg_temp.wait_for_health_block('gametime_health_one')
  and pg_temp.wait_for_health_block('gametime_health_two'),
  'both initial uploads wait at the same contest serialization point'
);
select is(extensions.dblink_exec('health_gate', 'commit'), 'COMMIT',
  'releasing the gate lets one whole snapshot win');

create temporary table t_first_race as
select response
from extensions.dblink_get_result('health_one') result(response text)
union all
select response
from extensions.dblink_get_result('health_two') result(response text);
select count(*) from extensions.dblink_get_result('health_one') result(response text);
select count(*) from extensions.dblink_get_result('health_two') result(response text);

select is(
  (select count(*) from t_first_race where response = 'ok'),
  2::bigint,
  'simultaneous identical first inserts converge through replay semantics'
);
select is(
  (
    select count(*)
    from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id = 'dd000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the initial race persists exactly one private row'
);

-- Deterministic equal-time conflict and newer lower replacement use the same
-- two external authenticated sessions.
create temporary table t_race_state as
select snapshot.observed_at, snapshot.query_through
from app.personal_health_snapshots_v2 snapshot
where snapshot.challenge_id = 'dd000000-0000-0000-0000-000000000001';

select is(
  (
    select response
    from extensions.dblink(
      'health_two',
      format(
        $sql$select public.health_race_upload(
          'dd000000-0000-0000-0000-000000000001', %L, %L, 1
        )$sql$,
        (select observed_at from t_race_state),
        (select query_through from t_race_state)
      )
    ) result(response text)
  ),
  '23505',
  'equal observation time with different contents loses deterministically'
);

select is(
  (
    select response
    from extensions.dblink(
      'health_one',
      format(
        $sql$select public.health_race_upload(
          'dd000000-0000-0000-0000-000000000001', %L, %L, 1
        )$sql$,
        (select observed_at + interval '1 second' from t_race_state),
        (select query_through from t_race_state)
      )
    ) result(response text)
  ),
  'ok',
  'a newer observation replaces the whole snapshot'
);
select is(
  (
    select response
    from extensions.dblink(
      'health_two',
      format(
        $sql$select public.health_race_upload(
          'dd000000-0000-0000-0000-000000000001', %L, %L, 0
        )$sql$,
        (select observed_at + interval '2 seconds' from t_race_state),
        (select query_through from t_race_state)
      )
    ) result(response text)
  ),
  'ok',
  'a still-newer observation may replace all totals downward'
);
select is(
  (
    select snapshot.total_steps
    from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id = 'dd000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the final whole replacement persists the lower authoritative total'
);

-- Publisher wins the cutoff race. The upload waits on its profile/contest
-- locks, then cannot mutate the finalized challenge or recreate the snapshot.
select extensions.dblink_exec('health_worker', 'begin');
create temporary table t_cutoff_result as
select result_id
from extensions.dblink(
  'health_worker',
  $$ select app.publish_due_personal_result_v2(
       'dd000000-0000-0000-0000-000000000002',
       clock_timestamp()
     ) $$
) result(result_id uuid);

select extensions.dblink_exec('health_two', 'reset role');
select extensions.dblink_exec('health_two', 'set role authenticated');
select extensions.dblink_exec(
  'health_two',
  $$ set "request.jwt.claims" = '{"sub":"dd222222-2222-2222-2222-222222222222"}' $$
);
select is(
  extensions.dblink_send_query(
    'health_two',
    $$ select public.health_race_upload(
         'dd000000-0000-0000-0000-000000000002',
         clock_timestamp(),
         '2026-07-08T00:00:00Z',
         0
       ) $$
  ),
  1,
  'an uploader starts while terminal publication remains uncommitted'
);
select ok(
  pg_temp.wait_for_health_block('gametime_health_two'),
  'the uploader waits behind terminal publication locks'
);
select is(extensions.dblink_exec('health_worker', 'commit'), 'COMMIT',
  'committing publication releases the cutoff serialization point');

create temporary table t_late_upload as
select response
from extensions.dblink_get_result('health_two') result(response text);
select count(*) from extensions.dblink_get_result('health_two') result(response text);

select is(
  (select response from t_late_upload),
  '42501',
  'the waiting uploader fails after publication finalizes the challenge'
);
select ok(
  exists (
    select 1 from public.personal_challenge_results result
    where result.challenge_id = 'dd000000-0000-0000-0000-000000000002'
      and result.outcome = 'inconclusive'
      and result.commitment_waived
  )
  and not exists (
    select 1 from app.personal_health_snapshots_v2 snapshot
    where snapshot.challenge_id = 'dd000000-0000-0000-0000-000000000002'
  ),
  'the cutoff race leaves one immutable result and no mutable snapshot'
);

-- A legacy and Health-marked Stripe commit for the same admitted setup are
-- genuinely concurrent. The actor lock chooses one policy, and the losing
-- boundary must reject instead of replaying the winner as its own policy.
select *
from extensions.dblink(
  'health_setup',
  $$ select public.set_personal_stripe_sandbox_runtime_v1(
       'ddf00000-0000-4000-8000-000000000001', true
     ) $$
) result(enabled boolean);
select *
from extensions.dblink(
  'health_setup',
  $$ select public.set_personal_stripe_sandbox_beta_eligibility_v1(
       'ddf00000-0000-4000-8000-000000000002',
       'dd333333-3333-3333-3333-333333333333',
       true
     ) $$
) result(eligible boolean);

select extensions.dblink_exec(
  'health_setup',
  $stripe_setup$
    insert into app.personal_stripe_sandbox_customers (
      user_id, stripe_customer_id
    ) values (
      'dd333333-3333-3333-3333-333333333333',
      'cus_DD333333333333333333333333333333'
    );

    insert into app.personal_stripe_sandbox_setups (
      id, user_id, request_id, payload_hash, cadence, target_steps,
      commitment_amount_minor, currency, timezone, agreement_version,
      consent_version, consented_at, expires_at, stripe_customer_id,
      stripe_setup_intent_id, stripe_payment_method_id, status, succeeded_at,
      beta_authorization_version, beta_authorized_at
    ) values (
      'ddf00000-0000-4000-8000-000000000003',
      'dd333333-3333-3333-3333-333333333333',
      'ddf00000-0000-4000-8000-000000000004',
      decode(repeat('3d', 32), 'hex'),
      'daily', 333, 1000, 'USD', 'UTC',
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1',
      statement_timestamp(), statement_timestamp() + interval '24 hours',
      'cus_DD333333333333333333333333333333',
      'seti_DD33333333333333333333333333333',
      'pm_DD333333333333333333333333333333',
      'succeeded', statement_timestamp(),
      'personal-stripe-sandbox-beta-v1', statement_timestamp()
    );

    create function public.health_stripe_policy_race(p_policy text)
    returns text
    language plpgsql
    volatile
    security definer
    set search_path = ''
    as $function$
    declare
      v_result jsonb;
      v_policy text;
    begin
      if p_policy = 'v1' then
        v_result := public.commit_personal_stripe_sandbox_challenge_service_v1(
          'dd333333-3333-3333-3333-333333333333',
          'ddf00000-0000-4000-8000-000000000004',
          'ddf00000-0000-4000-8000-000000000003',
          'daily', 333, 1000, 'USD', 'UTC', null,
          'personal-stripe-sandbox-v1',
          'personal-stripe-sandbox-consent-v1'
        );
      elsif p_policy = 'v2' then
        v_result := public.commit_personal_stripe_sandbox_challenge_service_v2(
          'dd333333-3333-3333-3333-333333333333',
          'ddf00000-0000-4000-8000-000000000004',
          'ddf00000-0000-4000-8000-000000000003',
          'daily', 333, 1000, 'USD', 'UTC', null,
          'personal-stripe-sandbox-v1',
          'personal-stripe-sandbox-consent-v1'
        );
      else
        raise exception 'invalid test policy';
      end if;

      select terms.step_data_policy::text into v_policy
      from public.personal_challenge_terms terms
      where terms.challenge_id = (v_result ->> 'challenge_id')::uuid;
      return 'ok:' || v_policy;
    exception when others then
      return sqlstate;
    end;
    $function$;

    grant execute on function public.health_stripe_policy_race(text)
      to service_role;
  $stripe_setup$
);

select extensions.dblink_exec('health_one', 'reset role');
select extensions.dblink_exec('health_two', 'reset role');
select extensions.dblink_exec('health_one', 'set role service_role');
select extensions.dblink_exec('health_two', 'set role service_role');
select extensions.dblink_exec('health_gate', 'begin');
select extensions.dblink_exec(
  'health_gate',
  $$ update public.profiles set display_name = display_name
     where id = 'dd333333-3333-3333-3333-333333333333' $$
);
select is(
  extensions.dblink_send_query(
    'health_one',
    $$ select public.health_stripe_policy_race('v1') $$
  ),
  1,
  'the unmarked Stripe commit enters the policy race'
);
select is(
  extensions.dblink_send_query(
    'health_two',
    $$ select public.health_stripe_policy_race('v2') $$
  ),
  1,
  'the Health-marked Stripe commit enters the policy race'
);
select ok(
  pg_temp.wait_for_health_block('gametime_health_one')
  and pg_temp.wait_for_health_block('gametime_health_two'),
  'both Stripe policies wait behind the same owner serialization point'
);
select is(extensions.dblink_exec('health_gate', 'commit'), 'COMMIT',
  'releasing the owner lock lets exactly one Stripe policy commit');

create temporary table t_stripe_policy_race as
select 'v1'::text as requested_policy, response
from extensions.dblink_get_result('health_one') result(response text)
union all
select 'v2'::text, response
from extensions.dblink_get_result('health_two') result(response text);
select count(*) from extensions.dblink_get_result('health_one') result(response text);
select count(*) from extensions.dblink_get_result('health_two') result(response text);

select ok(
  (select count(*) = 1 from t_stripe_policy_race where response like 'ok:%')
  and (select count(*) = 1 from t_stripe_policy_race where response = '22023'),
  'one Stripe policy wins and the opposite policy cannot acknowledge its challenge'
);
select ok(
  exists (
    select 1
    from t_stripe_policy_race race
    join app.personal_stripe_sandbox_setups setup
      on setup.id = 'ddf00000-0000-4000-8000-000000000003'
    join public.personal_challenge_terms terms
      on terms.challenge_id = setup.consumed_challenge_id
    where race.response = 'ok:' || terms.step_data_policy::text
      and (
        (race.requested_policy = 'v1'
          and terms.step_data_policy = 'attested_hourly_v1')
        or
        (race.requested_policy = 'v2'
          and terms.step_data_policy = 'healthkit_nonmanual_daily_v1')
      )
  ),
  'the committed Stripe policy exactly matches the winning boundary'
);

select extensions.dblink_exec(
  'health_setup',
  $cleanup$
    set session_replication_role = replica;
    drop function public.health_stripe_policy_race(text);
    delete from app.personal_stripe_sandbox_agreements
      where setup_id = 'ddf00000-0000-4000-8000-000000000003';
    delete from app.personal_stripe_sandbox_setups
      where id = 'ddf00000-0000-4000-8000-000000000003';
    delete from app.personal_challenge_creation_requests
      where actor_id = 'dd333333-3333-3333-3333-333333333333';
    delete from public.personal_challenge_terms
      where user_id = 'dd333333-3333-3333-3333-333333333333';
    delete from public.contest_participants
      where user_id = 'dd333333-3333-3333-3333-333333333333';
    delete from app.workflow_scope_actors
      where actor_id = 'dd333333-3333-3333-3333-333333333333';
    delete from app.workflow_scopes scope
      using public.contests contest
      where contest.created_by = 'dd333333-3333-3333-3333-333333333333'
        and scope.scope_kind = 'contest_lineage'
        and scope.scope_id = contest.id;
    delete from public.contests
      where created_by = 'dd333333-3333-3333-3333-333333333333';
    delete from app.personal_stripe_sandbox_customers
      where user_id = 'dd333333-3333-3333-3333-333333333333';
    delete from app.personal_stripe_sandbox_beta_eligibility
      where owner_id = 'dd333333-3333-3333-3333-333333333333';
    delete from app.personal_stripe_sandbox_control_requests
      where request_id in (
        'ddf00000-0000-4000-8000-000000000001',
        'ddf00000-0000-4000-8000-000000000002'
      );
    update app.personal_stripe_sandbox_runtime
      set payment_activity_enabled = false,
          updated_at = clock_timestamp()
      where singleton;
    drop function public.health_race_upload(uuid,timestamptz,timestamptz,integer);
    delete from app.personal_result_worker_attempts
      where challenge_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from public.personal_challenge_results
      where challenge_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from app.personal_health_snapshots_v2
      where challenge_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from public.personal_challenge_terms
      where challenge_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from public.contest_participants
      where contest_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from app.workflow_scope_actors
      where scope_kind = 'contest_lineage'
        and scope_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from app.workflow_scopes
      where scope_kind = 'contest_lineage'
        and scope_id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from public.contests
      where id in ('dd000000-0000-0000-0000-000000000001','dd000000-0000-0000-0000-000000000002');
    delete from app.profile_handle_claims
      where actor_id in ('dd111111-1111-1111-1111-111111111111','dd222222-2222-2222-2222-222222222222','dd333333-3333-3333-3333-333333333333');
    delete from app.active_profile_auth_bindings
      where actor_id in ('dd111111-1111-1111-1111-111111111111','dd222222-2222-2222-2222-222222222222','dd333333-3333-3333-3333-333333333333');
    delete from public.profiles
      where id in ('dd111111-1111-1111-1111-111111111111','dd222222-2222-2222-2222-222222222222','dd333333-3333-3333-3333-333333333333');
    delete from auth.users
      where id in ('dd111111-1111-1111-1111-111111111111','dd222222-2222-2222-2222-222222222222','dd333333-3333-3333-3333-333333333333');
    set session_replication_role = origin;
  $cleanup$
);

select is(extensions.dblink_disconnect('health_one'), 'OK',
  'the first uploader disconnects cleanly');
select is(extensions.dblink_disconnect('health_two'), 'OK',
  'the second uploader disconnects cleanly');
select is(extensions.dblink_disconnect('health_worker'), 'OK',
  'the publisher disconnects cleanly');
select extensions.dblink_disconnect('health_gate');
select extensions.dblink_disconnect('health_setup');

select * from finish();
rollback;
