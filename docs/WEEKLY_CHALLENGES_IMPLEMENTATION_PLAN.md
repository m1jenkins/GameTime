# Weekly challenges: implementation specification

Planning update: September 6, 2026 UTC, following the owner's September 5
discussion. The owner subsequently authorized all feasible local W1–W4 work.
This specification owns requirements; [local acceptance](WEEKLY_LOCAL_ACCEPTANCE.md)
and [execution status](WEEKLY_EXECUTION.md) own implementation and test evidence.
Neither local fixtures nor passing mocks establish launch acceptance.
Read [project memory](../PROJECT_MEMORY.md), [repository conventions](../AGENTS.md)
and the [main roadmap](../PLAN.md) first.

## Authority and scope

- **Decided:** friend challenges and personal commitments remain the products;
  a fixed 5K is dropped. People may choose supported distances and targets.
  Beta friend challenges support up to five friends; the working interpretation
  is 2–5 participants total, including the creator. Community launch starts
  with one common weekly step target for every participant, interpreted as
  individual completion of the same target rather than a combined team total.
  These interpretations are explicit planning assumptions; the numeric
  community target remains unselected.
  Preserve old agreements, source policies, requests, results and acceptance.
- **Authorized now:** execute feasible local W1–W4 implementation in dependency
  order, with parallel bounded agents, integration and independent review. This
  supersedes the historical W1A-only prompt without waiving acceptance. No hosted
  mutations, recruitment, external messages, notification delivery or money.
- **Recommended build order:** weekly friend steps first, one weekly community
  experiment next, Exercise minutes after source validation, then configurable
  distance goals. These are reversible planning defaults, not claims the owner
  selected every mode or approved public participation or a funds flow.
- **Still open:** community rollout clearance, numeric shared weekly step target, real
  stakes, fees, forfeiture recipient, provider, numerical financial limits and
  jurisdiction. Keep unresolved choices explicit. They do not block fictional
  local rules and consent work.
- Apply [responsible engagement](BUSINESS_MODEL.md#responsible-engagement-and-commercial-incentives)
  throughout: voluntary participation, clear outcomes and exits, private health
  data, no loss-triggered promotion, automatic rematches or stake escalation.

## Existing work: keep, adapt and pause

| Existing work | Treatment for new formats |
| --- | --- |
| Personal daily/weekly steps and local-first refresh | Reuse collection/display patterns and regression coverage. Keep its exact merged nonmanual source policy and seven-day historical agreements unchanged. New competitive reads need a separate source policy and adapter. |
| Identity, friendships, blocks, named invitations and links | Reuse authorization and exact-request patterns. New requests must reference the new product and terms; old links cannot become community enrollment. |
| Consent preview, durable request recovery, result/review/history and safe exits | Reuse tested patterns; adapt participant projections, decisions and deadlines under new versions. Existing tests are not proof of the new contracts. |
| Fictional official-5K duels, chip-time evaluator and pair-only simulated returns | Preserve as historical local functionality. Do not widen validators or reinterpret saved records. Two people and one winner do not implement a community pool. |
| Longer commitment agreements, milestones and selected following | Preserve. Port relevant progress/privacy behavior after the new format exists; the 28–90-day constraint is not a weekly-mode requirement. |
| Unfinished organizer-event nomination/completeness screens | Pause as the default next task. Revisit only if an organizer format is separately chosen; do not complete them merely to reach weekly steps. |
| Consent summaries and dormant push cleanup | Keep the completed responsible-engagement work. New summaries must describe the new policy accurately. |
| Personal Stripe sandbox and other legacy money paths | Preserve without extension. No new deposits, participant payouts or community money exist. |

Use separate versioned weekly agreements and participation records, with names
chosen during W1B, rather than adding new meanings to old duel, Personal, Solo
or charity records. A community aggregate is a later addition. Extract shared
helpers where behavior actually matches; do not build an arbitrary rules DSL.

## W1 — weekly steps with friends

**Recommended first mode:** each participant in a group of 2–5 meets their own agreed
cumulative step target. All may succeed. The beta capacity is interpreted as
five total, including the creator; individual friend targets remain a proposed default. Most steps, fastest finish and daily
streaks are different rules and are excluded from this slice.

### Proposed rule contract

| Rule | Local development default |
| --- | --- |
| Window | Seven consecutive calendar dates, Monday 00:00 through the following Monday 00:00, in one creator-selected IANA timezone frozen for all participants. Creation chooses a future week; no retroactive steps. Travel does not move the window. |
| Roster | Freeze 2–5 distinct participants, including the creator, before consent. Each invitee must be an accepted friend of the creator; joining grants no access beyond this challenge. No silent roster changes or post-start additions. An incomplete roster at cutoff does not start; revising it requires fresh consent. These are proposed group-consent defaults. |
| Consent | All participants explicitly accept the same version, source, dates, targets, simulated amounts and outcome rules before the start. The creator sets a proposed positive whole-step target for each person; editing any target or the roster requires a new agreement/consent. |
| Target | Cumulative eligible steps greater than or equal to that person's target. Different targets are allowed with every participant’s consent. No forced daily activity or penalty for rest days. |
| Source in W1A | Fictional, complete or explicitly incomplete daily snapshots, labeled `fixture_weekly_steps_v1`. No claim of Apple verification. |
| Proposed actual source | Eligible Apple iPhone/Watch step records, with explicit manual exclusion and source/deduplication checks. The source policy remains unavailable until W1B device research establishes what can actually be measured. Never silently fall back to all Health writers. |
| Observation | Distinguish zero steps in a usable observation from absent data, revoked permission, incomplete capture or a failed query. Permission completion and a successful empty query alone do not establish complete capture. |
| Corrections | Append revisions; refreshed totals may decrease. No permanent win from an early preview or immutable result before the agreed observation/review process finishes. |
| Simulation | Nonredeemable 2,000 example cents per person, zero fee, no provider or actual asset. These are fixture values, not proposed live pricing. |
| Review | W1B must freeze explicit upload, correction, notice, filing, resolution and finality deadlines in the new policy. Select and test them as weekly rules; do not inherit organizer timelines automatically or truncate review to open the next week. |

DST can make these seven dates contain 167 or 169 hours. Freeze exact start/end
instants and day boundaries along with the timezone. Retain the timestamp
precision used by existing agreement boundaries. Exact cutoff equality is
tested explicitly, not handled by rounding.

Proposed simulation outcomes after the applicable result/review process:

| Final facts | Simulated allocation |
| --- | --- |
| All meet their targets | Return each person's own 2,000 example cents; no bonus. |
| Some meet targets and the rest have confirmed misses | Each qualifier recovers their entry plus an equal share of confirmed forfeitures. Keep integer remainders explicitly unallocated. |
| All have confirmed misses | Record forfeitures as unallocated simulation; no named recipient, company income or transfer. |
| Any participant remains unresolved at cutoff | Proposed conservative friend-group default: void the group and return all simulated entries; lack of data alone cannot create a miss. |
| Incomplete acceptance at cutoff, pre-start cancellation, simulated withdrawal or injury exit | Proposed default: void the group with no simulated loss; retain reasons and agreements. Funded exit rules need separate selection and consent. |

Blocking ends social access, not historical ownership or permission to change
results. Define deletion and safe closure consistently with the new simulated
exit rules while preserving needed receipts. Do not make a friend confirm
someone else's failure or treat a private report as proof.

### W1A — next implementation task: pure rules and fixtures

Deliver a new weekly-steps policy/terms model and pure qualification evaluator
with no I/O or ambient clock. Use the existing pure-evaluator testing approach,
without changing or calling the old official-5K scoring policy. Inputs bind 2–5
distinct participants, their explicit consents, individual targets, frozen
calendar window, ordered daily revisions, observation status and injected time.
Validate policy/source/version bindings, units, positive bounded integer targets,
nonnegative safe integer observations, duplicate/out-of-window dates, changed
consents and invalid snapshots. Pick and document fixture validation bounds;
they must not be represented as recommended health targets.

Return individual pending/met/confirmed-miss/unresolved qualification and the
derived group outcome. These are evaluator decisions, not published final
results or ledger writes. The fixture completeness assertion is authoritative
only inside tests; a future client cannot grant itself that authority. Do not
implement money allocation, notices, reviews or finality persistence in W1A.

**Acceptance:** group sizes 2, 3, 4 and 5; reject fewer than two or more than five,
duplicate participants, changed rosters and missing consents; unequal targets,
all met, each possible sole success, multiple successes and all missed, incomplete/missing/zero observations, upward/downward revisions, revoked
source, clock/cutoff equality, DST, travel, stale/wrong consent, invalid input
and deterministic replay. No result is final before the window/review process.
Existing official-5K and Personal tests remain unchanged and pass relevant
regressions. Exit with a dated acceptance record and the W1B handoff.

### W1B — source feasibility, agreements and local lifecycle

Split this work into reviewable deliveries; validate the source before coupling
new agreement/scoring code to assumed Health fields.

1. Prototype a dedicated step-source adapter and record on physical iPhone/
   Watch: source identity, explicit manual entries, third-party imports, merged
   overlaps, duplicate reimports, deletion/downward edits, late Watch sync,
   locked/offline states, permission revocation and timezone changes. Reuse
   Personal refresh primitives without changing its query or source meaning.
   Describe what supports a confirmed miss and what remains unknowable. If the
   source cannot support the policy, stay fictional and revise the proposal.
2. Add new default-off local agreement/admission, participant, exact-request,
   observation, result/review and simulated-allocation boundaries. Bind uploads
   to active actors and accepted terms; server validation cannot rely on a
   client-provided `complete` or `verified` flag. No base-table client writes.
   Keep observed progress separate from qualifying and final results.
3. Freeze the weekly deadlines, source version, safe exits and retention rules.
   Add clock-injected activation, correction/review handling, immutable finals
   and separately appended simulation. Preserve access/recovery after admission
   closes. Keep notices durable in-app; no scheduled hosted runner or APNs.
4. Separate participation conflicts from pending finalization. Proposed policy:
   one weekly steps enrollment per actor for overlapping activity windows,
   across friend/community modes; a future nonoverlapping week can be joined
   while the prior result is under review. Select bounded pending-enrollment
   limits and test them; do not release old product slots or permit unlimited
   financial exposure. Future financial limits count all unsettled amounts.

**Acceptance:** authenticated 2–5-participant privacy, changed-payload/exact retries,
concurrent accepts at capacity, roster/consent changes, accept/cancel/block/delete races, observations versus finalization, complete
correction/review windows, simulation conservation and no double allocation.
Prove week two can be accepted while week one is in review; pausing new entry
still permits existing reviews/exits. Run focused database/concurrency checks
in a disposable stack and the applicable portable regression gate. Real-source
device evidence and fictional database evidence must be reported separately.

### W1C — native friend challenge and progress

Add opt-in local weekly creation, target review, named invitation/acceptance,
progress, freshness, result/review, safe exits and explicit next-week creation.
Use distinct durable requests and typed models. Reuse consent summaries and
account-clearing patterns, not old fixed-5K decoding. Show which totals qualify
and why a refresh may change progress without exposing raw source records.

Sharing is explicit and target-bound. No automatic public result, loss prompt,
daily exercise streak, automatic renewal or pre-funded rematch. Milestones and
selected following can follow the new progress flow; implementing the full
old organizer catalog or long-goal UI is not a prerequisite.

**Acceptance:** full native-to-local flows at two and five participants, roster/capacity enforcement, invitation decline,
changed consent, response-loss recovery, account switching, blocked contacts,
late responses, background refresh, review after a new week joins, and default
Personal/Release isolation. Add comprehension and accessibility/device checks;
record unrun VoiceOver or device checks without claiming acceptance.

## W2 — one weekly community experiment

**Owner-selected launch format; rollout remains separately gated.** One common
weekly step target applies to every entrant. Working interpretation: each
person reaches that same number individually; steps are not summed into a
collective goal. The numeric target remains open. Depends on W1's tested
step source, qualification, lifecycle and native flow. Start with one officially
configured future cohort; no participant-created public marketplace or random
opponent matching. Proposed trial zone: America/Chicago, with the same exact
window for everyone and clear local-time display. Each week is a fresh opt-in.

### W2A — rules, enrollment and simulation

- Define server-owned cohort creation, join cutoff, one enrollment per person,
  bounded capacity, minimum two participants, cancellation/refund when minimum
  is missed, and immutable rules. Creation can be manual and local initially.
  Own history survives joining closure; authentication and current admission
  are required for every new join. Friend participation within the cohort is
  a view of the same enrollment, not a second entry or stake.
- Choose and publish one positive whole-step weekly target for the cohort before
  enrollment. Freeze that number, source, dates and timezone in every consent.
  No personalized baseline formula or participant-selected community targets.
  Validate suitability and comprehension during the pilot; changes apply only
  to a future cohort. Private friends may continue accepting custom targets.
- Add multi-person qualification and allocation records; do not expand the
  old exactly-two-runner validator or reuse charity settlement. Each person
  qualifies against the same published weekly target; exceeding it earns no larger share.
- Freeze a minimal community projection: counts and own progress; friend
  progress only under explicit sharing authorization. Joining does not expose
  strangers' goals, raw health, routes, forfeitures or a financial leaderboard.
  Enforce blocks, revocation, reports/support and deletion at read time.

Proposed zero-fee simulation: each successful entrant recovers their entry and
an equal share of confirmed forfeitures. Resolve/refund uncertain or safely
withdrawn entrants before computing the distributable pool. If all succeed,
return their entries with zero bonus. If none qualify, record unallocated
simulated forfeitures without a payee. Integer division remainder stays a
separately recorded unallocated simulated amount; do not reward earlier joins
or randomly select financial bonuses. Real no-winner/remainder recipients and
fee rules require selection before any funded policy.

**Acceptance:** zero/one/many entrants; duplicate and simultaneous joins;
minimum/capacity/cutoff equality; identical target in every consent, reject
per-person overrides and post-join target changes; all/none/some qualify; missing data, withdrawal,
deletion and late corrections; no divide-by-zero; deterministic integer
allocation and conservation of entries = returns + bonuses + unallocated
simulation. Publish allocation only against a stable resolved cohort snapshot;
retries cannot pay twice. Test private/cohort overlapping windows and week-two
admission while week-one review remains open. No pooled real money.

### W2B — native community join and descriptive pilot

Add one discoverable cohort, rules/target preview, explicit join, own progress,
consented friend context, results/review and optional next-week entry. It must
be usable by a person with no friends in GameTime. Show stakes returned and
possible bonus separately; never equate the entire pot with personal earnings.
Build participant UX and support/privacy flows before pilot distribution.

Use [the revised pilot](BUSINESS_MODEL.md#user-validation-pilot): 20–30 adults,
two consecutive seven-day rounds, simulated only. Include solo joiners and
existing friend groups. Observe voluntary week-two participation without
loss-triggered outreach, goal fairness, comprehension, pressure, source failures
and review workload. Small-sample results are descriptive. Recruitment,
hosting/distribution and notifications retain their separate approval gates.
If community work is deferred, use the same two-round study structure with
private W1 groups of 2–5 after that format's acceptance and distribution gates.
Report it as friend-only evidence; W2 is not required to validate W1.

## W3 — Apple Watch Exercise minutes

Add a separate source and policy using Exercise minutes, with cumulative weekly
targets first. Do not substitute workout duration, calories, ring percentage
or Garmin weighted intensity minutes. A ring total can include manually added
workouts. Inspect eligible underlying records and test whether source/manual
metadata survives generated Exercise-time samples before promising sensor proof.

Deliver a device feasibility report, dedicated read permissions/adapter,
deduplicated observations and new rule fixtures before adding a selectable
metric to friend/community screens. If valid filtering cannot distinguish
manual/imported credit, keep the mode unavailable or propose a separately named
sensor-workout policy; never silently change what Exercise minutes means.
Weekly consistency and workout-frequency variants are later optional policies,
not necessary for this slice. Do not force consecutive-day exercise.

**Acceptance:** manual Health workouts, imported iOS workouts, approved Watch
sessions, overlaps, deletion, late sync, permission/source loss, unit precision
and below/exactly/above-target boundaries. Repeat W1/W2 lifecycle and privacy
tests for the new metric without changing historical steps agreements.

## W4 — participant-selected distance goals and longer commitments

Keep two distinct formats: accumulated qualifying running distance in a window,
and a single qualifying run over a chosen distance under a chosen elapsed time.
Choose the first based on source feasibility; timed performance is not required
to launch cumulative distance. Use configurable supported values and explicit
unit conversions, not a mandatory 5K or organizer event. Distance, comparator,
window, activity type and source are frozen before acceptance.

For timed goals, define full elapsed time/pauses, route accuracy, short-distance
tolerances, segment extraction and edits/deletions. A sum of daily distance
cannot prove a timed attempt. Preserve the distinction between 1,600 m and
1,609.344 m and strict versus inclusive time comparisons. No conversion of
earlier official-5K requests, terms or results. Garmin remains a possible later
source, not a prerequisite for Apple-based development.

Build the new agreement/proof/evaluator/native contracts, then adapt longer
goal attempts, private milestones and selected following where useful. Manual
check-ins never determine qualification. Preserve longer durations without
making the current fixture's 28–90 days a universal restriction. Require device
field tests and separate proof-of-miss handling before a new source is admitted.

## Cross-cutting delivery and money gates

- Complete explicit preferences, category consent, quiet hours, caps, server
  suppression/deduplication and authenticated routing before external reminders.
  Push remains off until that full flow exists. Durable in-app notices remain
  available without optional reminders.
- Implement privacy-minimized pilot measurement and working review/exit/support
  controls before recruitment. Goal comprehension and trust constrain voluntary
  return; paid frequency and return after loss are not growth targets.
- All new weekly/community development uses simulation. Provider choice,
  deposit versus later charge, fee, recipient, refund/cash-out costs and limits
  remain unresolved. StepBet/WayBetter are comparison material, not permission
  to use their money structures or revenue assumptions.
- [Phase 6](../PLAN.md#phase-6--payment-feasibility-then-separately-gated-implementation)
  still governs real funds. Server exposure/rolling commitment limits and pause
  must span private challenges, communities and personal goals, including prior
  weeks awaiting settlement. A new weekly join cannot evade a limit via a
  different product, invitation, rematch or pending result.

## Research basis and limits

Primary sources reviewed during the September 5–6 discussion inform proposals,
not source acceptance or provider clearance:

| Source | Planning implication |
| --- | --- |
| [Apple step counts](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount) | iPhone and Watch can record steps. A sensor-capable data type does not establish complete capture or a competitive source policy. |
| [Apple Exercise time](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/appleexercisetime) and [manual workouts](https://support.apple.com/en-la/101952) | Exercise time differs from workout duration; manually added workouts can increase ring credit. W3 must test underlying provenance. |
| [Apple workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration) and [workout routes](https://developer.apple.com/documentation/healthkit/hkworkoutroute) | Workout duration and route records require explicit interpretation; W4 cannot derive a timed run from daily totals. |
| [StepBet FAQ](https://www.stepbet.com/faq) | Personalized historical-data goals and shared completion pools are precedents. Most games last six weeks, so GameTime's weekly duration is an experiment. |
| [WayBetter commitments](https://support.waybetter.app/hc/en-us/articles/12298730134419-What-are-Financial-Commitments-and-how-do-they-work) | Traditional pooled winnings are funded by nonqualifying participants; returning principal is not profit. Membership, game exceptions and costs prevent assuming universal economics. |

## Current next-build prompt

Use the [local acceptance record](WEEKLY_LOCAL_ACCEPTANCE.md) for remaining work
and precise missing evidence. The owner expanded execution beyond the prompt
below; it is retained only as the historical W1A scope. Do not restart completed
W1A or reinterpret its restrictions as a limit on the authorized local roadmap.

### Historical W1A prompt — superseded execution scope

```text
Work in /Users/user/Documents/GitHub/GameTime.

Implement only docs/WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md W1A: the local
fictional weekly-steps policy, pure qualification evaluator and fixture tests.
Read AGENTS.md, PROJECT_MEMORY.md, PLAN.md, the weekly specification,
DECISIONS.md D130/D131/D132 and docs/BUSINESS_MODEL.md. Inspect git status and preserve
unrelated work, including the responsible-engagement changes.

Use cumulative individual step targets for 2–5 explicitly consenting participants
(including the creator) over seven frozen calendar dates in one timezone.
All may meet their targets. Validate the frozen roster, capacity and every consent.
Bind the exact policy/source, participants, targets, dates and consents; preserve
pending versus met, confirmed miss and unresolved data. Fixture completeness is
not a client trust mechanism. Distinguish zero from missing, allow downward
corrections before finality, and validate calendar/cutoff and integer boundaries.

Keep the module pure and separate from old fixed-5K and Personal evaluation.
Use an injected clock and documented fictional snapshots. Add the W1A fixture
matrix and a dated acceptance record with an actionable W1B handoff. Run the
relevant evaluator/regression, format and type checks; report unrun checks.

Do not add database migrations, native screens, Health permissions, source
ingestion, published results, allocation ledgers, payment adapters, schedules,
hosted mutations or live money. Do not alter old policies, consent, requests,
scorers, final results or acceptance history. Do not resume the organizer-event
nomination task. Finish with the implemented scope, verification and remaining
source/contract/lifecycle work; this slice does not create a playable mode.
```
