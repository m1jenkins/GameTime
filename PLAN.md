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
| M6.5 | Next | Real-device App Attest conformance against staging |
| M7 | Not started | Scheduling, standings, finalization, settlement, disputes, pledge lifecycle |
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

This is the next engineering work because App Attest is the trust root for both
metric and check-in ingest, while the current cryptographic suites prove only
that the verifier agrees with the repository's Apple-shaped test signer.

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

## M7 — settlement and finalization

M7 starts with decisions, then proves scheduling, then adds money-adjacent state.

### 1. Resolve the product decisions first

- How a pledge becomes confirmed as honored: self-attestation, receipt evidence,
  winner acknowledgement, charity integration, or a deliberate combination.
- How a contest that ran but produced `void` or
  `tie_break_inconclusive` is represented terminally.
- How the six-hour ingest grace period interacts with unresolved quarantine
  review, including what happens when a reviewer never responds.
- Who may read live/final standings and how much integrity detail each role sees.
- Who may file a dispute, within what window, which states it moves through, who
  adjudicates it, and how an open or resolved dispute affects obligations and
  reliability.
- Which notification events M7 emits for invitations, review, timezone consent,
  and pledge confirmation; M8 owns APNs delivery.

### 2. Make activation real

- Enable and configure the scheduler.
- Call `app.activate_due_contests()` on a tested cadence.
- Assert the installed schedule and idempotency in pgTAP.
- Exercise metric ingest, timezone epochs, and check-ins against a contest the
  scheduler activated rather than a test-forced row.

### 3. Add the standings/finalization orchestrator

- Load `contest_evidence`, source reputation, timezone applied events,
  quarantine state, `contest_checkin_integrity`, and trusted location
  observations into the one TypeScript scoring/integrity pipeline.
- Expose an authorized standings read surface.
- Do not finalize before `app.ingest_grace_period()` closes.
- Fail closed on unresolved review according to the decision above.
- Serialize finalization with both metric and geofence ingest so an in-flight
  request cannot commit evidence after the result is fixed.
- Persist the scoring and integrity configuration versions used for the result.

### 4. Add settlement, disputes, and reliability

- Append-only winner/loser/amount/charity obligations.
- Pledge-confirmation evidence plus the decided dispute filing window,
  transitions, adjudication authority, and obligation effects.
- Reliability score derived from the chosen confirmation semantics.
- Account deletion/anonymization that preserves obligations and contest history.
- Explicit void/inconclusive outcomes with no fabricated winner.

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
| Notifications | Four flows require another person to act; silence otherwise stalls them |
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
