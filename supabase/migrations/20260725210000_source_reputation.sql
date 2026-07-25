-- M5: expose current M3 source metadata to the integrity sidecar without
-- changing the one M4 scoring view or the generated admissibility invariant.

-- One row per current admissible provenance contribution. `contest_evidence`
-- deliberately combines device and third-party values into the number M4
-- scores; this parallel view preserves the provenance and bundle identifier M5
-- judges. It never filters `contest_evidence` or writes `is_admissible`.
--
-- Revisions need the same care as scoring. The current contribution is the
-- largest value for one provenance and bucket. Identical retry observations
-- collapse to one source row. If equally current observations disagree about
-- their bundle identifier, the honest answer is NULL (missing attribution),
-- not an arbitrary winner.
create view public.contest_evidence_sources
with (security_invoker = true)
as
with current_per_provenance as (
  select
    contest_id,
    user_id,
    metric,
    bucket_start,
    local_day,
    local_hour,
    provenance,
    max(value) as value
  from public.metric_snapshots
  where is_admissible
  group by
    contest_id,
    user_id,
    metric,
    bucket_start,
    local_day,
    local_hour,
    provenance
)
select
  current_source.contest_id,
  current_source.user_id,
  current_source.metric,
  current_source.bucket_start,
  current_source.local_day,
  current_source.local_hour,
  current_source.provenance,
  case
    when bool_and(snapshot.source_bundle_id is not null)
         and count(distinct snapshot.source_bundle_id) = 1
      then min(snapshot.source_bundle_id)
    else null
  end as source_bundle_id,
  current_source.value
from current_per_provenance current_source
join public.metric_snapshots snapshot
  on snapshot.contest_id = current_source.contest_id
 and snapshot.user_id = current_source.user_id
 and snapshot.metric = current_source.metric
 and snapshot.bucket_start = current_source.bucket_start
 and snapshot.local_day = current_source.local_day
 and snapshot.local_hour = current_source.local_hour
 and snapshot.provenance = current_source.provenance
 and snapshot.value = current_source.value
where snapshot.is_admissible
group by
  current_source.contest_id,
  current_source.user_id,
  current_source.metric,
  current_source.bucket_start,
  current_source.local_day,
  current_source.local_hour,
  current_source.provenance,
  current_source.value;

comment on view public.contest_evidence_sources is
  'Current admissible provenance and source bundle metadata for M5 integrity assessment.';

-- Match the evidence ledger: signed-in participants may read only rows the
-- underlying metric_snapshots RLS policy permits. `security_invoker` above is
-- load-bearing; without it, the migration owner would bypass that policy.
revoke all on public.contest_evidence_sources from public, anon, authenticated;
grant select on public.contest_evidence_sources to authenticated;
