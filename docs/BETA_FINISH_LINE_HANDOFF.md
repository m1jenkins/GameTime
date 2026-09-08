# Beta finish-line handoff — b7

Worktree: `/Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta`.
Branch: `fm/gametime-beta-finish-b7`; latest implementation checkpoint `60d2e6d`.
Authority: D134, [Beta plan](BETA_IMPLEMENTATION_PLAN.md),
[roadmap](BETA_FINISH_LINE_ROADMAP.md). See [acceptance](BETA_FINISH_LINE_ACCEPTANCE.md)
for implemented versus executed evidence and historical failed runs.
This task is **still active**. Do not stop at the completed native matrix.

## Next executable work

1. The original historical UI batch FINISHED with exit 65: **50 executed, 43
   passed, seven failed**, 1582.711 seconds. Retain
   `m6-final-historical-ui.log` / `.xcresult`; no reporting stall occurred.
2. All seven unchanged baseline tests FAILED at the same assertions on preserved
   main 577bc32, 289.992 seconds. Evidence `m6-legacy-baseline-seven.log/.xcresult`.
   Baseline and candidate builds succeeded in separate disposable derived folders.
   Their actual fixture AX/screenshot captures are in `legacy-label-observations.json`.
   Baseline You returned mixed-case Apple Health while its screenshot was uppercase;
   the other selected baseline labels and all candidate captures returned uppercase.
   Keep that observed variation; do not claim a missing heading or all-uppercase AX.
3. TEST-ONLY full-label case-insensitive static-text queries accommodate the four
   observed styled labels. The full expected text, element kind and downstream
   behavior assertions remain. All seven affected tests PASSED, zero failures,
   382.704 seconds, `m6-legacy-query-fix-seven.log/.xcresult`.
4. Commit the tested fix and run all 50 historical UI tests again from that
   candidate. Preserve the prior 43-pass/seven-failure batch and all baseline
   failures. Firstmate inbox 005 was acknowledged; local acceptance key
   `legacy-health-heading` stays open until full verification finishes.
5. Also run old duel and performance native controllers sequentially from the
   isolated candidate copy in `legacy-native-preparation.json`, ports 5632x. Only
   four test/controller port literals changed across 682 hashed committed inputs;
   production Swift is byte-identical to 60d2e6d. The generic build-for-testing
   passed in `/tmp/gametime-finish-b7-legacy-derived`. The private
   `weekly-owned-status.json` is refreshed and five old-domain idle/gate checks
   passed. The task-owned weekly stack is running only for these checks; stop it
   afterward with backup retention. Never run original 5432x controller defaults.
6. Latest six-person touch passed on 60d2e6d (636.211 seconds); two-person preview
   touch passed (241.789 seconds). Broad native suite: 392 executed, 388 passes,
   four explicit controller skips. Beta/weekly native controllers have separate
   executed evidence; older duel/performance above remain pending. Source guard
   focused 10-test suite, native URL/relaunch/age entry and Release build passed.
7. Finish fresh Debug build, original preservation/runtime gates, clean fast-forward
   check, ledger reconciliation and committed handoff before terminal readiness.
   Latest portable gate on 97d9026 passed 3,840 SQL / 82 files, 835 Deno, 113 core
   Swift and persisted weekly smoke. Do not recycle counts as new runs.

External privacy/support/retention/domain/community questions are retained in
captain task `gametime-beta-release-readiness-b7`; physical/tolerance questions in
`gametime-beta-source-acceptance-b7`. No approvals. Local preview instructions and
rollout/association/disclosure drafts are now authored and linked from acceptance.

## Implemented and executed

- `c114078`: inherited planning/design bytes, authorship uncertainty and original
  proposal status preserved separately (101 files / 51,192,467 bytes).
- `c50125b`: private, explicit opt-in, volatile on-device investigation UI; 3
  native tests; no physical observations.
- `b8b708f` / `0ed8a30`: new steps backend and deterministic historical wrong-digest
  regression. No historical production agreement/migration was widened.
- `32ca057`: first production native two/six steps HTTP journeys and recovery.
- `fd1e4cb`: all 13 policies, private personal consent, community fixtures,
  age/links/report/block/scoped operators. 162 SQL assertions; portable gate passed.
- `3886355`: native matrix/selectors/entry, previously unallowlisted link grant,
  rejection/revocation, actual server-session revocation; 11 native tests and 210
  new-domain SQL assertions. Full portable gate passed: 3,786 SQL / 78 files,
  835 Deno, 113 Swift core, persisted historical weekly smoke.
- `e9e0ee3`: stable actor-bound Home sections, partial-failure preservation,
  monotonic 60-second visibility, background/auth/late-page fences, exact native
  icon/chart labels. 14 native tests, 224 new-domain SQL assertions, 15 actual
  multi-session checks. Concurrency rerun **passed from this commit** in
  `/tmp/gametime-finish-b7-evidence/m6-committed-concurrency.log`.
- Focused SIX touch passed from the prior native candidate in
  `m4-six-touch-focused.log`; focused TWO touch passed with the section store in
  `m6-two-touch-sections.log`. Both drive real SwiftUI participant controls and
  assert the exact new final-history row/return. Operator/clock/facts remain
  explicitly fictional controller actions. No physical/human evidence is claimed.
- Current committed portable rerun is in
  `/tmp/gametime-finish-b7-evidence/m6-sections-portable-gate.log`, temporary copy
  `/tmp/gametime-weekly-verify.ampOQfYS`. It passed 3,800 SQL / 79 files, 835 Deno, 113 core and weekly lifecycle smoke.

## Owned resources and commands

Only this Simulator belongs to this task:
`72A3249A-2DE0-4695-AF41-DCD2743B4666` (`GameTimeFinishB7`, iPhone 17 Pro/iOS 26.5).
Derived build: `/tmp/gametime-finish-b7-derived`.
App: `Build/Products/Debug-iphonesimulator/GameTime.app` beneath it;
bundle `com.mjenkins.gametime.staging`.

The active implementation database belongs to this task:
`/tmp/gametime-finish-b7-stack`, project `gametime-finish-b7`;
API 58321, DB 58322, native controller 58339. Supabase CLI email login was enabled
only in this temp config, with no confirmations/mail delivery. All real-source
flags remain constrained off. Native scripts enable fictional actors/clock only
while running, then disable gates and revoke only their own fictional sessions.
The stack itself stays available. Do not run an unscoped reset.

A second retained stack, also created by this task, is
`/tmp/gametime-finish-b7-weekly-stack`, project `gametime-finish-b7-weekly`
(API 56321 / DB 56322). It ran the historical authenticated weekly journey with
separate fixture users and gates. Its credential status file is restricted at
`/tmp/gametime-finish-b7-evidence/weekly-owned-status.json`; do not print or commit it.
The weekly verification stack was stopped with its default volume backup retained,
then restarted only to run the two additional historical native controller checks.
Stop it again with backup retention after those checks; keep the 5832x preview stack.
Neither is the original 5432x development database.


```sh
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --native-only
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --touch-only 2
scripts/beta-native-smoke.py --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --touch-only 6
scripts/beta-concurrency.py --owned-project gametime-finish-b7
WEEKLY_VERIFY_PORT_BASE=59320 scripts/weekly-local-verify.sh
```

Do not overlap concurrency/native scripts: both require the implementation stack's
fixture gates off at entry. The portable gate makes its own project and can run
independently from a committed candidate. Logs live under
`/tmp/gametime-finish-b7-evidence`; local credential files/logs are restricted and
must not be committed. The ignored native manifest is removed on cleanup.

Private source-tool launch (software verification only):
`xcrun simctl launch 72A3249A-2DE0-4695-AF41-DCD2743B4666 com.mjenkins.gametime.staging --health-source-investigation`.
The new shell requires `--beta-challenges-local` and explicit loopback connection
environment variables; the morning launcher and URL/sign-in/age entry have been executed. Legacy default
navigation is intact.

## Preservation and external gates

Original read-only repository: `/Users/user/Documents/GitHub/GameTime`, original
HEAD `577bc321e72750976e2e8027680387707070b0e3`; original database `supabase_db_gametime`
on 5432x ports. Identity/status/hash baselines are under
`docs/evidence/beta-finish-line-b7/`. Neither original checkout/database nor any
pre-existing Simulator/container may be changed. Reverify at terminal completion.

Firstmate inbox 001 was handled: physical iPhone/Watch actions and timed-distance
tolerance are in captain-held task `gametime-beta-source-acceptance-b7`. Neither
is accepted. [Physical instructions](BETA_SOURCE_INVESTIGATION.md) remain exact;
raw Health records stay on-device, never in screenshots/logs/reports/commits.
M5 real ingestion, all four sources, M7 legacy replacement and distribution remain
disabled. Community settings, comprehension, monitored support/legal identities,
hosted operations and TestFlight/recruitment remain external gates.
No push, remote mutation, pipeline, legacy deletion or real money is authorized.
