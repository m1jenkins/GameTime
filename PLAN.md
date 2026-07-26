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
| M7 | M7.2a and D81 foundation implemented | Product contract D74–D82, transactional outbox, activation job, and account deletion/retention foundation are integrated; full database/CI/concurrency/staging verification remains |
| M8 | Not started | Product iOS app target and product device/framework integrations |

M6's boundary is backend plus portable client core. It does not include live
Core Location collection, HealthKit queries, or a production scoring/finalizer
orchestrator; the first two belong to M8 and the orchestrator belongs to M7.

## Audit snapshot and immediate repository gate

Local audit/D81 commit `c6bfed67` and upstream M6.5 hardening commit `cc8f440`
are now reconciled on `main`. The combined branch contains D81's
account-deletion/retention migrations and tests together with the hosted PKI.js
runtime fix and reviewed staging configuration. Reconciliation removes the
repository split; it does not substitute for the full database, Swift, CI,
concurrency, or staging proof still listed below.

The 2026-07-26 local audit established:

- Deno lint and type-check pass; all 287 Deno tests pass.
- All 15 migration files parse with a PostgreSQL 17 parser, and all five Bash
  scripts pass `bash -n`.
- The repository contains 18 pgTAP files planning 733 assertions, but Docker,
  Supabase CLI, and `psql` were unavailable here, so those assertions were not
  executed in this audit.
- Swift and Xcode were unavailable here. The repository contains 88 portable
  GameTimeCore test cases and ten conformance-target XCTest cases; only the
  portable package is a current CI job.
- `deno fmt --check` is blocked on this Windows checkout by CRLF conversion in
  otherwise unchanged tracked files. Verify from an LF checkout rather than
  formatting 25 files as audit noise.

Before new feature work:

1. Review the reconciled diff and verify LF behavior from a fresh checkout.
2. Run `supabase db reset`, all 733 pgTAP assertions, database lint/advisors,
   Deno checks, Swift tests, and CI on the integrated revision.
3. Add a macOS simulator job for the conformance target; the Supabase CLI and
   Deno CI versions are now pinned to the audited toolchain.

## Corrections retained from the prior audit

- Reconciled the two feature commits that completed M5 and implemented M6.
- Made timezone and quarantine review quorum immutable. Account deletion cannot
  erase a vote, shrink consent into approval, or reopen a terminal rejection.
- Enforced timezone epochs strictly inside the contest window and removed a
  millisecond-precision race from the pgTAP assertion.
- Made `service_role` privileges deterministic and denied direct mutation of
  derived consent/check-in ledgers; writes stay behind their guarded RPCs.
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

The staging project is linked; migrations through M7.2a, the required secrets,
and three Edge Functions were deployed and verified before D81 landed. The D81
migrations remain unstaged. The connected iPhone is visible to Xcode, but the
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
- [ ] Integrate the D81 work on top of `origin/main`, run the full 733-assertion
  database suite and CI, and clear database security/performance advisors.
- [ ] Add multi-session tests for deletion racing activation, invitation
  acceptance, ingest, receipt marking, hold creation, retention, and future
  finality writes. A single pgTAP transaction cannot prove lock ordering.
- [ ] Apply the 2,860-line deletion migration to a production-shaped staging
  copy, measure migration-wide lock duration, and document backup, deployment
  window, failure recovery, and rollback limits.
- [ ] Observe `gametime-prune-raw-evidence` in hosted staging and verify its run
  history, holds/cutoffs, immutable events, and failed-job recovery.
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
- Expose D77's phase- and role-authorized standings/review surfaces, and narrow
  direct rival table access that would bypass their redaction.
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

The first M8 slice should prove the complete loop, not only render a shell:

- Xcode app target and Sign in with Apple.
- Profile onboarding, exact-handle discovery, friend request, and friend
  acceptance so contest invitation has a real social-graph path.
- HealthKit authorization, incremental queries, provenance extraction, and
  background sync into the existing metric queue.
- Core Location collection and HealthKit workout selection into the persisted
  exact-byte check-in queue.
- DeviceCheck/App Attest key lifecycle and signed retries.
- Create, invite, accept, review, view standings, settle, and dispute screens.
- Local persistence for queues and pending human actions.
- APNs registration and delivery for action-required events.

After the loop works: handle-change throttling, avatar storage, a privacy-safe
group feed, invitation expiry/reminders, accessibility polish, and App Store
privacy disclosures.

## Launch blockers and cross-cutting work

| Item | Why it blocks |
| --- | --- |
| Production charity list | Production is intentionally empty; contest creation fails until EINs are verified |
| App Attest device proof | The roots and staging backend exist, but attested endpoints must not launch until the eligible-team physical-device run passes without the bypass |
| Hosted staging proofs | Activation and retention need recorded committed-row cron executions and failure-recovery evidence |
| Notifications | Action-required flows need a durable inbox and eventual delivery; deadlines cannot depend on push |
| Adjudication operations | Review and dispute deadlines need authorized staffing, queues, alerts, and a tested SLA |
| Observability | Rejected ingest, scheduler failures, and stuck reviews must be measurable |
| Rate limiting | Signed-in callers can currently create avoidable endpoint load |
| Privacy and abuse handling | Health, workout, and location data require disclosure, retention rules, and reporting paths |
| Release engineering | Continuously build the conformance target and document deploy/rollback/restore |

## Verification policy

Every milestone remains gated by:

- pgTAP for schema, privileges, RLS, transitions, and concurrency invariants;
- Deno format, lint, type-check, and handler/engine tests;
- Swift build and Swift Testing for portable client logic;
- real-device/staging smoke tests for claims that fixtures cannot establish.

When Docker and the Supabase CLI are unavailable locally, the CI database job
remains the merge authority for SQL changes; parser success or a declared pgTAP
plan is not a substitute for an executed suite.
