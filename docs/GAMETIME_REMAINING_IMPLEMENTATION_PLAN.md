# GameTime remaining implementation plan

## Current local handoff — P6 complete

P6 is locally completed on `codex/private-community-p6`, implementation
`05f405c24453fe6743ece994d646058958bfdbb2`, based on P5
`e16cff4b3beaa7bcce95db6b0e82eedaa94865fa`. The dedicated checkout is
`/private/tmp/gametime-p6-20260912/GameTime`. Read the
[P6 completion report](../outputs/reports/2026-09-12-p6-completion.md) for scope,
actual checks, retained failures and limitations. Original/product/P4/P5 branches
are preserved. **P7 is unstarted and needs explicit physical-device opt-in.**
Earlier status records below are historical; do not restart completed P4/P5/P6
or enable hosted/source/money/distribution gates from this local completion.

Updated September 11, 2026 after the owner asked to simplify the work and code
where useful. Use the [prompt pack](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md)
for one task at a time. The [previous plan](archive/2026-09-11_PRE_SIMPLIFICATION_GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md)
is historical.

The objective is a usable, correct local Beta, followed by source and release
acceptance. Full release verification is no longer a prerequisite for each
local task. Missing correctness checks for the change itself still prevent
accepting that change. This cleanup does not mark unfinished work passed.

## Reuse the current work

These are observed September 11 identities. Recheck the branch before starting;
they are not instructions to reset another checkout.

| Work | Disposition |
| --- | --- |
| Original /Users/user/Documents/GitHub/GameTime | Dirty at 577bc321e72750976e2e8027680387707070b0e3. Preserve it; it is not the current Beta code baseline. |
| Current product /Users/user/firstmate-workspace/projects/gametime-beta | Main affd367ebe5411969fd5b7abd45629e0746a5a7d: accepted Cobalt UI over a18f00fa19ac95f946c4686ba3b6a068064d797b. Normal challenge transport is closed; demos do not create live friend challenges. |
| Prompts 0, 0A and 3 | Implemented. Preserve c8, Watch retirement and the Health contracts/fakes. |
| Prompt 2 | Reviewed baseline at e3b6b92c48695abfb6f5ecbc0a60ec84a3f99dc0 in fm/gametime-beta-load-prep-e2. Reuse scripts/challenge-load, docs/load and its published evidence without importing unrelated gate changes. |
| Prompt 4 | Preserved partial d0742eac0fab4d182338dc75d5aacb77658e0c09 remains in pool 9. Completed and locally verified at b67776c8b3fc1173f4e7f44bd794db9f81b2b7a0 on isolated codex/lean-beta-preparation, based on 201d7459bad293c9f942de067c1b6afd99b58479. Product main has not moved. |
| Gate recovery | ff71ee28b05456dfa487d48ddd044105c9bdab37 was cancelled, never accepted. Retain the evidence; do not restart its infrastructure or make it a local product dependency. |

The original dirty diff contains 27 modified documents, 10 native source files,
nine tests/smoke scripts and 52 deleted design/documentation files. Most code
edits are copy changes, including removed disclosures with stale UI assertions.
Review useful changes individually; do not apply that whole patch to Cobalt or
restore/delete unrelated assets during cleanup.

Current UI evidence lives in the current product's
docs/design/crisp-cobalt/DEFAULT_UI.md and VERIFICATION.md. Existing P4 evidence:
[task report](/Users/user/firstmate-workspace/data/gametime-beta-scoped-locks-p4/report.md).
Recovery disposition:
[closure](/Users/user/firstmate-workspace/data/gametime-beta-verification-recovery-e10/captain-closure-20260911.md).
The preparation report for this cleanup is
[here](../outputs/reports/2026-09-11-beta-simplification.md).
Final P4 source, validation and limitations are in the
[completion report](../outputs/reports/2026-09-11-p4-completion.md).
P5 is now locally completed at `e0a94bd793e4720ae04795760d614b049005618b` on
`codex/bounded-queries-p5`, based on completed P4 `369e7b90dfeb74314244a923a87864e368348412`.
See [P5 measurements/checks and handoff](../outputs/reports/2026-09-11-p5-completion.md).
P6 remains unstarted. Product main and the retained P4 checkout have not moved.

## Product requirements stay intact

- Friend goals/leaderboards support 2–6 people; personal commitments are goal-only.
  Preserve all 13 policies, consent, revocation, admission limits, exact retries,
  review time, privacy, safe exits and historical agreements.
- The iPhone reads eligible Watch activity through HealthKit; there is no
  GameTime Watch app. All four real sources need physical acceptance. Empty reads
  never prove zero, readiness or a missed goal.
- Community is one private operator-published steps cohort, targeting 250 people.
  Own progress may be current. Exact anonymous counts require five joined, active,
  nonremoved members and a server snapshot at least 15 minutes old. Below five,
  expose no exact or differential counts. Five is not the outcome minimum.
- Amounts remain nonredeemable simulation. Keep that clear at consent/results.
  Source policies and publication settings remain evidence-dependent decisions.

## Proportionate local acceptance

Use installed tools, a new owned disposable database where needed, focused tests
and one concise review. Preserve other stacks, devices and artifacts. Do not build
another allocator, sandbox, evidence-packet framework or recurring review process.

| Change | Local checks |
| --- | --- |
| SQL/session/worker | Fresh migration application; affected domain tests and actual-session races; an old-data upgrade/historical smoke. Shared helpers may justify one full portable SQL pass. |
| Native/models/UI | Build the affected target and test its journey. Exercise minimum iOS for compatibility-sensitive APIs/layout changes. |
| Queries | Compare the same fixture/query before and after; test ownership, pagination and cursor behavior. |
| Docs/copy | Check links, meaning and diff; run existing relevant checks when executable copy changes. |

Test the final source. Fix concrete findings and rerun affected checks; earlier
passes do not cover later SQL edits. Repeat races a small bounded number of times
where order matters. Preserve actual failures and missing checks.

Use the prior local task's 90-minute validation budget and 20-minute command limit
as working defaults. After the same environment obstacle twice, stop that check,
record it once and continue independent work. An untested safety invariant stays
open. Do not turn a feature task into general infrastructure repair.

The full native/historical matrix, both runtimes, sanitizers, archive checks and
long soak belong at integration/release milestones. The accepted minimum-Simulator
policy is the lowest compatible installed iOS 18.x: observed 18.6 / 22G86 / arm64,
with 26.5 as the observed current lane. Deployment remains 18.0; exact 18.0 runtime
behavior is untested.

## Remaining order

| Prompt | Deliverable | Dependency |
| --- | --- | --- |
| 4 | Completed locally: scoped locks, durable bounded claims and cancelled-work fix | Isolated result above; not landed on product main |
| 5 | Completed locally: bounded history keysets and measured query/index improvements | Isolated P5 result above; not landed on product main |
| 6 | Community disclosure, 250 capacity, moderator boundaries and quotas | P4/P5 accepted locally |
| 7 | Physical source decisions | Device opt-in and owner participation; may accompany unrelated local work |
| 8 | Versioned minimal-fact ingestion | Accepted source policies |
| 9 | Four adapters and usable native friend/personal journeys | 8 and accepted sources |
| 10 | Hosted configuration/operator preparation | Local integration ready |
| 11 | Hosted capacity/recovery | Approved target, budget and actions |
| 12–13 | Integrated release audit, physical accessibility and human acceptance | Tested source-backed candidate |

Run shared SQL tasks 4/5/6 sequentially. Each requested task ends with its scoped
changes, actual results and limitations. Do not automatically start later prompts
or change another checkout's branch. Local work does not authorize push, deployment,
distribution, real Health access, money or user-data deletion.

## Measurements and deferred breadth

P2's two-hour 10/s soak completed 72,000 operations. Worker contention failed by
one completion 4.388542 ms late; the 250-arrival join storm had 14 disconnects at
the existing 100-member cap; the 25k-account attempt had 15 failures and 10,039
unoffered arrivals. It recorded 123,500 worker entries for 100 cancelled challenges.

P4/P5 need short comparable measurements of their changed bottlenecks, including
throughput and actual lock waits. P2 did not measure per-request lock-hold duration:
measure that in both comparison runs. Sparse zero-wait samples are not proof of no
contention. Keep failed scenarios; short local improvements do not prove hosted capacity.

The Beta target remains 2,000 accounts / 250 DAU / 100 concurrent / 25 requests
per second / one 250-person community. Hosted acceptance retains the proposed
budgets: unexpected errors below 1%; read p95/p99 ≤500/1,500 ms; mutation p95/p99
≤800/2,000 ms; zero deadlocks or unrelated global-lock waits; lock-wait p95 ≤100 ms;
30% connection headroom; worker start within 60 seconds; outage backlog 95%/100%
drained within 5/15 minutes; and two-hour stability. Correctness/privacy failures
always count as failures.

Defer 25k/10k-community characterization, four-hour soak, speculative partitioning,
generic queue frameworks, user-hosted communities and unused retention infrastructure.
Retention policy, monitored support, physical source/accessibility acceptance and
explicit rollout approval still matter before external Beta.
