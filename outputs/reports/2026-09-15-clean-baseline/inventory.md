# Read-only checkout inventory — September 15, 2026

Baseline `B = 1dacc6644f2100567d85fbaa2970bb7285bbaa35`. The task is isolated at
`/Users/user/.treehouse/GameTime-54367f/2/GameTime`, branch
`fm/gametime-clean-baseline-20260915`. No other checkout, branch, worktree, remote
or lifecycle state was changed. Firstmate owns cleanup and publication.

Commands: `git worktree list --porcelain`, `git for-each-ref`,
`GIT_OPTIONAL_LOCKS=0 git status --short --untracked-files=all`, `git ls-files
--others --ignored --exclude-standard`, `git stash list`, and for every tip,
`git rev-list --left-right --count B...TIP` in the authoritative repository.
A zero right-hand count proves ancestry. No cherry-pick equivalence is assumed.
Live branches were read through `gh-axi api repos/m1jenkins/GameTime/branches
--paginate`; no fetch/prune or remote mutation occurred.

## Authoritative local refs and remote branches

`main`, `origin/main`, `origin/HEAD`, and live GitHub `main` all equal B.
Counts below are **main-only / tip-only commits** at inventory time.

| Local branch | Tip | Counts | Disposition |
| --- | --- | --- | --- |
| `main` | `1dacc6644f21` | 0 / 0 | Retain authoritative checkout |
| `fm/gametime-p9-authenticated-app-20260915` | `1dacc6644f21` | 0 / 0 | Fully landed; cleanup candidate after pool ownership and ignored evidence are handled |
| `fm/gametime-clean-baseline-20260915` | B at allocation | 0 / 0 initially | Active task; retain through delivery/publication |
| `codex/consolidate-main` | `ae5aa5d4da41` | 29 / 0 | Fully landed branch cleanup candidate |
| `codex/crisp-cobalt-ui` | `affd367ebe54` | 43 / 0 | Fully landed branch cleanup candidate |
| `codex/archive-beta1-20260912` | `8d63f93aec65` | 75 / 20 | Retain competing Beta1 and checkpoint; unique unlanded work |
| `codex/archive-original-20260912` | `8014c97d1b5e` | 75 / 1 | Retain original dirty copy checkpoint; unique unlanded work |
| `codex/beta1-policy-foundation` | `0f5491009f95` | 75 / 19 | Unlanded; contained in retained archive-beta1 tip, but not a main-landed candidate |
| `codex/ios-accessibility-audit` | `8e2e267d2c85` | 112 / 2 | Retain; two commits absent from main |
| `codex/overnight-integration-20260913` | `264bbd00bccc` | 28 / 5 | Retain; fixes adapted in S2/P8 do not establish whole-branch equivalence |
| `codex/signal-native-migration` | `823ee0a769da` | 27 / 1 | Retain provenance; migration is incorporated by other commits, but ancestry and `git cherry` do not prove this commit redundant |
| `daybreak-ledger-tokens` | `0957d075c7fb` | 104 / 2 | Retain; obsolete appearance, unique history and one unpushed commit relative to live remote |

Live remote inventory contains exactly these five branches; current local
remote-tracking refs match their tips. `origin/HEAD` is a symbolic alias of main.

| Remote branch | Tip | Counts | Disposition |
| --- | --- | --- | --- |
| `main` | `1dacc6644f21` | 0 / 0 | Retain |
| `claude/app-language-review-oxo9mf` | `8404fbb54dc9` | 140 / 0 | Fully landed remote cleanup candidate |
| `codex/weekly-local-roadmap` | `fddcbcd0c823` | 76 / 0 | Fully landed remote cleanup candidate |
| `codex/ios-accessibility-audit` | `8e2e267d2c85` | 112 / 2 | Retain unique commits |
| `daybreak-ledger-tokens` | `ea16beb67e6a` | 104 / 1 | Retain unique commit |

Unique history includes the original-copy checkpoint, competing Beta1 policy and
UI work, two accessibility commits (`8f9ba35`, `8e2e267`), five overnight commits
(`f5adb6c`, `a3e7733`, `172c24b`, `b912599`, `264bbd0`), the original Signal commit,
and Daybreak commits `ea16beb`/`0957d07`. Obsolete appearance or a cancelled task
is not proof of landing. Never merge cancelled verification work to make its
branch deletable. Earlier cancelled candidates remain in the September 12
external recovery bundle; no new cancelled verification branch is checked out.

## Linked/pool checkouts

All non-task checkouts have **zero tracked modifications and zero nonignored
untracked files**. Ignored material is a separate retention category.

| Location | HEAD / branch | Disposition |
| --- | --- | --- |
| `/Users/user/Documents/GitHub/GameTime` | B / `main` | Retain primary. 130,366 ignored files at inspection; includes historical build/results, local config, `.ua/.trash-*`, generated design work and Supabase local metadata. No ignored-file purge authorized by this inventory. |
| `/Users/user/.treehouse/GameTime-54367f/1/GameTime` | B / P9 branch above | Landed checkout candidate, conditional on Firstmate reconciling **S2 and P9 sharing pool1**. 30,545 ignored files: `tmp/p9-authenticated-app/` (30,543), `tmp/beta-native-smoke-report.json`, and `supabase/.temp/` (one). Preserve P9 result bundles/logs and any runtime-owned metadata before retirement. |
| `/Users/user/.treehouse/GameTime-54367f/2/GameTime` | B at allocation / this task | Retain active cleanup. Old `gametime-p8-concurrency-20260913.meta` still names this path; Firstmate confirmed P8 cleanup preceded reuse. New ignored outputs are under `tmp/clean-baseline/`. |
| `/Users/user/firstmate-workspace/projects/gametime-beta` | `ae5aa5d4da41` / `main` | Clean obsolete clone candidate; no ignored files or stashes. Local main is an ancestor of B (29 / 0). |
| `/Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta` | `ae5aa5d4da41` / detached | Clean obsolete pool candidate; 29 / 0, no ignored files. |
| `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta` | `b25834c8ea2a` / detached | Clean obsolete pool candidate; 27 / 0, no ignored files. **Older scout (`gametime-signal-native-plan-s1`) and validation (`gametime-beta-real-validation-c8`) share pool2 in stale task metadata.** Reconcile ownership before removal. |

Current pool root has empty slots 3–5; older pool root has empty slots 3–9.
Their treehouse JSON lists only the two extant worktrees in each pool. Empty slot
folders and stale task records are administrative state, not additional Git work.
Firstmate reports ten old task copies were retired before this task; this worker
did not remove them or treat their stale paths as live checkouts.

The primary repository retains stash `1d6bcb66951546bc05a820e6375dea63d4f538c3`
(`stash@{0}`), a four-line `YouView.swift` diff renaming the nested `State` enum to
`DeleteAccountState`. Those two added lines exist on B. Retain the stash pending
Firstmate's explicit disposition; it was neither applied nor dropped.

## Older clone's cached refs

Its remote is the local authoritative repository, not a fresh GitHub snapshot.
It lacks B's object, so cross-repository ancestry above was checked in the current
repository, which contains every old tip. No objects or refs were copied.

Its only local branch is `main = ae5aa5d4da41` (two behind its cached origin/main).
All cached remote refs are listed below. Each is already represented by a current
local ref or a main ancestor; the clone holds no unique referenced commit.

| Cached ref (`origin/`) | Tip | Counts vs B / current recovery |
| --- | --- | --- |
| `HEAD`, `main` | `b25834c8ea2a` | 27 / 0, current main ancestry |
| `codex/consolidate-main` | `ae5aa5d4da41` | 29 / 0, current main ancestry |
| `codex/crisp-cobalt-ui` | `affd367ebe54` | 43 / 0, current main ancestry |
| `codex/archive-beta1-20260912` | `8d63f93aec65` | 75 / 20, retained local archive branch |
| `codex/archive-original-20260912` | `8014c97d1b5e` | 75 / 1, retained local archive branch |
| `codex/beta1-policy-foundation` | `0f5491009f95` | 75 / 19, retained local branch/archive |
| `codex/ios-accessibility-audit` | `8e2e267d2c85` | 112 / 2, retained local/live remote branch |
| `codex/overnight-integration-20260913` | `264bbd00bccc` | 28 / 5, retained local branch |
| `daybreak-ledger-tokens` | `0957d075c7fb` | 104 / 2, retained local branch including its unpushed commit |

This proves referenced-history coverage, not a license to discard reflogs or
unknown filesystem material. The older clone's final removal remains Firstmate's
guarded action after its own last-minute status/ownership check.

## Supervisor follow-up — after this inventory

Firstmate reports local `codex/consolidate-main`/`codex/crisp-cobalt-ui` and remote
`claude/app-language-review-oxo9mf`/`codex/weekly-local-roadmap` deleted, followed
by fetch/prune. The P9 copy was retired with 44 MB of validation preserved in its
private task data. Duplicate ownership records were reconciled with stopped old
agents and backed-up records; current cleanup pool2 remains active. Older scout
copies were being returned. Seven unique local branches and two corresponding
remotes remain pending the owner's retention/recovery-bundle decision. The
initial tables above preserve the read-only evidence used to choose those actions.

## Executed historical-ref disposition — September 15, 2026

After the relevance audit, Firstmate deleted local `codex/beta1-policy-foundation`
and `codex/signal-native-migration`, plus remote `codex/ios-accessibility-audit`
and `daybreak-ledger-tokens`, using exact-hash guards. Local archive-beta1,
archive-original, accessibility, overnight and Daybreak refs remain unchanged.
See the [dated disposition](../../../docs/HISTORICAL_BRANCH_DISPOSITION_20260915.md)
for full refs/hashes, current equivalents and the required retained carriers.
This is a later execution receipt; the original read-only tables above retain
their historical meaning. No additional historical branch is approved for deletion
by that receipt.

## Later action — September 16, 2026

At 2026-09-16T05:13:25Z, Firstmate deleted the five formerly retained local
refs under the captain's explicit backup-and-delete choice. Two other local
refs and both matching remotes were already deleted; only main remained locally
and remotely at that checkpoint, and the stash was unchanged. All nine exact tips
were independently restored from the external bundle and `git fsck --full`
passed. The [superseding disposition](../../../docs/HISTORICAL_BRANCH_DISPOSITION_20260915.md) records the recovery location,
checksum and scratch-mirror recipe. Useful old work remains recoverable; the
static-only profile-retry follow-up remains unresolved. These later actions
supersede live-ref retention, without rewriting the historical tables or manifests.
