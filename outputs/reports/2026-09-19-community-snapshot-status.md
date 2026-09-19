# Local community snapshot freshness — September 19, 2026

Implemented on `codex/community-snapshot-status` from committed main
`9f116ac4954594a8d64467f78a6dca55d3cc2ce4`. The verified implementation commit is
`a9530702597b9da4f788585a53897352453f8d79`; the later evidence commit changes only
this report and its sanitized artifacts. Worktree:
`/Users/user/.codex/worktrees/community-snapshot-freshness-8765/GameTime`.
The pre-existing `codex/community-snapshot-freshness` branch and its separate
worktree were left untouched. This branch is available for review; no main merge,
push, deployment or hosted operation was performed.

## Implementation and boundaries

The forward migration adds one STABLE, service-only RPC:
`challenge_community_snapshot_status_v1(p_id uuid)`. It reuses the existing
publication, runtime, snapshot and invocation rows. There are no new tables,
record rewrites, capture side effects, worker/disclosure changes or alerts.
The [contract](../../docs/COMMUNITY_SNAPSHOT_STATUS_LOCAL.md) documents all twelve
fields, bounded states, authorization and clock limitations.

Capture age comes only from actual snapshot rows. Invocation preparation,
attempt and success use separately named wall timestamps; successful throttles
and replay cannot refresh a snapshot. Capture authorization follows the actual
`fixtures` + `discovery` + publication checks and is independent of processing,
admission and actor allowlisting. Missing runtime is unavailable, and old
capture/attempt observations remain visible. No output contains participant
counts, Health values, identities, raw receipts or raw errors.

The existing snapshot schema does not store historical clock provenance.
`reference_clock` labels the current age reference only. A reversed fixture
clock yields `clock_ahead` and null age, never a manufactured fresh zero.
No age is classified against the proposed 1,800-second alert threshold; no
threshold, schedule, alert destination, source or P7 policy was adopted.

## Performed verification

Exact committed-source command:

```sh
python3 scripts/community-snapshot-status-verify.py \
  --evidence-dir /tmp/gametime-snapshot-status-final
```

The runner exited **0**. It initialized fresh Supabase Postgres 17.6.1.143,
applied Auth v2.192.0 migrations and all **82** repository migrations in order,
and used PostgREST v14.14 with fictional signed JWTs. No retained stack, linked
project, hosted credential or schema dump was used. SQL tests ran with their
actual role grants, not an ACL-free schema reconstruction.

| Check | Actual result |
| --- | --- |
| New freshness suite 515 | **59/59** assertions passed, no skip/TODO |
| Existing community progress suite 508 | **9/9** passed |
| Existing worker recovery suite 509 | **43/43** passed |
| Complete runner | **46** checks passed, including setup, suite results, baseline comparisons and HTTP checks; these are not 46 independent HTTP scenarios |
| HTTP authorization | Service allowed; unsigned/anon 401, signed authenticated 403; null selection 400; unknown selection unavailable |
| HTTP behavior | Missing/first/old capture, delayed replay, throttle, failed dispatch, discovery disabled, fixtures disabled, backward clock and missing runtime passed |
| Privacy | Exact twelve-field allowlist; four-person snapshot retains null count; SQL fifth join cannot change monitoring fields; other cohort's newer capture/invocation cannot refresh the selected cohort |
| Read-only | Every HTTP status read preserved hashes of every app/public/auth table; repeated SQL reads preserved every challenge table and left the write guard off; HTTP GET and SQL `BEGIN READ ONLY` succeeded without table changes |
| Preservation | Historical cron execution off from first database start, zero executions; existing disclosure tests retain delayed aggregates and under-five suppression |
| Security advisor | **Unavailable**, exit 1 `LegacyDbConnectError / PgClient: Failed to connect` against the explicit numeric loopback database; not a passing advisor audit |
| Source checks | Python compilation and staged `git diff --check` passed |

The focused matrix includes prepared-only and failed-first invocations, direct
wall-reference capture, captures with processing/admission paused, throttle
boundary equality, unknown/unpublished selections, fixed definer path, effective
role grants and defense in depth after a transaction-local accidental EXECUTE
grant. Missing-runtime and failure cases use explicit disposable fault injection;
those are tests, not new operating controls.

**Two broader baseline failures remain.** Suite 506 stops at line 128 after 50
passing assertions; suite 507 stops at line 54 after 13. Both raise
`challenge_session_required` when a suspended fictional actor attempts the old
safe-access/appeal path. The runner independently removed the sole new function
inside a rollback-only transaction and reproduced the same failure and preceding
assertions for each suite. These are unchanged baseline results, not passes or
failures concealed by lowering the test plan. Their behavior was not changed in
this bounded monitoring task.

Initial attempts were retained separately: automatic network-pool exhaustion,
a missing IPAM configuration case in the new harness, bootstrap startup/role
setup errors, internal-network loopback refusal, the broader baseline failures,
and one new-suite fixture grant failure (53/54). The grant failure was the service
role's access to a temporary test ID table; the runtime RPC was unchanged. The
runner fixes, clock-independent assertions and final committed-source run above
supersede those failed attempts without relabeling them as passes.

## Sanitized output and resource disposition

[Example JSON](community-snapshot-status-20260919/example.json) is the actual
response after an invocation replay with a capture age of **7,200 fixture
seconds**. Its capture remains at `2026-10-01T12:00:00Z`; the fixture reference
is `14:00:00Z`. Invocation and observation timestamps remain actual September
19 wall times. `checked` is not a freshness guarantee.

The [sanitized verification summary](community-snapshot-status-20260919/verification.json)
records results and SHA-256 hashes for the exact implementation/test inputs.
Full migration manifests, TAP and private fixture receipts remain at
`/tmp/gametime-snapshot-status-final`; earlier attempts remain in their numbered
sibling directories. Only sanitized output and summaries are committed.

Owned resource prefix: `gametime-snapshot-status-f504e38b6d5d`. Database and
PostgREST were bound only to numeric loopback. Cleanup verified ownership labels
before removing its three containers, database volume and network. No original
or unrelated resource was stopped, reset, pruned or changed. The review worktree
is retained for the branch review.

This establishes local SQL/PostgREST behavior, not hosted credential isolation,
real Auth sign-in, a gateway, recurring operation, alert delivery, capacity,
source acceptance or release readiness. All existing proposed operating defaults
and external gates retain their previous status. The repository Supabase skill
and current [function security](https://supabase.com/docs/guides/database/functions)
and [API grants](https://supabase.com/docs/guides/api/securing-your-api) guidance
were used; the changelog was checked without changing infrastructure versions.
