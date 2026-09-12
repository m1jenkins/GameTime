# GameTime remaining prompts

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

Updated September 11, 2026. Use the [simplified plan](GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md).
The [previous pack](archive/2026-09-11_PRE_SIMPLIFICATION_FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md)
is historical. Prompts 0, 0A and 3 are complete; Prompt 2 evidence is available.
Prompt 4 is now completed and locally verified on the isolated continuation at
`b67776c8b3fc1173f4e7f44bd794db9f81b2b7a0`; see its
[completion report](../outputs/reports/2026-09-11-p4-completion.md).
Prompt 5 is also locally completed at `e0a94bd793e4720ae04795760d614b049005618b`
on `codex/bounded-queries-p5`; see its
[completion report](../outputs/reports/2026-09-11-p5-completion.md).
Product main has not moved. Reconcile that result before later work; do not
restart P4/P5 or automatically start P6. The task text below is retained for its
contract. Use the common instructions with one requested task at a time.

## Common instructions

```text
Read PROJECT_MEMORY.md, CLAUDE.md and the current remaining implementation plan.
Implement only the numbered task below. Change working code only for a concrete
correctness, maintenance or performance benefit.

Reconcile existing workers and branches first. The September 11 product baseline
is affd367ebe5411969fd5b7abd45629e0746a5a7d in
/Users/user/firstmate-workspace/projects/gametime-beta. Recheck the latest accepted
descendant. Use an isolated branch/worktree; preserve the dirty original, other
branches and retained resources. Do not apply the entire dirty diff or duplicate
an active task. Check the simplification report for the prepared P4 continuation.

Cancelled candidate-gate recovery is not a prerequisite for local work. Reuse
specific tools/evidence; do not restart completed prompts or import an entire
unaccepted verification branch.

Preserve historical agreements, consent, privacy, revocation, limits, exact retries
and safe exits. Keep applied migrations immutable; use forward migrations.
Real-source and money gates stay closed.

Use focused tests and one concise review. Test final source. SQL changes need an
owned disposable DB, changed-invariant races, affected tests and an old-data
upgrade/historical smoke; shared helpers may justify one full portable SQL pass.
Native changes need an affected build/journey. Avoid a full release matrix or long
soak after every local change.

Use 90 minutes of validation and 20 minutes per command as working defaults.
After the same environment obstacle twice, preserve it and continue independent
work. Missing required correctness checks prevent acceptance, not preservation of
completed work. Fix concrete product defects; report additional validation needed.

End with exact base/result commits, changed behavior, actual checks and limitations.
A commit with missing required checks is not accepted. Stop after this task.
No push, deployment, distribution, real Health access, money, user-data deletion
or changes to another checkout's branch/resources are authorized.
```

## Prompt 4 — finish scoped locking and worker claims

```text
Finish existing P4 d0742eac0fab4d182338dc75d5aacb77658e0c09 on
fm/gametime-beta-scoped-locks-p4 (pool 9, parent a18f00f). Preserve its branch and
partial evidence. Reuse its useful code on the current product baseline, including
the prepared harness fixes identified in the simplification report. Do not edit
the retained/applied migration; add a forward correction migration as needed.

Separate ordinary session/read validation from mutation locking. Use scoped
session/actor, link, lobby/capacity and member/source locks, with one documented
order across actors/challenges. Preserve revocation, admission/processing pauses,
exact retries, consent and safe actions.

Use a small durable due-work/claim table with bounded FOR UPDATE SKIP LOCKED
claims. Commit claims quickly; complete each item in its own short, idempotent
transaction. Record attempts, next_attempt_at, bounded backoff, abandoned-claim
recovery and failed/overdue visibility. Avoid a general queue framework. Exclude
cancelled/terminal challenges. Keep review deadlines based on actual notices/filing.

The current candidate still uses advisory claims and one batch-held transaction;
its completion/retry contract is unfinished. Avoid recomputing the full work
inventory for every candidate. Its pre-final SQL passes are not final-source proof.

Finish the five unreached races in its report. Prove unrelated accounts/challenges
proceed; conflicting admissions, link redemption, consent, revocation and retries
remain correct; two workers skip owned claims, recover abandoned claims and never
double-apply a result. Check reads/reviews/exits during worker pause/failure.
Retain 249th/250th/251st fixture-capacity checks; community product changes belong
to P6. Run affected SQL and historical/upgrade checks once.

Reuse P2's harness and retain its failures. Compare short identical before/after
independent-client and worker-contention workloads, recording throughput and lock
waits. Prove repeated polls do not reprocess cancelled work. No two-hour soak here.
```

## Prompt 5 — bound the queries that need it

```text
After P4 correctness passes, use P2's plans and current measurements to identify
expensive Home/detail/history and due-work paths. Replace unbounded history IDs
and per-row projection loops where needed with bounded projections and stable
keyset pagination. Add only measured indexes; preserve ownership/cursor behavior.

Use a forward migration and necessary client changes. Show before/after plans,
latency and write/storage cost. Test page boundaries, stale cursors and cross-actor
access; run affected SQL/native and upgrade checks. Defer speculative partitioning,
generic repository/retention frameworks and history deletion.
```

## Prompt 6 — finish the private community

```text
Complete the existing operator-published steps community after P4/P5. Support
250 people with narrow capacity reservation and per-member state. Own progress is
current/private; stranger identities, standings and times remain hidden.
Exact anonymous counts require five joined, active, nonremoved people and fixed
server snapshots at least 15 minutes old. Below five, counts are null with a
threshold state. Test 899/900/901 seconds, join/exit/removal and alternate endpoints
or metadata that could reveal fresher or suppressed counts.

Require account/age/Beta eligibility and discovery authorization; keep safe reads,
reviews and exits during admission pause. Make report scope explicit. Challenge
moderators cannot see unrelated reports or impose global suspension. Keep global
support authority separately audited. Add grant expiry/revocation, appeal/
reinstatement and practical quotas for discovery, lookup, redemption, joins,
reports and repeated mutations.

Parameterize publication settings and keep a small publisher identity/type seam,
but publication stays operator-only and off. No user hosting or feed. Test capacity,
privacy, moderator boundaries and shared limits, including a short 250-arrival run.
```

## Prompt 7 — physical source acceptance

```text
Resume the existing source-acceptance task after my explicit opt-in naming the
iPhone and paired Apple Watch. Follow BETA_PHYSICAL_SESSIONS.md for steps, Exercise,
cumulative running and timed running: source/sync, correction, permission/lock,
workout and time boundaries. Keep raw Health data on-device; record only prescribed
categorical findings.

Return eligibility/reconciliation decisions, completeness limitations, correction/
late-sync rules, workout boundaries and measured timed-distance tolerance. Empty
reads cannot establish denial, readiness or zero. Keep unaccepted sources disabled.
This needs my participation; Simulator tests do not replace physical observations.
```

## Prompt 8 — minimal scoring-fact ingestion

```text
Using accepted physical source policies, add versioned agreement/ingestion contracts
behind closed gates. Accept only actor/challenge/terms/source-policy identity,
window, replacement value or deleted/unresolved state, monotonic revision, freshness,
exact request identity and the required integrity binding.

Reuse existing auth/retry mechanisms. Reject stale sessions, wrong actors/terms,
replay and disallowed late facts. Test downward corrections, deletion, response
loss and concurrent revisions. Derive qualification/results on the server; reject
raw samples, routes, source names, baselines and client-authored finality. Preserve
historical contracts; run affected SQL/RLS, upgrade and ingestion tests.
```

## Prompt 9 — connect sources and actual journeys

```text
Implement the four accepted iPhone adapters: steps; Exercise as integer seconds;
running distance as integer millimetres; whole timed runs using end-start elapsed
seconds and the accepted distance band. Apply accepted source/overlap/boundary rules.
Keep the seven readiness states and protected account/terms-bound cache. Fence
stale responses; support exact retries, lower/deleted values and late/locked/offline
recovery. Finish background query callbacks promptly.

Before final consent, require eligible source history from the prior 30 days for
steps/Exercise/distance and a comparable whole workout from the prior 90 days for
timed running. This establishes availability only, never complete coverage or zero.

Connect existing Cobalt friend/personal flows in the authorized local environment.
Verify friend selection/invitation, own targets, roster freeze, consent and start;
then progress, correction, review and final result. Exercise all 13 policies without
rebuilding working screens. Preserve historical Personal access. Real source and
background claims need device evidence. Do not enable hosted release or display
preview data as ordinary signed-in account data.
```

## Prompt 10 — prepare hosted operation

```text
Use the existing release-readiness task to prepare hosted configuration, sign-in/
link identities, feature flags, operator permissions, scheduler, monitoring,
rollback and support/retention runbooks. Reuse working tools. List missing owner
inputs/proposed settings; do not invent approved publication values or policies.
Verify intended RPC exposure and least privilege. Preparation only: no provisioning,
deployment, credential changes, data deletion or external messages.
```

## Prompts 11–13 — integrated Beta acceptance

```text
After separate approval of the hosted target, budget and actions, run the Beta
capacity/recovery suite from the plan, including one two-hour soak. Retain earlier
failures. Test actual auth/links, worker replay/pause and source corrections.

Review one immutable source-backed candidate and fix concrete findings. Run the
full relevant SQL/native/historical/controller matrix, minimum/current iOS,
supported sanitizers and Release packaging once; repeat affected checks after fixes.
Keep missing checks explicit. Verify the production client, absence of fixture
actors/clocks/payment paths/Watch app, and the actual binary. Do not restart the
cancelled verification-recovery task merely to reuse its process.

With explicit device opt-in, finish physical sources, accessibility, offline/locked
recovery and two/six-person comprehension. Confirm support/operating readiness.
Unresolved privacy, wrong-result, consent, unsafe-exit or other P0/P1 defects block
release. Readiness gates change only with their own actual acceptance evidence.
Return an honest release decision. TestFlight, recruitment and distribution still
require explicit authorization.
```
