-- M7 / D81: authentication deletion pseudonymizes a durable actor, resolves
-- only transitionable work, returns hash-only scoped capabilities once, and
-- leaves raw evidence to a separate guarded retention worker.

begin;
select plan(71);

set local timezone = 'UTC';

-- ---------------------------------------------------------------------------
-- Schema, durable references, and least privilege
-- ---------------------------------------------------------------------------

select has_column(
  'public',
  'profiles',
  'deleted_at',
  'profiles carry an explicit account-deletion tombstone timestamp'
);
select has_type(
  'public',
  'account_capability_scope_kind',
  'deleted-account capabilities use a closed scope vocabulary'
);
select set_eq(
  $$ select enum_value.enumlabel::text
     from pg_catalog.pg_enum enum_value
     join pg_catalog.pg_type enum_type
       on enum_type.oid = enum_value.enumtypid
     join pg_catalog.pg_namespace enum_schema
       on enum_schema.oid = enum_type.typnamespace
     where enum_schema.nspname = 'public'
       and enum_type.typname = 'account_capability_scope_kind' $$,
  array['contest_lineage', 'case'],
  'capabilities are limited to contest lineages and standalone cases'
);
select ok(
  to_regclass('app.account_deletion_secrets') is not null
  and to_regclass('app.account_deletion_transactions') is not null
  and to_regclass('app.account_deletion_participant_events') is not null
  and to_regclass('app.profile_handle_claims') is not null
  and to_regclass('app.active_profile_auth_bindings') is not null
  and to_regclass('app.retention_policy_versions') is not null
  and to_regclass('app.raw_evidence_retention_rules') is not null
  and to_regclass('app.workflow_scopes') is not null
  and to_regclass('app.workflow_scope_actors') is not null
  and to_regclass('app.retention_holds') is not null
  and to_regclass('app.account_capabilities') is not null
  and to_regclass('app.raw_evidence_retention_events') is not null
  and to_regclass('app.device_receipt_retention_summaries') is not null,
  'private deletion, capability, and retention state all exist'
);
select set_eq(
  $$ select rule.evidence_kind || ':' || rule.retain_for::text
     from app.raw_evidence_retention_rules rule
     where rule.policy_version = 'raw-evidence-retention-v1' $$,
  array[
    'app_attest_receipt:90 days',
    'device_registration:90 days',
    'donation_receipt:90 days',
    'exact_location:30 days',
    'metric_observation:90 days'
  ],
  'the launch retention policy is versioned with its D81 intervals'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid =
          'public.contest_participants'::regclass
      and constraint_row.conname = 'contest_participants_user_id_fkey'
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.confdeltype = 'r'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid = 'public.device_attestations'::regclass
      and constraint_row.conname = 'device_attestations_user_id_fkey'
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.confdeltype = 'r'
  )
  and not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where (
      constraint_row.conrelid = 'public.ingest_batches'::regclass
      and constraint_row.conname = 'ingest_batches_key_id_fkey'
    )
    or (
      constraint_row.conrelid = 'public.geofence_checkins'::regclass
      and constraint_row.conname = 'geofence_checkins_key_id_fkey'
    )
    or (
      constraint_row.conrelid =
        'app.device_attestation_receipts'::regclass
      and constraint_row.conname =
        'device_attestation_receipts_key_id_fkey'
    )
    or (
      constraint_row.conrelid = 'public.evidence_quarantines'::regclass
      and constraint_row.conname =
        'evidence_quarantines_snapshot_id_fkey'
    )
  ),
  'auth, device, snapshot, and roster cascades cannot erase durable facts'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_policy policy
    where not policy.polpermissive
      and (
        policy.polname = 'profiles_active_actor_only'
        or policy.polname = 'active_actor_only'
      )
  ),
  20::bigint,
  'every authenticated public table composes a restrictive active-actor policy'
);
select ok(
  not exists (
    select 1
    from (
      values
        ('app.account_deletion_secrets'),
        ('app.account_deletion_transactions'),
        ('app.account_deletion_participant_events'),
        ('app.profile_handle_claims'),
        ('app.active_profile_auth_bindings'),
        ('app.retention_policy_versions'),
        ('app.raw_evidence_retention_rules'),
        ('app.workflow_scopes'),
        ('app.workflow_scope_actors'),
        ('app.retention_holds'),
        ('app.account_capabilities'),
        ('app.raw_evidence_retention_events'),
        ('app.device_receipt_retention_summaries')
    ) private_table(relation_name)
    cross join (
      values ('anon'), ('authenticated'), ('service_role')
    ) application_role(role_name)
    cross join (
      values ('select'), ('insert'), ('update'), ('delete')
    ) table_privilege(privilege_name)
    where has_table_privilege(
      application_role.role_name,
      private_table.relation_name,
      table_privilege.privilege_name
    )
  ),
  'private deletion and retention tables grant no direct application access'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.delete_account(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.delete_account(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.delete_account(uuid)',
    'execute'
  ),
  'only service_role can invoke atomic account deletion'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.set_workflow_retention_state(public.account_capability_scope_kind,uuid,boolean,timestamptz,timestamptz,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'public.create_retention_hold(public.account_capability_scope_kind,uuid,text,timestamptz)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'app.run_raw_evidence_retention(timestamptz,integer)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.set_workflow_retention_state(public.account_capability_scope_kind,uuid,boolean,timestamptz,timestamptz,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_retention_hold(public.account_capability_scope_kind,uuid,text,timestamptz)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.run_raw_evidence_retention(timestamptz,integer)',
    'execute'
  ),
  'retention state, holds, and pruning are service-only APIs'
);
select ok(
  has_column_privilege(
    'authenticated',
    'public.profiles',
    'display_name',
    'update'
  )
  and not has_column_privilege(
    'authenticated',
    'public.profiles',
    'deleted_at',
    'insert'
  )
  and not has_column_privilege(
    'authenticated',
    'public.profiles',
    'deleted_at',
    'update'
  )
  and not has_function_privilege(
    'service_role',
    'app.deleted_handle_digest(text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'app.authorize_account_capability(text,public.account_capability_scope_kind,uuid,timestamptz)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.is_account_deletion_transaction(uuid)',
    'execute'
  ),
  'clients cannot tombstone profiles or invoke private HMAC/capability helpers'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid =
          'public.contest_participants'::regclass
      and trigger_row.tgname =
          'contest_participants_01_lock_pending_contests'
      and not trigger_row.tgisinternal
      and trigger_row.tgenabled <> 'D'
  )
  and has_function_privilege(
    'authenticated',
    'app.lock_caller_pending_contests()',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'app.lock_caller_pending_contests()',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'app.lock_participant_pending_contests()',
    'execute'
  ),
  'participant acceptance uses the narrow contest-first locking boundary'
);
select is(
  (
    select count(*)
    from cron.job
    where jobname = 'gametime-prune-raw-evidence'
      and schedule = '17 * * * *'
      and command = 'select app.run_raw_evidence_retention();'
  ),
  1::bigint,
  'one named hourly cron entry invokes the guarded retention worker'
);

-- ---------------------------------------------------------------------------
-- Fixed actors and contest lifecycle fixtures
-- ---------------------------------------------------------------------------

create temporary table t_clock as
select
  transaction_timestamp() as t0,
  transaction_timestamp() - interval '80 days' as terminal_at,
  transaction_timestamp() + interval '20 days' as hold_until,
  transaction_timestamp() + interval '100 days' as worker_at;
grant select on t_clock to service_role;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), -- departing actor
  ('22222222-2222-2222-2222-222222222222'), -- surviving creator/rival
  ('33333333-3333-3333-3333-333333333333'), -- surviving invitee/rival
  ('44444444-4444-4444-4444-444444444444'), -- active-device owner
  ('55555555-5555-5555-5555-555555555555'); -- attempted handle reuser

insert into public.profiles (
  id,
  handle,
  display_name,
  avatar_path,
  timezone
) values
  (
    '11111111-1111-1111-1111-111111111111',
    'departing_81',
    'Departing Member',
    'avatars/departing.png',
    'America/Los_Angeles'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'survivor_81',
    'Survivor',
    null,
    'UTC'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'invitee_81',
    'Invitee',
    null,
    'UTC'
  ),
  (
    '44444444-4444-4444-4444-444444444444',
    'device_owner_81',
    'Device Owner',
    null,
    'UTC'
  );

insert into public.charities (id, name, ein, slug) values (
  'c0000001-0000-0000-0000-000000000001',
  'D81 Test Fund',
  '12-3456789',
  'd81-test-fund'
);

insert into public.friendships (
  user_a,
  user_b,
  requested_by,
  status
) values (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'accepted'
);

insert into public.blocks (blocker_id, blocked_id) values (
  '11111111-1111-1111-1111-111111111111',
  '33333333-3333-3333-3333-333333333333'
);

insert into public.groups (id, name, join_code, created_by) values (
  '60000001-0000-0000-0000-000000000001',
  'D81 Survivors',
  'ABCDEFGH',
  '22222222-2222-2222-2222-222222222222'
);
insert into public.group_members (group_id, user_id) values (
  '60000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111'
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
    'a0000001-0000-0000-0000-000000000001',
    'Retained active lineage',
    '22222222-2222-2222-2222-222222222222',
    'steps',
    'cumulative',
    10000,
    2500,
    date_trunc('hour', transaction_timestamp()) - interval '10 days',
    date_trunc('hour', transaction_timestamp()) + interval '10 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    'Departing author pending',
    '11111111-1111-1111-1111-111111111111',
    'steps',
    'cumulative',
    10000,
    2500,
    date_trunc('hour', transaction_timestamp()) + interval '20 days',
    date_trunc('hour', transaction_timestamp()) + interval '30 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000003',
    'Other pending accepted',
    '22222222-2222-2222-2222-222222222222',
    'steps',
    'cumulative',
    10000,
    2500,
    date_trunc('hour', transaction_timestamp()) + interval '20 days',
    date_trunc('hour', transaction_timestamp()) + interval '30 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000004',
    'Other pending unanswered',
    '22222222-2222-2222-2222-222222222222',
    'steps',
    'cumulative',
    10000,
    2500,
    date_trunc('hour', transaction_timestamp()) + interval '20 days',
    date_trunc('hour', transaction_timestamp()) + interval '30 days',
    4
  ),
  (
    'a0000001-0000-0000-0000-000000000005',
    'Open retention control',
    '22222222-2222-2222-2222-222222222222',
    'steps',
    'cumulative',
    10000,
    2500,
    date_trunc('hour', transaction_timestamp()) - interval '10 days',
    date_trunc('hour', transaction_timestamp()) + interval '10 days',
    4
  );

alter table public.contests enable trigger contests_assert_future_window;

insert into public.contest_participants (
  contest_id,
  user_id,
  status,
  invited_by,
  timezone,
  charity_id
) values
  (
    'a0000001-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222',
    'accepted',
    null,
    'UTC',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'invited',
    '22222222-2222-2222-2222-222222222222',
    null,
    null
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'accepted',
    null,
    'America/Los_Angeles',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000002',
    '33333333-3333-3333-3333-333333333333',
    'invited',
    '11111111-1111-1111-1111-111111111111',
    null,
    null
  ),
  (
    'a0000001-0000-0000-0000-000000000003',
    '22222222-2222-2222-2222-222222222222',
    'accepted',
    null,
    'UTC',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'invited',
    '22222222-2222-2222-2222-222222222222',
    null,
    null
  ),
  (
    'a0000001-0000-0000-0000-000000000004',
    '22222222-2222-2222-2222-222222222222',
    'accepted',
    null,
    'UTC',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'invited',
    '22222222-2222-2222-2222-222222222222',
    null,
    null
  ),
  (
    'a0000001-0000-0000-0000-000000000005',
    '22222222-2222-2222-2222-222222222222',
    'accepted',
    null,
    'UTC',
    'c0000001-0000-0000-0000-000000000001'
  ),
  (
    'a0000001-0000-0000-0000-000000000005',
    '33333333-3333-3333-3333-333333333333',
    'invited',
    '22222222-2222-2222-2222-222222222222',
    null,
    null
  );

update public.contest_participants
set status = 'accepted',
    timezone = case user_id
      when '11111111-1111-1111-1111-111111111111'::uuid
        then 'America/Los_Angeles'
      else 'UTC'
    end,
    charity_id = 'c0000001-0000-0000-0000-000000000001'
where (contest_id, user_id) in (
  (
    'a0000001-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
  ),
  (
    'a0000001-0000-0000-0000-000000000003'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
  )
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
with updated as (
  update public.contest_participants
  set status = 'accepted',
      timezone = 'UTC',
      charity_id = 'c0000001-0000-0000-0000-000000000001'
  where contest_id = 'a0000001-0000-0000-0000-000000000005'
    and user_id = '33333333-3333-3333-3333-333333333333'
  returning 1
)
select is(
  (select count(*) from updated),
  1::bigint,
  'ordinary authenticated acceptance crosses the contest-first trigger without private-marker privileges'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

insert into public.contest_geofences (
  id,
  contest_id,
  name,
  center_latitude,
  center_longitude,
  radius_meters,
  max_accuracy_meters,
  minimum_dwell_seconds,
  maximum_sample_gap_seconds,
  minimum_workout_overlap_seconds
) values
  (
    'f0000001-0000-0000-0000-000000000001',
    'a0000001-0000-0000-0000-000000000001',
    'D81 retained venue',
    0,
    0,
    200,
    20,
    60,
    60,
    30
  ),
  (
    'f0000001-0000-0000-0000-000000000005',
    'a0000001-0000-0000-0000-000000000005',
    'D81 open control venue',
    0,
    0,
    200,
    20,
    60,
    60,
    30
  );

update public.contests
set status = 'active',
    activated_at = transaction_timestamp()
where id in (
  'a0000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000005'
);

create temporary table t_keys as
select
  departing_public_key,
  extensions.digest(departing_public_key, 'sha256') as departing_key_id,
  active_public_key,
  extensions.digest(active_public_key, 'sha256') as active_key_id
from (
  values (
    pg_catalog.decode(
      '04' || pg_catalog.repeat('11', 64),
      'hex'
    ),
    pg_catalog.decode(
      '04' || pg_catalog.repeat('22', 64),
      'hex'
    )
  )
) key_bytes(departing_public_key, active_public_key);

insert into public.device_attestations (
  key_id,
  user_id,
  public_key,
  environment,
  sign_count,
  attested_at,
  updated_at
)
select
  departing_key_id,
  '11111111-1111-1111-1111-111111111111'::uuid,
  departing_public_key,
  'production'::public.attestation_environment,
  7,
  (select t0 - interval '200 days' from t_clock),
  (select t0 - interval '200 days' from t_clock)
from t_keys
union all
select
  active_key_id,
  '44444444-4444-4444-4444-444444444444'::uuid,
  active_public_key,
  'production'::public.attestation_environment,
  0,
  (select t0 - interval '200 days' from t_clock),
  (select t0 - interval '200 days' from t_clock)
from t_keys;

insert into app.device_attestation_receipts (
  key_id,
  initial_receipt,
  current_receipt,
  received_at
)
select
  departing_key_id,
  pg_catalog.decode('a101', 'hex'),
  pg_catalog.decode('a102', 'hex'),
  (select t0 - interval '200 days' from t_clock)
from t_keys
union all
select
  active_key_id,
  pg_catalog.decode('b201', 'hex'),
  pg_catalog.decode('b202', 'hex'),
  (select t0 - interval '200 days' from t_clock)
from t_keys;

insert into public.ingest_batches (
  id,
  contest_id,
  user_id,
  client_batch_id,
  key_id,
  sign_count,
  attested,
  payload_digest,
  observation_count,
  observed_at,
  recorded_at
)
select
  'b1000001-0000-0000-0000-000000000001'::uuid,
  'a0000001-0000-0000-0000-000000000001'::uuid,
  '11111111-1111-1111-1111-111111111111'::uuid,
  'c1000001-0000-0000-0000-000000000001'::uuid,
  departing_key_id,
  7,
  true,
  extensions.digest('d81-retained-batch', 'sha256'),
  1,
  (select t0 - interval '5 days' from t_clock),
  (select t0 from t_clock)
from t_keys
union all
select
  'b1000001-0000-0000-0000-000000000005'::uuid,
  'a0000001-0000-0000-0000-000000000005'::uuid,
  '22222222-2222-2222-2222-222222222222'::uuid,
  'c1000001-0000-0000-0000-000000000005'::uuid,
  null,
  null,
  false,
  extensions.digest('d81-open-control-batch', 'sha256'),
  1,
  (select t0 - interval '5 days' from t_clock),
  (select t0 from t_clock)
from t_keys;

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
  source_bundle_id,
  device_model,
  observed_at,
  recorded_at
) values
  (
    'b2000001-0000-0000-0000-000000000001',
    'b1000001-0000-0000-0000-000000000001',
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'steps',
    date_trunc('hour', transaction_timestamp()) - interval '5 days',
    current_date,
    0,
    12000,
    'device',
    20,
    'com.apple.health',
    'Watch-retained',
    (select t0 - interval '5 days' from t_clock),
    (select t0 from t_clock)
  ),
  (
    'b2000001-0000-0000-0000-000000000005',
    'b1000001-0000-0000-0000-000000000005',
    'a0000001-0000-0000-0000-000000000005',
    '22222222-2222-2222-2222-222222222222',
    'steps',
    date_trunc('hour', transaction_timestamp()) - interval '5 days',
    current_date,
    0,
    9000,
    'device',
    10,
    'com.apple.health',
    'Watch-open-control',
    (select t0 - interval '5 days' from t_clock),
    (select t0 from t_clock)
  );

insert into public.evidence_quarantines (
  id,
  snapshot_id,
  contest_id,
  user_id,
  metric,
  bucket_start,
  rule_version,
  signal_key,
  threshold_ms,
  reporting_lag_ms,
  details
) values (
  'b3000001-0000-0000-0000-000000000001',
  'b2000001-0000-0000-0000-000000000001',
  'a0000001-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'steps',
  date_trunc('hour', transaction_timestamp()) - interval '5 days',
  'd81-test-v1',
  'd81-retained-snapshot',
  1000,
  1000,
  '{"fixture":"D81"}'
);

insert into public.geofence_checkins (
  id,
  contest_id,
  geofence_id,
  user_id,
  client_checkin_id,
  key_id,
  sign_count,
  attested,
  payload_digest,
  started_at,
  ended_at,
  workout_id,
  workout_started_at,
  workout_ended_at,
  workout_activity_type,
  workout_source_bundle_id,
  workout_provenance,
  location_count,
  inside_location_count,
  dwell_seconds,
  workout_overlap_seconds,
  outcome,
  rule_version,
  recorded_at
)
select
  'e1000001-0000-0000-0000-000000000001'::uuid,
  'a0000001-0000-0000-0000-000000000001'::uuid,
  'f0000001-0000-0000-0000-000000000001'::uuid,
  '11111111-1111-1111-1111-111111111111'::uuid,
  'c2000001-0000-0000-0000-000000000001'::uuid,
  departing_key_id,
  7,
  true,
  extensions.digest('d81-retained-checkin', 'sha256'),
  (select t0 - interval '4 days' from t_clock),
  (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
  'd1000001-0000-0000-0000-000000000001'::uuid,
  (select t0 - interval '4 days' from t_clock),
  (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
  'running',
  'com.apple.health.retained',
  'device'::public.metric_provenance,
  2,
  2,
  60,
  30,
  'accepted'::public.geofence_checkin_outcome,
  'd81-test-v1',
  (select t0 - interval '4 days' from t_clock)
from t_keys
union all
select
  'e1000001-0000-0000-0000-000000000005'::uuid,
  'a0000001-0000-0000-0000-000000000005'::uuid,
  'f0000001-0000-0000-0000-000000000005'::uuid,
  '22222222-2222-2222-2222-222222222222'::uuid,
  'c2000001-0000-0000-0000-000000000005'::uuid,
  null,
  null,
  false,
  extensions.digest('d81-open-control-checkin', 'sha256'),
  (select t0 - interval '4 days' from t_clock),
  (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
  'd1000001-0000-0000-0000-000000000005'::uuid,
  (select t0 - interval '4 days' from t_clock),
  (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
  'running',
  'com.apple.health.open',
  'device'::public.metric_provenance,
  2,
  2,
  60,
  30,
  'accepted'::public.geofence_checkin_outcome,
  'd81-test-v1',
  (select t0 - interval '4 days' from t_clock)
from t_keys;

insert into public.geofence_location_observations (
  id,
  checkin_id,
  contest_id,
  user_id,
  sample_index,
  observed_at,
  latitude,
  longitude,
  accuracy_meters,
  is_simulated,
  is_produced_by_accessory,
  distance_meters,
  outcome,
  created_at
) values
  (
    'e2000001-0000-0000-0000-000000000001',
    'e1000001-0000-0000-0000-000000000001',
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    1,
    (select t0 - interval '4 days' from t_clock),
    0,
    0,
    5,
    false,
    false,
    0,
    'inside',
    (select t0 - interval '4 days' from t_clock)
  ),
  (
    'e2000001-0000-0000-0000-000000000002',
    'e1000001-0000-0000-0000-000000000001',
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    2,
    (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
    0,
    0,
    5,
    false,
    false,
    0,
    'inside',
    (select t0 - interval '4 days' from t_clock)
  ),
  (
    'e2000001-0000-0000-0000-000000000005',
    'e1000001-0000-0000-0000-000000000005',
    'a0000001-0000-0000-0000-000000000005',
    '22222222-2222-2222-2222-222222222222',
    1,
    (select t0 - interval '4 days' from t_clock),
    0,
    0,
    5,
    false,
    false,
    0,
    'inside',
    (select t0 - interval '4 days' from t_clock)
  ),
  (
    'e2000001-0000-0000-0000-000000000006',
    'e1000001-0000-0000-0000-000000000005',
    'a0000001-0000-0000-0000-000000000005',
    '22222222-2222-2222-2222-222222222222',
    2,
    (select t0 - interval '4 days' + interval '60 seconds' from t_clock),
    0,
    0,
    5,
    false,
    false,
    0,
    'inside',
    (select t0 - interval '4 days' from t_clock)
  );

-- ---------------------------------------------------------------------------
-- Guarded auth deletion and the one atomic service transaction
-- ---------------------------------------------------------------------------

select set_config(
  'app.account_deletion_actor',
  '11111111-1111-1111-1111-111111111111',
  true
);
select throws_ok(
  $$ update public.profiles
     set handle = 'deleted-00000000000000000000',
         display_name = 'Deleted member',
         avatar_path = null,
         timezone = 'UTC',
         deleted_at = clock_timestamp()
     where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501',
  null,
  'a caller-set deletion GUC cannot forge the private transaction marker'
);
select set_config('app.account_deletion_actor', '', true);

select throws_ok(
  $$ delete from auth.users
     where id = '11111111-1111-1111-1111-111111111111' $$,
  '23001',
  null,
  'direct Auth deletion refuses an onboarded active account'
);
select ok(
  exists (
    select 1
    from auth.users
    where id = '11111111-1111-1111-1111-111111111111'
  )
  and exists (
    select 1
    from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
      and deleted_at is null
  ),
  'the refused direct delete leaves both auth and profile live'
);

create temporary table t_delete_result (result jsonb not null);
grant insert on t_delete_result to service_role;

set local role service_role;
insert into t_delete_result (result)
select public.delete_account(
  '11111111-1111-1111-1111-111111111111'
);
reset role;

select set_config(
  'd81.tombstone_handle',
  (
    select profile.handle::text
    from public.profiles profile
    where profile.id = '11111111-1111-1111-1111-111111111111'
  ),
  true
);

select ok(
  (
    select
      profile.deleted_at is not null
      and profile.deleted_at =
        (deletion.result ->> 'deletedAt')::timestamptz
      and profile.handle::text ~ '^deleted-[0-9a-f]{20}$'
      and profile.handle::text <>
        'deleted-' || left(
          replace(profile.id::text, '-', ''),
          20
        )
      and profile.display_name = 'Deleted member'
      and profile.avatar_path is null
      and profile.timezone = 'UTC'
    from public.profiles profile
    cross join t_delete_result deletion
    where profile.id = '11111111-1111-1111-1111-111111111111'
  ),
  'service deletion leaves only the random public tombstone shape'
);
select ok(
  not exists (
    select 1
    from auth.users
    where id = '11111111-1111-1111-1111-111111111111'
  )
  and not exists (
    select 1
    from app.active_profile_auth_bindings
    where actor_id = '11111111-1111-1111-1111-111111111111'
  )
  and not exists (
    select 1
    from app.account_deletion_transactions
  ),
  'the same transaction removes auth, the live binding, and its private marker'
);
select ok(
  (
    select
      octet_length(claim.handle_digest) = 32
      and claim.handle_digest =
        app.deleted_handle_digest('DEPARTING_81')
      and claim.handle_digest <>
        extensions.digest(
          pg_catalog.convert_to('departing_81', 'UTF8'),
          'sha256'
        )
      and claim.retained_at = (
        select profile.deleted_at
        from public.profiles profile
        where profile.id = claim.actor_id
      )
    from app.profile_handle_claims claim
    where claim.actor_id =
      '11111111-1111-1111-1111-111111111111'
      and claim.retained_at is not null
  )
  and not exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'app'
      and column_row.table_name = 'profile_handle_claims'
      and column_row.column_name in ('handle', 'normalized_handle')
  ),
  'the former handle survives only as a private keyed HMAC reservation'
);
select throws_ok(
  $$ insert into auth.users (id)
     values ('11111111-1111-1111-1111-111111111111') $$,
  '23505',
  null,
  'a deleted durable actor UUID can never be registered in Auth again'
);
select throws_ok(
  $$ update auth.users
     set id = '11111111-1111-1111-1111-111111111111'
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '23001',
  null,
  'Auth actor UUIDs cannot be reassigned through UPDATE'
);
select throws_ok(
  $$ insert into public.profiles (id, handle, display_name)
     values (
       '55555555-5555-5555-5555-555555555555',
       'DePaRtInG_81',
       'Impersonator'
     ) $$,
  '23505',
  null,
  'the normalized former handle cannot be claimed again'
);

set local role service_role;
select throws_ok(
  $$ select public.delete_account(
       '11111111-1111-1111-1111-111111111111'
     ) $$,
  '42501',
  null,
  'account deletion cannot replay the one-time capability response'
);
reset role;

select ok(
  not exists (
    select 1
    from public.friendships
    where '11111111-1111-1111-1111-111111111111' in (user_a, user_b)
  )
  and not exists (
    select 1
    from public.blocks
    where '11111111-1111-1111-1111-111111111111'
      in (blocker_id, blocked_id)
  )
  and not exists (
    select 1
    from public.group_members
    where user_id = '11111111-1111-1111-1111-111111111111'
  )
  and exists (
    select 1
    from public.groups
    where id = '60000001-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.group_members
    where group_id = '60000001-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'
  ),
  'friendships, blocks, and only the departing group membership are removed'
);
select ok(
  (
    select
      status = 'cancelled'
      and cancellation_reason = 'creator_cancelled'
      and cancelled_at is not null
    from public.contests
    where id = 'a0000001-0000-0000-0000-000000000002'
  ),
  'a pending contest authored by the departing actor is cancelled'
);
select is(
  (
    select status
    from public.contest_participants
    where contest_id = 'a0000001-0000-0000-0000-000000000002'
      and user_id = '33333333-3333-3333-3333-333333333333'
  ),
  'lapsed'::public.contest_participant_status,
  'the authored contest lapses its unanswered invitation'
);
select ok(
  (
    select status = 'withdrawn'
    from public.contest_participants
    where contest_id = 'a0000001-0000-0000-0000-000000000003'
      and user_id = '11111111-1111-1111-1111-111111111111'
  )
  and (
    select status = 'lapsed'
    from public.contest_participants
    where contest_id = 'a0000001-0000-0000-0000-000000000004'
      and user_id = '11111111-1111-1111-1111-111111111111'
  ),
  'other pending contests distinguish accepted withdrawal from silence'
);
select ok(
  (
    select
      count(*) = 2
      and array_agg(
        event.from_status::text || '>' || event.to_status::text
        order by event.from_status::text
      ) = array['accepted>withdrawn', 'invited>lapsed']
      and bool_and(event.reason = 'account_deleted')
      and bool_and(event.actor_id =
        '11111111-1111-1111-1111-111111111111'::uuid)
    from app.account_deletion_participant_events event
  )
  and (
    select count(*) = 2
    from public.notification_intents intent
    join app.account_deletion_participant_events event
      on event.id = intent.entity_id
    where intent.event_type = 'contest_participation_changed'
      and intent.recipient_user_id =
          '22222222-2222-2222-2222-222222222222'
  ),
  'both account-deletion departures commit immutable D80 intents for the creator'
);
select throws_ok(
  $$ update app.account_deletion_participant_events
     set reason = 'rewritten' $$,
  '23001',
  null,
  'account-deletion participation events are immutable'
);
select set_eq(
  $$ select intent.recipient_user_id
     from public.notification_intents intent
     where intent.event_type = 'contest_cancelled'
       and intent.entity_id =
         'a0000001-0000-0000-0000-000000000002'::uuid $$,
  array[
    '11111111-1111-1111-1111-111111111111'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid
  ],
  'the cancellation and its recipient outbox rows commit with deletion'
);

create temporary table t_account_deletion_participant_events as
select event.id
from app.account_deletion_participant_events event
where event.actor_id = '11111111-1111-1111-1111-111111111111';
grant select on t_account_deletion_participant_events to authenticated;

select ok(
  (
    select
      jsonb_array_length(deletion.result -> 'capabilities') = 1
      and deletion.result -> 'capabilities' -> 0 ->> 'kind' =
          'contest_lineage'
      and (
        deletion.result -> 'capabilities' -> 0 ->> 'scopeId'
      )::uuid = 'a0000001-0000-0000-0000-000000000001'::uuid
    from t_delete_result deletion
  ),
  'deletion returns one capability for the retained active lineage'
);
select ok(
  (
    select deletion.result -> 'capabilities' -> 0 ->> 'secret'
           ~ '^gtcap1_[0-9a-f]{64}$'
    from t_delete_result deletion
  )
  and (
    select capability.secret_hash =
      extensions.digest(
        pg_catalog.convert_to(
          deletion.result -> 'capabilities' -> 0 ->> 'secret',
          'UTF8'
        ),
        'sha256'
      )
    from app.account_capabilities capability
    cross join t_delete_result deletion
    where capability.actor_id =
      '11111111-1111-1111-1111-111111111111'
      and capability.scope_kind = 'contest_lineage'
      and capability.scope_id =
        'a0000001-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'app'
      and column_row.table_name = 'account_capabilities'
      and column_row.column_name = 'secret'
  ),
  'only the returned plaintext and its private SHA-256 hash exist'
);
select is(
  (
    select app.authorize_account_capability(
      deletion.result -> 'capabilities' -> 0 ->> 'secret',
      'contest_lineage',
      'a0000001-0000-0000-0000-000000000001',
      (select t0 from t_clock)
    )
    from t_delete_result deletion
  ),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'the hash-only lineage capability resolves while its workflow is open'
);
select ok(
  (
    select contest.status = 'active'
    from public.contests contest
    where contest.id = 'a0000001-0000-0000-0000-000000000001'
  )
  and (
    select participant.status = 'accepted'
    from public.contest_participants participant
    where participant.contest_id =
          'a0000001-0000-0000-0000-000000000001'
      and participant.user_id =
          '11111111-1111-1111-1111-111111111111'
  ),
  'deletion preserves the active contest and accepted stake'
);
select ok(
  (
    select device.revoked_at is not null
    from public.device_attestations device
    cross join t_keys keys
    where device.key_id = keys.departing_key_id
  ),
  'the operational device registration is retained but revoked'
);
select ok(
  exists (
    select 1
    from public.ingest_batches batch
    cross join t_keys keys
    where batch.id = 'b1000001-0000-0000-0000-000000000001'
      and batch.key_id = keys.departing_key_id
  ),
  'the attested ingest batch and key fingerprint survive auth deletion'
);
select ok(
  exists (
    select 1
    from public.metric_snapshots
    where id = 'b2000001-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.evidence_quarantines
    where id = 'b3000001-0000-0000-0000-000000000001'
      and snapshot_id = 'b2000001-0000-0000-0000-000000000001'
  ),
  'raw metric and its adjudicated quarantine survive auth deletion'
);
select ok(
  exists (
    select 1
    from public.geofence_checkins
    where id = 'e1000001-0000-0000-0000-000000000001'
      and outcome = 'accepted'
  )
  and (
    select count(*) = 2
    from public.geofence_location_observations
    where checkin_id = 'e1000001-0000-0000-0000-000000000001'
  ),
  'the check-in fact and its raw samples survive auth deletion'
);

-- ---------------------------------------------------------------------------
-- Stale JWTs lose every table and RPC authorization path
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (
    select count(*)
    from t_account_deletion_participant_events event_id
    cross join lateral public.get_account_deletion_participant_event(
      event_id.id
    ) resolved
  ),
  2::bigint,
  'the active contest creator can resolve both exact departure event IDs'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333"}',
  true
);
select is(
  (
    select count(*)
    from t_account_deletion_participant_events event_id
    cross join lateral public.get_account_deletion_participant_event(
      event_id.id
    ) resolved
  ),
  0::bigint,
  'an unrelated active actor learns nothing from an exact departure event ID'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111"}',
  true
);
select throws_ok(
  $$ select *
     from public.get_account_deletion_participant_event(
       (
         select event_id.id
         from t_account_deletion_participant_events event_id
         limit 1
       )
     ) $$,
  '42501',
  null,
  'the deleted actor stale JWT cannot resolve a departure event'
);
select ok(
  (select count(*) = 0 from public.profiles)
  and (select count(*) = 0 from public.friendships)
  and (select count(*) = 0 from public.groups)
  and (select count(*) = 0 from public.contests)
  and (select count(*) = 0 from public.contest_participants)
  and (select count(*) = 0 from public.device_attestations)
  and (select count(*) = 0 from public.ingest_batches)
  and (select count(*) = 0 from public.metric_snapshots)
  and (select count(*) = 0 from public.evidence_quarantines)
  and (select count(*) = 0 from public.geofence_checkins)
  and (select count(*) = 0 from public.geofence_location_observations)
  and (select count(*) = 0 from public.notification_intents),
  'a tombstoned stale JWT reads no public table rows'
);
select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values (
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222'
     ) $$,
  '42501',
  null,
  'a tombstoned stale JWT cannot mutate a public table'
);
select throws_ok(
  $$ select * from public.find_profile_by_handle('survivor_81') $$,
  '42501',
  null,
  'a tombstoned stale JWT cannot invoke an authenticated RPC'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222"}',
  true
);
select is(
  (
    select count(*)
    from public.find_profile_by_handle('departing_81')
  ) + (
    select count(*)
    from public.find_profile_by_handle(
      current_setting('d81.tombstone_handle')
    )
  ),
  0::bigint,
  'an active survivor cannot discover either former or tombstone handle'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

set local role service_role;
select throws_ok(
  $$ select public.assert_active_actor(null) $$,
  '42501',
  null,
  'the service active-actor boundary rejects a NULL actor'
);
select throws_ok(
  $$ select public.create_retention_hold(
       'contest_lineage',
       'a0000001-0000-0000-0000-000000000001',
       'invalid infinite hold',
       'infinity'::timestamptz
     ) $$,
  '22023',
  null,
  'retention holds require a finite expiry'
);
select throws_ok(
  $$ select *
     from app.run_raw_evidence_retention(
       'infinity'::timestamptz,
       100
     ) $$,
  '22023',
  null,
  'the retention worker rejects a non-finite authority clock'
);
reset role;

-- ---------------------------------------------------------------------------
-- Only the guarded worker can delete or scrub raw evidence
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ delete from public.metric_snapshots
     where id = 'b2000001-0000-0000-0000-000000000001' $$,
  '23001',
  null,
  'even the owner cannot directly delete a raw metric'
);
select throws_ok(
  $$ delete from public.geofence_location_observations
     where id = 'e2000001-0000-0000-0000-000000000001' $$,
  '23001',
  null,
  'even the owner cannot directly delete a raw location'
);
select throws_ok(
  $$ update public.geofence_checkins
     set workout_source_bundle_id = null
     where id = 'e1000001-0000-0000-0000-000000000001' $$,
  '23001',
  null,
  'even the owner cannot directly scrub a source identifier'
);
select throws_ok(
  $$ delete from public.device_attestations device
     using t_keys keys
     where device.key_id = keys.departing_key_id $$,
  '23001',
  null,
  'even a revoked registration can be removed only by the worker'
);
select throws_ok(
  $$ delete from app.device_attestation_receipts receipt
     using t_keys keys
     where receipt.key_id = keys.departing_key_id $$,
  '23001',
  null,
  'opaque App Attest receipts share the same worker guard'
);

-- ---------------------------------------------------------------------------
-- Persisted finality, holds, capability expiry, and raw retention
-- ---------------------------------------------------------------------------

set local role service_role;
select public.set_workflow_retention_state(
  'contest_lineage',
  'a0000001-0000-0000-0000-000000000001',
  false,
  (select terminal_at from t_clock),
  null,
  'raw-evidence-retention-v1'
);
reset role;

select ok(
  (
    select
      not scope.workflow_open
      and scope.user_terminal_at = clock_fixture.terminal_at
      and scope.operator_open_until =
        clock_fixture.terminal_at + interval '90 days'
      and scope.retention_policy_version =
        'raw-evidence-retention-v1'
    from app.workflow_scopes scope
    cross join t_clock clock_fixture
    where scope.scope_kind = 'contest_lineage'
      and scope.scope_id =
        'a0000001-0000-0000-0000-000000000001'
  ),
  'closing a scope persists finality and the versioned maximum cutoff'
);
select is(
  (
    select app.authorize_account_capability(
      deletion.result -> 'capabilities' -> 0 ->> 'secret',
      'contest_lineage',
      'a0000001-0000-0000-0000-000000000001',
      clock_fixture.terminal_at + interval '90 days 1 second'
    )
    from t_delete_result deletion
    cross join t_clock clock_fixture
  ),
  null::uuid,
  'the capability expires after the closed scope cutoff'
);

create temporary table t_hold (id uuid not null);
grant insert on t_hold to service_role;

set local role service_role;
insert into t_hold (id)
select public.create_retention_hold(
  'contest_lineage',
  'a0000001-0000-0000-0000-000000000001',
  'D81 fixed legal hold',
  (select hold_until from t_clock)
);
reset role;

select ok(
  exists (
    select 1
    from app.retention_holds hold
    cross join t_clock clock_fixture
    where hold.id = (select id from t_hold)
      and hold.scope_kind = 'contest_lineage'
      and hold.scope_id =
        'a0000001-0000-0000-0000-000000000001'
      and hold.expires_at = clock_fixture.hold_until
  )
  and (
    select scope.operator_open_until = clock_fixture.hold_until
    from app.workflow_scopes scope
    cross join t_clock clock_fixture
    where scope.scope_kind = 'contest_lineage'
      and scope.scope_id =
        'a0000001-0000-0000-0000-000000000001'
  ),
  'an append-only scoped hold transactionally extends the persisted cutoff'
);
select is(
  (
    select app.authorize_account_capability(
      deletion.result -> 'capabilities' -> 0 ->> 'secret',
      'contest_lineage',
      'a0000001-0000-0000-0000-000000000001',
      clock_fixture.t0
    )
    from t_delete_result deletion
    cross join t_clock clock_fixture
  ),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'an unexpired hold keeps the deleted actor capability reachable'
);
select throws_ok(
  $$ update app.retention_holds
     set reason = 'rewritten'
     where id = (select id from t_hold) $$,
  '23001',
  null,
  'retention holds are append-only audit facts'
);
select is(
  (
    select app.authorize_account_capability(
      deletion.result -> 'capabilities' -> 0 ->> 'secret',
      'contest_lineage',
      'a0000001-0000-0000-0000-000000000001',
      clock_fixture.hold_until + interval '1 second'
    )
    from t_delete_result deletion
    cross join t_clock clock_fixture
  ),
  null::uuid,
  'the capability expires again when both cutoff and hold have elapsed'
);

create temporary table t_retention_result (
  location_rows_pruned integer,
  metric_rows_pruned integer,
  source_ids_scrubbed integer,
  receipt_rows_pruned integer,
  device_rows_pruned integer
);
grant insert on t_retention_result to service_role;

set local role service_role;
insert into t_retention_result
select *
from app.run_raw_evidence_retention(
  (select worker_at from t_clock),
  100
);
reset role;

select ok(
  (
    select
      location_rows_pruned = 2
      and metric_rows_pruned = 1
      and source_ids_scrubbed = 1
      and receipt_rows_pruned = 2
      and device_rows_pruned = 1
    from t_retention_result
  ),
  'the worker reports exactly the eligible raw rows it pruned'
);
select ok(
  not exists (
    select 1
    from public.metric_snapshots
    where id = 'b2000001-0000-0000-0000-000000000001'
  )
  and not exists (
    select 1
    from public.geofence_location_observations
    where checkin_id = 'e1000001-0000-0000-0000-000000000001'
  )
  and (
    select
      workout_id is null
      and workout_source_bundle_id is null
    from public.geofence_checkins
    where id = 'e1000001-0000-0000-0000-000000000001'
  ),
  'eligible metric values, exact locations, and source IDs are minimized'
);
select ok(
  exists (
    select 1
    from public.metric_snapshots
    where id = 'b2000001-0000-0000-0000-000000000005'
  )
  and (
    select count(*) = 2
    from public.geofence_location_observations
    where checkin_id = 'e1000001-0000-0000-0000-000000000005'
  )
  and (
    select
      workout_id = 'd1000001-0000-0000-0000-000000000005'::uuid
      and workout_source_bundle_id = 'com.apple.health.open'
    from public.geofence_checkins
    where id = 'e1000001-0000-0000-0000-000000000005'
  ),
  'an open workflow keeps all of its raw metric and location material'
);
select ok(
  not exists (
    select 1
    from public.device_attestations device
    cross join t_keys keys
    where device.key_id = keys.departing_key_id
  )
  and not exists (
    select 1
    from app.device_attestation_receipts receipt
    cross join t_keys keys
    where receipt.key_id = keys.departing_key_id
  ),
  'an eligible revoked registration and its opaque receipt are pruned together'
);
select ok(
  exists (
    select 1
    from public.device_attestations device
    cross join t_keys keys
    where device.key_id = keys.active_key_id
      and device.revoked_at is null
  )
  and not exists (
    select 1
    from app.device_attestation_receipts receipt
    cross join t_keys keys
    where receipt.key_id = keys.active_key_id
  )
  and (
    select
      summary.initial_receipt_digest =
        extensions.digest(pg_catalog.decode('b201', 'hex'), 'sha256')
      and summary.current_receipt_digest =
        extensions.digest(pg_catalog.decode('b202', 'hex'), 'sha256')
      and summary.retention_policy_version =
          'raw-evidence-retention-v1'
    from app.device_receipt_retention_summaries summary
    cross join t_keys keys
    where summary.key_id = keys.active_key_id
  ),
  'an active key/counter survives while its aged receipt becomes a digest summary'
);
select ok(
  exists (
    select 1
    from public.contest_participants
    where contest_id = 'a0000001-0000-0000-0000-000000000001'
      and user_id = '11111111-1111-1111-1111-111111111111'
      and status = 'accepted'
  )
  and exists (
    select 1
    from public.ingest_batches batch
    cross join t_keys keys
    where batch.id = 'b1000001-0000-0000-0000-000000000001'
      and batch.key_id = keys.departing_key_id
  )
  and exists (
    select 1
    from public.evidence_quarantines
    where id = 'b3000001-0000-0000-0000-000000000001'
      and snapshot_id = 'b2000001-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.geofence_checkins checkin
    cross join t_keys keys
    where checkin.id = 'e1000001-0000-0000-0000-000000000001'
      and checkin.key_id = keys.departing_key_id
      and checkin.outcome = 'accepted'
  ),
  'roster, ingest, quarantine, check-in, and hash-only key lineage remain durable'
);
select set_eq(
  $$ select event.evidence_kind || ':' || count(*)::text
     from app.raw_evidence_retention_events event
     group by event.evidence_kind $$,
  array[
    'app_attest_receipt:2',
    'device_registration:1',
    'exact_location:2',
    'metric_observation:1',
    'source_identifier:1'
  ],
  'every raw deletion or scrub appends one typed retention event'
);
select ok(
  (
    select count(*) = 7
       and bool_and(octet_length(event.target_digest) = 32)
       and bool_and(
         event.policy_version = 'raw-evidence-retention-v1'
       )
    from app.raw_evidence_retention_events event
  )
  and (
    select event.target_digest = keys.departing_key_id
    from app.raw_evidence_retention_events event
    cross join t_keys keys
    where event.evidence_kind = 'device_registration'
  )
  and (
    select event.target_digest =
      extensions.digest(
        pg_catalog.decode('a102', 'hex'),
        'sha256'
      )
    from app.raw_evidence_retention_events event
    cross join t_keys keys
    where event.evidence_kind = 'app_attest_receipt'
      and event.target_ref =
          pg_catalog.encode(keys.departing_key_id, 'hex')
  ),
  'retention events keep only permanent target digests and policy provenance'
);
select throws_ok(
  $$ update app.raw_evidence_retention_events
     set target_ref = 'rewritten' $$,
  '23001',
  null,
  'retention events are immutable'
);

truncate table t_retention_result;

set local role service_role;
insert into t_retention_result
select *
from app.run_raw_evidence_retention(
  (select worker_at from t_clock),
  100
);
reset role;

select ok(
  (
    select
      location_rows_pruned = 0
      and metric_rows_pruned = 0
      and source_ids_scrubbed = 0
      and receipt_rows_pruned = 0
      and device_rows_pruned = 0
    from t_retention_result
  ),
  'a repeated worker run is idempotent'
);
select is(
  (select count(*) from app.raw_evidence_retention_events),
  7::bigint,
  'an idempotent rerun appends no duplicate retention events'
);

select * from finish();
rollback;
