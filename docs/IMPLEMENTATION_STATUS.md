# GameTime implementation status

> Audit snapshot: synchronized `origin/main` baseline `167d31b`, including the
> M8.3c M7-backed standings, M8.3d isolated on-device demo, staging-only
> explicit steps-sync slice, and device-independent M7 trusted assessment.
> Branch `codex/m7-d76-review-deadlines` adds the bounded D76
> deadline/escalation slice; its local database and Deno verification passed on
> 2026-07-30. The working tree also adds a locally verified M8.4 lead-loss
> push/deep-link/reaction slice; no hosted deployment or APNs device proof was
> performed.
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
complete two-user flow remain open. Full M8 remains open. The M7 repository now
implements trusted evidence loading, canonical TypeScript assessment, complete
immutable persistence, exact quarantine materialization, assessment-gated
results, and the bounded D76 deadline/escalation state machine. Operated
adjudicator authorization/queues, an authorized hosted normal finalizer,
actionable settlement/disputes, and later M8 background sensor, inbox/APNs, and
release slices remain to be built.

The M8.4 working-tree slice converts a rank-1-to-lower-rank standings transition
into one generic, idempotent M7 notification intent, then leases delivery to a
secret-authenticated Edge Function that speaks directly to APNs. Device tokens
are actor-bound, invalid tokens are retired, delivery state does not mutate the
append-only intent, and notification content carries no metric totals or health
data. A default tap routes to the accepted participant's standings; the
notification and standings screen both expose an idempotent **I’m coming back
😤** reaction. Hosted secrets/function/cron, Apple provisioning, and a real
two-account lead change remain open.

The M7 slice reads `contest_evidence`, source metadata for versioned reputation
rules, applied timezone epochs, complete quarantine state,
`contest_checkin_integrity`, and trusted accepted/attested inside-location
observations through one service-only loader. A strict dormant TypeScript
operation invokes the existing scoring/integrity engine and submits a
privacy-minimized assessment to an append-only private ledger. PostgreSQL
rechecks the frozen evidence digest, serializes concurrent attempts,
materializes every required quarantine before inserting the assessment, and
requires the exact assessment for a final result and every final standing.
D76 adds immutable grace-anchored review deadlines, immediate rejection
escalation, bounded adjudication, idempotent explicit clearance, payload-free
outbox events, and a named local worker whose only result path is
`inconclusive:review_timeout` with no obligation. No hosted caller, operated
operator queue, deployment, product UI, or normal winner/obligation finalizer
was added.

M8.3d adds a separately labeled, in-memory demo to Debug and Staging. A
single tester can search `david1` or `david2`, add the synthetic profile with a
transparent instant demo acceptance, and select the new friend in challenge
creation. The retained live model and Supabase data are unchanged, demo state
is discarded on exit, and Release does not compile the fixture factory. This
does not satisfy the live two-user acceptance gate.

The current working tree improves the physical acceptance path without closing
it. Creator and invitee views now expose the immutable window, timezone, and
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

A 2026-07-29 physical-device retry built, signed, installed, and launched this
working tree on one iPhone. The tester confirmed the amber Staging banner and
live four-tab shell. The Challenges screen correctly showed no challenges and
kept creation disabled because this account has no accepted friendship. This is
current one-device runtime evidence, not the required two-user run. The tester
then deferred the remaining physical acceptance because a second friend/device
was unavailable; no HealthKit or metric-upload action was attempted.

During the final source review, the connected iPhone accepted a fresh signed
Staging build, but the launch request was denied because the device remained
locked. This confirms current-tree device compilation/signing only; it does not
replace the earlier launch observation or add any HealthKit/runtime evidence.

This activity slice has no background delivery. It also adds no workouts, Core
Location, settlement, donations, disputes, APNs, TestFlight, or production
release work. The local verifier now keeps `com.gametime.conformance` as its
primary identity and accepts a strict, maximum-three
`APPLE_ADDITIONAL_BUNDLE_IDS` list for product registration and metric
assertions outside production only. Receipt verification uses the exact App ID
that passed attestation; check-in remains primary-only; production rejects the
additional list. The approved Staging rollout added the product App ID,
preserved the conformance primary identity and development-only acceptance,
and kept `ATTEST_DEV_BYPASS` absent. The explicit deployment named only
`attest-device` and `ingest-metrics`; all returned files for those functions
match the committed source. Supabase's secret propagation also advanced the
active `ingest-checkin` configuration version without including it in the
deployment command, and its returned source still matches the commit. Hosted
fail-closed and authenticated rejection probes passed without sending
HealthKit data. Physical App Attest conformance and the two-account steps run
remain open.

A current readiness attempt stopped before execution because 0/2 connected
physical devices were available. No device session or staging account was
opened, no App Attest or HealthKit action was attempted, and no sensor data was
sent. A read-only connector check found the staging project healthy and 3/3
functions active. The local CLI lacked Management API authentication, so the
secret-name list was not independently refreshed; the approved rollout remains
the latest evidence that `ATTEST_DEV_BYPASS` is absent.

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

The explicit steps-sync work is part of the audited repository baseline. Its
local evidence is recorded separately below; do not attribute older revision
evidence to it.

## Verification evidence

### Executed for the current M7 D76 branch

| Check | Result | What it proves |
| --- | --- | --- |
| `./scripts/db-test.sh` from the workspace | Pass, all 21 migrations and 26 pgTAP files / 1,104 assertions | The complete prior 1,004-assertion suite remains green; 67 focused D76 assertions cover boundaries, authorization, retries, tombstones, outbox, and fail-closed results, while 33 D76 concurrency assertions exercise both reviewer/worker commit orders and both clearance/timeout commit orders in real sessions |
| `deno fmt --check`, `deno lint`, `deno check .`, and `deno test --allow-env` from `supabase/functions` | Pass; 44 files format-checked, 43 files linted, all modules type-checked, 323 tests passed | Required sidecars fail closed when absent, the canonical assessment is deterministic and privacy-minimized, the dormant load/assess/record operation is composed, and the service adapter preserves the exact envelope |
| `supabase db lint --local --schema app,public --level warning --fail-on warning` | Pass, zero warnings or errors | The production schemas contain no PL/pgSQL/schema findings under the local Supabase linter |
| Focused D76 privilege and migration review | Pass; private adjudication tables have RLS and no application-role table grants, clearance and the real-clock worker are service-only, the test-time clock helper is withheld, all privileged routines pin blank `search_path`, and transition intents contain no payload column | The local mutation surface is least-privileged and does not expose evidence or operator detail |
| Recent GitHub Actions audit | Current `main` run [30565946352](https://github.com/m1jenkins/GameTime/actions/runs/30565946352) stopped before any job started because GitHub reported an account payment/spending-limit problem | Latest-head CI remains externally open; this run supplies neither a code failure nor a green result |

These checks are local database, TypeScript, and static evidence. No hosted
Supabase state, cron execution, operated adjudication, physical device, Swift
product code, deployment, or release surface changed in this slice. The clean
reset proves forward migration execution on the local fixture database; it
does not measure the D76 deadline backfill or table-lock duration on a
populated production-shaped copy.

### Executed for the M8.4 lead-loss push/reaction working tree

| Check | Result | What it proves |
| --- | --- | --- |
| Clean local reset and `./scripts/db-test.sh` | Pass, 27 pgTAP files / 1,130 assertions | The complete database suite remains green with transition detection, intent idempotency, guarded reaction/token RPCs, delivery leasing/retry recording, and the named dispatch job |
| `deno fmt --check`, lint, type-check, and focused tests for `deliver-push` | Pass, 4 tests | The APNs adapter and secret-authenticated handler are formatted, lint-clean, type-safe, and cover successful delivery plus permanent/retryable failure classification |
| Product Debug build, unsigned Staging/Release builds, and full `GameTimeTests` on iPhone 16e Simulator | Pass, no build warnings; 70 unit tests | Push registration wiring, direct standings routing, reaction idempotency, and existing product behavior compile and pass together; Staging selects development APNs while Release selects production and retains its fixture lock |
| Targeted `GameTimeUITests.testProvisionalAndFinalStandingsDisclosure` | Pass, 1 test / 0 failures | A below-first participant sees and sends the comeback reaction in provisional standings, receives the sent state, and the existing final disclosure path remains intact |
| Entitlement plist lint, focused Swift formatting, and whitespace review | Pass | Development/production APNs entitlement selection parses, new Swift/Edge files satisfy their formatters, and the feature patch has no whitespace errors |

This evidence is local database, simulator, and unit-level APNs-adapter proof.
It does not prove Apple Developer capability/provisioning, a provider-accepted
push, hosted Vault/Edge/cron configuration, physical-device notification
presentation, or a real two-user standings transition.

### Executed for the explicit steps-sync repository slice

| Check | Result | What it proves |
| --- | --- | --- |
| `swift test` in `ios/GameTimeCore` after a clean generated build | Pass, 103 tests in 9 suites | Completed-interval planning, hourly bucketing, timezone/window boundaries, exact-byte metric queue restoration, duplicate rejection, and account-agnostic portable primitives remain green |
| Product `GameTimeTests` on iPhone 17 Simulator, Debug, without signing | Pass, 68 tests; 0 failures; no warnings | HealthKit authorization outcomes, exact boundary pairing, merged phone/watch totals, non-device exclusion, coordinator chunking and failure boundaries, exact-body persistence, offline/relaunch retry, response-count integrity, account isolation, registration-response recovery, privacy diagnostics, and configuration safety pass together |
| Product `GameTimeUITests` on iPhone 17 Simulator | Pass, 10 tests; 0 failures; no warnings | The explicit Staging activity actions and existing challenge/demo/recovery surfaces remain navigable |
| `GameTimeConformance` tests on iPhone 17 Simulator, Debug, without signing | Pass, 10 tests; 0 failures; no warnings | The existing App Attest request, CBOR, and replay conformance contract still passes after product integration |
| `GameTime-Staging` simulator build, Staging, without signing | Pass; no warnings | The staging product compiles with the dedicated HealthKit/App Attest entitlements and activity permission description |
| `GameTime` simulator build, Release, without signing | Pass; no warnings | Release compiles with its original entitlement/plist path; its environment and mutation locks follow the optional local secrets include, activity sync remains disabled, and fixture routing is absent |
| `deno fmt --check`, `deno lint`, `deno check .`, and `deno test --allow-env` from `supabase/functions` | Pass; format checked 42 files, lint checked 41 files, 313 tests passed | The Edge/shared TypeScript tree remains formatted, lint-clean, type-safe, and behaviorally green, including metric-failure detail redaction, strict staging-only additional App IDs, exact successful-App-ID receipt binding, and product metric assertion verification |
| Approved Staging configuration and function verification | Pass; 5/5 required configuration checks, 34/34 returned function files matched, and 2/2 explicitly deployed functions are active | The conformance primary identity, product additional identity, development-only setting, staging environment, and bypass absence match the reviewed configuration. `attest-device` is active at version 29 and `ingest-metrics` at version 22; the configuration-propagated `ingest-checkin` version 21 also remains source-identical |
| Hosted no-data probes | Pass; 4/4 fail-closed cases and 3/3 authenticated availability/rejection cases | Missing and forged authentication fail closed, a malformed registration is rejected, and a partial App Attest header pair is rejected before metric persistence. No HealthKit upload or physical App Attest conformance was attempted |
| Current physical readiness inventory | Blocked; 0/2 devices available | The acceptance run stopped before build, launch, account access, App Attest, or HealthKit. Physical proof remains unchanged |
| Current connected hosted inventory | Partial; project healthy and 3/3 functions active | Read-only status was available, but Management API authentication was unavailable for a fresh secret-name listing. No hosted configuration or deployment changed |
| `./scripts/db-test.sh` against a clean local Supabase stack | Pass, 21 pgTAP files / 869 assertions; cleanup passed | Every migration and database assertion passed after Docker recovery. The gate ran from a verified byte-identical temporary checkout because iCloud-offloaded SQL files could not be read reliably from the workspace; `supabase stop --no-backup` removed the local volumes afterward |
| Strict `swift-format` lint for the 11 new Swift files; `plutil -lint` for product/Staging plists and entitlements; scoped forbidden-API/log scans; `bash -n`; `git diff --check` | Pass | New Swift files are formatter-clean, configuration files parse, no new App Attest bypass/location/APNs/raw-data logging hook was found in the scoped product files, shell syntax parses, and the patch has no whitespace errors |

These are local simulator, package, static, and local-database results. They do
not prove Apple provisioning, HealthKit behavior on a physical iPhone, hosted
product App Attest identity, two-account synchronization, or signed
distribution.

### Executed in this audit

The rows in this section predate the current explicit steps-sync working tree.
They remain historical evidence for the named revisions and scopes only.

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
| Hosted product App Attest rollout and physical HealthKit proof | The local registration/assertion verifier now supports the staging product identity without changing the primary conformance identity, and one connected-device profile contains the required capabilities; the hosted functions/configuration are older and no physical acceptance record exists | With separate approval, configure the product additional App ID, deploy only the reviewed registration/metric bundles, rerun rejection/conformance probes, complete keychain signing approval, provision a second device, and record two accepted uploads plus one exact replay without a bypass |
| M8.1 two-user Apple staging proof | Product App ID/team provisioning and a bounded one-user reload proof now pass; Apple-name prefill and the second authenticated user remain open | Re-observe the first-sign-in Apple name with an eligible fresh or re-authorized test account, then complete `M8_1_STAGING_ACCEPTANCE.md`, including force-quit reloads, one lost challenge response, and one lost metric response |
| Hosted activation cron proof | pgTAP transactions cannot be observed by the background worker; only the retention job has a committed-row staging proof | Record a committed-row activation run and exercise its downstream paths |

## Milestone ledger

| Milestone | Status | Delivered | Still open |
| --- | --- | --- | --- |
| M0 | Complete baseline | Supabase scaffold, migrations, local scripts, pgTAP/Deno/Swift CI with pinned Supabase/Deno/Xcode versions | Preserve latest-head/main CI and add deployment/rollback automation |
| M1 | Complete in repo | Profiles, friendships, groups, membership, blocks, RLS and guarded RPCs | Product screens; handle throttling/avatar storage |
| M2 | Complete in repo | Charities schema, contests, invitations, participant lifecycle, activation primitive | Verified production charity data |
| M3 | Complete in repo | Attested metric ledger, idempotent ingest, local-hour bucketing/provenance/queue core | Physical product HealthKit/App Attest proof and background delivery |
| M4 | Complete in repo | Deterministic TypeScript scoring and fixture corpus | Authorized hosted finalizer orchestration |
| M5 | Complete in repo | Integrity scoring, quarantines/reviews, source reputation, timezone epochs | Operated D76 adjudicator authorization and queue |
| M6 | Complete in repo | Geofences, workout overlap, trusted-location integrity, exact-byte check-in queue | Live Core Location/HealthKit workout collection |
| M6.5 | Gate open | Staging backend, conformance target, independent receipt verification, runbook, paid-team identity, and one signed/installed/launched Staging product build with the required capabilities | Complete the conformance Auth fixture and physical App Attest registration, assertion, replay, and receipt observation |
| M7.1 | Complete | D74–D82 product contract | Implementation of most settlement domain |
| M7.2a | Implemented | Transactional notification intents and named one-minute activation job | Hosted committed-row activation proof |
| D81 foundation | Staged; local and retention-cycle proven | Durable actors, atomic service-only deletion, capabilities, holds/cutoffs, raw-retention worker, forward generated-column repair | Broader concurrency/production-shaped migration, hosted advisors, hold/failure recovery; user-facing deletion/capability path |
| M7 finalization/settlement | Trusted assessment, D76 deadline, and first-result foundations implemented locally but normal finalization remains dormant | Canonical service-only evidence loading, immutable versioned complete assessments, exact quarantine materialization, retry/concurrency safety, D76 peer/adjudication deadlines, explicit clearance, fail-closed timeout, assessment-gated final results/standings, accepted-participant redacted reads, and exact per-debtor obligations | Operated adjudicator authorization/queues, authorized hosted normal-finalizer caller, claims, disputes, actionability, reliability, and remaining deadline workers |
| M8 | Repository slices present; partial single-user staging proof recorded; full milestone open | Product Xcode target, native Apple token exchange, exact-handle social/challenge loop, immutable review and staging diagnostics, protected challenge retry, M7-backed rankings, isolated demo, locally verified source-merged Apple-device steps sync, a bounded staging-only product App Attest identity bridge, and a locally verified lead-loss push/deep-link/reaction path | Apple-name prefill, approved hosted verifier and push rollout, signed two-device challenge/step-sync/lead-loss acceptance, background HealthKit, Core Location, remaining inbox actions, later M7 screens, privacy/release hardening |

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
- in the current working tree, explicit steps-only HealthKit authorization and
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

The trusted load, canonical assessment, quarantine materialization, immutable
persistence, D76 deadline/escalation state machine, and real concurrent
assessment/review/timeout proof are complete locally.
Remaining:

1. Add explicit adjudicator authorization, guarded queues, conflict handling,
   and audit/observability boundaries.
2. Review and operate the named D76 worker with committed staging rows,
   a production-shaped backfill/lock measurement, scheduler-failure alerts,
   staffing, and an on-call/SLA runbook.
3. Install an authorized hosted caller that invokes the dormant assessment
   operation and the existing serialized, grace-gated first-result publisher
   only after D76 permits finality.
4. Operate the finalizer in staging with authorized queues, observability,
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

1. Connect, unlock, trust, and keep awake two physical devices provisioned
   through the eligible paid team with Sign in with Apple, HealthKit, and
   development App Attest. The current readiness inventory had 0/2 available.
2. Do not repeat the completed hosted rollout. Before physical traffic,
   re-list the secret names read-only and confirm
   `APPLE_BUNDLE_ID=com.gametime.conformance`,
   `APPLE_ADDITIONAL_BUNDLE_IDS=com.mjenkins.gametime.staging`,
   Staging-only `APP_ATTEST_ALLOW_DEVELOPMENT=true`, and
   `ATTEST_DEV_BYPASS` absence. Obtain explicit approval before any further
   hosted mutation or deployment.
3. Record the two-account challenge run and two real step uploads, including
   force-quit restore, lost-response exact retry, replay acceptance, account
   isolation, and the app-log privacy check. Keep Release locked.
4. Add HealthKit background delivery and Core Location/workout capture through
   the existing exact-byte queues.
5. Extend the protected pending-action model beyond challenge creation, add a
   durable in-app inbox, and expand the locally implemented lead-loss APNs path
   to the remaining action-required events.
6. Add review/adjudication and actionable settlement/dispute screens only after
   M7 supplies those APIs; stage-prove the implemented standings read surface.
7. Complete accessibility/privacy hardening, avatar/group-feed policy,
   reminders, and App Store release work.

## Recommended next sequence

1. **Repository proof:** obtain one green database/Deno/Swift/CI result on the
   reconciled revision.
2. **External proof sprint:** close M6.5, M7.2b, and the remaining retention
   failure-recovery proof while the staging environment is active.
3. **Operated-adjudicator slice:** add explicit D76 authorization, guarded
   operator queues, conflict checks, observability, staffing, alerts, and an
   SLA/runbook; review-gate that slice before any hosted caller or timer
   acceptance.
4. **Settlement slice:** obligations, confirmation, disputes, reliability, and
   their operated deadlines.
5. **Product slice:** close M8.1 and explicit steps-sync external proof, then
   add background sensor delivery, remaining protected actions, the durable
   inbox and hosted/device proof for lead-loss APNs, and later M7-backed product
   slices.
6. **Launch hardening:** charities, monitoring, rate limits, privacy/abuse,
   backup/restore, deployment controls, accessibility, and App Store evidence.

## Claims that should not be made yet

- The app is usable, beta-ready, or App Store ready.
- M8.1 is complete before its two-user Apple staging record exists.
- HealthKit or product App Attest is complete before two physical accounts
  produce accepted step uploads and the lost-response replay is recorded.
- Full M8 is complete merely because the M8.3a creation, M8.3c standings, and
  M8.3d demo plus explicit steps-sync slices are locally implemented.
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
