# GameTime project memory

## Adopted business direction — September 4, 2026

The owner explicitly selected **friend duels** and **personal performance
commitments** as GameTime's new business model. This is the chosen direction,
not a list of alternatives awaiting confirmation.

GameTime makes athletic challenges between friends and personal performance
claims concrete through agreed rules, credible results, and meaningful
financial stakes. The audience of interest is fit, active adults, especially
people in their twenties who enjoy competition and products such as Kalshi
and Polymarket. Demand from that audience remains to be validated; their
interest in prediction markets is not evidence of demand for this app.

### 1. Friend duels

- Friends challenge each other to a defined athletic contest, accept the same
  rules, follow progress, receive a result, and can play again.
- Illustrative format: "Fastest qualifying 5K this month; $20 each."
- Participant stakes, a pooled entry amount, and winner payouts are within the
  new product-design scope. The precise permitted payment structure, fees,
  settlement rules, launch jurisdictions, and provider remain unresolved.
- Candidate formats include same-event races, fixed-distance time trials,
  agreed personal targets or handicaps, and bounded consistency challenges.
- Sharing a challenge into an existing friend group and rematches are leading
  engagement hypotheses, not implemented capabilities of the current app.

### 2. Personal performance commitments

- A person commits money to achieving a measurable athletic milestone by a
  deadline, including goals lasting longer than the current seven-day window.
- Owner example: "Run a mile in under six minutes before December 1, or lose
  the committed money." The amount, year, and exact proof rule are examples or
  open choices, not universal product defaults.
- Friends can follow attempts and progress. Intermediate milestones and
  verified attempts should give the commitment a continuing story.
- Actual locked deposits and later failure-contingent charges are different
  funds flows. Do not describe a saved payment method as locked money.
- The destination of forfeited money must be explicit. Whether it goes to the
  business, an approved beneficiary, or another participant is not decided.

### Product and implementation context

- Running is the leading initial sport recommendation. Garmin activities,
  running distance, workout minutes, and timed performances are candidate
  inputs. The owner has not locked the launch metric or device ecosystem.
- Verification must define accepted sources, distance, elapsed versus moving
  time, edits, late uploads, and disputed results. Garmin intensity minutes
  are weighted and must not silently equal another provider's active minutes.
- Spectator wagering, a public prediction exchange, tradable contracts, and
  markets against a participant's own performance are not part of the adopted
  initial scope.
- Pricing is open: transparent contest/service fees and optional recurring
  club features are hypotheses. No rake, subscription, stake limit, or revenue
  forecast has been approved.
- The existing app is still the solo seven-day Apple Health steps product with
  test-only/sandbox payments. It has not gained duels, Garmin integration,
  performance-goal verification, locked deposits, or live payouts through this
  decision.

### How this decision changes prior plans

This memory supersedes the old **future business scope** that restricted
GameTime to solo steps or prohibited participant payouts in a future social
version. Preserve old decisions and historical agreements; document the pivot
with new decisions and forward-compatible designs. Do not reinterpret old
charity contests or existing Personal/Solo records as the new products.

The strategic choice does not establish legal or provider approval. Keep live
money disabled until the selected funds flow has the applicable jurisdiction,
processor, platform, verification, and operational clearance. Existing
sandbox-only cancellation and step-trust policies are not automatically
suitable for a real-money duel or months-long deposit.

### Planning baseline completed — September 4, 2026

The documentation planning task produced [docs/BUSINESS_MODEL.md](docs/BUSINESS_MODEL.md),
the replacement [PLAN.md](PLAN.md), and D123 in [DECISIONS.md](DECISIONS.md).
The [prior Personal plan](docs/archive/2026-09-04_PRE_PIVOT_PLAN.md) is preserved.
These are plans and a source inventory, not implemented new products or a fresh
hosted/device acceptance record.

The recommended first slice is a local, default-off, simulated same-event 5K
duel agreement backend with two explicit consents. The proposed human pilot
uses organizer-published chip times before adding automatic Garmin proof.
The proposed commitment launch format is a timed 5K goal over 28–90 days;
true-mile and asynchronous formats follow. These are reversible planning
defaults, not additional owner mandates. Neither a provider, a forfeiture
beneficiary, a live price nor a launch jurisdiction has been selected.

### Original planning request

Update the project documentation to reflect this direction, inspect the
existing implementation for reusable pieces, and create a concrete phased
implementation plan. Separate what exists, what is decided, what is proposed,
and what needs external validation. The planning task should choose reasonable
reversible defaults and continue without asking whether to make this pivot.

The original planning brief is
[docs/NEXT_BUSINESS_MODEL_PROMPT.md](docs/NEXT_BUSINESS_MODEL_PROMPT.md).
For the next build task, use the Phase 1A implementation prompt at the end of
[PLAN.md](PLAN.md#copy-ready-first-implementation-prompt).

### Phase 1A implementation — September 4, 2026

The isolated local simulated 5K duel agreement backend is now implemented:
immutable policy/event/terms, creator and invitee consents, private exact-request
and enrollment records, default-off database admission, and pre-start account
deletion. Local database and real-session concurrency evidence is recorded in
[DUEL_AGREEMENT_V1_ACCEPTANCE.md](docs/DUEL_AGREEMENT_V1_ACCEPTANCE.md), along with
the Phase 1B native handoff. The planning prompt above is retained as the
original task specification. No native duel feature, proof, scoring, scheduler,
provider integration, hosted mutation, deployment or live money was added.

### Phase 1B native implementation — September 4, 2026

The opt-in native simulated duel flow now has typed models, an isolated RPC
client, actor-bound durable request recovery, accepted-friend/event selection,
creator review/receipt, explicit invitee consent, safe exits and history.
Debug/Staging fixtures are separate from live clients; actual duel RPC clients
are restricted to an explicitly selected loopback stack. Release cannot route
to the feature. See [DUEL_NATIVE_V1_ACCEPTANCE.md](docs/DUEL_NATIVE_V1_ACCEPTANCE.md)
for verification. Phase 1B local acceptance is complete: the authenticated
two-account native-to-local-HTTP smoke passed using real local Auth sessions,
the production Swift RPC client, native account switching and durable recovery.
Gate-off preserved committed retries, history and safe cancellation; cleanup
closed admission and revoked the fictional sessions. VoiceOver and physical
devices remain unverified. Results in the app, review operations, providers,
hosted rollout and money remain unimplemented.

### Phase 2(a) pure evaluator — September 4, 2026

Phase 2 has started with its first planned slice. The isolated pure Deno
evaluator now checks the exact Phase 1A fictional 5K policy and both consents,
compares whole-second official chip times, distinguishes confirmed nonfinishes
from missing proof, and evaluates correction, notice, review and finality
deadlines. It preserves PostgreSQL microseconds and a persisted final outcome;
later corrections only flag support. See [DUEL_SCORING_V1_ACCEPTANCE.md](docs/DUEL_SCORING_V1_ACCEPTANCE.md)
for the fixture matrix, verification and Phase 2(b) handoff.

This is a pure decision module, not an operational result service. Private proof
storage, operator permissions, worker transitions, durable notices, native
results/review, rematches and links remain Phase 2 work. No schema, historical
agreement, native source, hosted state, provider, scheduler or money path changed.

### Phase 2(b) private proof and operator boundary — September 5, 2026

Private append-only fictional sources and independently reviewed full-pair proof
revisions now persist behind a separate default-off gate. Per-duel server-owned
reviewer grants/revocations, active session checks, server receipt/retrieval
metadata, source/bib validation, exact retries and audited source reads are
implemented. Participants receive redacted receipt metadata only. Role,
correction, cutoff/cap and deletion races pass local SQL checks; the persisted
snapshots pass the pure evaluator and the full portable regression gate passes.
See [DUEL_PROOF_V1_ACCEPTANCE.md](docs/DUEL_PROOF_V1_ACCEPTANCE.md).

**Phase 2(c) handoff (implemented below):** activation/expiry, durable provisional notices, review
cases/resolutions, safe exits, a clock-injected worker, immutable final results
and separately appended simulated settlement. Proof receipts do not publish
results or release slots. Post-final support correction intake also remains
unimplemented. Native results/rematches, real organizer proof, hosted operation
and live money remain outside this completed local slice. Existing agreements,
native source and historical product behavior were preserved.


### Phase 2(c) simulated lifecycle — September 5, 2026

The separate default-off local lifecycle worker now persists activation/expiry,
durable provisional notice pairs, participant cases and independent resolutions,
safe exits, immutable final results and separately appended nonredeemable
simulated settlement. Full-snapshot optimistic commits serialize corrections,
notices, reviews, deletion and finalization; PostgreSQL microseconds and the
unchanged evaluator's full review windows are preserved. Post-final fictional
corrections enter a separate audited support ledger and cannot change results.

Local SQL boundary/concurrency tests, the persisted scorer/worker smoke and the
full portable regression gate pass. See [DUEL_LIFECYCLE_V1_ACCEPTANCE.md](docs/DUEL_LIFECYCLE_V1_ACCEPTANCE.md)
for the evidence, manual loopback runner and Phase 2(d) handoff. Historical
agreements retain their terms and receipt meanings. No native source, hosted
state, schedule, external delivery, provider or live money changed.

**Phase 2(d) is implemented below.** Phase 2(e) still owns new-consent
rematches and target-bound links. Real organizer operations and hosted rollout
remain separate gates.


### Phase 2(d) native progress and review — September 5, 2026

The opt-in native local duel now renders durable result notices and correction
history, own review cases and decisions, immutable final results, and separately
recorded simulated returns. Review filing and withdrawal/injury actions use
actor-bound durable requests with explicit exact retries. Account changes and
failed reads clear result content; blocked contacts retain only allowed own
receipts. Server timestamps preserve PostgreSQL microseconds.

An additive participant projection exposes server time, available-action hints
and redacted saved exits without changing historical agreements or scoring.
Local SQL, portable regression, native unit/UI and authenticated two-account
HTTP evidence is recorded in
[DUEL_NATIVE_LIFECYCLE_V1_ACCEPTANCE.md](docs/DUEL_NATIVE_LIFECYCLE_V1_ACCEPTANCE.md).
All exercised local gates finished off; fictional sessions were revoked.
VoiceOver traversal and physical devices remain unverified. No hosted state,
schedule, external delivery, provider or live money was enabled.

**Phase 2(e) is implemented below:** new-consent rematches and target-bound invitation links.
Real organizer operations, hosted rollout and money remain separate gates.


### Phase 2(e) rematches and invitation links — September 5, 2026

The local simulated duel now supports **Challenge again** with the same friend,
a different future event and fresh explicit consent from both runners. Private
provenance links the new agreement to its predecessor without changing earlier
terms, results or simulated returns. Creator-issued links expire at the earlier
of 24 hours or the invitation cutoff, can be revoked/replaced, and resolve only
for the named recipient with an active session. Opening never accepts.

Native sharing is initiated by the person. The Debug/Staging custom app route
retains only an untrusted locator through login/relaunch; account changes clear
resolved content and reject late responses. All new mutations use exact durable
requests. Release keeps its original URL registrations and no duel route.
Local SQL, real-session concurrency, native unit/UI and authenticated two-account
HTTP evidence is recorded in
[DUEL_REMATCH_LINK_V1_ACCEPTANCE.md](docs/DUEL_REMATCH_LINK_V1_ACCEPTANCE.md).
The local smoke finished with admission off, no open slots and fictional
sessions revoked. No hosted state, schedule, external message, provider or money
was enabled. Universal-link hosting, actual organizers/reviewers, VoiceOver
traversal and physical-device acceptance remain separate work.

**Phase 3(a) is implemented below:** separate longer performance-commitment agreements.
The proposed initial official-5K format remains a reversible planning default.

### Phase 3(a) performance commitment agreements — September 5, 2026

The separate local agreement backend now freezes a strict official-5K target,
28–90 elapsed UTC days, exact source/window/deadlines, owner consent and a
nonredeemable simulated amount. The $20 amount, $0 fee, future start within
30 days and duration interpretation are reversible implementation defaults;
the forfeiture recipient remains explicitly unselected. Private tables and
owner RPCs have separate default-off admission and one open commitment slot.

Digest-bound preview/creation, actor-bound exact retries, owner history,
cancellation/withdrawal/injury exits and account deletion retention are locally
verified, including real transaction races and full portable regression.
An accepted duel and Personal history can coexist with one new commitment.
Deadline passage keeps it open awaiting proof; no result or money is inferred.
See [PERFORMANCE_COMMITMENT_AGREEMENT_V1_ACCEPTANCE.md](docs/PERFORMANCE_COMMITMENT_AGREEMENT_V1_ACCEPTANCE.md).

**Phase 3(b) is implemented below:** nominated event attempts and strict target evaluation.
Proof/review retention scopes, milestones, followers and native commitment
screens remain later work. No earlier migration or native source changed.
All exercised gates finished off. No hosted mutation, deployment, schedule,
external message, provider operation or live money was enabled.


### Phase 3(b) nominated attempts and evaluator — September 5, 2026

A separate default-off local attempt boundary now stores immutable fictional
5K event nominations, private organizer sources and independently reviewed
append-only corrections. Exact requests, audited source reads, active reviewer
sessions/grants and product-specific retention holds protect the longer goal.
Owner reads expose redacted receipts, not raw proof or a published result.

The pure evaluator enforces the existing strict target, preserves a qualifying
success across later slower attempts, distinguishes missing proof from a
confirmed miss and evaluates the full frozen notice/review/finality windows.
A confirmed-set miss requires explicit owner completeness; no-attempt silence
never counts as acknowledgement. Local nomination bounds and conservative
whole-event admission are reversible implementation defaults, recorded in D125.

See [PERFORMANCE_ATTEMPTS_V1_ACCEPTANCE.md](docs/PERFORMANCE_ATTEMPTS_V1_ACCEPTANCE.md)
for local SQL, concurrency, pure fixtures and persisted-snapshot evidence.
The evaluator does not publish results or release slots. Commitment notices,
review cases, final results and settlement remain a later lifecycle slice.
Existing agreement terms and earlier migrations were preserved; no native,
hosted, schedule, external message, provider or live-money path was changed.

**Phase 3(c) is implemented below:** named intermediate milestones and manual progress,
which must never substitute for qualifying organizer proof. Following and
commitment result/review history remain Phases 3(d/e). Real-proof retention,
support operations, native flows and hosted acceptance are still unimplemented.

### Phase 3(c) milestones and manual progress — September 5, 2026

A separate default-off local owner ledger now stores immutable named milestones,
manual check-ins and append-only completion/reopening/retirement. Actor-bound
exact requests survive gate shutdown, safe closure and deadline passage; active
owner/session checks protect reads and recovery. History uses bounded sequence
pagination with milestone states frozen to the same upper sequence.

Manual progress is explicitly owner-reported and never enters organizer proof,
the unchanged evaluator snapshot, result finality or settlement. The local
32-milestone/512-entry limits and text/date rules are reversible defaults in D126.
A product-specific retention hold preserves history and receipts through safe
closure and deletion; an approved real-note retention/purge policy remains open.
See [PERFORMANCE_PROGRESS_V1_ACCEPTANCE.md](docs/PERFORMANCE_PROGRESS_V1_ACCEPTANCE.md)
for SQL boundary/concurrency, pure scorer isolation and persisted-smoke evidence.
The full portable regression gate passed. Progress/attempt/commitment admission
finished off with no open commitment slots or fictional progress sessions.

**Next is Phase 3(d):** explicit friend-following permissions and selected
progress, revocation, reactions and reminder/report/block/support behavior.
Following gets no implicit access to private notes or proof. Phase 3(e) still
owns result/review persistence. Native commitments, hosted operation, real
organizers and money remain later work; earlier agreements and native source
were preserved.

### Checkpoint before Phase 3(d) — September 5, 2026

The existing implementation through Phase 3(c) was reviewed with focused
privacy, concurrency, contract and native coverage. A forward migration fixes
rematch/link session expiry during waits and performance source JSON that the
pure evaluator could not consume. Unused evaluator history maps were removed;
local test connections now support a separate disposable stack. See
[the checkpoint review](docs/PHASE_3D_CHECKPOINT.md) for the inventory, fresh
verification, retained limitations and local commit scope. Phase 3(d) was not
implemented. Original agreements, the normal development database and unrelated
skills/trash were preserved.
