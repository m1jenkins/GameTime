# GameTime checkout consolidation

Use [WORKING_BASELINE.md](WORKING_BASELINE.md) for current source and status.
The [September 15 cleanup report](../outputs/reports/2026-09-15-clean-baseline.md)
records the current read-only branch, remote and pool inventory, exact retention
exceptions and candidates for Firstmate's guarded cleanup. No resource removal
is claimed by that inventory.

## Historical consolidation — September 12, 2026

The actions and checks below belong to the earlier consolidation. Cobalt was
then the default; Signal has superseded it. Earlier statements about local-only
publication or active runtime paths do not describe current main or ownership.

## Cleanup completed

- Retired all **21 older checkout locations**: removed 11 clean linked worktrees
  after preservation, and moved 10 complete standalone clones into the archive.
- Preserved all 157 original retained references/checkout tips in a verified Git
  bundle, plus all 264 loose-file changes in hash-checked snapshots.
- Saved the original dirty copy on `codex/archive-original-20260912` at `8014c97d`.
  Its copy changes, design files and recorded deletions remain recoverable.
- Saved earlier Beta1 work on `codex/archive-beta1-20260912` at `8d63f93a`.
  Its separate application/domain was kept out of the current implementation.
- Preserved ignored evidence/build artifacts when removing linked worktrees.
  Standalone clones were moved intact. This was source consolidation, not a purge
  of retained build artifacts or database storage.
- Updated entry documents and prompts to use main. Older source locations and
  next-task statements in dated reports remain historical records.

The active login preview under `/private/tmp/gametime-finish-b7-preview` is a
separate runtime folder without Git metadata. It and the existing local stacks
were left running. Do not start a second preview controller on the same project.

## Recover earlier work

The private archive is
[Documents/GameTime-Archives/2026-09-12-consolidation](/Users/user/Documents/GameTime-Archives/2026-09-12-consolidation/README.md).
It contains:

| Record | Purpose |
| --- | --- |
| [manifest.json](/Users/user/Documents/GameTime-Archives/2026-09-12-consolidation/manifest.json) | Original checkout identities, exact file hashes and bundle-ref mappings. |
| [all-history.bundle](/Users/user/Documents/GameTime-Archives/2026-09-12-consolidation/all-history.bundle) | Complete preserved referenced history, restored and checked in an independent repository. |
| [retired-checkouts.json](/Users/user/Documents/GameTime-Archives/2026-09-12-consolidation/retired-checkouts.json) | Maps all 21 old locations to archived checkouts, metadata and local artifacts. |
| [checkpoint-commits.json](/Users/user/Documents/GameTime-Archives/2026-09-12-consolidation/checkpoint-commits.json) | Exact original/Beta1 archive commits retained in this repository. |

The original inspection is [preserved separately](archive/2026-09-12_WORKTREE_CONSOLIDATION_AUDIT.md).
Do not merge old experiments, cancelled gate recovery or the complete original
copy patch into main. Restore an archive into a separate folder when reviewing it.

## Checks performed for consolidation

- `GameTimeBetaLocal` Simulator build succeeded.
- **20 focused native tests passed**, zero failures or skips.
- **20 Python tests passed**: four preview configuration/compatibility regressions,
  14 iPhone product-guard tests, and two worker-driver tests.
- The active iPhone product guard passed: 148 source files and the expected targets.
- All 76 migrations, app/core source, configuration and readiness bytes match P10.
  Product behavior and agreement definitions were not changed by this cleanup.
- Changed-file whitespace checks and current-entry link checks passed.

These are fresh build/fixture/tooling checks. The authenticated UI walkthrough,
full SQL/release matrix, physical sources and hosted operation were not rerun.
The existing P4/P5/P6/P10 evidence retains its original scope and limitations.

The last inspected [GitHub main CI run](https://github.com/m1jenkins/GameTime/actions/runs/34061887531)
was prevented from starting by account billing/spending limits. No fresh GitHub
CI result or push is claimed. No database reset/migration, hosted change, real
Health access, distribution or payment operation was performed.

[Machine-readable cleanup record](../outputs/reports/2026-09-12-main-consolidation.json)
records the source and archive identities and the executed checks.
