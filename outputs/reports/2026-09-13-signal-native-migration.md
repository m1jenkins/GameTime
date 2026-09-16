# Signal native migration — September 13, 2026

P9A implements the adopted [Signal migration contract](../../docs/design/SIGNAL_UI_MIGRATION.md)
in the iPhone app. Ordinary sign-in selects `SignalProductShell`; launch,
onboarding, Home / Challenges / You, challenge flows and retained Personal routes
use the same Signal foundations. Superseded cobalt rendering and font inputs are
removed. This is local presentation work; real source/transport integration and
physical, human and release acceptance retain their separate gates.

## Publication follow-up — September 13, 2026

The owner requested publication of Signal and clarified that no Apple Watch is
available: current development is simulator-only. Native source, tests and
configuration are now on GitHub `main` at
`b351a4775a938056ca229301caa513c3e1d85022`, verified against the remote ref.
All 199 final manifest inputs and the three recorded app executable hashes matched
at publication; the fresh iPhone product guard, Personal copy audit, candidate
preflight fixtures and whitespace checks passed. The native suites below were
not rerun for publication; their source and existing result bundles were preserved.

The complete original migration is committed locally at `823ee0a` on
`codex/signal-native-migration`. Automatic approval review rejected publishing
its additional documentation, reports and screenshots to the public repository;
the successful push contains only the 42 native source/test/configuration files.
Supporting records are restored as local working-copy files. The original source
and scope notes below describe the report's initial, uncommitted state.

Next use Signal for applicable native recovery fixes and authenticated loopback
simulator journeys with fictional activity. Physical P7 remains deferred until
hardware is available; no Watch actions are requested now. Source policy acceptance,
real integration and distribution remain separate from simulator verification.

## Source and scope

- Checkout: `/Users/user/Documents/GitHub/GameTime`.
- Task branch: `codex/signal-native-migration`, based on `b25834c`.
- Changes remain local and uncommitted. The [final source manifest](2026-09-13-signal-native/source-manifest.json)
  identifies 199 repository native/shared/test/configuration inputs; the
  [broad-regression manifest](2026-09-13-signal-native/regression-source-manifest.json)
  preserves the preceding snapshot. Only the final receipt-label reflow differs,
  and its two affected journeys were rerun. A branch name alone is not source identity.
- The owner's existing documentation changes were preserved and extended with
  the actual migration status. The initial documentation patch and original
  migration contract were saved under `/private/tmp/gametime-signal-*`.
- A bounded inspection of the other nine local branches found no applicable
  native Signal candidate. This implementation uses the adopted browser study
  and its refined goal/agreement compositions. It does not validate the earlier
  unlocated native-completion claim or import the separate recovery branch.

## Implemented presentation

`SignalTheme.swift` supplies adaptive light/dark colors, increased-contrast
colors, system semantic typography and scaled tabular metrics. Shared sections
are open, aligned and opaque. Personal goals and agreement summaries use the
adopted opaque accent band; leaderboards use restrained rows. Date facts preserve
the exact start, exclusive end, time zone and calendar duration.

The product shell uses native tabs. Navigation and action capsules use native
iOS 26 material; custom controls have matching solid geometry for older systems,
Reduce Transparency and increased contrast. Motion respects Reduce Motion.
Glass grouping stays within content/control groups, outside the scroll viewport
itself. Totals, histories, rules, consent, results and plots remain opaque.

The retained Personal chart puts its selected-day readout above the plot. Known
values alone form bars; future or unavailable days have unfilled placeholders.
Its selection, text alternatives and original progress calculations remain.
The creation flow uses open sections and adapts goal presets, amount selection
and goal entry to accessibility text sizes. Done moves to the navigation bar
while editing, making keyboard dismissal reachable in the accessibility tree.

The old theme, native cobalt component file, unused decorative field/countdown/
tile/roster components, bundled custom fonts and all three `UIAppFonts`
registrations are removed. There is no selectable cobalt appearance or forced
light mode. Dated browser/native cobalt evidence and the established app icon
are retained as historical evidence and an existing brand asset, respectively.

No request format, policy, store, authentication rule, Health upload, visibility
permission, consent text, agreement, amount or lifecycle rule was changed. The
ordinary challenge client remains unavailable; the local adapter remains
loopback-only. Missing data alone still cannot imply a loss. Community counts
retain the five-person threshold and at-least-15-minute delay. Existing Personal
access, neutral exits, privacy, account support and deletion confirmation remain.

## Verification

Built with Xcode 27.0 (`27A5237l`), using local simulator products with signing
disabled. No physical Health validation is inferred from these products.

| Check | Actual result |
| --- | --- |
| Debug build and iOS 26.5 broad regression suite | 76 passed, 0 failed/skipped/runtime warnings; 60 unit/rendering + 16 UI checks; `/private/tmp/gametime-signal-final.xcresult`, [summary](2026-09-13-signal-native/ios26-test-summary.json) |
| Release simulator build, final app source | Passed; `/private/tmp/gametime-signal-release-final-r2.log` |
| Staging simulator build, final app source | Passed; `/private/tmp/gametime-signal-staging-final-r2.log` |
| iOS 18.6 fallback rendering and focused journeys | 13 passed, 0 failed/skipped/runtime warnings; 10 unit/rendering + 3 UI checks; `/private/tmp/gametime-signal-ios18-final.xcresult`, [summary](2026-09-13-signal-native/ios18-test-summary.json) |
| Final receipt reflow, standard and largest text, iOS 18.6 | 2 passed, 0 failed/skipped/runtime warnings; `/private/tmp/gametime-signal-receipt-final.xcresult`, [summary](2026-09-13-signal-native/receipt-test-summary.json) |
| Largest accessibility text Personal setup, rules, safe dismissal, settings/privacy/deletion | Passed; `/private/tmp/gametime-signal-fixes-r6.xcresult`, 1 test, 0 failures or skips, 134.3 seconds including build |
| iPhone product guard on built Debug, Staging and Release products | Passed; 148 active source inputs across the targets/packages, three intended targets, Health linkage retained, no Watch payload or linkage; [final Debug capture](2026-09-13-signal-native/product-guard.json) |
| Active-source cleanup and whitespace | No cobalt/custom-font/forced-light/drop-shadow references in active app/configuration/project; `git diff --check` passed |

The main simulator is an iPhone 17 Pro on iOS 26.5 (`23F77`). The fallback run
uses an iPhone 13 mini on iOS 18.6 (`22G86`). Its historical device name contains Cobalt;
that name is not an application theme or source input.

### Route and state coverage

| Route/state | Verification |
| --- | --- |
| Ordinary signed-out, profile onboarding, signed-in closed shell, Home/Challenges/You, Existing challenges, sign-out | Native UI journeys and screenshots, using explicit fictional authentication where sign-in is needed |
| All 13 policies: eight friend, four personal, one community | Model-validated native detail renders and full agreement/date/rule renders |
| Two/six people, long name, large metrics, ties, missing value, departed/redacted participant | Compact and accessibility rendering fixtures; no synthesized account activity |
| Community join/detail, delayed count and hidden-threshold state | Native rendering with privacy text/exclusion assertions |
| Loading, empty, offline, unavailable, stale read and exact saved-action recovery | Native renders, UI journeys and focused store/domain regressions |
| Retained Personal creation, Health explanation, payment mode, exact consent, receipts, progress, missing final data and history | Fixture UI journeys plus progress/presentation/store regressions |
| Retained duel invitation/full rules/consent, correction/review, recovery, cancellation and safe exits | Native fixture UI journeys |
| Retained performance consent, recovery, final result and injury exit | Native fixture UI journeys |
| Retained weekly rules, privacy, provisional/final/recovery and closed invitation | Native rendering regressions |
| Light/dark, compact, accessibility, high-contrast solid controls and older-system fallback | UIKit viewport captures, trait-based rendering and simulator journeys |

The all-policy renders supplement touch coverage. The new `challenge_*_v1`
authenticated loopback touch suite was not run: its configured local controller
was absent. No hosted backend or disposable database stack was started for this
presentation migration. This does not establish P8/P9 real integration.

### Failures preserved and resolved

- Initial rendering captures omitted compositor-backed glass or used oversized
  synthetic windows. `SignalRenderedTests` now captures real UIKit viewports and
  scrolls their native content, checks OCR across pages and retains screenshots.
  The initial failures remain in the focused/render probe result bundles.
- A simulation banner applied as a tab safe-area inset clipped the Home header.
  It now sits above the native tab view in the shell layout.
- The first journey pass had 67 passes and 2 failures out of 69. The loading
  container/announcement were restored. Receipt testing now scrolls the complete
  disclosure row above the home indicator before tapping it.
- The Personal accessibility test used an invalid content-size raw value. It
  now obtains the largest value from UIKit. That exposed an inaccessible native
  keyboard toolbar; moving Done into navigation fixed the actual interaction and
  removed the invalid-frame warning in the successful focused rerun. Intermediate
  `gametime-signal-fixes` through `-r5` bundles retain the failures.
- The long initial journey tool response timed out after 300 seconds while
  Xcode continued. Its completed `.xcresult` was inspected; the timeout was not
  counted as a test result. The broad final tool response reached the same limit;
  its completed 76-pass result was also inspected. Staging's x86_64 linker warnings and App Intents
  metadata warning remain recorded in the successful build log.

## Artifacts and remaining acceptance

[Selected native screenshots](2026-09-13-signal-native/screenshots/) include
[ordinary launch without arguments](2026-09-13-signal-native/screenshots/ordinary-launch-signed-out.jpg),
[closed signed-in Home](2026-09-13-signal-native/screenshots/closed-home.png),
[fictional dark Home](2026-09-13-signal-native/screenshots/signal-home-dark-page-0.png),
[opaque personal goal](2026-09-13-signal-native/screenshots/signal-personal_exercise_goal_v1-page-0.png),
compact/large text, long agreements, community privacy, glass/solid controls and
[the final largest-text receipt](2026-09-13-signal-native/screenshots/personal-receipt-accessibility-xxxl.png).
Fixture activity in these captures is fictional. Raw `.xcresult` bundles and
build logs stay in the local paths recorded above; compact summaries and the
source manifests are retained alongside the screenshots. The iOS 18 simulator
is back in its original shutdown state; the iOS 26 simulator shows the ordinary
signed-out app. No physical device was touched.

P7 physical source sessions, real Apple sign-in/HTTPS links and source ingestion,
the integrated P9 journeys, VoiceOver/Switch Control walkthroughs, physical-device
Reduce Motion/Reduce Transparency checks, human comprehension, hosted operation,
capacity/recovery and distribution remain unperformed here. No physical device
was installed, no hosted state or money moved, and no readiness gate was enabled.

P9 should reuse this Signal implementation when connecting accepted real
contracts. P12/P13 qualify that integrated candidate; historical Personal product
retirement still requires its separately recorded replacement acceptance.

## Pruning follow-up — September 15, 2026

The local `codex/signal-native-migration` ref was deleted after committed-object
comparison established that its native source/tests/configuration are incorporated
in published main and its supporting evidence is preserved there. The publication
notes above describe their original dates; they no longer imply that the local
branch exists or that supporting records are only uncommitted. See the
[executed branch disposition](../../docs/HISTORICAL_BRANCH_DISPOSITION_20260915.md).
The original verification results, limitations, screenshots and hashed manifests
retain their historical identities; no native tests were rerun for pruning.
