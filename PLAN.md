# Implementation plan

Audited and reconciled 2026-07-28 against the code, tests, documentation, local
history, and `origin/main`. The current working tree also contains a narrow,
staging-only steps sync slice whose local automated verification is green.
README.md is the compact ledger of what is built; DECISIONS.md records why.
This file owns sequence, remaining work, and launch blockers. The dated evidence
and verification caveats are in `docs/IMPLEMENTATION_STATUS.md`.

## Current state

| Milestone | State | Delivered scope |
| --- | --- | --- |
| M0–M4 | Complete | Scaffold, social graph, contests, attested metric ledger, deterministic scoring |
| M5 | Complete | Integrity scoring, quarantine review, source reputation, consented timezone epochs |
| M6 | Complete | Attested geofence/workout validation, durable check-in queue primitives, trusted-location integrity inputs |
| M6.5 | In progress — conformance gate | Harness, independent receipt verification, and staging backend are verified; App Attest-capable signing and physical-iPhone proof remain |
| M7 | M7.2a, D81, and the M8.3c first-result foundation implemented | Product contract D74–D82, transactional outbox, activation job, account deletion/retention, immutable standings snapshots, explicit first results, and per-debtor obligations are integrated; the trusted evidence-loading/adjudication orchestrator, disputes, settlement, and external gates remain |
| M8 | M8.1 code path and later repository slices are present; acceptance remains open | Separate product app, Apple auth, exact-handle friendship, immutable challenge review, staging diagnostics, and locally implemented explicit Apple-device steps sync with HealthKit source merging, product App Attest, visible confirmed totals, and an account-isolated exact-byte retry queue; two-user/device proof, hosted product App Attest identity, background delivery, and later product slices remain |

M6's boundary is backend plus portable client core. It does not include live
Core Location collection, HealthKit queries, or a production scoring/finalizer
orchestrator; the first two belong to M8 and the orchestrator belongs to M7.

## Audit snapshot and immediate repository gate

Local audit/D81 commit `c6bfed67` and upstream M6.5 hardening commit `cc8f440`
are now reconciled on `main`. The combined branch contains D81's
account-deletion/retention migrations and tests together with the hosted PKI.js
runtime fix and reviewed staging configuration. Reconciliation removes the
repository split; it does not substitute for the Swift, CI, concurrency,
production-shaped migration, or remaining external proofs listed below.

The 2026-07-26 local audit established:

- Deno lint and type-check pass; all 287 Deno tests pass.
- All 16 migration files execute in a clean PostgreSQL 17 reset, and all five Bash
  scripts pass `bash -n`.
- The later D81 integration pass completed a clean migration reset and all 18
  pgTAP files: 733 assertions passed. Supabase CLI 2.109.1 also reported no
  `public`/`app` lint errors and no local bloat, blockers, or long-running
  queries through the supported inspection commands.
- The original audit host could not execute Xcode. The M8.1 pass later ran all
  88 GameTimeCore tests, 15 product unit tests, 6 product UI tests, and 10
  conformance tests locally under Xcode 26.2. Staging and Release both build
  without signing and warnings.
- `deno fmt --check` is blocked on this Windows checkout by CRLF conversion in
  otherwise unchanged tracked files. Verify from an LF checkout rather than
  formatting 25 files as audit noise.

The M8.1 pass also completed a clean 18-migration reset and all 20 pgTAP files:
824 assertions passed, including the bounded friendship, stale-JWT,
block/tombstone, atomic rollback, idempotent retry, changed-payload, and
two-session concurrent duplicate cases. The `public` and `app` schemas remain
clean under `supabase db lint`.

The 2026-07-28 M8.3a pass repeated the clean 18-migration / 824-assertion
database gate, including a two-invitee atomic roster and order-independent
same-request retry. It also passed 30 product unit tests, 7 product UI tests,
both unsigned Staging/Release simulator builds, 88 GameTimeCore tests, 10
conformance tests, strict Swift formatting, and local `public`/`app` schema
lint without warnings or errors.

The M8.3c pass applies 19 migrations and passes all 21 pgTAP files / 869
assertions, including the accepted-roster, disclosure, first-result,
idempotency, grace, append-only, and per-debtor obligation contracts. Deno
format, lint, type-check, and all 305 tests pass. The product target builds and
launches on an iPhone 17 simulator; 34 product unit tests and 8 UI tests pass,
including provisional rival-integrity redaction and final loser-obligation
fixtures. The local `public`/`app` schema lint reports no errors.

PR #11's initial M8.1 head (`c363610`) passed all four GitHub Actions jobs in
[run 30236956570](https://github.com/m1jenkins/GameTime/actions/runs/30236956570):
database, Deno, GameTimeCore, and the complete Xcode 26.2 product/configuration/
conformance job. The checkout runtime maintenance follow-up must also be green
before merge.

Remaining repository gates:

1. Keep the complete GitHub Actions result green for the latest M8.1 head and
   the post-merge `main` revision.
2. Re-check from a fresh checkout that the repository-wide LF rule removes
   Windows format/script drift without creating unintended source changes.
3. Run the hosted Security and Performance Advisors and the remaining
   production-shaped migration/operations proofs.

## Corrections retained from the prior audit

- Reconciled the two feature commits that completed M5 and implemented M6.
- Made timezone and quarantine review quorum immutable. Account deletion cannot
  erase a vote, shrink consent into approval, or reopen a terminal rejection.
- Enforced timezone epochs strictly inside the contest window and removed a
  millisecond-precision race from the pgTAP assertion.
- Made `service_role` privileges deterministic and denied direct mutation of
  derived consent/check-in ledgers; writes stay behind their guarded RPCs.
- Made metric batches, hourly snapshots, and quarantine audit rows owner-only;
  D77 peer review now binds to the evidence row's exact contest and exposes only
  phase-labelled, redacted pending-claim facts.
- Made the portable check-in queue restorable from persisted exact body bytes
  and fail visibly at capacity instead of evicting irreplaceable location
  evidence.
- Replaced literal NUL bytes in the scoring source with the equivalent escaped
  separator so normal text-search tools index the file.
- Confirmed the local toolchain: Xcode 26.2, iOS 26.2 SDK, and Swift 6.2.3.
  The chosen iOS 18 deployment target remains valid.

## M6.5 — device-conformance spike

This is the current engineering work because App Attest is the trust root for
both metric and check-in ingest. The repository now checks its verifier against
Apple's public 2026 attestation vector as well as its synthetic signer, but only
a physical-device run can prove the complete staging exchange.

Definition of done:

1. Provision a staging Supabase project and configure Apple's real App Attest
   attestation and receipt root certificates.
2. Use a small device target on a real iPhone to register one App Attest key.
3. Submit one signed metric batch and one signed geofence check-in using the
   exact production envelopes.
4. Confirm the attestation receipt/public-key representation and assertion
   counter behavior called out in D46.
5. Capture a repeatable smoke-test procedure and remove any development bypass
   from staging.

M6.5 owns a conformance-only device target, not the product app. This spike does
not need the full UI; its target can become the first thin slice of M8 if
maintaining a throwaway target would cost more than keeping it.

Implemented locally:

- A conformance-only iOS 18 target that persists one App Attest key, sends the
  exact production metric and check-in bodies, decodes counters, and replays the
  identical signed requests.
- Backward-compatible iOS 18–26 attestation parsing plus strict all-or-nothing
  parsing of Apple's iOS 27 COSE key/extensions suffix, with
  certificate/COSE/key-id binding and the published 2026 vector pinned.
- Independent, bounded BER/PKCS#7 receipt verification against Apple's
  fingerprint-pinned Root CA G3, including signature and chain, dedicated
  receipt-signer purpose, App ID, creation time, and stored public-key binding.
- Private quarantine of Apple's opaque attestation receipt on every failure.
  Only a service-role-only, digest-bound RPC can set
  `current_receipt_verified_at`, and only after the complete verifier succeeds.
- Hosted JWT verification from Supabase's injected JWKS, a separate challenge
  HMAC secret, and support for opaque hosted admin keys.
- Fingerprint-pinned, checked-in-project-identity-guarded staging scripts, a
  deterministic SQL fixture, database verification queries, and a real-device
  smoke runbook.

The staging project is linked; all migrations through D81 plus forward repair
`20260726230529`, the required secrets, and three Edge Functions are deployed.
A committed synthetic retention lineage proved both the repaired
source-identifier scrub and exact-location pruning; the hourly hosted worker is
recorded separately below. A 2026-07-29 retry used the paid team and a
development profile containing Sign in with Apple, HealthKit, and development
App Attest to build, sign, install, and launch `GameTime-Staging` on the
connected iPhone. The build log shows the intended entitlement file at CodeSign,
and the resulting CodeDirectory contains both legacy and DER entitlement slots.
This closes the one-device signing/install prerequisite, not physical HealthKit
or App Attest proof. A second provisioned device, the approved hosted metric
rollout, and the complete runbook remain open.

Do not mark M6.5 complete until the runbook records one successful device
registration, metric, check-in, exact retry, and counter/public-key/receipt audit
with `ATTEST_DEV_BYPASS` absent. That run must show the receipt's server-owned
verification timestamp; no receipt may influence fraud, eligibility, or
settlement while that timestamp is absent.

## M7 — settlement and finalization

M7 starts with decisions, then proves scheduling, then adds money-adjacent state.
M7.1 is complete as a documentation/product-contract slice. M7.2's outbox,
activation infrastructure, and D81's pre-result account-deletion foundation may
proceed while M6.5 awaits App Attest-capable signing and physical-device proof
because they create no settlement-bearing result. M6.5 remains a hard gate
before finalization or settlement is enabled.

### 1. Resolve the product decisions first — complete

- D74 combines provider confirmation, winner acknowledgement, and
  receipt-plus-challenge; self-attestation alone never confirms a pledge.
- D75 makes every contest that ran terminal through an explicit `winner`,
  `all_donate`, `void`, or `inconclusive` result without fabricating a winner.
- D76 allows bounded peer review as soon as quarantine materializes, anchors its
  72-hour deadline no earlier than ingest-grace close, and sends unanswered
  review through adjudication to `inconclusive`, never approval.
- D77 limits standings to accepted participants and phases integrity disclosure
  between provisional live views, self detail, and final rationale.
- D78 gives affected participants a seven-day dispute window, an append-only
  state machine, independent adjudication, and paused obligation/reliability
  effects.
- D79 fixes the versioned, obligation-only reliability formula.
- D80 makes durable notification intents M7's responsibility and APNs delivery
  M8's.
- D81 fixes pseudonymized account deletion before either results or obligations
  can leak the old cascade into schema design.
- D82 fixes activation as a named, inspectable one-minute database job.

### 2. M7.2 — Make activation real

- [x] Build D80's payload-free transactional outbox and retrofit invitation,
  timezone-consent request/resolution, quarantine request/approval, and
  activation/cancellation so each implemented transition commits with its
  durable intent. D76 rejection escalation waits for its adjudication queue.
- [x] Enable `pg_cron` and install D82's named one-minute activation job.
- [x] Call `app.activate_due_contests()` on a tested cadence.
- [x] Establish one idempotent scheduled-worker pattern and registry.
  Activation is the first committed job; the reconciled D81 slice adds raw
  retention. Later M7 slices add finalization/review escalation, claim
  expiration/confirmation/default, dispute timeout, and reminders without
  inventing separate timer semantics.
- [x] Assert the installed schedule, transition/outbox idempotency, cancellation
  semantics, least privilege, append-only enforcement, and stale-JWT denial in
  pgTAP.
- [ ] In staging, observe the background worker fire against committed rows and
  exercise metric ingest, timezone epochs, and check-ins against a contest it
  activated rather than a test-forced row. pgTAP transactions deliberately
  cannot prove background visibility.

### 3. Add the standings/finalization orchestrator

- [x] Implement D81's pre-result durable-actor foundation: replace the
  auth/profile and device-key evidence cascades with pseudonymization and
  retained audit digests; cover authored and accepted pending contests,
  active-contest and challenge-horizon capabilities, profile-field clearing,
  one atomic deletion RPC, generic case-capability authorization, persisted
  operator cutoffs, versioned raw-data retention, and the guarded retention
  worker. The pending pgTAP coverage is designed to assert that deletion cannot
  erase a roster, ingest batch, check-in, or quarantine, prune an active device
  registration, or let a stale JWT authorize the tombstone. Future result,
  obligation, dispute, and donation-receipt migrations attach their child
  scopes and retained facts to these seams.
- [x] Integrate the D81 work on top of `origin/main`.
- [x] Run the full 733-assertion database suite and the supported local
  lint/performance inspection commands.
- [ ] Run CI and clear the hosted Security and Performance Advisors.
- [ ] Add multi-session tests for deletion racing activation, invitation
  acceptance, ingest, receipt marking, hold creation, retention, and future
  finality writes. A single pgTAP transaction cannot prove lock ordering.
- [ ] Apply the 2,860-line deletion migration to a production-shaped staging
  copy, measure migration-wide lock duration, and document backup, deployment
  window, failure recovery, and rollback limits.
- [x] Apply D81 and forward repair `20260726230529` to hosted staging; run a
  committed manual retention cycle plus the next hourly job, and verify
  cutoffs, source scrubbing, generated ranges, immutable events, and an
  idempotent rerun.
- [ ] Exercise a hold-blocked staging cycle and failed-job recovery/alert path.
- [ ] Add the user-facing deletion service path: reauthentication and
  confirmation, one-time capability handoff/storage, an explicit
  lost-capability warning, and capability-authorized APIs. Any recovery
  mechanism requires a separate reviewed design. Never expose the service-only
  database RPC directly to the app.
- [ ] Load `contest_evidence`, source reputation, timezone applied events,
  quarantine state, `contest_checkin_integrity`, and trusted location
  observations into the one TypeScript scoring/integrity pipeline.
- [x] Update the scoring `Outcome` contract and fixtures so `all_donate` returns the
  complete accepted roster. Reject `insufficient_participants` from an active
  contest as an operational invariant failure.
- [x] Narrow metric/quarantine direct rival access and expose D77's
  exact-contest, phase-aware bounded quarantine-review surfaces.
- [x] Expose D77's phase- and role-authorized provisional/final standings and
  bounded final rationale after frozen assessments/results exist.
- [x] Serialize the trusted first-result write with both metric and geofence
  ingest so an in-flight
  request cannot commit evidence after the result is fixed.
- [ ] Before interpreting zero quarantines as clean, persist a complete versioned
  integrity assessment over the frozen evidence and materialize every required
  quarantine. Do not finalize before `app.ingest_grace_period()` closes.
- [ ] Implement D76's per-quarantine review deadline, early-rejection escalation,
  grace-anchored adjudication deadline, explicit clearance, and terminal
  `review_timeout`.
- [ ] Add explicit adjudicator authorization, guarded operator queues/tools,
  conflict checks, observability, and an on-call/SLA runbook for the D76/D78
  deadlines. A schema deadline without an operated queue is not complete.
- [x] Persist explicit `winner`, `all_donate`, `void`, and `inconclusive`
  first results;
  only the first two may create obligations.
- [x] Persist the scoring and integrity configuration versions used for the
  result.

M8.3c supplies the immutable first-result storage and trusted publication/read
boundary, but deliberately installs no finalization cron or hosted caller. The
service-only publisher cannot make the evidence-loading, complete-assessment,
adjudication, M6.5 device, or staging gates true by itself.

### 4. Add settlement, disputes, and reliability

- Append-only winner/loser/amount/charity obligations, plus D75's explicit
  self-directed `all_donate` exception.
- Pledge-confirmation evidence with D74's donation-time and receipt-allocation
  validation, redacted challenger view, and decided confirmation paths.
- D78's shared dispute cases, bounded adjudication, unioned pause intervals, and
  append-only result/obligation effects, including release reinstatement and
  nullable per-event filing deadlines plus one user adjudication opportunity per
  result or obligation event version.
- D79's versioned reliability score from score-bearing obligation outcomes;
  challengeable changes remain provisional through their filing window and the
  canonical server calculation returns its fixed `as_of`.
- Extend D80's outbox to result, actionable-obligation, release, claim, default,
  and dispute events and every deadline M7 owns.
- Extend the shared scheduled-worker registry to claim confirmation/expiration,
  defaults, dispute deadlines, reminders, and retention cutoffs.

## M8 — iOS product loop

### M8.1 — Live social and contest loop

Implemented in `codex/m8-live-social-loop`:

- [x] Separate iOS 18 / Swift 6 product, unit-test, and UI-test targets using
  `GameTimeCore` and an exact `supabase-swift` package pin.
- [x] Native Sign in with Apple nonce exchange, editable first-sign-in name
  prefill, explicit launch/auth/onboarding states, and complete sign-out reset.
- [x] Independent typed navigation per Today, Challenges, Friends, and You;
  centralized sheets; action-first Today; competitive-trust light/dark styling.
- [x] Exact-handle social cards for incoming, outgoing, and accepted
  relationships, with blocks, tombstones, caller isolation, and stale-JWT denial
  enforced by the bounded backend API.
- [x] Challenge editor and immutable creator/invitee review using the four
  backend metrics, daily/cumulative cadence, complete start/end window,
  timezone, target, staging stake, charity, tie-break, and full closed roster.
- [x] Atomic, caller-idempotent contest plus invitation creation with
  same-payload retry and changed-payload rejection.
- [x] Launch, foreground, pull-to-refresh, and post-mutation reloads; no
  Realtime and no automatic mutation retry.
- [x] Debug fixture/live-client parity, loading/empty/offline/future-state
  coverage, and Release-compilation gates that remove fixture routing and keep
  contest mutation disabled.
- [x] Staging-only challenge ID, state, and full-roster diagnostics, plus the
  stable `StagingAcceptanceDiagnostics.challengeCreationResponseReceived`
  breakpoint hook for a repeatable committed-but-unacknowledged creation run.
- [x] A `macos-26` CI job selecting Xcode 26.2 and testing both product and
  conformance schemes without signing.
- [ ] Provision the product App ID through an eligible Apple team and complete
  `docs/M8_1_STAGING_ACCEPTANCE.md` with two Apple-authenticated users,
  force-quit/relaunch after every mutation, a deliberately lost-response retry,
  and one shared pending contest.

The M8.1 repository path is present with staging proof open. M8.1 is not
complete. It is an internal alpha, not an App Store or production release.

### M8.2a — Restart-safe pending challenge action

- [x] Persist one immutable pending challenge per authenticated actor before its
  first network attempt, including the exact request UUID and canonical
  millisecond timestamps stored losslessly for the backend payload hash.
- [x] Store the versioned record atomically under Application Support with
  complete file protection, backup exclusion, account isolation, and
  conflict-checked monotonic attempt updates.
- [x] Retain ambiguous, offline, and cancelled attempts across relaunch; restore
  them only for the matching actor and require a deliberate retry.
- [x] Block a second challenge while recovery is pending or unreadable. Clear
  the record only after a confirmed contest UUID or an explicit warned discard;
  never retry automatically.
- [x] Cover file corruption, envelope versions, cross-account copies, exact
  round trips, changed-record rejection, auth-transition races, sign-out
  detachment, Release locking, lost-response relaunch, and recovery UI with
  product unit/UI fixtures.

This closes one pending-human-action durability gap. It does not complete the
check-in queue integration, other pending human actions, the two-user staging
proof, or full M8.

### M8.3a — Challenge terminology and atomic multi-select creation

- [x] Use Challenge terminology throughout the product domain, routes, clients,
  fixtures, UI, accessibility identifiers, and current tests while retaining
  the backend's established contest/RPC vocabulary.
- [x] Let the creator explicitly select 1–19 accepted friends, disclose the
  selected count, and review every invitee plus the resulting closed roster
  size before committing immutable terms.
- [x] Canonically sort the selected UUIDs and send the complete array,
  `max_participants = invitees + 1`, and one request UUID through exactly one
  `create_contest_with_invites_v1` call. There is no per-friend request loop or
  partial-success client state.
- [x] Advance the protected pending-request envelope to version 2 and migrate a
  version-1 single-invite saved duel in place without changing its actor,
  request UUID, invitee, attempt metadata, or timestamp bit patterns. Future or
  malformed versions still fail closed.
- [x] Cover selection bounds, canonical payload construction, one-call model
  submission, multi-invite atomicity/idempotency, persisted round trips, legacy
  migration, and explicit-retry UI behavior.

This is a repository implementation slice. It does not substitute for the
two-user staging run, and the migrated version-1 path remains intentionally
recognizable as legacy duel data.

### M8.3c — M7-backed standings and first-result obligations

- [x] Decode the canonical accepted-participant standings RPC into typed
  provisional/final, result, integrity-rationale, and obligation models.
- [x] Load standings only for the signed-in accepted participant of an active
  or finalized challenge, with per-challenge loading/error state and complete
  account-transition clearing.
- [x] Present provisional ordering as live progress rather than a predicted
  winner; show the caller's exact integrity detail while keeping rival detail
  redacted.
- [x] Present frozen final rankings, explicit result/rationale, exact integrity
  inputs, and only the signed-in loser's or all-donate participant's recorded
  obligation and review boundary.
- [x] Cover DTO decoding, model isolation, sign-out clearing, fixture/live
  parity, provisional disclosure, final winner display, and the per-loser
  obligation in product unit/UI tests.

This slice is a read surface over the new service-only M7 first-result boundary.
It does not enable hosted finalization, make an obligation actionable, settle a
pledge, resolve a dispute, or close the M6.5/two-user staging gates.

### M8.3d — Isolated on-device social/challenge demo

- [x] Expose an explicit demo entry from signed-out Staging and the You tab
  without replacing or signing out the retained live staging model.
- [x] Keep demo state entirely in memory behind the existing client protocols,
  label it persistently, discard it on exit, and compile its factory out of
  Release.
- [x] Provide exact synthetic handles `david1` and `david2`; accept demo
  requests immediately so a single tester can add David and select that new
  friend in the challenge creator.
- [x] Preserve normal fixture pending-request behavior and cover the interactive
  demo friend/challenge mutation path in product unit and UI targets.

This is a one-device product-flow simulator. It does not exercise Supabase,
Apple Auth, RLS, persistence across demo exits, cross-device notifications, or
the two-user staging acceptance gate.

### M8 staging slice: explicit steps sync

The current working tree implements this slice locally. The consolidated
repository verification gate passed on 2026-07-28; exact commands and counts are
recorded in `docs/IMPLEMENTATION_STATUS.md`. The physical two-account acceptance
gate remains open.

- [x] Expose **Enable Activity** and **Sync Activity** only in Staging for an
  accepted, active steps challenge. HealthKit reads remain user initiated.
- [x] Use the frozen timezone schedule plus `HourlyBucketer` to plan only
  complete, server-admissible local-hour intervals in the immutable challenge
  window. Use raw samples only to identify genuine Apple source revisions and
  devices, then query HealthKit cumulative statistics so overlapping iPhone and
  Apple Watch records are source-merged rather than added twice.
- [x] Upload the merged Apple-device contribution as `device` provenance.
  Manual, unknown, and third-party contributions remain outside this first
  trusted steps slice instead of being mislabeled or combined with a
  source-reconciled total.
- [x] Reuse `IngestQueue`, `PendingBatch`, and the
  `AttestedMetricPayload`/`EncodedMetricRequest` path from
  `MetricIngestPayload.swift`, then persist the exact encoded body before the
  first upload attempt.
- [x] Keep each queue file account-specific, protected, bounded, excluded from
  backup, and restorable across force-quit/relaunch without re-encoding the
  payload.
- [x] Split histories across the endpoint's 2,000-observation and one-megabyte
  limits, drain every chunk on one explicit sync, abandon only permanent
  refusals, and retain ambiguous/retryable exact bytes. Verify that each server
  receipt names the queued batch and exact observation count.
- [x] Report the exact device-recorded step value confirmed in the current sync
  or retained for retry, without logging the value or implying it is a live
  standings snapshot.
- [x] Generate and register a product App Attest key, persist the exact
  registration body through a bounded lost-response replay window, and rotate
  only that account's still-unregistered key on the next explicit sync after
  the window expires. Persist the exact metric assertion with its body and
  reuse both for an explicit idempotent retry. No `ATTEST_DEV_BYPASS` path was
  added.
- [x] Keep activity sync disabled in Debug and Release. Release retains its
  existing contest-mutation and fixture-route locks.
- [x] Introduce no raw sample, bucket, request-body, assertion, or authorization
  logging, and discard database conflict detail before an Edge metric failure
  can expose old or new health values. The physical app-log inspection remains
  an acceptance gate.
- [x] Keep `com.gametime.conformance` as the primary App Attest identity and add
  a strict, bounded, non-production-only `APPLE_ADDITIONAL_BUNDLE_IDS` verifier
  path for product registration and metric assertions. Receipt verification is
  bound to the exact App ID that passed attestation; check-in remains
  primary-only; production refuses the additional list.
- [ ] With separate approval, configure
  `APPLE_ADDITIONAL_BUNDLE_IDS=com.mjenkins.gametime.staging` and deploy the
  reviewed `attest-device` and `ingest-metrics` working-tree bundles. Keep
  `APP_ATTEST_ALLOW_DEVELOPMENT=true` in Staging and `ATTEST_DEV_BYPASS` absent,
  then rerun conformance and product rejection probes before physical testing.
- [ ] Record the physical two-account run in
  `docs/M8_1_STAGING_ACCEPTANCE.md`, including two real step uploads, a lost
  response, exact retry, replay acceptance, relaunch recovery, account
  isolation, and an app-log privacy check.

The 2026-07-29 one-device retry passed signed build, install, launch, Staging
banner, and empty live challenge-state observation. The tester deferred the
two-account run because a second friend/device was unavailable. That is a
scheduled handoff, not a failed gate or completion claim.

This slice has no background HealthKit delivery, HealthKit workout collection,
Core Location, Apple Push Notification service (APNs), settlement, donation,
dispute, or production-release work. Do not call HealthKit or M8.1 complete
until the physical staging record closes its open rows.

### Later M8 slices

- Incremental/background HealthKit delivery after the explicit steps flow has
  physical staging evidence.
- Core Location collection and HealthKit workout selection into the persisted
  exact-byte check-in queue.
- Product App Attest lifecycle hardening after the staging registration,
  assertion, replay, and counter observations pass on physical devices.
- Durable in-app action inbox plus APNs registration and delivery.
- Review/adjudication controls plus actionable settlement and dispute screens
  after the remaining M7 contracts exist.
- Product integration for the persistent check-in queue and remaining pending
  human actions.
- Accessibility hardening, privacy disclosures, handle-change throttling,
  avatar storage, privacy-safe group-feed policy, and invitation reminders.

## Launch blockers and cross-cutting work

| Item | Why it blocks |
| --- | --- |
| Production charity list | Production is intentionally empty; contest creation fails until EINs are verified |
| App Attest device proof | Product metric signing is implemented locally, but the hosted App ID must match `com.mjenkins.gametime.staging` and physical registration/assertion/replay must pass without a bypass |
| Hosted staging proofs | Retention has committed manual/cron proof; activation still needs a committed-row cron run, and retention still needs hold/failure-recovery evidence |
| Notifications | Action-required flows need a durable inbox and eventual delivery; deadlines cannot depend on push |
| Adjudication operations | Review and dispute deadlines need authorized staffing, queues, alerts, and a tested SLA |
| Observability | Rejected ingest, scheduler failures, and stuck reviews must be measurable |
| Rate limiting | Signed-in callers can currently create avoidable endpoint load |
| Privacy and abuse handling | Health, workout, and location data require disclosure, retention rules, and reporting paths |
| Release engineering | PR #11 has a green macOS product/conformance result; preserve the latest-head/main result and document deploy/rollback/restore |

## Verification policy

Every milestone remains gated by:

- pgTAP for schema, privileges, RLS, transitions, and concurrency invariants;
- Deno format, lint, type-check, and handler/engine tests;
- Swift build and Swift Testing for portable client logic;
- real-device/staging smoke tests for claims that fixtures cannot establish.

When Docker and the Supabase CLI are unavailable locally, the CI database job
remains the merge authority for SQL changes; parser success or a declared pgTAP
plan is not a substitute for an executed suite.
