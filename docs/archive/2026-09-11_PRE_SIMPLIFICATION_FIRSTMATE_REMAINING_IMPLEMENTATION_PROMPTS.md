# First Mate prompt pack — GameTime remaining implementation

**Prepared:** September 8, 2026  
**Companion plan:** [GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md)  
**Required baseline:** `fm/gametime-beta-real-validation-c8` at `9ce9ea6` or its explicitly approved descendant  
**Project mode:** `gametime-beta`, local-only, merge autonomy off

These are natural-language captain messages for the First Mate primary session.
Do not run First Mate's internal `fm-*` scripts manually. Paste one wave at a time,
let First Mate create and supervise the appropriate ship/scout tasks, review the
result, and approve a local landing before starting a dependent wave.

The prompts are self-contained because the current plan files live in the dirty
original checkout and may not yet be visible to a worker based on c8. Once the plan
is safely committed into the canonical branch, workers should read it too.

## Before the first prompt

1. Start the First Mate primary from `/Users/user/firstmate-workspace`.
2. Run `/ahoy` (or `$ahoy` in Codex) and confirm these existing tasks are not
   duplicated:
   - `gametime-beta-real-validation-c8`
   - `gametime-beta-source-acceptance-b7`
   - `gametime-beta-release-readiness-b7`
3. Confirm the `gametime-beta` project is still local-only and yolo/merge autonomy
   is off.
4. Paste Prompt 0. Do not paste implementation prompts onto `main` while it still
   lacks c8.

## Prompt 0 — reconcile and adopt the c8 baseline

```text
For the registered local-only project gametime-beta, make the existing clean
continuation fm/gametime-beta-real-validation-c8 at 9ce9ea6 the only candidate
baseline for remaining Beta work. Do not create a duplicate implementation task
and do not start from origin/main at 577bc32.

First read AGENTS.md, PROJECT_MEMORY.md, CLAUDE.md,
docs/BETA_REAL_VALIDATION_ACCEPTANCE.md,
docs/BETA_REAL_VALIDATION_HANDOFF.md,
docs/BETA_FINISH_LINE_ACCEPTANCE.md, and the existing First Mate task records.
Inspect the dirty original checkout read-only and preserve every uncommitted file.

Dispatch a bounded independent review of 577bc32..9ce9ea6, concentrating on the
five c8 lifecycle/privacy fixes, SECURITY DEFINER functions, RLS/grants, session
revocation, exact request recovery, reopened consent, block/exit/removal/suspension,
and historical agreement preservation. Then run one fresh committed-candidate
gate: all portable SQL/Deno/core tests; all required Beta controllers without
skips; native units; the full historical UI suite; conformance; Debug, Staging,
and unsigned Release builds. Use unique disposable resources and do not reset any
retained stack or overwrite an xcresult.

Produce a collision map between c8 and the original dirty files. If everything is
green, present one guarded local landing proposal and wait for my explicit merge
approval. Do not merge, push, deploy, delete, rewrite migrations, or attribute the
dirty work without that approval. End with the canonical commit I should use for
the next wave and every remaining failure or unperformed gate.
```

**Wait for:** review result, skip-free gate, collision map, and the explicit merge
decision. Every later prompt should replace `9ce9ea6` with the approved descendant
commit if c8 lands.

## Prompt 0A — freeze the clarified product contract

```text
Create a local-only ship task named gametime-beta-contract-d9. Yolo is off. Base a
new isolated worktree on the exact canonical commit accepted by Prompt 0. Stop if
that commit is ambiguous. Do not modify c8, b7, the dirty original checkout, or any
retained database, preview, Simulator controller, result bundle, or DerivedData.

Read AGENTS.md, PROJECT_MEMORY.md, CLAUDE.md, the current decision ledger, the Beta
implementation/acceptance/handoff/physical/rollout documents, and the accepted
Prompt 0 report. Record these owner decisions as the authoritative remaining-work
contract:

- Beta has no GameTime watchOS app and no WatchConnectivity dependency. Apple Watch
  records activity into Apple Health; the GameTime iPhone app reads eligible
  Watch-origin HealthKit data and uploads only minimum normalized scoring facts.
- A paired physical Apple Watch is a launch requirement, not a blocker to the
  pre-hardware implementation waves.
- Beta community is one operator-published private cohort. User-hosted community
  challenges are a separately versioned future feature.
- Own progress may be current. Exact anonymous community aggregates are visible only
  when the disclosure cohort contains at least five joined, active, nonremoved
  participants and only from a server snapshot at least 15 minutes old. Under five,
  expose no exact numerator, denominator, participant count, qualifier count, total,
  or alternative differential signal. Five is a disclosure threshold, not the
  challenge outcome minimum.
- Beta planning target: 2,000 registered, 250 DAU, 100 concurrent sessions, 25
  requests/second burst, and one 250-person cohort. Long-term characterization:
  25,000 / 5,000 DAU / 1,000 concurrent / 150 requests/second / 10,000 community.
- All amounts remain visibly nonredeemable simulation.

Audit the GameTimeWatch target, GameTimeWatchShared code,
PhoneWatchConnectivityCoordinator, schemes, packaging, and candidate checks. Remove
the dedicated Watch runtime path from the active Beta product/build configuration,
or leave historical source inert when deletion would cause unrelated churn. The
iPhone candidate must not build, embed, launch, or depend on a Watch app or WCSession.
Preserve the iPhone HealthKit capability, historical data, and all existing
agreements.

Do not implement source semantics, publish a community, redesign UI, deploy, or open
any readiness gate. Run focused project/candidate checks, Debug/Staging/unsigned
Release builds as appropriate, documentation/link checks, and git diff --check. End
with a clean commit, exact changed files and checks, confirmation that all external
gates remain false, and unresolved decisions. Do not push or merge.
```

**Wait for:** the clean `gametime-beta-contract-d9` commit. Use that exact commit as
the common parent for Wave 1.

## Wave 1 — three independent foundations

Prompts 1–3 may run concurrently after Prompt 0A establishes the contract commit.
They own different surfaces. Tell First Mate to dispatch them together only if it
can prove nonoverlapping file ownership and unique disposable resources.

### Prompt 1 — candidate gate and CI hardening

```text
Create a local-only ship task named gametime-beta-candidate-gate-d9. Yolo is off.
Continue GameTime from the exact Prompt 0A contract commit. Build a repeatable,
release-shaped candidate gate; do not change product behavior or visual design.

Read AGENTS.md, PROJECT_MEMORY.md, CLAUDE.md, the c8 acceptance/handoff, and the
current CI plus scripts/beta-native-smoke.py. Parameterize simulator ID, Supabase
workdir/port base, controller port, DerivedData, xcresult/evidence paths, actor
namespace, and cleanup. A required controller skip must fail the candidate gate.
Never overwrite an existing result bundle or target a retained/original database.

Add guarded CI or self-hosted-CI lanes for the portable SQL/Deno/core gate,
GameTimeBetaLocal authenticated controllers, native units/UI, historical UI,
conformance, Debug/Staging/unsigned Release, an old-data forward-migration fixture,
minimum/current supported iOS, sanitizer-supported tests, and bounded flaky repeats.
Because no GameTime watchOS app will ship, do not build Watch features; assert that
the test-only Watch prototype is not embedded in Release.

Replace or version the legacy candidate checker. The new ChallengeV1 shell/client
must be the Release route over configured HTTPS; local fixture actors/clocks and
loopback helpers must be unreachable; no Stripe/payment path may be reachable; and
archive inspection must verify HealthKit/privacy-manifest/AASA configuration, no
Watch companion/WCSession, and the tested binary hash.

Preserve all old agreements, migrations, feature gates, and local-only behavior.
Do not push, deploy, change Apple/Supabase accounts, or alter signing. Finish with
one documented command that produces a skip-free candidate report, exact results,
and remaining environment-only limits.
```

### Prompt 2 — unchanged scale baseline and load harness

```text
Create a read-only scout task named gametime-beta-scale-scout-d9. Continue GameTime
from the exact Prompt 0A contract commit. Create an unchanged-system
scale baseline and reusable synthetic load harness. Own only scripts/challenge-load,
synthetic fixture support, performance-test configuration, and a capacity report;
do not edit challenge SQL or app behavior in this task.

Read the c8 acceptance/handoff, every challenge_*_v1 migration, current concurrency
driver, CI, and Supabase/Postgres best-practice guidance. Prove the current global
challenge_runtime singleton locking behavior rather than assuming it.

Generate deterministic synthetic shapes for 2,000 and 25,000 accounts plus at least
1,000,000 challenge-related rows, including history, corrections, reviews, reports,
blocks, exits, links, and due work. Seed only disposable local stacks using batched
inserts or COPY. Add scoped cleanup that can delete only its own synthetic namespace.

Capture EXPLAIN (ANALYZE, BUFFERS), locks, latency, rows/buffers, database size, and
failures for Home sections, detail/history, community discovery/join, ingestion-like
revision writes, links, reports, and worker discovery. Add k6-style authenticated
arrival-rate scenarios for ramp, spike, 100-session foreground burst, 250-person
join storm, worker/client contention, and a two-hour soak, but do not claim hosted
results from local Docker.

Beta target: 2,000 registered, 250 DAU, 100 concurrent, 25 requests/sec burst,
250-person community. Long-term design target: 25,000 / 5,000 DAU / 1,000 concurrent /
150 requests/sec / 10,000-person community. Do not run against production or any
unapproved hosted project. Deliver the measured unchanged bottleneck report and the
smallest evidence-backed redesign recommendations; do not optimize yet.
```

### Prompt 3 — pre-hardware Health contracts and fakes

```text
Create a local-only ship task named gametime-beta-health-seam-d9. Yolo is off.
Continue GameTime from the exact Prompt 0A contract commit. Prepare the source-backed
Health architecture while the owner sources a physical Apple Watch. There is no
GameTime watchOS app: activity recorded by Apple Watch will sync into the iPhone
HealthKit store, and the iPhone GameTime app will read and upload minimum challenge
facts.

Read the c8 source investigation, physical sessions, current Personal Health code,
WeeklyHealthSourceProbe, challenge policy matrix, and Apple HealthKit privacy,
authorization, query, observer, and background-delivery documentation.

Implement only framework-free versioned contracts, deterministic Health-store fakes,
and closed interfaces for four adapters: steps, Apple Exercise Time in integer
seconds, cumulative running distance in integer millimetres, and best qualifying
whole timed run using end-start elapsed seconds. Add the seven semantic readiness
states from docs/GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md if that file is present;
otherwise use unsupported, notConnected, checking, ready, noEligibleDataYet,
temporarilyUnavailable, and staleOrIncomplete. Permission completion or an empty
read must never mean ready or zero.

Cover limited history, manual/import/nil metadata, source/sync identities, overlap,
duplicate/out-of-order additions, deletion/lower replacement, late Watch sync,
boundary-straddling workouts, lock/query failure, account/terms switch, and exact
retry bytes. Keep routes, raw samples, source device names, and baselines on-device.
Keep every real source and real ingestion gate constrained off. Do not invent a
source allowlist, reconciliation policy, Exercise lineage, workout-boundary rule,
or timed tolerance before physical evidence. Do not touch the Watch target, deploy,
or request Health access. End with tests and the exact inputs the physical session
must decide.
```

## Wave 2 — ordered database scalability changes

Run Prompts 4 and 5 sequentially. Both change shared SQL functions; do not dispatch
them in parallel.

### Prompt 4 — replace the global mutex with scoped locking

```text
Continue GameTime from the canonical c8-derived commit and the completed unchanged
scale baseline. Remove the global challenge runtime mutex without weakening session,
admission, consent, capacity, privacy, or exact-retry invariants.

Use one new forward migration and focused tests; never edit applied migrations.
Split ordinary session validation from feature-gate mutation so reads take no global
FOR UPDATE lock. Scope locks to session/actor generation, link/token, lobby/capacity,
sorted participant actors, and per-member/source state. Document one deterministic
lock order and keep transactions short. Preserve immediate session revocation and
safe behavior during admission/processing pause.

Replace the worker's singleton-held multi-item loop with bounded due-work claims
using FOR UPDATE SKIP LOCKED, short claim transactions, idempotent attempts,
next_attempt_at, overdue/dead-letter visibility, and independent completion. A
paused/failing worker must not block reads, reviews, safe exits, or recovery.

Add repeated independent-session races proving unrelated accounts/challenges proceed
concurrently while same-actor admission, same-link redemption, same-lobby consent,
249th/250th/251st capacity, and session revocation remain correct. Assert no deadlock,
privacy leak, double allocation, wrong result, or lost exact response. Rerun every
new-domain and historical suite plus the load baseline. Do not deploy or tune hosted
pool settings. End with before/after lock waits and throughput, not just passing tests.
```

### Prompt 5 — query, projection, index, and retention-ready data shape

```text
Continue after the scoped-lock migration. Make challenge reads and lifecycle work
bounded at Beta and long-term cardinalities without changing product semantics.

Use a new forward migration plus focused native/client changes. Replace complete-
history UUID arrays, per-row detail projection loops, and unbounded lists with batched
section projections and stable keyset cursors. Add per-member latest observation /
result rows and small per-cohort rollups where needed; never store growing participant,
revision, notice, or allocation arrays in one row.

Run production-shaped EXPLAIN (ANALYZE, BUFFERS) before adding indexes. Add only
measured foreign-key, composite, or partial indexes for actor/history, due work,
community discovery, current revision, reports, and audit access. Optimize RLS with
indexed ownership and cached auth identity patterns without widening access. Record
read improvement and write/storage cost.

Add retention hooks/partition or purge seams for requests, source revisions, reports,
audit, cursor snapshots, and worker attempts, but do not choose retention durations
or delete real records before the owner/legal policy is approved. Synthetic cleanup
must remain namespace-scoped. Rerun correctness, migration-upgrade, privacy, and load
tests. Do not deploy or modify production data.
```

## Wave 3 — community Beta hardening

### Prompt 6 — selected private community contract

```text
Continue GameTime after the scoped-lock and bounded-query migrations. Finish the
existing c8 community implementation for the selected Beta contract; do not build a
public feed or redesign screens.

Beta scope: one operator-published private steps challenge. Own progress is exact and
private. Stranger names, totals, ranks, roster, and timestamps remain absent. When
the disclosure cohort has fewer than five joined, active, nonremoved people, return
null counts plus threshold state, never zero. At or above five disclosure-cohort
members, publish approved exact anonymous joined/qualified counts on a fixed cadence
at least 15 minutes delayed, with snapshot revision and as_of. Five controls
disclosure only; it is not the outcome minimum. Prove no alternate endpoint, cache,
internal lobby revision, error, ETag, or timing path exposes fresher counts. Use
fixed server snapshot buckets rather than a client timer or rolling event-time
reveal. Test 899/900/901-second boundaries and join/leave/removal transitions.

Require explicit Beta eligibility, confirmed age, an active nonsuspended account,
and the discovery switch for every catalog/detail path. Admission pause must not
disable already-authorized safe reads, exits, or reviews.

Support a tested capacity of 250 using per-member state and a narrow atomic capacity
reservation, not cohort-wide progress locks. Parameterize target, minimum, capacity,
window/timezone, and simulated amount; keep real publication/discovery off until
actual values are approved.

Fix safety scope: reports need an explicit challenge or account-global scope; a
challenge moderator must not see an unrelated report or impose a global suspension.
Separate removal from global support suspension, and add grant expiry/revocation plus
appeal/reinstatement state and races. Add quotas for discovery, exact lookup, link
redemption, join, reports, and repeated mutations.

Add a versioned publisher type/identity seam for future participant-hosted community
challenges, but grant publish only to the operator/service in Beta and test that
ordinary users cannot publish. Do not implement user hosting, public profiles, feed,
comments, reactions, or stranger standings. Rerun all 13 policies, historical tests,
privacy tests, and the 250-person load scenarios. Do not deploy.
```

## Wave 4 — hardware-dependent source acceptance

### Prompt 7 — resume the existing physical source task

Run this only when the Apple Watch is available. Keep the First Mate session
interactive; do **not** use `/afk` for this task.

```text
Resume the existing gametime-beta-source-acceptance-b7 task against the canonical
c8-derived branch. Do not create a new source-acceptance task. I will provide explicit
private opt-in naming the exact iPhone and paired Apple Watch before any installation
or Health read.

Follow docs/BETA_PHYSICAL_SESSIONS.md exactly. Raw samples, values, routes, timestamps,
source identifiers, and accuracy measurements stay volatile and on-device. Record
only the prescribed categorical conclusions.

Run phone-only and Watch-only steps, both-device overlap, manual/import, edit/delete,
late/offline Watch sync, locked/offline phone, permission change, app termination,
Exercise lineage, known-distance indoor/outdoor running, pause/resume, whole elapsed
duration, boundary-straddling workout, frozen timezone, midnight, and DST when
practical. Exercise first-sync and correction behavior at end, +24 hours, and +48
hours; the current fixture contract rejects a first fact after +24 hours unless an
unresolved fact already exists. Never infer denial or true zero from an empty Health
query.

Return one evidence table per metric and explicit proposed decisions for eligible
sources, reconciliation, corrections/deletions, trustworthy-miss limitations,
Exercise viability, whole-workout boundary handling, and timed distance tolerance.
Do not enable sources, upload data, score activity, deploy, or record raw evidence.
If evidence is insufficient, keep that source blocked and specify the next smallest
physical observation needed.
```

## Wave 5 — source-backed implementation

Prompts 8 and 9 depend on Prompt 7's accepted policies. Do not use fixtures to bypass
that dependency.

### Prompt 8 — real-source agreements and attested ingestion foundation

```text
Continue GameTime from the canonical branch and the owner-accepted physical source
policy memos. Add forward-only real-source agreement/policy versions and a minimum-
data authenticated/attested challenge ingestion path. Preserve every fictional and
historical agreement; never edit applied migrations.

Bind each request to actor, challenge, agreement version, terms digest, source-policy
version, frozen window, monotonic observation revision, prior revision, observed-at /
freshness facts, canonical replacement value or deleted/unresolved state, and exact
idempotency ID. Values may decrease. Exact retries return the original response;
changed payloads conflict. Revoked/stale sessions, wrong actors, wrong terms/source,
out-of-window facts, replay, client-authored completeness/qualification/results, and
late disallowed revisions fail closed.

Reject and test raw Health samples, routes, workout/source device names, baseline
history, client winners, and allocations. Reuse reviewed App Attest patterns only
where their production identity and replay contract actually match; do not retrofit
the historical Personal endpoint. All source switches remain independently default-
off. Add RLS/least-privilege, lower/deletion, concurrent revision, response-loss,
cutoff, and privacy-safe logging tests. Run advisors and the complete candidate gate.
Do not deploy or enable hosted ingestion.
```

### Prompt 9 — four Health adapters and native source-backed journeys

```text
Continue after the real-ingestion foundation. Implement the four accepted iPhone
HealthKit adapters and connect them to the Beta native shell. There is no GameTime
watchOS app; Apple Watch activity is consumed only after HealthKit syncs it to iPhone.

Use the accepted source-policy versions exactly. Implement competitive source-aware
steps, Apple Exercise Time in integer seconds, cumulative eligible whole-running
distance in integer millimetres, and the best qualifying whole timed workout using
end-start elapsed seconds including pauses and the accepted distance band. Do not
sum overlapping phone/Watch data, prorate workouts, infer segments, upload routes, or
reuse permissive historical Personal rules unless the accepted memo explicitly says
so.

Connect seven-state readiness, protected account/terms/source-bound replacement
cache, durable exact upload retry, on-device-only goal suggestions, per-type observer
queries, foreground recovery, and background delivery. Always finish HealthKit
observer callbacks promptly; locked/unavailable reads stay unresolved. Fence stale
async results and permit lower/deleted revisions and late Watch sync.

Before final consent or join, require positive eligible Watch-origin history: at
least one selected-source record in the prior 30 days for steps, Exercise Time, and
cumulative distance, and at least one comparable selected-source whole workout in
the prior 90 days for timed running. Treat this only as a source-availability signal;
it never proves full authorization or converts an empty read to zero.

For each metric prove creation readiness, progress, downward/deletion correction,
late sync, source loss, provisional notice, review, and immutable final through real
client/server code. Rerun all dependent friend/personal/leaderboard policies plus
historical Personal regressions. Keep Release/hosted source flags off until separate
acceptance. Do not deploy or request distribution.
```

## Wave 6 — hosted preparation and Beta load

### Prompt 10 — prepare hosted staging without deploying

```text
Continue GameTime from the fully tested source-backed local candidate. Prepare a
reviewable hosted-staging change set and runbook only; do not provision, deploy,
publish links, change accounts, or send messages without a separate captain approval.

Reconcile the existing gametime-beta-release-readiness-b7 task. Inventory the exact
required Supabase project/region/compute/pool, Apple team/Release bundle/Sign in with
Apple/associated domain, secrets and App Attest environment, operator identities,
support route, retention/deletion policy, scheduler, alerts, source/admission /
processing/discovery gates, rollback, credential rotation, and synthetic-data purge.
List every missing owner input instead of inventing values.

Prepare forward migrations/configuration with explicit Data API exposure, RLS and
least privilege. Hosted fixture actors/clocks must be impossible. Use transaction-
mode pooling for short-lived serverless traffic and size it from observed usage.
Update any observability tooling away from the Supabase logs.all endpoint removed on
2026-09-23. Keep Edge work within current memory/CPU/wall/log limits and put durable
work in idempotent database jobs.

Deliver a dry-run migration/rollback plan, secret-free environment matrix, monitored
runbook, and exact approvals needed for execution. No deployment is authorized by
this prompt.
```

### Prompt 11 — execute authorized staging and Beta-A stress acceptance

Paste only after explicitly approving the exact staging target and test budget.

```text
Use only the exact nonproduction staging project I have approved. Never target
production. Verify the project identity before every mutation and retain a scoped
synthetic-data manifest and purge plan.

Apply the reviewed candidate, configure only approved gates/credentials, and run
hosted multi-account auth/RLS/link/source/worker recovery smoke tests. Then run the
Beta-A load suite: 2,000 registered, 250 DAU shape, 100 concurrent sessions, 25
requests/sec ramp, 50 requests/sec five-minute spike, 100-session foreground burst,
249th/250th/251st community join race, two-hour soak, worker outage/backlog replay,
JWT expiry, transient 5xx, query timeout, database restart, pool pressure, and
duplicate/out-of-order/lower source revisions.

Required thresholds: zero privacy/invariant/wrong-result/lost-write/cap/deadline
failures; unexpected HTTP failures below 1%; read p95 <=500ms and p99 <=1500ms;
mutation p95 <=800ms and p99 <=2000ms; zero deadlocks; no unrelated global lock wait;
p95 app lock wait <=100ms; at least 30% connection headroom; normal work starts
within 60s; outage backlog 95% drains within 5m and 100% within 15m; no k6 dropped
iterations; stable two-hour resource/latency profile.

Observe pg_stat_statements, connections/waits, CPU/memory/I/O/cache, dead tuples /
autovacuum, database/index growth, Edge errors, and worker lag without logging Health
totals, routes, source/device IDs, usernames, amounts, review text, tokens, or signed
payloads. Stop on target ambiguity, privacy failure, uncontrolled cost, or production
identity. Purge only manifested synthetic data. Deliver the highest safe envelope,
bottleneck, cost, recovery time, and every failed threshold honestly.
```

## Wave 7 — final bug hunt and release acceptance

### Prompt 12 — adversarial release-candidate audit and fixes

```text
Against one immutable source-backed candidate, run a parallel read-only bug hunt
across database/RLS, native/session/cache, Health/source correction, community/privacy,
worker/operations, and migration/release packaging. Consolidate findings before any
fixes. Prioritize P0 privacy/wrong-result/consent/data-loss and P1 exit/recovery /
source/session/lifecycle defects.

After I review the findings, dispatch bounded nonoverlapping fixes, each with a
regression at the smallest layer plus the affected end-to-end journey. Re-run the
entire skip-free candidate gate, migration upgrade, all 13 source-backed policies,
Beta-A hosted load regressions where relevant, and signed-device packaging. Confirm
no GameTime watchOS app is embedded and Watch-origin activity still flows through
iPhone HealthKit.

Inspect the exact Release archive by hash. Confirm the new hosted HTTPS Beta shell is
active and that Stripe/payment, fixture actor/clock, Watch app, and WCSession paths
are absent; verify the intended HealthKit entitlements, privacy manifest, and AASA.

Do not redesign the app, delete legacy data, deploy a new candidate, distribute,
recruit, or enable money. Finish with a P0/P1/P2 ledger, exact tests, residual risk,
and a go/no-go recommendation. No open P0/P1 may be recommended for TestFlight.
```

### Prompt 13 — interactive physical, human, and operations gate

Do not run `/afk`; the owner, devices, test adults, and operators must participate.

```text
Resume the existing source-acceptance and release-readiness tasks; do not duplicate
them. On the exact approved signed Release candidate and staging environment, guide
the owner through final iPhone/Apple Watch source sync/correction/finality, physical
VoiceOver, Dynamic Type, reduced motion, Voice Control/Switch Control, offline /
locked recovery, account switching, link-before/after-sign-in, and voluntary exit.

Run two-person and six-person comprehension sessions. Each adult must explain roster,
own targets, consent/reconsent, what Health data counts, missing/unresolved behavior,
ties, corrections, exits, review deadlines, community privacy, and simulated money
in their own words. Test the monitored support route only with explicit permission.
Exercise operator pause, report/removal/suspension boundaries, worker outage/replay,
credential rotation, rollback, and source kill switches.

Record categorical results only—no Health values, routes, usernames, amounts, review
text, tokens, or private screenshots. Do not flip readiness gates merely because a
script passed. Stop and report every failed/unperformed gate. Do not upload to
TestFlight, invite testers, or publish anything until I give separate distribution
and recruitment authorization after reviewing the final gate ledger.
```

## Optional post-Beta prompt — long-term B capacity

```text
After Beta-A is stable, run the existing nonproduction load suite at the long-term B
envelope: 25,000 registered, 5,000 DAU shape, 1,000 concurrent sessions, 150
requests/sec burst, one 10,000-person cohort, and a four-hour soak. Preserve the same
privacy/invariant requirements and classify every threshold failure. Do not change
production or silently raise hosted compute. First measure; then propose the smallest
query/data/compute change with cost. A long-term failure must not be relabeled as a
Beta-A failure if the smaller envelope still passes, but the capacity report must say
the highest proven envelope and bottleneck.
```

## How to operate the waves

- Use `/ahoy` before each wave to reconcile completed work and open captain decisions.
- Paste one complete prompt, not fragments. Let First Mate classify ship vs scout and
  create isolated worktrees.
- Parallelize only Prompt 1/2/3 and later clearly nonoverlapping read-only audits.
  Serialize migrations that replace shared challenge functions.
- Approve local landings in dependency order. A downstream worker must name the exact
  landed parent commit, not merely “latest main.”
- Use `/afk` only for tasks with no expected hardware action, account approval,
  external target selection, or captain decision. Use `/ahoy` when returning.
- Keep Prompt 7 and Prompt 13 interactive. First Mate cannot manufacture physical
  source evidence or human comprehension.
- Never paste secrets, Health values, routes, private profiles, or signed payloads
  into First Mate. Provide exact device identities privately only when the existing
  physical task asks for the opt-in.
- Never run `scripts/db-test.sh` directly in c8 or another preserved checkout, and
  never reuse, stop, or reconfigure the retained c8 5832x Supabase stack, preview,
  or Simulator controller. Each worker owns unique disposable ports and artifacts.
- A worker saying “tests pass” is not enough. Require exact commands, counts, skipped
  tests, environment identity, artifact paths, limitations, and preservation checks.
- Do not run hosted load until the exact nonproduction project and cost are approved.
  Coordinate heavy load with Supabase support when the selected plan/event warrants
  it.
- No prompt grants permission to deploy, distribute, recruit, delete user data, or
  enable real money.
