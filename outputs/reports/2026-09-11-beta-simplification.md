# GameTime simplification — September 11, 2026

The active plan and prompt pack are now 330 lines combined, down from 1,311.
The previous versions are preserved byte-for-byte in docs/archive. Root README,
PLAN and PROJECT_MEMORY now point to the current execution plan.

## Source and continuation

| Item | Exact identity |
| --- | --- |
| Original dirty checkout | /Users/user/Documents/GitHub/GameTime, main 577bc321e72750976e2e8027680387707070b0e3 |
| Current product baseline | /Users/user/firstmate-workspace/projects/gametime-beta, main affd367ebe5411969fd5b7abd45629e0746a5a7d |
| Preserved original P4 | d0742eac0fab4d182338dc75d5aacb77658e0c09, parent a18f00fa19ac95f946c4686ba3b6a068064d797b, pool 9 |
| Isolated prepared continuation | /private/tmp/gametime-simplify-20260911-byc27c1u/GameTime, branch codex/lean-beta-preparation |
| Existing P4 replay on current product | 9e9ea93, normal local cherry-pick of d0742ea onto affd367; no conflicts |

The prepared continuation includes current Cobalt, the existing P4 changes, the
focused runner repair and the new plan. Use it to finish P4. It is a preparation
candidate, **not accepted P4 or an accepted database migration**. The existing
pool-9 branch and both original/current main branches were not moved. Nothing
was pushed, deployed or applied to a database.

## What was simplified

- Full release verification no longer blocks every local feature task.
  Focused final-source correctness checks still gate that task's acceptance.
- Completed prompts and the cancelled recovery task stay closed. Reuse existing
  P4 code and reviewed P2 measurements, including their failures.
- Keep one concise review and checks proportional to changed behavior. Use short
  comparable load measurements for P4/P5; the two-hour soak and complete runtime,
  native/historical, sanitizer and packaging matrix belong at integrated release.
- Keep the 13-policy product, consent, revocation, exact retry, safe exits,
  migration preservation, 250-person community and delayed-count privacy contract.
  Avoid speculative frameworks, partitioning or participant-hosted products.

This is an execution-policy change, not a claim that cancelled recovery passed.

## Concrete code cleanup

The original dirty code was primarily wording changes, not a duplicate backend.
There was no useful broad native refactor. Nonempty disclosure views on the current
Cobalt baseline should not be replaced mechanically with the dirty EmptyView
versions: the dirty patch also leaves related UI assertions inconsistent.
Those screen-copy choices remain preserved for a separate deliberate decision.

Six internal comments/assertion labels across five original-checkout files were
restored to precise simulation/settlement wording. This fixes “outcome updateed”
and descriptions such as “conserved test configuration” for a money-conservation
assertion. Conditions, values and user-facing strings did not change:
- ios/GameTime/GameTimeTests/PerformanceCommitmentNativeSmokeTests.swift
- scripts/duel-lifecycle-local-smoke.ts
- scripts/performance-lifecycle-local-smoke.ts
- supabase/tests/466_duel_native_projection.test.sql
- supabase/tests/477_performance_lifecycle.test.sql

In the isolated continuation, scripts/beta-scoped-locks-p4-concurrency.py now:
- tracks its own psql children from creation;
- kills/reaps remaining owned children before requesting the exclusive shutdown
  gate, so a timed-out contender cannot keep that cleanup waiting indefinitely;
- bounds synchronous SQL calls, including shutdown, to 20 seconds;
- checks shutdown's result and reports failure instead of falsely claiming gates
  were disabled.

No general runner, allocator or sandbox framework was added. Existing migrations,
RPCs, worker behavior and test scenarios were not rewritten by this cleanup.

## Performed verification

Command in the prepared continuation:
`PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/beta-scoped-locks-p4-runner.test.py -v`

Five checks passed on the final runner/test source: timed-out child collection
before gate shutdown; unowned process preservation; accurate failed-shutdown
reporting; propagated shutdown timeout; and already-collected child cleanup.
The tests create finite owned local Python children and use an injected shutdown
result. They establish process/error handling, **not PostgreSQL race correctness**.
An earlier four-check pass preceded the added already-collected-child regression.

Active-code/document diff checks and local-link checks passed. The full staged
`git diff --cached --check` reports seven pre-existing Markdown hard-break lines
in the two verbatim archives (exit 2); those archives remain byte-for-byte exact.
Archive equality and preservation of all unrelated original-checkout files were
checked separately. The five developer-only wording corrections restore those
files to their tracked bytes; no native or database rerun is warranted for those
labels/comments.

## Still belongs to Prompt 4

The preserved P4 implementation remains incomplete:
- claims use transaction advisory locks and processing still shares one batch
  transaction; durable SKIP LOCKED claims, retry scheduling, abandoned-claim
  recovery and independent completion are still required;
- candidate rechecks call the broad work projection repeatedly;
- five original races were unreached, and the final migration did not receive
  its required database rerun;
- no accepted before/after lock-wait or throughput comparison exists.

The runner repair does not close those gaps. The next prompt explicitly finishes
them with targeted SQL/race/upgrade checks and short measurements. P5/P6 follow
only after their dependencies pass. No full candidate gate, database tests, load
run, Xcode matrix, physical Health access, external action or later prompt ran
during this cleanup.
