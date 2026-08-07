-- Close the two settlement paths that can legitimately skip a new assessment
-- INSERT: an exact assessment retry and publication of an assessment recorded
-- before provenance snapshots existed.

create function app.assert_production_personal_evidence_v1(
  p_challenge_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.ingest_batches batch
    where batch.contest_id = p_challenge_id
      and batch.user_id = p_user_id
      and batch.attestation_environment is distinct from 'production'
  ) then
    raise exception 'complete personal evidence requires production-origin metric batches'
      using errcode = 'restrict_violation';
  end if;

  if exists (
    select 1
    from public.personal_sync_coverage_batches coverage
    where coverage.challenge_id = p_challenge_id
      and coverage.user_id = p_user_id
      and coverage.attestation_environment is distinct from 'production'
  ) then
    raise exception 'complete personal evidence requires production-origin coverage batches'
      using errcode = 'restrict_violation';
  end if;
end;
$$;

comment on function app.assert_production_personal_evidence_v1(uuid, uuid) is
  'Raises unless every metric and coverage batch that Personal V1 settlement would count has durable production App Attest provenance.';

create or replace function app.require_production_personal_evidence_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.evidence_state = 'complete' then
    perform app.assert_production_personal_evidence_v1(
      new.challenge_id,
      new.user_id
    );
  end if;

  return new;
end;
$$;

alter function public.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) set schema app;

alter function app.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) rename to record_personal_assessment_v1_unchecked;

create function public.record_personal_assessment_v1(
  p_challenge_id       uuid,
  p_request_id         uuid,
  p_evidence_state     public.personal_evidence_state,
  p_assessment_version text,
  p_evidence_digest    bytea,
  p_outage_reference   text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if p_challenge_id is null
     or p_request_id is null
     or p_evidence_state is null
     or p_assessment_version <> 'personal-v1'
     or p_evidence_digest is null
     or octet_length(p_evidence_digest) <> 32
  then
    raise exception 'personal-v1 assessment identity, state, version, and SHA-256 digest are required'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_evidence_state = 'complete' then
    select contest.created_by
      into v_user_id
    from public.contests contest
    where contest.id = p_challenge_id;

    if v_user_id is not null then
      perform app.assert_production_personal_evidence_v1(
        p_challenge_id,
        v_user_id
      );
    end if;
  end if;

  return app.record_personal_assessment_v1_unchecked(
    p_challenge_id,
    p_request_id,
    p_evidence_state,
    p_assessment_version,
    p_evidence_digest,
    p_outage_reference
  );
end;
$$;

comment on function public.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) is
  'service_role-only immutable personal-v1 assessment. Complete initial calls and exact retries both require production-origin metric and coverage evidence.';

create function app.require_production_personal_result_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment app.personal_evidence_assessments;
begin
  select assessment.* into v_assessment
  from app.personal_evidence_assessments assessment
  where assessment.id = new.assessment_id;

  if v_assessment.evidence_state = 'complete' then
    perform app.assert_production_personal_evidence_v1(
      v_assessment.challenge_id,
      v_assessment.user_id
    );
  end if;

  return new;
end;
$$;

comment on function app.require_production_personal_result_v1() is
  'Prevents publication of a legacy complete Personal V1 assessment when its counted evidence has development or unknown App Attest provenance.';

create trigger personal_results_require_production_evidence
  before insert on public.personal_challenge_results
  for each row execute function app.require_production_personal_result_v1();

-- Already-published results cannot be silently repaired without rewriting an
-- append-only settlement record. Refuse this migration if one is found so an
-- operator must audit it explicitly before rollout.
do $$
begin
  if exists (
    select 1
    from public.personal_challenge_results result
    join app.personal_evidence_assessments assessment
      on assessment.id = result.assessment_id
    where assessment.evidence_state = 'complete'
      and (
        exists (
          select 1
          from public.ingest_batches batch
          where batch.contest_id = assessment.challenge_id
            and batch.user_id = assessment.user_id
            and batch.attestation_environment is distinct from 'production'
        )
        or exists (
          select 1
          from public.personal_sync_coverage_batches coverage
          where coverage.challenge_id = assessment.challenge_id
            and coverage.user_id = assessment.user_id
            and coverage.attestation_environment is distinct from 'production'
        )
      )
  ) then
    raise exception 'existing published Personal V1 result depends on non-production or unknown attestation provenance; audit before migration'
      using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function
  app.assert_production_personal_evidence_v1(uuid, uuid),
  app.require_production_personal_evidence_v1(),
  app.require_production_personal_result_v1(),
  app.record_personal_assessment_v1_unchecked(
    uuid, uuid, public.personal_evidence_state, text, bytea, text
  )
from public, anon, authenticated, service_role;

revoke all on function public.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) from public, anon, authenticated, service_role;

grant execute on function public.record_personal_assessment_v1(
  uuid, uuid, public.personal_evidence_state, text, bytea, text
) to service_role;
