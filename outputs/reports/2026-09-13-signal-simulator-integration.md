# Signal simulator integration — 2026-09-13

Completed locally with Signal preserved. Authenticated Simulator journeys pass;
physical source, human, hosted and release acceptance remain closed.

## Source and changes

Local branch `fm/gametime-signal-simulator-integration-s2`, isolated worktree
`/Users/user/.treehouse/GameTime-54367f/1/GameTime`, from published Signal
`b351a4775a938056ca229301caa513c3e1d85022`. The newer primary documentation and
evidence were read in place and preserved; they are not imported into this branch.
No push, merge, hosted mutation, payment, physical-device action or Watch app.
App/controller integration commit:
`401b8b241d2ba33e4725ad0e62023b282f964c69`. Final code/test commit
`08850da5ec2e1f115d2af25a3d5bc36b43075c95` changes only
two restriction tests' recognition of the observed OCR f/r confusion. Full
source identities and file hashes are in the private source manifest.

Inspected overnight code `a3e77333a2c788d67243b51b84bce8bf82a89461` and report
`264bbd00bccc4f924b36c9e2146c7350bdf406d6`; adapted its three fixes to Signal:

- Issued invitation links are journaled by actor, challenge and exact request
  before clearing the pending command. Retry and recreated views/stores recover
  the link and its revoke control. Unconfirmed revocation retains the locator;
  confirmed revocation removes only that link. Storage failure retains recovery.
- Redemption acknowledges only its own confirmed receipt for the same actor
  and unchanged input. An older response cannot erase a newer invitation.
- Per-detail request ordering preserves newer corrections, ranks and final
  results. Current-session revocation and departure/privacy restrictions retain
  precedence over ordinary response supersession; unrelated reads stay usable.

SignalProductShell, SignalTheme, native system tabs, both browser studies,
historical Personal access and immutable agreements remain intact. The only new
shipping prose extends the existing local privacy disclosure to saved issued
links. No SQL, source acceptance, transport enablement or readiness flags changed.

## Defects and disconfirming evidence

| Trigger | Expected / prior symptom | Regression and masking condition |
| --- | --- | --- |
| Issue-link response lost after commit; reopen issuer | Recover the exact link and revoke it; view-local receipt previously disappeared | Journal, mounted issuer, exact retry/recreation/revoke checks. A retained view-local receipt masked the loss. Overnight baseline evidence is historical, not a new run here. |
| Receive/edit an invitation or change account while redemption waits | Preserve newer/unconfirmed input; older completion previously cleared it | Actor/request/input-bound acknowledgement tests. No overlapping input masked the problem. |
| Two same-detail reads finish in reverse order | Keep the accepted correction/rank/final; older ordinary reply previously replaced it | Held RPC and mounted tests, including current-session rejection and replacement session. Refresh/expiry could mask the missing per-read fence. |
| Controller fictional email/password sign-in against copied email-disabled local config | Reach authenticated journeys; initial run returned Auth 422 | Enabled email/password only in the owned fixture stack and restarted only that stack. Ordinary app authentication stays closed. |
| Compress repeated policy journeys into seconds with seven actors | Exercise scenarios within unchanged quotas; 202 discovery reads and 189 commands in 28 seconds reached rate limits | The controller now paces requests by actor and endpoint against wall time. No quota data/rules are reset; no response is converted to success. Failed HTTP trace is retained. |
| New operator privacy check used participant client | Reach operator HTTP and verify server authorization; participant endpoint allowlist rejected the request first | Test uses authenticated operator SDK RPC and requires server `42501` denials. Participant allowlist remains unchanged; a client-side rejection is not server privacy proof. |
| Retry after failed community journey left its cohort open | Preserve one-community rule; next fixture publication correctly failed | Saved the exact owned cohort state, then advanced only it through the existing fictional processor to a non-punitive closed result. No rows or agreements deleted. |
| Old layer capture and cropped OCR with Signal glass/metrics | Inspect the actual mounted screen; initial images were black, subsequent OCR dropped separators or misread “of” | Real UIKit viewport/scroll captures, retained screenshots/transcripts and exact privacy/model assertions. Larger text and whole-viewport OCR replace obsolete capture assumptions. The continuing metric regex tolerates only the observed f/r OCR confusion and retains its exact numeric pair. |

Native community fixture creation also returns its exact publication ID, avoiding
selection of another retained cohort when the fixture clock moves backward.

## Coverage and results

Earlier overnight injected-RPC passes and Signal-only renders are not counted as
passes in this task. Controller-dependent skips count as missing checks.

| Focused lane | Actual result |
| --- | --- |
| Native matrix at `08850da`, `--native-only --native-phase matrix` | 22 passed, zero failures/skips, 744.168 s; one authenticated journey plus 21 policy/section/client/session checks. All 13 policies, native two-/six-person steps, correction/review/final, missing-data return and safe exits; 3,866 HTTP calls, zero HTTP errors. Zero build errors/warnings. Seven actors revoked, fixture gates off. |
| Native recovery/privacy, `--native-only --native-phase recovery` | 22 tests passed, zero failures/skips, 93.681 s. One authenticated journey plus 21 policy/section/client/session checks; 684 HTTP calls. Expected server denials: unassigned/revoked moderator, global support access, obsolete consent, revoked session. All seven actors revoked; fixture gates off. |
| Two-person authenticated touch, `--touch-only 2` | 1 journey passed, zero failures/skips; 155 HTTP calls. Created/invited through the Signal UI, independent targets, roster/freeze, each consent, progress, corrected review, review request, final simulated return, account switching/sign-out. |
| Six-person authenticated touch, `--touch-only 6` | 1 journey passed, zero failures/skips; 403 HTTP calls, 705.147 s test operation. Same complete flow with six separate fictional accounts and independently proposed targets. Final two-/six-person screenshots inspected. |
| Authenticated entry, `--touch-only entry` | 2 tests passed, zero failures/skips; 43 HTTP calls. Native tabs, account exit, four target-free leaderboard selectors, Personal validation and renewed consent after amount editing, privacy/terms navigation. |
| Focused mounted/model/Signal/Personal regression at `401b8b2` | 101 tests: 99 passed, 2 failed, zero skips. Both failures were OCR “of” → “or” for the retained own value; screenshot inspected. All five selected historical Personal/Signal UI tests passed. |
| Affected restriction suite at `08850da` | 9 passed, zero failures/skips, 26.3 s; zero build errors/warnings. Resolves both preceding failures. No other test or app source changed after the 101-test lane. |
| Exact SQL policy/entry/privacy suites, 490–502 and 506–508 | 395 pgTAP assertions passed across 16 files on the owned DB; no SQL source changes. SQL-role fixture evidence, not UI or physical-source evidence. |
| Controller configuration tests / Personal-copy check / diff check | 4 tests / 1 check / whitespace check passed. |

The focused 101-test selection is green across the original lane and the affected-file rerun;
99 + 9 is not a count of unique tests.

Failed evidence is retained separately: initial Auth 422 (21 passed/1 failed);
expanded matrix rate limits (21/1); `native-paced` (21/1 before operator HTTP);
first scoped recovery (21/1, retained open community); initial black captures
(40/10); `recovery-signal`
(46/4); `capture-sharp` (0/4); `capture-readable` (3/1). These are not counted as
passes. The last capture run stalled during automatic Simulator diagnostics;
only that run's owned `simctl diagnose` child was stopped, allowing its failed
bundle to finalize. Later lanes use supported `-collect-test-diagnostics never`
and retain ordinary result bundles and attachments.
XcodeBuildMCP's 300-second RPC wait expired during the focused 101-test run;
the owned Xcode process continued and finalized its complete result bundle.
It was not restarted or overlapped with another lane. That bundle records zero
build errors, warnings and analyzer warnings.

The matrix phase runs each policy through agreed terms, fictional progress,
downward correction, review and final result, then separate missing-data and
paused safe-exit scenarios. Missing data remains absent and the simulated entry
returns. All friend goals use independently proposed targets; leaderboards have
no qualifying target. Community outcome minimum is two in these explicit
fixtures, distinct from the five-person disclosure threshold.

| Exact policy | Native authenticated matrix actors | UI touch scope |
| --- | --- | --- |
| `friend_steps_goal_v1` | 2 and 6 | Full two-/six-person journeys |
| `friend_steps_leaderboard_v1` | 2 | Metric/competition picker only |
| `friend_exercise_goal_v1` | 2 | No full journey |
| `friend_exercise_leaderboard_v1` | 2 | Metric/competition picker only |
| `friend_distance_goal_v1` | 2 | No full journey |
| `friend_distance_leaderboard_v1` | 2 | Metric/competition picker only |
| `friend_timed_goal_v1` | 2 | No full journey |
| `friend_timed_leaderboard_v1` | 2 | Metric/competition picker only |
| `personal_steps_goal_v1` | 1 | Creation, edit and renewed consent |
| `personal_exercise_goal_v1` | 1 | No full journey |
| `personal_distance_goal_v1` | 1 | No full journey |
| `personal_timed_goal_v1` | 1 | No full journey |
| `community_steps_goal_v1` | 2; separate privacy journey grows to 6 | Mounted detail/join renders only |

No six-person matrix claim applies to the
other seven friend policies. Mounted Signal renders cover all 13 policies but
do not add authenticated or touch coverage. The operator report/removal checks
use authenticated SDK HTTP; participant journeys use the production native
participant client. Controlled overlapping responses and view/store recreation
use injected RPC tests; the controller supplies only fictional fixtures and
deliberately lost HTTP responses to the native journeys.

Lost-response recovery uses the real local HTTP commit followed by a dropped
reply and exact persisted-request retry. Journal relaunch coverage recreates the
store/view against that persisted directory; it is not a forced mid-request OS
process-kill test. Separate UI launches and account switches verify sign-in and
exit behavior. No human VoiceOver or physical activity-source acceptance is
claimed.

Self-review checked receipt ownership, storage-before-request-removal ordering,
generation and per-read fences, current-session restriction precedence, and
the Signal composition points. The participant RPC allowlist, SQL quotas,
privacy rules, policy definitions, consent literals, shell/theme and closed
transport inputs have no diff. Test changes retain private-value absence and
model assertions while updating obsolete render/accessibility assumptions.

## Commands and evidence

All controller invocations set `GAMETIME_BETA_PREVIEW_PROJECT` to
`gametime-signal-s2-20260913`, `GAMETIME_BETA_PREVIEW_PORT_BASE=60320`,
`GAMETIME_BETA_PREVIEW_STACK` to the private `stack` directory and
`GAMETIME_BETA_PREVIEW_SIMULATOR` to the owned UDID below. Each used
`python3 scripts/beta-native-smoke.py --simulator <owned-UDID>` with
`--derived-data <private-root>/DerivedData`, a distinct `--evidence-dir`, and
the exact lane selector in the results table. Each command has a 1,200-second
bound and disables parallel testing and verbose Simulator diagnosis.

The XcodeBuildMCP profile used this worktree's
`ios/GameTime/GameTime.xcodeproj`, `GameTimeBetaLocal`, Debug, the exact owned
Simulator and DerivedData. `regression-command.json` records every selection:
invitation, overlap, departure, restriction, presentation, Signal render/theme,
Personal model/result/displayed progress, and five historical UI checks for
navigation, discard, missing-result guarantee, locked terms and account/privacy
actions. The follow-up selected all `ChallengeRestrictionTests`.

Static commands: `python3 scripts/check-iphone-product.py --app <built-app>`;
`bash scripts/check-beta-candidate.sh --personal-copy-only`;
`python3 scripts/tests/beta-preview-config.test.py`; and `git diff --check`
against both the working tree and Signal base. SQL logs identify each exact
490–502/506–508 test file and its pgTAP plan/result in `sql/summary.json`.

Private `*-summary.json`, `*-http-report.json`, result bundles, original failed
logs and exported screenshots/transcripts preserve counts and disconfirming
evidence. `manifest.json` at handoff hashes these artifacts; `final-source.json`
binds the final source files to their code commit. Logs containing local tokens
or fictional sign-in input remain private. Simulator logs include system
NSMapTable, CK trait-collection and duplicate accessibility-class warnings;
they are retained, with no corresponding assertion failure observed.

## Resources, preservation and limits

Private evidence root:
`/Users/user/firstmate-workspace/data/gametime-signal-simulator-integration-s2`.
The [private evidence index](/Users/user/firstmate-workspace/data/gametime-signal-simulator-integration-s2/report.md)
records exact bundle paths, code/report commits and receipts.
Owned iPhone 17 Pro, iOS 26.5 (`23F77`):
`0D4944D8-7F19-4B0A-87DC-E8B61D44DBC7`, named
`GameTimeSignalIntegrationS2-20260913`. DerivedData and result bundles are beneath
that private root. Backend project `gametime-signal-s2-20260913` uses the owned
network `gametime-signal-s2-20260913-network`, subnet `10.253.219.0/24`.

Native/controller traffic uses `127.0.0.1:60339`, forwarding to API `60321`; SQL
uses loopback `60322`. Docker publishes API and DB on `0.0.0.0` and `::`;
the initial stack also published mail at `60324`, which was absent after the
owned fixture restart. This is loopback client traffic, not a loopback-only
host binding.
Installed Supabase CLI 2.109.1 help and current
[CLI configuration](https://supabase.com/docs/guides/local-development/cli/config)
and [command documentation](https://supabase.com/docs/reference/cli/supabase-start)
provided no task-scoped bind-address option. No global Docker/firewall repair.

Simulator functional results do not establish physical source acceptance, real
ingestion, human comprehension, hosted operation or release acceptance. All 18
readiness gates remain closed. Ordinary accounts remain unavailable for new
challenges; fictional actors are explicitly isolated.

The final preservation check matched all 55 intake-hashed primary files,
the complete primary status and original Signal HEAD. All 165 original
container IDs and every original Simulator state were still present/unchanged.
Only this task's backend containers were added and stopped. The owned Simulator
is shut down; controller manifest is absent; ports 60321/60322/60324/60339 have
no listeners. The owned DB/storage volumes, custom network, Simulator data and
all evidence remain retained. `final-resource-receipt.json` and
`final-primary-preservation.json` record the checks. No P11 implementation,
source/release decision change or new hardware request was made.

Unresolved separately: **Privacy1**, reviewer-case read versus grant revocation
(source-confirmed concern, runtime unverified), and **S1**, concurrent friend
creation/suspension (unverified). Scoped moderation journeys do not prove those
concurrent cases. No speculative SQL fix is claimed.

Next useful no-hardware task: bounded P8 actual-session reproduction of those
two existing privacy/authorization dependencies, before external use; obtain
separate scope for any demonstrated SQL correction. Do not start it here.
