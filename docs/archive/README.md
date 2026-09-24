# Repository history and recovery

Current work starts with [the project README](../../README.md),
[working baseline](../WORKING_BASELINE.md) and
[friends TestFlight plan](../FRIENDS_TESTFLIGHT_PLAN.md). The other files in this
directory describe dated products or decisions; their instructions do not
select the next task.

## September 23 cleanup

- Removed 823 tracked files: 644 old agent-run files, 173 native cache/lock
  files and six superseded prompt packs. With two navigation/search files
  added, the tracked total fell from 3,441 to 2,620 (24%).
- Removed 231,239 ignored generated files from old build directories: 12.15 GB
  of logical file contents. Retained 2,830 original local log/result/helper
  files in place and verified their checksums. Later builds regenerate caches.
- Reduced project memory from 810 to 120 lines, with its original chronology
  recoverable below. Current entry documents link to one maintained status
  record and the D142 delivery plan.
- Checked the iPhone source/product guard, unchanged app/backend/test inputs,
  archive recovery, ignore behavior and local Markdown links. No new broken
  file links were introduced; existing unrelated broken links remain. No app
  test suite was rerun for this documentation/cache cleanup.

## Retired task prompts

The September 23, 2026 repository cleanup removed these completed or superseded
briefs from the working tree. Their full text remains in Git at
`98b511863275a2c478e2f1523569308116c9e0f9`, the pre-cleanup commit.

| Former path | Why it was retired | Current reference |
| --- | --- | --- |
| `docs/BETA_IMPLEMENTATION_PROMPTS.md` | Superseded Personal hourly-ingest rollout tasks | [Personal snapshot contract](../PERSONAL_HEALTH_SNAPSHOT_V2_ACCEPTANCE.md) |
| `docs/FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md` | Dated P0–P13 tasks and obsolete checkout directions | [Friends plan](../FRIENDS_TESTFLIGHT_PLAN.md); [broader Beta plan](../GAMETIME_REMAINING_IMPLEMENTATION_PLAN.md) |
| `docs/NEXT_BUSINESS_MODEL_PROMPT.md` | Planning completed September 4 | [Business model](../BUSINESS_MODEL.md) and D123 |
| `docs/P9_NEXT_PLANNING_PROMPT.md` | Historical P9 handoff | [Working baseline](../WORKING_BASELINE.md) |
| `docs/P11B_NEXT_PLANNING_PROMPT.md` | Superseded by D142 and later hosted receipts | [Friends plan](../FRIENDS_TESTFLIGHT_PLAN.md) |
| `docs/SIGNAL_UI_FIDELITY_IMPLEMENTATION_PROMPT.md` | Creation work completed; later mocks adopted | [Current visual contract](../design/SIGNAL_UI_MIGRATION.md) |
| `PLAN.md` — final Phase 1A prompt | Already completed fixed-5K implementation brief | Historical Phase 1A record remains in [PLAN.md](../../PLAN.md) |

Read an old brief without restoring it to the active repository:

```sh
git show 98b511863275a2c478e2f1523569308116c9e0f9:docs/FIRSTMATE_REMAINING_IMPLEMENTATION_PROMPTS.md
```

Substitute any path in the table to recover its exact contents. Preserved scope
contracts in those prompts remain historical reference material; current
decisions and acceptance records govern new work.

## Other retired material

The same commit preserves `.agents/ORIGINAL_REQUEST.md`, `.agents/sentinel_*`,
`.agents/teamwork_preview_*` and `.agents/worker_m4_verification_*`: old agent
briefs, dispatches, progress logs, a one-off verification harness and compiler
caches. No current build or script consumes those runs. Reusable
`.agents/skills/` remains in the checkout.

`ios/GameTime/cache/` and `ios/GameTime/.tmp/` held compiled modules and empty
package locks. They are generated, not app source. Old input manifests may
still name them: those manifests describe their original tested commit and
must not be rewritten to imply a new test run.

The pre-cleanup `PROJECT_MEMORY.md` preserves the full dated completion
chronology. Its current version keeps adopted direction and links to the
maintained status record. Decisions, contracts, original consent, test receipts,
screenshots and approved design studies remain in the repository. No history
was rewritten and no product data was removed.

## Searching historical evidence

The root `.ignore` excludes `outputs/`, `docs/archive/`, `docs/evidence/` and
`.lavish/` from ordinary ripgrep searches. This is a search preference, not a
Git exclusion or a deletion. Follow the current contract's links when checking
an older result or design, or opt into a specific directory:

```sh
rg --no-ignore 'pattern' outputs/reports/
rg --hidden --no-ignore 'pattern' .lavish/gametime-live-goal-2026-09-21/
```
