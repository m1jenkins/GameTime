# Ship automatic Apple Health Personal challenges and the sandbox beta

GameTime V1 is a solo accountability product. One person commits to a seven-day
steps goal, chooses daily or cumulative cadence, and selects a test commitment
of $10, $20, $30, $40, or $50.

Internal Stage A remains structurally `test_only` and never charges money. The
lean external Release beta is a separate Stage B rehearsal that may use Stripe
test mode for payment setup and simulated settlement. It must never accept live
Stripe objects or move real money. `docs/BETA_LAUNCH_AUDIT.md` controls that
external-beta scope and its launch gates; this plan continues to preserve the
Stage A evidence contract.

`README.md` records what is built. `DECISIONS.md` records why. Historical social
implementation records remain under `docs/archive/`. The social schema and
contracts stay read-compatible for existing challenges, but the V1 app does not
offer social creation or expose friends, invitations, rosters, standings,
winners, charities, reactions, or tie-breaks.

**August 12, 2026 policy replacement.** New Personal challenges no longer use
the hourly evidence, App Attest, coverage, diagnostic, eligibility-hold, or
manual-sync contract described by the historical M9 record. That contract is
frozen as `attested_hourly_v1`. The active path is
`healthkit_nonmanual_daily_v1`: one automatic Apple Health snapshot containing
seven ordered daily totals, uploaded through an authenticated owner-bound RPC
and frozen into history at cutoff. Sections that explicitly describe Solo,
Social, generic metric ingest, or historical Personal V1 remain regression
context; they are not permission to route a new Personal challenge through the
old path.

## What functional means

The Stage A product must let one real user:

- Sign in with Apple, complete public-handle onboarding, and restore the same
  account after relaunch.
- Create at most one scheduled or active personal steps challenge.
- Choose daily or cumulative cadence and edit a positive whole-step target.
- Start at the next midnight in a frozen IANA timezone and run for seven
  complete local calendar days, including daylight-saving transitions.
- Select one of the five test commitment presets, with $10 selected by default.
- In internal Stage A, see **Test commitment — no money will be charged.**
  before confirming. In the external sandbox beta, see **Payment test mode —
  sandbox transactions only.** plus a plain statement that no real money moves.
- Complete one user-initiated **Connect Apple Health** permission request before
  creating. Completion, not a positive step sample, unlocks continuation.
- See Apple Health progress automatically after challenge load/creation, app
  launch or foregrounding, Health observer changes, and ordinary pull to
  refresh, without a step-specific sync button.
- See the same displayed total, daily timeline, pace, and update time on Today,
  Challenges, detail, and completed history.
- Cancel only before the challenge begins.
- Receive a 24-hour finalization period after the seventh day while GameTime
  keeps re-reading Apple Health through the challenge end for late Watch data.
- Receive `met_goal`, `missed_goal`, or a commitment-waived `inconclusive` only
  after the server freezes the selected snapshot.

Simulator and fixture behavior does not prove Apple Health, background wakes,
locked-device retry, or late Watch delivery. Physical-iPhone acceptance remains
separate. Personal App Attest is not part of that proof.

## Locked automatic snapshot boundaries

- Steps are the only presented metric. Other metric code remains dormant for a
  later version.
- Personal challenges use dedicated terms, daily snapshot, displayed progress,
  cache, result, API, Swift model, and pending-request types. They are never
  represented as a social challenge with an empty invitation list.
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
- Query each of the seven exact frozen local dates with cumulative HealthKit
  statistics. Read through now during the challenge and through `ends_at`
  during grace. Twenty-three- and twenty-five-hour dates remain one local day.
- Include Health's merged writers and exclude only samples where
  `HKMetadataKeyWasUserEntered == true`. Missing manual-entry metadata remains
  indistinguishable from automatic data and is included.
- A snapshot carries challenge ID, frozen-terms fingerprint, observation time,
  query-through time, and exactly seven ordered nonnegative daily totals. The
  overall total is derived, never independently supplied.
- Publish a successful Health read locally before uploading. A successful zero
  or downward edit replaces the prior whole snapshot; query failure preserves
  the prior value and marks it stale. Never splice days from separate reads.
- The server keeps one private mutable full-window snapshot for an open
  challenge. Older observations are ignored, identical replays succeed, equal
  timestamps with different payloads fail, and a newer snapshot replaces the
  whole prior snapshot even when totals decrease.
- Missing or incomplete final data becomes commitment-waived `inconclusive`.
  A complete miss alone may enter Stripe sandbox review. Met and inconclusive
  results never do.
- Release mutations remain disabled for the internal Stage A and every legacy
  social path. The invite-only external beta may enable only Personal creation
  through `stripe_sandbox` and the separately approved hosted beta target. Live
  settlement remains forbidden.

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
- Frozen `step_data_policy`: `attested_hourly_v1` for history and
  `healthkit_nonmanual_daily_v1` for the automatic path.
- One private mutable full-window snapshot per open v2 challenge and exactly one
  authenticated `upsert_my_personal_health_snapshot_v2` write boundary. The
  function derives the owner from authentication; clients receive no direct
  table write grant.
- Validation of ownership, lifecycle, frozen local dates, cutoff, observation
  and query-through timestamps, payload bounds, ordering, and future-day zeros.
- Clean owner-only v2 list/detail responses with ordinary steps, seven daily
  totals, Health observation/update times, policy, and terminal result, with no
  coverage, trusted, diagnostic, or assessment fields.
- A 24-hour personal finalization grace without changing the legacy six-hour
  social grace.
- One immutable cutoff result that copies the selected daily totals directly,
  deletes the mutable snapshot, and does not require the legacy evidence
  assessment relationship.
- Explicit grants and RLS on every new exposed table and function.

Exit criteria:

- Exact creation retries return the same challenge; changed terms under the same
  request UUID fail.
- Concurrent requests cannot create two open personal challenges.
- Personal activation succeeds with exactly one accepted owner.
- Personal scoring creates no standings, winner, charity, donation obligation,
  or participant payout.
- Daily, cumulative, 23/25-hour DST, late-Watch, zero/downward replacement,
  malformed snapshot, cutoff-race, missing-final-data, immutable rerun, and
  cancellation tests pass.
- Two authenticated database actors cannot read or write each other's terms,
  snapshots, progress, or results; `anon` cannot execute the snapshot RPC.
- The server, rather than a client flag, proves every personal term is
  `test_only`.

## 2A. Owner-only Solo contract domain — implemented locally

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

## 2B. Local fake authorization adapter — implemented locally

Step 2B is a forward-only extension of the disabled Solo aggregate. It provides
one deterministic processor-neutral fake boundary for reviewing authorization
linkage, retries, cancellation, logical settlement, and account deletion. It
does not add a provider or claim that money can move.

Implemented in this reviewable slice:

- Private `app.solo_authorizations` rows bind one contract immutably through a
  composite foreign key to its owner, policy version and digest, commitment
  amount, `USD` currency, and `test_only` settlement mode. The fixed adapter is
  `processor_neutral_fake` version `local-fake-v1`; typed facts and request
  terms receive SHA-256 digests without storing an instrument or raw payload.
- Private `app.solo_authorization_events` rows repeat that complete binding and
  form a two-event append-only lifecycle: `authorized`, then exactly one of
  `cancelled`, `released`, `forfeited`, or `waived`. Updates, deletes, truncates,
  out-of-order events, mismatches, and duplicate resolutions are refused.
- `create_solo_contract_with_fake_authorization_v2` is a new authenticated
  owner RPC. It retains all Step 2A policy, profile, beta, switch, one-open-slot,
  and request validation, then atomically commits the contract, one fake
  authorization, its initial event, and the exact-request result. A missing
  linked fact rolls the entire transaction back.
- `create_solo_contract_v1` remains contract-only with unchanged behavior.
  A request UUID already committed through v1 cannot be upgraded into a v2
  authorization, and a v2 UUID cannot be reused with changed terms.
- The pure private fake adapter has deterministic `authorize`, `refuse`,
  `retryable`, and `injected_failure` scenarios. The public v2 RPC uses only
  `authorize`. Test-only refusal and retryable outcomes commit an exact result
  without creating a contract or authorization; injected failure proves the
  candidate contract and request record roll back together.
- Pre-start cancellation appends `cancelled` in the same transaction. Terminal
  Solo settlement appends the matching logical `released`, `forfeited`, or
  `waived` outcome in the same transaction. Preliminary evaluation and appeal
  activity leave the fake authorization unresolved until contract finality.
- D109 account deletion still cancels only a strictly pre-start scheduled
  contract. That same deletion transaction appends the fake `cancelled` event,
  disables beta eligibility, and leaves post-start contract, authorization,
  evaluation, and appeal facts available only for service finality. Stale owner
  tokens retain no access.
- RLS is enabled on both private tables and every direct privilege is revoked
  from `public`, `anon`, `authenticated`, and `service_role`. Versioned
  functions and guarded triggers are the only write path. The adapter accepts
  no credential, provider secret or identifier, payment instrument, customer,
  mandate, card data, arbitrary body, or other raw sensitive payload; it logs
  nothing and performs no external call.

Exit criteria for 2B:

- Forward migrations preserve all Personal, Social, and Step 2A migration
  history while proving v1 contract-only compatibility and atomic v2 linkage.
- pgTAP proves immutable bindings, RLS and complete privilege matrices, denied
  direct writes, exact retries, changed-payload refusal, all permitted and
  forbidden transitions, contract/owner/policy/amount/currency/settlement-mode
  mismatch rejection, simultaneous linkage, duplicate resolution, appeal,
  cancellation, settlement, and deletion races.
- Deterministic fake success, refusal, retryable/retry, and injected-failure
  paths are covered, including proof that no provider secret, payment
  instrument, or raw sensitive payload is stored or logged.
- Full local database, advisor/lint, Deno, Swift package, portable, reference,
  and whitespace checks pass.

Transitional after 2B:

- The Solo creation switch remains off and the beta allowlist remains empty.
- No iOS route, public Edge endpoint, scheduler, Personal-to-Solo integration,
  or cross-domain slot rule is added.
- No hosted configuration, provider SDK, credential, payment method, mandate,
  webhook, capture, charge, transfer, payout, or external provider call exists.
- Local fake-adapter tests do not prove a real processor, money movement, legal
  or App Review approval, hosted scheduling, physical-device behavior, or
  hosted multi-user isolation.

## 3. Personal iOS

Retain the approved Daybreak visual system and replace the normal app journey:

- Use only Today, Challenges, and You tabs, with independent navigation stacks.
- Today shows the open challenge, remaining steps, seven-day timeline, automatic
  Apple Health update time, and a creation call to action when no challenge is
  open.
- Challenges separates the current challenge from completed history. Personal
  detail shows frozen terms, cadence, progress, update time, and result.
- Creation walks through steps, cadence, editable target, commitment preset,
  one Apple Health permission action, and frozen-terms review. A positive Health
  sample is never a creation prerequisite.
- You preserves handle/profile setup and adds Health access recovery and
  privacy. Personal v2 exposes no diagnostic or eligibility-hold state.
- Use separate Health reader, authenticated snapshot uploader, and protected
  whole-snapshot cache interfaces. Do not reuse the hourly evidence coordinator
  or `PersonalProgress` as the v2 source of truth.
- Coalesce overlapping automatic refreshes into one active read and one trailing
  read. Cancel or discard work after account/challenge changes. Display local
  Health before attempting an upload.
- Resolve displayed progress before cutoff as live Health, matching cache,
  server snapshot, then legacy result fallback. After cutoff prefer the frozen
  server result. Generic pull to refresh remains; no step-specific control does.
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
- Reachable Personal v2 UI contains no **Sync my steps**, **Send saved steps**,
  **Not synced**, **not confirmed**, **Steps received**, Step Syncing card,
  coverage status, diagnostic, eligibility-hold, or App Attest language.
- Pending request, routing, app-model, configuration, unit, and UI tests pass.
- Debug, Staging, and Release simulator builds compile without actionable
  compiler or linker warnings, while Release continues to reject personal
  mutations. D83 explicitly accepts Xcode 26.2's expected no-AppIntents
  metadata-extraction self-skip for targets that intentionally have no
  `AppIntents.framework` dependency.

## 4. Automatic snapshot acceptance

Use `docs/PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md`. Keep proof layers separate:

1. Local migration, pgTAP, Deno, product unit/UI, configuration, and build
   proof. Legacy App Attest conformance remains a separate regression suite.
2. Hosted Staging migration, function, scheduler, RLS, and test-only proof only
   after explicit deployment approval.
3. Physical-iPhone proof for first permission, iPhone-only steps, Watch catch-up,
   opportunistic background wake, locked-device retry, offline/reconnect,
   foreground refresh, challenge end, and the full 24-hour grace period.
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
| Automatic Health snapshot client | Implemented; native unit and fixture UI proof pass | Physical automatic-trigger, locked-device, Watch, and cutoff acceptance |
| Authenticated daily snapshot backend | Implemented; local RLS/idempotency/concurrency/finalization suite passes | Approved hosted smoke and controlled cutover |
| Historical hourly/App Attest path | Preserved as `attested_hourly_v1` | Regression/history only; not a new-Personal or TestFlight gate |
| Personal scoring and freezing | Implemented; local cutoff, immutable-rerun, and Stripe-review tests pass | Hosted cutoff worker smoke and frozen-history observation |
| Solo contract domain (2A) | Implemented locally; policy-locked owner records, rollout gates, append-only evaluation/appeal facts, lifecycle, and deletion integration | Runtime remains off; client/worker integration and hosted acceptance remain separate slices |
| Solo fake authorization adapter (2B) | Implemented locally; atomic v2 creation, immutable private binding, append-only fake outcomes, exact retries, and deletion integration | Runtime and allowlist remain closed; no provider, app/worker wiring, or hosted acceptance |
| Three-tab personal Daybreak app | Snapshot-v2 cross-surface fixture UI implemented and verified | Physical Health acceptance |
| Historical hosted Stage A | Personal V1 hourly schema/functions were deployed for `attested_hourly_v1` | Preserve and resolve history; do not treat those endpoints as snapshot-v2 acceptance |
| Physical Stage A | Not run | One provisioned iPhone and bounded evidence record |
| Stripe sandbox Stage B foundation | Implemented and verified locally: native PaymentSheet setup, server-verified challenge commit, signed webhook reconciliation, review, and one idempotent test PaymentIntent | Dedicated non-production target, tester allowlist/kill switch, Stripe test secrets and webhook, secure dispatcher, and hosted sandbox acceptance |
| Real fees | Disabled | Apple, Stripe, legal, age/jurisdiction, hosted deployment, and production acceptance gates below |

## Stage B Stripe sandbox foundation and live-fee gate

Stage B now has a local Stripe sandbox implementation. This section locks the
implemented product contract. Local database, Edge Function, Swift, simulator,
and conformance checks pass; this does not claim that the sandbox is hosted,
that end-to-end webhook and dispatch behavior is accepted, or that any live
payment is permitted.

The sandbox flow is:

1. After Health access is ready and before final confirmation, create a Stripe
   `SetupIntent` to save an approved payment method for later off-session use.
   Starting a challenge creates no authorization hold and no charge.
2. Create the challenge only after payment setup succeeds and the exact amount,
   terms version, payment-method reference, and explicit off-session consent are
   bound to the exact creation request. GameTime stores provider identifiers and
   status, never card data.
3. Run the seven-day challenge and its existing 24-hour final-sync period. No
   payment decision occurs before the evidence cutoff.
4. `met_goal`, `inconclusive`, and pre-start cancellation close with $0 charged.
   Missing, conflicting, or unresolved step data never becomes a miss.
5. Publish a complete `missed_goal` as provisional. Set
   `review_deadline = published_at + interval '7 days'`. No charge may occur
   before that deadline or while a timely review remains unresolved.
6. If no review is filed by the deadline, or a completed review confirms the
   miss, create exactly one idempotent off-session Stripe `PaymentIntent` for the
   frozen amount. If a review overturns the miss, or remains unresolved at the
   deadline, waive the amount and charge $0.
7. If the off-session attempt fails or requires customer action, do not retry it
   automatically. Require an explicit user-authorized recovery action and block
   another paid challenge until the payment state is resolved or waived. Do not
   use repeated retries or debt collection.

All Stripe objects and payment methods in the sandbox use Stripe test mode. A
sandbox `PaymentIntent` moves no real money. Sandbox UI must say
**Payment test mode — no real money moves.** Test objects, simulator results, and
local webhook fixtures do not prove hosted deployment, provider approval, or a
live charge.

Stage A, Solo 2A, and Solo 2B remain structurally `test_only`. D113 requires a
new forward terms version and forward migrations. Do not rewrite their enums,
rows, results, or historical migrations to add Stripe.

Live Stripe mode remains disabled until all of these exist:

- A US counsel memo defining the fee model, 18+ rules, versioned state allowlist,
  cancellation, waiver, review, refund, deletion, and retention policies.
- Written Stripe approval explicitly covering a HealthKit-informed,
  failure-contingent, off-session fee.
- App Store payment and HealthKit policy clearance.
- Approved age and jurisdiction verification.
- Separately approved hosted deployment, webhook verification, reconciliation,
  and end-to-end sandbox acceptance before any live configuration.

The invite-only Release sandbox also remains NO-GO until the narrower D114
candidate, hosted, physical-device, and TestFlight gates pass.

Injury reporting uses structured attestations without medical records. Its
policy, review path, and effect on a provisional miss require the same written
approval as the rest of the live fee model.

Steps 2A and 2B remain `test_only`. Dollar-denominated commitments, logical
settlement, and fake authorization events are not Stage B clearance. They do
not reserve funds, authorize a charge, or move money.

## Deferred V2

V2 may add `social_accountability`, where people share a challenge but keep
independent goals, outcomes, and fees. It must not pool money or pay a
participant. Start with structured reactions and reminders. Free-form comments
remain blocked until Apple-compliant filtering, reporting, blocking, moderation,
and support controls exist.

## Verification rules

- Simulator tests prove navigation and fixtures, not Apple services.
- Local database tests prove migrations and policies, not hosted scheduling.
- A signed build proves signing inputs, not Apple Health reads, observer wakes,
  Watch catch-up, or locked-device retry.
- Permission-request completion does not prove readable data. A successful
  Health query, including an authoritative zero, is the snapshot observation.
- A seven-day local-calendar window is not always 168 elapsed hours.
- A one-user device run does not prove two-actor privacy isolation.
- Local fake-adapter tests do not prove a real processor, money movement, legal
  or App Review approval, hosted scheduling, physical-device behavior, or
  hosted multi-user isolation.
- Preserve exact request UUIDs and encoded bytes for every retried mutation.
- Never expose a service-role key, Apple private key, access token, assertion,
  payload body, raw health value, or private profile data in evidence or logs.
- Require explicit approval before push, merge, deployment, hosted mutation,
  TestFlight, production configuration, or submission.

## References

- `docs/PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md`: controlling automatic
  Personal acceptance runbook.
- `docs/PERSONAL_V1_ACCEPTANCE.md`: historical hourly/App Attest Personal record.
- `docs/M8_1_STAGING_ACCEPTANCE.md`: retained historical social-alpha runbook.
- `docs/M6_5_DEVICE_CONFORMANCE.md`: legacy/social metric App Attest conformance.
- `docs/archive/2026-07-30_IMPLEMENTATION_STATUS.md`: historical implementation evidence.
- `docs/archive/2026-07-30_IMPLEMENTATION_PLAN.md`: previous milestone plan.
