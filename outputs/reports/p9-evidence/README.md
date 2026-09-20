# P9 focused evidence index

Application source: `cbfaf255612bf55e87fde7c4262902825f271d6d`.
Pacing correction: `c19bb28`. Acceptance follow-up
`b336f4c3c1cbc8e09f895018f50fba6cb0bcac21` extends the steps journey. Final app
source `b0ce67e64ae1a47dd222d5e56e8ea0ef4c63dfae` fixes locked-launch recovery;
17 affected flow/observer checks passed. Later changes are reports/docs only.
Results are local and synthetic, not release or physical acceptance.

## Portable receipts

- `summary.json`: counts and preserved gates; native counts are unique, not added across reruns.
- `sql-counts.json`: all 33 suite basenames and 1,245 assertion total.
- `populated-upgrade.json`, `final-populated-upgrade.json`: baseline digest and exact migration SHA-256 values, no credentials.
- `http-results.json`: four full journeys, independent active seed and all five race invariants.
- `native-focused.json`: 244 pass / one community fixture failure on application source.
- `native-paced-matrix.json`: steps, recovery and matrix pass; publication correctly refuses the prior open community fixture. MCP returned a 300-second timeout while Xcode completed; this xcresult is authoritative.
- `native-final-steps-community.json`: two pass on the fresh stack, including new deleted/unresolved replacements and all community disclosure/minimum checks.
- `ui-signal-retained.json`: five UI tests pass; actual screenshot artifacts are under `../../../.lavish/p9-assets/`.
- `large-text-lifecycle.json`: 18 pass, including the new Health views at Accessibility 3 in both appearances, all seven readiness states and deletion owner isolation. These cases also passed in the aggregate run.
- `iphone-guard.json`: source and built-app product guard.
- `native-final-unlock.json`: 17 passed on final app source, including actual native unlock notification delivery without a connected Health source, and stopping after sign-out.
- `cleanup.json`: closed runtime and removed owner-labelled resources / owned Simulator.

## Exact commands / selections

Core (application code unchanged between this run and the source commit):

```sh
swift test --package-path ios/GameTimeCore
```

Passed 182 tests in 20 suites. Local full output:
`/private/tmp/gametime-p9-core-final.log`.

Affected endpoint boundaries:

```sh
deno test --config supabase/functions/deno.json --allow-env --allow-read \
  supabase/functions/ingest-challenge-health supabase/functions/ingest-metrics \
  supabase/functions/activity-diagnostic supabase/functions/personal-sync-coverage
```

96 passed. Output: `/private/tmp/gametime-p9-edge-configured.log`.

Static checks:

```sh
deno check --config supabase/functions/deno.json scripts/p9-signal-health-controller.ts
deno lint --config supabase/functions/deno.json scripts/p8-real-health-http.ts \
  scripts/p9-signal-health-controller.ts supabase/functions/ingest-challenge-health/handler.ts \
  supabase/functions/ingest-challenge-health/handler.test.ts
deno fmt --check --config supabase/functions/deno.json scripts/p8-real-health-http.ts \
  scripts/p9-signal-health-controller.ts supabase/functions/ingest-challenge-health/handler.ts \
  supabase/functions/ingest-challenge-health/handler.test.ts
PYTHONPYCACHEPREFIX=/private/tmp/gametime-p9/pycache python3 -m py_compile \
  scripts/p8-real-health-verify.py scripts/p9-signal-health-verify.py
python3 scripts/check-iphone-product.py
python3 scripts/check-iphone-product.py --app /private/tmp/gametime-p9-native/Build/Products/Debug-iphonesimulator/GameTime.app
git diff --check
```

Owned SQL setup used the P9 wrapper’s `prepare`/`apply-forward` actions, then this
exact generated selector list on committed source. Each pgTAP suite runs in the
separate owned fresh-test database, while `check` also verifies populated digests:

```python
import json, subprocess
cmd = ['python3', 'scripts/p9-signal-health-verify.py', 'check',
       '--manifest', '/private/tmp/gametime-p9/stack.json']
for suite in json.load(open('outputs/reports/p9-evidence/sql-counts.json')):
    cmd += ['--tap', suite]
subprocess.run(cmd, check=True)
```

All 33 passed. Output: `/private/tmp/gametime-p9-focused-sql-final.log`; private
per-suite output under `/private/tmp/gametime-p9/stack-receipts/`. For the final
community fixture, guarded `rebuild`, then `apply-forward --tap
523_challenge_signal_health_v2` passed another 93 assertions. The manifest was
removed by final cleanup; never point these commands at an unrelated stack.

Signed HTTP (controller stopped first, each metric sequentially):

```sh
deno run --config supabase/functions/deno.json --allow-env \
  --allow-read=/private/tmp/gametime-p9/stack.json --allow-net=127.0.0.1 --allow-run=docker \
  scripts/p8-real-health-http.ts /private/tmp/gametime-p9/stack.json steps
```

Repeat with `exercise`, `distance`, `timed`; then an independent `steps
--retain-active` seed followed by:

```sh
python3 scripts/p8-real-health-concurrency.py --manifest /private/tmp/gametime-p9/stack.json
```

Logs: `/private/tmp/gametime-p9-http-{steps,exercise,distance,timed}.log`,
`/private/tmp/gametime-p9-http-race-seed.log`, `/private/tmp/gametime-p9-concurrency.log`.

Native execution used XcodeBuildMCP `test_sim` with session defaults:

```json
{
  "projectPath": "/Users/user/Documents/GitHub/GameTime/ios/GameTime/GameTime.xcodeproj",
  "scheme": "GameTime",
  "configuration": "Debug",
  "simulatorId": "441394F3-899F-4681-97A2-A9BA7BEC20AC",
  "derivedDataPath": "/private/tmp/gametime-p9-native"
}
```

The owned device was iPhone 17 Pro / iOS 26.5, named GameTime-P9-Signal-20260920.
`test_sim` arguments were `progress: false`, and `extraArgs` began with
`CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled`, `NO`, followed by
`-only-testing:GameTimeTests/<suite>` for each entry of `native-suites.json`.
The paced matrix rerun selected `GameTimeTests/ChallengeHealthOrdinaryAppTests`.
The final fresh-stack run selected only its `testStepsCorrectionReviewAndFinalHistoryInOrdinaryRoot`
and `testZCommunityReadinessDisclosureAndOutcomeMinimum` methods.

The five UI selectors were:

```text
GameTimeUITests/ChallengeHealthSignalUITests
GameTimeUITests/GameTimeUITests/testMainModeCanStartNowAndExposeSyncNow
GameTimeUITests/GameTimeUITests/testPersonalDetailContainsLockedTermsAndNoCompetitiveLanguage
GameTimeUITests/GameTimeUITests/testSignalProductShellPreservesAccountAndExistingChallenges
GameTimeUITests/GameTimeUITests/testTodayShowsAutomaticPersonalProgressTimeline
```

Local artifacts live under
`/Users/user/Library/Developer/XcodeBuildMCP/workspaces/GameTime-7b9ccaa5aefb/`.
Each portable native JSON names its exact result bundle. Matching logs and test
products remain alongside it. The final extended steps/community log is
`logs/test_sim_2026-09-20T06-25-58-892Z_pid30447_0234bc59.log`.

## Failure artifacts retained

These are intermediate failures, with corrected/re-run disposition in the report:

| Case | Local result bundle suffix / log |
| --- | --- |
| Combined initial native fixture checks | `test_sim_2026-09-20T05-22-07…1e54ccb1.xcresult` |
| Invalid test key, Exercise reader checks | `test_sim_2026-09-20T05-34-06…ccb187c8.xcresult` |
| Wrong UI timezone control | `test_sim_2026-09-20T05-46-22…1be0a166.xcresult` |
| Simulator launch/preflight | `test_sim_2026-09-20T05-48-49…9b6ff75b.xcresult`, `test_sim_2026-09-20T05-52-44…75b95397.xcresult` |
| Wrong final-return text assertion | `test_sim_2026-09-20T05-58-34-795Z_pid30447_f9bb2a01.xcresult` |
| Actor discovery quota | Exact path in `native-focused.json` |
| Existing open community / MCP reply timeout | Exact path in `native-paced-matrix.json` |
| Missing Deno config | `/private/tmp/gametime-p9-edge-final.log` |

Earlier uncommitted development states are not claimed reproducible as the final
source. No private manifest, token, source record, route or suggestion baseline
is included in this evidence directory.

The final unlock run used the same project/scheme/derived data on a second owned
iPhone 17 Pro / iOS 26.5 Simulator, `D400F1A0-0B66-495C-BE8F-4C6B938750E4`
(GameTime-P9-Unlock-20260920). Exact selectors were
`GameTimeTests/ChallengeHealthFlowStoreTests` and
`GameTimeTests/PersonalHealthBackgroundDeliveryTests`, with the same signing/serial
arguments. This Simulator was also removed after its passing result.
