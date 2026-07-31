# Archived M7 account deletion and raw-evidence retention design: 2026-07-30

> Retained production design. This work is deferred until the functional two-user alpha passes.

> Status: D81 foundation integrated into the reconciled 2026-07-26 branch and
> locally database-proven at 733/733 assertions. D81 and forward repair
> `20260726230529` are deployed to staging, where committed manual and hosted
> retention cycles pass. It is not yet CI- or concurrency-proven,
> production-shaped staging-tested, or exposed as an end-to-end user feature.

This document describes the implementation boundary and the evidence required
before deployment. Product rules remain authoritative in DECISIONS.md D81.

## Purpose and boundary

Authentication can end while a contest identity and agreement must remain
auditable. The implementation therefore:

- keeps a stable, non-discoverable actor UUID and accepted roster/audit facts;
- removes the Auth principal and social/delivery state;
- resolves only transitionable pending participation;
- revokes operational device registrations without cascading evidence;
- denies stale authenticated JWTs by checking the active actor on every policy
  and actor RPC;
- returns scoped continuation capability plaintext once, retaining only hashes;
  and
- prunes sensitive raw material after workflow finality, policy windows, operator
  cutoffs, and scoped holds permit it.

It does not yet implement the service/API/UI that confirms deletion,
reauthenticates the user, delivers/stores capabilities, or lets a deleted actor
use those capabilities against future result/obligation/dispute APIs.

## Migration ownership

| Migration | Responsibility |
| --- | --- |
| `20260726055000_account_deletion_notification_event.sql` | Adds the participant-change notification event in a separate enum migration/transaction boundary |
| `20260726060000_account_deletion_foundation.sql` | Durable actors, active Auth bindings, cascade removal, actor guards, pending lifecycle, capability scopes, and atomic deletion |
| `20260726070000_raw_evidence_retention.sql` | Scope finality/holds, guarded raw pruning, immutable retention summaries/events, and the hourly job |
| `20260726230529_fix_raw_evidence_generated_column_guard.sql` | Forward-only repair for the check-in source scrub: excludes stored generated ranges from the `BEFORE UPDATE` row comparison while preserving their base timestamps |
| `170_account_deletion.test.sql` | D81 schema, privilege, lifecycle, stale-JWT, capability, preservation, hold, and retention assertions |

The deletion migration is large and deliberately takes one migration-wide write
barrier while it rewires foreign keys and triggers. Treat it as a production
migration exercise, not an ordinary small DDL deploy.

Migration `20260726070000` was already recorded in staging before the
generated-column defect was found. It is therefore immutable. Never move the
repair back into that file: every deployed correction must remain represented
by the forward migration above.

## Privileged interfaces

All mutation interfaces below revoke `PUBLIC`, `anon`, and `authenticated`.
They are service-only or private-worker primitives.

### Delete an account

```sql
select public.delete_account('<actor UUID>');
```

The single transaction returns:

```json
{
  "deletedAt": "<server timestamp>",
  "capabilities": [
    {
      "kind": "contest_lineage | case",
      "scopeId": "<UUID>",
      "secret": "gtcap1_<one-time secret>"
    }
  ]
}
```

That response is the only plaintext delivery. Retrying a completed deletion
returns the same private “account is not active” refusal as an unknown or
already-deleted actor; it cannot recover lost secrets.

The eventual service must:

1. require a recent authenticated session and explicit destructive confirmation;
2. call the RPC with `service_role` only on the server;
3. durably hand the complete response to the user exactly once without logging
   capability plaintext;
4. explain active-contest/pledge consequences before commit;
5. revoke local credentials and clear personal data after successful handoff;
6. never claim recovery is available unless a separately designed recovery
   mechanism exists.

### Authorize a continuation capability

`app.authorize_account_capability(secret, scope_kind, scope_id, at)` returns the
pseudonymous actor UUID only while the hashed capability covers the exact case
or its contest lineage and the workflow/cutoff remains open. It is a private
building block for future narrowly redacted APIs, not a general session or a
route back into the social account.

### Advance finality and retention

```sql
select public.set_workflow_retention_state(
  'contest_lineage',
  '<scope UUID>',
  false,
  '<user-terminal timestamp>',
  '<operator-open-until timestamp>',
  'raw-evidence-retention-v1'
);

select public.create_retention_hold(
  'contest_lineage',
  '<scope UUID>',
  '<reviewed reason>',
  '<finite expiry>'
);
```

Future finalization, obligation, and dispute transactions must update these
scopes atomically with their own state. A closed workflow requires a
user-terminal timestamp. Holds are append-only, scoped, reasoned, and expiring;
they are not an undocumented way to retain everything forever.

### Run raw retention

```sql
select * from app.run_raw_evidence_retention(clock_timestamp(), 500);
```

The worker returns counts for location rows, metric rows, source identifiers,
receipt rows, and device rows pruned. It uses an advisory transaction lock,
bounded batches, row locks, and `skip locked`. The named hosted schedule is:

```text
gametime-prune-raw-evidence
17 * * * *
select app.run_raw_evidence_retention();
```

Exact locations use a 30-day rule. Raw metric/source material, revoked device
registration material, and opaque App Attest receipts use 90-day rules.
Accepted check-in facts, ingest audit facts, quarantines, roster identities,
digests/fingerprints, and immutable retention events remain.

## Staging evidence — 2026-07-26

Staging migration history already contained every D81 migration through
`20260726070000`. Its installed `guard_geofence_checkin_update()` omitted
`visit_range` and `workout_range`; PostgreSQL supplies those stored generated
columns as `NULL` in `NEW` during a `BEFORE` trigger, so the otherwise exact
row comparison blocked the authorized scrub.

Forward migration `20260726230529` replaced only that function. The deployed
definition now excludes both generated ranges and the two source fields,
retains the base timestamp comparison, and has ACL `{postgres=X/postgres}`.

A committed synthetic lineage then exercised actual staging state:

- manual worker call at `2026-07-26 23:09:47 UTC`: 2 exact-location rows
  pruned, 1 source-identifier pair scrubbed, and every other count 0;
- the accepted check-in, outcome, rule version, base timestamps, and both
  correctly recomputed generated ranges remained;
- 2 `exact_location` and 1 `source_identifier` immutable events were appended
  under `raw-evidence-retention-v1`, all with 32-byte digests;
- an immediate recovery rerun returned five zero counts and appended no
  duplicate events; and
- the `2026-07-26 23:17:00 UTC` hosted run succeeded in 28 ms and processed a
  second committed probe, proving background visibility and the repaired
  automatic path.

This is a targeted synthetic staging proof, not the production-shaped migration
exercise. Hosted advisor review, multi-session concurrency, a hold-blocked
cycle, deliberate failure/alert recovery, and backup/lock/rollback measurement
remain open.

## Deployment gate

Do not apply these migrations to production until all items pass:

- [x] Reconcile the D81 work with `origin/main` and review one combined diff.
- [x] Run a clean local reset and every pgTAP file (18 files / 733 assertions).
- [x] Run database lint and the supported local database inspection commands.
- [x] Keep deployed `20260726070000` immutable, apply forward repair
      `20260726230529`, and reconcile staging migration history.
- [x] Run committed manual and hosted retention probes; verify the source scrub,
      generated ranges, immutable events, and an idempotent recovery run.
- [ ] Run Deno/Swift/CI and the hosted Security and Performance Advisors.
- [ ] Test deletion against activation, invitation acceptance, metric/check-in
      ingest, receipt marking, hold/finality updates, and pruning in separate
      sessions.
- [ ] Restore a production-shaped backup into staging and measure migration
      locks/duration and table rewrite/storage impact.
- [ ] Document the backup point, quiet deployment window, statement/lock
      timeouts, abort criteria, recovery owner, and rollback limitations.
- [ ] Confirm all new foreign keys preserve rosters/evidence when Auth and device
      rows are removed.
- [ ] Exercise pending-author, pending-participant, active-contest, and
      no-capability deletion paths through the eventual service.
- [ ] Prove capability plaintext never enters logs, analytics, notifications,
      crash reports, or support tooling.
- [ ] Exercise a hold-blocked cycle and deliberate failed-job alert/recovery.

## Operator checks

Inspect the installed schedules and recent executions:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname in (
  'gametime-activate-due-contests',
  'gametime-prune-raw-evidence'
);

select jobid, status, return_message, start_time, end_time
from cron.job_run_details
where jobid in (
  select jobid
  from cron.job
  where jobname in (
    'gametime-activate-due-contests',
    'gametime-prune-raw-evidence'
  )
)
order by start_time desc
limit 50;
```

Inspect open workflows and holds before investigating apparent pruning lag:

```sql
select scope_kind, scope_id, workflow_open, user_terminal_at,
       operator_open_until, retention_policy_version, updated_at
from app.workflow_scopes
where workflow_open
   or operator_open_until > clock_timestamp()
order by updated_at;

select scope_kind, scope_id, reason, expires_at, created_at
from app.retention_holds
where expires_at > clock_timestamp()
order by expires_at;
```

Audit immutable pruning output without exposing removed raw values:

```sql
select evidence_kind, policy_version, count(*) as events,
       min(pruned_at) as first_pruned_at,
       max(pruned_at) as last_pruned_at
from app.raw_evidence_retention_events
group by evidence_kind, policy_version
order by evidence_kind, policy_version;
```

Alert on failed cron runs, prolonged absence of successful runs, unexpectedly
large eligible backlogs, scopes whose operator cutoff has passed but remain
open, repeated zero-progress recovery runs, and any direct deletion attempt
blocked by the retention guards.

## Required follow-on integration

Every future result, obligation, claim, dispute, adjudication, and
donation-receipt migration must:

- attach its actors and child scope to the correct contest lineage;
- define user terminality and the operator-open cutoff;
- serialize with deletion and finalization in the documented lock order;
- preserve the redacted facts a deleted capability holder may still need;
- add its own raw-evidence retention kind/rule only through a new versioned
  policy when necessary; and
- extend account-deletion and retention tests before deployment.
