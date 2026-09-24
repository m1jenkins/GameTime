# GameTime Beta 1 implementation plan

Owner-approved planning target, September 6, with D135 amendments September 9
and D140's Beta scope correction plus D141's optional received-score leaderboard
contract September 20, 2026. This document owns the
future Beta 1 product contract. D134 in [DECISIONS.md](../DECISIONS.md) records
the original choices; D140 removes the all-13 distribution condition. The older
[weekly specification](WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md) and its
acceptance records remain authoritative descriptions of the frozen local
`weekly_*_v1` implementation; they do not implement or constrain this new
Beta 1 contract.

This is an implementation plan, not evidence that the product exists. It does
not authorize hosted mutations, TestFlight distribution, recruitment, data
deletion, notification delivery, payment-provider activity, or live money.

For current implementation status and the September 13 execution reevaluation,
use [WORKING_BASELINE.md](WORKING_BASELINE.md) and the
[remaining plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md). They reuse completed
design/backend work and distinguish local Beta, private TestFlight and a proposed
public simulated launch. This document retains D134/D135's product rules and
D140's working nine-goal Beta scope. D141 adds optional local received-score
leaderboards, with historical policy and test records intact.

**D142 first private TestFlight (September 22, 2026).** The
[friends TestFlight plan](FRIENDS_TESTFLIGHT_PLAN.md) selects a narrower first
build. The Beta 1 contract below stays the later target and is unchanged.

| Beta 1 contract | Build 1 under D142 |
| --- | --- |
| Invites | Accepted friends only. People become friends through server-backed friend requests by exact username. |
| Access | Open Apple sign-up after the 21+ question during account setup, instead of link-granted access. |
| Uploads | Account-mode uploads for every age-confirmed account, disclosed. |
| Policies | Four friend goals plus Personal Steps and Outdoor runs, behind a runtime per-policy allowlist. That allowlist is how build 1 implements the per-policy kill switch required below. |
| Community, links | Closed on the server. |
| Leaderboards | Received-score leaderboards arrive in a following build. |
| Shell | `Home · Challenges · You` stays. Friends live under You, with requests as Home action rows. |

D135 and [the remaining-work contract](BETA_REMAINING_WORK_CONTRACT.md) add six
explicit owner decisions. Their Watch architecture, hardware sequencing,
community disclosure and workload targets govern remaining work. They do not
claim those source/server behaviors have been implemented.

Signal is the official UI/UX as of the September 13 owner clarification. The
[Signal migration contract](design/SIGNAL_UI_MIGRATION.md) governs native default
wiring and cobalt visual retirement (P9A). Its [local native implementation](../outputs/reports/2026-09-13-signal-native-migration.md)
uses Signal across new and retained routes; the report records verification and
remaining device/human limits. D134/D135 product rules and historical access are
preserved. The [bounded P9 connection](../outputs/reports/2026-09-15-p9-authenticated-app.md)
now reuses the ordinary app's authenticated session, with checked-in transport
still off. D138 supplies source and timed-distance rules. The [P8 contract](P8_REAL_HEALTH_CONTRACT.md)
records local implementation and the Exercise causal-origin limit. Approved
hosting/identities and source-backed native journeys remain P9 work.

## Product contract

Beta 1 includes three goal products. The table also preserves the deferred
friend leaderboard design:

| Product | Competition | Metrics | Participants | Window and target |
| --- | --- | --- | --- | --- |
| Friend goal | Each person qualifies independently | Steps, Apple Exercise Time, cumulative running distance, timed running | Creator plus one to five friends; 2–6 total | Each participant proposes their own target before the creator freezes the roster and terms |
| Friend leaderboard (deferred beyond Beta 1) | Best eligible result wins | Steps, Apple Exercise Time, cumulative running distance, timed running | Creator plus one to five friends; 2–6 total | No qualifying target or target suggestion; highest cumulative result or fastest eligible timed run wins |
| Personal performance commitment | The owner qualifies against their own target | Steps, Apple Exercise Time, cumulative running distance, timed running | One | Owner-selected target |
| Community goal | Each entrant qualifies independently against one common value | Steps only | One private operator-published cohort; outcome minimum and publication capacity remain configurable/unapproved | One common target; user-hosted communities are a separately versioned future feature |

The working Beta 1 release set is nine goals: four friend, four personal and
community steps. This is the current scope after D140, not a claim of physical
or hosted acceptance. The four friend leaderboard policies remain specified for
optional local delivery under D141, without becoming a Beta release gate. New
v2 creation ranks eligible activity saved by the correction deadline; existing
leaderboard records retain their original terms and safe lifecycle handling.

Friend and personal policies use scheduled full-day windows lasting 1–30 local
calendar days. The window starts and ends at midnight in its frozen creator or
owner timezone, starts 2–30 calendar days after creation, includes the start
instant, and excludes the end instant. A timezone change or travel never moves
the frozen instants. Community scheduling uses the same full-day representation;
its target, capacity, timezone, and simulated amount remain disabled
configuration until approved from source and comprehension evidence.

All amounts are visibly nonredeemable simulation. Friend creators and personal
owners select a uniform whole-dollar USD display value from $1–$500 for the
applicable agreement. Store integer cents. The community amount remains an
unselected, disabled operator configuration. There is no wallet, balance,
currency conversion, provider object, charge, transfer, payout, fee, or thing
of value.

Profile photos and every photo-specific storage, UI, moderation, analytics, and
verification task are deferred. Beta 1 uses initials or monograms. Username and
account safety work remains in scope.

Push notifications and rolling windows are deferred. Home is the durable action
inbox.

## New domain and preserved history

Create a new versioned `challenge_*_v1` aggregate. Do not widen or reinterpret
legacy Personal, Solo, legacy social contest, `duel_*`, `performance_commitment_*`, or
`weekly_*_v1` agreements. In particular, the locally accepted weekly contract
remains a 2–5-person, seven-date, steps-only fictional policy even though the
new Beta 1 friend contract supports 2–6 people and 1–30 days.

Use shared primitives only where the meaning is identical: durable actor
identity, exact-request recovery, canonical JSON and digests, participant
locking, immutable terms, append-only corrections, notices, review, privacy
redaction, and account cleanup. Do not build a general contest DSL.

Add separately versioned policy evaluators for:

- four friend-goal policies;
- four friend-leaderboard policies;
- four personal-goal policies; and
- one community steps-goal policy.

The friend policy matrix is exactly eight combinations. Individual targets are
part of every friend-goal agreement rather than another selectable policy axis.
Friend leaderboards have no target.

## Lobby, consent, and admission

### Friend lobbies

1. A creator opens a lobby, selects a policy, amount, timezone, and window, then
   invites by exact username or reusable link.
2. Each prospective participant, including the creator, proposes their own
   target for a goal policy. Leaderboard lobbies contain no target fields.
3. Pending link entrants do not consume the 2–6 roster capacity. The creator may
   approve or remove entrants.
4. The creator freezes a complete roster and, for a goal, every participant's
   proposed target. The lobby becomes `consent_pending` and claims admission
   slots for the selected participants.
5. Every selected participant consents to the same complete agreement: policy,
   source, competition, amount, roster, targets when applicable, timezone,
   window, scoring, exits, review, and simulated allocation.
6. Any roster or terms change creates a new lobby/agreement version and clears
   every prior consent. Incomplete consent at the scheduled start cancels the
   challenge and returns all simulated entries.

The creator cannot edit another participant's proposed target. They can ask that
person to revise it before freezing or exclude them from the roster.

### Personal commitments

A personal owner selects one of the four goal metrics, amount, target, timezone,
and 1–30-day window, reviews the complete agreement, and explicitly consents.
There is no lobby, leaderboard, opponent, or shared target. Personal commitments
otherwise use the same metric-specific scoring, readiness, correction, review,
and safe-exit rules. A confirmed personal miss leaves the simulated amount
explicitly unallocated.

### Reusable invitation links

A high-entropy link may be opened by anyone, but challenge details remain hidden
until account creation or sign-in and 21+ confirmation. Successful redemption:

- grants full Beta 1 access immediately;
- creates one pending request for that lobby without creating a friendship or
  roster membership;
- is idempotent per link and account; and
- counts once toward the link's unique-account ceiling.

Each link closes at 20 unique accounts or 30 days after issuance, whichever
comes first. Creator revocation or lobby closure stops future redemption. Access
already granted remains, even if the creator later removes or does not select
the entrant. Blocking, suspended accounts, duplicate accounts, cutoff equality,
and concurrent twentieth/twenty-first redemptions require explicit tests.

### Participation limits

A person may have:

- at most one overlapping friend challenge for a given metric;
- at most the one published community cohort during an overlapping window; and
- at most three unsettled challenges total across friend, community, and
  personal products.

`consent_pending`, `scheduled`, `active`, `syncing`, and `review` count as
unsettled. A finalized friend roster claims slots; a community join and a
personal consent claim them immediately. Unselected pending link entrants do not
claim a slot. A personal commitment may overlap a friend challenge of the same
metric, subject to the aggregate three-challenge limit; this is a Beta 1
simulation rule and does not approve duplicated funded exposure later.

Admission and exact-retry recovery must serialize under durable participant and
challenge locks. Pausing admission blocks new slot claims, not reads, exits,
reviews, corrections, or safe finalization.

## Lifecycle and recovery

Mode-specific entry states converge on one result lifecycle:

- friend: `lobby_open → consent_pending → scheduled → active`;
- personal: `consent_pending → scheduled → active`;
- community: `published_open → scheduled → active` after its join cutoff; and
- every mode: `active → syncing → review → final`, with explicit `cancelled` and
  `void` outcomes.

Freeze the policy/source version, canonical agreement and digest, exact UTC
window, display timezone, amount, roster and targets where applicable, scoring
precision, admission rules, correction deadlines, and exit/review rules. Every
mutation requires an actor-bound request ID and canonical payload. An exact
retry recovers the committed result after time, gate, or network changes; using
the same request ID for changed content fails.

Timing is deterministic:

- initial sync remains open through exactly end +24 hours;
- corrections remain open through exactly end +48 hours;
- provisional publication is due no later than end +72 hours as an operational
  service level;
- participant review closes 48 full hours after the actual provisional notice;
- operator resolution closes 72 full hours after the actual review filing; and
- scheduler or recovery delay never shortens a person's review or resolution
  window and does not by itself void the result.

Late processing extends finality. It never rewrites the activity, sync, or
correction window. Untrustworthy or unresolved scoring facts can still require
a void under the applicable result policy.

Use separate kill switches for new admission, each metric/source policy,
ingestion, lifecycle processing, community discovery, and optional analytics.

## Scoring and simulated allocation

Normalize values before evaluation:

- steps: whole counts;
- Apple Exercise Time: integer seconds, with minute-based UI targets;
- running distance: integer millimetres; and
- timed running: conservative whole elapsed seconds including pauses.

### Goals

Cumulative goals qualify at `observed >= target`. Timed-running goals qualify
only at `elapsed < target`; equality is a miss when the complete admissible facts
support a decision. The best eligible whole workout in the window counts.

Missing or unreadable Health data never establishes a miss. For friend goals,
exclude and refund an unresolved participant, then evaluate the remaining
resolvable group. Qualifiers recover their own simulated entry and split the
confirmed misses evenly. Integer remainders and all-miss pools remain explicitly
unallocated. If any exclusion leaves fewer than two resolvable friend
participants, void the whole challenge and return every simulated entry.

For personal commitments, missing or unresolved data voids the commitment and
returns its simulated entry. A confirmed miss records the entry as unallocated;
a qualifier recovers it. Community uses the same per-person goal allocation with
its operator-selected minimum and capacity.

### Leaderboards

Steps, Exercise Time, and cumulative-distance leaderboards rank the highest
normalized result. Timed-running leaderboards rank the fastest eligible whole
workout. Equal normalized results are co-winners and split the active simulated
pool evenly; integer remainders remain unallocated.

For NEW `friend_*_leaderboard_v2` agreements, D141 ranks eligible activity
successfully saved through the existing correction cutoff, inclusive, without
requiring complete Apple Health history. Partial saved totals rank at those totals;
a missing workout cannot improve a saved time. Missing or late activity does not
count. No valid saved score means unranked and return of that simulated entry.
Fewer than two valid remaining scores voids and returns all entries. First scores
and corrections can be saved through end +48 hours for v2 only.

Show the server-saved score, last update, deadline and Refresh; a local read is
not upload confirmation. Confirmed GameTime failures use exact recovery or review.
Consent, source rules (including Exercise credit v2), review, exits, privacy and
nonredeemable simulation remain. [The v2 contract](RECEIVED_LEADERBOARD_V2.md) owns
implementation detail. Historical leaderboard v1 still voids when any remaining
participant is unresolved; no old agreement is reinterpreted.

### Safe exits and account changes

All Beta 1 withdrawals are non-punitive. Exclude and refund the withdrawing
participant. Continue only with at least two resolvable friend participants;
otherwise void the whole friend challenge. Apply the same minimum after account
deletion, a pre-finality block that ends participation, or operator removal. A
post-final block ends contact and shared visibility but never rewrites a final
result. A personal withdrawal returns its simulated entry. Preserve the minimum
pseudonymized agreement/result audit while ending social visibility and contact.

Do not enable either timed-running policy until physical tests produce an
approved whole-workout distance tolerance. Record that value as a new policy
decision; never invent or silently reuse the zero-tolerance fixture.

## iPhone and Apple Watch architecture

Beta has no GameTime watchOS app or WatchConnectivity dependency. Apple Watch
records activity into Apple Health; GameTime iPhone reads eligible Watch-origin
HealthKit data and uploads only minimum normalized scoring facts. Preserve iPhone
HealthKit and historical agreements. A paired physical Watch is a launch
requirement, not a blocker to authorized pre-hardware implementation. Real source
semantics, completeness, adapters and ingestion still require separate acceptance.

## Health readiness, suggestions, and ingestion

Preserve the seven visible readiness states. Completing a permission prompt or
receiving a successful empty query is never `Ready`.

Browsing, lobby drafting, and target proposals work without Health access. Final
consent or community joining requires a successful selected-source read with:

- at least one eligible record in the prior 30 days for steps, Apple Exercise
  Time, or cumulative running distance; or
- at least one comparable eligible whole workout in the prior 90 days for timed
  running, using the approved distance-tolerance policy.

This is a positive-read readiness signal, not proof of complete history.

Compute target suggestions on-device only for friend goals and personal
commitments. Never compute or show a target suggestion for a leaderboard.

- cumulative suggestion:
  `ceil(trailing 28-day eligible total × challenge days ÷ 28 × 1.10)` in the
  metric's canonical unit;
- timed suggestion:
  `floor(best comparable eligible elapsed seconds from the prior 90 days × 0.98)`.

Omit a suggestion when eligible history is absent. A participant may edit their
goal proposal before friend terms freeze; a personal owner may edit before
consent. Upload only the selected target, never the local baseline history.

Build separate adapters for steps, Apple Exercise Time, running-workout
distance, and timed workouts. Exclude manual and unsupported imported records,
keep routes on-device, and upload only minimum scoring facts through the
attested boundary. A client cannot author `complete`, `verified`, qualifying, or
final flags. Revisions can decrease and deletions must remain representable.

All four goal-metric source policies must pass the physical iPhone/Watch matrix
before TestFlight distribution of the working nine-goal Beta set. A source that
cannot support trustworthy miss handling remains disabled and blocks the working
Beta milestone until the owner makes a separate scope decision. The four
friend leaderboards do not block this Beta milestone; new v2 agreements follow
D141 while historical v1 creation remains blocked.

## Identity, safety, and product shell

After Sign in with Apple, ask `Are you 21 or older?` Store only the confirmation,
policy version, and timestamp—never a birth date or identity document.

Retain exact, case-insensitive username lookup. Do not add fuzzy search or a
global profile directory. Add username/account reporting, blocking, operator
removal from a lobby or community, and audited account suspension before
external beta. Manual owner-operated moderation is sufficient for the small
cohort. No photo moderation exists in Beta 1.

The target shell is `Home · Challenges · You`:

- **Home:** stable server action/status projection ordered by actionable review
  deadline, pending consent/start, active end time, upcoming start, then recent
  history. Preserve last-known sections when one refresh fails.
- **Challenges:** create, join, community discovery, invitation handling, and
  complete history.
- **You:** account, Health readiness, safety, support, privacy, and terms.

Replace the current shell only after the new flows pass local and physical
acceptance. Remove legacy seven-day Personal creation, navigation, client
wiring, background refresh, and visible history from the new shell. This does
not reinterpret the newer personal performance-commitment product.

Retain applied Personal migrations and inert schema objects. After an exact
non-production inventory and audit export, delete only legacy Personal
challenge, snapshot, review, payment-test, and directly related records. Preserve
accounts and new-product data. Cleanup requires a separately reviewed,
environment-guarded admin runbook and explicit destructive-cleanup approval;
the plan itself does not authorize execution.

Community Beta 1 is one operator-published private scheduled steps-goal cohort.
User-hosted communities require a separately versioned future feature. Own progress
may be current. Exact anonymous aggregates require at least five joined, active,
nonremoved disclosure-cohort participants and a server snapshot at least 15 minutes
old. Under five expose no exact numerator, denominator, participant count,
qualifier count, total or alternative differential signal. Five is a disclosure
threshold, not the challenge outcome minimum. No stranger usernames, ranking or
inferred friend access is permitted. These are remaining server/UI requirements,
not acceptance of current fictional projections. Keep target, outcome minimum,
publication capacity, timezone and simulated amount disabled until selected after
source and comprehension testing.

Beta planning workload: 2,000 registered, 250 DAU, 100 concurrent sessions,
25 requests/second burst, one 250-person cohort. Long-term characterization:
25,000 registered, 5,000 DAU, 1,000 concurrent, 150 requests/second, 10,000 community.
These are planning targets, not measured throughput or approved publication values.

## Public interfaces

Add versioned operations for:

- age confirmation and invitation-link redemption;
- friend lobby preview, create, target proposal, entrant request,
  approve/remove, roster freeze, consent, leave, cancel, and link closure;
- personal commitment preview, create/consent, leave, and cancel;
- community publication, preview, join, leave, and closure;
- paginated Home/history/detail projections with stable cursors, server time,
  projection revision, and per-section freshness;
- metric-specific attested ingestion and corrections;
- participant review filing and narrowly scoped operator resolution/result
  correction; and
- username/account reporting, blocking, moderation, and suspension.

Add typed client models for product mode, policy, competition, metric, target,
scheduled window, readiness, lobby/consent, freshness, review, qualification,
ranking, and simulated allocation. Do not add notification registration APIs or
photo operations in Beta 1.

## Verification and rollout

Qualify the nine enabled goal policies for Beta: four friend goals, four personal
goals and one community steps goal. Keep the existing 13-policy fictional and
historical regression evidence, and verify the four deferred friend leaderboard
modes cannot be created as new real challenges.

- Test friend rosters of every size 2–6, with two- and six-person end-to-end
  native/HTTP goal journeys; participant-proposed targets; withdrawals;
  deletion; blocking; operator removal;
  unresolved data; all/some/no goal qualifiers; amount conservation; exact
  retries; and concurrent lobby, consent, admission, and link actions.
- Test personal goals for all four metrics, strict timed equality, safe exit,
  unresolved data, confirmed miss/unallocated simulation, correction/review,
  exact retry, and the aggregate three-unsettled limit.
- Test the twentieth and twenty-first unique link redemption, exact 30-day
  equality, revocation, lobby closure, repeated account redemption, removed
  entrants retaining beta access, and blocked/suspended accounts.
- Test one overlapping friend challenge per metric, the community exception,
  personal overlap, aggregate three-challenge admission, prior review plus a
  future window, and concurrent requests at each limit.
- Test full-day windows across DST and timezone changes, start/end equality,
  2- and 30-day creation lead bounds, 1- and 30-date duration bounds, late and
  downward Health corrections, and scheduler recovery without shortened review.
- Validate formulas, absent history, metric-specific readiness lookbacks, units,
  rounding, strict timed comparisons and editable proposals. Preserve
  leaderboard target rejection, ties and allocation as later-mode regression
  checks without treating them as real-source Beta acceptance.
- Run the physical source matrix for manual/imported records, overlapping
  devices, deletions, late Watch sync, permission changes, pauses, source loss,
  and timed-distance accuracy.
- Test onboarding, link redemption through sign-in/age confirmation, Home
  ordering, every creation/join flow, review, community privacy, username/account
  reporting, blocking/suspension, accessibility sizes, VoiceOver, reduced motion,
  offline use, account switching, and expired sessions. Use monograms; no photo
  cases exist.

Before TestFlight, require revised privacy/terms disclosures, a monitored support
route, operator credentials and audit logging, a hosted scheduler/recovery drill,
explicit hosted deployment approval, and destructive-cleanup approval where
cleanup is still desired.

Use default-off, revocable first-party pilot instrumentation only. Exclude Health
totals, usernames, simulated amounts, routes, and review text. Do not add session
replay or third-party growth analytics.

No live payments, deposits, payouts, fees, Garmin integration, push delivery,
profile photos, or public deployment are included.

## Evidence gates and non-decisions

- Apple Health is the only Beta 1 activity source.
- All Beta 1 amounts are visibly nonredeemable simulation.
- StepBet and WayBetter support only the general return-plus-possible-share
  concept; they do not select GameTime's target, duration, capacity, amount, or
  concurrency policy.
- D138 selects inclusive 100–102% whole-workout timed distance and closes the
  owner's measured P7 effort. Community target/capacity/timezone/amount still
  require owner approval from recorded human evidence. Checked-in source and
  external transport gates remain closed; local implementation does not approve
  hosted operation or distribution.
- Hosted mutation, TestFlight distribution, participant recruitment, legacy
  Personal-data deletion, and any destructive cleanup remain explicit rollout
  actions—not consequences of completing local code.
