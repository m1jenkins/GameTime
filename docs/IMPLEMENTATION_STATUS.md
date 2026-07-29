# GameTime implementation status

> Audit snapshot: 2026-07-28, including the M8.3c M7-backed standings and
> M8.3d isolated on-device demo implementation.
> This is a dated evidence record. `README.md` is the compact project overview,
> `PLAN.md` owns sequence and launch gates, and `DECISIONS.md` owns
> product/architecture decisions.

## Executive assessment

GameTime now has a production-shaped iOS app in addition to its substantial
backend and portable client-domain foundation, but it is not yet a usable beta
or production app. The repository is strongest in schema invariants,
RLS/least privilege, attested evidence ingestion, deterministic scoring,
anti-cheat sidecars, exact-byte retry behavior, and the newly tested social
and challenge navigation loop.

Milestones M0–M6 are complete within their deliberately backend-first scope.
M6.5 has a verified staging backend and a purpose-built iPhone conformance
target, but the eligible-team physical-device observation is still open. M7.2a's
notification outbox and scheduled activation are implemented, but their hosted
committed-row proof is open. A large D81 account-deletion/retention foundation
is integrated, locally database-proven, deployed to staging, and proven there
with committed manual and hosted retention cycles. Broader concurrency, hosted
advisor, and production-shaped migration proofs remain open. M8.1 implements
the product target, native Apple-token exchange, onboarding, exact-handle
friendships, challenge creation/invitation/acceptance, reload behavior,
and Debug/Release boundaries. M8.2a adds a versioned, per-actor protected
pending-challenge record before the creation RPC, preserves canonical
millisecond terms losslessly, and exposes only explicit same-request recovery
after an ambiguous outcome. M8.3a moves the product to Challenge terminology,
supports explicit 1–19-friend selection through one atomic request, and
migrates version-1 single-invite saved-duel records to the canonical version-2
roster without changing request identity or timestamps. M8.3c adds the
service-only M7 first-result publication boundary, accepted-participant
provisional/final standings with phase-aware integrity disclosure, and the
challenge-detail final ranking/per-loser obligation surface. A 2026-07-27 iPhone 17
staging run now proves paid-team
signing, native Apple identity creation, onboarding, the live four-tab shell,
and session/profile reload for one user. Apple did not return the requested
first-sign-in full name, so the editable Apple-name prefill observation and the
complete two-user flow remain open. Full M8 remains open. The trusted M7
evidence-loading/complete-assessment/adjudication orchestrator, actionable
settlement/disputes, and later M8 sensor, App Attest, inbox/APNs, and release
slices remain to be built.

M8.3d adds a separately labeled, in-memory demo to Debug and Staging. A
single tester can search `david1` or `david2`, add the synthetic profile with a
transparent instant demo acceptance, and select the new friend in challenge
creation. The retained live model and Supabase data are unchanged, demo state
is discarded on exit, and Release does not compile the fixture factory. This
does not satisfy the live two-user acceptance gate.

“Complete” below means the milestone's repository scope is implemented and
covered by its intended automated tests. It does not mean production deployed,
externally proven, operationally staffed, or App Store ready.

## Reconciled baseline

The reconciled baseline combines the local audit/D81 commit `c6bfed67` with upstream M6.5
hardening commit `cc8f440`. The hosted PKI.js Edge Runtime fix, reviewed staging
identity, safer staging scripts, D81 migrations/tests, documentation, and pinned
CI toolchains are therefore in one reviewable history. M8.1 adds the separate
product target, a bounded social-card API, atomic/idempotent contest creation,
and a macOS product/conformance job on top of that baseline. M8.2a adds
restart-safe pending-challenge persistence, conflict-checked monotonic retry
metadata, and fail-closed account/corruption handling without changing the
server request contract. M8.3a extends that record to a canonical invitee array,
adds a lossless version-1 migration, and passes the whole selection through the
existing atomic multi-invite RPC rather than adding a schema migration. The
M8.3c migration adds immutable standings/result/obligation ledgers, a
service-only idempotent publisher, and a participant-only redacted read RPC;
the product consumes that RPC through account-isolated per-challenge state.
The combined revision has a green initial PR #11
suite plus the current local Swift/Xcode evidence below, and still needs
hosted-advisor, production-shaped migration, and the external proofs below
before it can support a release claim.

## Verification evidence

### Executed in this audit

| Check | Result | What it proves |
| --- | --- | --- |
| M8.3d product compile gates | Debug build, Debug build-for-testing, Staging build, and Release build pass with no warnings | New unit/UI sources compile; Staging includes the explicit demo path, while Release compiles with fixture code absent. Runtime tests still require a booted simulator |
| Deno lint | Pass, 41 files checked | Current TypeScript satisfies configured lint rules |
| Deno type-check | Pass | Current Edge Function/shared code type-checks |
| Deno tests | 305 passed, 0 failed | Handler, cryptography, JWT, scoring, integrity, and adapter unit behavior, including complete accepted-roster all-donate outcomes |
| PostgreSQL 17 migration execution | All 19 migrations applied in a clean reset | Migration syntax and execution semantics succeed on the local PostgreSQL 17 stack |
| Bash syntax | All 5 scripts passed `bash -n` | Shell grammar only |
| Static Supabase security review | Exposed public tables have RLS; public views are `security_invoker`; privileged functions use explicit grants/revokes and blank `search_path`; standings ledgers have no direct client grants | Strong static posture; not a substitute for a live advisor or RLS suite |
| Clean local database reset and pgTAP | Pass, 21 files / 869 assertions | Every migration executes and the complete prior suite plus accepted-roster disclosure, result idempotency, deterministic-result gates, append-only ledgers, and exact per-debtor obligation mappings pass |
| Supabase database lint | Pass, no `public` or `app` schema errors | `supabase db lint --local --schema public,app --level warning` found no PL/pgSQL/schema issues |
| Product Xcode scheme | Pass, 34 unit and 8 UI tests (42 total); no warnings | Prior product behavior plus provisional rival-integrity redaction, final-result decoding, per-loser obligations, account-transition cache clearing, and provisional/final challenge-detail fixtures pass together |
| Product Staging and Release simulator builds | Pass without signing; no warnings | Both live configurations compile; Staging excludes `DEBUG` routing and Release compiles with fixture code absent and contest mutation locked |
| Single-user product staging device | Partial pass on 2026-07-27; Xcode 26.2, iPhone 17, iOS 27.0, app revision `dca1309` | Paid-team signing, install, native Apple identity, linked profile, four tabs, staging banner, live charity request, and force-quit session/profile reload passed. Apple returned no full name, so the name-prefill observation remains open |
| Conformance Xcode scheme | Pass, 10 tests; no warnings | Removing the product preview preserves the focused request/CBOR/replay harness |
| GameTimeCore SwiftPM | Pass, 88 tests; 0 failed | The portable domain, exact-byte queue, validation, request-building, and cryptographic/supporting primitives remain green independently of the app target |
| M8.1 pull-request CI | PR #11 initial head `c363610` passed all four jobs in [run 30236956570](https://github.com/m1jenkins/GameTime/actions/runs/30236956570); the Xcode 26.2 job completed in 15m 8s | A clean GitHub-hosted run reproduced pgTAP, Deno, GameTimeCore, product tests, Staging/Release builds, and conformance tests; the checkout-runtime follow-up must rerun before merge |
| Supported local database inspection | Pass; database/index/role stats and outliers reviewed, with no bloat, blocking queries, or long-running queries | Local runtime health after the clean suite; fresh-test index counters are diagnostic and do not justify dropping indexes |
| Staging migration reconciliation | Migrations through `20260726070000` were already applied; forward repair `20260726230529` applied successfully | The applied migration remains immutable and staging history now carries the generated-column repair as a new migration |
| Staging manual retention cycle | At 2026-07-26 23:09:47 UTC, 2 exact-location rows were pruned and 1 source-identifier pair was scrubbed; 3 immutable events were appended; immediate rerun returned all zeros | The repaired guard permits only the worker scrub, stored ranges recompute correctly, audit output is durable, and the worker is idempotent |
| Hosted retention cron | The 2026-07-26 23:17:00 UTC run succeeded in 28 ms and processed a second committed synthetic probe | The scheduled worker can see committed eligible rows and invoke the repaired retention path |

### Not executed in this audit

| Check | Why | Required follow-up |
| --- | --- | --- |
| Hosted Security and Performance Advisors | Supabase CLI 2.109.1 exposes local lint and `inspect db`, but no local `advisors` command; the product advisors are hosted Dashboard checks | Run both advisors against the staged D81 schema and investigate every finding |
| Physical App Attest proof | Not exercised in this product-app run; the paid Program team is now verified for signing, but App Attest registration/assertion exchange remains outside this proof | Provision the conformance target with the paid team and record the complete runbook evidence |
| M8.1 two-user Apple staging proof | Product App ID/team provisioning and a bounded one-user reload proof now pass; Apple-name prefill and the second authenticated user remain open | Re-observe the first-sign-in Apple name with an eligible fresh/re-authorized test account, then complete `M8_1_STAGING_ACCEPTANCE.md`, including force-quit reloads and one deliberately lost-response retry |
| Hosted activation cron proof | pgTAP transactions cannot be observed by the background worker; only the retention job has a committed-row staging proof | Record a committed-row activation run and exercise its downstream paths |

`deno fmt --check` also reported 25 tracked files as different only by line
endings because this Windows checkout uses `core.autocrlf=true`. Run the check
from an LF checkout or enforce LF in `.gitattributes`; do not create a broad
format-only diff and call that a source fix.

## Milestone ledger

| Milestone | Status | Delivered | Still open |
| --- | --- | --- | --- |
| M0 | Complete baseline | Supabase scaffold, migrations, local scripts, pgTAP/Deno/Swift CI with pinned Supabase/Deno/Xcode versions | Preserve latest-head/main CI and add deployment/rollback automation |
| M1 | Complete in repo | Profiles, friendships, groups, membership, blocks, RLS and guarded RPCs | Product screens; handle throttling/avatar storage |
| M2 | Complete in repo | Charities schema, contests, invitations, participant lifecycle, activation primitive | Verified production charity data |
| M3 | Complete in repo | Attested metric ledger, idempotent ingest, local-hour bucketing/provenance/queue core | Live HealthKit collection and background delivery |
| M4 | Complete in repo | Deterministic TypeScript scoring and fixture corpus | Production data-loading/finalizer orchestrator |
| M5 | Complete in repo | Integrity scoring, quarantines/reviews, source reputation, timezone epochs | D76 escalation/adjudicator operation |
| M6 | Complete in repo | Geofences, workout overlap, trusted-location integrity, exact-byte check-in queue | Live Core Location/HealthKit workout collection |
| M6.5 | Gate open | Staging backend, conformance target, independent receipt verification, runbook, and paid-team product signing | Paid-team conformance provisioning, Auth fixture, and physical App Attest observation |
| M7.1 | Complete | D74–D82 product contract | Implementation of most settlement domain |
| M7.2a | Implemented | Transactional notification intents and named one-minute activation job | Hosted committed-row activation proof |
| D81 foundation | Staged; local and retention-cycle proven | Durable actors, atomic service-only deletion, capabilities, holds/cutoffs, raw-retention worker, forward generated-column repair | Broader concurrency/production-shaped migration, hosted advisors, hold/failure recovery; user-facing deletion/capability path |
| M7 finalization/settlement | First-result foundation implemented but dormant | Immutable provisional/final snapshots, explicit first results, versioned scoring/integrity inputs, accepted-participant redacted reads, ingest serialization, and exact per-debtor obligations | Trusted evidence loading, complete persisted assessments, D76 adjudication, hosted caller, claims, disputes, actionability, reliability, and deadline workers |
| M8 | M8.1, M8.2a, M8.3a, M8.3c, and M8.3d implemented; partial single-user staging proof recorded; full milestone open | Product Xcode target, native Apple token exchange, exact-handle social/challenge loop, protected pending retry, M7-backed provisional/final rankings with own-obligation disclosure, and an isolated one-device demo | Apple-name prefill observation, two-user staging acceptance, live multi-friend/standings observation, HealthKit, Core Location, product App Attest, persistence for other pending actions, inbox/APNs, review/actionable settlement/dispute screens, privacy/release hardening |

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
- a separate production-shaped SwiftUI app with native Apple-token exchange,
  explicit auth/onboarding state, typed per-tab navigation, exact-handle social
  actions, atomic multi-friend challenge creation, live/fixture client
  boundaries, and fail-closed Staging/Release configuration;
- an isolated Debug/Staging on-device demo with synthetic exact handles,
  single-tester friend acceptance, challenge creation, explicit labeling,
  retained live-session isolation, and no Release fixture route;
- a versioned per-actor pending-challenge record written with complete file
  protection before the creation RPC, with canonical millisecond terms stored
  losslessly, immutable conflict checks, monotonic attempt metadata, explicit
  same-request retry after ambiguous/offline/cancelled outcomes, fail-closed
  corruption and account transitions, a lossless version-1 single-invite
  migration, and a warned local-only discard path;
- append-only standings snapshots, explicit first results, configuration
  versions, per-debtor obligations, and accepted-participant phase-redacted
  reads behind a service-only publication boundary;
- challenge-detail provisional/final ranking UI with account-isolated loading
  state, caller-only live integrity detail, and own-obligation disclosure;
- a payload-free transactional notification-intent ledger and named activation
  scheduler; and
- in the reconciled branch, durable pseudonymous actors, stale-JWT denial,
  account-deletion capabilities, retention policies/holds/events, and an hourly
  raw-evidence pruner.

## Remaining work, by priority

### P0 — Prove the reconciled repository revision

1. Preserve the green GitHub Actions result on the latest PR head and
   post-merge `main`.
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

### P2 — Complete the finalization vertical slice

1. Load evidence, source reputation, timezone events, quarantine state,
   geofence integrity, and trusted locations into one server orchestrator.
2. Persist a complete versioned integrity assessment before interpreting
   “zero quarantines” as clean.
3. Implement bounded D76 escalation/adjudication and explicit clearance.
4. Invoke the existing serialized, grace-gated first-result publisher only from
   that trusted pipeline; add multi-session coverage around the finality locks.
5. Operate the finalizer in staging with authorized queues, observability,
   alerts, and an on-call/SLA runbook before enabling it.

### P3 — Complete settlement and operations

- make the append-only first-result obligations actionable only after D78's
  review/dispute boundary, then add D74 pledge-confirmation/receipt evidence;
- D78 result/obligation disputes, pauses, corrections, and audited authority;
- D79 reliability calculation and challenge windows;
- remaining notification events and deadline workers;
- a guarded account-deletion service with reauthentication, confirmation,
  one-time capability delivery/storage, and explicit non-recovery UX; any
  recovery mechanism requires a separate reviewed design;
- operator queues, authorization, conflicts, SLAs, alerting, and runbooks; and
- rate limits, structured observability, privacy/abuse processes, retention
  operations, and production charity curation.

### P4 — Close M8.1 proof and continue the product loop

1. Provision the product App ID through an eligible Apple team and complete the
   two-user, force-quit/reload M8.1 staging run.
2. Add HealthKit background sync and Core Location/workout capture through the
   existing exact-byte queues.
3. Add product App Attest key lifecycle and evidence signing, then unlock
   Release contest mutation only after its staging gate.
4. Extend the protected pending-action model beyond challenge creation, then
   add a durable in-app inbox and APNs delivery.
5. Add review/adjudication and actionable settlement/dispute screens only after
   M7 supplies those APIs; stage-prove the implemented standings read surface.
6. Complete accessibility/privacy hardening, avatar/group-feed policy,
   reminders, and App Store release work.

## Recommended next sequence

1. **Repository proof:** obtain one green database/Deno/Swift/CI result on the
   reconciled revision.
2. **External proof sprint:** close M6.5, M7.2b, and the remaining retention
   failure-recovery proof while the staging environment is active.
3. **Finalizer slice:** connect evidence loading and complete assessments to the
   immutable result boundary, including adjudication and operational gates.
4. **Settlement slice:** obligations, confirmation, disputes, reliability, and
   their operated deadlines.
5. **Product slice:** close M8.1's external proof, extend protected persistence
   to the remaining pending actions, then add the sensor, App Attest,
   inbox/APNs, and M7-backed product slices.
6. **Launch hardening:** charities, monitoring, rate limits, privacy/abuse,
   backup/restore, deployment controls, accessibility, and App Store evidence.

## Claims that should not be made yet

- The app is usable, beta-ready, or App Store ready.
- M8.1 is complete before its two-user Apple staging record exists.
- Full M8 is complete merely because the M8.3a creation, M8.3c standings, and
  M8.3d demo slices are locally implemented and tested.
- D81 is CI-proven or safe to deploy at production scale.
- M6.5 physical App Attest conformance is complete.
- The activation job has a committed-row hosted proof.
- Account deletion is an end-to-end user feature.
- Hosted finalization, actionable donations, disputes, reliability, push
  delivery, or operator workflows are enabled merely because first-result
  ledgers and fixture-backed reads exist.

## Supabase compatibility watch

The repository already targets PostgreSQL 17 and relies on explicit grants
rather than automatic Data API exposure, which aligns with Supabase's 2026
platform changes. Keep that explicit exposure model when new public tables are
added. CI now pins the audited Supabase CLI and Deno versions rather than
floating on their latest releases. Review the
[Supabase breaking-change changelog](https://supabase.com/changelog?types=breaking-change)
before database/runtime upgrades.
