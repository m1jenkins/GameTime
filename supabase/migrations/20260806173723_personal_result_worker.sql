-- Beta workstream 4 -- automatic Personal V1 result publication.
--
-- The worker deliberately stays inside Postgres. It shares the contest-row lock
-- used by final sync, assessment, and publication, then calls the already
-- protected public assessment/publication operations. No payment, social,
-- notification, or general job infrastructure is introduced here.

begin;

-- One bounded operational row per challenge makes partial worker failures
-- visible without retaining exception messages, stacks, payloads, or Health
-- data. This is mutable operational state, not a result or evidence ledger.
create table app.personal_result_worker_attempts (
  challenge_id        uuid primary key
    references public.contests (id) on delete restrict,
  attempt_count       bigint not null default 1,
  first_attempted_at  timestamptz not null,
  last_attempted_at   timestamptz not null,
  last_status         text not null,
  last_sqlstate       text,
  published_result_id uuid
    references public.personal_challenge_results (id) on delete restrict,

  constraint personal_result_worker_attempt_count_positive
    check (attempt_count > 0),
  constraint personal_result_worker_attempt_times_ordered
    check (
      pg_catalog.isfinite(first_attempted_at)
      and pg_catalog.isfinite(last_attempted_at)
      and first_attempted_at <= last_attempted_at
    ),
  constraint personal_result_worker_status_bounded
    check (last_status in ('published', 'failed')),
  constraint personal_result_worker_sqlstate_bounded
    check (
      last_sqlstate is null
      or (
        char_length(last_sqlstate) = 5
        and last_sqlstate ~ '^[0-9A-Z]{5}$'
      )
    ),
  constraint personal_result_worker_attempt_shape
    check (
      (
        last_status = 'published'
        and last_sqlstate is null
        and published_result_id is not null
      )
      or (
        last_status = 'failed'
        and last_sqlstate is not null
        and published_result_id is null
      )
    )
);

comment on table app.personal_result_worker_attempts is
  'Private bounded worker health state. Stores result ids and SQLSTATE categories only; never exception text, signed bodies, Health data, or credentials.';

alter table app.personal_result_worker_attempts enable row level security;

revoke all on table app.personal_result_worker_attempts
  from public, anon, authenticated, service_role;

-- The worker owns one deterministic request UUID per challenge. A SHA-256
-- namespace keeps it stable without adding uuid-ossp or accepting a caller
-- supplied idempotency key.
create function app.personal_result_worker_request_id_v1(
  p_challenge_id uuid
)
returns uuid
language sql
immutable
security definer
set search_path = ''
as $$
  with encoded as (
    select pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(
          'gametime:personal-result-worker:v1:' || p_challenge_id::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ) as value
  )
  select (
    pg_catalog.substr(encoded.value, 1, 8) || '-' ||
    pg_catalog.substr(encoded.value, 9, 4) || '-' ||
    pg_catalog.substr(encoded.value, 13, 4) || '-' ||
    pg_catalog.substr(encoded.value, 17, 4) || '-' ||
    pg_catalog.substr(encoded.value, 21, 12)
  )::uuid
  from encoded;
$$;

comment on function app.personal_result_worker_request_id_v1(uuid) is
  'Deterministic private idempotency UUID for one Personal V1 worker assessment per challenge.';

-- Classification is intentionally narrow. It auto-scores only an exact,
-- production-origin evidence set. Calendar overlap has an explicit platform
-- outage rule; contradictory local-day attribution is a durable conflict;
-- unresolved/rejected flags remain quarantined; missing hours remain missing;
-- and ambiguous provenance remains unresolved. The worker never infers
-- user_device_sync_failure because doing so would create an eligibility hold.
create function app.classify_personal_result_evidence_v1(
  p_challenge_id uuid
)
returns table (
  evidence_state   public.personal_evidence_state,
  outage_reference text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_missing boolean;
  v_extra   boolean;
begin
  if p_challenge_id is null
     or not exists (
       select 1
       from public.contests contest
       join public.personal_challenge_terms terms
         on terms.challenge_id = contest.id
       where contest.id = p_challenge_id
         and contest.challenge_model = 'personal_accountability'
     )
  then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  if app.personal_has_overlapping_coverage_v1(p_challenge_id) then
    return query
    select
      'gametime_outage'::public.personal_evidence_state,
      'calendar-overlap-personal-v1'::text;
    return;
  end if;

  if exists (
    select 1
    from public.contest_evidence evidence
    where evidence.contest_id = p_challenge_id
      and evidence.metric = 'steps'
    group by evidence.metric, evidence.bucket_start
    having count(*) > 1
  ) then
    return query
    select
      'conflicting'::public.personal_evidence_state,
      null::text;
    return;
  end if;

  if exists (
    select 1
    from public.evidence_quarantines quarantine
    left join app.personal_quarantine_resolutions resolution
      on resolution.quarantine_id = quarantine.id
    where quarantine.contest_id = p_challenge_id
      and (
        resolution.id is null
        or resolution.resolution = 'rejected'
      )
  ) then
    return query
    select
      'quarantined'::public.personal_evidence_state,
      null::text;
    return;
  end if;

  if exists (
    select 1
    from public.ingest_batches batch
    where batch.contest_id = p_challenge_id
      and (
        not batch.attested
        or batch.attestation_environment is distinct from 'production'
      )
  )
  or exists (
    select 1
    from public.personal_sync_coverage_batches coverage
    where coverage.challenge_id = p_challenge_id
      and coverage.attestation_environment is distinct from 'production'
  ) then
    return query
    select 'unresolved'::public.personal_evidence_state, null::text;
    return;
  end if;

  select exists (
    select 1
    from (
      select expected.bucket_start
      from app.personal_expected_coverage_buckets_v1(
        p_challenge_id,
        'infinity'::timestamptz
      ) expected
      except
      select coverage.bucket_start
      from public.personal_sync_coverage_buckets coverage
      where coverage.challenge_id = p_challenge_id
    ) difference
  ) into v_missing;

  if v_missing then
    return query
    select 'missing'::public.personal_evidence_state, null::text;
    return;
  end if;

  select exists (
    select 1
    from (
      select coverage.bucket_start
      from public.personal_sync_coverage_buckets coverage
      where coverage.challenge_id = p_challenge_id
      except
      select expected.bucket_start
      from app.personal_expected_coverage_buckets_v1(
        p_challenge_id,
        'infinity'::timestamptz
      ) expected
    ) difference
  ) into v_extra;

  if v_extra then
    return query
    select 'conflicting'::public.personal_evidence_state, null::text;
    return;
  end if;

  return query
  select 'complete'::public.personal_evidence_state, null::text;
end;
$$;

comment on function app.classify_personal_result_evidence_v1(uuid) is
  'Private fail-closed Personal V1 worker classifier. Exact production coverage with no unresolved conflict may score; the worker never infers user/device fault.';

-- Bind the frozen assessment to a canonical, privacy-minimized snapshot of the
-- exact terms, derived evidence, coverage, provenance, and flag decisions used
-- by the classifier. Ordered JSONB arrays avoid row-order-dependent digests.
create function app.personal_result_worker_evidence_digest_v1(
  p_challenge_id     uuid,
  p_evidence_state   public.personal_evidence_state,
  p_outage_reference text default null
)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'schema_version', 'personal-result-worker-input-v1',
        'challenge_id', contest.id::text,
        'owner_id', terms.user_id::text,
        'cadence', terms.cadence::text,
        'target_steps', terms.target_steps,
        'starts_at_us',
          (extract(epoch from contest.starts_at) * 1000000)::bigint,
        'ends_at_us',
          (extract(epoch from contest.ends_at) * 1000000)::bigint,
        'evidence_cutoff_us',
          (extract(epoch from terms.evidence_cutoff) * 1000000)::bigint,
        'evidence_state', p_evidence_state::text,
        'outage_reference', p_outage_reference,
        'expected_buckets', coalesce(
          (
            select pg_catalog.jsonb_agg(
              (extract(epoch from expected.bucket_start) * 1000000)::bigint
              order by expected.bucket_start
            )
            from app.personal_expected_coverage_buckets_v1(
              p_challenge_id,
              'infinity'::timestamptz
            ) expected
          ),
          '[]'::jsonb
        ),
        'covered_buckets', coalesce(
          (
            select pg_catalog.jsonb_agg(
              (extract(epoch from coverage.bucket_start) * 1000000)::bigint
              order by coverage.bucket_start
            )
            from (
              select distinct bucket.bucket_start
              from public.personal_sync_coverage_buckets bucket
              where bucket.challenge_id = p_challenge_id
            ) coverage
          ),
          '[]'::jsonb
        ),
        'admissible_steps', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_array(
                (extract(epoch from evidence.bucket_start) * 1000000)::bigint,
                pg_catalog.to_char(evidence.local_day, 'YYYY-MM-DD'),
                evidence.local_hour,
                evidence.value,
                evidence.sample_count,
                evidence.observation_count
              )
              order by
                evidence.bucket_start,
                evidence.local_day,
                evidence.local_hour
            )
            from public.contest_evidence evidence
            where evidence.contest_id = p_challenge_id
              and evidence.user_id = terms.user_id
              and evidence.metric = 'steps'
          ),
          '[]'::jsonb
        ),
        'metric_batches', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_array(
                batch.id::text,
                pg_catalog.encode(batch.payload_digest, 'hex'),
                batch.attested,
                coalesce(batch.attestation_environment::text, 'unknown')
              )
              order by batch.id
            )
            from public.ingest_batches batch
            where batch.contest_id = p_challenge_id
              and batch.user_id = terms.user_id
          ),
          '[]'::jsonb
        ),
        'coverage_batches', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_array(
                coverage.id::text,
                pg_catalog.encode(coverage.payload_digest, 'hex'),
                coverage.covered_bucket_count,
                coalesce(coverage.attestation_environment::text, 'unknown')
              )
              order by coverage.id
            )
            from public.personal_sync_coverage_batches coverage
            where coverage.challenge_id = p_challenge_id
              and coverage.user_id = terms.user_id
          ),
          '[]'::jsonb
        ),
        'quarantines', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_array(
                quarantine.id::text,
                quarantine.snapshot_id::text,
                quarantine.rule_version,
                quarantine.signal_key,
                coalesce(resolution.resolution::text, 'unresolved'),
                coalesce(
                  pg_catalog.encode(resolution.evidence_digest, 'hex'),
                  ''
                )
              )
              order by quarantine.id
            )
            from public.evidence_quarantines quarantine
            left join app.personal_quarantine_resolutions resolution
              on resolution.quarantine_id = quarantine.id
            where quarantine.contest_id = p_challenge_id
              and quarantine.user_id = terms.user_id
          ),
          '[]'::jsonb
        )
      )::text,
      'UTF8'
    ),
    'sha256'
  )
  from public.contests contest
  join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
  where contest.id = p_challenge_id
    and contest.challenge_model = 'personal_accountability';
$$;

comment on function app.personal_result_worker_evidence_digest_v1(
  uuid, public.personal_evidence_state, text
) is
  'SHA-256 of the ordered, privacy-minimized Personal V1 evidence snapshot used by the automatic result worker.';

-- Settle one challenge while holding the same parent-row lock used by final
-- coverage sync, assessment, and publication. Rechecking after that lock makes
-- a just-before-cutoff final sync visible and makes a just-after-cutoff sync
-- lose safely. Existing assessments are resumed rather than replaced.
create function app.publish_due_personal_result_v1(
  p_challenge_id uuid,
  p_now          timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner_id          uuid;
  v_status            public.contest_status;
  v_model             public.challenge_model;
  v_evidence_cutoff   timestamptz;
  v_existing_result   uuid;
  v_existing_assessment app.personal_evidence_assessments;
  v_assessment_id     uuid;
  v_request_id        uuid;
  v_evidence_state    public.personal_evidence_state;
  v_outage_reference  text;
  v_evidence_digest   bytea;
begin
  if p_challenge_id is null
     or p_now is null
     or not pg_catalog.isfinite(p_now)
  then
    raise exception 'challenge and finite worker time are required'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Profile is the repository-wide actor/deletion serialization lock. Metric
  -- and coverage ingress take it before the contest, and account deletion does
  -- too. Locking the retained profile row directly (rather than requiring an
  -- active auth binding) still lets a deleted account's retained challenge
  -- receive its service-owned terminal result.
  select terms.user_id into v_owner_id
  from public.personal_challenge_terms terms
  join public.profiles profile
    on profile.id = terms.user_id
  where terms.challenge_id = p_challenge_id
  for update of profile;

  if v_owner_id is null then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select contest.status, contest.challenge_model, terms.evidence_cutoff
    into v_status, v_model, v_evidence_cutoff
  from public.contests contest
  join public.personal_challenge_terms terms
    on terms.challenge_id = contest.id
  where contest.id = p_challenge_id
  for update of contest;

  if v_model is null or v_model <> 'personal_accountability' then
    raise exception 'personal challenge not found'
      using errcode = 'invalid_parameter_value';
  end if;

  select result.id into v_existing_result
  from public.personal_challenge_results result
  where result.challenge_id = p_challenge_id;

  if v_existing_result is not null then
    return v_existing_result;
  end if;

  if v_status <> 'active'
     or v_evidence_cutoff is null
     or p_now < v_evidence_cutoff
     or clock_timestamp() < v_evidence_cutoff
  then
    raise exception 'personal challenge is not due for automatic result'
      using errcode = 'restrict_violation';
  end if;

  select assessment.* into v_existing_assessment
  from app.personal_evidence_assessments assessment
  where assessment.challenge_id = p_challenge_id;

  select classified.evidence_state, classified.outage_reference
    into v_evidence_state, v_outage_reference
  from app.classify_personal_result_evidence_v1(p_challenge_id) classified;

  v_evidence_digest :=
    app.personal_result_worker_evidence_digest_v1(
      p_challenge_id,
      v_evidence_state,
      v_outage_reference
    );
  v_request_id := app.personal_result_worker_request_id_v1(p_challenge_id);

  if v_evidence_state is null
     or v_evidence_digest is null
     or v_request_id is null
  then
    raise exception 'personal worker could not freeze assessment input'
      using errcode = 'data_exception';
  end if;

  if v_existing_assessment.id is not null then
    if v_existing_assessment.request_id <> v_request_id
       or v_existing_assessment.evidence_state <> v_evidence_state
       or v_existing_assessment.evidence_cutoff <> v_evidence_cutoff
       or v_existing_assessment.assessment_version <> 'personal-v1'
       or v_existing_assessment.evidence_digest <> v_evidence_digest
       or v_existing_assessment.outage_reference
            is distinct from v_outage_reference
    then
      raise exception 'existing personal assessment does not match the worker snapshot'
        using errcode = 'restrict_violation';
    end if;

    v_assessment_id := v_existing_assessment.id;
  else
    v_assessment_id := public.record_personal_assessment_v1(
      p_challenge_id,
      v_request_id,
      v_evidence_state,
      'personal-v1',
      v_evidence_digest,
      v_outage_reference
    );
  end if;

  return public.publish_personal_result_v1(
    p_challenge_id,
    v_assessment_id
  );
end;
$$;

comment on function app.publish_due_personal_result_v1(uuid, timestamptz) is
  'Private one-challenge worker. Locks, classifies, records, and publishes through the protected Personal V1 boundaries in one transaction.';

-- A bounded sweep isolates each challenge in a PL/pgSQL subtransaction. One
-- malformed legacy assessment cannot block other due users, while its SQLSTATE
-- becomes a small private health signal for founder review.
create function app.run_personal_result_worker_at(
  p_now   timestamptz,
  p_limit integer
)
returns table (
  challenges_selected integer,
  results_published    integer,
  failures_recorded    integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_due          record;
  v_result_id    uuid;
  v_attempted_at timestamptz;
  v_sqlstate     text;
begin
  if p_now is null
     or not pg_catalog.isfinite(p_now)
     or p_limit is null
     or p_limit not between 1 and 100
  then
    raise exception 'finite worker time and limit from 1 through 100 are required'
      using errcode = 'invalid_parameter_value';
  end if;

  challenges_selected := 0;
  results_published := 0;
  failures_recorded := 0;

  for v_due in
    select contest.id
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    join public.profiles profile
      on profile.id = terms.user_id
    where contest.challenge_model = 'personal_accountability'
      and contest.status = 'active'
      and terms.evidence_cutoff <= p_now
      and not exists (
        select 1
        from public.personal_challenge_results result
        where result.challenge_id = contest.id
      )
    order by terms.evidence_cutoff, contest.id
    limit p_limit
    for update of profile skip locked
  loop
    challenges_selected := challenges_selected + 1;
    v_attempted_at := clock_timestamp();

    begin
      v_result_id := app.publish_due_personal_result_v1(
        v_due.id,
        p_now
      );

      insert into app.personal_result_worker_attempts as attempt (
        challenge_id,
        attempt_count,
        first_attempted_at,
        last_attempted_at,
        last_status,
        last_sqlstate,
        published_result_id
      )
      values (
        v_due.id,
        1,
        v_attempted_at,
        v_attempted_at,
        'published',
        null,
        v_result_id
      )
      on conflict (challenge_id) do update
      set attempt_count = attempt.attempt_count + 1,
          last_attempted_at = excluded.last_attempted_at,
          last_status = excluded.last_status,
          last_sqlstate = null,
          published_result_id = excluded.published_result_id;

      results_published := results_published + 1;
    exception
      when others then
        get stacked diagnostics v_sqlstate = returned_sqlstate;

        insert into app.personal_result_worker_attempts as attempt (
          challenge_id,
          attempt_count,
          first_attempted_at,
          last_attempted_at,
          last_status,
          last_sqlstate,
          published_result_id
        )
        values (
          v_due.id,
          1,
          v_attempted_at,
          v_attempted_at,
          'failed',
          v_sqlstate,
          null
        )
        on conflict (challenge_id) do update
        set attempt_count = attempt.attempt_count + 1,
            last_attempted_at = excluded.last_attempted_at,
            last_status = excluded.last_status,
            last_sqlstate = excluded.last_sqlstate,
            published_result_id = null;

        failures_recorded := failures_recorded + 1;
    end;
  end loop;

  return next;
end;
$$;

create function app.run_personal_result_worker()
returns table (
  challenges_selected integer,
  results_published    integer,
  failures_recorded    integer
)
language sql
volatile
security definer
set search_path = ''
as $$
  select *
  from app.run_personal_result_worker_at(
    clock_timestamp(),
    10
  );
$$;

comment on function app.run_personal_result_worker_at(timestamptz, integer) is
  'Private bounded Personal V1 due-result sweep with SKIP LOCKED concurrency and per-challenge failure isolation.';

comment on function app.run_personal_result_worker() is
  'Five-minute Personal V1 cron entry point. Publishes due immutable results and records privacy-safe failure categories.';

-- One aggregate row is sufficient for a daily founder check. It reveals no
-- user identity or Health value. Fifteen minutes gives the five-minute worker
-- three ordinary opportunities before a result is considered overdue.
create function app.personal_result_worker_health_v1(
  p_now timestamptz default clock_timestamp()
)
returns table (
  scheduler_configured    boolean,
  scheduler_active        boolean,
  due_challenges          bigint,
  overdue_challenges      bigint,
  current_failures        bigint,
  oldest_overdue_cutoff   timestamptz,
  last_attempt_at         timestamptz,
  last_failure_at         timestamptz,
  last_failure_sqlstate   text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_now is null or not pg_catalog.isfinite(p_now) then
    raise exception 'finite health-check time is required'
      using errcode = 'invalid_parameter_value';
  end if;

  return query
  with due as (
    select contest.id, terms.evidence_cutoff
    from public.contests contest
    join public.personal_challenge_terms terms
      on terms.challenge_id = contest.id
    where contest.challenge_model = 'personal_accountability'
      and contest.status = 'active'
      and terms.evidence_cutoff <= p_now
      and not exists (
        select 1
        from public.personal_challenge_results result
        where result.challenge_id = contest.id
      )
  ),
  current_failure as (
    select attempt.last_attempted_at, attempt.last_sqlstate
    from app.personal_result_worker_attempts attempt
    join due on due.id = attempt.challenge_id
    where attempt.last_status = 'failed'
  ),
  latest_failure as (
    select
      failure.last_attempted_at,
      failure.last_sqlstate
    from current_failure failure
    order by failure.last_attempted_at desc
    limit 1
  )
  select
    exists (
      select 1
      from cron.job job
      where job.jobname = 'gametime-publish-personal-results'
    ),
    exists (
      select 1
      from cron.job job
      where job.jobname = 'gametime-publish-personal-results'
        and job.active
    ),
    (select count(*) from due),
    (
      select count(*)
      from due
      where due.evidence_cutoff <= p_now - interval '15 minutes'
    ),
    (select count(*) from current_failure),
    (
      select min(due.evidence_cutoff)
      from due
      where due.evidence_cutoff <= p_now - interval '15 minutes'
    ),
    (
      select max(attempt.last_attempted_at)
      from app.personal_result_worker_attempts attempt
    ),
    (select latest_failure.last_attempted_at from latest_failure),
    (select latest_failure.last_sqlstate from latest_failure);
end;
$$;

comment on function app.personal_result_worker_health_v1(timestamptz) is
  'Private aggregate daily check: schedule configured/enabled, due/overdue counts, current failures, and latest SQLSTATE only.';

revoke all on function
  app.personal_result_worker_request_id_v1(uuid),
  app.classify_personal_result_evidence_v1(uuid),
  app.personal_result_worker_evidence_digest_v1(
    uuid, public.personal_evidence_state, text
  ),
  app.publish_due_personal_result_v1(uuid, timestamptz),
  app.run_personal_result_worker_at(timestamptz, integer)
from public, anon, authenticated, service_role;

revoke all on function
  app.run_personal_result_worker(),
  app.personal_result_worker_health_v1(timestamptz)
from public, anon, authenticated, service_role;

grant execute on function
  app.run_personal_result_worker(),
  app.personal_result_worker_health_v1(timestamptz)
to service_role;

-- Do not silently adopt an assessment created before this worker's classifier,
-- digest, and deterministic request identity existed. An operator must audit or
-- finish any such row before scheduling automatic irreversible publication.
do $$
begin
  if exists (
    select 1
    from app.personal_evidence_assessments assessment
    join public.contests contest
      on contest.id = assessment.challenge_id
    left join public.personal_challenge_results result
      on result.assessment_id = assessment.id
    where contest.challenge_model = 'personal_accountability'
      and result.id is null
  ) then
    raise exception 'unpublished Personal V1 assessments require an operator audit before enabling the automatic result worker'
      using errcode = 'check_violation';
  end if;
end;
$$;

-- Supabase's current Cron guidance requires scheduler changes through
-- cron.schedule/alter_job rather than direct writes to cron.job. Register the
-- reviewed five-minute configuration but keep it dormant. Hosted activation is
-- a separate, approval-gated operation after migration review and smoke-test
-- preparation; applying this migration alone can never publish a result.
select cron.schedule(
  'gametime-publish-personal-results',
  '*/5 * * * *',
  'select app.run_personal_result_worker();'
);

select cron.alter_job(job.jobid, active := false)
from cron.job job
where job.jobname = 'gametime-publish-personal-results';

commit;
