-- M7 / D81 -- versioned, scope-aware raw evidence retention.
--
-- Durable adjudicated facts remain append-only. Only exact locations, raw
-- hourly observations/source identifiers, revoked operational device material,
-- and opaque App Attest receipts are prunable, and only through this worker
-- after user finality, child-workflow closure, the applicable policy interval,
-- and every scoped hold.
begin;

-- ===========================================================================
-- SECTION 1 -- Scope state and hold APIs
-- ===========================================================================

create function public.set_workflow_retention_state(
  p_scope_kind               public.account_capability_scope_kind,
  p_scope_id                 uuid,
  p_workflow_open            boolean,
  p_user_terminal_at         timestamptz default null,
  p_operator_open_until      timestamptz default null,
  p_retention_policy_version text default 'raw-evidence-retention-v1'
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope                  app.workflow_scopes;
  v_terminal_at            timestamptz;
  v_operator_open_until    timestamptz;
  v_max_retention          interval;
  v_latest_hold_expiry     timestamptz;
begin
  if p_scope_kind is null
     or p_scope_id is null
     or p_workflow_open is null
     or p_retention_policy_version is null
     or (
       p_user_terminal_at is not null
       and not pg_catalog.isfinite(p_user_terminal_at)
     )
     or (
       p_operator_open_until is not null
       and not pg_catalog.isfinite(p_operator_open_until)
     )
  then
    raise exception 'scope, workflow state, and retention policy are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select scope.*
    into v_scope
  from app.workflow_scopes scope
  where scope.scope_kind = p_scope_kind
    and scope.scope_id = p_scope_id
  for update;

  if not found then
    raise exception 'workflow scope does not exist'
      using errcode = 'foreign_key_violation';
  end if;

  if not exists (
    select 1
    from app.retention_policy_versions policy
    where policy.version = p_retention_policy_version
  ) then
    raise exception 'retention policy % does not exist',
      p_retention_policy_version
      using errcode = 'invalid_parameter_value';
  end if;

  if v_scope.user_terminal_at is not null
     and p_retention_policy_version <>
         v_scope.retention_policy_version
  then
    raise exception 'a finalized scope cannot change retention policy versions'
      using errcode = 'restrict_violation';
  end if;

  v_terminal_at := case
    when v_scope.user_terminal_at is null then p_user_terminal_at
    when p_user_terminal_at is null then v_scope.user_terminal_at
    else greatest(v_scope.user_terminal_at, p_user_terminal_at)
  end;

  if not p_workflow_open and v_terminal_at is null then
    raise exception 'closing a workflow requires its user-terminal timestamp'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_terminal_at is not null then
    select max(rule.retain_for)
      into v_max_retention
    from app.raw_evidence_retention_rules rule
    where rule.policy_version = p_retention_policy_version;

    if v_max_retention is null then
      raise exception 'retention policy % has no rules',
        p_retention_policy_version
        using errcode = 'invalid_parameter_value';
    end if;

    select max(hold.expires_at)
      into v_latest_hold_expiry
    from app.retention_holds hold
    where hold.scope_kind = p_scope_kind
      and hold.scope_id = p_scope_id;

    v_operator_open_until := greatest(
      v_terminal_at + v_max_retention,
      coalesce(p_operator_open_until, '-infinity'::timestamptz),
      coalesce(v_scope.operator_open_until, '-infinity'::timestamptz),
      coalesce(v_latest_hold_expiry, '-infinity'::timestamptz)
    );
  else
    v_operator_open_until := null;
  end if;

  if (
       p_workflow_open
       or v_operator_open_until > clock_timestamp()
     )
     and exists (
       select 1
       from app.workflow_scope_actors scope_actor
       join public.profiles profile on profile.id = scope_actor.actor_id
       where scope_actor.scope_kind = p_scope_kind
         and scope_actor.scope_id = p_scope_id
         and profile.deleted_at is not null
         and not exists (
            select 1
            from app.account_capabilities capability
            where capability.actor_id = scope_actor.actor_id
              and capability.revoked_at is null
              and (
               (
                 capability.scope_kind = p_scope_kind
                 and capability.scope_id = p_scope_id
               )
               or (
                 capability.scope_kind = 'contest_lineage'
                 and scope_actor.covered_by_contest_id = capability.scope_id
               )
             )
         )
     )
  then
    raise exception 'workflow access cannot outlive a deleted actor without a delivered capability'
      using errcode = 'restrict_violation';
  end if;

  update app.workflow_scopes scope
  set workflow_open = p_workflow_open,
      user_terminal_at = v_terminal_at,
      operator_open_until = v_operator_open_until,
      retention_policy_version = p_retention_policy_version,
      updated_at = clock_timestamp()
  where scope.scope_kind = p_scope_kind
    and scope.scope_id = p_scope_id;
end;
$$;

comment on function public.set_workflow_retention_state(
  public.account_capability_scope_kind,
  uuid,
  boolean,
  timestamptz,
  timestamptz,
  text
) is
  'Service-only D81 hook. Persists monotonic user-finality and operator cutoffs for a workflow scope.';

create function public.create_retention_hold(
  p_scope_kind public.account_capability_scope_kind,
  p_scope_id   uuid,
  p_reason     text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_hold_id uuid;
  v_scope   app.workflow_scopes;
begin
  if p_scope_kind is null
     or p_scope_id is null
     or p_reason is null
     or p_expires_at is null
     or not pg_catalog.isfinite(p_expires_at)
     or p_expires_at <= clock_timestamp()
  then
    raise exception 'scope, reason, and a future hold expiry are required'
      using errcode = 'invalid_parameter_value';
  end if;

  select scope.*
    into v_scope
  from app.workflow_scopes scope
  where scope.scope_kind = p_scope_kind
    and scope.scope_id = p_scope_id
  for update;

  if not found then
    raise exception 'workflow scope does not exist'
      using errcode = 'foreign_key_violation';
  end if;

  if not v_scope.workflow_open
     and coalesce(
       v_scope.operator_open_until,
       '-infinity'::timestamptz
     ) <= clock_timestamp()
  then
    raise exception 'an expired workflow scope cannot be reopened by a hold'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from app.workflow_scope_actors scope_actor
    join public.profiles profile on profile.id = scope_actor.actor_id
    where scope_actor.scope_kind = p_scope_kind
      and scope_actor.scope_id = p_scope_id
      and profile.deleted_at is not null
      and not exists (
        select 1
        from app.account_capabilities capability
        where capability.actor_id = scope_actor.actor_id
          and capability.revoked_at is null
          and (
            (
              capability.scope_kind = p_scope_kind
              and capability.scope_id = p_scope_id
            )
            or (
              capability.scope_kind = 'contest_lineage'
              and scope_actor.covered_by_contest_id = capability.scope_id
            )
          )
      )
  ) then
    raise exception 'a hold cannot create unreachable work for a deleted actor'
      using errcode = 'restrict_violation';
  end if;

  insert into app.retention_holds (
    scope_kind,
    scope_id,
    reason,
    expires_at
  )
  values (
    p_scope_kind,
    p_scope_id,
    p_reason,
    p_expires_at
  )
  returning id into v_hold_id;

  -- Once finality has fixed a cutoff, adding a hold can only extend it.
  if v_scope.user_terminal_at is not null then
    update app.workflow_scopes scope
    set operator_open_until = greatest(
          scope.operator_open_until,
          p_expires_at
        ),
        updated_at = clock_timestamp()
    where scope.scope_kind = p_scope_kind
      and scope.scope_id = p_scope_id;
  end if;

  return v_hold_id;
end;
$$;

comment on function public.create_retention_hold(
  public.account_capability_scope_kind,
  uuid,
  text,
  timestamptz
) is
  'Service-only append-only scoped retention hold with a mandatory expiry.';

revoke all on function public.set_workflow_retention_state(
                         public.account_capability_scope_kind,
                         uuid,
                         boolean,
                         timestamptz,
                         timestamptz,
                         text
                       ),
                       public.create_retention_hold(
                         public.account_capability_scope_kind,
                         uuid,
                         text,
                         timestamptz
                       )
  from public, anon, authenticated, service_role;

grant execute on function public.set_workflow_retention_state(
                            public.account_capability_scope_kind,
                            uuid,
                            boolean,
                            timestamptz,
                            timestamptz,
                            text
                          ),
                          public.create_retention_hold(
                            public.account_capability_scope_kind,
                            uuid,
                            text,
                            timestamptz
                          )
  to service_role;

-- Receipt bytes age out independently of the active public key/counter. Keep a
-- minimal immutable verification summary so retries cannot recreate pruned
-- bytes and audit facts survive the raw object.
create table app.device_receipt_retention_summaries (
  key_id                       bytea primary key
    check (octet_length(key_id) = 32),
  initial_receipt_digest       bytea not null
    check (octet_length(initial_receipt_digest) = 32),
  current_receipt_digest       bytea not null
    check (octet_length(current_receipt_digest) = 32),
  received_at                  timestamptz not null,
  refreshed_at                 timestamptz,
  current_receipt_verified_at  timestamptz,
  retention_policy_version     text not null
    references app.retention_policy_versions (version) on delete restrict,
  pruned_at                    timestamptz not null,

  constraint device_receipt_retention_summary_order
    check (
      pruned_at >= received_at
      and (refreshed_at is null or pruned_at >= refreshed_at)
      and (
        current_receipt_verified_at is null
        or pruned_at >= current_receipt_verified_at
      )
    )
);

create trigger device_receipt_retention_summaries_forbid_mutation
  before update or delete or truncate
  on app.device_receipt_retention_summaries
  for each statement execute function app.forbid_mutation();

revoke all on table app.device_receipt_retention_summaries
  from public, anon, authenticated, service_role;

create function app.lock_device_receipt_retention(p_key_id bytea)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_key_id is null or octet_length(p_key_id) <> 32 then
    raise exception 'device key id must be a SHA-256 digest'
      using errcode = 'invalid_parameter_value';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.encode(p_key_id, 'hex'),
      0
    )
  );
end;
$$;

revoke all on function app.lock_device_receipt_retention(bytea)
  from public, anon, authenticated, service_role;

-- A lost-response registration retry remains idempotent after the raw receipt
-- has aged out. It may recover the original capture time, but it cannot restore
-- the deleted bytes or revive a revoked/pruned device.
create or replace function public.register_device_key(
  p_user_id             uuid,
  p_key_id              bytea,
  p_public_key          bytea,
  p_attestation_receipt bytea,
  p_environment         public.attestation_environment
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_device       public.device_attestations;
  v_device_found boolean;
  v_summary      app.device_receipt_retention_summaries;
begin
  if p_user_id is null
     or p_key_id is null
     or p_public_key is null
     or p_attestation_receipt is null
     or p_environment is null
  then
    raise exception 'complete device registration metadata is required'
      using errcode = 'invalid_parameter_value';
  end if;

  perform app.lock_active_actors(array[p_user_id]);

  select device.*
    into v_device
  from public.device_attestations device
  where device.key_id = p_key_id
  for update;
  v_device_found := found;

  perform app.lock_device_receipt_retention(p_key_id);

  if exists (
    select 1
    from app.raw_evidence_retention_events event
    where event.evidence_kind = 'device_registration'
      and event.target_ref = pg_catalog.encode(p_key_id, 'hex')
  ) then
    raise exception 'this device key is no longer registrable'
      using errcode = 'unique_violation';
  end if;

  select summary.*
    into v_summary
  from app.device_receipt_retention_summaries summary
  where summary.key_id = p_key_id;

  if found then
    if not v_device_found
       or v_device.revoked_at is not null
       or v_device.user_id is distinct from p_user_id
       or v_device.public_key is distinct from p_public_key
       or v_device.environment is distinct from p_environment
       or v_summary.initial_receipt_digest is distinct from
          extensions.digest(p_attestation_receipt, 'sha256')
    then
      raise exception 'this device key is no longer registrable'
        using errcode = 'unique_violation';
    end if;

    return v_summary.received_at;
  end if;

  return app.register_device_key_unchecked(
    p_user_id,
    p_key_id,
    p_public_key,
    p_attestation_receipt,
    p_environment
  );
end;
$$;

-- ===========================================================================
-- SECTION 2 -- The only raw-delete/scrub authority
-- ===========================================================================

create function app.guard_raw_evidence_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if current_user <> v_owner
     or coalesce(
       pg_catalog.current_setting('app.raw_retention_worker', true),
       ''
     ) <> 'on'
  then
    raise exception 'raw evidence can be deleted only by the guarded retention worker'
      using errcode = 'restrict_violation';
  end if;

  return old;
end;
$$;

comment on function app.guard_raw_evidence_delete() is
  'Allows DELETE only inside the owner-executed D81 retention worker transaction.';

create trigger metric_snapshots_guard_delete
  before delete on public.metric_snapshots
  for each row execute function app.guard_raw_evidence_delete();

create trigger geofence_location_observations_guard_delete
  before delete on public.geofence_location_observations
  for each row execute function app.guard_raw_evidence_delete();

create trigger device_attestations_guard_delete
  before delete on public.device_attestations
  for each row execute function app.guard_raw_evidence_delete();

create trigger device_attestation_receipts_guard_delete
  before delete on app.device_attestation_receipts
  for each row execute function app.guard_raw_evidence_delete();

create trigger metric_snapshots_forbid_truncate
  before truncate on public.metric_snapshots
  for each statement execute function app.forbid_mutation();
create trigger geofence_location_observations_forbid_truncate
  before truncate on public.geofence_location_observations
  for each statement execute function app.forbid_mutation();
create trigger device_attestations_forbid_truncate
  before truncate on public.device_attestations
  for each statement execute function app.forbid_mutation();
create trigger device_attestation_receipts_forbid_truncate
  before truncate on app.device_attestation_receipts
  for each statement execute function app.forbid_mutation();

-- A check-in's adjudicated outcome is permanent, but its raw HealthKit source
-- identifiers are 90-day material. Replace the blanket UPDATE prohibition with
-- one exact, owner-and-worker-only scrub transition.
alter table public.geofence_checkins
  alter column workout_id drop not null;

drop trigger geofence_checkins_forbid_update
  on public.geofence_checkins;

create function app.guard_geofence_checkin_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner name;
begin
  select role.rolname
    into v_owner
  from pg_catalog.pg_class relation
  join pg_catalog.pg_roles role on role.oid = relation.relowner
  where relation.oid = tg_relid;

  if current_user = v_owner
     and coalesce(
       pg_catalog.current_setting('app.raw_retention_worker', true),
       ''
     ) = 'on'
     and (
       old.workout_id is not null
       or old.workout_source_bundle_id is not null
     )
     and new.workout_id is null
     and new.workout_source_bundle_id is null
     and (
       to_jsonb(new) - array['workout_id', 'workout_source_bundle_id']
       is not distinct from
       to_jsonb(old) - array['workout_id', 'workout_source_bundle_id']
     )
  then
    return new;
  end if;

  raise exception 'geofence check-ins are immutable outside the guarded source-identifier scrub'
    using errcode = 'restrict_violation';
end;
$$;

create trigger geofence_checkins_guard_update
  before update on public.geofence_checkins
  for each row execute function app.guard_geofence_checkin_update();

revoke all on function app.guard_raw_evidence_delete(),
                       app.guard_geofence_checkin_update()
  from public, anon, authenticated, service_role;

create index profiles_active_handle_idx
  on public.profiles (lower(handle::text))
  where deleted_at is null;

create index device_attestations_revoked_idx
  on public.device_attestations (revoked_at, key_id)
  where revoked_at is not null;

create index geofence_checkins_raw_source_idx
  on public.geofence_checkins (contest_id, recorded_at, id)
  where workout_id is not null
     or workout_source_bundle_id is not null;

create index ingest_batches_key_id_idx
  on public.ingest_batches (key_id, contest_id)
  where key_id is not null;

create index metric_snapshots_retention_scan_idx
  on public.metric_snapshots (recorded_at, id);

create index geofence_location_observations_retention_scan_idx
  on public.geofence_location_observations (created_at, id);

-- Evidence of a contest is eligible for one policy kind only when finality has
-- been persisted, its kind-specific interval has elapsed, and no scoped hold
-- remains. operator_open_until is the maximum capability/case-admission
-- horizon; shorter-lived evidence can still follow its own versioned deadline.
create function app.scope_evidence_retention_ready(
  p_contest_id   uuid,
  p_evidence_kind text,
  p_at           timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from app.workflow_scopes scope
    join app.raw_evidence_retention_rules rule
      on rule.policy_version = scope.retention_policy_version
     and rule.evidence_kind = p_evidence_kind
    where scope.scope_kind = 'contest_lineage'
      and scope.scope_id = p_contest_id
      and not scope.workflow_open
      and scope.user_terminal_at is not null
      and scope.operator_open_until is not null
      and scope.user_terminal_at + rule.retain_for <= p_at
      and not exists (
        select 1
        from app.retention_holds hold
        where hold.scope_kind = scope.scope_kind
          and hold.scope_id = scope.scope_id
          and hold.expires_at > p_at
      )
  );
$$;

-- The scan predicate above keeps candidate discovery cheap. This second check
-- owns the scope row lock shared by finality updates and hold creation, then
-- re-evaluates eligibility after waiting. No raw mutation may rely on the
-- unlocked discovery result alone.
create function app.lock_scope_evidence_retention_ready(
  p_contest_id    uuid,
  p_evidence_kind text,
  p_at            timestamptz
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope      app.workflow_scopes;
  v_retain_for interval;
begin
  if p_contest_id is null
     or p_evidence_kind is null
     or p_at is null
  then
    return false;
  end if;

  select scope.*
    into v_scope
  from app.workflow_scopes scope
  where scope.scope_kind = 'contest_lineage'
    and scope.scope_id = p_contest_id
  for update;

  if not found
     or v_scope.workflow_open
     or v_scope.user_terminal_at is null
     or v_scope.operator_open_until is null
  then
    return false;
  end if;

  select rule.retain_for
    into v_retain_for
  from app.raw_evidence_retention_rules rule
  where rule.policy_version = v_scope.retention_policy_version
    and rule.evidence_kind = p_evidence_kind;

  return v_retain_for is not null
     and v_scope.user_terminal_at + v_retain_for <= p_at
     and not exists (
       select 1
       from app.retention_holds hold
       where hold.scope_kind = v_scope.scope_kind
         and hold.scope_id = v_scope.scope_id
         and hold.expires_at > p_at
     );
end;
$$;

revoke all on function app.scope_evidence_retention_ready(
  uuid,
  text,
  timestamptz
),
                       app.lock_scope_evidence_retention_ready(
  uuid,
  text,
  timestamptz
) from public, anon, authenticated, service_role;

-- ===========================================================================
-- SECTION 3 -- Idempotent raw evidence retention worker
-- ===========================================================================

create function app.run_raw_evidence_retention(
  p_now   timestamptz default clock_timestamp(),
  p_limit integer default 500
)
returns table (
  location_rows_pruned integer,
  metric_rows_pruned   integer,
  source_ids_scrubbed  integer,
  receipt_rows_pruned  integer,
  device_rows_pruned   integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_location     record;
  v_metric       record;
  v_checkin      record;
  v_device       record;
  v_receipt      app.device_attestation_receipts;
  v_used_contest_id uuid;
  v_device_ready boolean;
  v_previous_worker_setting text :=
    pg_catalog.current_setting('app.raw_retention_worker', true);
begin
  if p_now is null
     or not pg_catalog.isfinite(p_now)
     or p_limit is null
     or p_limit not between 1 and 5000
  then
    raise exception 'retention time and a limit between 1 and 5000 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  location_rows_pruned := 0;
  metric_rows_pruned := 0;
  source_ids_scrubbed := 0;
  receipt_rows_pruned := 0;
  device_rows_pruned := 0;

  -- One worker transaction at a time keeps its raw-row -> scope-row lock order
  -- globally consistent even when the RPC is invoked manually beside cron.
  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('gametime-raw-evidence-retention', 0)
  ) then
    return next;
    return;
  end if;

  perform pg_catalog.set_config('app.raw_retention_worker', 'on', true);

  -- Exact coordinates and unredacted per-sample location material: 30 days.
  for v_location in
    select
      observation.id,
      observation.contest_id,
      scope.retention_policy_version
    from public.geofence_location_observations observation
    join app.workflow_scopes scope
      on scope.scope_kind = 'contest_lineage'
     and scope.scope_id = observation.contest_id
    where app.scope_evidence_retention_ready(
      observation.contest_id,
      'exact_location',
      p_now
    )
    order by observation.created_at, observation.id
    limit p_limit
    for update of observation skip locked
  loop
    if not app.lock_scope_evidence_retention_ready(
      v_location.contest_id,
      'exact_location',
      p_now
    ) then
      continue;
    end if;

    insert into app.raw_evidence_retention_events (
      scope_kind,
      scope_id,
      evidence_kind,
      target_ref,
      target_digest,
      policy_version,
      pruned_at
    )
    values (
      'contest_lineage',
      v_location.contest_id,
      'exact_location',
      v_location.id::text,
      extensions.digest(
        pg_catalog.convert_to(v_location.id::text, 'UTF8'),
        'sha256'
      ),
      v_location.retention_policy_version,
      p_now
    );

    delete from public.geofence_location_observations observation
    where observation.id = v_location.id;

    location_rows_pruned := location_rows_pruned + 1;
  end loop;

  -- Raw hourly values and their HealthKit source/device metadata: 90 days.
  -- Quarantines retain the historical snapshot UUID without a cascade.
  for v_metric in
    select
      snapshot.id,
      snapshot.contest_id,
      scope.retention_policy_version
    from public.metric_snapshots snapshot
    join app.workflow_scopes scope
      on scope.scope_kind = 'contest_lineage'
     and scope.scope_id = snapshot.contest_id
    where app.scope_evidence_retention_ready(
      snapshot.contest_id,
      'metric_observation',
      p_now
    )
    order by snapshot.recorded_at, snapshot.id
    limit p_limit
    for update of snapshot skip locked
  loop
    if not app.lock_scope_evidence_retention_ready(
      v_metric.contest_id,
      'metric_observation',
      p_now
    ) then
      continue;
    end if;

    insert into app.raw_evidence_retention_events (
      scope_kind,
      scope_id,
      evidence_kind,
      target_ref,
      target_digest,
      policy_version,
      pruned_at
    )
    values (
      'contest_lineage',
      v_metric.contest_id,
      'metric_observation',
      v_metric.id::text,
      extensions.digest(
        pg_catalog.convert_to(v_metric.id::text, 'UTF8'),
        'sha256'
      ),
      v_metric.retention_policy_version,
      p_now
    );

    delete from public.metric_snapshots snapshot
    where snapshot.id = v_metric.id;

    metric_rows_pruned := metric_rows_pruned + 1;
  end loop;

  -- The derived check-in survives; only its raw HealthKit bundle identifier is
  -- scrubbed at the same 90-day boundary.
  for v_checkin in
    select
      checkin.id,
      checkin.contest_id,
      checkin.workout_id,
      checkin.workout_source_bundle_id,
      scope.retention_policy_version
    from public.geofence_checkins checkin
    join app.workflow_scopes scope
      on scope.scope_kind = 'contest_lineage'
     and scope.scope_id = checkin.contest_id
    where (
        checkin.workout_id is not null
        or checkin.workout_source_bundle_id is not null
      )
      and app.scope_evidence_retention_ready(
        checkin.contest_id,
        'metric_observation',
        p_now
      )
    order by checkin.recorded_at, checkin.id
    limit p_limit
    for update of checkin skip locked
  loop
    if not app.lock_scope_evidence_retention_ready(
      v_checkin.contest_id,
      'metric_observation',
      p_now
    ) then
      continue;
    end if;

    insert into app.raw_evidence_retention_events (
      scope_kind,
      scope_id,
      evidence_kind,
      target_ref,
      target_digest,
      policy_version,
      pruned_at
    )
    values (
      'contest_lineage',
      v_checkin.contest_id,
      'source_identifier',
      v_checkin.id::text,
       extensions.digest(
         pg_catalog.convert_to(
           coalesce(v_checkin.workout_id::text, '')
             || ':'
             || coalesce(v_checkin.workout_source_bundle_id, ''),
           'UTF8'
         ),
         'sha256'
      ),
      v_checkin.retention_policy_version,
      p_now
    );

    update public.geofence_checkins checkin
    set workout_id = null,
        workout_source_bundle_id = null
    where checkin.id = v_checkin.id;

    source_ids_scrubbed := source_ids_scrubbed + 1;
  end loop;

  -- Receipt bytes are historical evidence, not active-key state. They age out
  -- even while the public key/counter remains operational.
  for v_device in
    select
      device.*,
      receipt_rule.retain_for as receipt_retain_for
    from public.device_attestations device
    join app.device_attestation_receipts receipt
      on receipt.key_id = device.key_id
    join app.raw_evidence_retention_rules receipt_rule
      on receipt_rule.policy_version = device.retention_policy_version
     and receipt_rule.evidence_kind = 'app_attest_receipt'
    where coalesce(receipt.refreshed_at, receipt.received_at)
            + receipt_rule.retain_for <= p_now
      and not exists (
        select 1
        from (
          select batch.contest_id
          from public.ingest_batches batch
          where batch.key_id = device.key_id
          union
          select checkin.contest_id
          from public.geofence_checkins checkin
          where checkin.key_id = device.key_id
        ) used_contest
        where not app.scope_evidence_retention_ready(
          used_contest.contest_id,
          'app_attest_receipt',
          p_now
        )
      )
    order by coalesce(receipt.refreshed_at, receipt.received_at),
             device.key_id
    limit p_limit
    for update of device skip locked
  loop
    perform app.lock_device_receipt_retention(v_device.key_id);

    select receipt.*
      into v_receipt
    from app.device_attestation_receipts receipt
    where receipt.key_id = v_device.key_id
    for update;

    if not found
       or coalesce(v_receipt.refreshed_at, v_receipt.received_at)
            + v_device.receipt_retain_for > p_now
       or (
         v_receipt.current_receipt_verified_at is not null
         and v_receipt.current_receipt_verified_at > p_now
       )
    then
      continue;
    end if;

    v_device_ready := true;
    for v_used_contest_id in
      select used_contest.contest_id
      from (
        select batch.contest_id
        from public.ingest_batches batch
        where batch.key_id = v_device.key_id
        union
        select checkin.contest_id
        from public.geofence_checkins checkin
        where checkin.key_id = v_device.key_id
      ) used_contest
      order by used_contest.contest_id
    loop
      if not app.lock_scope_evidence_retention_ready(
        v_used_contest_id,
        'app_attest_receipt',
        p_now
      )
      then
        v_device_ready := false;
        exit;
      end if;
    end loop;

    if not v_device_ready then
      continue;
    end if;

    insert into app.device_receipt_retention_summaries (
      key_id,
      initial_receipt_digest,
      current_receipt_digest,
      received_at,
      refreshed_at,
      current_receipt_verified_at,
      retention_policy_version,
      pruned_at
    )
    values (
      v_device.key_id,
      extensions.digest(v_receipt.initial_receipt, 'sha256'),
      extensions.digest(v_receipt.current_receipt, 'sha256'),
      v_receipt.received_at,
      v_receipt.refreshed_at,
      v_receipt.current_receipt_verified_at,
      v_device.retention_policy_version,
      p_now
    );

    insert into app.raw_evidence_retention_events (
      evidence_kind,
      target_ref,
      target_digest,
      policy_version,
      pruned_at
    )
    values (
      'app_attest_receipt',
      pg_catalog.encode(v_device.key_id, 'hex'),
      extensions.digest(v_receipt.current_receipt, 'sha256'),
      v_device.retention_policy_version,
      p_now
    );

    delete from app.device_attestation_receipts receipt
    where receipt.key_id = v_device.key_id;

    receipt_rows_pruned := receipt_rows_pruned + 1;
  end loop;

  -- A public key/counter row is operational until revocation. Only revoked
  -- registrations whose receipt is already pruned and whose every used contest
  -- is scope-eligible can leave.
  for v_device in
    select
      device.*,
      device_rule.retain_for as device_retain_for
    from public.device_attestations device
    join app.raw_evidence_retention_rules device_rule
      on device_rule.policy_version = device.retention_policy_version
     and device_rule.evidence_kind = 'device_registration'
    where device.revoked_at is not null
      and device.revoked_at + device_rule.retain_for <= p_now
      and not exists (
        select 1
        from app.device_attestation_receipts receipt
        where receipt.key_id = device.key_id
      )
      and not exists (
        select 1
        from (
          select batch.contest_id
          from public.ingest_batches batch
          where batch.key_id = device.key_id
          union
          select checkin.contest_id
          from public.geofence_checkins checkin
          where checkin.key_id = device.key_id
        ) used_contest
        where not app.scope_evidence_retention_ready(
          used_contest.contest_id,
          'device_registration',
          p_now
        )
      )
    order by device.revoked_at, device.key_id
    limit p_limit
    for update of device skip locked
  loop
    if v_device.revoked_at + v_device.device_retain_for > p_now then
      continue;
    end if;

    v_device_ready := true;
    for v_used_contest_id in
      select used_contest.contest_id
      from (
        select batch.contest_id
        from public.ingest_batches batch
        where batch.key_id = v_device.key_id
        union
        select checkin.contest_id
        from public.geofence_checkins checkin
        where checkin.key_id = v_device.key_id
      ) used_contest
      order by used_contest.contest_id
    loop
      if not app.lock_scope_evidence_retention_ready(
        v_used_contest_id,
        'device_registration',
        p_now
      ) then
        v_device_ready := false;
        exit;
      end if;
    end loop;

    if not v_device_ready then
      continue;
    end if;

    insert into app.raw_evidence_retention_events (
      evidence_kind,
      target_ref,
      target_digest,
      policy_version,
      pruned_at
    )
    values (
      'device_registration',
      pg_catalog.encode(v_device.key_id, 'hex'),
      v_device.key_id,
      v_device.retention_policy_version,
      p_now
    );

    delete from public.device_attestations device
    where device.key_id = v_device.key_id;

    device_rows_pruned := device_rows_pruned + 1;
  end loop;

  perform pg_catalog.set_config(
    'app.raw_retention_worker',
    coalesce(v_previous_worker_setting, 'off'),
    true
  );

  return next;
end;
$$;

comment on function app.run_raw_evidence_retention(timestamptz, integer) is
  'Idempotent D81 worker. Prunes only scope-eligible raw rows and permanently logs each target/digest.';

revoke all on function app.run_raw_evidence_retention(
  timestamptz,
  integer
) from public, anon, authenticated, service_role;
grant execute on function app.run_raw_evidence_retention(
  timestamptz,
  integer
) to service_role;

-- Raw evidence windows are measured in days. Hourly work bounds ordinary
-- cleanup lag without creating needless load, and reuses D82's named job
-- registry/idempotent worker pattern.
select cron.schedule(
  'gametime-prune-raw-evidence',
  '17 * * * *',
  'select app.run_raw_evidence_retention();'
);

commit;
