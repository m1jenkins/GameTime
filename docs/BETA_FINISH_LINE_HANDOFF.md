# Beta finish-line handoff — b7

Local implementation and dependency-ready verification are complete. The roadmap
is **not accepted for physical scoring, legacy replacement, hosted use or
release**. M1 physical findings, M5 adapters/ingestion, human M6 acceptance and
M7–M8 activation remain gated. No authorized dependency-ready local task remains.

Worktree: `/Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta`.
Branch: `fm/gametime-beta-finish-b7`. Product checkpoint: `60d2e6d`; tested historical
query correction: `5436836`; subsequent commits record evidence/handoff only.
Authority: D134, [Beta plan](BETA_IMPLEMENTATION_PLAN.md),
[roadmap](BETA_FINISH_LINE_ROADMAP.md). [Acceptance](BETA_FINISH_LINE_ACCEPTANCE.md)
contains milestone/per-policy rows, failures and the evidence trail.
Do not push, merge, open a remote review, deploy or distribute this branch.
Firstmate owns the local guarded fast-forward merge.

## Try it in the morning

```sh
cd /Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta
scripts/beta-preview.py --owned-project gametime-finish-b7 serve
```

Keep that foreground terminal open. Tap Sign in on the owned Simulator. The
launcher creates seven fictional accounts and supplies local credentials privately;
it does not agree to anything. Follow [the walkthrough](BETA_LOCAL_PREVIEW.md) to
create a friend steps lobby, propose different goals, select/freeze the roster,
consent separately, enter fictional progress and a downward correction, review,
and reach final history. It includes exact clock/operator commands, account
switching, six-person expansion, lost-response recovery and cleanup.

Press Ctrl-C to close the preview: its gates turn off, only its fictional sessions
are revoked, its credential manifest is removed, and all records are retained.
Do not overlap preview, operator-smoke, concurrency or native controllers.
All money is simulated/nonredeemable. Real activity cannot score these challenges.

## What is implemented

- Separate forward `challenge_*_v1` contracts for all thirteen policies: friend
  goals/leaderboards across four metrics, four private personal goals, private
  community steps. Historical weekly 2–5/seven-day agreements remain unchanged.
- Local opt-in native Home/Challenges/You, refined Home/icon starting points,
  exact own-value chart, private actor-bound sections, explicit frozen-roster
  consent, corrections/notices/reviews/finals and history.
- Safe cancellation/leaving, report/block/suspension, scoped operators, account
  switching, held-auth/expiry protection, durable exact-request recovery and
  abandonment. Entry includes 21+ confirmation, opaque link persistence through
  sign-in/relaunch, access/pending request, selection and fresh consent.
- Private on-device source investigation tooling, scoped local operations/worker,
  overdue monitoring, tested foreground preview and release/association/disclosure
  preparation. Suggestions and real adapters remain dependent on accepted sources.

## Executed acceptance

Each row is an actual run, not a cumulative count or substitute for another layer.

| Layer | Actual result | Evidence under `docs/evidence/beta-finish-line-b7/` or private log |
| --- | --- | --- |
| Committed portable gate, 97d9026 | 3,840 SQL assertions / 82 files, 835 Deno tests, 113 core Swift tests, persisted weekly smoke passed | `m6-final-committed-portable-gate.log` |
| New-domain SQL | 264 assertions included in that SQL total | Acceptance ledger, tests 490–499 |
| New native HTTP matrix | 16 tests passed; two/six steps plus all thirteen correction/review/paused-exit/final journeys | `m6-native-invited-reconsent-expiry.log` |
| Two-person native touch | One pass, 241.789 seconds; participant UI through final history | `preview-execution.json`, `m6-preview-two-touch.log` |
| Six-person native touch, 60d2e6d | One pass, 636.211 seconds, 404 local requests | `six-touch-final.json` |
| Native regression, 60d2e6d | 392 executed: 388 passed, four controller skips, zero failures | `native-units-final.json`; skipped suites all executed separately |
| Historical authenticated weekly | One pass, 4.896 seconds | `historical-native-final.json` |
| Historical authenticated duel / commitment | One pass each, 11.149 / 5.405 seconds | `legacy-controllers-final.json` |
| Historical UI, 5436836 | All 50 passed, zero failures, 1639.927 seconds | `historical-ui-final.json` |
| Concurrency / operator | 15 actual multi-session checks / 11 authenticated CLI checks passed | `m6-final-concurrency.log`, `m6-operator-help-recovery.log` |
| Accessibility preparation | Four native UI tests; 16 unfiltered screen audits passed across light/dark/largest text/320-point viewport | `a11y-preparation.json`; physical/human checks unperformed |
| Private launch guard | 10 focused tests passed after reproducing both observer exclusions failing | `m6-observer-exclusion-{before,after}.log` |
| Build | Working Debug Simulator build and unsigned Release device build; new local/private modes absent in Release | `debug-build-final.json`, `release-build.json` |

Native HTTP/touch uses production Swift clients with authenticated local actors.
Clocks, activity facts and operator test actions are fictional. Historical UI uses
fixtures. None of these runs is physical-source, human comprehension or hosted
acceptance. Raw logs and result bundles live under
`/tmp/gametime-finish-b7-evidence` or the exact paths in their JSON reports.
Credentials/raw UI typing logs stay restricted and uncommitted.

The prior historical UI batch (43 passes/seven failures) is retained. All seven
failures reproduced on main 577bc32. Actual baseline/candidate screenshots and AX
captures established casing variation in four styled labels. The test-only fix
keeps full semantic text and element kind; seven focused tests then passed, followed
by the full 50-case committed run. `legacy-label-observations.json` preserves the
mixed-case baseline observation. Key `legacy-health-heading` is resolved locally.
Earlier failed/interrupted accessibility runs also remain failures, with later
accepted runs distinguished. No shared Xcode service/daemon was restarted.

## Owned resources and safe reproduction

Only Simulator `72A3249A-2DE0-4695-AF41-DCD2743B4666` belongs to this task:
GameTimeFinishB7, iPhone 17 Pro / iOS 26.5. Xcode:
`/Applications/Xcode-beta.app/Contents/Developer` (SDK 27.0).
Debug app: `/tmp/gametime-finish-b7-derived/Build/Products/Debug-iphonesimulator/GameTime.app`,
bundle `com.mjenkins.gametime.staging`. Exact rebuild/start commands are in the
morning walkthrough. Release: `/tmp/gametime-finish-b7-release/Build/Products/Release-iphoneos/GameTime.app`;
unsigned, never installed physically or distributed. Default navigation is legacy.

The available preview stack is `/tmp/gametime-finish-b7-stack`, project
`gametime-finish-b7`: API 58321, DB 58322, controller 58339. No reset is needed.
All ten runtime gates are off, actors empty, fictional clock null. Status found
zero due/overdue items or recent failures. Both task controller ports are free.
No preview/native credential manifest remains. All 18 external readiness gates
are false. Source/ingestion/analytics controls are constrained off.

The second owned stack `/tmp/gametime-finish-b7-weekly-stack`, project
`gametime-finish-b7-weekly`, API 56321 / DB 56322, is **stopped with volume backup
retained**. Its weekly/duel/commitment native runs finished with gates off,
allowlists/owned sessions/unfinished slots empty. Historical controller defaults
must never target original 5432x. `scripts/beta-legacy-native-prepare.py` makes an
independent committed copy and remaps only four test/controller port files to
5632x; `legacy-native-inputs.json` records 682 before/after hashes. Production Swift
is unchanged. Exact executed commands and input/result paths are in the reports.

```sh
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --native-only
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --touch-only 2
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --touch-only 6
scripts/beta-concurrency.py --owned-project gametime-finish-b7
WEEKLY_VERIFY_PORT_BASE=59320 scripts/weekly-local-verify.sh
```

Run native/controllers sequentially. The portable gate creates another unique
stack from a committed candidate and cleans up only that stack. Never use an
unscoped database reset, copied hosted credentials, or another effort's Simulator.

## Preservation and next dependency

Original `/Users/user/Documents/GitHub/GameTime` remains read-only. Terminal
verification matched its HEAD 577bc321e72750976e2e8027680387707070b0e3, exact porcelain
status, all 101 inherited source hashes and original database container/volume /
start identity. The 55 historical migration blobs are unchanged; 14 migrations
are forward additions. Reports: `preservation-final.json`,
`migration-preservation.json`. Database identity is not a content snapshot or a
claim about unrelated external database activity. No original reset/stash/git
mutation, database change, push or hosted action was performed by this task.

The next executable product work depends on these exact external actions:

1. `physical-source-actions`, held in `gametime-beta-source-acceptance-b7`: follow
   [private physical instructions](BETA_SOURCE_INVESTIGATION.md) on an opted-in
   iPhone/Watch. Record only categorical findings. Raw Health records stay volatile
   on-device with no screenshots/logs/uploads. Select timed-distance tolerance and
   reconcile new readiness mapping from those findings. Every physical row is
   unperformed. Then implement accepted M5 adapters/minimum-data ingestion and
   execute the physical correction/review/final journey; keep each source disabled
   until its requirements pass.
2. `beta-release-identities-retention`, held in `gametime-beta-release-readiness-b7`:
   provide accountable legal/support identity, approved retention/deidentification,
   hosting domain and community settings. Exact questions are in
   [the unpublished disclosure draft](BETA_PRIVACY_TERMS_DRAFT.md).
3. Run human comprehension, physical accessibility/assistive-control and monitored
   support checks from [rollout preparation](BETA_ROLLOUT_PREPARATION.md). No test
   message, recruitment or distribution has been authorized or performed.
4. Only after physical/replacement acceptance and separate hosted authorization,
   execute M7 wiring/replacement and actual hosted acceptance. M8 distribution /
   recruitment and real money each require separate authorization. Prepared files
   and successful local tests grant none of these approvals.

## September 8 continuation — c8

The preserved b7 completion remains `cf82e25bd7905c851525b837259bba0f0aaf3d8f`.
Continue from [the c8 handoff](BETA_REAL_VALIDATION_HANDOFF.md) and
[its acceptance ledger](BETA_REAL_VALIDATION_ACCEPTANCE.md), which supersede
the earlier no-dependency-ready-work conclusion with reproduced lifecycle/privacy
fixes. c8 builds and documentation live in the isolated `/2/` checkout; b7 remains
read-only. Prior runs above are historical evidence, not fresh c8 checks.
