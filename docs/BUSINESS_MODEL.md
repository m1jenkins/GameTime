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
agreements, nominated attempts and private manual progress. Phase 3(d) adds the
[local following and report/support backend](PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md).
Phase 3(e) adds the [local result/review lifecycle and separate simulation](PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md).
The [first native commitment slice](PERFORMANCE_COMMITMENT_NATIVE_V1_ACCEPTANCE.md)
adds local agreement and result/review history. Native attempts, progress,
following and hosted operations remain open; organizer-event entry is paused
as the default next task under the weekly-first roadmap.
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
| Adopted | Friend challenges and personal commitments, athletic focus, no mandatory fixed 5K, participant-selected supported distances/targets, stakes in design scope and responsible engagement; no spectator betting or public prediction exchange |
| Implemented | The existing Personal seven-day Apple Health steps app, internal test-only and Stripe sandbox paths, dormant historical systems below, the isolated local Phase 1A simulated duel agreement backend with an opt-in Phase 1B native fixture/local flow, Phase 2(a)'s pure fictional-result evaluator, Phase 2(b)'s private fictional proof/operator boundary, Phases 2(c–e)'s local lifecycle/native results/rematches/links, and Phase 3(a–e)'s separate commitment agreements/attempts/manual progress/following/result-review backend |
| Adopted beta/launch scope | Up to five friends; one common weekly community step goal. Working interpretations: five participants total and individual completion of the same target (D132) |
| Recommended | Weekly friend steps first, one community experiment, then Exercise minutes and configurable distance; all timing, target, simulation and pilot defaults are reversible |
| Unresolved | Community rollout clearance and numeric common weekly step target, demand, source validation, provider access, money structure, forfeiture/remainder recipients, fees, limits, jurisdictions and launch clearance |

## Current format authority

The owner dropped a mandatory fixed-5K format on September 5 and requested this
implementation-plan reconciliation. Friend challenges and personal commitments
remain adopted. People may choose supported distances/targets. The recommended
next build is cumulative weekly steps with friends; one official weekly
community experiment follows, then Exercise minutes and configurable-distance
policies. This is a planning sequence, not confirmation that every proposed
mode or payment arrangement has been selected. D132 selects the community
launch format as one common weekly step goal; rollout clearance remains separate.

The existing fictional official-5K implementation and immutable agreements
remain historical local functionality. New formats need separate versions,
requests and source/review rules. Read [the weekly implementation specification](WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md)
for W1–W4, the reuse/pause inventory, acceptance and current W1A build prompt.
D130 responsible-engagement requirements remain in force alongside D131 and D132.

## Audience, positioning, and engagement

The audience hypothesis remains active adults who enjoy commitments and friendly
competition. The weekly-steps proposal broadens the first experience beyond
runners entering organized races. Interest in Kalshi or Polymarket does not
establish demand for GameTime, and no retention or revenue outcome is proven.

The first job is to turn an agreed weekly target into clear participation,
credible progress and an understandable result. A friend can accept a different
target before the start; everyone in the group may succeed. Most steps or fastest performance
is a distinct head-to-head rule, not the default meaning of keeping a promise.

The proposed weekly flow is invitation or community discovery → rule/target
review → explicit acceptance → chosen activity and progress → result/review →
optional next week. Community participation offers a way to begin without an
existing friend in the app; whether that improves voluntary return is a pilot
question. Start with one official cohort if that experiment proceeds. Defer a
public creator marketplace, random opponent matching and financial leaderboards.

Longer commitments retain goal → selected milestone → qualifying attempt →
result/review. They remain useful without a universal 5K or mandatory 28–90-day
window. Native milestones and following should serve the selected new format;
finishing the historical organizer catalog is not a prerequisite for weekly play.
The existing native duel/rematch flow and commitment agreement/result screens
remain local simulations, not these new experiences.

Retain Today, Challenges, and You as a starting navigation structure. Add typed
new destinations while preserving Personal. Invitations and next-week joins
require fresh consent; public enrollment must not silently create friendships,
second stakes or visibility into health data. Share selected friend progress
only with current permission. Result sharing needs separate explicit consent.
No strangers' health totals, routes, private notes or financial losses should
appear because they joined the same cohort. Free-form chat, public feeds and
automatic contact imports remain deferred. Privacy, blocks, reports/support,
account clearing and safe exits are part of the first usable community flow.

## First sport, format, and proof recommendation

**Recommended sequence:** cumulative weekly steps with friends; a single weekly
community experiment; Apple Watch Exercise minutes; configurable cumulative or
timed distance goals. This reuses the working Personal steps foundation and
social/consent patterns while avoiding an organized-event dependency. It does
not turn historical Personal snapshots into competitive proof automatically.

W1 starts with a fictional, pure weekly-steps evaluator, then a separate step
source investigation and new local agreement/lifecycle. The beta supports up to five friends, interpreted as 2–5 total participants
including the creator. Everyone consents to the frozen roster, each person’s
target and the same seven calendar dates/timezone before starting. No forced
daily streak. The owner selected one common weekly step goal for community
launch: the working interpretation is that each entrant individually meets
the same published target, rather than contributing to a combined total.
The numeric target remains open; personalized community goals are out of
initial scope. See D132 for decisions versus working interpretations.

The current step reader merges Health writers and excludes only explicitly
manual records. New competitive rules must separately validate accepted source
identity, overlaps, duplicates, manual/imported activity, corrections and late
sync on devices. A successful empty query or a completed permission prompt does
not establish complete observation. Missing data cannot by itself cause a loss.

Exercise minutes need their own permissions and source adapter. Apple lets
manual workouts update the Exercise ring, so a ring total alone is insufficient
for the proposed source policy. Do not equate Exercise minutes with workout
elapsed time, calories or Garmin weighted intensity minutes. Whether generated
minute samples preserve enough provenance is an explicit device-test question.

For distance goals, distinguish accumulated qualifying distance in a window from
one qualifying performance over a chosen distance under a chosen time. Preserve
exact units: a true mile is 1,609.344 metres; 1,600 m is different. Freeze source,
units, precision, activity type, comparator, window, corrections, missingness,
rest/injury and review rules before consent. Selectable distance requires new
proof/validation, not relabeling the existing fixed-5K fixture.

Apple Watch workouts and Garmin activities are candidate performance sources;
Garmin access is not a dependency for weekly steps. Organizer results remain an
optional later format with source permission and review, not the launch path.
No provider is selected and the human pilot requires actual source acceptance.

## Proposed weekly and community money mechanics

These are **simulation defaults and commercial hypotheses**, not approved real
money. The W1 fixture uses 2,000 nonredeemable example cents each and zero fee.
For the proposed 2–5-person friend simulation, all qualify → return all entries;
some qualify → return qualifiers’ entries plus equal shares of confirmed
forfeitures. All confirmed misses and integer division remainders stay
unallocated, with no company revenue or named payee. The proposed conservative
friend-group default voids the whole group and returns entries if any proof
remains unresolved or a simulated safe exit occurs. These expanded allocation
and exit rules are recommendations, not owner-selected money terms.
Old 5K outcomes keep their own rules.

For a proposed community pool, each qualifier recovers their entry and an equal
share of confirmed forfeitures. Resolve/refund unknown or safely withdrawn
participants before allocation. All qualify → no bonus; none qualify → no
winner allocation and no divide-by-zero. Keep integer remainders and zero-winner
forfeitures explicitly unallocated in simulation. Selecting a real recipient,
fees and refund rules is separate work; the earlier beneficiary suggestion has
not been adopted. See [W2 acceptance](WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md#w2a--rules-enrollment-and-simulation).

Receiving an entry back is not profit, and the total pot is not one person's
prize. For example, ten simulated entries of 2,000 cents and eight qualifiers
produce 2,500 cents returned per qualifier: 2,000 original plus 500 bonus before
any separate costs. This is arithmetic, not a forecast. New weeks require new
consent and cannot automatically roll over funds or increase amounts.

StepBet/WayBetter demonstrate pooled-completion mechanics; their rules are
comparison material, not GameTime's approved economics or evidence of demand.
Company revenue research remains separately disclosed service fees and optional
club tools. Do not rely on participant failure or confuse contributed stakes
with revenue. A solo success ordinarily returns its commitment; an extra reward
needs an explicitly funded source.

## Proposed duel agreement and lifecycle

The following describes the implemented fictional official-5K simulation. It
is a lifecycle reference for future formats, not a mandatory future race format.
It does not amend Personal cancellation, Solo appeals, or charity obligations.

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

The exact deadlines and organizer-attempt mechanics below describe the existing
local longer-goal policy. W4 chooses new configurable-distance rules; W1/W2 do
not inherit these deadlines or require this format.

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

For the historical organizer format, use one official result per runner and event. Record
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
  tests. Do not quietly round a short activity up to the agreed distance or extrapolate a mile.
- Full elapsed time including pauses. `end - start` is the initial time basis;
  do not substitute moving time, active duration, best pace, or aggregate
  exercise minutes. Extracting an exact chosen-distance segment of a longer run needs a
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

For the current completed-work inventory and weekly changes, use
[keep, adapt and pause](WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md#existing-work-keep-adapt-and-pause).
The historical table below must not be read as a current claim that invitations,
results or following backends have never been implemented.

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

## Responsible engagement and commercial incentives

Adopted in response to the owner's supplied report, *Engagement, Compulsion,
and Responsible iOS Design in Contract-Trading Apps*, September 6, 2026. Apply
its autonomy and incentive principles to athletic commitments; do not import
prediction-market regulation or treat the report as GameTime legal clearance.
These product requirements govern new work. The exact prices, numerical limits,
notification caps and launch metric remain proposals until validated.

**Product objective:** people understand an agreement, voluntarily pursue an
athletic goal, receive an understandable and fair result, and can leave or
choose another challenge. Measure meaningful progress and voluntary retention
alongside trust and reported pressure. App opens, time in app, notification
clicks, committed dollars and paid-challenge frequency are diagnostics, never
standalone success criteria. A missed goal must not initiate growth targeting.

- Lead the future home experience with goals, selected milestones, attempts,
  update freshness and explicitly followed friends. Keep amounts accessible
  and prominent at consent and financial outcomes; do not hide maximum loss.
- Celebrate athletic achievements, with the same treatment across amounts.
  No financial confetti, stake-size badges, paid-challenge streaks, randomized
  financial rewards, escalating defaults or loss-recovery prompts. Rest must
  not break an app reward streak; never prescribe last-minute exercise to
  protect a stake. An unverified check-in cannot earn a verified-result badge.
- Keep friend invitations private and deliberate, with fresh consent for every
  rematch. No automatic sends, repeated prompting after decline, money-won
  leaderboards, public humiliation or inferred result-sharing consent. No
  interface can accept, fund or increase an obligation from a notification.
- At review show the goal, dates/zone, accepted source, exact amount and fees,
  win/miss/tie/uncertain outcomes, recipient where selected, and exit/review
  rules. Keep full unchanged terms reachable. Simplifying text placement
  never weakens consent or rewrites an existing agreement.
- New-money participation needs server-enforced outstanding-exposure and
  rolling new-commitment limits across products, plus a person-controlled pause
  on new money challenges. Limits cover invitations, community joins, acceptance
  and rematches, including prior weeks awaiting finality,
  with concurrent requests and exact recovery tested. Decreases/pause take
  effect immediately for new admission; increases require deliberate consent
  and a defined delay. Existing history, exits, disputes, support and applicable
  refund/payout access remain usable. A pause does not cancel an agreement or
  promise forgiveness. Numerical caps and delay require selection before cash.
- Revenue hypotheses remain transparent service fees and optional club tools.
  Do not optimize for participant failure, amount escalation or rapid repeat
  commitments. Do not paywall risk controls, review, records, support, exits or
  money access. No activity-linked referral/deposit incentives are planned.
  Recipient selection remains open; a beneficiary reduces one direct conflict
  but does not itself establish provider or legal permission.

### Notification and privacy requirements

External push remains disabled today. The local following backend's personal
pull-based reminders are not APNs delivery or a notification-preference system.
Before enabling push, implement contextual consent, per-category preferences,
quiet hours, caps, current server authorization, opt-out and delivery checks
as one usable flow. No inert settings may imply these protections already work.

Separate invitations, requested goal reminders, selected friend updates,
results/review and account security. Optional categories start off. Ask for OS
permission after the person requests a useful alert, never on app launch;
respect refusal. Proposed optional reminder limits are one per day, three per
week, and quiet hours 21:00–09:00 in the person's selected zone. These are trial
ceilings, not delivery targets. Coalesce/deduplicate events, suppress obsolete
and blocked/revoked content, and give every category a reason and an easy mute.
Security and time-sensitive result/review notices require their own policy;
never silently apply optional-marketing caps to critical notices or promise
real-time delivery. Durable in-app notices remain the authoritative record.

Keep push payloads free of goals, health values, amounts and private friend
content. Resolve an opaque destination only after authentication and current
permission checks. Badge counts represent unread actionable updates, not
activity or popularity. Server events drive result alerts; background refresh
and APNs delivery are not clocks for changing terms or deadlines.

Use a first-party, allowlisted event schema; log intent, exposure and outcome
separately, with stable experiment assignment and deduplication. Do not send
raw health values/routes, private notes, names, dispute text, tokens or exact
financial amounts to growth analytics. No session replay or automatic screen/
network capture in sensitive flows. Restrict precise financial records to
operations and safety; a safety suppression signal cannot become a revenue
segment. Never use fitness data or missed goals to target higher-stake offers.

Apple recommends requesting notification permission in context
([permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)).
Apple restricts advertising/marketing uses of health and fitness data
([health-data guidance](https://developer.apple.com/health-fitness/)). These primary
sources were checked September 6, 2026. The supplied report's company-specific
and regulatory claims have not been independently re-audited for this change.

### Pilot and experiment guardrails

For the small initial cohort, use comprehension sessions and descriptive
results; do not claim a powered A/B result. Ask people to restate the goal,
amount at risk, recipient, source, review and exit consequences. Track reports
of pressure to accept, increase stakes or exercise while injured, unwanted
notifications, privacy incidents, unresolved disputes and difficulty leaving.
A person using a limit, withdrawing or muting is exercising a control, not a
failed conversion. Do not turn these choices into growth targeting.

For later experiments, predeclare the hypothesis, assignment, exposure event,
primary comprehension/task outcome, observation window, sample-size rationale
and safety stopping rule. Start with review comprehension and requested-reminder
usefulness. Record denominators, opt-outs and missing telemetry. Pause an
experiment for a credible coercion/injury-pressure report, privacy breach or
broken exit/review control; investigate before resuming. Increased clicks or
rematches cannot override a worsening guardrail. Track rapid stake increases
or new commitments after losses defensively if live money is later approved;
a simulated pilot cannot establish financial safety.

## Payment-model decisions and options

**Now:** new development and pilot use nonredeemable simulation only, no card,
no cash-equivalent prize, no outside collection, no payment provider calls.
Use a displayed $20 example per person and fee $0; these are test labels, not
approved prices or live limits. Retain the old Stripe sandbox path unchanged.

| Option | Exact movement and recipient | Decision |
| --- | --- | --- |
| Historical simulated race duel | Record two simulated $20 entries; winner receives a simulated $40 outcome, or both entries return for void/tie; no asset exists | Implemented local fixture; preserve its terms |
| Proposed weekly friend/community simulation | Record nonredeemable entries, qualification, returns, bonuses and unallocated remainder/forfeitures separately | W1/W2 planned work; no assets, fees or recipient selected |
| Funded head-to-head duel | Each person pays stake `S` plus separately disclosed fee `F` to an expressly approved provider. After both funding confirmations, result and review, winner receives `2S`; provider routes `2F` to GameTime. Tie/void/cancel returns `S + F` to each; business bears unrecovered processing costs | Preferred product-design hypothesis for real stakes, contingent on a provider/jurisdiction that permits this exact flow; no selected provider |
| Funded target-based friend/community pool | An expressly supported holder collects entries and disclosed fees; after final qualification/review, return successful principals and distribute confirmed forfeitures under frozen rules, including refunds, no-winner and rounding recipients | Research only; not implemented or approved by the duel simulation or another app's practices |
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

**Revised proposal, not recruited or run:** 20–30 adults over two consecutive
seven-day rounds, with one official community cohort. Include solo joiners and
existing friend groups of 2–5. Use nonredeemable simulation only: no real stakes, fees,
prizes of value, outside collection or compensation for TestFlight access.
This replaces the earlier six-week/12-pair/8-commitment pilot as the recommended
first study. Longer goal formats need later observation matching their duration.
If the community experiment is deferred, the two-round study can instead use
private W1 friend groups of 2–5 after their source/native/support acceptance. It then
provides no evidence for solo community entry, public fairness or pooled groups.
Community implementation is not a prerequisite for validating private challenges.

Before invitations, W1 source/device and two-account native acceptance and W2
community rules, enrollment, allocation, privacy and support must pass. A local
friend flow alone cannot establish community readiness. A hosted/distributed
pilot still needs an approved candidate, privacy disclosures, consent and
working review/exit/support. No organizer is required for steps. Disable dormant
Solo creation and preserve existing records. Weekly enrollment must permit
round two while round one is under review without bypassing exposure limits or
shortening review. Next-week entry always requires fresh consent.

Use minimal allowlisted first-party events: rule preview/consent, invitation
created/opened/accepted/declined/expired, cohort join, progress refresh status,
result viewed, review/withdrawal, optional next-week entry and explicit sharing.
Distinguish intent, exposure and outcome. Store opaque IDs, timestamps and policy
versions with deduplication; omit health values, routes, private notes, exact
amounts and loss-based growth segments. Report delivery loss and opt-outs before
interpreting percentages. Follow the engagement guardrails above.

| Measure | Definition and interpretation |
| --- | --- |
| Agreement comprehension | People accurately restating target, accepted source, dates, simulation, possible outcomes and exit/review / people assessed. Resolve material misunderstandings before participation; report initial and assisted understanding. |
| Individual completion | Qualifiers / accepted participants whose activity window ended. Separately report confirmed misses, unknown data, safe exits, outages and withdrawals; administrative closure is not athletic completion. |
| Goal fairness and result clarity | Respondents who understood and considered their target/result fair / respondents, with nonrespondents reported. Ask whether the common community target and agreed friend targets felt achievable and fair, without presenting them as medical advice. |
| Voluntary week-two participation | People choosing round two / round-one participants offered a valid second round. Report timing and missing follow-up; no automatic enrollment, loss-targeted outreach or return-after-loss target. |
| Friend invitation | Distinct voluntary senders and accepted invitations, with valid delivered invitations as the acceptance denominator. Separate joining alone from joining with friends; record decline without repeated prompts. |
| Source and operating burden | Failed/incomplete updates, corrections, disputed results and reviewer/support time per participant/result; investigate long tails and any incorrect forfeiture. |
| Pressure, privacy and exits | Reports of exercise/financial/social pressure, unwanted contact, data exposure and difficulty leaving or reviewing. Any credible material defect blocks expansion pending investigation. |
| Motivation and pricing | Ask whether progress, friends, the community or possible rewards motivated return. Test disclosed service-fee concepts separately; stated willingness is not paid conversion. |

This is descriptive usability/demand research, not a powered A/B test. Report
counts/denominators and interview explanations; the sample cannot establish
financial safety, typical winnings, long-term retention or superiority of weekly
versus longer games. Do not select a success threshold after seeing results.
Before recruitment, predeclare any directional return/fairness thresholds and
stopping rules with the actual cohort; no outcome is guaranteed by this plan.

Proceed to a larger simulated cohort only after comprehension, source/results,
privacy and working exits/reviews pass and voluntary participation supports
another test. Iterate confusing goals or poor source coverage. Pause for material
privacy, coercion/injury-pressure or unresolved result defects. No increase in
engagement overrides those guardrails. Actual money and long-term commitment
validation remain separately cleared later studies.
