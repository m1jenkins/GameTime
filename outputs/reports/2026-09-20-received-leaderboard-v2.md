# D141 received-score leaderboard — focused local record

September 20, 2026. Started from local main at D140 `110c470`, in the isolated
`codex/received-leaderboard` worktree. The original checkout had unrelated,
uncommitted private-device work; it was not edited by this task. Main later
advanced independently to `7bca11c`; its committed private-device changes are
preserved during integration. No push, deployment, hosted gate change, physical
Health upload, distribution or recruitment was performed by this task.

## Delivered behavior

Four NEW `friend_*_leaderboard_v2` agreements freeze the received-by-correction-
cutoff rule, source, missing/partial/failure treatment and existing timing.
Eligible saved totals and best whole-run times rank without complete Health
history. No valid score is unranked with that entry returned; fewer than two
valid remaining scores voids and returns all entries. Normalized ties, review,
exits, privacy and nonredeemable allocation remain. First saves and corrections
count through end +48 hours inclusive only for the new policy. Strict Exercise
v1 stays unavailable; new Activity minutes use Exercise credit v2.

Signal selects v2 only for new real leaderboard creation and shows the saved
score, its server update time, deadline and Refresh. Local values and pending
delivery are distinct. Lost replies retain exact signed recovery, including
after cutoff, and errors direct the person to recovery/review. A void keeps a
saved score visible without a rank. Private timed leaderboards have no goal-time
instruction. Historical agreement and Personal behavior remain unchanged.

D141, the copy contract and active plans describe the change. D140's original
entry is byte-for-byte unchanged, and leaderboards remain outside the required
nine-goal Beta release set. Dated reports were not rewritten. The separately
authorized hosted private trial remains personal-steps-only; this local feature
does not widen it.

## Checks actually run

Using the existing P8/P9 disposable loopback harness:

- 87 assertions in `527_challenge_received_leaderboard_v2` passed (originally
  named `526_challenge_received_leaderboard_v2` before concurrent main used 526).
  Covers authenticated creation/freeze and old creation rejection, all four
  metrics, partial/missing scores, ties, downward corrections, deletion, minimum,
  exact cutoff, one-microsecond-late rejection, server timestamps, exact receipt
  recovery after cutoff/gate closure, and review protection. New helpers remain
  private. No raw Health data is used.
- 93 preserved P9 assertions in `523_challenge_signal_health_v2` passed: old
  leaderboard voids, goal results/missingness, strict Exercise v1 and credit v2.
- The harness applied all nine forward migrations to the retained 85-migration
  baseline and its independent fresh database. Its existing 30-assertion steps
  fixture ran during setup. Historical populated agreement/consent digest stayed
  `0fea3f2a3ddd2c5741da60df5c9b6f14fef7ebbe735c5f491cb47c63c480e1cf`.
- Local Supabase security advisors (`--type security --level error --fail-on error`)
  against the owned numeric-loopback database returned no issues. No linked
  project was queried.

Native checks used XcodeBuildMCP, Debug, iOS 26.5 simulator
`GameTimeCleanBaseline-20260915`, code signing disabled. Twenty-one distinct
focused native tests passed across the implementation runs: Health flow,
source adapters, actor/session fencing, unknown/deleted activity, cutoff/recovery,
policy parsing, ranking and Signal rendering. Source corrections received
focused reruns. Final integration checks are recorded below.

`check-iphone-product.py --app /private/tmp/gametime-d141-checks/DerivedData/Build/Products/Debug-iphonesimulator/GameTime.app`
passed: iPhone product, HealthKit linked, no Watch payloads or links.
`git diff --check` passed. A source comparison confirmed D140 was unchanged.

The first SQL run failed in the new test fixture because its age row omitted
an existing required `policy` field. The fixture was corrected; no production
change was needed, and the full focused suite passed. Native runs had no failed
checks. The initial build retained an existing unrelated WeeklyModels warning;
later incremental builds emitted none.

## Reproduction and limits

Use `scripts/p8-real-health-verify.py prepare` with a fresh private manifest,
then `apply-forward` with every September 20 migration in order via repeated
`--forward-migration`, then `check --tap 527_challenge_received_leaderboard_v2
--tap 523_challenge_signal_health_v2`. Always use an owned disposable stack,
never another checkout's stack or hosted credentials. `cleanup` verifies owner
labels before removing resources. Manifests contain generated local credentials;
they remain private and are never committed.

Native selectors are `GameTimeTests/ChallengeHealthFlowStoreTests`,
`GameTimeTests/ChallengePresentationTests`, and
`GameTimeTests/ChallengePolicyTests/testCanonicalUnitsAndStrictInputBounds`.
The build uses the checked-in project; no test framework was added.

No requested focused check was blocked. The full weekly gate, release matrix,
soak/load, physical-device/Health, hosted and distribution campaigns were
intentionally not run. Local software checks do not accept those gates. No
concrete local implementation blocker remains; using this feature on hosting
requires separate authorization and retains the current private-trial limit.
