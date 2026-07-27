# Implementation plan

Audited and reconciled 2026-07-26 against the code, tests, documentation, local
history, and `origin/main`. README.md is the compact ledger of what is built;
DECISIONS.md records why. This file owns sequence, remaining work, and launch
blockers. The dated evidence and verification caveats are in
`docs/IMPLEMENTATION_STATUS.md`.

## Current state

| Milestone | State | Delivered scope |
| --- | --- | --- |
| M0–M4 | Complete | Scaffold, social graph, contests, attested metric ledger, deterministic scoring |
| M5 | Complete | Integrity scoring, quarantine review, source reputation, consented timezone epochs |
| M6 | Complete | Attested geofence/workout validation, durable check-in queue primitives, trusted-location integrity inputs |
| M6.5 | In progress — conformance gate | Harness, independent receipt verification, and staging backend are verified; App Attest-capable signing and physical-iPhone proof remain |
| M7 | M7.2a and D81 foundation implemented | Product contract D74–D82, transactional outbox, activation job, and account deletion/retention foundation are integrated; local database and staging retention proofs pass, while broader concurrency and production-shaped migration proof remains |
| M8 | M8.1 plus restart-safe duel retry implemented; staging proof open | Separate product app, Apple-auth/onboarding state machine, exact-handle social loop, atomic duel creation/invitation, protected per-user pending retries, four-tab SwiftUI system, fixtures, and Xcode tests; two-user Apple staging proof and later device/framework slices remain |

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
recorded separately below. The connected iPhone is visible to Xcode, but the
current Apple account exposes only a Personal Team. Xcode refuses to provision
the target because Personal Teams do not support the App Attest capability. Add
an Apple Developer Program team with an App Attest-enabled App ID, update
`APPLE_TEAM_ID` and the target signing team, then create the staging Auth
user/fixture needed by the smoke run.

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
- Load `contest_evidence`, source reputation, timezone applied events,
  quarantine state, `contest_checkin_integrity`, and trusted location
  observations into the one TypeScript scoring/integrity pipeline.
- Update the scoring `Outcome` contract and fixtures so `all_donate` returns the
  complete accepted roster. Reject `insufficient_participants` from an active
  contest as an operational invariant failure.
- [x] Narrow metric/quarantine direct rival access and expose D77's
  exact-contest, phase-aware bounded quarantine-review surfaces.
- Expose D77's remaining phase- and role-authorized live/final standings and
  bounded final rationale after frozen assessments/results exist.
- Serialize finalization with both metric and geofence ingest so an in-flight
  request cannot commit evidence after the result is fixed.
- Before interpreting zero quarantines as clean, persist a complete versioned
  integrity assessment over the frozen evidence and materialize every required
  quarantine. Do not finalize before `app.ingest_grace_period()` closes.
- Implement D76's per-quarantine review deadline, early-rejection escalation,
  grace-anchored adjudication deadline, explicit clearance, and terminal
  `review_timeout`.
- Add explicit adjudicator authorization, guarded operator queues/tools,
  conflict checks, observability, and an on-call/SLA runbook for the D76/D78
  deadlines. A schema deadline without an operated queue is not complete.
- Persist explicit `winner`, `all_donate`, `void`, and `inconclusive` results;
  only the first two may create obligations.
- Persist the scoring and integrity configuration versions used for the result.

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
- [x] One-to-one duel editor and immutable review using the four backend
  metrics, daily/cumulative cadence, future dates, target, staging stake,
  charity, and tie-break.
- [x] Atomic, caller-idempotent contest plus invitation creation with
  same-payload retry and changed-payload rejection.
- [x] Launch, foreground, pull-to-refresh, and post-mutation reloads; no
  Realtime and no automatic mutation retry.
- [x] Debug fixture/live-client parity, loading/empty/offline/future-state
  coverage, and Release-compilation gates that remove fixture routing and keep
  contest mutation disabled.
- [x] A `macos-26` CI job selecting Xcode 26.2 and testing both product and
  conformance schemes without signing.
- [ ] Provision the product App ID through an eligible Apple team and complete
  `docs/M8_1_STAGING_ACCEPTANCE.md` with two Apple-authenticated users,
  force-quit/relaunch after every mutation, a deliberately lost-response retry,
  and one shared pending contest.

M8.1 is implemented with staging proof open, not complete. It is an internal
alpha, not an App Store or production release.

### M8.2a — Restart-safe pending duel action

- [x] Persist one immutable pending duel per authenticated actor before its first
  network attempt, including the exact request UUID and canonical millisecond
  timestamps stored losslessly for the backend payload hash.
- [x] Store the versioned record atomically under Application Support with
  complete file protection, backup exclusion, account isolation, and
  conflict-checked monotonic attempt updates.
- [x] Retain ambiguous, offline, and cancelled attempts across relaunch; restore
  them only for the matching actor and require a deliberate retry.
- [x] Block a second duel while recovery is pending or unreadable. Clear the
  record only after a confirmed contest UUID or an explicit warned discard;
  never retry automatically.
- [x] Cover file corruption, envelope versions, cross-account copies, exact
  round trips, changed-record rejection, auth-transition races, sign-out
  detachment, Release locking, lost-response relaunch, and recovery UI with
  product unit/UI fixtures.

This closes one pending-human-action durability gap. It does not complete
persistent metric/check-in evidence queues, the two-user staging proof, or full
M8.

### Later M8 slices

- HealthKit authorization, incremental queries, provenance extraction, and
  background sync into the existing metric queue.
- Core Location collection and HealthKit workout selection into the persisted
  exact-byte check-in queue.
- DeviceCheck/App Attest key lifecycle and signed retries in the product target.
- Durable in-app action inbox plus APNs registration and delivery.
- Live standings/review/finalization, settlement, and dispute screens after M7
  supplies those contracts.
- Persistent metric/check-in evidence queues and remaining pending human
  actions.
- Accessibility hardening, privacy disclosures, handle-change throttling,
  avatar storage, privacy-safe group-feed policy, and invitation reminders.

## Launch blockers and cross-cutting work

| Item | Why it blocks |
| --- | --- |
| Production charity list | Production is intentionally empty; contest creation fails until EINs are verified |
| App Attest device proof | The roots and staging backend exist, but attested endpoints must not launch until the eligible-team physical-device run passes without the bypass |
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
