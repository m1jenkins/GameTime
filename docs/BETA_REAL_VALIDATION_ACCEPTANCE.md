# Real-activity continuation acceptance — c8

This ledger continues [b7 acceptance](BETA_FINISH_LINE_ACCEPTANCE.md), preserving
its historical successes, failures and limits. It records software validation with
fictional activity separately from physical observation and owner acceptance.
**Beta is not finished.** No physical source has been accepted or enabled.

## September 9 parent gate and Prompt 0A contract

Firstmate supplied independent closure of D9-1 through D9-4 and the complete fresh
Prompt 0 software gate at `9c84459e88246e1a34cd2acd6c6f9477384cefec`: 24 required
top-level commands exited 0; 510 Xcode executions in 14 bundles passed with zero
failures/skips; four builds passed. The exact report/index, commands, collision
map and preservation are in the private task record
`/Users/user/firstmate-workspace/data/gametime-beta-real-validation-c8/gate-9c84459-20260909-1905/`.
This is supplied parent evidence, not tests rerun by Prompt 0A or acceptance/landing.

[D135's remaining-work contract](BETA_REMAINING_WORK_CONTRACT.md) now governs
architecture, hardware sequencing, private community disclosure, workload targets
and simulation. Prompt 0A removes active Watch build/bootstrap dependencies only;
its exact child-commit verification belongs to the private contract task report.
No independent Prompt 0A review or full Prompt 0 rerun is implied. The ledgers
below retain earlier c8 results, including prior skips/failures, as dated history.

## Identity and preservation

- Continuation: `fm/gametime-beta-real-validation-c8`, isolated checkout
  `/Users/user/.treehouse/gametime-beta-7b9cca/2/gametime-beta`.
- Direct parent: `cf82e25bd7905c851525b837259bba0f0aaf3d8f`; no rebase or merge.
- Main/original baseline: `577bc321e72750976e2e8027680387707070b0e3`.
- [Start preservation evidence](evidence/beta-real-validation-c8/preservation-start.json):
  b7 clean at cf82; 101 original file hashes unchanged; original database container,
  volume and start identity match. Database contents were not read.
- Original status already contained six additional morning Lavish files compared
  with b7's earlier snapshot. The [exact delta](evidence/beta-real-validation-c8/original-status-delta.txt)
  was recorded before c8 edits; it is not attributed to this worker.
- Firstmate confirmed b7 idle before reusing `GameTimeFinishB7` Simulator
  `72A3249A-2DE0-4695-AF41-DCD2743B4666` and retained `gametime-finish-b7`
  API 58321 / DB 58322. Controller 58339 was checked free. No reset occurred.
  c8 owns `/tmp/gametime-real-validation-c8-derived` and
  `/tmp/gametime-real-validation-c8-evidence`; b7 build/evidence files are retained.
- No push, remote operation, merge, pipeline, deployment, distribution, recruitment,
  outside message, legacy deletion, signing identity selection or real-money action.

## Implemented changes

Commit `4744a3d41279b8dbb81703877ecec5726c91bca4`:

| Finding | Runtime reproduction | Resulting behavior |
| --- | --- | --- |
| R1: reopened draft mistaken for below-minimum active group | SQL 500 initially 9 passed / 19 failed; reject, noncreator leave and process between reopen and refreeze | Current `lobby_open` is a draft even with historical agreement versions. No wrongful final; new terms require fresh consents. |
| R2: unreadable pending file orphaned private detail values | Production temporary request file fails decoding after detail success; native test failed before fix | Values and expiry timestamps clear together. Durable unreadable request bytes remain available for recovery. |
| R3: foreground privacy expiry awaited a hung refresh | Actual watchdog starts its own held page request and crosses the 60-second limit; native test failed before fix | Expiry continues independently, with one owned maintenance task and actor/background guards. Late stale response cannot restore content. |
| R4: pending outsider's block ejected selected participants | SQL 501 before fix: 7 passed / 5 failed across R4/R5 | Block remains global; an unselected/exited outsider cannot end the selected roster's agreements. Selected-to-selected safe exits remain covered. |
| R5: remaining participant received departed activity/username | Actual three-person active goal, fictional activity then voluntary exit | Current counterpart member projection omits departed identity, target and activity; own receipt and immutable agreement/result context remain. Native view also guards departed content. |
| Home falsely suggested an empty account during loading/failure | Four additional section/privacy regressions, including partial reads and account switch | Distinct loading, unavailable, confirmed-empty and populated states. |
| Local preview could reinstall the older build on account switch | Inspected and exercised preview launch path | Explicit validated Simulator `--app` is retained in the private manifest; native test output paths can be isolated. |

The read-only scout report at
`/Users/user/firstmate-workspace/data/gametime-beta-risk-review-c8/report.md`
was input to this work. It did not run our tests or control any database/Simulator.
R4/R5 were initially questions and were classified only after actual local cases,
using D134's pending/selected and ending-social-visibility boundaries. Historical
agreements, consents and fictional facts are preserved by the forward patches.

The earlier claim that no dependency-ready work remained is superseded by these
reproduced defects. Previous b7 evidence remains previous evidence, not fresh c8
execution. Its six-person touch and historical UI runs have not been rerun here.

## Checks actually executed

Private raw fictional test logs/result bundles remain under
`/tmp/gametime-real-validation-c8-evidence`. They contain no physical Health records.
Sanitized reports and summaries under this document's evidence directory are safe
project evidence; private manifests and credentials are not committed.

| Check | Actual result and evidence |
| --- | --- |
| Before-fix native section tests | 9 executed, 7 passed, 2 failed, 0 skipped; `privacy-before.log` and `.xcresult`. Failures R2/R3. |
| Fixed sections + request recovery + historical held-auth race | 15 executed, 15 passed, 0 failed/skipped; `privacy-after.log` and `.xcresult`. |
| Reopened lifecycle SQL 500 | Before 9/28 passed; after 28/28 passed, no skip. `reopen-before.log`, `reopen-after.log`. |
| Participation privacy SQL 501 | Before 7/12 passed; after 12/12 passed. Expanded own-receipt/current-target controls: 14/14 passed in `participation-final.log`. |
| All new-domain SQL on retained fixture database | Initial 301/304 passed; 3 global-count assumptions in historical test 493 counted retained fictional records. No product exception or deletion. |
| Scoped SQL 493 fixture repair | One intermediate typo (`reporter_id`) produced a SQL error; corrected to actual `reporter`. Final 42/42 passed in `493-scoped-final.log`. Counts now use this test's link/actor/reporter. |
| Authenticated native production HTTP | 20 executed, 20 passed, 0 failed/skipped, 41.566 seconds; `native-http-after.log`. All thirteen policies, reconsent, correction/review/history, response loss and paused safe exits. [Sanitized trace](evidence/beta-real-validation-c8/native-http-report.json): seven fixture actors revoked, gates off, no cleanup failures. |
| First visual refinement audit | Light: one test failed with one contrast issue on a partially clipped creation disclosure. `accessibility-light.log`; actual fictional screenshot inspected. |
| Native labeled-row audit | Light: contrast issue resolved; one test failed with a distinct clipped single-line timezone field. `accessibility-final-light.log`. The next wrapping change resolved this failure. |

Final UI refinements are in `bfcec58a910d54f3a5d64a2ca53045229ff1fac0` (wrapping
native timezone field) and `2480bca4d1db6253be4b91871af3bedfa50b146e` (remove the
redundant compact goal heading; retain explicit field label). The compact initial
run at bfcec58 failed one contrast audit on the partially visible added heading;
`accessibility-wrapping-compact.log` preserves it. This is distinct from the two
creation failures above.

| Final check | Exact fresh result |
| --- | --- |
| Committed portable gate at 4744a3d | Exit 0: 3,882 SQL assertions / 84 files, 835 Deno tests, 113 core Swift tests, zero failures; formatting/lint/type/build steps passed. Historical two/five-person persisted weekly lifecycle passed and rolled back. New domain contributes 306 assertions. Unique project `gametime-weekly-verify.a7yhtkvu`, DB 59322, logs `/tmp/gametime-weekly-verify.a7YHTkVu`; disposable stack cleaned up. [Summary](evidence/beta-real-validation-c8/portable-final.json). |
| Final GameTimeTests at 2480bca | 396 executed, 392 passed, 4 controller skips, zero failures, 19.060 seconds. Skips: Beta, historical duel, commitment and weekly authenticated controller tests; Beta separately executed above. [Summary](evidence/beta-real-validation-c8/native-units-final.json). |
| Final native appearance at 2480bca | Four tests passed, zero failures/skips, sixteen unfiltered screen audits. Light/dark/largest were rerun after the final compact edit. [Exact per-run log, bundle and time](evidence/beta-real-validation-c8/accessibility-final.json). |
| Fresh c8 preview | Correct explicit c8 app path, mode-0600 manifest, installed executable hash matched before and after account switching. Actors 1 → 2 → 1 reached Home. Native goal/leaderboard/personal-invalid-input screens inspected; no automatic consent. [Preview record](evidence/beta-real-validation-c8/preview-reopened.json). |
| Preservation recheck | b7 clean at cf82, main/original unchanged at 577bc, 101 inherited original source hashes and exact starting all-files status unchanged; 55 historical migrations byte-identical; original DB container/volume/start identity unchanged. [Final evidence](evidence/beta-real-validation-c8/preservation-final.json). No private DB contents read. |
| Visual review artifact | Actual images loaded, appearance selector worked, no horizontal overflow at 500/1280 widths; desktop capture visually inspected. Firstmate owns registered feedback monitoring. [Review](BETA_NATIVE_REVIEW_C8.md). |

The final unit command uses the same xcodebuild project/scheme/destination/build
path below, with `-only-testing:GameTimeTests` and result bundle
`/tmp/gametime-real-validation-c8-evidence/native-units-final.xcresult`.
Light/dark/largest final logs are `accessibility-verified-{light,dark,large}.log`;
compact is `accessibility-compact-final.log`. UI controllers cleaned up their seven
actors and restored light/default large text after each run. The separately
reopened preview intentionally has fictional admission/processing/fixture gates on
for its seven actors; all real sources/ingestion/analytics/discovery remain off.
[Actual preview status](evidence/beta-real-validation-c8/preview-runtime-status.json).
All 18 external readiness gates remain false. Previous gated test shutdown must not
be confused with the currently running fictional preview.

No full historical fixture UI or fresh unsigned Release run was added in c8; prior
b7 evidence stays historical. These forward patches/native changes are covered by
the fresh portable historical suites, complete native units and targeted Beta
HTTP/UI runs. Compact-mode coverage is a simulated viewport, not a real
compact device or human assistive-control acceptance.

Reproduction commands, from the c8 checkout (controllers are serialized):

```sh
xcodebuild test -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTimeBetaLocal -configuration Debug \
  -destination 'platform=iOS Simulator,id=72A3249A-2DE0-4695-AF41-DCD2743B4666' \
  -derivedDataPath /tmp/gametime-real-validation-c8-derived \
  -parallel-testing-enabled NO \
  -only-testing:GameTimeTests/ChallengeSectionTests \
  -only-testing:GameTimeTests/ChallengeV1NativeTests \
  -only-testing:GameTimeTests/WeeklySocialRefreshAuthRaceTests \
  -resultBundlePath /tmp/gametime-real-validation-c8-evidence/privacy-after.xcresult \
  CODE_SIGNING_ALLOWED=NO

psql postgresql://postgres:postgres@127.0.0.1:58322/postgres \
  -X -v ON_ERROR_STOP=1 -f supabase/tests/500_challenge_reopened_draft_lifecycle.test.sql
psql postgresql://postgres:postgres@127.0.0.1:58322/postgres \
  -X -v ON_ERROR_STOP=1 -f supabase/tests/501_challenge_participation_privacy.test.sql

scripts/beta-native-smoke.py \
  --simulator 72A3249A-2DE0-4695-AF41-DCD2743B4666 --native-only \
  --derived-data /tmp/gametime-real-validation-c8-derived \
  --evidence-dir /tmp/gametime-real-validation-c8-evidence
# The four UI runs substitute --accessibility light/dark/large/compact for --native-only.
WEEKLY_VERIFY_PORT_BASE=59320 scripts/weekly-local-verify.sh
```

The portable command copies committed inputs to a newly named disposable project;
its reset and cleanup apply only there. Never run `scripts/db-test.sh` directly in
this checkout or either preserved checkout. Use a new result bundle path when
repeating an Xcode command; an existing `.xcresult` must not be overwritten.

Final local document verification: 50 relative Markdown links checked with zero
missing targets; all 18 external gates false; sanitized evidence JSON checked for
credential-field names with none found; `git diff --check` passed. These are
local document/format checks, not additional product tests.

## Physical observation and owner acceptance

| Source | Physical observation | Source policy / adapter / real journey |
| --- | --- | --- |
| Steps | Unperformed; explicit device opt-in pending | Unaccepted / not implemented / unperformed |
| Apple Exercise Time | Unperformed | Unaccepted / not implemented / unperformed |
| Cumulative running distance | Unperformed | Unaccepted / not implemented / unperformed |
| Timed running | Unperformed; no distance measurements | Unaccepted; tolerance unselected / not implemented / unperformed |

[Grouped private sessions](BETA_PHYSICAL_SESSIONS.md) start with steps and investigate
Exercise and running early. Raw samples and supporting accuracy measurements stay
on-device. Empty reads never establish a miss. All four sources are required before
distribution unless the owner changes scope. No fictional agreement was reinterpreted
as real-source terms; seven-state adapters, on-device suggestions and minimum-data
attested ingestion await accepted source evidence.

Authoritative dependencies remain `gametime-beta-source-acceptance-b7`, key
`physical-source-actions`, and `gametime-beta-release-readiness-b7`, key
`beta-release-identities-retention`. No duplicate decisions were created. Physical
comprehension/accessibility, support operation, retention/deletion, identities,
community settings and hosted acceptance remain unperformed/unapproved. All 18
external readiness gates remain closed.

Next executable human action: Firstmate delivers explicit private-investigation
opt-in and the exact selected iPhone plus paired Watch; then execute Session A.
No physical installation or Health access precedes that instruction. Exact preview
and remaining preparation steps are in [the handoff](BETA_REAL_VALIDATION_HANDOFF.md).
