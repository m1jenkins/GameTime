# Clean Signal baseline — September 15, 2026

The cleanup is implemented on `fm/gametime-clean-baseline-20260915`, based on
published main `1dacc6644f2100567d85fbaa2970bb7285bbaa35`. Final implementation
commit: **`fab88d1a9b1a5bc6a559e76a9d3674cb8025300d`**. Following documentation
commits contain this report, screenshots and supervisor cleanup updates; resolve the delivered tip with
`git rev-parse fm/gametime-clean-baseline-20260915`. No app behavior, historical
consent, source policy, readiness flag, migration or stored data changed.
Firstmate owns the final fast-forward, push and guarded resource retirement;
this worker did none of those actions.

## Result

- Ordinary native launch and retained routes already use Signal. Removed the
  last unused Matchday icon implementation after finding no consumers. The
  synchronized Xcode source group needs no explicit file-list repair.
- Replaced the 911-line root README with current status, navigation, local build
  instructions and a short explanation of the distinct data contracts. Reconciled
  working baseline, project memory, remaining plan/prompts and native guide with
  all completed work published through `1dacc66`. XcodeBuildMCP now defaults to
  the product project/scheme rather than the separate conformance harness.
- Removed **132 tracked files / 68,483,219 bytes** of obsolete material. Git history
  at the published parent retains every removed byte. Historical document links
  now point to that version rather than absent local exports.
- Repaired two observed stale UI assertions: shared deletion warning updated to
  the disclosure landed in `ece3f1e`; ordinary-shell account navigation queries
  the actual native `You` tab instead of an identifier not exposed by the tab bar.
  Shipping copy and deletion behavior remain unchanged.

## Removal evidence and retained exceptions

| Category | Files | Why removable |
| --- | ---: | --- |
| `.lavish` Matchday/Clubhouse mirrors and wrappers | 40 | 37 byte-identical copies of former `outputs/design` exports; three redundant review wrappers. No native/build/script consumers. Other `.lavish` acceptance and decision reports remain. |
| Superseded September 6/7 concept exports and prompts | 47 | Unselected raster/HTML/SVG/ZIP studies and generation inputs, superseded by Signal. Historical README decisions/research remain; c8's exact `02-home-refined.png` reference remains. |
| Old challenge/Better Bet exports and design prompts | 38 | No current build consumers; replaced visual references. Retained historical guidance links removed assets/prompts to their exact Git-history version. Cobalt approval image, design/implementation/verification records and native screenshots remain. |
| Pre-simplification plan snapshots | 2 | Exact backup copies superseded by the operative remaining plan/prompt pack; historical simplification report now identifies recovery in Git history. |
| `.ua` generated maps | 4 | Map metadata identifies September 3 source `8e2e074`; stale graph, fingerprints, scan and metadata removed. Tool configuration/exclusions remain; generated outputs are ignored. |
| `MatchdayMetricIcon.swift` | 1 | Only occurrence of its type was its definition. Signal uses native symbols; no test, preview or build reference requires this Debug-only component. |

Preserved: adopted Signal study and its checks; the companion Fieldwork study
still referenced by Signal's browser comparison/check; all required licenses;
all native/release/source decision evidence and dated failures; migrations,
behavioral fixtures and tests; historical Personal/Solo/charity/weekly/duel/
commitment contracts; inert historical Watch source. No unique branch, stash,
uncommitted file or other checkout's ignored artifact was discarded. No new
archive directory was created to relocate retired material.

## UI reconciliation and evidence

Static inspection confirms `GameTimeApp` installs `SignalAppearance` and uses
`SignalProductShell` ordinarily. It shares `ChallengeV1Shell` and
`AppAccountNavigationView`; **Existing challenges** opens the retained
`AppShellView`. New challenge views and retained Personal, account, privacy,
deletion, weekly, duel and commitment routes use Signal components. No active
Cobalt/CompetitiveTrust/Barlow references, custom-font calls or bundled font files
remain. The asset catalog contains only the existing app icon. Historical names
in dated evidence are not runtime inputs.

Representative screenshots were exported byte-for-byte from the actual local
XCTest result bundles and visually inspected. All figures are fictional fixtures.

| View | Evidence / observation |
| --- | --- |
| Ordinary signed-in closed service | [Home](2026-09-15-clean-baseline/screenshots/signal-default-signed-in-home.png): native tabs, Signal typography, simulation disclosure and retained access; no invented account scores |
| Populated fixture | [Home](2026-09-15-clean-baseline/screenshots/signal-home-page-0.png): open rows, exact totals, opaque progress and system controls |
| Large text | [Home](2026-09-15-clean-baseline/screenshots/signal-home-accessibility-page-0.png): stacked labels and totals; content continues by scrolling |
| Dark/solid six-person layout | [Detail](2026-09-15-clean-baseline/screenshots/signal-people-6-large-dark-solid-page-0.png): adaptive colors and readable date/rule rows; all pages checked by the existing render test |
| Personal agreement | [Distance goal](2026-09-15-clean-baseline/screenshots/signal-agreement-personal_distance_goal_v1-page-0.png): approved opaque accent band, units, dates, simulation and full rules |
| Signed-out route | [Sign-in](2026-09-15-clean-baseline/screenshots/signal-historical-sign-in.png): Signal styling with retained Personal copy |
| Onboarding | [Profile](2026-09-15-clean-baseline/screenshots/signal-historical-onboarding.png): Signal fields; the fresh Simulator keyboard tutorial obscures the lower portion of this capture, so it is not full-screen acceptance |

The corrected run also records [retained privacy](2026-09-15-clean-baseline/screenshots/retained-privacy.png),
[the unchanged deletion warning](2026-09-15-clean-baseline/screenshots/retained-deletion-confirmation.png)
and [the Personal receipt at accessibility XXXL](2026-09-15-clean-baseline/screenshots/retained-receipt-accessibility.png).
Navigation/actions pass the focused journey checks; a single scroll position is
not proof that all content fits at once. No physical Health, real Apple sign-in,
hosted service, human VoiceOver/comprehension or release readiness is inferred.

## Focused validation

Toolchain: **Xcode 27.0 (27A5237l), iOS 26.5 (23F77)**, task-created iPhone 17 Pro
Simulator `10F34302-A5E8-43D6-BB55-C4111B96E8F3`. All build/log/result outputs are
under this worktree's ignored `tmp/clean-baseline/`; no shared Simulator or stack
was reset. No pipeline or full release matrix was run.

| Check | Result |
| --- | --- |
| Debug `GameTime` build-for-testing | PASS: app, core dependency and native/UI test targets built after icon removal |
| iPhone source + built-product guard | PASS: 153 source inputs, expected three targets/schemes, HealthKit linked, no Watch payload/link/runtime symbols |
| `AppModelAndRoutingTests` | 33 passed |
| `SignalRenderedTests` | 7 passed: all 13 policies across four metrics, long agreements, 2/6 people, compact/large text, dark/solid controls, unknown/corrected/redacted/recovery/community states |
| `SignalThemeAdversarialTests` | 3 passed: contrast, system-font scaling/no font registration, no content drop shadows |
| Initial four UI journeys | 2 passed, 2 failed: stale deletion disclosure and missing `beta.tab.you` selector; failures preserved in `focused.xcresult` and `focused-summary.json` |
| Corrected UI tests plus affected recovery/large-text journeys | PASS: 4 passed, 0 failures/skips; 49 distinct checks passed across the original and corrected runs |
| Documentation/resource links and preservation | PASS: no new broken relative Markdown/HTML links, all changed-document targets resolve; migrations/configuration/readiness/source evidence and historical Watch bytes unchanged; `git diff --check` clean |

Reproduction commands (choose the recorded task-owned simulator/output paths
only while this task still owns them):

```sh
xcodebuild build-for-testing -project ios/GameTime/GameTime.xcodeproj \
  -scheme GameTime -configuration Debug \
  -destination 'platform=iOS Simulator,id=10F34302-A5E8-43D6-BB55-C4111B96E8F3' \
  -derivedDataPath tmp/clean-baseline/DerivedData CODE_SIGNING_ALLOWED=NO
python3 scripts/check-iphone-product.py \
  --app "$PWD/tmp/clean-baseline/DerivedData/Build/Products/Debug-iphonesimulator/GameTime.app"
```

The first `test-without-building` selected the three named native suites plus
`testSignalProductShellPreservesAccountAndExistingChallenges`,
`testSignedOutAndPublicHandleOnboardingRoots`,
`testPersonalDetailContainsLockedTermsAndNoCompetitiveLanguage` and
`testSettingsKeepPrivacyHelpDocumentsAndAccountActionsReachable`.
After fixing the assertions, `xcodebuild test` rebuilt the UI tests and selected
the two failed tests plus `testAccountDeletionFailureRemainsVisibleAndRecoverable`
and `testPersonalDynamicTypeAccessibilityLabelsAndReduceMotion`. Both runs use
`-parallel-testing-enabled NO` and their own result bundles. The compact
[original summary](2026-09-15-clean-baseline/focused-summary.json),
[corrected-run summary](2026-09-15-clean-baseline/retained-recheck-summary.json)
and [product guard result](2026-09-15-clean-baseline/product-guard.json) are committed.
The [exact removed-file list](2026-09-15-clean-baseline/removed-files.txt) accompanies
the category table. The task Simulator was shut down after validation; raw results
remain in the owned output directory for Firstmate's disposition.

Preserved warnings: the first result bundle reports an invalid-frame-dimension
runtime warning during the selected tests; this cleanup does not establish its
origin or repair. The final four UI tests report no runtime warnings. The
reference scan also retains 15 pre-existing unresolved historical paths in old
roadmap/load material (plus one dynamic HTML path the scanner cannot resolve);
none was introduced by these removals. Current entry links all resolve. Build logs retain the existing `WeeklyModels.swift:275`
trailing-closure warning and App Intents metadata notices. The rendering tests
passed despite that runtime warning; this is not a warning-free release claim.

## Branch/worktree disposition and remaining gates

The [complete read-only inventory](2026-09-15-clean-baseline/inventory.md) records
all current/local/remote refs, exact ancestry counts, ignored artifacts, stash
and old-clone recovery. It was delivered to Firstmate before validation finished;
later supervisor cleanup is a separate action and may change those dated facts.

Fully landed candidates: local `codex/consolidate-main`, `codex/crisp-cobalt-ui`
and the P9 branch/worktree; remote `claude/app-language-review-oxo9mf` and
`codex/weekly-local-roadmap`; the old Firstmate clone and its two clean detached
copies. Keep unique archive/Beta1/accessibility/overnight/Signal/Daybreak history
and the stash. The P9 worktree has ignored evidence to preserve. Reconcile **S2/P9
sharing current pool1**, **old scout/validation sharing older pool2**, and stale
**P8 ownership of this now-active cleanup pool2** before any resource removal.

Firstmate subsequently reported guarded cleanup: deleted local
`codex/consolidate-main` and `codex/crisp-cobalt-ui`, deleted remote
`claude/app-language-review-oxo9mf` and `codex/weekly-local-roadmap`, and pruned
remote-tracking refs. The landed P9 copy was retired after preserving 44 MB of
validation in Firstmate's private `gametime-p9-authenticated-app-20260915/retained-validation`
data. Stale duplicate ownership was reconciled with stopped old agents and
backed-up private records; this active cleanup copy was preserved. Old scout
copies were being returned at that update. Seven unique local branches and two
corresponding remotes remain pending the owner's retention/bundle decision.
These are supervisor-reported actions, not worker-executed cleanup; do not claim
that every branch or all older resources have been removed.

P7–P13 remain undispatched by this task. All four physical sources and measured
timed tolerance, real-source ingestion/adapters and integrated 13-policy journeys,
approved HTTPS/Apple/hosted identities and operation, retention/recovery/capacity,
then physical/human/release acceptance remain required. Checked-in transport is
off; all 18 readiness entries remain false. No funds, distribution, outside
messages, real Health reads or hosted mutations occurred.

No unresolved test failure blocks this cleanup delivery. Warning investigation
and physical/human/hosted/release acceptance remain outside the completed scope.
