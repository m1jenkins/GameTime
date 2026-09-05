-- Real database sessions prove both lock-sensitive Stripe sandbox control
-- boundaries:
--   1. an admitted setup commits before one atomic runtime-off + eligibility-
--      revoke service transaction, without a deadlock; and
--   2. account deletion commits before charge discovery, so a stale active-
--      actor snapshot can never create or lease a simulated charge command.

begin;
select no_plan();

select has_extension(
  'extensions',
  'dblink',
  'the local harness provides the multi-session concurrency driver'
);

create function pg_temp.wait_for_stripe_control_block(
  p_waiter_application_name text,
  p_blocker_application_name text,
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
    -- A transaction otherwise reuses one statistics snapshot and can miss a
    -- backend that began waiting after the first poll.
    perform pg_catalog.pg_stat_clear_snapshot();

    if exists (
      select 1
      from pg_catalog.pg_stat_activity waiter
      where waiter.application_name = p_waiter_application_name
        and exists (
          select 1
          from pg_catalog.unnest(
            pg_catalog.pg_blocking_pids(waiter.pid)
          ) as blocked(blocker_pid)
          join pg_catalog.pg_stat_activity blocker
            on blocker.pid = blocked.blocker_pid
          where blocker.application_name = p_blocker_application_name
        )
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
  'stripe_control_setup',
  pg_catalog.format(
    'host=' || host(inet_server_addr()) || ' port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);
select extensions.dblink_connect(
  'stripe_control_apply',
  pg_catalog.format(
    'host=' || host(inet_server_addr()) || ' port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);
select extensions.dblink_connect(
  'stripe_control_delete',
  pg_catalog.format(
    'host=' || host(inet_server_addr()) || ' port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);
select extensions.dblink_connect(
  'stripe_control_claim',
  pg_catalog.format(
    'host=' || host(inet_server_addr()) || ' port=5432 dbname=%s user=postgres password=postgres',
    pg_catalog.current_database()
  )
);

select extensions.dblink_exec(
  'stripe_control_setup',
  $$ set application_name = 'gametime_stripe_control_setup' $$
);
select extensions.dblink_exec(
  'stripe_control_apply',
  $$ set application_name = 'gametime_stripe_control_apply' $$
);
select extensions.dblink_exec(
  'stripe_control_delete',
  $$ set application_name = 'gametime_stripe_control_delete' $$
);
select extensions.dblink_exec(
  'stripe_control_claim',
  $$ set application_name = 'gametime_stripe_control_claim' $$
);

-- The fixture session commits state that every dblink worker can observe. The
-- setup retry wrapper returns only SQLSTATE, never provider or account data.
select extensions.dblink_exec(
  'stripe_control_setup',
  $setup$
    insert into auth.users (id)
    values
      ('cb111111-1111-1111-1111-111111111111'),
      ('cb222222-2222-2222-2222-222222222222');

    insert into public.profiles (id, handle, display_name, timezone)
    values
      (
        'cb111111-1111-1111-1111-111111111111',
        'stripecontrolrace',
        'Stripe Control Race',
        'UTC'
      ),
      (
        'cb222222-2222-2222-2222-222222222222',
        'stripeclaimdelete',
        'Stripe Claim Delete',
        'UTC'
      );

    do $block$
    begin
      perform public.set_personal_stripe_sandbox_runtime_v1(
        'cb000000-0000-0000-0000-000000000001',
        true
      );
      perform public.set_personal_stripe_sandbox_beta_eligibility_v1(
        'cb000000-0000-0000-0000-000000000002',
        'cb111111-1111-1111-1111-111111111111',
        true
      );
      perform public.set_personal_stripe_sandbox_beta_eligibility_v1(
        'cb000000-0000-0000-0000-000000000003',
        'cb222222-2222-2222-2222-222222222222',
        true
      );
    end;
    $block$;

    create function pg_temp.try_stripe_control_setup(
      p_request_id uuid
    )
    returns text
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    begin
      perform public.begin_personal_stripe_sandbox_setup_v1(
        p_request_id,
        'daily',
        10000,
        1000,
        'USD',
        'UTC',
        null,
        'personal-stripe-sandbox-v1',
        'personal-stripe-sandbox-consent-v1'
      );
      return 'unexpected_success';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    revoke all on function pg_temp.try_stripe_control_setup(uuid)
      from public, anon, authenticated, service_role;
    grant execute on function pg_temp.try_stripe_control_setup(uuid)
      to authenticated;

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
      'cb200000-0000-0000-0000-000000000001',
      'Stripe deletion and claim race',
      'cb222222-2222-2222-2222-222222222222',
      'personal_accountability',
      'steps',
      'daily',
      10000,
      1000,
      'void',
      '2026-07-20T00:00:00Z',
      '2026-07-27T00:00:00Z',
      1,
      'pending'
    );

    alter table public.contests
      enable trigger contests_assert_future_window;

    insert into public.contest_participants (
      contest_id,
      user_id,
      status,
      timezone,
      charity_id
    )
    values (
      'cb200000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'accepted',
      'UTC',
      null
    );

    insert into public.personal_challenge_terms (
      challenge_id,
      user_id,
      cadence,
      target_steps,
      commitment_amount_minor,
      currency,
      settlement_mode,
      terms_version,
      timezone,
      agreed_at,
      evidence_cutoff,
      closed_at
    )
    values (
      'cb200000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'daily',
      10000,
      1000,
      'USD',
      'test_only',
      'personal-v1',
      'UTC',
      '2026-07-19T00:00:00Z',
      '2026-07-28T00:00:00Z',
      null
    );

    insert into app.personal_stripe_sandbox_customers (
      user_id,
      stripe_customer_id
    )
    values (
      'cb222222-2222-2222-2222-222222222222',
      'cus_CB222222222222222222222222222222'
    );

    insert into app.personal_stripe_sandbox_setups (
      id,
      user_id,
      request_id,
      payload_hash,
      cadence,
      target_steps,
      commitment_amount_minor,
      currency,
      timezone,
      agreement_version,
      consent_version,
      consented_at,
      expires_at,
      stripe_customer_id,
      stripe_setup_intent_id,
      stripe_payment_method_id,
      status,
      succeeded_at,
      consumed_at,
      consumed_challenge_id,
      beta_authorization_version,
      beta_authorized_at
    )
    values (
      'cb210000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'cb210000-0000-0000-0000-000000000002',
      decode(repeat('41', 32), 'hex'),
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1',
      '2026-07-19T01:00:00Z',
      '2026-07-20T01:00:00Z',
      'cus_CB222222222222222222222222222222',
      'seti_CB22222222222222222222222222222',
      'pm_CB222222222222222222222222222222',
      'succeeded',
      '2026-07-19T01:30:00Z',
      '2026-07-19T01:40:00Z',
      'cb200000-0000-0000-0000-000000000001',
      'personal-stripe-sandbox-beta-v1',
      '2026-07-19T01:00:00Z'
    );

    insert into app.personal_stripe_sandbox_agreements (
      challenge_id,
      user_id,
      setup_id,
      create_request_id,
      creation_payload_hash,
      setup_payload_hash,
      cadence,
      target_steps,
      commitment_amount_minor,
      currency,
      timezone,
      agreement_version,
      consent_version,
      consented_at,
      stripe_customer_id,
      stripe_setup_intent_id,
      stripe_payment_method_id,
      beta_authorization_version,
      beta_authorized_at
    )
    values (
      'cb200000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'cb210000-0000-0000-0000-000000000001',
      'cb210000-0000-0000-0000-000000000003',
      decode(repeat('42', 32), 'hex'),
      decode(repeat('41', 32), 'hex'),
      'daily',
      10000,
      1000,
      'USD',
      'UTC',
      'personal-stripe-sandbox-v1',
      'personal-stripe-sandbox-consent-v1',
      '2026-07-19T01:00:00Z',
      'cus_CB222222222222222222222222222222',
      'seti_CB22222222222222222222222222222',
      'pm_CB222222222222222222222222222222',
      'personal-stripe-sandbox-beta-v1',
      '2026-07-19T01:30:00Z'
    );

    alter table public.contests
      disable trigger contests_enforce_status_transition;

    update public.contests contest
    set
      status = 'finalized',
      activated_at = '2026-07-20T00:00:00Z'
    where contest.id = 'cb200000-0000-0000-0000-000000000001';

    alter table public.contests
      enable trigger contests_enforce_status_transition;

    insert into app.personal_evidence_assessments (
      id,
      challenge_id,
      user_id,
      request_id,
      evidence_state,
      evidence_cutoff,
      assessment_version,
      evidence_digest,
      full_expected_buckets,
      covered_buckets,
      total_steps,
      daily_totals,
      assessed_at
    )
    values (
      'cb220000-0000-0000-0000-000000000001',
      'cb200000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'cb220000-0000-0000-0000-000000000002',
      'complete',
      '2026-07-28T00:00:00Z',
      'personal-v1',
      decode(repeat('43', 32), 'hex'),
      168,
      168,
      0,
      jsonb_build_array(
        jsonb_build_object('local_date', '2099-01-01', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-02', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-03', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-04', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-05', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-06', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-07', 'total_steps', 0)
      ),
      '2026-07-28T00:30:00Z'
    );

    insert into public.personal_challenge_results (
      id,
      challenge_id,
      user_id,
      assessment_id,
      outcome,
      reason,
      evidence_state,
      evidence_cutoff,
      total_steps,
      daily_totals,
      commitment_waived,
      published_at
    )
    values (
      'cb230000-0000-0000-0000-000000000001',
      'cb200000-0000-0000-0000-000000000001',
      'cb222222-2222-2222-2222-222222222222',
      'cb220000-0000-0000-0000-000000000001',
      'missed_goal',
      'target_missed',
      'complete',
      '2026-07-28T00:00:00Z',
      0,
      jsonb_build_array(
        jsonb_build_object('local_date', '2099-01-01', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-02', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-03', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-04', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-05', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-06', 'total_steps', 0),
        jsonb_build_object('local_date', '2099-01-07', 'total_steps', 0)
      ),
      false,
      '2026-07-28T01:00:00Z'
    );

    update app.personal_stripe_sandbox_payment_reviews review
    set
      opened_at = '2026-07-28T01:00:00Z',
      review_deadline = '2026-08-04T01:00:00Z',
      updated_at = '2026-08-04T01:00:00Z'
    where review.challenge_id =
      'cb200000-0000-0000-0000-000000000001';
  $setup$
);

-- The control session owns a session-local wrapper so both service setters are
-- one atomic transaction and any deadlock is returned as SQLSTATE.
select extensions.dblink_exec(
  'stripe_control_apply',
  $helpers$
    create function pg_temp.apply_stripe_controls_atomically()
    returns jsonb
    language plpgsql
    volatile
    security invoker
    set search_path = ''
    as $function$
    declare
      v_runtime_enabled boolean;
      v_eligible        boolean;
    begin
      v_runtime_enabled :=
        public.set_personal_stripe_sandbox_runtime_v1(
          'cb000000-0000-0000-0000-000000000004',
          false
        );
      v_eligible :=
        public.set_personal_stripe_sandbox_beta_eligibility_v1(
          'cb000000-0000-0000-0000-000000000005',
          'cb111111-1111-1111-1111-111111111111',
          false
        );

      return pg_catalog.jsonb_build_object(
        'runtime_enabled', v_runtime_enabled,
        'eligible', v_eligible
      );
    exception
      when others then
        return pg_catalog.jsonb_build_object('sqlstate', sqlstate);
    end;
    $function$;

    revoke all on function pg_temp.apply_stripe_controls_atomically()
      from public, anon, authenticated, service_role;
    grant execute on function pg_temp.apply_stripe_controls_atomically()
      to service_role;
  $helpers$
);

-- ===========================================================================
-- Race 1: an admitted setup commits before an atomic control shutdown
-- ===========================================================================

select extensions.dblink_exec('stripe_control_setup', 'begin');
select extensions.dblink_exec(
  'stripe_control_setup',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'stripe_control_setup',
  $$ set local "request.jwt.claims" =
       '{"sub":"cb111111-1111-1111-1111-111111111111"}' $$
);

create temporary table t_admitted_setup as
select remote.value
from extensions.dblink(
  'stripe_control_setup',
  $$ select public.begin_personal_stripe_sandbox_setup_v1(
       'cb100000-0000-0000-0000-000000000001',
       'daily',
       10000,
       1000,
       'USD',
       'UTC',
       null,
       'personal-stripe-sandbox-v1',
       'personal-stripe-sandbox-consent-v1'
     ) $$
) as remote(value jsonb);

select ok(
  (
    select
      value ? 'setup_id'
      and value ->> 'replayed' = 'false'
    from t_admitted_setup
  ),
  'the first setup is admitted while runtime and exact eligibility are on'
);

select extensions.dblink_exec('stripe_control_apply', 'begin');
select extensions.dblink_exec(
  'stripe_control_apply',
  'set local role service_role'
);

select is(
  extensions.dblink_send_query(
    'stripe_control_apply',
    $$ select pg_temp.apply_stripe_controls_atomically() $$
  ),
  1,
  'the atomic runtime-off then eligibility-revoke transaction starts'
);

select ok(
  pg_temp.wait_for_stripe_control_block(
    'gametime_stripe_control_apply',
    'gametime_stripe_control_setup'
  ),
  'the control transaction waits for the admitted setup shared control lock'
);

select is(
  extensions.dblink_exec('stripe_control_setup', 'commit'),
  'COMMIT',
  'committing the admitted setup releases its control snapshot'
);

create temporary table t_atomic_controls as
select remote.value
from extensions.dblink_get_result(
  'stripe_control_apply'
) as remote(value jsonb);

-- dblink's async API requires one final empty drain before connection reuse.
select count(*)
from extensions.dblink_get_result(
  'stripe_control_apply'
) as remote(value jsonb);

select is(
  (select value from t_atomic_controls),
  '{"eligible": false, "runtime_enabled": false}'::jsonb,
  'both control changes complete in order without a deadlock'
);

select is(
  extensions.dblink_exec('stripe_control_apply', 'commit'),
  'COMMIT',
  'the runtime and eligibility changes commit atomically'
);

select ok(
  (
    select
      setup_count = 1
      and admitted_setup_count = 1
      and not runtime_enabled
      and not eligible
    from extensions.dblink(
      'stripe_control_setup',
      $$ select
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_setups setup
             where setup.user_id =
               'cb111111-1111-1111-1111-111111111111'
           ),
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_setups setup
             where setup.user_id =
                 'cb111111-1111-1111-1111-111111111111'
               and setup.beta_authorization_version =
                 'personal-stripe-sandbox-beta-v1'
               and setup.beta_authorized_at is not null
           ),
           (
             select runtime.payment_activity_enabled
             from app.personal_stripe_sandbox_runtime runtime
             where runtime.singleton
           ),
           (
             select beta.eligible
             from app.personal_stripe_sandbox_beta_eligibility beta
             where beta.owner_id =
               'cb111111-1111-1111-1111-111111111111'
           ) $$
    ) as state(
      setup_count bigint,
      admitted_setup_count bigint,
      runtime_enabled boolean,
      eligible boolean
    )
  ),
  'the pre-control setup commits with provenance and both later controls are off'
);

select extensions.dblink_exec(
  'stripe_control_setup',
  'set role authenticated'
);
select extensions.dblink_exec(
  'stripe_control_setup',
  $$ set "request.jwt.claims" =
       '{"sub":"cb111111-1111-1111-1111-111111111111"}' $$
);

select is(
  (
    select remote.result
    from extensions.dblink(
      'stripe_control_setup',
      $$ select pg_temp.try_stripe_control_setup(
           'cb100000-0000-0000-0000-000000000002'
         ) $$
    ) as remote(result text)
  ),
  '42501',
  'a new setup request is blocked after the atomic control transaction'
);

select extensions.dblink_exec(
  'stripe_control_setup',
  'reset role'
);

select is(
  (
    select count(*)::bigint
    from extensions.dblink(
      'stripe_control_setup',
      $$ select setup.id
         from app.personal_stripe_sandbox_setups setup
         where setup.user_id =
           'cb111111-1111-1111-1111-111111111111' $$
    ) as remote(id uuid)
  ),
  1::bigint,
  'the blocked post-control request persists no second setup'
);

-- ===========================================================================
-- Race 2: account deletion commits before charge discovery
-- ===========================================================================

select is(
  (
    select remote.enabled
    from extensions.dblink(
      'stripe_control_setup',
      $$ select public.set_personal_stripe_sandbox_runtime_v1(
           'cb000000-0000-0000-0000-000000000006',
           true
         ) $$
    ) as remote(enabled boolean)
  ),
  true,
  'payment activity is re-enabled for the independent deletion race'
);

select extensions.dblink_exec('stripe_control_delete', 'begin');
select extensions.dblink_exec(
  'stripe_control_delete',
  'set local role service_role'
);

select is(
  extensions.dblink_exec(
    'stripe_control_delete',
    $$ do $block$
       begin
         perform public.delete_account(
           'cb222222-2222-2222-2222-222222222222'
         );
       end;
       $block$ $$
  ),
  'DO',
  'account deletion reaches its uncommitted tombstone while retaining locks'
);

select extensions.dblink_exec(
  'stripe_control_claim',
  'set role service_role'
);

select is(
  extensions.dblink_send_query(
    'stripe_control_claim',
    $$ select public.claim_personal_stripe_sandbox_charges_v1(
         'cb900000-0000-0000-0000-000000000001',
         10
       ) $$
  ),
  1,
  'the charge worker starts while account deletion is uncommitted'
);

select ok(
  pg_temp.wait_for_stripe_control_block(
    'gametime_stripe_control_claim',
    'gametime_stripe_control_delete'
  ),
  'the charge worker waits on the deleting owner profile serialization lock'
);

select is(
  extensions.dblink_exec('stripe_control_delete', 'commit'),
  'COMMIT',
  'committing deletion releases the owner profile lock'
);

create temporary table t_post_delete_claim as
select remote.value
from extensions.dblink_get_result(
  'stripe_control_claim'
) as remote(value jsonb);

select count(*)
from extensions.dblink_get_result(
  'stripe_control_claim'
) as remote(value jsonb);

select is(
  (select value from t_post_delete_claim),
  '[]'::jsonb,
  'the waiting claim rechecks the committed tombstone and returns no work'
);

select ok(
  (
    select
      profile_deleted
      and not auth_exists
      and review_state = 'review_open'
      and command_count = 0
      and leased_or_attempted_count = 0
    from extensions.dblink(
      'stripe_control_setup',
      $$ select
           (
             select profile.deleted_at is not null
             from public.profiles profile
             where profile.id =
               'cb222222-2222-2222-2222-222222222222'
           ),
           exists (
             select 1
             from auth.users auth_user
             where auth_user.id =
               'cb222222-2222-2222-2222-222222222222'
           ),
           (
             select review.state
             from app.personal_stripe_sandbox_payment_reviews review
             where review.challenge_id =
               'cb200000-0000-0000-0000-000000000001'
           ),
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_charge_commands command
             where command.user_id =
               'cb222222-2222-2222-2222-222222222222'
           ),
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_charge_commands command
             where command.user_id =
                 'cb222222-2222-2222-2222-222222222222'
               and (
                 command.attempt_count > 0
                 or command.lease_owner is not null
                 or command.lease_expires_at is not null
               )
           ) $$
    ) as state(
      profile_deleted boolean,
      auth_exists boolean,
      review_state text,
      command_count bigint,
      leased_or_attempted_count bigint
    )
  ),
  'deletion wins atomically: the review stays provisional and no command is created or leased'
);

select extensions.dblink_exec(
  'stripe_control_claim',
  'reset role'
);

-- dblink fixtures commit outside this test transaction. Remove only these
-- unique rows and restore the fail-closed runtime seed.
select extensions.dblink_exec(
  'stripe_control_setup',
  $cleanup$
    set session_replication_role = replica;

    delete from public.notification_intents
    where recipient_user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    )
       or entity_id = 'cb200000-0000-0000-0000-000000000001';

    delete from app.account_deletion_participant_events
    where actor_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.account_capabilities
    where actor_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_stripe_sandbox_webhook_receipts
    where charge_command_id in (
      select command.id
      from app.personal_stripe_sandbox_charge_commands command
      where command.user_id in (
        'cb111111-1111-1111-1111-111111111111',
        'cb222222-2222-2222-2222-222222222222'
      )
    );

    delete from app.personal_stripe_sandbox_charge_commands
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_stripe_sandbox_payment_reviews
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from public.personal_challenge_results
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_evidence_assessments
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_stripe_sandbox_agreements
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_stripe_sandbox_setups
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.personal_stripe_sandbox_customers
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from public.personal_challenge_terms
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from public.contest_participants
    where user_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.retention_holds
    where scope_id = 'cb200000-0000-0000-0000-000000000001';

    delete from app.workflow_scope_actors
    where scope_id = 'cb200000-0000-0000-0000-000000000001'
       or actor_id in (
         'cb111111-1111-1111-1111-111111111111',
         'cb222222-2222-2222-2222-222222222222'
       );

    delete from app.workflow_scopes
    where scope_id = 'cb200000-0000-0000-0000-000000000001';

    delete from public.contests
    where id = 'cb200000-0000-0000-0000-000000000001';

    delete from app.personal_stripe_sandbox_control_requests
    where request_id in (
      'cb000000-0000-0000-0000-000000000001',
      'cb000000-0000-0000-0000-000000000002',
      'cb000000-0000-0000-0000-000000000003',
      'cb000000-0000-0000-0000-000000000004',
      'cb000000-0000-0000-0000-000000000005',
      'cb000000-0000-0000-0000-000000000006'
    );

    delete from app.personal_stripe_sandbox_beta_eligibility
    where owner_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    update app.personal_stripe_sandbox_runtime
    set
      payment_activity_enabled = false,
      updated_at = clock_timestamp()
    where singleton;

    delete from app.account_deletion_transactions
    where actor_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.profile_handle_claims
    where actor_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from app.active_profile_auth_bindings
    where actor_id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from public.profiles
    where id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    delete from auth.users
    where id in (
      'cb111111-1111-1111-1111-111111111111',
      'cb222222-2222-2222-2222-222222222222'
    );

    set session_replication_role = origin;
  $cleanup$
);

select ok(
  (
    select
      not runtime_enabled
      and user_count = 0
      and setup_count = 0
      and command_count = 0
    from extensions.dblink(
      'stripe_control_setup',
      $$ select
           (
             select runtime.payment_activity_enabled
             from app.personal_stripe_sandbox_runtime runtime
             where runtime.singleton
           ),
           (
             select count(*)::bigint
             from public.profiles profile
             where profile.id in (
               'cb111111-1111-1111-1111-111111111111',
               'cb222222-2222-2222-2222-222222222222'
             )
           ),
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_setups setup
             where setup.user_id in (
               'cb111111-1111-1111-1111-111111111111',
               'cb222222-2222-2222-2222-222222222222'
             )
           ),
           (
             select count(*)::bigint
             from app.personal_stripe_sandbox_charge_commands command
             where command.user_id in (
               'cb111111-1111-1111-1111-111111111111',
               'cb222222-2222-2222-2222-222222222222'
             )
           ) $$
    ) as state(
      runtime_enabled boolean,
      user_count bigint,
      setup_count bigint,
      command_count bigint
    )
  ),
  'committed concurrency fixtures are removed and runtime is restored off'
);

select is(
  extensions.dblink_disconnect('stripe_control_claim'),
  'OK',
  'the charge-claim session disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('stripe_control_delete'),
  'OK',
  'the deletion session disconnects cleanly'
);
select is(
  extensions.dblink_disconnect('stripe_control_apply'),
  'OK',
  'the atomic-control session disconnects cleanly'
);
select extensions.dblink_disconnect('stripe_control_setup');

select * from finish();
rollback;
