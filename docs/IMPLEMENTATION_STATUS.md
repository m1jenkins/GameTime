# GameTime implementation status

> Audit snapshot: 2026-07-29 at main revision `b593679`, including the M8.3c
> M7-backed standings, M8.3d isolated on-device demo, and staging-only explicit
> steps-sync implementation. Local automated verification completed across
> 2026-07-28–29, including the App Attest verifier follow-up.
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
target. One paid-team Staging product sign/install/launch is complete, but the
focused physical App Attest conformance observation is still open. M7.2a's
notification outbox and scheduled activation are implemented, but their hosted
committed-row proof is open. A large D81 account-deletion/retention foundation
is integrated, locally database-proven, deployed to staging, and proven there
with committed manual and hosted retention cycles. Broader concurrency, hosted
advisor, and production-shaped migration proofs remain open. The M8.1
repository path includes the product target, native Apple-token exchange,
onboarding, exact-handle
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
settlement/disputes, and later M8 background sensor, inbox/APNs, and release
slices remain to be built.

M8.3d adds a separately labeled, in-memory demo to Debug and Staging. A
single tester can search `david1` or `david2`, add the synthetic profile with a
transparent instant demo acceptance, and select the new friend in challenge
creation. The retained live model and Supabase data are unchanged, demo state
is discarded on exit, and Release does not compile the fixture factory. This
does not satisfy the live two-user acceptance gate.

Revision `b593679` improves the physical acceptance path without closing it.
Creator and invitee views now expose the immutable window, timezone, and
full roster. Staging challenge detail exposes the challenge ID and loaded
roster, and
`StagingAcceptanceDiagnostics.challengeCreationResponseReceived` supplies a
stable lost-response breakpoint. A staging-only activity slice adds explicit
**Enable Activity** and **Sync Activity** actions for accepted, active steps
challenges. It uses `HourlyBucketer` to plan completed frozen-local-hour
intervals, uses raw samples only to identify genuine Apple devices and sources,
and asks HealthKit statistics to merge overlapping phone/watch steps into one
device contribution. Manual, unknown, and third-party rows remain outside this
first trusted slice. It reuses `IngestQueue`, `PendingBatch`, and the encoded
metric-ingest payload path, persists exact body and App Attest assertion bytes
in an account-specific protected queue, reports the exact confirmed or retained
step total, and retries only when the person taps **Sync Activity**. Histories
are split across the server count/body limits, permanent refusals are abandoned,
and ambiguous failures retain exact bytes. Before the first metric upload it also
persists the exact App Attest registration body with a bounded replay deadline.
A lost registration response reuses those bytes; after the deadline, the next
explicit sync rotates only that account's unregistered key and starts a fresh
registration. The Edge database adapter discards PostgREST conflict detail
before logging or returning a metric-ingest failure, so duplicate diagnostics
cannot expose old or new step values or source metadata.
Release activity sync remains disabled, contest mutation remains locked, and
fixture routes remain absent.

A 2026-07-29 physical-device retry built, signed, installed, and launched the
then-current steps-sync tree on one iPhone. The tester confirmed the amber
Staging banner and live four-tab shell. The Challenges screen correctly showed
no challenges and kept creation disabled because this account has no accepted
friendship. This is one-device runtime evidence, not proof that exact revision
`b593679` launched and not the required two-user run. The tester then deferred
the remaining physical acceptance because a second friend/device was
unavailable; no HealthKit or metric-upload action was attempted.

During the final source review, the connected iPhone accepted a fresh signed
Staging build, but the launch request was denied because the device remained
locked. This confirms final-source device compilation/signing only; it does not
replace the earlier launch observation or add any HealthKit/runtime evidence.

This activity slice has no background delivery. It also adds no workouts, Core
Location, settlement, donations, disputes, APNs, TestFlight, or production
release work. The local verifier now keeps `com.gametime.conformance` as its
primary identity and accepts a strict, maximum-three
`APPLE_ADDITIONAL_BUNDLE_IDS` list for product registration and metric
assertions outside production only. Receipt verification uses the exact App ID
that passed attestation; check-in remains primary-only; production rejects the
additional list. The hosted project has not received the revision `b593679`
function bundles or the product App ID configuration. Its active
`ingest-metrics` bundle also
predates the local database-detail redaction, so real health uploads must wait
for a separately approved hosted rollout. Development-signed Staging
verification still requires `APP_ATTEST_ALLOW_DEVELOPMENT=true`, with
`ATTEST_DEV_BYPASS` absent.

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

The explicit steps-sync work is committed in revision `b593679` on top of that
baseline. Its local evidence is recorded separately below; do not attribute
older revision evidence to it.

## Verification evidence

### Executed for explicit steps-sync revision `b593679`

| Check | Result | What it proves |
| --- | --- | --- |
| `swift test` in `ios/GameTimeCore` after a clean generated build | Pass, 103 tests in 9 suites | Completed-interval planning, hourly bucketing, timezone/window boundaries, exact-byte metric queue restoration, duplicate rejection, and account-agnostic portable primitives remain green |
| Product `GameTimeTests` on iPhone 17 Simulator, Debug, without signing | Pass, 68 tests; 0 failures; no warnings | HealthKit authorization outcomes, exact boundary pairing, merged phone/watch totals, non-device exclusion, coordinator chunking and failure boundaries, exact-body persistence, offline/relaunch retry, response-count integrity, account isolation, registration-response recovery, privacy diagnostics, and configuration safety pass together |
| Product `GameTimeUITests` on iPhone 17 Simulator | Pass, 10 tests; 0 failures; no warnings | The explicit Staging activity actions and existing challenge/demo/recovery surfaces remain navigable |
| `GameTimeConformance` tests on iPhone 17 Simulator, Debug, without signing | Pass, 10 tests; 0 failures; no warnings | The existing App Attest request, CBOR, and replay conformance contract still passes after product integration |
| `GameTime-Staging` simulator build, Staging, without signing | Pass; no warnings | The staging product compiles with the dedicated HealthKit/App Attest entitlements and activity permission description |
| `GameTime` simulator build, Release, without signing | Pass; no warnings | Release compiles with its original entitlement/plist path; its environment and mutation locks follow the optional local secrets include, activity sync remains disabled, and fixture routing is absent |
| `deno fmt --check`, `deno lint`, `deno check .`, and `deno test --allow-env` from `supabase/functions` | Pass; format checked 42 files, lint checked 41 files, 313 tests passed | The Edge/shared TypeScript tree remains formatted, lint-clean, type-safe, and behaviorally green, including metric-failure detail redaction, strict staging-only additional App IDs, exact successful-App-ID receipt binding, and product metric assertion verification |
| `./scripts/db-test.sh` against the local Supabase stack | Prior current-slice pass after local reset/reseed: 21 pgTAP files / 869 assertions; not rerun after the final client-only edits because Docker health inspection did not return | Existing database ingest idempotency, RLS, challenge, and result invariants passed on the unchanged database SQL; this finalization makes no fresh pgTAP claim and did not exercise or mutate hosted staging |
| Strict `swift-format` lint for the 11 new Swift files; `plutil -lint` for product/Staging plists and entitlements; scoped forbidden-API/log scans; `bash -n`; `git diff --check` | Pass | New Swift files are formatter-clean, configuration files parse, no new App Attest bypass/location/APNs/raw-data logging hook was found in the scoped product files, shell syntax parses, and the patch has no whitespace errors |

These are local simulator, package, static, and local-database results. They do
not prove Apple provisioning, HealthKit behavior on a physical iPhone, hosted
product App Attest identity, two-account synchronization, or signed
distribution.

### Earlier revision evidence

The rows in this section predate explicit steps-sync revision `b593679`. They
remain historical evidence for the named revisions and scopes only.

| Check | Result | What it proves |
| --- | --- | --- |
| M8.3d product compile gates | Debug build, Debug build-for-testing, Staging build, and Release build pass with no warnings | New unit/UI sources compile; Staging includes the explicit demo path, while Release compiles with fixture code absent. Runtime tests still require a booted simulator |
| Deno lint | Pass, 41 files checked | That revision's TypeScript satisfies configured lint rules |
| Deno type-check | Pass | That revision's Edge Function/shared code type-checks |
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
| M8.1 pull-request CI | PR #11 initial head `c363610` passed all four jobs in [run 30236956570](https://github.com/m1jenkins/GameTime/actions/runs/30236956570); the Xcode 26.2 job completed in 15m 8s | A clean GitHub-hosted run reproduced pgTAP, Deno, GameTimeCore, product tests, Staging/Release builds, and conformance tests for that historical revision; record a separate current-main result for `b593679` or its direct successor |
| Supported local database inspection | Pass; database/index/role stats and outliers reviewed, with no bloat, blocking queries, or long-running queries | Local runtime health after the clean suite; fresh-test index counters are diagnostic and do not justify dropping indexes |
| Staging migration reconciliation | Migrations through `20260726070000` were already applied; forward repair `20260726230529` applied successfully | The applied migration remains immutable and staging history now carries the generated-column repair as a new migration |
| Staging manual retention cycle | At 2026-07-26 23:09:47 UTC, 2 exact-location rows were pruned and 1 source-identifier pair was scrubbed; 3 immutable events were appended; immediate rerun returned all zeros | The repaired guard permits only the worker scrub, stored ranges recompute correctly, audit output is durable, and the worker is idempotent |
| Hosted retention cron | The 2026-07-26 23:17:00 UTC run succeeded in 28 ms and processed a second committed synthetic probe | The scheduled worker can see committed eligible rows and invoke the repaired retention path |

### Not executed in this audit

| Check | Why | Required follow-up |
| --- | --- | --- |
| Hosted Security and Performance Advisors | Supabase CLI 2.109.1 exposes local lint and `inspect db`, but no local `advisors` command; the product advisors are hosted Dashboard checks | Run both advisors against the staged D81 schema and investigate every finding |
| Hosted product App Attest rollout and physical HealthKit proof | The local registration/assertion verifier now supports the staging product identity without changing the primary conformance identity, and one connected-device profile contains the required capabilities; the hosted functions/configuration are older and no physical acceptance record exists | With separate approval, configure the product additional App ID, deploy only the reviewed registration/metric bundles, rerun rejection/conformance probes, complete keychain signing approval, provision a second device, and record two accepted uploads plus one exact replay without a bypass |
| M8.1 two-user Apple staging proof | Product App ID/team provisioning and a bounded one-user reload proof now pass; Apple-name prefill and the second authenticated user remain open | Re-observe the first-sign-in Apple name with an eligible fresh or re-authorized test account, then complete `M8_1_STAGING_ACCEPTANCE.md`, including force-quit reloads, one lost challenge response, and one lost metric response |
| Hosted activation cron proof | pgTAP transactions cannot be observed by the background worker; only the retention job has a committed-row staging proof | Record a committed-row activation run and exercise its downstream paths |

## Milestone ledger

| Milestone | Status | Delivered | Still open |
| --- | --- | --- | --- |
| M0 | Complete baseline | Supabase scaffold, migrations, local scripts, pgTAP/Deno/Swift CI with pinned Supabase/Deno/Xcode versions | Record current-main CI and add deployment/rollback automation |
| M1 | Complete in repo | Profiles, friendships, groups, membership, blocks, RLS, guarded RPCs, and exact-handle friendship UI | Group/profile-management UI; handle throttling/avatar storage |
| M2 | Complete in repo | Charities schema, contests, invitations, participant lifecycle, activation primitive | Verified production charity data |
| M3 | Complete in repo | Attested metric ledger, idempotent ingest, local-hour bucketing/provenance/queue core | Physical product HealthKit/App Attest proof and background delivery |
| M4 | Complete in repo | Deterministic TypeScript scoring and fixture corpus | Production data-loading/finalizer orchestrator |
| M5 | Complete in repo | Integrity scoring, quarantines/reviews, source reputation, timezone epochs | D76 escalation/adjudicator operation |
| M6 | Complete in repo | Geofences, workout overlap, trusted-location integrity, exact-byte check-in queue | Live Core Location/HealthKit workout collection |
| M6.5 | Gate open | Staging backend, conformance target, independent receipt verification, runbook, paid-team identity, and one signed/installed/launched Staging product build with the required capabilities | Provision and run the focused conformance target: App Attest registration, one signed metric and check-in, exact replay/counter checks, and receipt/public-key audit |
| M7.1 | Complete | D74–D82 product contract | Implementation of most settlement domain |
| M7.2a | Implemented | Transactional notification intents and named one-minute activation job | Hosted committed-row activation proof |
| D81 foundation | Staged; local and retention-cycle proven | Durable actors, atomic service-only deletion, capabilities, holds/cutoffs, raw-retention worker, forward generated-column repair | Broader concurrency/production-shaped migration, hosted advisors, hold/failure recovery; user-facing deletion/capability path |
| M7 finalization/settlement | First-result foundation implemented but dormant | Immutable provisional/final snapshots, explicit first results, versioned scoring/integrity inputs, accepted-participant redacted reads, ingest serialization, and exact per-debtor obligations | Trusted evidence loading, complete persisted assessments, D76 adjudication, hosted caller, claims, disputes, actionability, reliability, and deadline workers |
| M8 | Repository slices present; partial single-user staging proof recorded; full milestone open | Product Xcode target, native Apple token exchange, exact-handle social/challenge loop, immutable review and staging diagnostics, protected challenge retry, M7-backed rankings, isolated demo, locally verified source-merged Apple-device steps sync with visible exact totals and exact-byte account isolation, and a bounded staging-only product App Attest identity bridge | Apple-name prefill, approved hosted verifier rollout, signed two-device challenge and step-sync acceptance, background HealthKit, Core Location, other pending actions, inbox/APNs, later M7 screens, privacy/release hardening |

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
- complete immutable creator/invitee review plus staging-only challenge ID and
  roster diagnostics, including a stable breakpoint after the challenge
  creation response;
- in revision `b593679`, explicit steps-only HealthKit authorization and
  sync for active staging challenges, completed frozen-timezone interval
  planning, source-merged Apple-device statistics that avoid phone/watch
  double counting, exact boundary pairing, visible confirmed/retained totals,
  bounded multi-request delivery, `IngestQueue`/`PendingBatch`,
  `MetricIngestPayload.swift` encoding, account-specific protected persistence,
  product App Attest registration/assertion retry, and a bounded
  non-production-only product App ID verifier path without a development bypass
  or raw health/request logging;
- append-only standings snapshots, explicit first results, configuration
  versions, per-debtor obligations, and accepted-participant phase-redacted
  reads behind a service-only publication boundary;
- challenge-detail provisional/final ranking UI with account-isolated loading
  state, caller-only live integrity detail, and own-obligation disclosure;
- a payload-free transactional notification-intent ledger and named activation
  scheduler; and
- on `main`, durable pseudonymous actors, stale-JWT denial,
  account-deletion capabilities, retention policies/holds/events, and an hourly
  raw-evidence pruner.

## Current plan

This dated status record does not own work priority or sequencing. See
[`PLAN.md`](../PLAN.md) for the current repository gates, milestone work, and
recommended next sequence.

## Claims that should not be made yet

- The app is usable, beta-ready, or App Store ready.
- M8.1 is complete before its two-user Apple staging record exists.
- HealthKit or product App Attest is complete before two physical accounts
  produce accepted step uploads and the lost-response replay is recorded.
- Full M8 is complete merely because the M8.3a creation, M8.3c standings, and
  M8.3d demo plus explicit steps-sync slices are locally implemented.
- Revision `b593679` or its current-main successor has a recorded green CI run.
  Historical PR #11 CI covers a revision containing D81, not the current
  repository revision.
- D81 is safe to deploy at production scale before its concurrency,
  production-shaped staging, advisor, and failure-recovery gates pass.
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
