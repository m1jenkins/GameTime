# Beta finish-line handoff — b7

Worktree: `/Users/user/.treehouse/gametime-beta-7b9cca/1/gametime-beta`.
Branch: `fm/gametime-beta-finish-b7`; latest tested correction checkpoint `5436836` (product code `60d2e6d`).
Authority: D134, [Beta plan](BETA_IMPLEMENTATION_PLAN.md),
[roadmap](BETA_FINISH_LINE_ROADMAP.md). See [acceptance](BETA_FINISH_LINE_ACCEPTANCE.md)
for implemented versus executed evidence and historical failed runs.
This task is **still active**. Do not stop at the completed native matrix.

## Next executable work

1. The full 50-test historical UI gate is RUNNING from committed `5436836` on the
   owned Simulator. Process group 26236, bounded 2700 seconds; log/result bundle
   `/tmp/gametime-finish-b7-evidence/m6-committed-historical-ui-accepted`. Despite
   that destination name, it is NOT acceptance until the run finishes successfully.
   Do not drive this Simulator concurrently. The exact command is saved in
   `/tmp/gametime-finish-b7-evidence/historical-ui-active.json`.
2. Prior full batch: 43 passed/seven failed. All seven failures reproduced on main
   577bc32. Actual candidate/baseline AX captures establish styled-label casing
   variation, including mixed-case baseline Apple Health. Test-only complete-label
   case-insensitive queries then passed all seven affected tests (382.704 seconds).
   Preserve every failed batch. Key `legacy-health-heading` stays open until the
   full committed rerun passes; Firstmate inbox 005 was handled.
3. Historical duel and performance authenticated controllers both PASSED from
   committed 60d2e6d production Swift inputs in an independent copy. Only four
   controller/test port literals changed to 5632x across 682 hashed input files.
   Duel: one pass, 11.149 seconds, 177 requests. Performance: one pass, 5.405
   seconds, 60 requests. Gates, allowlists, sessions and unfinished slots are zero.
   `legacy-controllers-final.json` records exact logs/bundles and cleanup. The owned
   weekly stack is stopped with volume backup retained; no original stack changed.
4. Latest six-person touch passed on 60d2e6d (636.211 seconds); two-person preview
   touch passed (241.789 seconds). Broad native suite: 392 executed, 388 passes,
   four explicit controller skips; all four controller suites now have separately
   executed authenticated evidence. Source guard 10-test suite, native
   URL/relaunch/age entry and unsigned Release build passed.
5. After full UI gate passes, record its actual counts/time, resolve the exact local
   blocker key, verify original 101 source hashes/status/HEAD/database identity and
   all local gates, reconcile this handoff and commit. The full UI command also
   builds the working local Debug app. No additional product changes followed the
   tested Release candidate; do not repeat passed suites without a new concern.
6. Recheck local `main` ancestry and clean committed branch before terminal status.
   Latest portable gate on 97d9026 passed 3,840 SQL / 82 files, 835 Deno, 113 core
   Swift and persisted weekly smoke. Counts identify actual runs, not new executions.

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
The weekly verification stack ran weekly, duel and performance native controllers.
All owned gates/allowlists/sessions were checked closed before stopping it again
with the default volume backup retained. Keep the 5832x preview stack available.
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
