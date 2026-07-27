# GameTime implementation status

> Audit snapshot: 2026-07-26. This is a dated evidence record. `README.md` is
> the compact project overview, `PLAN.md` owns sequence and launch gates, and
> `DECISIONS.md` owns product/architecture decisions.

## Executive assessment

GameTime has a substantial backend and portable client-domain foundation, but
it is not yet a usable product app. The repository is strongest in schema
invariants, RLS/least privilege, attested evidence ingestion, deterministic
scoring, anti-cheat sidecars, and exact-byte retry behavior.

Milestones M0–M6 are complete within their deliberately backend-first scope.
M6.5 has a verified staging backend and a purpose-built iPhone conformance
target, but the eligible-team physical-device observation is still open. M7.2a's
notification outbox and scheduled activation are implemented, but their hosted
committed-row proof is open. A large D81 account-deletion/retention foundation
is integrated, locally database-proven, deployed to staging, and proven there
with committed manual and hosted retention cycles. CI, concurrency, hosted
advisor, and production-shaped migration proofs remain open. The M7
finalizer/settlement domain and the M8 product iOS app remain to be built.

“Complete” below means the milestone's repository scope is implemented and
covered by its intended automated tests. It does not mean production deployed,
externally proven, operationally staffed, or App Store ready.

## Reconciled baseline

`main` now combines the local audit/D81 commit `c6bfed67` with upstream M6.5
hardening commit `cc8f440`. The hosted PKI.js Edge Runtime fix, reviewed staging
identity, safer staging scripts, D81 migrations/tests, documentation, and pinned
CI toolchains are therefore in one reviewable history. The combined revision
still needs Swift, CI, concurrency, hosted-advisor, production-shaped migration,
and remaining external proof below before it can support a release claim.

## Verification evidence

### Executed in this audit

| Check | Result | What it proves |
| --- | --- | --- |
| Deno lint | Pass, 39 files checked | Current TypeScript satisfies configured lint rules |
| Deno type-check | Pass | Current Edge Function/shared code type-checks |
| Deno tests | 287 passed, 0 failed | Handler, cryptography, JWT, scoring, integrity, and adapter unit behavior |
| PostgreSQL 17 migration execution | All 16 migrations applied in a clean reset | Migration syntax and execution semantics succeed on the local PostgreSQL 17 stack |
| Bash syntax | All 5 scripts passed `bash -n` | Shell grammar only |
| Static Supabase security review | 20 exposed public tables have RLS; public views are `security_invoker`; no `auth.role()`/user-metadata authorization; privileged functions use explicit grants/revokes and blank `search_path` | Strong static posture; not a substitute for a live advisor or RLS suite |
| Clean local database reset and pgTAP | Pass, 18 files / 733 assertions | Every migration executes and the complete RLS, privilege, lifecycle, D80–D82, deletion, and retention suite passes through the supported runner |
| Supabase database lint | Pass, no `public` or `app` schema errors | `supabase db lint --local --schema public,app --level warning` found no PL/pgSQL/schema issues |
| Supported local database inspection | Pass; database/index/role stats and outliers reviewed, with no bloat, blocking queries, or long-running queries | Local runtime health after the clean suite; fresh-test index counters are diagnostic and do not justify dropping indexes |
| Staging migration reconciliation | Migrations through `20260726070000` were already applied; forward repair `20260726230529` applied successfully | The applied migration remains immutable and staging history now carries the generated-column repair as a new migration |
| Staging manual retention cycle | At 2026-07-26 23:09:47 UTC, 2 exact-location rows were pruned and 1 source-identifier pair was scrubbed; 3 immutable events were appended; immediate rerun returned all zeros | The repaired guard permits only the worker scrub, stored ranges recompute correctly, audit output is durable, and the worker is idempotent |
| Hosted retention cron | The 2026-07-26 23:17:00 UTC run succeeded in 28 ms and processed a second committed synthetic probe | The scheduled worker can see committed eligible rows and invoke the repaired retention path |

### Not executed in this audit

| Check | Why | Required follow-up |
| --- | --- | --- |
| Hosted Security and Performance Advisors | Supabase CLI 2.109.1 exposes local lint and `inspect db`, but no local `advisors` command; the product advisors are hosted Dashboard checks | Run both advisors against the staged D81 schema and investigate every finding |
| Swift build/tests | Swift/Xcode are unavailable on this host | Run 88 GameTimeCore tests and 10 conformance XCTest cases |
| Conformance Xcode CI | Current CI builds only GameTimeCore on Linux | Add a macOS simulator build/test job |
| Physical App Attest proof | Current signing account is a Personal Team | Use an App Attest-capable Program team and record the runbook evidence |
| Hosted activation cron proof | pgTAP transactions cannot be observed by the background worker; only the retention job has a committed-row staging proof | Record a committed-row activation run and exercise its downstream paths |
| Current private GitHub Actions result | Unauthenticated GitHub API access could not read it | Confirm CI in GitHub on reconciled `main` |

`deno fmt --check` also reported 25 tracked files as different only by line
endings because this Windows checkout uses `core.autocrlf=true`. Run the check
from an LF checkout or enforce LF in `.gitattributes`; do not create a broad
format-only diff and call that a source fix.

## Milestone ledger

| Milestone | Status | Delivered | Still open |
| --- | --- | --- | --- |
| M0 | Complete baseline | Supabase scaffold, migrations, local scripts, pgTAP/Deno/Swift CI with pinned Supabase/Deno versions | Prove the pins in CI; conformance CI; deployment/rollback automation |
| M1 | Complete in repo | Profiles, friendships, groups, membership, blocks, RLS and guarded RPCs | Product screens; handle throttling/avatar storage |
| M2 | Complete in repo | Charities schema, contests, invitations, participant lifecycle, activation primitive | Verified production charity data |
| M3 | Complete in repo | Attested metric ledger, idempotent ingest, local-hour bucketing/provenance/queue core | Live HealthKit collection and background delivery |
| M4 | Complete in repo | Deterministic TypeScript scoring and fixture corpus | Production data-loading/finalizer orchestrator |
| M5 | Complete in repo | Integrity scoring, quarantines/reviews, source reputation, timezone epochs | D76 escalation/adjudicator operation |
| M6 | Complete in repo | Geofences, workout overlap, trusted-location integrity, exact-byte check-in queue | Live Core Location/HealthKit workout collection |
| M6.5 | Gate open | Staging backend, conformance target, independent receipt verification, runbook | Eligible Apple team, Auth fixture, physical-device observation |
| M7.1 | Complete | D74–D82 product contract | Implementation of most settlement domain |
| M7.2a | Implemented | Transactional notification intents and named one-minute activation job | Hosted committed-row activation proof |
| D81 foundation | Staged; local and retention-cycle proven | Durable actors, atomic service-only deletion, capabilities, holds/cutoffs, raw-retention worker, forward generated-column repair | CI/concurrency/production-shaped migration, hosted advisors, hold/failure recovery; user-facing deletion/capability path |
| M7 finalization/settlement | Mostly not started | Pure scoring/integrity engines and schema seams exist | Standings API, frozen assessments, results, obligations, claims, disputes, reliability, deadline workers |
| M8 | Not started | Portable GameTimeCore and conformance-only target | Product Xcode target, Auth, HealthKit, Core Location, App Attest lifecycle, persistence, screens, APNs |

## Work already delivered

The implemented architecture includes:

- a migration-first PostgreSQL schema with explicit constraints, state
  transitions, RLS, withheld grants, security-invoker views, and guarded RPCs;
- a social graph and immutable contest/participant agreement model;
- append-only metric evidence with provenance, exact local-hour/day semantics,
  App Attest registration/assertions, atomic counters, and replay-safe ingest;
- deterministic scoring plus versioned integrity, quarantine, source-reputation,
  timezone-change, geofence, dwell, workout, and travel signals;
- portable Swift models, bucketing, validation, metric batching/retry
  primitives, and a restorable exact-byte check-in queue, all without
  Apple-framework coupling;
- independent App Attest receipt PKCS#7/X.509 verification and a focused
  real-device conformance target;
- a payload-free transactional notification-intent ledger and named activation
  scheduler; and
- in the reconciled branch, durable pseudonymous actors, stale-JWT denial,
  account-deletion capabilities, retention policies/holds/events, and an hourly
  raw-evidence pruner.

## Remaining work, by priority

### P0 — Prove the reconciled repository revision

1. Run the remaining Deno checks, both Swift suites, and CI on the locally
   database-verified revision.
2. Re-check from a fresh checkout that the repository-wide LF rule removes
   Windows format/script drift without creating unintended source changes.
3. Run the hosted Security and Performance Advisors against the staged D81
   schema.
4. Add real multi-session concurrency tests for deletion racing activation,
   invitation acceptance, ingest, receipt marking, finality/holds, and pruning.
5. Apply the large D81 migration to a production-shaped staging copy; measure
   locks and document backup, deployment window, recovery, and rollback limits.

### P1 — Close the two external backend gates

1. Provision the connected iPhone through an App Attest-capable Apple Developer
   Program team.
2. Create the staging Auth user/fixture and complete every M6.5 observation.
3. Run M7.2b against committed rows opened by `gametime-activate-due-contests`;
   inspect `cron.job_run_details` and exercise ingest/timezone/check-in paths.
4. Complete retention operations proof with a hold-blocked cycle, deliberate
   failed-job observation, alerting, and recovery.

### P2 — Build one finalization vertical slice

1. Load evidence, source reputation, timezone events, quarantine state,
   geofence integrity, and trusted locations into one server orchestrator.
2. Update the scoring outcome contract for complete `all_donate` rosters and
   treat an active one-person contest as an invariant failure.
3. Persist a complete versioned integrity assessment before interpreting
   “zero quarantines” as clean.
4. Serialize finalization with metric/check-in ingest and wait for ingest grace.
5. Add D77 role/phase-redacted standings and review surfaces.
6. Implement bounded D76 escalation/adjudication, then persist explicit
   `winner`, `all_donate`, `void`, or `inconclusive` results with configuration
   versions.

### P3 — Complete settlement and operations

- append-only obligations and D74 pledge-confirmation/receipt evidence;
- D78 result/obligation disputes, pauses, corrections, and audited authority;
- D79 reliability calculation and challenge windows;
- remaining notification events and deadline workers;
- a guarded account-deletion service with reauthentication, confirmation,
  one-time capability delivery/storage, and explicit non-recovery UX; any
  recovery mechanism requires a separate reviewed design;
- operator queues, authorization, conflicts, SLAs, alerting, and runbooks; and
- rate limits, structured observability, privacy/abuse processes, retention
  operations, and production charity curation.

### P4 — Build the M8 product loop

Create the real Xcode app target and prove an end-to-end loop: Sign in with
Apple, onboarding/social discovery, contest creation/invitation/acceptance,
HealthKit background sync, Core Location/workout capture, App Attest key
lifecycle, queue persistence, standings/review/finalization/settlement/dispute
screens, an in-app action inbox, and APNs delivery. Then add accessibility,
privacy disclosures, avatar storage, group feed policy, reminders, and App Store
release work.

## Recommended next sequence

1. **Repository proof:** obtain one green database/Deno/Swift/CI result on the
   reconciled revision.
2. **External proof sprint:** close M6.5, M7.2b, and the remaining retention
   failure-recovery proof while the staging environment is active.
3. **Finalizer slice:** ship evidence loading through one immutable explicit
   result, including redacted standings and adjudication gates.
4. **Settlement slice:** obligations, confirmation, disputes, reliability, and
   their operated deadlines.
5. **Product slice:** build the M8 iOS vertical loop against stable backend
   contracts.
6. **Launch hardening:** charities, monitoring, rate limits, privacy/abuse,
   backup/restore, deployment controls, accessibility, and App Store evidence.

## Claims that should not be made yet

- The app is usable, beta-ready, or App Store ready.
- D81 is CI-proven or safe to deploy at production scale.
- M6.5 physical App Attest conformance is complete.
- The activation job has a committed-row hosted proof.
- Account deletion is an end-to-end user feature.
- Final results, donations, disputes, reliability, push delivery, or operator
  workflows exist merely because their contracts and schema seams do.

## Supabase compatibility watch

The repository already targets PostgreSQL 17 and relies on explicit grants
rather than automatic Data API exposure, which aligns with Supabase's 2026
platform changes. Keep that explicit exposure model when new public tables are
added. CI now pins the audited Supabase CLI and Deno versions rather than
floating on their latest releases. Review the
[Supabase breaking-change changelog](https://supabase.com/changelog?types=breaking-change)
before database/runtime upgrades.
