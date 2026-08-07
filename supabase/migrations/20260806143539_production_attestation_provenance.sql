-- Preserve the App Attest environment on every durable Personal V1 evidence
-- record. Device registrations are operational data and may be pruned later;
-- production settlement must not infer provenance from a row that may no
-- longer exist.

alter table public.ingest_batches
  add column attestation_environment public.attestation_environment;

alter table public.personal_sync_coverage_batches
  add column attestation_environment public.attestation_environment;

alter table public.personal_trusted_diagnostics
  add column attestation_environment public.attestation_environment;

comment on column public.ingest_batches.attestation_environment is
  'Immutable App Attest environment captured when the batch is accepted. NULL means unattested or historical origin unknown and is never production evidence.';

comment on column public.personal_sync_coverage_batches.attestation_environment is
  'Immutable App Attest environment captured when coverage is accepted. NULL means historical origin unknown and is never production evidence.';

comment on column public.personal_trusted_diagnostics.attestation_environment is
  'Immutable App Attest environment captured when the diagnostic is accepted. NULL means historical origin unknown and is never production evidence.';

-- Append-only guards intentionally prevent ordinary changes to the audit
-- trail. Disable only those guards for this one migration backfill; a failed
-- migration transaction restores both the data and trigger state.
alter table public.ingest_batches
  disable trigger ingest_batches_forbid_update;

update public.ingest_batches batch
set attestation_environment = device.environment
from public.device_attestations device
where device.key_id = batch.key_id;

alter table public.ingest_batches
  enable trigger ingest_batches_forbid_update;

alter table public.personal_sync_coverage_batches
  disable trigger personal_coverage_batches_forbid_mutation;

update public.personal_sync_coverage_batches batch
set attestation_environment = device.environment
from public.device_attestations device
where device.key_id = batch.key_id;

alter table public.personal_sync_coverage_batches
  enable trigger personal_coverage_batches_forbid_mutation;

alter table public.personal_trusted_diagnostics
  disable trigger personal_diagnostics_forbid_mutation;

update public.personal_trusted_diagnostics diagnostic
set attestation_environment = device.environment
from public.device_attestations device
where device.key_id = diagnostic.key_id;

alter table public.personal_trusted_diagnostics
  enable trigger personal_diagnostics_forbid_mutation;

create function app.snapshot_attestation_environment_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_environment public.attestation_environment;
begin
  if new.key_id is null then
    if new.attestation_environment is not null then
      raise exception 'an unattested record cannot claim an attestation environment'
        using errcode = 'invalid_parameter_value';
    end if;

    return new;
  end if;

  select device.environment
    into v_environment
  from public.device_attestations device
  where device.key_id = new.key_id;

  if new.attestation_environment is not null
     and new.attestation_environment is distinct from v_environment
  then
    raise exception 'attestation environment does not match the registered device key'
      using errcode = 'restrict_violation';
  end if;

  -- A missing registration is retained as unknown provenance for historical
  -- imports performed by a privileged operator. Trusted RPCs independently
  -- require a live, owned, non-revoked registration before reaching INSERT.
  new.attestation_environment := v_environment;
  return new;
end;
$$;

comment on function app.snapshot_attestation_environment_v1() is
  'Captures immutable App Attest provenance from the registered key. Missing registrations remain unknown and fail closed for production Personal V1 assessment.';

create trigger ingest_batches_snapshot_attestation_environment
  before insert on public.ingest_batches
  for each row execute function app.snapshot_attestation_environment_v1();

create trigger personal_coverage_snapshot_attestation_environment
  before insert on public.personal_sync_coverage_batches
  for each row execute function app.snapshot_attestation_environment_v1();

create trigger personal_diagnostics_snapshot_attestation_environment
  before insert on public.personal_trusted_diagnostics
  for each row execute function app.snapshot_attestation_environment_v1();

revoke all on function app.snapshot_attestation_environment_v1()
  from public, anon, authenticated, service_role;

-- Exact retries still bypass the consumed App Attest counter, but they must
-- use the same key as the committed record. Otherwise a production key could
-- "adopt" a development-origin request UUID and payload without creating a
-- new row (and therefore without running the provenance snapshot trigger).
create or replace function public.record_metric_batch(
  p_user_id         uuid,
  p_contest_id      uuid,
  p_client_batch_id uuid,
  p_payload_digest  bytea,
  p_observed_at     timestamptz,
  p_observations    jsonb,
  p_key_id          bytea default null,
  p_sign_count      bigint default null
)
returns table (
  batch_id           uuid,
  observation_count integer,
  replayed           boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing public.ingest_batches;
begin
  if p_user_id is null then
    raise exception 'account is not active'
      using errcode = 'insufficient_privilege';
  end if;

  perform app.lock_active_actors(array[p_user_id]);

  select batch.* into v_existing
  from public.ingest_batches batch
  where batch.user_id = p_user_id
    and batch.client_batch_id = p_client_batch_id;

  if v_existing.id is not null
     and v_existing.key_id is distinct from p_key_id
  then
    raise exception 'batch request UUID was already used by a different attestation key'
      using errcode = 'unique_violation';
  end if;

  return query
  select result.batch_id, result.observation_count, result.replayed
  from app.record_metric_batch_unchecked(
    p_user_id,
    p_contest_id,
    p_client_batch_id,
    p_payload_digest,
    p_observed_at,
    p_observations,
    p_key_id,
    p_sign_count
  ) result;
end;
$$;

comment on function public.record_metric_batch(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) is
  'Attested ingest. service_role only: the Edge Function checks the signature; this boundary preserves actor locks, exact-key idempotency, and database invariants.';

-- Retain the already-reviewed Personal V1 implementations as private
-- primitives and put the exact-key retry guard in a narrow public wrapper.
alter function public.record_personal_sync_coverage_v1(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) set schema app;

alter function app.record_personal_sync_coverage_v1(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) rename to record_personal_sync_coverage_v1_unchecked;

create function public.record_personal_sync_coverage_v1(
  p_user_id               uuid,
  p_challenge_id          uuid,
  p_client_coverage_id    uuid,
  p_payload_digest        bytea,
  p_observed_at           timestamptz,
  p_covered_bucket_starts jsonb,
  p_key_id                bytea,
  p_sign_count            bigint
)
returns table (coverage_batch_id uuid, replayed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing public.personal_sync_coverage_batches;
begin
  perform public.assert_active_actor(p_user_id);

  select coverage.* into v_existing
  from public.personal_sync_coverage_batches coverage
  where coverage.user_id = p_user_id
    and coverage.client_coverage_id = p_client_coverage_id;

  if v_existing.id is not null
     and v_existing.key_id is distinct from p_key_id
  then
    raise exception 'coverage request UUID was already used by a different attestation key'
      using errcode = 'unique_violation';
  end if;

  return query
  select result.coverage_batch_id, result.replayed
  from app.record_personal_sync_coverage_v1_unchecked(
    p_user_id,
    p_challenge_id,
    p_client_coverage_id,
    p_payload_digest,
    p_observed_at,
    p_covered_bucket_starts,
    p_key_id,
    p_sign_count
  ) result;
end;
$$;

comment on function public.record_personal_sync_coverage_v1(
  uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
) is
  'service_role-only append-only coverage boundary. Exact retries must use the original attestation key; new rows snapshot their App Attest environment.';

alter function public.record_trusted_personal_diagnostic_v1(
  uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
  integer, bytea, bigint
) set schema app;

alter function app.record_trusted_personal_diagnostic_v1(
  uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
  integer, bytea, bigint
) rename to record_trusted_personal_diagnostic_v1_unchecked;

create function public.record_trusted_personal_diagnostic_v1(
  p_user_id                     uuid,
  p_client_diagnostic_id        uuid,
  p_payload_digest              bytea,
  p_observed_at                 timestamptz,
  p_query_started_at            timestamptz,
  p_query_ended_at              timestamptz,
  p_trusted_device_sample_count integer,
  p_key_id                      bytea,
  p_sign_count                  bigint
)
returns table (
  diagnostic_id uuid,
  performed_at  timestamptz,
  replayed      boolean,
  cleared_hold  boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_existing public.personal_trusted_diagnostics;
begin
  perform public.assert_active_actor(p_user_id);

  select diagnostic.* into v_existing
  from public.personal_trusted_diagnostics diagnostic
  where diagnostic.user_id = p_user_id
    and diagnostic.client_diagnostic_id = p_client_diagnostic_id;

  if v_existing.id is not null
     and v_existing.key_id is distinct from p_key_id
  then
    raise exception 'diagnostic request UUID was already used by a different attestation key'
      using errcode = 'unique_violation';
  end if;

  return query
  select
    result.diagnostic_id,
    result.performed_at,
    result.replayed,
    result.cleared_hold
  from app.record_trusted_personal_diagnostic_v1_unchecked(
    p_user_id,
    p_client_diagnostic_id,
    p_payload_digest,
    p_observed_at,
    p_query_started_at,
    p_query_ended_at,
    p_trusted_device_sample_count,
    p_key_id,
    p_sign_count
  ) result;
end;
$$;

comment on function public.record_trusted_personal_diagnostic_v1(
  uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
  integer, bytea, bigint
) is
  'service_role-only fresh HealthKit/App-Attest diagnostic. Exact retries must use the original attestation key; new rows snapshot their App Attest environment.';

revoke all on function
  app.record_personal_sync_coverage_v1_unchecked(
    uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
  ),
  app.record_trusted_personal_diagnostic_v1_unchecked(
    uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
    integer, bytea, bigint
  )
from public, anon, authenticated, service_role;

revoke all on function
  public.record_metric_batch(
    uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
  ),
  public.record_personal_sync_coverage_v1(
    uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
  ),
  public.record_trusted_personal_diagnostic_v1(
    uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
    integer, bytea, bigint
  )
from public, anon, authenticated, service_role;

grant execute on function
  public.record_metric_batch(
    uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
  ),
  public.record_personal_sync_coverage_v1(
    uuid, uuid, uuid, bytea, timestamptz, jsonb, bytea, bigint
  ),
  public.record_trusted_personal_diagnostic_v1(
    uuid, uuid, bytea, timestamptz, timestamptz, timestamptz,
    integer, bytea, bigint
  )
to service_role;

-- A "complete" Personal V1 assessment is the production settlement boundary.
-- Reject the assessment if any evidence it would count came from a
-- development key or has unknown historical provenance. This is deliberately
-- fail-closed: mixed-origin evidence must be investigated rather than silently
-- producing a production result from contaminated totals or coverage counts.
create function app.require_production_personal_evidence_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.evidence_state <> 'complete' then
    return new;
  end if;

  if exists (
    select 1
    from public.ingest_batches batch
    where batch.contest_id = new.challenge_id
      and batch.user_id = new.user_id
      and batch.attestation_environment is distinct from 'production'
  ) then
    raise exception 'complete personal evidence requires production-origin metric batches'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from public.personal_sync_coverage_batches coverage
    where coverage.challenge_id = new.challenge_id
      and coverage.user_id = new.user_id
      and coverage.attestation_environment is distinct from 'production'
  ) then
    raise exception 'complete personal evidence requires production-origin coverage batches'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

comment on function app.require_production_personal_evidence_v1() is
  'Fail-closed insert guard: complete Personal V1 assessments may count only production-origin metric and coverage batches.';

create trigger personal_assessments_require_production_evidence
  before insert on app.personal_evidence_assessments
  for each row execute function app.require_production_personal_evidence_v1();

revoke all on function app.require_production_personal_evidence_v1()
  from public, anon, authenticated, service_role;
