import XCTest

/// Legacy UI tests skipped with the owner's approval on September 27, 2026.
/// Each one drives a screen that `add54cf` stopped mounting, when
/// `AppShellView` began showing `LiveChallengeShell` in place of the Personal
/// Today, Challenges and You tabs, and each fails at its first navigation step.
/// Only the tests listed here are skipped; any other test in these suites runs.
/// Remove a test's entry in the commit that repairs it. The repair plan is in
/// `outputs/reports/2026-09-27-legacy-uitest-skip.md`. The 13 Personal-detail
/// tests were repaired against `LivePersonalDetailView` on September 28; see
/// `outputs/reports/2026-09-28-personal-detail-uitest-repair.md`.
enum RetiredShellSkips {
    enum Reason: String {
        case accountScreens = "Retired Personal sign-in, onboarding and You screens (add54cf). The new shell has its own versions with different copy, partly covered by LiveDesignUITests; rewrite the test against them, then remove its skip."
        case personalFlow = "Retired Personal Today tab, Personal creation or Signal shell (add54cf). These steps no longer exist; keep this skipped until a replacement flow exists, then rewrite or retire the test."
        case friendDuels = "Retired You → Friend duels entry (old YouView, add54cf). Restore the entry in the new You tab behind the Debug/Staging and launch-argument gates, or rewrite this coverage, then remove its skip."
        case runningGoals = "Retired You → Running goals entry (old YouView, add54cf). Restore the entry in the new You tab behind the Debug/Staging and launch-argument gates, or rewrite this coverage, then remove its skip."
    }

    /// 38 tests, keyed like `-only-testing` identifiers without the target.
    static let listed: [String: Reason] = [
        // GameTimeUITests, 2: sign-in, onboarding and account deletion.
        "GameTimeUITests/testSignedOutAndPublicHandleOnboardingRoots": .accountScreens,
        "GameTimeUITests/testAccountDeletionFailureRemainsVisibleAndRecoverable": .accountScreens,

        // GameTimeUITests, 17: Today, old creation and the Signal shell.
        "GameTimeUITests/testSignalProductShellPreservesAccountAndExistingChallenges": .personalFlow,
        "GameTimeUITests/testDirtyCreationCloseUsesExactDiscardDialog": .personalFlow,
        "GameTimeUITests/testOnlyThreePersonalTabsAreReachable": .personalFlow,
        "GameTimeUITests/testDemoEnvironmentDisclosureAcrossTabsAndVisibleCreationSheet": .personalFlow,
        "GameTimeUITests/testStripeSandboxFlowUsesFixturePaymentAndExactConsent": .personalFlow,
        "GameTimeUITests/testTodayShowsAutomaticPersonalProgressTimeline": .personalFlow,
        "GameTimeUITests/testPersonalProgressReplacementFixturesStayConsistentAcrossSurfaces": .personalFlow,
        "GameTimeUITests/testNoDataStaleAndUploadDelayFixturesExplainProgressHonestly": .personalFlow,
        "GameTimeUITests/testPendingCancellationFixturesStayActionableAndRouteToSupport": .personalFlow,
        "GameTimeUITests/testCumulativeCreationOmitsFixedMetricAndStartSteps": .personalFlow,
        "GameTimeUITests/testMainModeCanStartNowAndExposeSyncNow": .personalFlow,
        "GameTimeUITests/testCompletedAppleHealthPermissionCarriesIntoCreation": .personalFlow,
        "GameTimeUITests/testLegacyDiagnosticAndHoldStateStayOutOfPersonalV2UI": .personalFlow,
        "GameTimeUITests/testSavedSandboxPaymentRequestCanResumeAfterRelaunch": .personalFlow,
        "GameTimeUITests/testLoadingEmptyAndOfflineStates": .personalFlow,
        "GameTimeUITests/testSettingsKeepPrivacyHelpDocumentsAndAccountActionsReachable": .personalFlow,
        "GameTimeUITests/testPersonalDynamicTypeAccessibilityLabelsAndReduceMotion": .personalFlow,

        // DuelUITests, 11.
        "DuelUITests/testSummaryAndFullRulesDoNotAcceptInvitation": .friendDuels,
        "DuelUITests/testCreateConsentReceiptAndLostResponseRecovery": .friendDuels,
        "DuelUITests/testIncomingAcceptanceAndCancellationRetainHistory": .friendDuels,
        "DuelUITests/testGateOffDeclineWorksAtAccessibilityTextSize": .friendDuels,
        "DuelUITests/testCorrectedNoticeReviewAndLostResponseRecovery": .friendDuels,
        "DuelUITests/testBlockedContactStillAllowsSafeExitAtAccessibilitySize": .friendDuels,
        "DuelUITests/testFinalResultKeepsSimulatedReturnSeparate": .friendDuels,
        "DuelUITests/testRecordedReturnIsExplicitlySimulated": .friendDuels,
        "DuelUITests/testNormalPersonalLaunchHasNoDuelEntry": .friendDuels,
        "DuelUITests/testLinkOpensReviewWithoutConsentAndRejectsReplacement": .friendDuels,
        "DuelUITests/testRematchFreshConsentAndLinkRevocation": .friendDuels,

        // PerformanceCommitmentUITests, 8.
        "PerformanceCommitmentUITests/testSummaryKeepsAmountAndFullRulesBeforeConsent": .runningGoals,
        "PerformanceCommitmentUITests/testGoalConsentAndExactRecovery": .runningGoals,
        "PerformanceCommitmentUITests/testChangingPreviewRequiresFreshConsent": .runningGoals,
        "PerformanceCommitmentUITests/testCorrectedResultReviewSurvivesLostResponseWithGateOff": .runningGoals,
        "PerformanceCommitmentUITests/testFinalResultDoesNotInventSimulatedReturnOrAllowExit": .runningGoals,
        "PerformanceCommitmentUITests/testAppendedSimulationIsSeparateAndNonredeemable": .runningGoals,
        "PerformanceCommitmentUITests/testGateOffSafeExitAtAccessibilitySize": .runningGoals,
        "PerformanceCommitmentUITests/testNormalPersonalLaunchHasNoRunningGoalEntry": .runningGoals,
    ]

    /// Call first in `setUpWithError()`, before the app launches.
    static func skipIfListed(_ test: XCTestCase) throws {
        // XCTest names a test "-[GameTimeUITests.DuelUITests testSomething]".
        let suite = String(describing: type(of: test))
        guard let method = test.name.split(separator: " ").last?.dropLast(),
              let reason = listed["\(suite)/\(method)"] else { return }
        throw XCTSkip(reason.rawValue)
    }
}
