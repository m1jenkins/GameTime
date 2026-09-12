# GameTime remaining implementation plan

Updated September 12, 2026 UTC after consolidating Cobalt and P4–P7 preparation.
The [working baseline](WORKING_BASELINE.md) owns source identity and evidence:
`/Users/user/firstmate-workspace/projects/gametime-beta`, active branch
`codex/beta-working-baseline`, descended from P7 checkpoint `1b8fe6a`.
Earlier `main` and temporary task checkouts are preserved historical sources.

P4/P5/P6 are completed and locally verified. P7 has a prepared signed Debug build;
physical observations and all four source acceptances are still unperformed.
Continue its [checkpoint](../outputs/reports/2026-09-12-p7-preparation.md) and
[physical sessions](BETA_PHYSICAL_SESSIONS.md) after device-specific opt-in.
Do not restart completed prompts or the cancelled candidate-gate recovery.

Use the [prompt pack](FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md) for one task
at a time. The objective is a usable, correct local Beta, followed by source and
release acceptance. Full release verification is not a prerequisite for every
local task; missing correctness checks for the change itself still prevent
accepting it. Prior [simplification](../outputs/reports/2026-09-11-beta-simplification.md)
and [archived plan](archive/2026-09-11_PRE_SIMPLIFICATION_GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md)
remain historical records. The original dirty patch was not imported.

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
| 4 | Completed locally: scoped locks, durable bounded claims and cancelled-work fix | Included in the working baseline |
| 5 | Completed locally: bounded history keysets and measured query/index improvements | Included in the working baseline |
| 6 | Completed locally: private community disclosure, 250 capacity, moderator boundaries and quotas | Included in the working baseline |
| 7 | Prepared only; physical source decisions remain | Device opt-in and owner participation; may accompany unrelated local work |
| 8 | Versioned minimal-fact ingestion | Accepted source policies |
| 9 | Four adapters and usable native friend/personal journeys | 8 and accepted sources |
| 10 | Hosted configuration/operator preparation | Local integration ready |
| 11 | Hosted capacity/recovery | Approved target, budget and actions |
| 12–13 | Integrated release audit, physical accessibility and human acceptance | Tested source-backed candidate |

Shared SQL tasks 4/5/6 were completed sequentially and are included in this
baseline. Each subsequent requested task ends with scoped changes, actual results
and limitations. Do not automatically start later prompts
or change another checkout's branch. Local work does not authorize push, deployment,
distribution, real Health access, money or user-data deletion.

## Measurements and deferred breadth

P2's two-hour 10/s soak completed 72,000 operations. Worker contention failed by
one completion 4.388542 ms late; the 250-arrival join storm had 14 disconnects at
the existing 100-member cap; the 25k-account attempt had 15 failures and 10,039
unoffered arrivals. It recorded 123,500 worker entries for 100 cancelled challenges.

P4's [comparison](../outputs/reports/2026-09-11-p4-completion.md) records short
throughput, actual lock waits and sampled lock residence before/after. P5's
[measurements](../outputs/reports/2026-09-11-p5-completion.md) record identical
query fixtures, plans, latency and storage/write costs. P6's
[250-arrival burst](../outputs/reports/2026-09-12-p6-completion.md) verifies local
capacity and retries. Retain their sampling limits, blocked CLI advisors/lint and
historical P2 failures. These are local results, not hosted capacity acceptance;
no additional general load task is required by this consolidation.

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
