# Implementation plan

Audited 2026-07-25 against the code, tests, pull-request refs, and every remote
branch. README.md is the compact ledger of what is built; DECISIONS.md records
why. This file owns sequence, remaining work, and launch blockers.

## Current state

| Milestone | State | Delivered scope |
| --- | --- | --- |
| M0–M4 | Complete | Scaffold, social graph, contests, attested metric ledger, deterministic scoring |
| M5 | Complete | Integrity scoring, quarantine review, source reputation, consented timezone epochs |
| M6 | Complete | Attested geofence/workout validation, durable check-in queue primitives, trusted-location integrity inputs |
| M6.5 | In progress — conformance gate | Harness and staging procedure implemented; physical-iPhone/staging proof and independent receipt validation remain |
| M7 | Started — M7.1 complete | Product contract resolved in D74–D81; scheduler and implementation remain |
| M8 | Not started | iOS app target and all device/framework integrations |

M6's boundary is backend plus portable client core. It does not include live
Core Location collection, HealthKit queries, or a production scoring/finalizer
orchestrator; the first two belong to M8 and the orchestrator belongs to M7.

## What this audit corrected

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

The audit also found stale repository administration: PRs #5 and #6 point to
commits already in `main`, and #7 is an obsolete alternate M2 implementation.
They should be closed and their dead branches deleted after confirming no
external automation still references them. The old M5 branch must not be
merged again; its tree is already represented in `main`.

## M6.5 — device-conformance spike

This is the current engineering work because App Attest is the trust root for
both metric and check-in ingest. The repository now checks its verifier against
Apple's public 2026 attestation vector as well as its synthetic signer, but only
a physical-device run can prove the complete staging exchange.

Definition of done:

1. Provision a staging Supabase project and configure Apple's real App Attest
   root certificate.
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
- Private quarantine of Apple's opaque attestation receipt, explicitly
  untrusted until its independent PKCS#7 validation is implemented.
- Hosted JWT verification from Supabase's injected JWKS, a separate challenge
  HMAC secret, and support for opaque hosted admin keys.
- Fingerprint-pinned, checked-in-project-identity-guarded staging scripts, a
  deterministic SQL fixture, database verification queries, and a real-device
  smoke runbook.

Current execution gate: this workstation has no connected physical iPhone and
no staging project credentials. Do not mark M6.5 complete until the runbook
records one successful device registration, metric, check-in, exact retry, and
counter/public-key/receipt audit with `ATTEST_DEV_BYPASS` absent. Receipt bytes
must remain quarantined and unused until their Apple-required independent
PKCS#7 validation path is implemented and exercised.

## M7 — settlement and finalization

M7 starts with decisions, then proves scheduling, then adds money-adjacent state.
M7.1 is complete as a documentation/product-contract slice. M7.2's outbox and
activation infrastructure may proceed while M6.5 awaits staging credentials and
physical-device proof because it creates no settlement-bearing result. M6.5
remains a hard gate before finalization or settlement is enabled.

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

### 2. M7.2 — Make activation real

- Build D80's transactional outbox first and retrofit invitations, timezone
  consent, quarantine review, and activation/cancellation so each transition
  commits with its durable intent.
- Enable and configure the scheduler.
- Call `app.activate_due_contests()` on a tested cadence.
- Establish one idempotent scheduled-worker pattern and registry. Activation is
  its first job; later M7 slices add finalization/review escalation, claim
  expiration/confirmation/default, dispute timeout, reminder, and retention
  jobs without inventing separate timer semantics.
- Assert the installed schedule, transition/outbox idempotency, and cancellation
  semantics in pgTAP.
- Exercise metric ingest, timezone epochs, and check-ins against a contest the
  scheduler activated rather than a test-forced row.

### 3. Add the standings/finalization orchestrator

- Implement D81's durable actor before the first result: replace the auth/profile
  and device-key evidence cascades with pseudonymization and retained audit
  digests; cover authored and accepted pending contests, active-contest
  and challenge-horizon capabilities, profile-field clearing, one atomic
  deletion RPC, case-capability authorization, persisted operator cutoffs,
  versioned raw-data retention, and the guarded retention worker; prove deletion
  cannot erase a roster, ingest batch, check-in, quarantine, or result, prune an
  active device registration, or let a stale JWT authorize the tombstone.
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
| App Attest root + real-device proof | Attested endpoints must not launch on the development bypass |
| Staging environment | Device conformance and scheduled activation need a real target |
| Notifications | Action-required flows need a durable inbox and eventual delivery; deadlines cannot depend on push |
| Adjudication operations | Review and dispute deadlines need authorized staffing, queues, alerts, and a tested SLA |
| Observability | Rejected ingest, scheduler failures, and stuck reviews must be measurable |
| Rate limiting | Signed-in callers can currently create avoidable endpoint load |
| Privacy and abuse handling | Health, workout, and location data require disclosure, retention rules, and reporting paths |

## Verification policy

Every milestone remains gated by:

- pgTAP for schema, privileges, RLS, transitions, and concurrency invariants;
- Deno format, lint, type-check, and handler/engine tests;
- Swift build and Swift Testing for portable client logic;
- real-device/staging smoke tests for claims that fixtures cannot establish.

The full database suite remains the merge authority for SQL changes when Docker
and the Supabase CLI are unavailable locally.
