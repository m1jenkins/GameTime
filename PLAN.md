# Implementation plan

Audited and reconciled 2026-07-29 against the code, tests, documentation, local
history, and `origin/main` at revision `b593679`. The staging-only explicit
steps-sync slice is committed on `main`; its local automated verification is
green and its physical two-account acceptance gate remains open.
README.md is the compact ledger of what is built; DECISIONS.md records why.
This file owns sequence, remaining work, and launch blockers. The dated evidence
and verification caveats are in `docs/IMPLEMENTATION_STATUS.md`.

## Current state

| Milestone | State | Delivered scope |
| --- | --- | --- |
| M0–M4 | Complete | Scaffold, social graph, contests, attested metric ledger, deterministic scoring |
| M5 | Complete | Integrity scoring, quarantine review, source reputation, consented timezone epochs |
| M6 | Complete | Attested geofence/workout validation, durable check-in queue primitives, trusted-location integrity inputs |
| M6.5 | In progress — conformance gate | Harness, independent receipt verification, staging backend, and one paid-team product sign/install/launch are verified; the focused conformance target still needs App Attest registration, one signed metric and check-in, exact replay/counter checks, and receipt/public-key audit on a physical iPhone |
| M7 | M7.2a, D81, and the M8.3c first-result foundation implemented | Product contract D74–D82, transactional outbox, activation job, account deletion/retention, immutable standings snapshots, explicit first results, and per-debtor obligations are integrated; the trusted evidence-loading/adjudication orchestrator, disputes, settlement, and external gates remain |
| M8 | M8.1 code path and later repository slices are present; acceptance remains open | Separate product app, Apple auth, exact-handle friendship, immutable challenge review, staging diagnostics, and committed explicit Apple-device steps sync with HealthKit source merging, product App Attest, visible confirmed totals, and an account-isolated exact-byte retry queue; two-user/device proof, hosted product App Attest identity, background delivery, and later product slices remain |

M6's boundary is backend plus portable client core. It does not include live
Core Location collection, HealthKit queries, or a production scoring/finalizer
orchestrator; the first two belong to M8 and the orchestrator belongs to M7.

## Current repository gate

`main` at `b593679` contains the reconciled backend, D81 retention work,
M8.1/M8.2a/M8.3a/M8.3c/M8.3d product slices, and explicit steps sync. Historical
test counts and revision-specific caveats live in
`docs/IMPLEMENTATION_STATUS.md`, not in this forward plan.

Remaining repository gates:

1. Obtain and record one complete green GitHub Actions run for `b593679` or its
   direct current-`main` successor. PR #11's initial head is useful historical
   evidence, but it is not proof of the current revision.
2. Re-check from a fresh LF checkout that the repository-wide line-ending rule
   removes Windows format/script drift without creating unintended source
   changes.
3. Run the hosted Security and Performance Advisors and the remaining
   production-shaped migration/operations proofs.

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

M6.5 owns the focused conformance-only target. The M8 product app remains a
separate target under D83.

Implemented in the repository:

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
or App Attest proof. The focused M6.5 gate still needs paid-team provisioning
for `com.gametime.conformance`, a staging Auth fixture, and the complete
registration/metric/check-in/replay runbook on a physical iPhone. Separately,
M8 needs a second provisioned device and the approved hosted product-verifier
rollout.

Do not mark M6.5 complete until the runbook records one successful device
registration, metric, check-in, exact retry, and counter/public-key/receipt audit
with `ATTEST_DEV_BYPASS` absent. That run must show the receipt's server-owned
verification timestamp; no receipt may influence fraud, eligibility, or
settlement while that timestamp is absent.

## M7 — settlement and finalization

M7 starts with decisions, then proves scheduling, then adds money-adjacent state.
M7.1 is complete as a documentation/product-contract slice. M7.2's outbox,
activation infrastructure, and D81's pre-result account-deletion foundation may
proceed while M6.5 awaits focused physical App Attest conformance because they
create no settlement-bearing result. M6.5 remains a hard gate before
finalization or settlement is enabled.

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
  worker. The pgTAP suite asserts that deletion cannot erase a roster, ingest
  batch, check-in, or quarantine, prune an active device registration, or let a
  stale JWT authorize the tombstone. The implemented first-result and
  obligation migration attaches its workflow scope and retained facts to these
  seams; future dispute and donation-receipt migrations must do the same.
- [x] Integrate the D81 work on top of `origin/main`.
- [x] Run the current 21-file/869-assertion database suite and the supported
  local lint/performance inspection commands.
- [x] Run Deno, Swift, and all four CI jobs on a revision containing D81 and its
  forward repair (PR #11 initial head).
- [ ] Record a current-main CI result and clear the hosted Security and
  Performance Advisors.
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

- Make the existing append-only winner/loser/amount/charity obligations
  actionable only after the review/dispute boundary; preserve D75's explicit
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

Implemented on `main` (the initial repository slice originated in PR #11):

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
- [x] Provision the paid-team Staging App ID and complete one signed
  build/install/launch with Sign in with Apple, HealthKit, and development
  App Attest entitlement inputs.
- [ ] Complete `docs/M8_1_STAGING_ACCEPTANCE.md` with a second provisioned
  physical device, two Apple-authenticated users, force-quit/relaunch after
  every mutation, deliberately lost challenge and metric responses, one shared
  challenge, accepted step uploads, and App Attest replay evidence.

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

Main revision `b593679` implements this slice. Its consolidated local repository
verification gate passed; exact commands, dates, counts, and caveats are
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
  reviewed `attest-device` and `ingest-metrics` repository bundles. Keep
  `APP_ATTEST_ALLOW_DEVELOPMENT=true` in Staging and `ATTEST_DEV_BYPASS` absent,
  then rerun conformance and product rejection probes before physical testing.
- [ ] Record the physical two-account run in
  `docs/M8_1_STAGING_ACCEPTANCE.md`, including two real step uploads, a lost
  response, exact retry, replay acceptance, relaunch recovery, account
  isolation, and an app-log privacy check.

The 2026-07-29 one-device retry passed signed build, install, launch, Staging
banner, and empty live challenge-state observation. The tester deferred the
two-account run because a second friend/device was unavailable. That is a
recorded external blocker, not a failed gate or completion claim.

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
| App Attest device proof | Product metric signing is implemented in the repository, but the hosted verifier must allow `com.mjenkins.gametime.staging` as the bounded Staging-only additional ID while retaining `com.gametime.conformance` as primary; physical registration/assertion/replay must pass without a bypass |
| Hosted staging proofs | Retention has committed manual/cron proof; activation still needs a committed-row cron run, and retention still needs hold/failure-recovery evidence |
| Notifications | Action-required flows need a durable inbox and eventual delivery; deadlines cannot depend on push |
| Adjudication operations | Review and dispute deadlines need authorized staffing, queues, alerts, and a tested SLA |
| Observability | Rejected ingest, scheduler failures, and stuck reviews must be measurable |
| Rate limiting | Signed-in callers can currently create avoidable endpoint load |
| Privacy and abuse handling | Health, workout, and location data require disclosure, retention rules, and reporting paths |
| Release engineering | PR #11 provides historical green macOS product/conformance evidence; obtain a current-main result and document deploy/rollback/restore |

## Verification policy

Every milestone remains gated by:

- pgTAP for schema, privileges, RLS, transitions, and concurrency invariants;
- Deno format, lint, type-check, and handler/engine tests;
- Swift build and Swift Testing for portable client logic;
- real-device/staging smoke tests for claims that fixtures cannot establish.

When Docker and the Supabase CLI are unavailable locally, the CI database job
remains the merge authority for SQL changes; parser success or a declared pgTAP
plan is not a substitute for an executed suite.
