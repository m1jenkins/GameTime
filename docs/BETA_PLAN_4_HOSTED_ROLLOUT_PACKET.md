# Beta Plan 4 hosted rollout packet

**Prepared:** August 6, 2026

**Read-only hosted checks completed through:** August 6, 2026 at 19:16 CDT

**Scope:** the four pending production-App-Attest migrations and the pending
Personal result-worker migration only

**Source checkpoint note:** the five migration artifacts and this packet are
now intended to be tracked together on local `main`. That removes the
untracked-file risk described in the original 19:16 CDT snapshot, but it does
not authorize hosted application, function deployment, smoke data, or Cron
activation. The hashes and every remaining gate below still control.

## Founder decision

**NO-GO for migration application and NO-GO for Cron activation today.**

The read-only hosted data inventory found no current row-level blocker: the
linked project is healthy, its migration ledger stops immediately before the
five candidate files, the future worker job name is unused, and the hosted
project currently has no Personal evidence, assessment, result, due challenge,
or cleared-hold row that would block these migrations. This is not the final
preflight because the authenticated CLI dry run, schema-drift check, frozen
artifact review, and approvals remain open.

The rollout is still not ready because:

1. The five migration files need one frozen reviewed source revision and named
   owner approval before any hosted dry run or application.
2. The fourth migration has been regenerated as a forward production-diagnostic
   clearance guard. Its prior duplicate settlement assertion was rejected; the
   new artifact and focused regression still need local proof and owner review.
3. The currently deployed `ingest-metrics`, `personal-sync-coverage`, and
   `activity-diagnostic` functions do not contain the working-tree
   App-Attest-environment filter. Migration 4 now also blocks a future
   development-origin diagnostic at the database hold-clearance boundary, but
   the exact hosted function bundles remain a separate deployment dependency.
4. No approved, isolated hosted smoke dataset exists for the required met,
   missed, and inconclusive result publications.
5. No approval has been given to apply migrations, publish immutable smoke
   results, or activate Cron.

This document is an operator packet, not authorization. No migration, Cron,
secret, hosted-data, deployment, Git, Apple, or TestFlight change was made while
preparing it.

## Locked rollout boundary

Only these five migration files belong to this packet, in this order:

| Order | Migration | SHA-256 | Immediate effect when applied |
|---:|---|---|---|
| 1 | [`20260806143539_production_attestation_provenance.sql`](../supabase/migrations/20260806143539_production_attestation_provenance.sql) | `e6b69f0e187ffbeac14e8a10aef02536998135fd61ceab3b617db5c3debad27d` | Adds and backfills durable App Attest provenance, replaces three service RPC boundaries, and begins rejecting non-production evidence for complete Personal assessments. This migration is not dormant. |
| 2 | [`20260806144639_production_attestation_settlement_guards.sql`](../supabase/migrations/20260806144639_production_attestation_settlement_guards.sql) | `7c8c862a3ea8cdd0dad3451a03223c4be909b9454699fdc33e66f6ee3d5e6255` | Closes exact-assessment-retry and legacy-publication gaps. It aborts if an existing complete published result depends on development or unknown provenance. |
| 3 | [`20260806145058_production_diagnostic_provenance_audit.sql`](../supabase/migrations/20260806145058_production_diagnostic_provenance_audit.sql) | `0dcee03581b4b332f57213b34bb22107aadaf7e7636c9b13a53b516f3f508339` | One-time audit only. It aborts if an existing hold was cleared by a development or unknown diagnostic. It installs no forward diagnostic guard. |
| 4 | [`20260806145502_production_diagnostic_clearance_guard.sql`](../supabase/migrations/20260806145502_production_diagnostic_clearance_guard.sql) | `a34c354b58d6de6401462a46632a3e5c5ede65e0fdb5bc0b3944ffd12220478d` | Installs the forward production-provenance guard for diagnostic hold clearance, then repeats only the narrow historical diagnostic audit in the same transaction to close the migration 3-to-4 race window. |
| 5 | [`20260806173723_personal_result_worker.sql`](../supabase/migrations/20260806173723_personal_result_worker.sql) | `b67ee1a6d2efec98d8638094f289d8604d4985afc4952bdfd10ccd8043bcd27f` | Adds the private worker, health state, and one named five-minute Cron job. The job is created inactive in the same transaction. The migration aborts if any Personal assessment lacks a result. |

Any byte change creates a new artifact and invalidates this packet's hashes and
approval. Do not use `--include-all`, `--include-seed`, migration repair, or a
broader migration directory without a new review.

This packet and its hash manifest were regenerated after rejecting migration
4's duplicated retained-batch settlement guard. Any later filename or byte
change requires another packet, dry-run manifest, and approval review.

The worker remains inside Postgres. It does not need Vault, an Edge Function,
an HTTP endpoint, or a new secret. It can publish a complete missed result,
which may open the existing Stripe sandbox review when a matching sandbox
agreement exists, but it never creates a charge command itself.

## What the five migrations actually protect

### Production App Attest predecessors

Migration 1 snapshots `development` or `production` onto every retained metric,
coverage, and trusted-diagnostic record. An unmatched historical key remains
unknown and fails closed. It also prevents an exact request UUID from being
adopted by a different App Attest key.

Migrations 1 and 2 ensure that both new and retried complete assessments, plus
publication of an older complete assessment, require production-origin metric
and coverage evidence.

Migration 3 checks historical diagnostic-based hold clearances. Migration 4
installs the forward database invariant: an eligibility hold may be cleared only
by a diagnostic with durable production provenance. It repeats the narrow
diagnostic audit after trigger installation so a clearance between migrations 3
and 4 cannot escape both checks. The Edge environment filter remains required
at ingestion so development evidence is refused before it reaches storage.

### Personal result worker

The worker:

- selects at most 10 active Personal challenges whose 24-hour evidence cutoff
  has passed;
- locks in the same profile-then-contest order used by final sync and deletion;
- classifies complete production evidence, missing evidence, quarantine,
  conflict, unknown provenance, and GameTime calendar overlap fail closed;
- never guesses `user_device_sync_failure`;
- creates one deterministic assessment request per challenge;
- publishes at most one immutable result through the existing protected
  assessment and publication operations;
- skips already-published results and retries only unresolved failures;
- isolates one challenge's failure from the rest of the batch;
- stores only challenge/result IDs, counts, timestamps, status, and
  five-character SQLSTATE categories in private worker health state;
- creates no Social result, standing, donation obligation, or charge command.

Its only service-role entry points are:

```sql
app.run_personal_result_worker()
app.personal_result_worker_health_v1(timestamptz)
```

All narrower helper functions are private. Every new privileged function uses
`SECURITY DEFINER`, pins `search_path = ''`, and is explicitly revoked from
public application roles. `service_role` is the only explicitly granted
non-owner application role for the two operator entry points; the function owner
and database superusers retain their normal database authority.

## Evidence boundary

Passing this packet would prove only the five-migration application, automatic
Personal result behavior, worker scheduling, and its narrow hosted smoke.

It would not prove or close the beta plan's separate sandbox review-decision,
signed webhook, simulated-settlement, physical-device, production App Attest
request, account-deletion, TestFlight, or external-invitation gates.

## Confirmed linked project and hosted state

### Project identity

The repository link files and the authenticated read-only Supabase project list
agree on:

| Field | Confirmed value |
|---|---|
| Project reference | `jrkzdttophnmkxjoyioo` |
| Organization | `nfokjrpuwftlmvfrathp` |
| Region | `ca-central-1` |
| Database host | `db.jrkzdttophnmkxjoyioo.supabase.co` |
| Database release | Postgres `17.6.1.147`, engine 17 |
| Platform status | `ACTIVE_HEALTHY` |

The technical identity is confirmed. The dashboard label is generic and does
not prove that this is the intended non-production Stripe-sandbox beta target.
The owner must explicitly approve that purpose before any write.

### Hosted migration and Cron state

Read-only checks returned:

| Check | Current hosted value |
|---|---:|
| Applied migrations | 29 |
| Latest migration | `20260805131357_personal_stripe_sandbox_foundation` |
| Exact five packet migrations applied | 0 |
| Existing Cron jobs | 4, all active |
| `gametime-publish-personal-results` job | Absent |
| Unpublished Personal assessments | 0 |
| Active due Personal challenges without a result | 0 |
| Published Personal results | 0 |
| Published complete results blocked by provenance | 0 |
| Cleared eligibility holds | 0 |
| Cleared holds blocked by diagnostic provenance | 0 |
| Retained metric batches | 0 |
| Personal coverage batches | 0 |
| Personal trusted diagnostics | 0 |
| Pending-object schema collisions checked by this packet | 0 |

The four existing jobs are:

- `gametime-activate-due-contests`
- `gametime-dispatch-push`
- `gametime-process-quarantine-review-deadlines`
- `gametime-prune-raw-evidence`

The Supabase CLI is version `2.109.1` and supports `db push --dry-run`. The CLI
could not perform the linked dry run in this session because no CLI access token
was available. No token was requested or set. The authenticated read-only
Supabase connection independently confirmed the project and all 29 migration
records.

### Hosted App Attest dependency

The currently deployed functions are active at:

| Function | Hosted version | Hosted bundle SHA-256 |
|---|---:|---|
| `ingest-metrics` | 41 | `ad0bf531b45149af739a835a406d5fb49b38f5651e786a87787425637225e128` |
| `personal-sync-coverage` | 9 | `bb189e7b1e4822f4d252cf6c852973d07cb6d78c644a183059be43bb5e831d3a` |
| `activity-diagnostic` | 9 | `a037bce8570e4de58ee1d3b3a862c55ba03e61c9f12bda03e025296d8bcff1ac` |

Their deployed entry points call `deviceKeyLookup(dataApi)` without an allowed
environment. The local working tree has changed that boundary to
`deviceKeyLookup(dataApi, allowedEnvironments)`.

This remains a hard beta-trust gate. Migration 4 now prevents a development or
unknown diagnostic from clearing eligibility even if a stale function accepts
it, but the hosted functions must still refuse the wrong environment at their
public assertion boundary. The exact production-environment-filtering bundles
must be reviewed, deployed, and verified separately. This packet does not
authorize that deployment.

## Gate 1 — freeze and local proof

Before requesting hosted application approval:

- [ ] Name an owner for each of the five untracked files.
- [x] Reject migration 4's duplicated settlement guard and regenerate it as the
      forward production-diagnostic clearance invariant.
- [ ] Recompute and record all five SHA-256 hashes only after the exact ordered
      five-file set is accepted.
- [ ] Confirm the repository contains no sixth pending migration.
- [ ] In the trust lane, run
      [`320_personal_v1_evidence_retention_isolation.test.sql`](../supabase/tests/320_personal_v1_evidence_retention_isolation.test.sql)
      and
      [`420_production_attestation_provenance.test.sql`](../supabase/tests/420_production_attestation_provenance.test.sql).
- [ ] Only after the trust lane is frozen, Prompt 4 separately owns
      [`430_personal_result_worker.test.sql`](../supabase/tests/430_personal_result_worker.test.sql)
      and
      [`431_personal_result_worker_concurrency.test.sql`](../supabase/tests/431_personal_result_worker_concurrency.test.sql).
- [ ] Run the existing full local database/backend regression gate only when
      local Supabase stack ownership is established.
- [ ] Freeze one reviewed source revision. Do not treat untracked files as a
      deployable release artifact.
- [ ] Confirm the exact production-environment-filtering hosted function
      dependency has been resolved.

The hosted pgTAP files are not a smoke-test script. They insert synthetic Auth
users, disable triggers, use privileged cross-session setup, and delete fixtures.
Never run them against the linked hosted project.

## Gate 2 — final read-only preflight

Run these checks again in one quiet operator window immediately before any
application. No manual Personal assessment or result operation may run between
this preflight and the migration command.

### Identity, history, and exact dry run

```sh
/usr/bin/env DO_NOT_TRACK=1 supabase migration list --linked
/usr/bin/env DO_NOT_TRACK=1 supabase db push --linked --dry-run
shasum -a 256 \
  supabase/migrations/20260806143539_production_attestation_provenance.sql \
  supabase/migrations/20260806144639_production_attestation_settlement_guards.sql \
  supabase/migrations/20260806145058_production_diagnostic_provenance_audit.sql \
  supabase/migrations/20260806145502_production_diagnostic_clearance_guard.sql \
  supabase/migrations/20260806173723_personal_result_worker.sql
```

Required result:

- the linked reference is exactly `jrkzdttophnmkxjoyioo`;
- the remote tail is exactly `20260805131357`;
- the dry run lists exactly the five frozen files in this packet and nothing
  else;
- every hash matches the approved manifest.

Stop if the operator cannot authenticate the CLI safely. Do not paste or print
the access token in the packet, terminal transcript, or approval record.

### Hosted schema-drift gate

A clean migration ledger does not rule out a manually created object. Check the
main collision points before application:

```sql
select table_schema, table_name, column_name
from information_schema.columns
where column_name = 'attestation_environment'
  and (table_schema, table_name) in (
    ('public', 'ingest_batches'),
    ('public', 'personal_sync_coverage_batches'),
    ('public', 'personal_trusted_diagnostics')
  );

select
  to_regclass('app.personal_result_worker_attempts')
    as worker_attempts_table,
  to_regprocedure('app.snapshot_attestation_environment_v1()')
    as provenance_snapshot_function,
  to_regprocedure(
    'app.assert_production_personal_evidence_v1(uuid,uuid)'
  ) as production_assertion_function,
  to_regprocedure(
    'app.require_production_personal_diagnostic_clearance_v1()'
  ) as production_diagnostic_clearance_function,
  to_regprocedure('app.personal_result_worker_request_id_v1(uuid)')
    as worker_request_function,
  to_regprocedure('app.run_personal_result_worker()')
    as worker_run_function,
  to_regprocedure(
    'app.personal_result_worker_health_v1(timestamp with time zone)'
  ) as worker_health_function;

select tgname
from pg_trigger
where not tgisinternal
  and tgname in (
    'ingest_batches_snapshot_attestation_environment',
    'personal_coverage_snapshot_attestation_environment',
    'personal_diagnostics_snapshot_attestation_environment',
    'personal_assessments_require_production_evidence',
    'personal_results_require_production_evidence',
    'personal_holds_require_production_diagnostic'
  );
```

Expected before migration 1: the column and trigger queries return zero rows,
and every `to_regclass`/`to_regprocedure` value is null. Any collision or
unexpected partial object is a hard stop requiring a new schema review.

### Cron collision and unpublished-assessment gate

```sql
select jobid, jobname, schedule, active
from cron.job
where jobname = 'gametime-publish-personal-results';

select count(*) as unpublished_personal_assessments
from app.personal_evidence_assessments assessment
join public.contests contest
  on contest.id = assessment.challenge_id
left join public.personal_challenge_results result
  on result.assessment_id = assessment.id
where contest.challenge_model = 'personal_accountability'
  and result.id is null;

select count(*) as due_personal_challenges_without_result
from public.contests contest
join public.personal_challenge_terms terms
  on terms.challenge_id = contest.id
where contest.challenge_model = 'personal_accountability'
  and contest.status = 'active'
  and terms.evidence_cutoff <= clock_timestamp()
  and not exists (
    select 1
    from public.personal_challenge_results result
    where result.challenge_id = contest.id
  );
```

Required result before application:

- zero job-name collisions;
- zero unpublished assessments;
- every due challenge, if the count has drifted above zero, is privately audited
  before proceeding.

Any unpublished assessment is a hard stop. Do not delete, rewrite, or silently
adopt it. Resolve it through a separately reviewed operator decision.

### Legacy published-result provenance

The new provenance columns do not exist before migration 1, so the preflight
must resolve each retained key against `device_attestations`:

```sql
select
  count(*) as published_complete_results,
  count(*) filter (
    where exists (
      select 1
      from public.ingest_batches batch
      left join public.device_attestations device
        on device.key_id = batch.key_id
      where batch.contest_id = assessment.challenge_id
        and batch.user_id = assessment.user_id
        and device.environment is distinct from 'production'
    )
    or exists (
      select 1
      from public.personal_sync_coverage_batches coverage
      left join public.device_attestations device
        on device.key_id = coverage.key_id
      where coverage.challenge_id = assessment.challenge_id
        and coverage.user_id = assessment.user_id
        and device.environment is distinct from 'production'
    )
  ) as blocking_results
from public.personal_challenge_results result
join app.personal_evidence_assessments assessment
  on assessment.id = result.assessment_id
where assessment.evidence_state = 'complete';
```

`blocking_results` must be zero.

### Historical diagnostic-clearance provenance

```sql
select
  count(*) filter (where hold.cleared_at is not null) as cleared_holds,
  count(*) filter (
    where hold.cleared_at is not null
      and device.environment is distinct from 'production'
  ) as blocking_clearances
from public.personal_eligibility_holds hold
join public.personal_trusted_diagnostics diagnostic
  on diagnostic.id = hold.cleared_by_diagnostic_id
left join public.device_attestations device
  on device.key_id = diagnostic.key_id;
```

`blocking_clearances` must be zero.

### Backfill inventory

Record aggregate production, development, and unknown counts for all three
tables. Do not export row bodies or user identities.

```sql
select 'metric' as source,
  count(*) as rows_total,
  count(*) filter (where device.environment = 'production') as production_rows,
  count(*) filter (where device.environment = 'development') as development_rows,
  count(*) filter (where device.key_id is null) as unknown_rows
from public.ingest_batches batch
left join public.device_attestations device
  on device.key_id = batch.key_id
union all
select 'coverage',
  count(*),
  count(*) filter (where device.environment = 'production'),
  count(*) filter (where device.environment = 'development'),
  count(*) filter (where device.key_id is null)
from public.personal_sync_coverage_batches coverage
left join public.device_attestations device
  on device.key_id = coverage.key_id
union all
select 'diagnostic',
  count(*),
  count(*) filter (where device.environment = 'production'),
  count(*) filter (where device.environment = 'development'),
  count(*) filter (where device.key_id is null)
from public.personal_trusted_diagnostics diagnostic
left join public.device_attestations device
  on device.key_id = diagnostic.key_id;
```

Recheck table size and active locks if any count is no longer zero. Use a quiet
window because migration 1 alters and scans these tables and temporarily
disables their append-only guards inside its migration transaction.

Also record only aggregate before-counts for assessments, results, reviews,
charge commands, holds, and due challenges. Never record Health values, daily
totals, signed bodies, assertions, tokens, keys, receipts, private profiles, or
provider credentials.

## Gate 3 — dormant migration application

This is a future **WRITE** step requiring explicit database-owner approval.

Applying the five migrations is not operationally inert. The first four alter
schema, backfill provenance, move/replace privileged functions, and immediately
tighten assessment/publication behavior. Only the Cron schedule is dormant.

After every Gate 1 and Gate 2 item is green, the approved operator may apply
only the exact dry-run manifest:

```sh
/usr/bin/env DO_NOT_TRACK=1 supabase db push --linked
```

Do not add `--include-all`, `--include-seed`, or `--include-roles`.

### Partial-application rule

Each migration may be committed before the next begins. If any file fails:

1. stop immediately;
2. re-read hosted migration history and identify exactly which versions applied;
3. keep Cron inactive;
4. do not rerun blindly;
5. do not use migration repair;
6. do not drop the new columns, move functions back, disable guards, or rewrite
   hosted rows;
7. prepare a separately reviewed forward fix or approved restore decision.

### Dormant post-application verification

Before any manual worker call, require:

```sql
select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 5;

select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'gametime-publish-personal-results';

select *
from app.personal_result_worker_health_v1(clock_timestamp());

select count(*) as worker_attempt_rows
from app.personal_result_worker_attempts;
```

Expected:

- the exact five approved versions are the newest five migration records;
- exactly one worker job exists;
- schedule is `*/5 * * * *`;
- command is `select app.run_personal_result_worker();`;
- `active = false`;
- health reports `scheduler_configured = true` and
  `scheduler_active = false`;
- worker attempt count is zero;
- Personal assessment, result, review, charge-command, and hold counts did not
  change merely because the migrations were applied;
- provenance backfill counts match the preflight key/environment mapping;
- no Cron run exists for the dormant worker job;
- only `service_role` can execute the two public operator surfaces, while
  unchecked/internal functions remain inaccessible.

An active job, worker attempt, or result created during dormant application is a
hard stop.

## Gate 4 — controlled manual hosted smoke

This is a separate future **HOSTED DATA WRITE** step. It publishes append-only
Personal results and requires explicit data-owner approval.

Keep Cron inactive throughout the smoke.

The `app` schema is private and not exposed through the Data API. A
`service_role` API key does not make these functions available through a normal
client RPC. Run smoke and monitoring only through an approved direct-Postgres
or Supabase SQL Editor session, record the acting database role, and never paste
credentials into the transcript.

### Smoke-data prerequisite

Prepare three isolated, approved Personal challenges on the intended
non-production Stripe-sandbox beta target:

| Scenario | Required evidence before cutoff | Expected result |
|---|---|---|
| Met | Complete production-origin coverage and steps at or above the frozen target | `met_goal / target_reached / complete`, not waived |
| Missed | Complete production-origin coverage and steps below target, plus one valid sandbox agreement | `missed_goal / target_missed / complete`, not waived, with one review opened |
| Inconclusive | Intentionally incomplete trusted coverage, with no development/unknown evidence | `inconclusive / missing_coverage / missing`, waived |

Use normal production-App-Attest ingest and coverage paths. Do not rewrite
timestamps on a real accepted challenge. If an accelerated past-due fixture is
required, create a separate reviewed fixture plan or a disposable hosted branch;
do not improvise privileged inserts on the linked project.

Record only the three challenge UUIDs and expected outcome codes in a private
smoke manifest. Do not put user identity, Health values, signed payloads, or
Stripe provider identifiers in the manifest.

### Exact due-set gate

The service entry point selects the oldest 10 due challenges; it does not accept
a named challenge or beta allowlist. Before each call, prove that the complete
due set contains exactly the three approved smoke IDs and that no fourth
challenge will cross its cutoff during the smoke window. Hold a quiet window
with no new Personal creation, assessment, result, or operator write:

```sql
select contest.id as challenge_id, terms.evidence_cutoff
from public.contests contest
join public.personal_challenge_terms terms
  on terms.challenge_id = contest.id
where contest.challenge_model = 'personal_accountability'
  and contest.status = 'active'
  and terms.evidence_cutoff <= clock_timestamp()
  and not exists (
    select 1
    from public.personal_challenge_results result
    where result.challenge_id = contest.id
  )
order by terms.evidence_cutoff, contest.id;

select contest.id as challenge_id, terms.evidence_cutoff
from public.contests contest
join public.personal_challenge_terms terms
  on terms.challenge_id = contest.id
where contest.challenge_model = 'personal_accountability'
  and contest.status = 'active'
  and terms.evidence_cutoff > clock_timestamp()
  and terms.evidence_cutoff <= clock_timestamp() + interval '30 minutes'
  and not exists (
    select 1
    from public.personal_challenge_results result
    where result.challenge_id = contest.id
  )
order by terms.evidence_cutoff, contest.id;
```

The first query must return exactly the three approved IDs. The second must
return zero rows. Any mismatch is a hard stop.

### First manual worker call

With Cron still inactive, the authorized service operator runs:

```sql
begin;
set local role service_role;

select *
from app.run_personal_result_worker();

commit;
```

If exactly the three smoke challenges are due, expect:

```text
challenges_selected = 3
results_published    = 3
failures_recorded    = 0
```

Verify each manifest row without selecting `daily_totals` or private provider
data:

```sql
select
  result.challenge_id,
  result.id as result_id,
  result.outcome,
  result.reason,
  result.evidence_state,
  result.commitment_waived,
  result.published_at,
  assessment.id as assessment_id,
  attempt.last_status,
  attempt.attempt_count,
  review.state as sandbox_review_state,
  review.review_deadline,
  exists (
    select 1
    from app.personal_stripe_sandbox_charge_commands command
    where command.challenge_id = result.challenge_id
  ) as has_charge_command,
  exists (
    select 1
    from public.personal_eligibility_holds hold
    where hold.challenge_id = result.challenge_id
  ) as has_eligibility_hold
from public.personal_challenge_results result
join app.personal_evidence_assessments assessment
  on assessment.id = result.assessment_id
join app.personal_result_worker_attempts attempt
  on attempt.challenge_id = result.challenge_id
left join app.personal_stripe_sandbox_payment_reviews review
  on review.result_id = result.id
where result.challenge_id in (
  '<MET_CHALLENGE_UUID>'::uuid,
  '<MISSED_CHALLENGE_UUID>'::uuid,
  '<INCONCLUSIVE_CHALLENGE_UUID>'::uuid
)
order by result.challenge_id;
```

Required postconditions:

- met: no review, no charge command, no hold;
- missed: exactly one `review_open` row with
  `review_deadline = published_at + interval '7 days'`, backed by the required
  sandbox agreement, and no charge command;
- inconclusive: no review, no charge command, no hold;
- all three have one immutable result and one matching assessment;
- no Social result, standing, or donation obligation appears.

Verify the dormant product families explicitly:

```sql
select
  (
    select count(*)
    from public.contest_results social_result
    where social_result.contest_id in (
      '<MET_CHALLENGE_UUID>'::uuid,
      '<MISSED_CHALLENGE_UUID>'::uuid,
      '<INCONCLUSIVE_CHALLENGE_UUID>'::uuid
    )
  ) as social_results,
  (
    select count(*)
    from public.contest_standing_entries standing
    where standing.contest_id in (
      '<MET_CHALLENGE_UUID>'::uuid,
      '<MISSED_CHALLENGE_UUID>'::uuid,
      '<INCONCLUSIVE_CHALLENGE_UUID>'::uuid
    )
  ) as standings,
  (
    select count(*)
    from public.donation_obligations obligation
    where obligation.contest_id in (
      '<MET_CHALLENGE_UUID>'::uuid,
      '<MISSED_CHALLENGE_UUID>'::uuid,
      '<INCONCLUSIVE_CHALLENGE_UUID>'::uuid
    )
  ) as donation_obligations;
```

All three counts must be zero. Cross-account isolation remains a separate beta
acceptance gate and is not proved by this worker-only smoke.

The worker tests prove missed-result publication but do not prove the
Stripe-agreement-dependent review trigger. The hosted missed scenario must check
that review explicitly.

### Safe rerun

Freeze the three result IDs, assessment IDs, review count, and attempt rows.
Immediately inventory the full due set again, then run:

```sql
begin;
set local role service_role;

select *
from app.run_personal_result_worker();

commit;
```

If no other challenge became due, expect:

```text
challenges_selected = 0
results_published    = 0
failures_recorded    = 0
```

All result IDs, assessment IDs, outcomes, review rows, charge-command count, and
published attempt rows must remain unchanged. Any duplicate, replacement,
unexpected review, command, hold, or failure is a hard stop.

## Gate 5 — daily health monitoring

During the first beta cohort, a named operator records one privacy-safe daily
check through the approved direct-database channel. Verify the health grant
under `service_role`:

```sql
begin;
set local role service_role;

select *
from app.personal_result_worker_health_v1(clock_timestamp());

rollback;
```

Healthy means:

- `scheduler_configured = true`;
- `scheduler_active = true` after activation;
- `overdue_challenges = 0`;
- `current_failures = 0`;
- `oldest_overdue_cutoff is null`;
- no current failure timestamp or SQLSTATE.

`due_challenges` may briefly be nonzero for less than 15 minutes. The health
function is not a scheduler heartbeat when there is no due work:
`last_attempt_at` changes only when a challenge is selected.

Then, as the authorized database/Cron operator, pair it with Cron run history:

```sql
select run.status, run.start_time, run.end_time
from cron.job_run_details run
where run.jobid = (
  select jobid
  from cron.job
  where jobname = 'gametime-publish-personal-results'
)
order by run.start_time desc
limit 20;
```

The latest run should be `succeeded`, no more than about 10 minutes old, and not
still running near Supabase's 10-minute job-duration recommendation. Supabase
stores job configuration in `cron.job` and run history in
`cron.job_run_details`; current guidance requires scheduler changes through Cron
functions rather than direct table writes:
[Supabase Cron overview](https://supabase.com/docs/guides/cron) and
[Cron quickstart](https://supabase.com/docs/guides/cron/quickstart).

The daily record contains only:

- date/time and operator;
- active/configured booleans;
- due, overdue, and failure counts;
- oldest overdue cutoff;
- latest run status and timestamps;
- decision: green, investigate, or disabled.

Do not copy `return_message` into routine reports. A private operator may inspect
it after a failure, but must stop if it contains sensitive data.

## Gate 6 — explicit Cron activation and disable

Activation is separate from migration application and manual smoke. It requires
its own approval.

### Activation

First require exactly one inactive row with the exact approved schedule and
command:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'gametime-publish-personal-results';
```

Then activate only the matching configuration. This block verifies exactly one
named row and fails the same transaction if the configuration or final state
does not match:

```sql
do $$
declare
  v_job_count integer;
  v_job_id bigint;
begin
  select count(*), min(job.jobid)
    into v_job_count, v_job_id
  from cron.job job
  where job.jobname = 'gametime-publish-personal-results';

  if v_job_count <> 1 then
    raise exception 'expected exactly one Personal result worker Cron job';
  end if;

  if not exists (
    select 1
    from cron.job job
    where job.jobid = v_job_id
      and job.schedule = '*/5 * * * *'
      and job.command = 'select app.run_personal_result_worker();'
      and not job.active
  ) then
    raise exception 'Personal result worker Cron configuration is not approved';
  end if;

  perform cron.alter_job(v_job_id, active := true);

  if not exists (
    select 1
    from cron.job job
    where job.jobid = v_job_id
      and job.active
  ) then
    raise exception 'Personal result worker Cron activation did not persist';
  end if;
end;
$$;
```

Immediately re-read `cron.job`, worker health, and Cron run history. Watch at
least two scheduled executions before declaring activation healthy.

Never activate with `update cron.job`. Supabase no longer permits direct writes
to that table; use `cron.alter_job`.

### Emergency disable

The named on-call operator must have pre-authorized permission to disable the
job immediately when a stop condition occurs. The emergency block requires one
named row and verifies that it is inactive before commit:

```sql
do $$
declare
  v_job_count integer;
  v_job_id bigint;
begin
  select count(*), min(job.jobid)
    into v_job_count, v_job_id
  from cron.job job
  where job.jobname = 'gametime-publish-personal-results';

  if v_job_count <> 1 then
    raise exception 'expected exactly one Personal result worker Cron job';
  end if;

  if exists (
    select 1
    from cron.job job
    where job.jobid = v_job_id
      and job.active
  ) then
    perform cron.alter_job(v_job_id, active := false);
  end if;

  if exists (
    select 1
    from cron.job job
    where job.jobid = v_job_id
      and job.active
  ) then
    raise exception 'Personal result worker Cron disable did not persist';
  end if;
end;
$$;
```

Verify:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'gametime-publish-personal-results';

select run.status, run.start_time, run.end_time
from cron.job_run_details run
where run.jobid = (
  select jobid
  from cron.job
  where jobname = 'gametime-publish-personal-results'
)
order by run.start_time desc
limit 20;
```

Disable prevents future starts but may not cancel a transaction already
running. Do not terminate a database backend, unschedule/delete the job, or
alter worker state without separate incident approval.

## Stop and rollback rules

### Stop before application

Stop if any of these is true:

- project reference, organization, host, or intended beta purpose is unclear;
- the hosted migration tail is not exactly `20260805131357`;
- the dry run includes anything other than the five frozen files;
- a hash differs from the approved manifest;
- migration 4's regenerated diagnostic-clearance guard is not owned, reviewed,
  or green in the exact frozen regression;
- the exact hosted environment-filtering dependency is unresolved;
- the worker job name already exists;
- any unpublished Personal assessment exists;
- either legacy provenance audit has a blocker;
- any due challenge is unexpected or outside the approved cohort;
- current data counts have drifted and the backfill/lock impact was not reviewed;
- the exact frozen local regression gate is not green;
- recent backup/point-in-time recovery status and an authorized recovery owner
  have not been confirmed.

### Stop after dormant application

Stop before smoke if:

- any migration failed or only part of the five applied;
- the Cron row is missing, duplicated, changed, or active;
- applying the migrations created a worker attempt or Personal result;
- assessment/result/review/charge-command/hold counts changed unexpectedly;
- backfilled provenance does not match preflight mapping;
- grants expose an internal or unchecked function.

### Stop during smoke or active operation

Disable Cron immediately and stop new beta invitations for:

- an unapproved challenge selected by the worker;
- selected, published, or failure counts that differ from expectation;
- a wrong outcome, reason, waiver, review, hold, or payment-command shape;
- a duplicate or replaced immutable result;
- any charge command created by the worker smoke;
- any current worker failure or overdue challenge during the first cohort;
- two consecutive failed Cron runs, no scheduled run within 10 minutes, or a
  run approaching the platform's 10-minute job recommendation;
- cross-account visibility, raw Health/signed-body logging, credential exposure,
  or any other privacy leak;
- development or unknown evidence reaching a complete production result;
- a core Personal creation, sync, result, review, or history journey failure.

### What rollback means

The safe runtime rollback is **deactivate Cron**.

Published Personal results and their assessments are append-only. They cannot be
deleted, edited, replaced, or safely "rolled back." A bad publication requires
a separately reviewed forward correction and founder/data-owner decision.

The first four migrations also move functions and establish provenance guards.
Do not reverse them ad hoc by dropping columns/functions, moving unchecked
functions back into `public`, disabling append-only triggers, or rewriting
migration history. If schema recovery is truly required, choose between a
reviewed forward migration and an approved platform restore using the exact
partial-application evidence.

## Founder go/no-go checklist

### Verified now

- [x] The local link and authenticated Supabase project list agree on project
      `jrkzdttophnmkxjoyioo`.
- [x] The hosted project is `ACTIVE_HEALTHY`.
- [x] Hosted migration history has 29 entries through
      `20260805131357_personal_stripe_sandbox_foundation`.
- [x] Exactly five newer local migration files exist.
- [x] The five current file hashes are recorded in this packet.
- [x] The worker job name is absent; four unrelated jobs remain active.
- [x] Hosted Personal assessment/result/due/hold/evidence blocker counts are all
      zero in the August 6 read-only snapshot.
- [x] The sampled pending columns, functions, table, and trigger names have no
      hosted schema collision.
- [x] The worker migration creates its named Cron job inactive.
- [x] No secret is needed for this database-local worker.
- [x] No hosted write or external account action occurred while preparing this
      packet.

### Still NO-GO

- [ ] The owner has explicitly confirmed that this exact generic-named hosted
      project is the intended non-production Stripe-sandbox beta target.
- [ ] The five artifacts are owned, reviewed, tracked, and frozen.
- [x] Migration 4's duplicated settlement guard was rejected and replaced in
      this regenerated packet by the forward diagnostic-clearance guard.
- [ ] The production-App-Attest environment filter is verified on the exact
      hosted ingest, coverage, and diagnostic functions, or an approved database
      guard replaces that dependency.
- [ ] Focused and full local regression proof is green for the exact frozen
      hashes.
- [ ] An authenticated linked dry run lists exactly these five migrations.
- [ ] Recent backup/recovery status and the recovery owner are confirmed.
- [ ] Database-owner approval to apply the five migrations with Cron dormant is
      recorded.
- [ ] Dormant post-application checks pass with the worker job inactive.
- [ ] Three isolated hosted smoke challenges and their data owner are approved.
- [ ] Met, missed plus sandbox review, inconclusive, and rerun smoke checks pass.
- [ ] A named operator owns the daily health check.
- [ ] Separate Cron activation approval is recorded.
- [ ] The operator has standing authority to disable Cron immediately on a stop
      condition.

**Current result: NO-GO.** The clean hosted counts reduce migration risk, but
they do not close the artifact, App Attest, smoke-data, or approval gates.

## Exact approvals still needed

1. **Artifact-owner approval:** approve ownership and the exact regenerated
   five-file boundary, including migration 4's forward diagnostic-clearance
   guard. If anything changes, regenerate the packet rather than updating these
   approvals in place.
2. **Hosted-target approval:** confirm that project
   `jrkzdttophnmkxjoyioo` is the intended non-production Stripe-sandbox beta
   backend despite its generic dashboard name.
3. **App Attest dependency approval:** authorize a separate deployment of the
   exact environment-filtering ingest/coverage/diagnostic bundles. Migration 4
   provides database defense in depth for diagnostic clearance; this packet
   does not authorize the function deployment.
4. **Database application approval:** authorize applying only the exact frozen
   five migrations to the confirmed project, with Cron remaining inactive.
5. **Hosted smoke-data approval:** authorize creation/use of the three isolated
   due scenarios and acknowledge that the first manual worker call publishes
   immutable hosted results.
6. **Cron activation approval:** after dormant verification and smoke pass,
   authorize activating only `gametime-publish-personal-results` at
   `*/5 * * * *`.
7. **Incident-disable authority:** pre-authorize the named operator to deactivate
   that job immediately when a stop condition occurs, followed by read-only
   evidence capture.
8. **Recovery approval:** name the owner who may choose a reviewed forward fix or
   platform restore after partial application or bad publication. Backend
   termination, job deletion, and result rewriting are not pre-authorized.
9. **Source-publication approval:** separately authorize any commit or push
   needed to turn these untracked drafts into a frozen source revision.

No approval to set a worker secret is needed because the worker has no new
secret. No Edge Function deployment, hosted mutation, Git action, Apple action,
TestFlight action, or Stripe-provider action is bundled into this packet.
