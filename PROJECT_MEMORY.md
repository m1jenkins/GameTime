# GameTime project memory

## Current working baseline — September 22, 2026

Continue from local `main`. The [working baseline](docs/WORKING_BASELINE.md)
lists the Phase 0 commits. [D142](DECISIONS.md#d142-first-private-testflight-adds-friends-opens-apple-sign-up-and-ships-goals-first)
and the [friends TestFlight plan](docs/FRIENDS_TESTFLIGHT_PLAN.md) set the next
work. The first private TestFlight:

- adds friend requests under You, with Home action rows, keeping
  `Home · Challenges · You`
- opens Apple sign-up on `gametime-p11b` for fewer than ten email-invited testers
- extends disclosed account-mode uploads to every age-confirmed account
- ships four friend goals plus Personal Steps and Outdoor runs
- defers the D141 leaderboards to the next build
- closes community and links on the server

Hosted mutation waits until the owner's scheduled personal goals are final,
around October 4–6. Hosted mutation, TestFlight and recruitment each need explicit
approval.

Hosted `gametime-p11b` today:

- The private trial is on for one enrolled account, with device proof off and
  sign-up closed. Real admission, ingestion and processing are on.
- `20260922150718` lets that account save personal Steps and Outdoor runs.
- `20260920162025` is still unapplied.
- Deployed functions: worker, snapshot, monitor, `attest-device` and
  `ingest-challenge-health`.
- The checkout's CLI link and `supabase/staging-project-ref` still point at the
  historical project, so always pass `--project-ref`.

## September 20 baseline record

Continue from local `main`, containing reviewed P11 `8e45132` and P8/P9 through
merge `9652bc9`. The owner directs completed authorized work to be committed and
merged into `main`; push requires separate authorization. The
[working baseline](docs/WORKING_BASELINE.md), [P11 local report](outputs/reports/2026-09-20-p11-local-scheduling.md)
and [P11B installation receipt](outputs/reports/2026-09-20-p11b-hosted-installation.md)
own source and evidence. The approved bounded installation created `gametime-p11b`
(`lyushhqoednheqwzsmxh`) in Better Bet, `us-west-1`, Free, quoted $0/month with a
$20 ceiling. The owner is commissioning owner and credential custodian; reuse
Vault and Edge secrets. All 93 migrations and only the three challenge machine
functions are installed. All jobs/gates/fixtures remain off, Auth is closed,
private schemas unexposed and no community selected. The bounded checks passed.

D138/D139 source rules remain adopted. D141 adds [new received-score friend
leaderboards](docs/RECEIVED_LEADERBOARD_V2.md): rank eligible activity saved through
the correction deadline, without requiring complete history. Missing scores are
unranked with entries returned; fewer than two valid scores voids and returns all.
Old agreements and strict Exercise v1 stay unchanged; new Activity minutes use
Exercise credit v2. D140 keeps the working Beta scope at nine goals: these four
leaderboards are optional local capability, not a distribution requirement. All 18 external
gates and checked-in transport remain closed; the four goal-metric source gate
and other release acceptance remain unmet. Active operation,
remaining identity/operating decisions, named operators and broader acceptance
remain separate. Use the [next planning prompt](docs/P11B_NEXT_PLANNING_PROMPT.md)
without repeating completed local or installation checks.

## September 19 baseline record

Use `/Users/user/Documents/GitHub/GameTime` on `main` as the authoritative
project, with isolated task branches when needed. [WORKING_BASELINE.md](docs/WORKING_BASELINE.md)
owns exact source, completed work, evidence and next dependencies. The September
15 published baseline at `1dacc6644f2100567d85fbaa2970bb7285bbaa35` includes P4/P5/P6, P7/P10
preparation, Signal/P9A, S2/P8 privacy/recovery corrections, P11A local
worker/operator/deletion work and P9's bounded shared-session connection.

The September 19 [main consolidation](outputs/reports/2026-09-19-main-consolidation.md)
includes delivered invitation, operator recovery, suspended-account repair,
service monitoring, iOS 18 compatibility and the fictional Personal lifecycle
preview. It preserves the profile-retry and actor-switch fixes. The original
[integration record](outputs/reports/2026-09-19-integrated-candidate.md) keeps its
dated checks; the consolidation records the later full local gate and CI status
at merge. This does not accept sources, hosted operation or release. The complete release
matrix remains P12 work.

The owner selected **Signal as the official UI/UX** on September 13.
[The migration contract](docs/design/SIGNAL_UI_MIGRATION.md) and adopted study
remain design authority. Ordinary and retained native routes use Signal;
obsolete cobalt rendering and fonts are retired. The native report retains its
actual checks and limits; later publication includes its supporting evidence.
Dated cobalt records below describe historical decisions.

The September 15 request prepares a clean starting point before final testing:
consistent Signal, streamlined files/navigation and safe main consolidation.
Firstmate owns publication and guarded branch/worktree cleanup. Preserve unique
or uncommitted work; do not merge cancelled verification candidates just to
remove their branches. [The consolidation record](docs/WORKTREE_CONSOLIDATION_STATUS.md)
and linked cleanup report distinguish landed candidates and retained exceptions.

The September 15 cleanup did not start P7–P13. On September 18 the owner
obtained a paired Apple Watch, opted in and [started the private P7 device
session](outputs/reports/2026-09-18-p7-device-session.md) on an iPhone 17.
On September 19 the owner [signed off the P7 test effort and directed P8
preparation](DECISIONS.md#d137-owner-signs-off-p7-testing-and-directs-p8-preparation).
The session record preserves performed observations.
[D138](DECISIONS.md#d138-owner-selects-p8-source-rules-and-whole-run-distance-tolerance)
now selects Apple Watch/Workout origin, outdoor whole workouts, reconciled Watch
switching and inclusive 100–102% timed distance. The [P8 contract](docs/P8_REAL_HEALTH_CONTRACT.md)
records local adapters/ingestion and the concrete Exercise causal-origin limit;
Exercise admission remains unavailable. Positive observations cannot establish
complete leaderboards or misses. P9 wiring and delivery coordination with retained writers,
hosted operation and physical/human/release acceptance remain gated. Simulation
does not accept a source. Checked-in challenge transport remains off and all 18
readiness entries remain false. Preserve historical Personal/Solo
agreements and access until replacement acceptance. D134/D135 and the
[remaining plan](docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) still own
product requirements; no adopted scope changed.

## Historical completion records

The dated entries below preserve what was true at completion. Their branches,
paths, publication state and next-task instructions are superseded by the
working baseline above. Original checks and limitations remain intact.

## P10 device-independent preparation — September 12, 2026 UTC

P10 extended the existing release-readiness-b7 task on
`codex/hosted-preparation-p10`, based on `fd193e7`; its result is now included
in local `main`. The
[handoff](outputs/reports/2026-09-12-p10-completion.md) records hosted identity/settings
preparation, actual local RPC privileges, scheduler/monitoring/rollback design,
P6 operator permissions and support/retention decisions. All owner-selected
publication/hosting/policy values remain unapproved; no device participation was
needed or performed. P7–P9 and hosted acceptance remain pending, all 18 readiness
entries remain false, and normal signed-in challenges remain unavailable.
The P10 completion report preserves its original branch and resource identities.
No hosted operation or external readiness was established.

## Prompt 6 local completion — September 12, 2026 UTC

The private operator community is locally implemented at
`05f405c24453fe6743ece994d646058958bfdbb2` on `codex/private-community-p6`, in
`/private/tmp/gametime-p6-20260912/GameTime`, from P5
`e16cff4b3beaa7bcce95db6b0e82eedaa94865fa`. Read the
[P6 completion and handoff](outputs/reports/2026-09-12-p6-completion.md) and
[community contract](docs/PRIVATE_COMMUNITY_V1.md) before later work.

P6 adds 250-current-member reservations, delayed five-person-threshold counts,
private member revisions, scoped reports, separately audited global support,
appeals/reinstatement and quotas. Historical exits keep their unsettled returns;
replacements no longer break settlement. New native count/report/appeal controls
are locally verified. The report records actual SQL, HTTP, upgrade, concurrency
and native evidence, preserved failures and blocked CLI advisors. Snapshot
capture is service-only; no hosted periodic scheduler or external support is
configured. Product main and original/P4/P5 checkouts remain unchanged. P7 has
not started; real-source, money, hosted and distribution gates remain closed.

## Prompt 5 local completion — September 11, 2026

Bounded history keysets, shared private row projection and measured set-based
worker discovery are implemented and locally verified at
`e0a94bd793e4720ae04795760d614b049005618b` on `codex/bounded-queries-p5`, in
`/private/tmp/gametime-p5-20260911/GameTime`, based exactly on completed P4
`369e7b90dfeb74314244a923a87864e368348412`. The
[completion report](outputs/reports/2026-09-11-p5-completion.md) records identical
fixtures/plans, latency and storage/write cost, 3,998 SQL assertions, actual-session
races and old-data upgrade proof. New history cursors explicitly expire when
history ordering changes; old offset cursors retain their original lifetime.
CLI advisors/lint remain blocked; live discovery still scans the live eligible
set. Product main and the original dirty/P4 checkouts are preserved. P6 remains
unstarted; no hosted/source/money/distribution gate opened.

## Prompt 4 local completion — September 11, 2026

Scoped read/mutation locks, durable bounded claims and cancelled-work exclusion
are implemented and locally verified at
`b67776c8b3fc1173f4e7f44bd794db9f81b2b7a0` on the isolated
`codex/lean-beta-preparation` branch. The
[completion report](outputs/reports/2026-09-11-p4-completion.md) records final-source
tests, before/after measurements, preserved failures and limitations. The separate
product main remains `affd367ebe5411969fd5b7abd45629e0746a5a7d`; local completion
does not imply landing or rollout. At P4 completion, P5/P6 were unstarted; current P5 status is above.

## Simplified local execution — September 11, 2026

The owner asked to simplify the remaining prompts and implementation only where
there is a concrete benefit. Use the current
[remaining plan](docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) and
[prompt pack](docs/FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) for next work.
Keep focused correctness, privacy, revocation, retry and migration checks;
reserve the complete runtime/release matrix and long soak for integration/release.
Cancelled candidate-gate recovery is not a local implementation prerequisite.
This does not accept its failed verification or the partial Prompt 4 candidate.

The separate current product includes Cobalt over the c8-derived backend. The
original dirty checkout remains preserved. The P4 continuation below was completed
locally as recorded above; run P5/P6 sequentially only when requested and locally accepted.
Do not restart completed prompts or import the entire dirty copy/design patch.
The [cleanup report](outputs/reports/2026-09-11-beta-simplification.md) records
the exact branches, safe changes and remaining work. Product agreements, source
acceptance, community requirements and external-action boundaries stay intact.

## Default app interface — September 11, 2026

The owner selected `codex/crisp-cobalt-ui` as the default UI and authorized a
direct install on Mason’s iPhone. Normal signed-in Debug, Staging and Release
launches now use Cobalt Home, Challenges and You. Existing Personal agreements
remain accessible through **Existing challenges**; account support and privacy
remain available in You. Historical fixture/demo journeys keep their original
navigation for regression coverage.

This is UI activation, not hosted challenge admission: the regular app uses a
closed challenge client and explains that new challenges are not open. The local
preview remains an explicit Debug route. No sample scores are shown as account
data, and no hosted backend, Health scoring or money gate was enabled. See
[activation verification](docs/design/crisp-cobalt/DEFAULT_UI.md).

## Remaining-work authority — September 9, 2026

D135 and [the remaining-work contract](docs/BETA_REMAINING_WORK_CONTRACT.md)
record the owner's six current decisions: no GameTime watchOS app or
WatchConnectivity; eligible Watch-origin Health data read by iPhone with minimum
normalized scoring uploads; paired Watch required for launch but not pre-hardware
implementation; one operator-published private cohort; exact anonymous aggregates
only at five joined/active/nonremoved participants and from server snapshots at
least 15 minutes old, with no exact or differential signals under five; Beta
2,000/250 DAU/100 concurrent/25 requests per second/250-person cohort planning
and long-term 25,000/5,000/1,000/150/10,000 characterization; visibly nonredeemable
simulation. Five is a disclosure threshold, not an outcome minimum.

Prompt 0A retires the active dedicated Watch runtime while preserving inert
historical source and iPhone HealthKit. Community privacy, capacity and source
architecture above are adopted requirements, not newly implemented server/source
behavior. Physical source policies, timed tolerance, launch community settings,
human/hosted acceptance and all 18 external gates remain unresolved/false. Prior
"next physical task" statements below describe historical sequencing; hardware
availability does not block otherwise authorized pre-hardware work. Acceptance,
landing and later waves remain separately controlled.

## Audited Beta 1 product contract — September 6, 2026

The owner approved the audited Beta 1 planning contract recorded in D134 and
[the Beta implementation plan](docs/BETA_IMPLEMENTATION_PLAN.md). Beta 1 now
includes friend goals, friend leaderboards, personal performance commitments,
and one operator-published community steps goal. Friend and personal formats use
all four Apple Health metrics: steps, Apple Exercise Time, cumulative running
distance, and timed running. Personal commitments are goal-only. Friend
leaderboards have no target; equal normalized results create co-winners.

This supersedes D132's unconfirmed capacity interpretation and the W1–W4
sequence as the future product target. A friend challenge is the creator plus up
to five friends, 2–6 total. In friend goals, each person proposes their own
target before the creator freezes the full terms and everyone consents. Friend
and personal windows are scheduled full local calendar days lasting 1–30 days.
The adopted drafting default starts them 2–30 calendar days after creation.

Reusable links grant full beta access after sign-in and 21+ confirmation, create
a pending lobby request, and close after 20 unique accounts or 30 days. They do
not create friendship or roster membership. Admission allows at most one
overlapping friend challenge per metric plus the community cohort and three
unsettled friend/community/personal challenges total. Fewer than two resolvable
friend participants voids the challenge. Review and resolution windows run from
the actual notice and filing and are never shortened by scheduler delay.

Profile photos and every photo-specific task are deferred; keep username/account
reporting, blocking, operator removal and audited suspension. The legacy
seven-day Personal product is planned for removal from the new shell after the
replacement flows pass acceptance. Its applied contracts and current behavior
remain unchanged until that separately gated work occurs. The existing
`weekly_*_v1` implementation remains frozen 2–5-person historical local behavior;
do not relabel it as the new 2–6 contract.

The audited plan is planning authority, not implementation or rollout evidence.
Physical validation of all four sources still blocks distribution. The timed-run
distance tolerance and community target/capacity/timezone/simulated amount remain
evidence-dependent owner decisions. No hosted mutation, distribution,
recruitment, legacy-data deletion, provider activity, or live money was
authorized.

## Local weekly implementation execution — September 6, 2026

The owner expanded execution to all feasible local W1–W4 work, starting with
W1A and proceeding in dependency order. The historical W1A-only prompt below
is superseded; completed earlier phases are preserved and organizer-event
nomination UI remains paused. Implementation uses an isolated clone/branch,
leaving the original dirty checkout and its local Supabase stack untouched.

Current status is explicit:

- W1A is implemented and locally accepted as fictional policy logic.
- The fictional W1B/W2A backend is implemented and locally verified.
- The opt-in W1C/W2B native journeys are implemented and locally verified.
- W3 and W4 have fixture/prototype contracts only.
- Physical source validation, human accessibility/comprehension, a real pilot,
  hosted operation, notifications and funded operation remain unaccepted.

Implementation ownership and dependencies are tracked in
[WEEKLY_EXECUTION.md](docs/WEEKLY_EXECUTION.md).
[WEEKLY_LOCAL_ACCEPTANCE.md](docs/WEEKLY_LOCAL_ACCEPTANCE.md) is the authoritative
current checklist of executed tests and remaining gates; historical counts
below are not automatically rerun evidence. Independent review findings must
close with specific regression proof before local acceptance is recorded.

D133 records reversible fixture choices. Five total including creator remains
an assumption; a common community target describes individual completion, and
its numeric value is not selected for launch. Missing data never proves failure.
No real Health source, human accessibility pass, provider/legal clearance or
actual pilot has been established. Source-dependent metric selection, push and
funded capability remain disabled. The owner has authorized reconciling status,
marking [PR 17](https://github.com/m1jenkins/GameTime/pull/17) ready after its
checks pass, and merging it with its useful commit provenance preserved.
This delivery authorization does not authorize deployment or any external gate.

Fresh disposable verification passed 3,576 SQL assertions across 72 files, 833
TypeScript tests, 113 Swift core tests and the actual persisted lifecycle smoke.
Authenticated native HTTP and all 50 legacy UI tests passed. The local acceptance
record owns final native counts, artifacts, review findings and remaining gates.
The PR 17 CI snapshot at `6476d47` separately passed 3,576 SQL assertions,
835 Deno tests, 113 Swift core tests, 365 native tests with three explicit
controller-gated skips, 50 legacy UI tests, 10 conformance tests, and Staging/
Release builds. These results do not replace the earlier local-run counts.

After PR 17 merges, the authorized next task is a focused branch for a clearly
identified, default-off Debug steps-source investigation on an explicitly opted-in
physical iPhone and paired Watch. Keep raw Health records private on-device,
exclude the investigation from Release, and disconnect it from scoring, uploads,
telemetry and logs. Record only performed observations from the existing source
matrix; query success and Simulator tests do not establish physical acceptance.
Stop for the owner's required walking, Watch, Health-edit and permission actions.
If completeness or trustworthy miss handling remains unresolved, real weekly
scoring stays disabled. Do not add more fictional backend breadth or restart W1A.

Human VoiceOver, Dynamic Type, comprehension and voluntary-exit checks remain the
next native acceptance work after or alongside source investigation. The proposed
20–30-person, two-round pilot still needs separate authorization; it has not run.

## Historical beta friend capacity and community goal decision — September 6, 2026

The owner requested beta friend challenges supporting **up to five friends**
and selected **one common weekly step goal for community launch**. The updated
plan interprets these as **2–5 participants total, including the creator**, and
**each community entrant individually meeting the same step target**, not a
combined group total. These two interpretations are working assumptions, not
additional explicit owner decisions. The numeric community target is open.
This supersedes the two-person W1 recommendation and personalized community
target formula in D131 and the earlier reconciliation below. Friend-specific
individual targets remain a recommendation. This planning update required W1A
to evaluate a frozen 2–5-person roster with every participant’s consent and
W1B/C to support group invites, capacity, privacy and two- through five-person
acceptance. The local implementation above now supplies those fictional paths. Proposed
group simulation/exit rules are documented separately from adopted scope.
Community format is selected; rollout, recruitment and real money remain gated.
See D132 and the weekly specification. This update changes documentation only.

## Historical weekly implementation-plan reconciliation — September 6, 2026

The owner requested the needed implementation-plan changes after discussing
weekly friend steps, Apple Watch Exercise minutes and community challenges.
[PLAN.md](PLAN.md) and the [weekly specification](docs/WEEKLY_CHALLENGES_IMPLEMENTATION_PLAN.md)
then recommended W1 weekly friend steps, W2 one community experiment, W3 Exercise
minutes and W4 configurable cumulative/timed distance with relevant longer-goal
progress. W1A was the next slice at that planning point; it is now implemented
and locally accepted as fictional policy logic, as recorded above.
Organizer-event nomination screens are paused as the default next task.

That task changed documentation; it did not implement or approve every proposed
format. Dropping the mandatory 5K and preserving participant-selected supported
distances are owner decisions. The weekly-first order, community pilot, target
formula and simulated-allocation defaults remain recommendations; community
launch, fees, forfeiture/remainder recipients and actual money are unselected.
The proposed initial study is 20–30 adults over two weekly rounds after source,
native, community/privacy and support acceptance, with separate recruitment/
distribution authorization. It has not been recruited or run.

Completed Personal, fictional-5K and engagement work stays intact. New formats
need separate terms, requests, source validation and result/allocation rules.
Prior-week review must coexist with explicitly accepted future-week activity;
financial exposure limits must include unsettled earlier weeks. D130's consent,
privacy, voluntary-return, reminder and exit requirements remain in force.
See D131 for decision status. No app code, schema, hosted state, provider,
notification delivery or live money was changed by this planning task.

## Responsible engagement direction — September 6, 2026

The owner requested implementation and business-plan changes based on the
supplied engagement/compulsion report. New work optimizes understood agreements,
athletic progress, fair results and voluntary return with pressure/privacy/exit
guardrails. Do not optimize paid-challenge frequency, committed amounts, app
opens or return after loss in isolation. No loss-triggered marketing, financial
celebrations, forced daily exercise streaks, automatic rematches or stake raises.
Service fees/optional club tools remain hypotheses; forfeiture recipient, prices,
limits and notification caps remain unselected or explicitly proposed.

Native local duel/goal reviews now summarize existing terms before consent and
retain full expandable rules. Dormant native lead-loss/comeback category setup
and launch notification permission prompting are removed; push remains off.
See [scope and verification](docs/RESPONSIBLE_ENGAGEMENT_ACCEPTANCE.md).
No agreement, result, simulated amount, source policy or payment mode changed.

[PLAN.md](PLAN.md#current-implementation-order-after-the-engagement-review)
now combines the weekly-first roadmap with participant-selected metric policies,
relevant native progress/selected following and user-requested reminders with
server preferences and caps,
privacy-minimized pilot measurement, and server financial limits/pause before
cash. These remaining features are planned, not implemented by the review.
Historical fixed-5K slices and their acceptance records stay valid for existing
fixtures only; they must not become mandatory launch defaults again. Live money,
hosted rollout, recruitment and external delivery remain disabled/separately gated.

## Owner clarification — September 5, 2026

The owner has **dropped the fixed 5K race format as the future product
direction**. Distance-based challenges remain in scope when people choose
their own distances; a standard 5K must not be required. This supersedes the
earlier recommended official-5K launch and pilot defaults below and in the
planning documents. Friend challenges and personal commitments remain the
adopted products.

Weekly steps, Apple Watch Exercise-minute and community challenges were being
considered in this discussion. Their build order is now a documented planning
recommendation above; payout rules, company fees and forfeiture destinations
have not been selected; researching StepBet and WayBetter is not adoption of
their money models. Existing fixed-5K code and acceptance records describe
historical implementation, not the revised product requirement. Preserve
existing agreements and unrelated work. Live money remains disabled.

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
legacy social contests or existing Personal/Solo records as the new products.

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

At that planning baseline, the recommended first slice was a local, default-off,
simulated same-event 5K duel agreement backend with two explicit consents. The
proposed human pilot used organizer-published chip times before automatic Garmin
proof. The proposed commitment format was a timed 5K goal over 28–90 days, with
true-mile and asynchronous formats later. These historical planning defaults
were not owner mandates; the later no-mandatory-5K direction supersedes them. Neither a provider, a forfeiture
beneficiary, a live price nor a launch jurisdiction has been selected.

### Original planning request

Update the project documentation to reflect this direction, inspect the
existing implementation for reusable pieces, and create a concrete phased
implementation plan. Separate what exists, what is decided, what is proposed,
and what needs external validation. The planning task should choose reasonable
reversible defaults and continue without asking whether to make this pivot.

The original planning brief is
[docs/NEXT_BUSINESS_MODEL_PROMPT.md](docs/NEXT_BUSINESS_MODEL_PROMPT.md).
The original Phase 1A prompt is retained as completed history in PLAN.md.
For the next build task, use the
[current implementation order](PLAN.md#current-implementation-order-after-the-engagement-review).

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

**Phase 3(d) is implemented below:** explicit friend-following permissions and selected
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

### Phase 3(d) selected progress and following — September 5, 2026

A separate default-off local backend now requires owner sharing consent and
named-friend acceptance before exposing goal facts and explicitly published
manual-progress cards. Check-in cards omit private note text; milestone cards
share only the selected name/date/status. Retraction invalidates old pagination.
Revocation, unfriending, blocks, either person's deletion and safe closure end
existing follows permanently; reconnecting requires fresh consent.

Structured reactions, personal pull-based in-app reminders, exact block actions,
private reports and independently assigned/audited support access are included.
No social action changes proof, completeness, agreement terms, results or money.
A distinct local retention hold preserves fictional records after closure and
deletion. Actual social/report-data retention and staffed support remain open.

See [following acceptance](docs/PERFORMANCE_FOLLOWING_V1_ACCEPTANCE.md) for the
sharing contract, local verification, rollback-only example and client handoff.
The normal database and unrelated work were preserved. No native commitment
screen/cache, hosted mutation, scheduler, external delivery, provider or live
money was enabled. **Phase 3(e) is implemented below.** Native integration
remains separate work.


### Phase 3(e) commitment lifecycle — September 5, 2026

A separate default-off local worker now persists activation, durable owner
notices, review cases and independent resolutions, immutable finals and
separately appended nonredeemable simulated consequences. The unchanged pure
evaluator receives complete proof snapshots; even unreviewed source capture
invalidates an in-flight commit. PostgreSQL microseconds and full correction,
filing and review windows are preserved. Missing proof alone never means a miss.

Finality releases the commitment slot and permanently ends existing follows.
Original agreement terms, consent and closure receipts retain their meaning;
operational finality is read through the separate lifecycle projection. Owner
case recovery survives gate shutdown and finality with an active session.
Review/support grants are independent, scoped, expiring and audited. Post-final
support notes never rewrite proof, final results or simulated consequences.
A dedicated fictional retention hold preserves history through deletion.

See [lifecycle acceptance](docs/PERFORMANCE_LIFECYCLE_V1_ACCEPTANCE.md) for the
local SQL boundaries, transaction races, persisted evaluator/worker smoke and
full portable regression evidence. The separate disposable database was used;
the normal database and unrelated work were preserved. No native source,
hosted mutation, schedule, external delivery, provider or live money changed.
**Historical handoff, partly implemented in Phase 3(f) below:** local native
commitment integration across agreements, attempts, progress, selected following
and results/review. This handoff does not select the current next task. Actual organizer operations,
real-data retention/support policies, native/device acceptance, result-sharing
consent, true-mile formats and hosted rollout remain separate work.

### Phase 3(f), first native slice — September 5, 2026

The opt-in local Running goals route now starts native commitment integration:
server preview and explicit agreement consent, owner history, corrected notices,
review requests, safe exits, immutable results and separately recorded simulated
amounts. Distinct typed models and actor-bound durable requests preserve exact
recovery. Failed reads/account changes clear owner content; original `open`
agreement receipts never override a saved lifecycle final.

See [the native record and remaining handoff](docs/PERFORMANCE_COMMITMENT_NATIVE_V1_ACCEPTANCE.md).
Fresh evidence includes 328 native regression checks, a final focused run,
authenticated loopback acceptance and a Release build. Fictional sessions and
gates were cleaned up; the separate disposable database backup is retained.
This is the first native slice, not the whole Phase 3(e) handoff. Its remaining
handoff was native event nomination/completeness and private progress, followed
by selected following under Phase 3(d)'s strict cache rules. The weekly roadmap
above pauses organizer entry as the default next task; W1A and the feasible
fictional backend/native slices are now implemented. The current next task is
the authorized physical steps-source investigation, and the original acceptance
requirements remain historical. Release stays disabled. No
earlier migration, hosted state, provider, external delivery or live money was
changed. VoiceOver/device and real organizer/support/retention gates remain open.
