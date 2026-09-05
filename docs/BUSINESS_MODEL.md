# GameTime business model

Adopted direction: September 4, 2026. Planning baseline: local `c403b88` plus
the owner's existing guidance changes. This is a repository inspection and
product plan; no new app capability, hosted state, or payment approval is claimed.

Implementation update, September 4: Phase 1A now provides the isolated local
simulated same-event 5K agreement backend, with both consents and default-off
admission. Phase 1B now adds the opt-in native fixture/local agreement flow;
see [native acceptance](DUEL_NATIVE_V1_ACCEPTANCE.md). Phase 2(a) adds the isolated
[pure result evaluator](DUEL_SCORING_V1_ACCEPTANCE.md). September 5: Phase 2(b)
adds [private fictional proof and independent operator authorization](DUEL_PROOF_V1_ACCEPTANCE.md);
Phases 2(c–e) subsequently added the local lifecycle, native results/review,
rematches and invitation links. Phases 3(a–c) added separate commitment
agreements, nominated attempts and private manual progress. Hosted operations,
commitment followers and result/review persistence remain open.
See [the acceptance record](DUEL_AGREEMENT_V1_ACCEPTANCE.md) for local
verification and the Phase 1B handoff; this does not establish hosted or race proof.

## Decision and authority

GameTime turns athletic challenges between friends and personal performance
claims into agreed rules, visible attempts, credible results, and meaningful
financial stakes. **Friend duels and personal performance commitments are the
adopted business model.** Participant stakes and winner payouts are in future
design scope. The precise funds flow is still unresolved.

Read [PROJECT_MEMORY.md](../PROJECT_MEMORY.md) for owner intent,
[D123](../DECISIONS.md#d123-friend-duels-and-personal-performance-commitments-are-the-adopted-business-model)
for the decision, [PLAN.md](../PLAN.md) for implementation order, and
[README.md](../README.md) for current behavior. This document replaces earlier
solo-only future positioning. Earlier decisions still govern the records they
created. The [prior plan](archive/2026-09-04_PRE_PIVOT_PLAN.md) is preserved.

| Status | Meaning here |
| --- | --- |
| Adopted | Both products, athletic focus, stakes in design scope, private friend competition; no spectator betting or public prediction exchange |
| Implemented | The existing Personal seven-day Apple Health steps app, internal test-only and Stripe sandbox paths, dormant historical systems below, the isolated local Phase 1A simulated duel agreement backend with an opt-in Phase 1B native fixture/local flow, Phase 2(a)'s pure fictional-result evaluator, Phase 2(b)'s private fictional proof/operator boundary, Phases 2(c–e)'s local lifecycle/native results/rematches/links, and Phase 3(a–c)'s separate commitment agreements/attempts/manual progress |
| Recommended | Reversible first formats, timing rules, simulated amounts, pilot sizes and thresholds in this document |
| Unresolved | Demand, provider access and permission, real-money structure, recipient of commitment forfeitures, prices, jurisdictions and launch clearance |

## Audience, positioning, and engagement

Start with recreational runners who already compete with friends, especially
active adults in their twenties. Interest in Kalshi or Polymarket suggests a
possible appetite for consequential outcomes; it does not establish demand
for GameTime. The initial job is to make “race me” or “I'll run this time by
that date” specific enough to accept, follow, and finish.

Running is the recommended first sport because distance and time are legible
to this audience and one performance can resolve a challenge. This is a product
hypothesis, not a claim that GPS or wearable times are inherently reliable.
GameTime needs to beat an existing group chat on agreement clarity, result
credibility, and ease of playing again. Avoid a general fitness dashboard,
public matchmaking, a training prescription, or a trading interface initially.

The proposed duel loop is invitation → acceptance → race anticipation → result
→ rematch. A participant may later share an invitation into an existing group
chat through the system share sheet; recipients must authenticate and accept.
The proposed commitment loop is goal → named milestone → attempt → friend
encouragement → another attempt → final result → next goal. Progress must have
meaning between creation and a deadline months away. The duel loop is available in the opt-in local simulation; native commitment
screens and friend following remain unimplemented.

Retain Today, Challenges, and You as a starting navigation structure. Add typed
duel and commitment destinations as they are implemented; do not restore the
old social shell wholesale. Share result summaries only by explicit choice.
Followers get selected progress and results, never automatic access to raw
Health data, routes, payment methods, or dispute evidence. Financial amounts
are private to participants by default. Free-form chat, public feeds, and
automatic contact imports are deferred; structured reactions still need report,
block, and support behavior.

## First sport, format, and proof recommendation

**First usable pilot: two friends in the same organized outdoor 5K, compared
using the organizer's published chip time, with simulated $20 stakes each.**
Use one event/course/wave, one attempt, no handicaps, and a single timing basis.
The source is a manually reviewed official result, with participant-to-bib
mapping; it is not a screenshot asserted by a participant and not a new Garmin
integration. Pick an event with permission to use its results and a clearly
defined 5K course and chip-time column. Event selection is a pilot prerequisite,
not something verified in this planning task.

This deliberately narrows “fastest qualifying 5K this month” to a common race
before tackling different routes, terrain, weather, device error, and unlimited
attempts. It adds event-schedule friction; measure that in the pilot. If runners
cannot arrange repeat events, prioritize the asynchronous proof phase before
interpreting weak rematches as lack of demand for friend duels.

Local Phase 1A agreements use the `fixture_official_5k_v1` source policy with
fictional people and events; result records remain Phase 2 work. Human-pilot
proof would be `organizer_chip_5k_v1`, still a proposed source. A reviewer records source
reference, event identity, bib mapping, published value/precision, retrieval
time, and decision. No scraping or organizer API access is assumed.

For commitments, start with **one outdoor 5K below a user-chosen time within
28 days**, selectable out to **90 days**, using a reviewed qualifying event.
Named intermediate milestones (choose an event, first attempt, next attempt)
are progress only; they cannot trigger a charge. A later version supports the
owner's mile example: **1,609.344 metres in under 360 seconds by an explicit
date and year**. A 1,600 m track result is not a mile. A December 1 example
must freeze its year, timezone and exact closing instant at agreement.

Garmin Activity API is the recommended next automatic source for asynchronous
outdoor runs, conditional on access, permitted use, and validation. Apple
Watch workouts through HealthKit are a candidate parallel source, not a silent
fallback. Neither the current daily step snapshots nor Garmin-written steps
in Apple Health qualify as running-performance proof.

## Proposed duel agreement and lifecycle

These defaults apply only to new simulated duels. They do not amend old
Personal cancellation, Solo appeals, or charity obligations.

1. The creator chooses one accepted friend, an approved event within 30 days,
   the event's common start/end instants, timing policy, simulated amount,
   result/dispute deadlines, and cancellation rules. Creation freezes a
   version and complete terms digest; changed terms require a new invitation.
2. The creator's consent and named invitation are recorded atomically. The
   invited friend sees identical terms and accepts that version and digest.
   Acceptance expires at the earlier of creation + 72 elapsed hours or one
   hour before the event window starts. Equality at the cutoff is too late.
3. Both participants must accept before activation. In a future funded model,
   both funding confirmations must also exist before the funding deadline;
   absent funding cancels and returns any received funds. This is a planned
   invariant, not an enabled payment action.
4. The event runs within the frozen window. After its end, allow 72 elapsed
   hours for official results. Show “waiting for results,” not a predicted
   financial outcome. Publish a provisional result and notify both people.
5. Give both participants seven elapsed days from the durable result notice
   to dispute. A timely case pauses settlement. An independent reviewer has
   seven days after filing; if still unresolved, void the simulated outcome.
   Final settlement cannot precede the filing deadline even if a case closes
   early. A failed push does not remove the in-app notice or shorten a deadline.
6. Freeze the result and a separate simulated settlement event. A rematch is a
   fresh challenge with new dates, new request identity, and both consents;
   it references the old result but inherits no charge authority or proof.

| Situation | Recommended simulated rule |
| --- | --- |
| Both finish with valid proof | Lower chip time wins; compare the organizer's published whole seconds. Reject an event lacking a common timing basis; do not compare one gun time with another chip time |
| Tie at agreed precision | Tie, return both simulated stakes, fee zero; never use integrity score or fastest upload as a tie-break |
| One finish; other independently confirmed DNS/DNF/disqualification | Finisher wins after review; no hidden requirement for both to finish |
| Both confirmed without a qualifying finish | Void; return both simulated stakes; no all-donate outcome |
| One or both records missing, ambiguous identity, disputed course, delayed organizer, conflicting timing | Await proof through cutoff, then inconclusive/void if unresolved; missing upload alone is not a loss |
| Official corrections before finality | Append a new proof revision and recompute provisional result. Notify both and give seven full days on the corrected result; cap at end of event + 30 days, then void if unresolved |
| Correction after finality | Open an audited support correction case; never overwrite the original result or debit again automatically. No new financial consequence without the eventual approved correction policy |
| Decline, invitation expiry, creator cancellation before start | Cancel, release slot, preserve agreement and response history; zero fee |
| Withdrawal by either accepted runner before start | Cancel the pair; notify the other; zero fee. At/after start use the next rule |
| Voluntary withdrawal after start | In simulated pilot, end as `withdrawn_no_contest`, zero consequence. Track separately from a completed loss; do not copy this escape rule into funded contracts |
| Injury or event cancellation | Stop participation; void simulated duel without medical uploads. Real-money injury/withdrawal rules require a new approved policy; no pressure to race injured |
| Blocking or deleting an account | Stop social contact and revoke access; preserve the minimum agreement/result audit. Block is not permission to rewrite results; pilot withdrawal/deletion can close unfinalized simulated play without money |

## Proposed performance commitment lifecycle

Use a separate owner agreement and lifecycle: draft → scheduled/active →
attempts → awaiting proof → provisional success/miss/inconclusive → review →
final result → simulated disposition. Followers are not counterparties and
cannot change terms, approve a miss, or claim forfeited money by following.

Freeze distance, strict comparator (`elapsed_ms < target_ms`), accepted source,
start, deadline, IANA display timezone, upload cutoff, review rules, amount,
funds-flow mode, and any future beneficiary. Only attempts starting at/after
agreement and finishing before the exclusive deadline count. Display an exact
closing time rather than an ambiguous “by December 1.” Calendar selection must
resolve ambiguous/nonexistent local times explicitly; stored UTC instants own
scoring. Travel does not move a deadline.

Any qualifying attempt can satisfy the goal. Show it as provisionally met;
later slower attempts do not undo it. Corrections or disqualification may
invalidate that proof through an append-only revision. Keep interim milestones
and practice runs distinct from qualifying proof. Allow additional agreed
events within the original source policy, but never change distance, target,
beneficiary, or deadline on an active agreement; replacement requires fresh
consent and preserves the closed original.

At deadline + 72 hours, freeze the submitted proof set. Use the same seven-day
filing/reviewer windows and 30-day post-deadline finality cap as duels. A proven
qualifying attempt means success. A confirmed complete set of nominated-event
results without success, or an explicit owner acknowledgement of no qualifying
attempt, may support a provisional miss in the pilot. No submission, revoked
permissions, a disconnected device, or an unreadable result is not proof of a
miss. Unresolved completeness becomes inconclusive with zero consequence.
This allows strategic non-reporting; measure it. Real-money collection cannot
launch until the proof-of-miss problem has an acceptable versioned resolution.

Before start, cancel freely. During the simulated pilot, allow withdrawal or
injury exit with no consequence and retain its reason category. Success,
inconclusive, cancellation and withdrawal all close at zero loss. A confirmed
miss consumes the simulated commitment only. The eventual recipient is
explicitly **unselected**, so simulation records `simulated_loss` with no payee
or transfer; it must not imply the business or a friend received money.

## Verification contract and trust limits

The organizer pilot uses one official result per runner and event. Record
published whole seconds as integer milliseconds (`seconds × 1000`); reject
mixed/subsecond-only inputs until a version defines normalization. Keep the
source's stated precision. Identity matching requires the agreed bib and
event plus reviewer resolution of name ambiguity, not name matching alone.
Do not infer full-course completion from accumulated daily distance.

Before enabling an asynchronous time-trial policy, implement and validate:

- One outdoor running activity and a continuous distance/time series; exact
  provider activity ID, originating device/source, event times, upload times,
  consent version, edits/deletions, and duplicate/reimport lineage.
- A versioned distance rule: same measured course where possible, otherwise
  a calibrated GPS tolerance and explicit exclusion rules established by field
  tests. Do not quietly round a short activity up to 5K or extrapolate a mile.
- Full elapsed time including pauses. `end - start` is the initial time basis;
  do not substitute moving time, active duration, best pace, or aggregate
  exercise minutes. Extracting the first exact 5K of a longer run needs a
  reviewed interpolation/segment policy and sample-gap limits before use.
- Separate exclusion, suspicious-proof review, and valid result states. Reject
  manually entered or unsupported imported workouts; flag unexplained edits,
  impossible jumps, vehicle-like traces, and source/device changes for review.
  GPS, OAuth, and App Attest do not independently prove who ran or that a
  performance was honest. Peer approval alone cannot establish cash eligibility.
- Authoritative deduplication, late/reordered delivery, revocation and outage
  handling. Reuse of one event in distinct agreements is allowed only when each
  agreement independently permits it; never count duplicates as extra attempts.
- A complete missed-goal rule that separates no qualifying attempt from no
  data. The current permissive Personal steps policy is insufficient for cash.

Raw routes remain private and should be avoided in the organizer pilot. For a
later route adapter, propose deleting raw proof 30 days after finality unless
an active case requires a scoped hold; keep only minimal agreement/result
facts under a separately reviewed retention policy. Months-long goals must
not lose needed proof to the historical hourly/90-day purge jobs. Extend
deletion, revocation, and retention deliberately; never reuse those jobs by
table-name coincidence.

## Repository inspection: reuse and gaps

This table preserves the Phase 0 planning inspection at `c403b88`. “Exists”
means source and associated tests inspected then, not the later implemented
slices summarized above or a fresh hosted audit.

| Area and evidence | Reuse recommendation | Missing or incompatible |
| --- | --- | --- |
| `ios/GameTime/GameTime/AppShellView.swift`, `PersonalAccountabilityStore.swift`, `PersonalChallengeFlow.swift` | Keep three-tab shell, loading/error patterns, history and receipt presentation | Shell maps social destinations to unavailable; no reachable running duel/commitment journey |
| `PersonalHealthStepReader.swift`, `PersonalStepProgressStore.swift`, `PersonalHealthSnapshotUploader.swift`; migration `20260812154757_personal_health_snapshot_v2.sql`; tests `440_*`, `441_*` | Reuse local-first refresh, coherent cache, account cancellation and cutoff patterns | Exactly seven daily step totals; no workout timing, distance-series proof or opponent verification; permissive source policy stays Personal-only |
| Identity/social migration `20260724203000_identity_social_graph.sql`; `SupabaseClients.swift` friendship clients; tests `010_*`–`040_*` | Reuse Apple identity, durable actors, exact-handle friendship and blocks after access audit | Friend routes dormant; share links, target-bound redemption, followers, reporting/support and new read projections absent |
| `20260727030649_m8_1_live_social_loop.sql`, `PendingChallengeStore.swift`, `DomainModels.swift`; tests `070_*`, `190_*` | Reuse exact-request and bounded-read patterns | Old invitations require charity/timezone terms; old envelopes must never replay as new duel requests |
| `_shared/scoring.ts`, `integrity*.ts`, `metric_snapshots` | Reuse pure fixture-driven evaluation approach and reason/version discipline | Scorer sums hourly metrics/pass rates; `distance_meters` is not a fastest-run engine; Garmin bundle allowlist is not Garmin API integration |
| `20260728231601_m8_3c_standings_results_obligations.sql`; tests `210_*` | Reuse immutable provisional/final publication, locking and redacted reads as patterns | Outcomes create charity obligations; no participant pool, wallet, winner payout or operated new-product dispute queue |
| `20260803001438_solo_contract_domain.sql`, `20260803001455_solo_contract_rpc_boundary.sql`, `20260803014252_solo_fake_authorization_adapter.sql`; tests `330_*`–`380_*` | Reuse frozen policy digest, exact requests, one-open uniqueness, append-only evaluation/appeal and fake-failure tests | Disabled steps-only 1–7-day aggregate; fake authorization reserves nothing. Hosted tables were previously observed, runtime values not freshly checked |
| `PersonalPaymentClient.swift`, `SupabasePersonalPaymentClient.swift`; `personal-payment-setup`, `personal-challenge-commit`, `personal-stripe-sandbox-*`; tests `400_*`–`412_*` | Reuse provider isolation, signed events, idempotency, reconciliation and review patterns selectively | Saves a method and simulates one later confirmed-miss charge; no deposits, participant onboarding, funded pools, refunds/payout ledger or approval for prize competitions |
| `20260806173723_personal_result_worker.sql`, notification outbox, `deliver-push` | Reuse clock-injected workers and durable payload-free notices | New entity dispatch, milestones, correction notices, rematch notifications and operated schedules require additions; local cron is not hosted proof |
| `YouView.swift`, `AppModel.deleteAccount`, `functions/delete-account`, D81 actor/retention migrations; tests `170_*`, `220_*` | Existing reauthentication/deletion client and server orchestration are reusable foundations | New agreements, reviewer access, provider revocation and long-duration retention need explicit coverage; end-to-end hosted proof not established here |
| `GameTimeCore`, `supabase/tests`, Deno fixtures, `GameTimeTests`, `GameTimeUITests`, `.github/workflows/ci.yml` | Keep SQL concurrency/RLS, pure scoring fixtures, portable Swift, simulator/configuration gates | Add new-product suites; scope old forbidden-social-language assertions to Personal, never globally weaken legacy checks |

At that planning baseline, no Garmin OAuth, Activity API ingestion, official-event
catalog, running attempt ledger, personal performance-goal model, followers,
rematches or new monetary settlement existed. Historical [social/Solo notes](archive/2026-08-03_DORMANT_SUBSYSTEMS.md)
and [charity plan](archive/2026-07-31_CHARITY_PLEDGE_DONATION_IMPLEMENTATION_PLAN.md)
are reference material, not ready-made new-product implementations.

## Payment-model decisions and options

**Now:** new development and pilot use nonredeemable simulation only, no card,
no cash-equivalent prize, no outside collection, no payment provider calls.
Use a displayed $20 example per person and fee $0; these are test labels, not
approved prices or live limits. Retain the old Stripe sandbox path unchanged.

| Option | Exact movement and recipient | Decision |
| --- | --- | --- |
| Simulated duel | Record two simulated $20 entries; winner receives a simulated $40 outcome, or both entries return for void/tie; no asset exists | Recommended development/pilot mode; explicitly label no real money |
| Funded duel | Each person pays stake `S` plus separately disclosed fee `F` to an expressly approved provider. After both funding confirmations, result and review, winner receives `2S`; provider routes `2F` to GameTime. Tie/void/cancel returns `S + F` to each; business bears unrecovered processing costs | Preferred product-design hypothesis for real stakes, contingent on a provider/jurisdiction that permits this exact flow; no selected provider |
| Pay loser-to-winner after result | Save an authorized method, later attempt collection from loser and route proceeds to winner | Not recommended for initial funded duels: winner's prize is unfunded and collection can fail; not a workaround for gambling/payment rules |
| Personal prefunded commitment | Person pays `C` to an approved holder with segregated accounting. Success/waiver returns `C`; confirmed miss sends `C` to the named approved beneficiary after review. Any service fee is separately disclosed and versioned | Closest to “money committed now”; holder, beneficiary, fee and legal characterization remain unresolved; not implemented |
| Personal later contingent charge | Save method/explicit consent; on confirmed miss after review, attempt one charge of `C` to the disclosed merchant/recipient. Success/waiver means no charge | Alternative supported by existing sandbox patterns; no locked money or guaranteed collection. A new beneficiary flow needs new approval, not old consent |
| Authorization hold then capture/release | Issuer reserves capacity temporarily; later capture charges it or release/expiry restores availability | Unsuitable default for 28–90-day commitments plus review; no repeated holds to imitate a deposit |
| Immediate unconditional donation | Funds go directly to a beneficiary regardless of result | Different product economics; not the selected meaning of a failure-contingent commitment |

For personal forfeitures, compare an approved beneficiary (recommended research
direction to reduce the incentive for GameTime to declare misses), GameTime as
recipient (direct revenue but conflict of interest), and a named participant
(adds counterparty/prize considerations). No destination is selected. A real
agreement must name the recipient, amount, fee, timing, refund/reversal rules,
and who holds funds before consent. The old charity catalog is not approval
for a new beneficiary flow. No tax-deductibility or escrow claim is permitted
without the matching arrangement.

Recommended monetization tests are a transparent per-person contest/service
fee, and optional club tools sold separately from stakes. Test displayed fee
concepts of $0, $1, and $2 per person for a $20 duel and $5/month club tools;
these are research stimuli, not live prices or a revenue forecast. Avoid a
hidden rake or a business plan dependent on users failing. Participant stakes
are not revenue. Model contribution margin as service fees less processing,
refund losses, chargebacks, verification/support, and any partner/compliance
costs. Enter actual provider quotes only after supportability is established.

Result finality and payment finality must be different ledgers. Future adapters
need immutable agreement bindings, provider events, funding, refunds, payout
attempts, reversals, reconciliation and auditable correction events. Never
infer payment success from an app redirect, a sports result, or a timeout.
Failed payout remains pending/attention, never “paid.” No rollover wallet,
automatic rematch funding, credit, leverage, collection retries, or debt
collection is planned initially.

## Official-source findings and external gates

Checked September 4, 2026. These are published requirements and engineering
implications, not legal advice, account-specific approval, or proof of access.
Stripe CLI was unavailable and its documentation connector did not return
content after two attempts; official web documentation was used instead.

| Source | Finding and implication |
| --- | --- |
| [Garmin Activity API](https://developer.garmin.com/gc-developer-program/activity-api/) | Provides activity details/files after user consent and device sync; evaluation access follows approval. It does not promise fraud-proof performance. Validate edit/import identity and field availability using approved samples |
| [Garmin program FAQ](https://developer.garmin.com/gc-developer-program/program-faq/) | Business-use program, application review and OAuth 2.0. Some metrics can have commercial conditions. Access, pricing and permission for stakes-related processing remain unverified; no credentials or application were created |
| [Garmin intensity minutes](https://www.garmin.com/en-CA/garmin-technology/health-science/intensity-minutes/) and [official manual](https://www8.garmin.com/manuals/webhelp/GUID-4205DB9F-0ACD-4AC2-86A8-957F27150AE4/EN-US/GUID-63522E07-AD5E-4D2D-B680-3129A2300238.html) | Vigorous minutes are weighted twice; do not treat them as elapsed workout minutes or another provider's active minutes |
| [Apple workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration) and [route data](https://developer.apple.com/documentation/healthkit/creating-a-workout-route) | Duration can reflect active time/events; routes require distinct HealthKit permissions. Current step permission and daily totals cannot establish elapsed performance |
| [Stripe prohibited businesses](https://stripe.com/legal/restricted-businesses) | Lists prize-bearing skill competitions, certain prize-linked entry fees and peer-to-peer transmission as prohibited. Treat ordinary Stripe as unsuitable for the proposed duel unless an expressly permitted offering is established; legality alone does not establish supportability |
| [Stripe SetupIntents](https://docs.stripe.com/payments/setup-intents) | Saves a method without charging; later off-session use needs consent and may still require authentication. It does not fund a prize or lock a commitment |
| [Stripe authorizations](https://docs.stripe.com/payments/place-a-hold-on-a-payment-method) | Online card authorizations commonly last 5–7 days depending on network/type, with limited extensions. Use actual capture expiry, not a presumed months-long hold |
| [Stripe manual payouts](https://docs.stripe.com/connect/manual-payouts) | Delaying a connected-account payout is not escrow; Stripe says it does not provide escrow accounts. Connect capability does not grant permission for GameTime's funds flow |
| [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) §§1.2, 1.4.5, 3.1, 5.1.3, 5.3 | Address social moderation, harmful challenges, digital purchases, sensitive health data, and contest/gaming rules. Contests need in-app rules and Apple non-sponsorship disclosure; real-money gaming has licensing/location requirements and cannot fund gaming currency through IAP. Classification of these products and HealthKit-linked consequences needs review |

Before any live work is enabled, the owner and qualified counsel must select a
legal entity, launch country and explicit state/region allowlist, classify
each product separately, and decide age requirements, identity/location checks,
fund custody, consumer terms, taxes/reporting, beneficiary rules, refunds,
injury/disputes, retention, and chargeback liability. Recommended planning scope
is one US jurisdiction with adults only; this is not a conclusion that any US
state allows it. Pilot recruitment may use an 18+ minimum for simulated play;
the real-money minimum could differ. Jurisdiction defaults to **none enabled**.

Obtain written provider support for exact amounts/durations, entry/prize and
forfeiture paths; obtain platform clearance for the actual product and data
use. Payment processors receive payment identifiers and permitted financial
facts, not routes or raw health data. Any digital club subscription needs its
own storefront/payment analysis. Keep all of these outside the critical path
for local simulated development. If no suitable provider or lawful jurisdiction
exists, remain simulated; do not relabel the flow or introduce crypto to bypass
the restriction.

## User-validation pilot

Proposed, not recruited or run: **12 friend pairs (24 adults), six weeks**, plus
**8 voluntary performance commitments** from the same cohort with 28-day goals.
Recruitment should include runners outside the owner's close friends and some
people who decline. No stakes, entry fees, prizes of value, or compensation for
TestFlight access. Schedule at least two eligible events so rematches are
actually possible. Longer 90-day retention needs a later cohort; six weeks
cannot validate it.

Before invitations, Phase 2 must pass local two-actor flows; any hosted pilot
and distribution require a separately approved candidate, privacy disclosures,
consent, support operator and organizer permission. Use an operator workflow
for source review and record its time cost. Limit to one unsettled new duel and
one performance commitment per person; exclude dormant Solo creation. Do not
ask testers to settle off-app.

Record minimal first-party events: invitation created/opened/accepted/declined/
expired, event selected, attempt submitted/reviewed, result opened, dispute,
withdrawal, rematch created/accepted, milestone and subsequent return. Store
opaque IDs, timestamps and policy versions; do not send health results, routes
or financial details to advertising or third-party analytics. Capture event
delivery loss before interpreting funnel percentages.

| Measure | Definition | Proposed decision threshold |
| --- | --- | --- |
| Invitation acceptance | Distinct accepted named invitations / valid delivered invitations, excluding QA; also report created→delivered loss | At least 50%; interview every decline/expiry possible |
| Contest completion | Duels with both verified finishes / accepted duels whose event passed; report one-DNS, void, outage and withdrawal separately | At least 70%; do not count admin closure as athletic completion |
| Credible result | Participants who say result and rule were understood/fair / respondents; record nonrespondents and disputes | At least 80% and no unresolved material privacy or result defect |
| Rematch | Pairs accepting a fresh duel within 14 days of final result / pairs with 14 days observed and an available second event | At least 30%; separately report event availability and initiation vs acceptance |
| Return after loss | Distinct losers taking a meaningful action within seven days / losers with seven days observed | At least 50%; result-only app open is not enough |
| Commitment engagement | Owners recording a milestone or attempt in at least three of four weeks / started 28-day commitments | At least 60%; report completion, withdrawal and missing proof separately |
| Willingness to pay | Post-result choice among realistic disclosed service fee concepts, with a follow-up explanation | At least one-third choose a nonzero fee; stated intent alone cannot validate conversion |
| Operating cost | Reviewer minutes, support touches and dispute time per resolved duel/commitment | Target median ≤10 minutes; measure long tails and model cost against fee hypotheses |

These are predeclared directional thresholds for a small convenience sample,
not statistical proof. Report numerators and denominators and losses to follow-up.
Use interviews to distinguish low interest from organizer friction, unfair
matchups, confusing proof rules, or a simulation that lacks stakes. Compare
deposit versus later-charge explanations and ask users to restate when money
would move and who would receive it. No live payment is needed for that test.

Proceed to a larger simulated cohort if behavior and result credibility meet
the thresholds. Iterate the relevant format if acceptance is strong but event
friction suppresses rematches. Pause expansion for unresolved proof/privacy
defects or harm/coercion; offer immediate withdrawal and support. If willingness
to pay remains weak, revise monetization before funding integration. Actual
paid conversion, behavior under financial loss, and long-term retention require
later separately cleared trials; the pilot cannot establish them.
