# Ship Personal Accountability V1 as a test-only Stage A

GameTime V1 is a solo accountability product. One person commits to a seven-day
steps goal, chooses daily or cumulative cadence, and selects a test commitment
of $10, $20, $30, $40, or $50. Stage A never charges money.

`README.md` records what is built. `DECISIONS.md` records why. Historical social
implementation records remain under `docs/archive/`. The social schema and
contracts stay read-compatible for existing challenges, but the V1 app does not
offer social creation or expose friends, invitations, rosters, standings,
winners, charities, reactions, or tie-breaks.

## What functional means

The Stage A product must let one real user:

- Sign in with Apple, complete public-handle onboarding, and restore the same
  account after relaunch.
- Create at most one scheduled or active personal steps challenge.
- Choose daily or cumulative cadence and edit a positive whole-step target.
- Start at the next midnight in a frozen IANA timezone and run for seven
  complete local calendar days, including daylight-saving transitions.
- Select one of the five test commitment presets, with $10 selected by default.
- See **Test commitment — no money will be charged.** before confirming.
- Complete a trusted HealthKit and App Attest diagnostic.
- Manually sync attested steps and signed coverage for completed hourly buckets.
- See current progress, remaining steps, the seven-day timeline, sync health,
  completed history, and a final personal result.
- Cancel only before the challenge begins.
- Receive a 24-hour final-sync grace period after the seventh day.
- Receive `met_goal`, `missed_goal`, or `inconclusive` only after evidence
  completeness is decided.
- Recover from a user/device eligibility hold only through a later successful
  trusted diagnostic.

Simulator and fixture behavior does not prove HealthKit or App Attest. One
physical iPhone must separately prove the trusted device path.

## Locked Stage A boundaries

- Steps are the only presented metric. Other metric code remains dormant for a
  later version.
- Personal challenges use dedicated terms, result, progress, diagnostic, hold,
  API, Swift model, and pending-request types. They are never represented as a
  social challenge with an empty invitation list.
- Every pre-pivot challenge is `legacy_charity_contest`. Existing social data,
  results, standings, and obligations retain their historical meaning.
- `social_accountability` is reserved for V2 and has no V1 creation path.
- The server writes `test_only`; no personal creation request accepts a live
  settlement mode and no Stage A client can ask for one.
- An ended challenge awaiting grace, assessment, or its first result still
  occupies the user's open slot. Pre-start cancellation or the first published
  terminal personal result closes it.
- A complete daily challenge requires all seven local days to meet the target.
  A complete cumulative challenge requires the seven-day total to meet it.
- Trusted coverage, not the presence of positive step rows, decides whether a
  completed local-hour interval was observed. The expected set is generated
  from the frozen IANA timezone and challenge window; it must not assume every
  offset transition is a whole hour or that every window has a fixed count.
- Expected intervals must not overlap in scored evidence. If a platform
  calendar produces overlapping intervals for a non-hour offset transition,
  Stage A fails that result closed as `inconclusive / gametime_outage` until a
  non-overlapping collection rule is implemented and accepted on device.
- For each query, every positive metric batch must be durably accepted before
  its coverage batch is submitted. If any metric upload is pending or refused,
  coverage remains pending too; coverage must never certify a partially
  delivered query as complete.
- Missing coverage, unresolved quarantine, conflicting evidence, or unresolved
  assessment produces `inconclusive` before target comparison.
- A confirmed GameTime outage waives the test commitment without a hold. An
  unresolved user/device sync failure waives it and creates an eligibility hold.
- Release mutations remain disabled in Stage A. Local and Staging are the only
  mutable environments until a separate release authorization.

## Verified starting point

Implementation began from a clean `main` at commit `422e638`, matching the
cached `origin/main` reference. Old feature branches are reference material
only; none may be merged wholesale.

The prior privacy fix is isolated at commit `6cfae0b`. Only its self-only direct
participant access and bounded legacy challenge-summary behavior should be
reimplemented on current `main`. Its stale social UI and conflicting decision
numbering must not be imported.

## 1. Foundation — implemented locally

1. Add the challenge-model discriminator and backfill every existing challenge
   as `legacy_charity_contest`.
2. Dispatch creation invariants, activation quorum, ingest grace, and
   finalization by model while leaving legacy behavior unchanged.
3. Reimplement self-only direct participant reads and the bounded legacy summary
   RPC from the old privacy branch.
4. Prove that the backfill does not alter legacy challenges, results, standings,
   or donation obligations.
5. Keep the existing social creation RPC callable for older clients and dormant
   regression tests, but remove every normal V1 app route to it.

Exit criteria:

- Every preexisting and legacy-created row has the legacy discriminator.
- Legacy 2–20 participant, charity, six-hour grace, winner, standings, and
  obligation behavior still passes its existing tests.
- Direct participant reads return only the caller's row.
- The bounded legacy summary reveals no pending invitee identity or private
  participant term.
- No reserved `social_accountability` creation path exists.

## 2. Personal backend

Implement the complete server boundary:

- Frozen personal terms keyed by challenge and owner.
- Atomic, idempotent creation and a database-enforced one-open slot.
- Server-derived next-midnight start and seven-local-day end.
- Pre-start-only idempotent cancellation.
- Owner-only list and detail RPCs.
- A separately attested diagnostic upload that stores no raw health values.
- Append-only trusted sync coverage, including zero-valued periods.
- A 24-hour personal ingest grace without changing the legacy six-hour grace.
- Service-only versioned assessment input and append-only first-result publication.
- Durable eligibility-hold facts with one-time clearance fields set only by a
  successful trusted diagnostic whose Health query began strictly after the
  hold.
- Explicit grants and RLS on every new exposed table and function.

Exit criteria:

- Exact creation retries return the same challenge; changed terms under the same
  request UUID fail.
- Concurrent requests cannot create two open personal challenges.
- Personal activation succeeds with exactly one accepted owner.
- Personal scoring creates no standings, winner, charity, donation obligation,
  or participant payout.
- Daily, cumulative, DST, late-backfill, evidence-completeness, outage, hold,
  and cancellation tests pass.
- Two authenticated database actors cannot read each other's terms, coverage,
  activity, diagnostic, result, or hold.
- The server, rather than a client flag, proves every personal term is
  `test_only`.


+## 2A. Owner-only Solo contract domain — implemented locally

Step 2A adds a new, isolated contract aggregate without rewriting the Personal
V1 evidence path or any historical Social table. The aggregate is deliberately
dormant: its authoritative database creation switch is seeded off, no user is
beta-eligible by default, and the current iOS app does not call it.

Implemented in this reviewable slice:

- `solo_contracts` freezes the active policy version and digest, steps cadence
  and target, USD commitment, settlement mode, IANA timezone, and a 1–7-local-day
  window. A partial unique index permits one unsettled Solo contract per owner.
- Commitments accept integer USD cents from $10 through $50. Every row is
  structurally `test_only`; there is no processor, payment method,
  authorization, charge, transfer, payout, or provider identifier.
- The only lifecycle is `scheduled → active → awaiting_evaluation`, followed by
  preliminary success/inconclusive settlement readiness or one preliminary
  failure. A pre-start cancellation, one appeal, an append-only decision, and a
  terminal logical settlement are the only additional paths.
- `solo_evaluations` is an append-only service ledger.
  `solo_appeals` is an append-only event ledger with one `filed` event per
  preliminary failure and at most one `decided` event per filing.
- All client and service mutations use explicitly granted versioned RPCs and an
  exact-request ledger. Authenticated owners receive direct `SELECT` only,
  bounded by active owner RLS. `anon`, other owners, and direct client/service
  table writes are refused.
- New creation requires both the private DB-backed beta allowlist and the
  authoritative contract-creation switch, and the caller must acknowledge the
  exact active policy version. Exact committed retries recover before mutable
  rollout gates are rechecked.
- Account deletion cancels only a still-scheduled, pre-start Solo contract,
  disables that owner's beta eligibility, and retains post-start evaluation and
  appeal facts for service finality. Stale JWTs cannot read or mutate them. This
  versioned trigger bridge inherits D81's transaction marker and audit trail; it
  does not invent a second Solo request UUID for the existing deletion RPC.

Exit criteria for 2A:

- Forward migrations apply after every existing migration without modifying or
  disabling the Personal or Social implementation.
- pgTAP proves bounds, locked terms, RLS, privileges, exact retries, one-open
  concurrency, every lifecycle boundary, one-appeal races, and account-deletion
  boundaries.
- Full local database, advisor/lint, Deno, Swift package, reference, and
  whitespace checks pass.

Transitional after 2A:

- No app route or Edge Function uses the Solo RPCs yet.
- No hosted runtime switch or beta eligibility is changed.
- Scheduler wiring, a unified Personal-to-Solo client boundary, and
  hosted/two-actor acceptance remain later reviewable slices. Step 2B implements
  only the processor-neutral fake authorization adapter identified here.
- The existing Personal V1 and the dormant Solo aggregate have independent open
  slots. They must not both be enabled in a client until a later migration owns
  the cross-domain slot rule.


## 3. Personal iOS

Retain the approved Daybreak visual system and replace the normal app journey:

- Use only Today, Challenges, and You tabs, with independent navigation stacks.
- Today shows the open challenge, remaining steps, seven-day timeline, sync
  state, manual sync, and a creation call to action when no challenge is open.
- Challenges separates the current challenge from completed history. Personal
  detail shows frozen terms, cadence, progress, sync health, and result.
- Creation walks through steps, cadence, editable target, commitment preset,
  trusted diagnostic, and frozen-terms review.
- You preserves handle/profile setup and adds Health access, latest diagnostic,
  privacy, and eligibility-hold state.
- Use dedicated personal models and a separate versioned pending-request store.
  Social v1/v2 envelopes must never decode or retry as personal requests.
- Ignore dormant social standings push actions in the V1 shell.
- Make personal fixtures and previews the default; label legacy fixtures as V2
  or regression-only.

Exit criteria:

- Only three tabs and personal destinations are reachable in the normal app.
- Only steps is presented; both cadences and all five commitments work; $10 is
  the default.
- The exact no-charge disclosure is visible before confirmation and on active
  personal surfaces.
- Reachable UI contains no competitor, rank, winner, charity, invitation,
  roster, reaction, or tie-break language.
- Pending request, routing, app-model, configuration, unit, and UI tests pass.
- Debug, Staging, and Release simulator builds compile without actionable
  compiler or linker warnings, while Release continues to reject personal
  mutations. D83 explicitly accepts Xcode 26.2's expected no-AppIntents
  metadata-extraction self-skip for targets that intentionally have no
  `AppIntents.framework` dependency.

## 4. Stage A acceptance

Use `docs/PERSONAL_V1_ACCEPTANCE.md`. Keep proof layers separate:

1. Local migration, pgTAP, Deno, Swift package, product unit/UI, conformance,
   configuration, and build proof.
2. Hosted Staging migration, function, scheduler, RLS, and test-only proof only
   after explicit deployment approval.
3. One physical iPhone proof for HealthKit reads, App Attest, manual/background
   behavior actually implemented, final sync, scoring, and diagnostic recovery.
4. Two-actor privacy proof in pgTAP and a controlled account-isolation
   observation; one phone does not substitute for two authorization identities.

No push, hosted migration, Edge Function deployment, TestFlight publication,
App Store submission, or production configuration is authorized by this plan.

## Current implementation status

| Capability | Current state | Remaining proof |
| --- | --- | --- |
| Clean pivot baseline | Verified at local/cached `422e638` | Live remote refresh only if publication is later approved |
| Model discriminator and legacy backfill | Implemented; full local database suite passes | Hosted migration rehearsal after approval |
| Legacy roster privacy fix | Selectively ported; self-only RLS and bounded RPC pass locally | Hosted two-actor observation after approval |
| Personal terms and one-open slot | Implemented; lifecycle, exact-retry, and two-session concurrency tests pass | Hosted Staging observation after approval |
| Trusted diagnostic and sync coverage | Edge, database, and iOS paths implemented; local service tests and builds pass | Signed physical HealthKit/App Attest and background-delivery proof |
| Personal scoring and holds | Implemented; DST, completeness, outage, deletion, retention, and recovery tests pass locally | Hosted scheduler/operator run plus physical final sync |
| Solo contract domain (2A) | Implemented locally; policy-locked owner records, rollout gates, append-only evaluation/appeal facts, lifecycle, and deletion integration | Runtime remains off; client/worker integration and hosted acceptance remain separate slices |
| Three-tab personal Daybreak app | Personal simulator acceptance passes on a booted iPhone 17 Pro simulator: 103 unit, 10 UI, and 10 conformance tests pass; unsigned Debug/Staging/Release builds pass; D83 accepts the expected Xcode 26.2 no-AppIntents self-skip | Signed physical-device visual, HealthKit, App Attest, and background-delivery acceptance |
| Hosted Stage A | Not deployed | Separate approval plus hosted acceptance |
| Physical Stage A | Not run | One provisioned iPhone and bounded evidence record |
| Real fees | Blocked | Every Stage B gate below |

## Stage B real-fee gate

Real fees remain prohibited until all of these exist in writing and the product
is redesigned and reviewed against them:

- US counsel memo defining the fee model, 18+ rules, versioned state allowlist,
  cancellation, waiver, dispute, and refund policies.
- Processor approval explicitly covering a HealthKit-informed,
  failure-contingent, off-session fee.
- App Store/payment and HealthKit policy clearance.
- Approved age and jurisdiction verification.

Stage B must use a saved approved payment method and explicit off-session
mandate, never a seven-day authorization hold. A verified miss is provisional
after grace, receives a seven-day review window, pauses charging during review,
and waives automatically if unresolved by day 14. Injury reporting uses
structured attestations without medical records. A confirmed miss may be
charged once; failed collection requires a user-authorized retry and blocks
another paid challenge without repeated retries or debt collection.

Step 2A remains `test_only`. Dollar-denominated commitments and logical
settlement are not Stage B clearance. They do not reserve funds, authorize a
charge, or move money.

## Deferred V2

V2 may add `social_accountability`, where people share a challenge but keep
independent goals, outcomes, and fees. It must not pool money or pay a
participant. Start with structured reactions and reminders. Free-form comments
remain blocked until Apple-compliant filtering, reporting, blocking, moderation,
and support controls exist.

## Verification rules

- Simulator tests prove navigation and fixtures, not Apple services.
- Local database tests prove migrations and policies, not hosted scheduling.
- A signed build proves signing inputs, not HealthKit reads or App Attest.
- Positive step rows do not prove evidence completeness; trusted covered hours
  do.
- A seven-day local-calendar window is not always 168 elapsed hours.
- A one-user device run does not prove two-actor privacy isolation.
- Preserve exact request UUIDs and encoded bytes for every retried mutation.
- Never expose a service-role key, Apple private key, access token, assertion,
  payload body, raw health value, or private profile data in evidence or logs.
- Require explicit approval before push, merge, deployment, hosted mutation,
  TestFlight, production configuration, or submission.

## References

- `docs/PERSONAL_V1_ACCEPTANCE.md`: personal Stage A acceptance runbook.
- `docs/M8_1_STAGING_ACCEPTANCE.md`: retained historical social-alpha runbook.
- `docs/M6_5_DEVICE_CONFORMANCE.md`: full metric and App Attest conformance reference.
- `docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md`: historical implementation evidence.
- `docs/archive/2026-07-30_IMPLEMENTATION_PLAN.md`: previous milestone plan.
