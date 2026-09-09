# GameTime: current state and proposed finish-line roadmap

September 9 remaining-work authority is [D135](BETA_REMAINING_WORK_CONTRACT.md).
The milestone order and “what to do next” below are the historical finish-line
plan. Paired Watch is required for launch but does not block authorized
pre-hardware waves. D135's private operator cohort, delayed disclosure and
workload targets supersede less specific community/capacity statements below.
Prompt 0A does not execute M1–M6, later prompts, publication or any external gate.

Assessment: September 7, 2026, against `main` at `577bc32`, the current working
tree, native/backend source, acceptance records, and the final GitHub checks for
PR 17. This is a proposed execution sequence for the adopted
[Beta 1 contract](BETA_IMPLEMENTATION_PLAN.md), not a change to that contract or
authorization to implement, deploy, distribute, recruit, delete data, or move money.

## Where the app stands

GameTime has a substantial tested engineering foundation, a specific approved
beta product, and a promising proposed visual direction. The integrated app
described by that beta plan is still to be built. The normal native shell
continues to expose the older seven-day Personal steps experience; newer friend,
community, and running-goal journeys are explicit local development opt-ins.

The recent work has made the destination much clearer. It has not yet moved
those new products into the main app or connected them to accepted real-world
activity results. This is meaningful product-definition and design progress,
with substantial integration and source-validation work ahead.

### What changed recently

- The tracked uncommitted diff is **eight Markdown files, 203 additions and 31
  deletions**, with no staged changes and no Swift, TypeScript, SQL, or project
  configuration changes. It aligns project authority around D134.
- The new, untracked `BETA_IMPLEMENTATION_PLAN.md` specifies the new products,
  consent, source rules, lifecycle, links, limits, safety, and acceptance matrix.
- The latest design work contains **four Clubhouse/Scoreboard concepts and three
  Matchday concepts**, plus research, exact prompts, review pages, and revisions.
  Matchday covers Home, a friend leaderboard detail, and a personal timed goal.
- File modification times place the design work around **2:49–3:44 p.m. Central
  on September 7**; most planning edits are from the previous evening. These
  timestamps describe the saved files, not a complete authorship/session history.
- Matchday is the latest **recommended design exploration**, not an adopted
  design decision or a functioning native interface. Its charts contain known
  raster inaccuracies; the implementation must plot exact values.

The previous implementation was merged as [PR 17](https://github.com/m1jenkins/GameTime/pull/17)
on September 6 at 4:42 p.m. Central. A fresh GitHub read for this assessment
confirmed four passing checks: Database, Edge Functions, Client Core, and iOS
product/conformance; Supabase Preview was skipped. The
[acceptance ledger](WEEKLY_LOCAL_ACCEPTANCE.md) contains extensive dated SQL,
Deno, Swift, UI, and authenticated local HTTP evidence. Its intermediate test
counts should not be relabeled as new runs or as Beta 1 coverage.

## What we have made, and what remains

| Area | Implemented now | Remaining for the adopted beta |
| --- | --- | --- |
| Main app | Sign-in/account scaffolding; Personal steps creation, Health reads, progress, history, and sandbox/test behavior | New Home action inbox; unified Challenges creation/join/history; updated You and readiness; replacement navigation |
| Friend challenges | Fictional same-event 5K duels and weekly 2–5-person steps-goal backend/native journeys | 2–6-person lobbies, each person's own target proposal, roster freeze and reconsent, 1–30-day windows, four metrics, target-free leaderboards |
| Personal performance goals | Separate 28–90-day fictional 5K contract, proof/progress/following backends, initial native agreement/result/review slice | New four-metric, 1–30-day goal contract and complete source-backed native attempt/progress journey |
| Community | Fictional weekly steps publication/join/progress/review, with private participant projections | New-contract cohort, selected operator settings, new admission rules, accepted real-source results and operating process |
| Agreement and result machinery | Immutable terms, explicit consent, participant locks, durable exact retries, append-only correction, notices/review, safe exits, final results and simulated allocation | Adapt these patterns into the new versioned domain; implement different goal, leaderboard, exit and deadline semantics |
| Health and other metrics | Existing Personal Health reader; unwired investigation helper; pure metric fixtures; private distance notebook | Four accepted adapters, reconciliation, readiness, on-device suggestions, minimal attested ingestion, downward corrections/deletions, credible result handling |
| Identity and safety | Exact username lookup, private graph/blocking, actor/session fences, support/reporting patterns | 21+ confirmation; reusable access-granting lobby links; new-product moderation/removal/suspension; staffed support workflow |
| Visual system | Native GameTime theme, orange/neutral palette, system numerals and monograms; seven new raster concepts | Native Matchday components; creation, consent, loading, offline, review, result, tie, exit, community and accessibility states |
| Operations | Local worker and extensive disposable test infrastructure; historical hosted Personal work | New hosted configuration and scheduler, operator access, monitoring, recovery drills, privacy/terms, distribution acceptance |

There is no defensible percentage-complete estimate: the old product and trials
have significant implementation, while the adopted beta has different contracts
and an unresolved source-feasibility gate.

### Reuse the foundation without changing old agreements

The weekly implementation cannot become Beta 1 through renamed screens and one
larger roster limit. Concrete differences include:

- Weekly creator-entered targets become participant-proposed targets followed
  by a complete frozen roster and everyone's consent.
- Weekly seven-date steps rules become thirteen versioned policies: eight friend
  combinations, four personal goals, and one community steps goal.
- Historical weekly exits or unresolved friend data refund the whole group.
  New friend goals may continue after exclusion/refund while at least two
  resolvable participants remain. An unresolved leaderboard voids.
- Historical weekly missed notice deadlines can refund a group. Beta processing
  delay extends finality and must preserve full review windows; delay alone does
  not void the challenge.
- Exercise fixtures use thousandths of a minute; the adopted beta stores integer
  seconds. Timed beta goals use conservative whole elapsed seconds and strict
  under-target comparison.

Build the new `challenge_*_v1` domain required by the adopted plan. Reuse request
recovery, locking, canonical terms, privacy fences, correction/review patterns,
test harnesses and visual components where their meanings match. Keep applied
Personal, Solo, charity, duel, commitment and weekly records intact.

## What “finished” should mean

**First visible milestone:** a complete local native friend steps-goal journey
in the new design, including consent, corrections, review, safe exit and final
simulation. This is an internal development milestone.

**Beta 1 finish line:** the approved thirteen-policy product, all four physical
source policies accepted, integrated Home · Challenges · You, safe onboarding
and links, operating support/review, accepted hosted recovery, and an authorized
TestFlight build. All amounts remain explicitly nonredeemable simulation.

**Product validation:** an authorized small cohort actually completes challenges
and reviews. Observe understanding, fairness, privacy, pressure, support needs,
and voluntary return. Code and mockups cannot establish demand.

**Funded launch:** a later product milestone requiring selected funds flow,
recipients, fees/limits, provider and applicable legal/platform clearance,
financial controls, and separate implementation and acceptance. Existing Stripe
sandbox work does not provide deposits or participant payouts for this model.

## Proposed implementation sequence

### M0 — Preserve the baseline and make the next task unambiguous

Deliver a documentation/design checkpoint separate from application changes.
Keep D134 as product authority; retain the visual proposal's status and original
assets. Reconcile stale “merge PR 17” language and distinguish historical W1–W4
tasks from this proposed sequence. Inventory reusable code and test ownership.
No broad legacy rewrite or cleanup is needed to start.

**Done when:** another developer can identify the current contract, working
baseline, proposed design, and next bounded task without following obsolete
phase instructions. This assessment itself makes no commits.

### M1 — Resolve physical-source feasibility early

Start with the already-described default-off Debug steps investigation on the
owner's explicitly opted-in iPhone and paired Watch. Add an accessible local
investigation journey around the existing probe, exclude it from Release, and
keep raw records on-device and disconnected from scoring/uploads/telemetry.
Run the documented walking, manual/import, overlap, edit/deletion, late-sync,
locked/offline, permission-loss, account and timezone cases with human actions.

Then investigate Exercise lineage and cumulative/timed running. Measure
whole-workout distance accuracy, pauses and elapsed time; obtain the owner's
evidence-based timed-distance tolerance. Record which observations support
success, uncertainty and any confirmed miss. Neither an empty successful query,
a positive readiness sample, nor device attestation proves complete activity.

**Done when:** every source has a recorded feasible policy and limitations, or a
documented blocking finding. If any source cannot support the adopted rules,
keep it disabled and bring the specific contract/scope decision to the owner.
Do not silently ship a steps-only beta: all four sources are a current
distribution requirement. M2–M4 can advance using explicitly fictional data
while investigation is underway.

### M2 — Build the new challenge contract and backend core

Create versioned policy types/evaluators and a separate challenge aggregate.
Implement canonical units, scheduled 1–30-full-day windows with 2–30-day lead,
integer-cent simulated amounts, target-free leaderboard validation, participant
targets, lobby versions, roster freeze, fresh consent, and exact-request recovery.
Implement durable participant locking and the aggregate three-unsettled limit,
per-metric friend overlap limit, and community exception from the start.

Implement the shared lifecycle and new result semantics: +24-hour initial sync,
+48-hour corrections, provisional publication service level at +72 hours,
48-hour review from actual notice, and 72-hour resolution from actual filing.
Preserve safe reads/exits/reviews when admission is paused. Keep separate gates
for admission, source policies, ingestion, processing and discovery.

**Done when:** persisted local fixtures prove two- and six-person friend goals,
reconsent, concurrent admission, response-loss retry, corrections, exclusions,
full delayed review windows, immutable finals and conserved simulation. Add all
thirteen policy cases as breadth lands; old regression contracts still pass.

### M3 — Finish one native journey in the new shell

Build Home · Challenges · You behind a new local opt-in. Translate Matchday's
event cards, compact terms, monograms and system numerals into reusable native
components. First deliver a **friend steps goal**, using exact usernames to
reach the existing authenticated-account path: create lobby → propose each
target → approve roster → freeze → everyone reviews/consents → scheduled/active
progress → correction → provisional result → review → final → history.

Also complete cancellation, leave, unresolved-data outcomes, blocked/suspended
access, expired sessions, account switching and durable retry. Home must order
actionable reviews/consents before active progress and preserve permitted
last-known sections after partial failures. Stale social content must still
clear on account/auth changes, revocation or expiry.
Define stable cursors, server time, projection revision and per-section
freshness; stale actions must still require current authorization. Preserve the
existing held-authentication race regression when building the new store.

**Done when:** actual native clients and separate local Auth actors complete
two- and six-person end-to-end HTTP journeys, including one lost response and
one delayed result review. Verify exact data charts, compact devices, large
text, basic VoiceOver traversal, reduced motion, light/dark and loading/error
states as components are introduced. Keep the legacy default shell usable.

### M4 — Complete the product matrix and entry journeys

Extend the same new aggregate across friend goals/leaderboards, all four
personal goal formats, and one private community steps cohort. Finish the native
metric/format/window/amount selectors, own target proposals, local suggestion
presentation, leaderboard ties/co-winners, goal allocations and full history.
Use disabled fixture configurations until real-source policies are accepted.

Implement 21+ confirmation and reusable invitation links end to end: sign-in →
age confirmation → beta access → pending lobby request → creator selection →
consent. Add the hosted-link association configuration for later deployment.
Test the 20-account/30-day ceilings, concurrent last-slot redemption, idempotency,
revocation and rejected entrants retaining previously granted beta access.
Redemption must not silently create friendship or roster membership.

Community exposes own progress and anonymous counts only. Select its target,
capacity/minimum, timezone and simulated amount after source/comprehension
evidence; leave publication disabled until those settings are approved.

**Done when:** all thirteen policies and each product's create/join/leave/review
journey have server and native coverage; the UI never invents leaderboard
targets or exposes stranger standings. New reporting, blocking, operator removal
and audited suspension are implemented for these entry and participation paths.
Keep an executable per-policy ledger covering readiness, normalization,
qualification/ranking, corrections, review, exit and allocation. Include all-miss
and integer-remainder conservation, strict timed equality, DST/window boundaries,
and a previous challenge in review overlapping a future accepted challenge.

### M5 — Connect accepted real activity and finish progress

Depends on M1's policy findings and the new contract. Build four adapters,
selected-source positive-read readiness, on-device-only goal suggestions,
minimum-data attested ingestion, replay protection, source binding and correction
revisions that represent lower values and deletion. Preserve routes and baseline
history on-device. A client may not declare itself complete, verified or final.

Use steps counts, Exercise seconds, running millimetres and conservative whole
elapsed seconds. Timed goals are strictly under the target and use eligible
whole workouts, not a sum or inferred segment. Preserve exact frozen dates
through travel/DST and selected-source freshness for each person.

For charts, show the owner's history and agreed shared totals as the safe
initial presentation. Comparative friend historical series require a defined
minimum-data/consent contract; the raster proposal does not grant that access.
Native plots must use exact samples, labels and dates.

**Done when:** real-device observations travel through the new authenticated
protocol into progress, correction, review and final results, including
downward edits, late Watch sync, permission/source loss and unresolved outcomes.
Record physical evidence separately from fixtures and Simulator passes.

### M6 — Make the app operable and human-usable

Finish a minimal owner-operated publication, moderation, suspension and review
workflow with scoped credentials, assigned reviewers and audited actions.
Add durable Home notices, overdue-work monitoring, bounded retries, scheduler
recovery and an admission pause that preserves safe recovery. A polished general
admin console is not required for this small beta.

Run the full policy/concurrency/privacy matrix, native/HTTP acceptance and
historical regressions from a committed candidate using disposable stacks.
Conduct actual agreement/result comprehension, VoiceOver, Dynamic Type,
assistive-control, reduced-motion, offline, account-change and voluntary-exit
checks. Update the product's privacy/terms and verify the monitored support route.
If pilot instrumentation is added, keep it default-off, revocable and free of
Health totals, routes, usernames, simulated amounts and review text.

**Done when:** a release candidate has reproducible automated evidence, recorded
human acceptance, all four physical sources accepted and a tested operating
runbook. There are no unresolved defects preventing fair results or safe exits.

### M7 — Replace legacy navigation and prepare hosted acceptance

After replacement local and physical acceptance, remove legacy Personal
creation/navigation/client refresh/visible history from the new shell. Preserve
applied agreements/schema and accounts. Inventory any proposed non-production
data cleanup and prepare an audit export/runbook; deletion is optional and
requires its own explicit destructive approval. It is not a prerequisite for
retiring the UI.

Prepare reviewed hosted migrations/functions, environment configuration, link
hosting/association, source and admission switches, operator credentials,
scheduler/alerts, release configuration and rollback/disable instructions. After
explicit hosted approval, deploy and run multi-account privacy, session expiry,
ingestion, review and scheduler outage/replay checks on the actual environment.
Existing loopback restrictions need deliberate new-product hosted wiring.

**Done when:** the new release shell is accepted; hosted end-to-end and recovery
evidence is recorded; all gates are known and reversible; the TestFlight candidate
matches the approved contract and simulated-money disclosure.

### M8 — Authorized TestFlight and a real product-validation round

After distribution/recruitment authorization, release to a small controlled
cohort and run a proposed two-round study updated for 2–6-person groups, new
formats and the community privacy contract. Choose its exact cohort, durations
and success criteria before recruitment; old weekly pilot defaults are history.

Observe whether people understand what counts, can consent and leave easily,
trust the results, need support, and voluntarily choose another challenge.
Use the findings to prioritize product fixes before broader rollout or a funded
proposal. Push, photos, Garmin, public betting, automatic rematches and money
movement remain outside this Beta 1 plan.

**Done when:** the agreed study has actually run and produced an evidence-based
continue/change decision. Passing CI does not satisfy this milestone.

## What to do next

The next implementation task should be M1's bounded physical steps investigation,
with explicit owner participation for the device actions. The next product-code
slice should be M2/M3's new friend steps-goal journey. The two workstreams can
proceed independently until real-source integration requires the source result.
Investigate the other three sources early enough to expose blockers before
completing every screen.

Avoid more standalone fictional feature families, a fresh fixed-5K build,
large-scale legacy cleanup, or another broad design exploration before this
journey works. Use Matchday as the proposed implementation starting point and
resolve visual details in functioning native screens. It remains a recommendation.

A calendar forecast would be more credible after the physical investigation and
first complete journey establish feasibility and actual delivery pace. The
milestones above provide observable completion criteria now.

## Evidence and review limits

- [Current shell](../ios/GameTime/GameTime/AppShellView.swift),
  [runtime gates](../ios/GameTime/GameTime/AppConfiguration.swift),
  [weekly native flow](../ios/GameTime/GameTime/WeeklyViews.swift), and
  [weekly store](../ios/GameTime/GameTime/WeeklyStore.swift).
- [Existing lifecycle](../supabase/functions/_shared/weekly-lifecycle.ts),
  [local worker](../scripts/weekly-lifecycle-local-worker.ts), and
  [attested legacy ingestion](../supabase/functions/ingest-metrics/handler.ts).
- [Source investigation and unperformed physical matrix](WEEKLY_SOURCE_METRICS_ACCEPTANCE.md),
  [weekly evidence](WEEKLY_LOCAL_ACCEPTANCE.md), and
  [new Beta contract](BETA_IMPLEMENTATION_PLAN.md).
- [Matchday handoff](../outputs/design/2026-09-07-matchday/README.md),
  [earlier concepts](../outputs/design/2026-09-07-mobbin-direction/README.md), and
  [existing theme](../ios/GameTime/GameTime/CompetitiveTrustTheme.swift).

This assessment reviewed source, diffs, design images and recorded acceptance,
and freshly checked PR 17's merge/check status. Four read-only review roles
covered native intent, security/privacy, reliability, and contracts/coverage.
No native build, application test suite, physical investigation or hosted-runtime
check was rerun here. New deliverables are this proposed roadmap and its local
visual review; existing code, plans, designs and runtime state are preserved.
