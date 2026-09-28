# Legacy UI suites skipped with the owner's approval

Change on `claude/legacy-uitest-skip`, from `036d1bc`, September 27–28, 2026,
fast-forwarded into `main` and pushed. Nothing hosted was touched.

## The decision

Game Time Dev approved skipping the 51 legacy UI tests on September 27, under
Mason's September 27 autonomy mandate for finishing the TestFlight beta. That
answers the open owner input in the
[friends TestFlight plan](../../docs/FRIENDS_TESTFLIGHT_PLAN.md#open-owner-inputs),
raised by the [iOS CI receipt](2026-09-27-ios-ci.md#the-legacy-suites-not-changed).
The tests are skipped, not deleted. Each keeps its code, and its entry says
what would repair it.

## What is skipped

| Suite | Skipped | What the tests drive |
| --- | --- | --- |
| `GameTimeUITests` | 32 of 32 | The Personal Today, Challenges and You tabs, the old Personal creation flow and the Signal shell |
| `DuelUITests` | 11 of 11 | Friend duels, opened from the old You screen |
| `PerformanceCommitmentUITests` | 8 of 8 | Running goals, opened from the old You screen |

That's 51 tests: every test in the three suites, and exactly the 51 legacy
failures in CI run
[36369494374](https://github.com/m1jenkins/GameTime/actions/runs/36369494374)
at `8b947c9`. That run's only other UI failure, the friends accessibility
audit, was fixed in `036d1bc`.

Nothing else is skipped. `LiveDesignUITests`, including the friends audit,
`GameTimeTests`, the conformance harness, the preflight and legal-site script
tests, `check-beta-candidate.sh --personal-copy-only` and the product guard run
as before. `ChallengeV1UITests`, `SignalCreationUITests` and
`ChallengeHealthSignalUITests` still skip themselves on CI because they need an
owned local controller. That's unchanged.

## How

[`RetiredShellSkips.swift`](../../ios/GameTime/GameTimeUITests/RetiredShellSkips.swift)
lists the 51 tests by name, each with one of five reasons. Each suite's
`setUpWithError()` calls `RetiredShellSkips.skipIfListed(self)` first, so a
listed test throws `XCTSkip` before the app launches. xcodebuild counts the
test as skipped and prints its reason:

```
-[GameTimeUITests.DuelUITests testCreateConsentReceiptAndLostResponseRecovery] : Test skipped - Retired You → Friend duels entry (old YouView, add54cf). Restore the entry in the new You tab behind the Debug/Staging and launch-argument gates, or rewrite this coverage, then remove its skip.
```

A test that isn't listed runs normally, including any test added to these
suites later. The scheme, the workflow and the app's code are unchanged.
`XCTSkip` is what the three controller-owned suites above already use.

## Why they fail

`add54cf` (September 22) made `AppShellView` show `LiveChallengeShell` in place
of the Personal tab shell. `AppShellView` says so: "the retired Personal tab
shell is not mounted". The new shell's tabs are `beta.tab.*` buttons rather
than a system tab bar, and nothing shows the old navigation bars or the old You
screen's entries. Each test fails at its first navigation step:

| Tests | First wait that fails on CI |
| --- | --- |
| The 13 Personal-detail tests | The "Your challenge" navigation bar |
| `testSignedOutAndPublicHandleOnboardingRoots` | The test-environment line on the sign-in screen |
| `testAccountDeletionFailureRemainsVisibleAndRecoverable` | The old You tab, to open account support |
| The 17 retired-flow tests | The "Today" navigation bar, `personal.create`, the old You tab, the old empty state, or the Signal shell's `signal.service.closed` |
| All of `DuelUITests` and `PerformanceCommitmentUITests` | The old tab bar's You button |

## Repair plan

### 1. Next: the 13 Personal-detail tests

- `testStripeMissReviewUsesFixedReasonAndShowsSettlementPausedState`
- `testSandboxMetResultShowsZeroTestCharge`
- `testSandboxMissingResultShowsZeroTestChargeAndGuarantee`
- `testExpiredReviewStatesOnlyThatTheRequestWindowEnded`
- `testPaymentStatusCardCoversEveryAuthoritativeStateAndActionSet`
- `testPaymentStatusUnavailableRoutesToSupportWithoutPaymentRetry`
- `testPaymentStatusManualRefreshMovesPendingToCharged`
- `testPaymentStatusRefreshFailureKeepsStaleReviewAndDisablesReview`
- `testPaymentStatusReviewCardSupportsAccessibilityXXXLAndReduceMotion`
- `testScheduledAndCancelledFixturesUseLifecycleSpecificCopy`
- `testPersonalDetailContainsLockedTermsAndNoCompetitiveLanguage`
- `testActiveStripeSandboxCancellationRetainsCancelledHistory`
- `testAwaitingAndCompletedStripeSandboxChallengesCannotCancel`

They open a Personal challenge with `--fixture-open-result-challenge` or
`--fixture-open-active-challenge`. `LivePersonalRouteBridge` still turns those
routes into the `LivePersonalDetailView` sheet, which keeps many of the old
identifiers: `personal.result`, `personal.payment.status.*`,
`personal.review.request` and `personal.cancel`. The sheet titles its page from
the challenge's terms, and shows "Your challenge" only while it loads. So each
test's first wait needs a new anchor inside the sheet. Then check the rest of
the test against the new layout, and remove its entry once it passes.
Repairing these also brings back `assertNoForbiddenLanguage` on Personal
detail.

### 2. Rewrite: sign-in, onboarding and account deletion (2)

- `testSignedOutAndPublicHandleOnboardingRoots`
- `testAccountDeletionFailureRemainsVisibleAndRecoverable`

The new shell has its own versions of these screens, with different copy.
`LiveDesignUITests` covers part of them in
`testOnboardingSavesProfileAndAccountSignOutClearsTheNewShell`,
`testNewSettingsPreserveHealthPrivacyAndAccountDeletionConfirmation` and
`testLargestTextKeepsOnboardingConsentAndExitReachable`. Rewrite what those
don't cover, such as recovery from a failed deletion, and retire the rest.

### 3. Stay skipped until new flows exist: 17 retired-flow tests

- `testSignalProductShellPreservesAccountAndExistingChallenges`
- `testDirtyCreationCloseUsesExactDiscardDialog`
- `testOnlyThreePersonalTabsAreReachable`
- `testDemoEnvironmentDisclosureAcrossTabsAndVisibleCreationSheet`
- `testStripeSandboxFlowUsesFixturePaymentAndExactConsent`
- `testTodayShowsAutomaticPersonalProgressTimeline`
- `testPersonalProgressReplacementFixturesStayConsistentAcrossSurfaces`
- `testNoDataStaleAndUploadDelayFixturesExplainProgressHonestly`
- `testPendingCancellationFixturesStayActionableAndRouteToSupport`
- `testCumulativeCreationOmitsFixedMetricAndStartSteps`
- `testMainModeCanStartNowAndExposeSyncNow`
- `testCompletedAppleHealthPermissionCarriesIntoCreation`
- `testLegacyDiagnosticAndHoldStateStayOutOfPersonalV2UI`
- `testSavedSandboxPaymentRequestCanResumeAfterRelaunch`
- `testLoadingEmptyAndOfflineStates`
- `testSettingsKeepPrivacyHelpDocumentsAndAccountActionsReachable`
- `testPersonalDynamicTypeAccessibilityLabelsAndReduceMotion`

These start from the old Today tab, the old Personal creation flow or the
Signal shell. Those steps no longer exist, and the bridge "does not enable ...
old creation". They stay skipped until a replacement flow exists, and then get
rewritten or retired. A few of their later checks, such as a pending
cancellation or a saved creation request, have equivalents on the new Personal
history and detail screens (`personal.cancellation.*`, `personal.creation.*`),
and could move into the repaired detail tests sooner.

### 4. Friend duels (11) and Running goals (8)

`DuelUITests`:

- `testSummaryAndFullRulesDoNotAcceptInvitation`
- `testCreateConsentReceiptAndLostResponseRecovery`
- `testIncomingAcceptanceAndCancellationRetainHistory`
- `testGateOffDeclineWorksAtAccessibilityTextSize`
- `testCorrectedNoticeReviewAndLostResponseRecovery`
- `testBlockedContactStillAllowsSafeExitAtAccessibilitySize`
- `testFinalResultKeepsSimulatedReturnSeparate`
- `testRecordedReturnIsExplicitlySimulated`
- `testNormalPersonalLaunchHasNoDuelEntry`
- `testLinkOpensReviewWithoutConsentAndRejectsReplacement`
- `testRematchFreshConsentAndLinkRevocation`

`PerformanceCommitmentUITests`:

- `testSummaryKeepsAmountAndFullRulesBeforeConsent`
- `testGoalConsentAndExactRecovery`
- `testChangingPreviewRequiresFreshConsent`
- `testCorrectedResultReviewSurvivesLostResponseWithGateOff`
- `testFinalResultDoesNotInventSimulatedReturnOrAllowExit`
- `testAppendedSimulationIsSeparateAndNonredeemable`
- `testGateOffSafeExitAtAccessibilitySize`
- `testNormalPersonalLaunchHasNoRunningGoalEntry`

These open Friend duels and Running goals from the old You screen (`YouView`,
now unused). The duel acceptance still names "You → Friend duels" as the
fixture entry. A repair needs those entries back in the new You tab, behind
the existing Debug/Staging and launch-argument gates (`--duels`,
`--commitments`), and a bridge for duel invitation links, which still set the
old router's `youPath`. The alternative is new coverage written for the new
shell.

`testNormalPersonalLaunchHasNoDuelEntry` and
`testNormalPersonalLaunchHasNoRunningGoalEntry` only check that a normal launch
shows neither entry. They're the cheapest to restore: open `beta.tab.you` and
check the same absences. Restore them no later than the entries themselves.

## What the skip costs

None of these tests got past its first navigation step, so CI loses no check
that was passing. But:

- Until the repairs above, a passing iOS job includes no UI test of Personal
  detail, Friend duels or Running goals. `LiveDesignUITests` covers the new
  shell.
- `assertNoForbiddenLanguage`, the Personal wording check in
  `GameTimeUITests`, doesn't run while those tests are skipped. The static
  Personal copy audit, `check-beta-candidate.sh --personal-copy-only`, still
  runs in CI.
- Once "Test product app" passes, CI runs the steps after it again: the
  Staging and Release builds and the conformance harness, which it skipped
  while the product tests failed.

## What was run

Xcode 27.0 (27A5237l) on a new iPhone 17 Pro simulator with iOS 26.5, using
CI's commands with a local destination and derived-data path:

| Check | Result |
| --- | --- |
| `bash scripts/tests/check-beta-candidate.test.sh` | Passed |
| `python3 scripts/tests/build-legal-site.test.py` | 6 tests passed |
| `bash scripts/check-beta-candidate.sh --personal-copy-only` | 1 passed, 0 blockers |
| `python3 scripts/check-iphone-product.py` | Passed |
| `GameTime` `build-for-testing`, Debug | Succeeded, with no warnings in the changed files |
| The three legacy suites alone | 51 of 51 skipped, none failed, in 8 seconds. The skipped set equals the list: 13, 2 and 17 in `GameTimeUITests`, 11 and 8 in the others |
| The full `GameTime` scheme `test`, as in CI's "Test product app" | UI: 86 tests, 16 passed (all of `LiveDesignUITests`), 70 skipped (these 51 and the 19 controller-owned tests), none failed. Unit: 647 passed, 11 skipped, 1 failed; see [a false failure](#a-false-failure-in-a-unit-test). 21.5 minutes |
| `ChallengeRestrictionTests` alone, three times | 9 of 9 passed twice. The third run never started: the Simulator refused the launch ("Busy: Application failed preflight checks") |
| `GameTime-Staging`, Staging, generic iOS Simulator, unsigned | Build succeeded |
| `GameTime`, Release, generic iOS Simulator, unsigned | Build succeeded |
| `GameTimeConformance` `test` | 10 of 10 passed |

CI's run at `036d1bc`,
[36376804963](https://github.com/m1jenkins/GameTime/actions/runs/36376804963),
finished before this change was pushed. With Xcode 26.2, exactly the 51 listed
tests failed. `LiveDesignUITests` passed 16 of 16, including the friends audit
fixed in `036d1bc`, and the unit tests passed: 647 passed, 11 skipped. CI then
skipped the Staging and Release builds and the conformance harness, as it does
whenever the product tests fail.

## CI after the push

Run [36380467263](https://github.com/m1jenkins/GameTime/actions/runs/36380467263)
at `6653b41` passed all four jobs: Database, Edge Functions, Client Core and
iOS. It's the first green `main` run since `f47890c` on August 4. The iOS job
took 56 minutes with Xcode 26.2 and iOS 26.2:

| Step | Result |
| --- | --- |
| Script checks, before the Xcode steps | Passed |
| Test product app, UI | 86 tests: 16 passed (all of `LiveDesignUITests`), 70 skipped, none failed. The log prints the reason for each of the 51, and the skipped set equals the list |
| Test product app, unit | 647 passed, 11 skipped, none failed. All four `ChallengeRestrictionTests` mounted tests passed |
| Build staging and release products | Passed. No `main` run had reached this step since August 4 |
| Test conformance harness | 10 of 10 passed. No `main` run had reached this step since August 4 |

## A false failure in a unit test

In the full local run,
`ChallengeRestrictionTests.testMountedDetailEqualRevisionUpdatesWithoutAnotherFetch`
failed at `XCTAssertFalse(after.contains("321"))`, line 143. The assertion
checks that a restricted friend's 321 steps are gone from the goal page. They
were gone. The captured page read "updated sep 28, 2026 at 4:44:10.321728 am
gmt": `ChallengeInstant.text(zone:)` prints microseconds, the fixture stamps
its rows with the current time, and this time the microseconds contained
"321". `testMountedDetailHigherRevisionUpdatesWithoutAnotherFetch` makes the
same check, and each of the two fails this way in about 1 run in 250. This
change doesn't touch unit tests, so it's left as found. Checking for
"321 steps" instead would remove the chance match.

Found in passing: the same "Updated" line on a goal's People section
(`LiveGoalDetail.swift:448`) shows those microseconds to the person whenever
the recorded time has a fraction, as it does in this fixture.

## Limits

- CI uses Xcode 26.2 and iOS 26.2, which aren't installed here.
- The skip matches XCTest's test name, `-[GameTimeUITests.Suite testMethod]`.
  CI's logs at `8b947c9` print that format with Xcode 26.2, and it matched all
  51 tests here with Xcode 27.
- A renamed test drops off the list and runs again, so it fails visibly rather
  than hiding. An entry for a deleted test does nothing.
- No VoiceOver or device check was made.
