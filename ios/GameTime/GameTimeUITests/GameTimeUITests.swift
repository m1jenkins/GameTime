import XCTest

@MainActor
final class GameTimeUITests: XCTestCase {
    private enum EnvironmentMode {
        case testOnly
        case stripeSandbox
        case demo

        var copy: String {
            switch self {
            case .testOnly:
                "Test commitment — no money will be charged."
            case .stripeSandbox:
                "Payment test mode — no real money moves."
            case .demo:
                "Demo mode — no money will be charged. Nothing here leaves your phone."
            }
        }
    }

    private let deletionWarning =
        "Your name, username, and profile will be replaced with an anonymous placeholder. Your sign-in and setup saved on this phone will be removed, and your Stripe test customer and saved payment method will be deleted. Your step data will no longer be readable and will be removed on the schedule in the Privacy Policy. A small anonymous record that a challenge existed and how it was scored will remain. This can’t be undone."

    override func setUp() {
        continueAfterFailure = false
    }

    func testSignedOutAndPublicHandleOnboardingRoots() {
        let signedOut = launch("--fixture-signed-out")
        XCTAssertTrue(
            signedOut.buttons["Sign in with Apple"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: signedOut, mode: .testOnly)
        XCTAssertTrue(signedOut.staticTexts["GameTime"].exists)
        XCTAssertFalse(signedOut.staticTexts["Compete fairly."].exists)
        assertNoForbiddenLanguage(in: signedOut)
        signedOut.terminate()

        let onboarding = launch("--fixture-onboarding")
        XCTAssertTrue(
            onboarding.navigationBars["Set your profile"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(onboarding.textFields["Your name"].exists)
        XCTAssertTrue(onboarding.textFields["Username"].exists)
        XCTAssertEqual(
            onboarding.descendants(matching: .any)[
                "onboarding.name.message"
            ].label,
            "Name: 1–50 characters"
        )
        XCTAssertEqual(
            onboarding.descendants(matching: .any)[
                "onboarding.username.message"
            ].label,
            "Username: 3–30 letters, numbers, or underscores; starts with a letter"
        )
        XCTAssertTrue(
            onboarding.buttons["onboarding.use-different-account"].exists
        )
        assertEnvironmentDisclosure(in: onboarding, mode: .testOnly)
        assertNoForbiddenLanguage(in: onboarding)
    }

    func testDirtyCreationCloseUsesExactDiscardDialog() {
        let app = launch("--fixture-empty")
        app.buttons["personal.create"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )

        app.buttons["personal.continue"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Your goal"].waitForExistence(timeout: 4)
        )
        app.buttons["Close"].waitAndTap()

        XCTAssertTrue(
            exactStaticText("Discard this setup?", in: app)
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["Discard changes"].exists)
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 4))
        keepEditing.tap()
        XCTAssertTrue(app.navigationBars["Your goal"].exists)
    }

    func testOnlyThreePersonalTabsAreReachable() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertFalse(app.tabBars.buttons["Friends"].exists)

        for tab in ["Challenges", "You", "Today"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
            tabButton.tap()
            XCTAssertTrue(
                app.navigationBars[tab].waitForExistence(timeout: 3)
            )
            assertEnvironmentDisclosure(in: app, mode: .testOnly)
            assertNoForbiddenLanguage(in: app)
        }
    }

    func testDemoEnvironmentDisclosureAcrossTabsAndVisibleCreationSheet() {
        let app = launch(
            "--fixture-demo-interactive",
            "--fixture-empty"
        )

        for tab in ["Today", "Challenges", "You"] {
            app.tabBars.buttons[tab].waitAndTap()
            XCTAssertTrue(
                app.navigationBars[tab].waitForExistence(timeout: 4)
            )
            assertEnvironmentDisclosure(in: app, mode: .demo)
            assertNoForbiddenLanguage(in: app)
        }

        app.tabBars.buttons["Challenges"].waitAndTap()
        let create = app.buttons["personal.create"]
        for _ in 0..<8 where !create.isHittable { app.swipeUp() }
        create.waitAndTap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .demo)
        assertNoForbiddenLanguage(in: app)
    }

    func testStripeSandboxFlowUsesFixturePaymentAndExactConsent() {
        let app = launch(
            "--fixture-empty",
            "--fixture-stripe-sandbox"
        )
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        XCTAssertFalse(
            app.staticTexts[
                "Test commitment — no money will be charged."
            ].exists
        )

        app.buttons["personal.create"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 6"].exists
        )
        assertHiddenBetaCreationSteps(in: app)
        for title in ["Your goal", "Your amount", "Apple Health"] {
            app.buttons["personal.continue"].waitAndTap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 4)
            )
        }
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.continue"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Test payment"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)

        let consent =
            "By starting, you agree that GameTime may create one $10.00 test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
        XCTAssertTrue(
            exactStaticText(consent, in: app)
                .waitForExistence(timeout: 3)
        )
        let startNow = app.switches["personal.start.now"]
        XCTAssertTrue(startNow.waitForExistence(timeout: 3))
        startNow.tap()
        let setup = app.buttons["personal.payment.setup"]
        XCTAssertTrue(setup.exists)
        XCTAssertFalse(setup.isEnabled)
        app.switches["personal.payment.consent"].waitAndTap()
        XCTAssertTrue(setup.isEnabled)
        setup.tap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertReceiptFact(
            "payment-mode",
            contains: "Test method saved — no real money moves.",
            in: app
        )
        assertReceiptFact(
            "starts",
            contains: "Now — today counts from midnight",
            in: app
        )
        assertReceipt(
            in: app,
            mode: .stripeSandbox,
            expectsSavedDraft: true
        )
        assertNoForbiddenLanguage(in: app)
        let submit = app.buttons["personal.submit"]
        for _ in 0..<8 where !submit.isHittable { app.swipeUp() }
        submit.waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        XCTAssertTrue(app.staticTexts["In progress"].exists)
        XCTAssertTrue(app.buttons["personal.challenge.sync-now"].exists)
    }

    func testStripeMissReviewUsesFixedReasonAndShowsSettlementPausedState() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-stripe-review",
            "--fixture-open-result-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertCumulativeProgress(in: app)
        assertResultTitle("Goal missed.", in: app)

        _ = waitForPaymentStatus(
            "Goal missed — review open. Settlement is paused.",
            in: app
        )
        XCTAssertTrue(
            exactStaticText(
                "Only a confirmed miss after review can create one $20.00 test charge.",
                in: app
            ).exists
        )

        let request = app.buttons["personal.review.request"]
        scrollUntilHittable(request, in: app)
        XCTAssertTrue(
            containing("Ask us to review this result by", in: app).exists
        )
        XCTAssertTrue(request.waitForExistence(timeout: 3))
        XCTAssertTrue(request.isHittable)
        XCTAssertEqual(
            app.buttons.matching(identifier: "personal.review.request").count,
            1
        )
        XCTAssertTrue(
            app.buttons[
                "personal.review.reason.user_disputes_step_data"
            ].exists
        )
        let resultReason = app.buttons[
            "personal.review.reason.user_disputes_result"
        ]
        XCTAssertTrue(resultReason.exists)
        resultReason.tap()
        let selectedReason = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: resultReason
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedReason], timeout: 2),
            .completed
        )

        request.tap()

        _ = waitForPaymentStatus(
            "Under review — settlement paused.",
            in: app
        )
        XCTAssertFalse(containing("Review ends by", in: app).exists)
        XCTAssertFalse(app.buttons["personal.review.request"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testSandboxMetResultShowsZeroTestCharge() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-sandbox-met",
            "--fixture-open-result-challenge"
        )

        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertResultTitle("Goal met — $0 test charge.", in: app)
        _ = waitForPaymentStatus(
            "Goal met — $0 test charge.",
            in: app
        )
        XCTAssertFalse(app.buttons["personal.review.request"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testSandboxMissingResultShowsZeroTestChargeAndGuarantee() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-sandbox-missing-result",
            "--fixture-open-result-challenge"
        )

        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertResultTitle(
            "This one didn’t count — $0 test charge.",
            in: app
        )
        XCTAssertTrue(
            exactStaticText(
                "Missing or unclear step data never counts as a miss.",
                in: app
            ).exists
        )
        _ = waitForPaymentStatus(
            "This one didn’t count — $0 test charge.",
            in: app
        )
        XCTAssertFalse(app.buttons["personal.review.request"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testExpiredReviewStatesOnlyThatTheRequestWindowEnded() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-expired-review",
            "--fixture-open-result-challenge"
        )

        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertResultTitle("Goal missed.", in: app)

        _ = waitForPaymentStatus(
            "Review window ended — settlement update pending.",
            in: app
        )
        XCTAssertFalse(app.buttons["personal.review.request"].exists)
        XCTAssertTrue(app.buttons["personal.payment.status.refresh"].exists)
        XCTAssertTrue(app.buttons["personal.payment.status.support"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testPaymentStatusCardCoversEveryAuthoritativeStateAndActionSet() {
        let cases: [(
            rawState: String,
            label: String,
            hasRecovery: Bool,
            opensActive: Bool
        )] = [
            ("method_saved", "Test method saved.", true, true),
            (
                "review_open",
                "Goal missed — review open. Settlement is paused.",
                true,
                false
            ),
            (
                "under_review",
                "Under review — settlement paused.",
                true,
                false
            ),
            (
                "waived",
                "This one didn’t count — $0 test charge.",
                false,
                false
            ),
            ("no_charge", "Goal met — $0 test charge.", false, false),
            (
                "charge_pending",
                "Processing one $20.00 test charge.",
                true,
                false
            ),
            (
                "charged",
                "Test charge complete — sandbox transaction recorded.",
                false,
                false
            ),
            (
                "requires_action",
                "Test payment needs your attention. We won’t try again automatically.",
                true,
                false
            ),
            (
                "collection_failed",
                "Test payment needs your attention. We won’t try again automatically.",
                true,
                false
            ),
        ]

        for fixture in cases {
            let route = fixture.opensActive
                ? "--fixture-open-active-challenge"
                : "--fixture-open-result-challenge"
            let app = launch(
                "--fixture-stripe-sandbox",
                "--fixture-payment-status=\(fixture.rawState)",
                route
            )
            XCTAssertTrue(
                app.navigationBars["Your challenge"]
                    .waitForExistence(timeout: 5),
                "Failed to open payment fixture \(fixture.rawState)."
            )
            _ = waitForPaymentStatus(fixture.label, in: app)

            let refresh = app.buttons["personal.payment.status.refresh"]
            let support = app.buttons["personal.payment.status.support"]
            if fixture.hasRecovery {
                for _ in 0..<16 where !support.exists { app.swipeUp() }
                XCTAssertTrue(
                    refresh.exists,
                    "Refresh missing for \(fixture.rawState)."
                )
                XCTAssertTrue(
                    support.exists,
                    "Support missing for \(fixture.rawState)."
                )
            } else {
                XCTAssertFalse(
                    refresh.exists,
                    "Terminal state \(fixture.rawState) exposed Refresh."
                )
                XCTAssertFalse(
                    support.exists,
                    "Terminal state \(fixture.rawState) exposed Support."
                )
            }

            XCTAssertEqual(
                app.buttons["personal.review.request"].exists,
                fixture.rawState == "review_open"
            )
            XCTAssertFalse(app.buttons["personal.payment.retry"].exists)
            XCTAssertFalse(app.buttons["Retry payment"].exists)
            XCTAssertFalse(app.buttons["Try payment again"].exists)
            assertNoForbiddenLanguage(in: app)
            app.terminate()
        }
    }

    func testPaymentStatusUnavailableRoutesToSupportWithoutPaymentRetry() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-payment-unavailable",
            "--fixture-open-result-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Payment test status could not be confirmed.",
            in: app
        )

        let support = app.buttons["personal.payment.status.support"]
        scrollUntilHittable(support, in: app)
        XCTAssertTrue(app.buttons["personal.payment.status.refresh"].exists)
        XCTAssertTrue(support.isHittable)
        XCTAssertFalse(app.buttons["personal.payment.retry"].exists)
        support.tap()

        XCTAssertTrue(
            app.navigationBars["Account & support"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["account-support.contact"]
                .waitForExistence(timeout: 4)
        )
    }

    func testPaymentStatusManualRefreshMovesPendingToCharged() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-payment-status-sequence=charge_pending,charged",
            "--fixture-open-result-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Processing one $20.00 test charge.",
            in: app
        )

        let refresh = app.buttons["personal.payment.status.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 4))
        refresh.tap()

        _ = waitForPaymentStatus(
            "Test charge complete — sandbox transaction recorded.",
            in: app
        )
        XCTAssertFalse(app.buttons["personal.payment.status.refresh"].exists)
        XCTAssertFalse(app.buttons["personal.payment.status.support"].exists)
        XCTAssertFalse(app.buttons["personal.payment.retry"].exists)
    }

    func testPaymentStatusRefreshFailureKeepsStaleReviewAndDisablesReview() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-payment-status=review_open",
            "--fixture-payment-refresh-fails-after-first",
            "--fixture-open-result-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Goal missed — review open. Settlement is paused.",
            in: app
        )

        let refresh = app.buttons["personal.payment.status.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 4))
        refresh.tap()

        XCTAssertTrue(
            containing("Last confirmed", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            containing("We couldn’t refresh it.", in: app).exists
        )
        XCTAssertEqual(
            paymentStatusState(in: app).label,
            "Goal missed — review open. Settlement is paused."
        )
        let staleReviewRequest = app.buttons["personal.review.request"]
        XCTAssertTrue(staleReviewRequest.exists)
        XCTAssertFalse(staleReviewRequest.isEnabled)
        XCTAssertTrue(app.buttons["personal.payment.status.refresh"].exists)
        XCTAssertTrue(app.buttons["personal.payment.status.support"].exists)
    }

    func testPaymentStatusReviewCardSupportsAccessibilityXXXLAndReduceMotion() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-payment-status=review_open",
            "--fixture-open-result-challenge",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"].waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Goal missed — review open. Settlement is paused.",
            in: app
        )

        let firstReason = app.buttons[
            "personal.review.reason.user_disputes_step_data"
        ]
        let secondReason = app.buttons[
            "personal.review.reason.user_disputes_result"
        ]
        for control in [firstReason, secondReason] {
            XCTAssertTrue(control.waitForExistence(timeout: 4))
            XCTAssertFalse(control.label.isEmpty)
        }
        XCTAssertEqual(firstReason.value as? String, "Selected")
        XCTAssertEqual(secondReason.value as? String, "Not selected")

        secondReason.tap()
        XCTAssertTrue(secondReason.isHittable)
        let selectedReason = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: secondReason
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedReason], timeout: 2),
            .completed
        )
        let actions = [
            app.buttons["personal.review.request"],
            app.buttons["personal.payment.status.refresh"],
            app.buttons["personal.payment.status.support"],
        ]
        for action in actions {
            scrollUntilHittable(action, in: app, attempts: 8)
            XCTAssertTrue(action.isHittable)
            XCTAssertFalse(action.label.isEmpty)
        }
        XCTAssertEqual(actions[0].label, "Request a review")
        XCTAssertEqual(actions[1].label, "Refresh")
        XCTAssertEqual(actions[2].label, "Contact Support")
        XCTAssertFalse(app.buttons["personal.payment.retry"].exists)
        attachScreenshot(
            of: app,
            named: "Payment test status - accessibility XXXL"
        )
    }

    func testTodayShowsAutomaticPersonalProgressTimeline() {
        let app = launch("--fixture-activity")

        let todayProgress = personalProgress(
            label: "Today’s progress",
            value: "7,350 steps today. 2,650 to today’s goal.",
            in: app
        )
        XCTAssertTrue(
            todayProgress.waitForExistence(timeout: 5)
        )
        assertDailyProgress(in: app)
        XCTAssertFalse(app.staticTexts["17,832 steps"].exists)
        let completedDay = app.buttons["personal.pace.day.1"]
        let currentDay = app.buttons["personal.pace.day.2"]
        XCTAssertTrue(completedDay.waitForExistence(timeout: 4))
        XCTAssertTrue(completedDay.label.contains("10,482 steps"))
        XCTAssertTrue(currentDay.exists)
        XCTAssertTrue(currentDay.label.contains("7,350 steps"))
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        XCTAssertFalse(app.staticTexts["Friend requests"].exists)
        XCTAssertFalse(app.staticTexts["Challenge invitations"].exists)
        assertNoForbiddenLanguage(in: app)

        assertNoLegacyPersonalHealthSurfaces(in: app)

        app.tabBars.buttons["Challenges"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Challenges"].waitForExistence(timeout: 4)
        )
        assertDailyProgress(in: app)
        assertNoLegacyPersonalHealthSurfaces(in: app)

        let activeCard = app.buttons[
            "personal.challenge.18181818-1818-1818-1818-181818181818"
        ]
        XCTAssertTrue(activeCard.waitForExistence(timeout: 4))
        activeCard.tap()
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 4)
        )
        assertDailyProgress(in: app)
        XCTAssertTrue(app.staticTexts["Your pace"].exists)
        let syncNow = app.buttons["personal.challenge.sync-now"]
        XCTAssertTrue(syncNow.waitForExistence(timeout: 4))
        syncNow.tap()
        XCTAssertTrue(
            app.staticTexts["7,350 steps today"]
                .waitForExistence(timeout: 4)
        )
        let firstPaceDay = app.buttons["personal.pace.day.0"]
        for _ in 0..<8 where !firstPaceDay.exists { app.swipeUp() }
        XCTAssertTrue(firstPaceDay.waitForExistence(timeout: 4))
        let weekTotal = app.descendants(matching: .any)[
            "personal.pace.week-total"
        ]
        XCTAssertTrue(weekTotal.waitForExistence(timeout: 4))
        XCTAssertTrue(
            weekTotal.label.localizedCaseInsensitiveContains("Week total")
        )
        XCTAssertTrue(weekTotal.label.contains("17,832"))
        assertNoLegacyPersonalHealthSurfaces(in: app)
    }

    func testPersonalProgressReplacementFixturesStayConsistentAcrossSurfaces() {
        let cases: [(
            flag: String,
            steps: String,
            remaining: String,
            label: String,
            value: String
        )] = [
            (
                "--fixture-personal-active-cumulative",
                "17,832 steps this week",
                "52,168 to this week’s goal",
                "Week progress",
                "17,832 steps this week. 52,168 to this week’s goal."
            ),
            (
                "--fixture-personal-zero",
                "0 steps today",
                "10,000 to today’s goal",
                "Today’s progress",
                "0 steps today. 10,000 to today’s goal."
            ),
            (
                "--fixture-personal-downward",
                "2,200 steps today",
                "7,800 to today’s goal",
                "Today’s progress",
                "2,200 steps today. 7,800 to today’s goal."
            ),
        ]

        for fixture in cases {
            let app = launch(fixture.flag)
            XCTAssertTrue(
                app.navigationBars["Today"].waitForExistence(timeout: 5),
                "Today did not load for \(fixture.flag)."
            )
            assertPersonalProgress(
                steps: fixture.steps,
                remaining: fixture.remaining,
                accessibilityLabel: fixture.label,
                accessibilityValue: fixture.value,
                in: app
            )

            app.tabBars.buttons["Challenges"].waitAndTap()
            XCTAssertTrue(
                app.navigationBars["Challenges"]
                    .waitForExistence(timeout: 4)
            )
            assertPersonalProgress(
                steps: fixture.steps,
                remaining: fixture.remaining,
                accessibilityLabel: fixture.label,
                accessibilityValue: fixture.value,
                in: app
            )

            let activeCard = app.buttons[
                "personal.challenge.18181818-1818-1818-1818-181818181818"
            ]
            XCTAssertTrue(activeCard.waitForExistence(timeout: 4))
            activeCard.tap()
            XCTAssertTrue(
                app.navigationBars["Your challenge"]
                    .waitForExistence(timeout: 4)
            )
            assertPersonalProgress(
                steps: fixture.steps,
                remaining: fixture.remaining,
                accessibilityLabel: fixture.label,
                accessibilityValue: fixture.value,
                in: app
            )
            app.terminate()
        }
    }

    func testNoDataStaleAndUploadDelayFixturesExplainProgressHonestly() {
        let cases: [(
            flag: String,
            statusFragment: String,
            retainedSteps: String?
        )] = [
            (
                "--fixture-personal-no-data",
                "No step data available yet.",
                nil
            ),
            (
                "--fixture-personal-stale",
                "Apple Health is temporarily unavailable.",
                "7,350 steps today"
            ),
            (
                "--fixture-personal-upload-delay",
                "sent when connectivity returns.",
                "7,350 steps today"
            ),
        ]

        for fixture in cases {
            let app = launch(fixture.flag)
            XCTAssertTrue(
                app.navigationBars["Today"].waitForExistence(timeout: 5),
                "Today did not load for \(fixture.flag)."
            )
            let todayStatus = healthStatus(
                containing: fixture.statusFragment,
                in: app
            )
            XCTAssertTrue(
                todayStatus.waitForExistence(timeout: 5),
                "Health status did not settle for \(fixture.flag)."
            )
            if let retainedSteps = fixture.retainedSteps {
                XCTAssertTrue(exactStaticText(retainedSteps, in: app).exists)
                XCTAssertTrue(
                    exactStaticText("2,650 to today’s goal", in: app).exists
                )
            } else {
                XCTAssertFalse(
                    app.progressIndicators["personal.progress"].exists
                )
            }

            let openChallenge = app.buttons["personal.today.open"]
            for _ in 0..<8 where !openChallenge.isHittable { app.swipeUp() }
            XCTAssertTrue(openChallenge.isHittable)
            openChallenge.tap()
            XCTAssertTrue(
                app.navigationBars["Your challenge"]
                    .waitForExistence(timeout: 4)
            )
            let detailStatus = healthStatus(
                containing: fixture.statusFragment,
                in: app
            )
            XCTAssertTrue(
                detailStatus.waitForExistence(timeout: 4)
            )

            if fixture.flag == "--fixture-personal-no-data" {
                let retry = app.buttons["personal.challenge.sync-now"]
                XCTAssertTrue(retry.waitForExistence(timeout: 4))
                XCTAssertEqual(retry.label, "Try Again")
                XCTAssertTrue(retry.isEnabled)
                XCTAssertTrue(
                    app.descendants(matching: .any)[
                        "personal.challenge.health-help"
                    ].exists
                )
                XCTAssertEqual(
                    app.descendants(matching: .any)[
                        "personal.challenge.health-help"
                    ].label,
                    "Apple Health help"
                )
                let accountSupport = app.buttons[
                    "personal.challenge.account-support"
                ]
                XCTAssertTrue(accountSupport.exists)
                XCTAssertEqual(accountSupport.label, "Account & support")
            }
            app.terminate()
        }
    }

    func testScheduledAndCancelledFixturesUseLifecycleSpecificCopy() {
        let scheduled = launch(
            "--fixture-personal-scheduled",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            scheduled.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            scheduled.staticTexts["Scheduled"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            healthStatus(in: scheduled).waitForExistence(timeout: 4)
        )
        XCTAssertEqual(
            healthStatus(in: scheduled).label,
            "Apple Health updates begin when this challenge starts."
        )
        XCTAssertTrue(
            scheduled.buttons["personal.cancel"].waitForExistence(timeout: 4)
        )
        scheduled.terminate()

        let scheduledSandbox = launch(
            "--fixture-stripe-sandbox",
            "--fixture-personal-scheduled",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            scheduledSandbox.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            scheduledSandbox.buttons["personal.cancel"]
                .waitForExistence(timeout: 4)
        )
        _ = waitForPaymentStatus("Test method saved.", in: scheduledSandbox)
        scheduledSandbox.terminate()

        let cancelled = launch(
            "--fixture-personal-cancelled",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            cancelled.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            cancelled.staticTexts["Cancelled"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            healthStatus(in: cancelled).waitForExistence(timeout: 4)
        )
        XCTAssertEqual(
            healthStatus(in: cancelled).label,
            "Apple Health updates stopped when this challenge was cancelled."
        )
        XCTAssertFalse(cancelled.buttons["personal.cancel"].exists)
        XCTAssertFalse(
            cancelled.descendants(matching: .any)[
                "personal.payment.status.card"
            ].exists
        )
        cancelled.terminate()

        let cancelledSandbox = launch(
            "--fixture-stripe-sandbox",
            "--fixture-personal-cancelled",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            cancelledSandbox.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Challenge closed — $0 test charge.",
            in: cancelledSandbox
        )
        XCTAssertFalse(cancelledSandbox.buttons["personal.cancel"].exists)
    }

    func testPendingCancellationFixturesStayActionableAndRouteToSupport() {
        let cases: [(flag: String, message: String)] = [
            (
                "--fixture-personal-pending-cancellation",
                "Your cancellation is saved on this phone. We’ll keep using the same request until it is confirmed."
            ),
            (
                "--fixture-personal-unreadable-cancellation",
                "GameTime can’t safely read the cancellation saved on this phone yet. Starting another challenge stays paused until we know what happened."
            ),
        ]

        for fixture in cases {
            let app = launch(fixture.flag)
            XCTAssertTrue(
                app.navigationBars["Today"].waitForExistence(timeout: 5)
            )
            dismissGameTimeAlertIfPresent(in: app)

            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "personal.cancellation.pending"
                ].waitForExistence(timeout: 5),
                "Recovery card was missing for \(fixture.flag)."
            )
            XCTAssertTrue(
                containing("Cancellation saved — still trying.", in: app)
                    .exists
            )
            XCTAssertTrue(exactStaticText(fixture.message, in: app).exists)

            let retry = app.buttons["personal.cancellation.retry"]
            for _ in 0..<8 where !retry.isHittable { app.swipeUp() }
            XCTAssertTrue(retry.waitForExistence(timeout: 4))
            XCTAssertTrue(retry.isHittable)
            XCTAssertEqual(retry.label, "Retry Cancellation")
            XCTAssertTrue(retry.isEnabled)
            let refresh = app.buttons["personal.cancellation.refresh"]
            for _ in 0..<8 where !refresh.isHittable { app.swipeUp() }
            XCTAssertTrue(refresh.waitForExistence(timeout: 4))
            XCTAssertTrue(refresh.isHittable)
            XCTAssertEqual(refresh.label, "Refresh")
            XCTAssertTrue(refresh.isEnabled)

            let support = app.buttons["personal.cancellation.support"]
            for _ in 0..<8 where !support.isHittable { app.swipeUp() }
            XCTAssertTrue(support.isHittable)
            XCTAssertEqual(support.label, "Contact Support")
            support.tap()
            XCTAssertTrue(
                app.navigationBars["Account & support"]
                    .waitForExistence(timeout: 4)
            )
            app.terminate()
        }
    }

    func testAccountDeletionFailureRemainsVisibleAndRecoverable() {
        let app = launch("--fixture-account-deletion-failure")
        openAccountSupport(in: app)

        let delete = app.buttons["account-support.delete"]
        for _ in 0..<12 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        delete.tap()

        let warning = app.alerts["Delete your account?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 4))
        XCTAssertTrue(
            warning.staticTexts.matching(
                NSPredicate(format: "label == %@", deletionWarning)
            ).firstMatch.exists
        )
        warning.buttons["Continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Delete account"].waitForExistence(timeout: 4)
        )
        app.buttons["account-deletion.fixture-reauthenticate"].waitAndTap()
        XCTAssertTrue(
            exactStaticText("Deletion didn’t finish", in: app)
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            exactStaticText(
                "Account deletion is temporarily unavailable. Try again in a moment or contact support.",
                in: app
            ).exists
        )
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertFalse(app.links["Contact beta support"].exists)
    }

    func testPersonalDetailContainsLockedTermsAndNoCompetitiveLanguage() {
        let app = launch("--fixture-open-active-challenge")
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "personal.payment.status.card"
            ].exists
        )
        XCTAssertTrue(app.staticTexts["Your pace"].exists)
        XCTAssertFalse(app.staticTexts["Steps received"].exists)
        assertEnvironmentDisclosure(in: app, mode: .testOnly)

        // The terms still exist; they live behind "Challenge details" now.
        let details = app.buttons["personal.details"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        XCTAssertEqual(details.value as? String, "Hidden")
        details.tap()
        XCTAssertEqual(details.value as? String, "Showing")
        XCTAssertTrue(
            containing("Updates through", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(containing("How it counts", in: app).exists)

        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.isHittable { app.swipeDown() }
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 3),
            "Internal test-only active challenges should expose cleanup cancellation."
        )
        XCTAssertTrue(cancel.isHittable)

        assertNoLegacyPersonalHealthSurfaces(in: app)
        XCTAssertFalse(app.staticTexts["Standings"].exists)
        XCTAssertFalse(app.staticTexts["Winner"].exists)
        XCTAssertFalse(app.staticTexts["Charity"].exists)
        assertNoForbiddenLanguage(in: app)

        cancel.tap()
        XCTAssertTrue(
            exactStaticText("Cancel this challenge?", in: app)
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            exactStaticText(
                "This ends the test challenge immediately. It will stay in your history, and no money will be charged.",
                in: app
            ).exists
        )
        XCTAssertTrue(app.buttons["Keep it"].exists)
        app.buttons["Yes, cancel it"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Challenges"].waitForExistence(timeout: 5)
        )
    }

    func testActiveStripeSandboxCancellationRetainsCancelledHistory() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        _ = waitForPaymentStatus("Test method saved.", in: app)

        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.isHittable { app.swipeDown() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 4))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()

        XCTAssertTrue(
            exactStaticText("Cancel this challenge?", in: app)
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            exactStaticText(
                "This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged.",
                in: app
            ).exists
        )
        app.buttons["Yes, cancel it"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Challenges"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Cancelled"].waitForExistence(timeout: 4)
        )
        XCTAssertFalse(app.buttons["personal.cancel"].exists)
    }

    func testAwaitingAndCompletedStripeSandboxChallengesCannotCancel() {
        let awaiting = launch(
            "--fixture-stripe-sandbox",
            "--fixture-personal-awaiting-evidence",
            "--fixture-open-active-challenge"
        )
        XCTAssertTrue(
            awaiting.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            awaiting.staticTexts["Waiting on steps"]
                .waitForExistence(timeout: 4)
        )
        _ = waitForPaymentStatus("Test method saved.", in: awaiting)
        XCTAssertFalse(awaiting.buttons["personal.cancel"].exists)
        awaiting.terminate()

        let completed = launch(
            "--fixture-stripe-sandbox",
            "--fixture-open-result-challenge"
        )
        XCTAssertTrue(
            completed.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        _ = waitForPaymentStatus(
            "Goal met — $0 test charge.",
            in: completed
        )
        XCTAssertFalse(completed.buttons["personal.cancel"].exists)
    }

    func testCumulativeCreationOmitsFixedMetricAndStartSteps() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity"
        )
        XCTAssertTrue(
            app.buttons["personal.create"].waitForExistence(timeout: 5)
        )
        app.buttons["personal.create"].tap()

        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 5"].exists
        )
        XCTAssertFalse(app.buttons["Back"].exists)
        assertHiddenBetaCreationSteps(in: app)
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertNoForbiddenLanguage(in: app)
        attachScreenshot(
            of: app,
            named: "Beta creation - cadence first"
        )
        XCTAssertTrue(app.buttons["personal.cadence.daily"].exists)
        XCTAssertTrue(app.buttons["personal.cadence.cumulative"].exists)
        app.buttons["personal.cadence.cumulative"].tap()
        XCTAssertEqual(
            app.buttons["personal.cadence.cumulative"].value as? String,
            "Selected"
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your goal"].waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.textFields["personal.target"].value as? String,
            "70,000"
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your amount"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.buttons["personal.commitment.1000"].value as? String,
            "Selected"
        )
        for amount in [1_000, 2_000, 3_000, 4_000, 5_000] {
            let preset = app.buttons["personal.commitment.\(amount)"]
            XCTAssertTrue(preset.exists)
            preset.tap()
            XCTAssertEqual(preset.value as? String, "Selected")
        }
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        assertHiddenBetaCreationSteps(in: app)
        assertNoForbiddenLanguage(in: app)
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        XCTAssertFalse(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        attachScreenshot(
            of: app,
            named: "Apple Health - connection required"
        )
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(connectHealth.exists)
        XCTAssertTrue(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertReceiptFact(
            "how-it-counts",
            contains: "Week total",
            in: app
        )
        assertReceiptFact(
            "amount",
            contains: "$50",
            in: app
        )
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertReceipt(in: app, mode: .testOnly)
        assertNoForbiddenLanguage(in: app)
        let submit = app.buttons["personal.submit"]
        for _ in 0..<8 where !submit.isHittable { app.swipeUp() }
        submit.waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertNoForbiddenLanguage(in: app)
    }

    func testMainModeCanStartNowAndExposeSyncNow() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity"
        )
        app.buttons["personal.create"].waitAndTap()
        advancePersonalCreation(
            in: app,
            through: ["Your goal", "Your amount", "Apple Health"]
        )

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertReceipt(in: app, mode: .testOnly)
        for (identifier, value) in [
            ("length", "Seven full days"),
            ("final-check", "24 hours after your last day"),
            ("how-it-counts", "Every day"),
            ("amount", "$10"),
        ] {
            assertReceiptFact(identifier, contains: value, in: app)
        }
        assertNoForbiddenLanguage(in: app)
        let startNow = app.switches["personal.start.now"]
        XCTAssertTrue(startNow.waitForExistence(timeout: 3))
        for _ in 0..<12 where !startNow.isHittable { app.swipeDown() }
        XCTAssertTrue(startNow.isHittable)
        startNow.tap()
        assertReceiptFact(
            "starts",
            contains: "Now — today counts from midnight",
            in: app
        )
        let submit = app.buttons["personal.submit"]
        for _ in 0..<8 where !submit.isHittable { app.swipeUp() }
        submit.waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["In progress"].exists)
        let syncNow = app.buttons["personal.challenge.sync-now"]
        for _ in 0..<8 where !syncNow.exists { app.swipeUp() }
        XCTAssertTrue(syncNow.waitForExistence(timeout: 3))
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.exists { app.swipeUp() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        assertNoForbiddenLanguage(in: app)

        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "Last checked"
                )
            ).firstMatch.exists,
            "The local Apple Health creation check must not run or record a trusted diagnostic."
        )
    }

    func testCompletedAppleHealthPermissionCarriesIntoCreation() {
        let app = launch(
            "--fixture-empty"
        )
        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Apple Health"].exists)
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(connectHealth.exists)

        app.tabBars.buttons["Today"].waitAndTap()
        app.buttons["personal.create"].waitAndTap()
        advancePersonalCreation(
            in: app,
            through: ["Your goal", "Your amount", "Apple Health"]
        )

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Health connected"].exists)
        XCTAssertFalse(app.buttons["personal.health.verify"].exists)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        attachScreenshot(
            of: app,
            named: "Apple Health - permission completed"
        )

        let continueButton = app.buttons["personal.continue"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
    }

    func testLegacyDiagnosticAndHoldStateStayOutOfPersonalV2UI() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-hold"
        )
        app.tabBars.buttons["You"].waitAndTap()

        XCTAssertTrue(
            app.staticTexts["Apple Health"].waitForExistence(timeout: 5)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()

        app.tabBars.buttons["Today"].waitAndTap()
        let create = app.buttons["personal.create"]
        for _ in 0..<5 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        XCTAssertTrue(create.isEnabled)
        create.tap()
        advancePersonalCreation(
            in: app,
            through: ["Your goal", "Your amount", "Apple Health"]
        )
        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Health connected"].exists)
        app.buttons["personal.continue"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["personal.submit"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
    }

    func testSavedSandboxPaymentRequestCanResumeAfterRelaunch() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-pending",
            "--fixture-stripe-sandbox"
        )
        app.tabBars.buttons["Challenges"].waitAndTap()

        XCTAssertTrue(
            app.staticTexts["Ready to finish"].waitForExistence(timeout: 5)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertNoForbiddenLanguage(in: app)
        let resume = app.buttons["personal.pending.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 4))
        XCTAssertEqual(resume.label, "Continue setup")
        resume.tap()

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Test payment"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        XCTAssertFalse(app.switches["personal.start.now"].exists)
        let consent =
            "By starting, you agree that GameTime may create one $30.00 test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
        XCTAssertTrue(
            exactStaticText(consent, in: app).waitForExistence(timeout: 3)
        )
        let setup = app.buttons["personal.payment.setup"]
        XCTAssertTrue(setup.exists)
        XCTAssertFalse(setup.isEnabled)
        app.switches["personal.payment.consent"].waitAndTap()
        XCTAssertTrue(setup.isEnabled)
        setup.tap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertReceiptFact(
            "how-it-counts",
            contains: "Week total",
            in: app
        )
        assertReceiptFact("amount", contains: "$30", in: app)
        assertReceipt(
            in: app,
            mode: .stripeSandbox,
            expectsSavedDraft: true
        )
        assertNoForbiddenLanguage(in: app)
        let submit = app.buttons["personal.submit"]
        for _ in 0..<8 where !submit.isHittable { app.swipeUp() }
        submit.waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        assertEnvironmentDisclosure(in: app, mode: .stripeSandbox)
        assertNoForbiddenLanguage(in: app)
    }

    func testLoadingEmptyAndOfflineStates() {
        let loading = launch("--fixture-loading")
        XCTAssertTrue(loading.staticTexts["Loading…"].waitForExistence(timeout: 2))
        XCTAssertTrue(loading.otherElements["launch.loading"].exists)
        XCTAssertTrue(
            loading.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Loading GameTime")
            ).firstMatch.exists
        )
        assertNoForbiddenLanguage(in: loading)
        loading.terminate()

        let empty = launch("--fixture-empty")
        XCTAssertTrue(
            empty.staticTexts["Make this week count"]
                .waitForExistence(timeout: 5)
        )
        assertNoForbiddenLanguage(in: empty)
        empty.terminate()

        let offline = launch("--fixture-offline")
        XCTAssertTrue(
            offline.otherElements["state.offline"].waitForExistence(timeout: 5)
                || offline.staticTexts["Couldn’t refresh"].exists
        )
        XCTAssertFalse(offline.staticTexts["Make this week count"].exists)
        XCTAssertFalse(offline.buttons["personal.create"].exists)

        offline.tabBars.buttons["Challenges"].waitAndTap()
        XCTAssertTrue(
            offline.staticTexts["Couldn’t refresh"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(offline.buttons["Try again"].exists)
        XCTAssertFalse(offline.staticTexts["No challenges yet"].exists)
        XCTAssertFalse(offline.buttons["personal.create"].exists)
        assertNoForbiddenLanguage(in: offline)
    }

    func testSettingsKeepPrivacyHelpDocumentsAndAccountActionsReachable() {
        let app = launch("--fixture-empty")

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 4))
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertSettingsReachability(in: app)
    }

    func testPersonalDynamicTypeAccessibilityLabelsAndReduceMotion() {
        let app = launch(
            "--fixture-empty",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        )

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Refresh your progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Challenges"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        assertEnvironmentDisclosure(in: app, mode: .testOnly)

        let create = app.buttons["personal.create"]
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 5"].exists
        )
        XCTAssertFalse(app.buttons["Back"].exists)
        assertHiddenBetaCreationSteps(in: app)
        let continueButton = app.buttons["personal.continue"]
        XCTAssertEqual(continueButton.label, "Continue")
        XCTAssertTrue(continueButton.exists)
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertNoForbiddenLanguage(in: app)
        attachScreenshot(
            of: app,
            named: "Beta creation - cadence accessibility XXXL"
        )

        tapCreationContinue(in: app)
        XCTAssertTrue(
            app.navigationBars["Your goal"].waitForExistence(timeout: 4)
        )
        tapCreationContinue(in: app)
        XCTAssertTrue(
            app.navigationBars["Your amount"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "personal.commitment.protection"
            ].exists
        )
        tapCreationContinue(in: app)
        XCTAssertTrue(
            app.navigationBars["Apple Health"].waitForExistence(timeout: 4)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        for _ in 0..<12 where !connectHealth.isHittable { app.swipeUp() }
        XCTAssertTrue(connectHealth.isHittable)
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"].waitForExistence(timeout: 4)
        )
        tapCreationContinue(in: app)
        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertReceipt(in: app, mode: .testOnly)
        for identifier in [
            "personal.receipt.fact.how-it-counts",
            "personal.receipt.fact.day-one",
            "personal.receipt.fact.payment-mode",
        ] {
            let fact = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                fact.waitForExistence(timeout: 3),
                "Adaptive receipt fact is unreachable: \(identifier)"
            )
        }
        attachScreenshot(
            of: app,
            named: "Confirmation receipt - accessibility XXXL"
        )
        app.buttons["Close"].waitAndTap()
        XCTAssertTrue(
            exactStaticText("Discard this setup?", in: app)
                .waitForExistence(timeout: 4)
        )
        app.buttons["Discard changes"].waitAndTap()

        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 4))
        assertEnvironmentDisclosure(in: app, mode: .testOnly)
        assertSettingsReachability(in: app)
    }

    private func tapCreationContinue(in app: XCUIApplication) {
        let button = app.buttons["personal.continue"]
        for _ in 0..<12 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func advancePersonalCreation(
        in app: XCUIApplication,
        through navigationTitles: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for title in navigationTitles {
            app.buttons["personal.continue"].waitAndTap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 4),
                "Creation did not advance to \(title).",
                file: file,
                line: line
            )
        }
    }

    private func assertHiddenBetaCreationSteps(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.navigationBars["What you’ll track"].exists,
            "The one-option metric page is still reachable.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["personal.metric.steps"].exists,
            "The fixed Steps choice is still exposed.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.navigationBars["When you start"].exists,
            "The custom-start page is still reachable.",
            file: file,
            line: line
        )
        for identifier in [
            "personal.start.day",
            "personal.start.hour",
            "personal.start.tomorrow",
            "personal.start.next-hour",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[identifier].exists,
                "A custom-start control is still exposed: \(identifier)",
                file: file,
                line: line
            )
        }
    }

    private func assertNoLegacyPersonalHealthSurfaces(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for identifier in [
            "personal.sync",
            "personal.health.probe-result",
            "personal.diagnostic.run",
            "personal.eligibility-hold",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[identifier].exists,
                "Personal v2 exposed a retired Health surface: \(identifier)",
                file: file,
                line: line
            )
        }
        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let forbidden =
            #"health diagnostic|trusted diagnostic|\battested\b|app attest|first[- ]party|\bsample(?: count|s?)\b|completed[- ]hour|provisioned device"#
        XCTAssertNil(
            labels.range(
                of: forbidden,
                options: [.regularExpression, .caseInsensitive]
            ),
            "Challenge creation contains technical diagnostic copy:\n\(labels)",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(
        of app: XCUIApplication,
        named name: String
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertEnvironmentDisclosure(
        in app: XCUIApplication,
        mode: EnvironmentMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let disclosures = app.descendants(matching: .any).matching(
            identifier: "personal.environment-disclosure"
        )
        XCTAssertTrue(
            disclosures.firstMatch.waitForExistence(timeout: 4),
            "The environment disclosure is missing.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            disclosures.count,
            1,
            "Expected exactly one visible environment disclosure.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            disclosures.firstMatch.label,
            mode.copy,
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "personal.test-only-disclosure"
            ].exists,
            "The retired disclosure card is still reachable.",
            file: file,
            line: line
        )
    }

    private func assertReceipt(
        in app: XCUIApplication,
        mode: EnvironmentMode,
        expectsSavedDraft: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let receipt = app.descendants(matching: .any)["personal.receipt"]
        XCTAssertTrue(
            receipt.waitForExistence(timeout: 4),
            file: file,
            line: line
        )

        for (identifier, heading) in [
            ("personal.receipt.group.challenge", "Your challenge"),
            ("personal.receipt.group.start", "When it starts"),
            ("personal.receipt.group.payment", "Payment protection"),
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "Receipt group is missing: \(identifier)",
                file: file,
                line: line
            )
            XCTAssertTrue(
                exactStaticText(heading, in: app).exists,
                "Receipt heading is missing: \(heading)",
                file: file,
                line: line
            )
        }

        let commonFactIdentifiers = [
            "how-it-counts",
            "goal",
            "amount",
            "length",
            "starts",
            "day-one",
            "time-zone",
            "final-check",
        ]
        let paymentFactIdentifiers: [String]
        switch mode {
        case .testOnly, .demo:
            paymentFactIdentifiers = [
                "payment-mode",
                "zero-outcomes",
                "missing-data",
            ]
        case .stripeSandbox:
            paymentFactIdentifiers = [
                "payment-mode",
                "zero-outcomes",
                "confirmed-miss",
                "review",
            ]
        }
        let expectedFactIdentifiers =
            commonFactIdentifiers + paymentFactIdentifiers
        for identifier in expectedFactIdentifiers {
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "personal.receipt.fact.\(identifier)"
                ].exists,
                "Receipt fact is missing: \(identifier)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "personal.receipt.fact."
                )
            ).count,
            expectedFactIdentifiers.count,
            "Each receipt group must stay within its four-fact limit.",
            file: file,
            line: line
        )

        XCTAssertFalse(
            app.descendants(matching: .any)["personal.request-id"].exists,
            "The receipt exposes the internal draft request identifier.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "personal.submit").count,
            1,
            "The receipt must expose one primary submit action.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.buttons["personal.continue"].exists,
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.buttons["personal.payment.setup"].exists,
            file: file,
            line: line
        )

        let details = app.buttons["personal.receipt.more-details"]
        for _ in 0..<12 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.isHittable, file: file, line: line)
        XCTAssertEqual(details.label, "More details", file: file, line: line)
        XCTAssertEqual(
            details.value as? String,
            "Hidden",
            file: file,
            line: line
        )
        details.tap()
        XCTAssertEqual(
            details.value as? String,
            "Showing",
            file: file,
            line: line
        )

        for identifier in [
            "personal.receipt.detail.cadence",
            "personal.receipt.detail.day-one",
            "personal.receipt.detail.cancellation",
            "personal.receipt.detail.saved-draft",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier]
                    .waitForExistence(timeout: 3),
                "Expanded receipt detail is missing: \(identifier)",
                file: file,
                line: line
            )
        }

        let savedDraft = app.descendants(matching: .any)[
            "personal.receipt.detail.saved-draft"
        ]
        XCTAssertTrue(
            savedDraft.label.contains(
                expectsSavedDraft
                    ? "GameTime saved exactly what you picked"
                    : "If starting is interrupted"
            ),
            file: file,
            line: line
        )

        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        XCTAssertNil(
            labels.range(
                of: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
                options: .regularExpression
            ),
            "The receipt exposes a raw UUID:\n\(labels)",
            file: file,
            line: line
        )
        assertNoForbiddenLanguage(in: app, file: file, line: line)

        details.tap()
        XCTAssertEqual(
            details.value as? String,
            "Hidden",
            file: file,
            line: line
        )
    }

    private func assertReceiptFact(
        _ identifier: String,
        contains expectedValue: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fact = app.descendants(matching: .any)[
            "personal.receipt.fact.\(identifier)"
        ]
        XCTAssertTrue(
            fact.waitForExistence(timeout: 4),
            "Receipt fact is missing: \(identifier)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            fact.label.contains(expectedValue),
            "Receipt fact \(identifier) does not contain \(expectedValue): \(fact.label)",
            file: file,
            line: line
        )
    }

    private func assertResultTitle(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = exactStaticText(title, in: app)
        for _ in 0..<12 where !text.isHittable { app.swipeUp() }
        XCTAssertTrue(
            text.waitForExistence(timeout: 4),
            "Result title is missing: \(title)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["personal.result"].exists,
            file: file,
            line: line
        )
    }

    @discardableResult
    private func waitForPaymentStatus(
        _ expectedLabel: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let state = revealPaymentStatus(in: app, file: file, line: line)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                expectedLabel
            ),
            object: state
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Expected payment state ‘\(expectedLabel)’, got ‘\(state.label)’.",
            file: file,
            line: line
        )
        return state
    }

    private func paymentStatusState(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["personal.payment.status.state"]
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 4
    ) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<attempts where !element.isHittable {
            scrollView.swipeUp()
        }
    }

    @discardableResult
    private func revealPaymentStatus(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let card = app.descendants(matching: .any)[
            "personal.payment.status.card"
        ]
        let state = paymentStatusState(in: app)
        for _ in 0..<14 where !state.exists {
            app.swipeUp()
            _ = state.waitForExistence(timeout: 0.2)
        }
        XCTAssertTrue(
            card.waitForExistence(timeout: 4),
            "The Payment test status card is missing.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            state.waitForExistence(timeout: 4),
            "The authoritative payment state is missing.",
            file: file,
            line: line
        )
        return state
    }

    private func assertSettingsReachability(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.buttons["account.sign-out"].exists,
            "Sign out must live only in Account & support.",
            file: file,
            line: line
        )

        let privacy = app.buttons["privacy.open"]
        for _ in 0..<12 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable, file: file, line: line)
        privacy.tap()
        XCTAssertTrue(
            app.navigationBars["Privacy"].waitForExistence(timeout: 4),
            file: file,
            line: line
        )
        assertEnvironmentDisclosure(
            in: app,
            mode: .testOnly,
            file: file,
            line: line
        )
        assertNoForbiddenLanguage(in: app, file: file, line: line)

        let back = app.navigationBars["Privacy"].buttons["You"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), file: file, line: line)
        back.tap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4),
            file: file,
            line: line
        )

        let accountSupport = app.buttons["account-support.open"]
        for _ in 0..<12 where !accountSupport.isHittable { app.swipeUp() }
        XCTAssertTrue(accountSupport.isHittable, file: file, line: line)
        accountSupport.tap()
        XCTAssertTrue(
            app.navigationBars["Account & support"]
                .waitForExistence(timeout: 4),
            file: file,
            line: line
        )
        assertEnvironmentDisclosure(
            in: app,
            mode: .testOnly,
            file: file,
            line: line
        )
        XCTAssertTrue(
            exactStaticText("Help & documents", in: app).exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            containing("Apple Health help", in: app).exists,
            file: file,
            line: line
        )

        for identifier in [
            "account-support.contact",
            "account-support.privacy-policy",
            "account-support.beta-terms",
        ] {
            let item = app.descendants(matching: .any)[identifier]
            for _ in 0..<12 where !item.isHittable { app.swipeUp() }
            XCTAssertTrue(
                item.isHittable,
                "Help or document row is unreachable: \(identifier)",
                file: file,
                line: line
            )
        }

        let signOut = app.buttons["account-support.sign-out"]
        for _ in 0..<12 where !signOut.isHittable { app.swipeUp() }
        XCTAssertTrue(signOut.isHittable, file: file, line: line)

        let delete = app.buttons["account-support.delete"]
        for _ in 0..<12 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable, file: file, line: line)
        delete.tap()

        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 4),
            file: file,
            line: line
        )
        XCTAssertTrue(
            alert.staticTexts.matching(
                NSPredicate(format: "label == %@", deletionWarning)
            ).firstMatch.exists,
            file: file,
            line: line
        )
        XCTAssertTrue(alert.buttons["Continue"].exists, file: file, line: line)
        alert.buttons["Cancel"].waitAndTap()
        assertNoForbiddenLanguage(in: app, file: file, line: line)
    }

    private func assertDailyProgress(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["7,350 steps today"].exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts["2,650 to today’s goal"].exists,
            file: file,
            line: line
        )
        let progress = personalProgress(
            label: "Today’s progress",
            value: "7,350 steps today. 2,650 to today’s goal.",
            in: app
        )
        XCTAssertTrue(
            progress.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.label,
            "Today’s progress",
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.value as? String,
            "7,350 steps today. 2,650 to today’s goal.",
            file: file,
            line: line
        )
    }

    private func assertPersonalProgress(
        steps: String,
        remaining: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            exactStaticText(steps, in: app).waitForExistence(timeout: 5),
            "Progress steps are missing: \(steps)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            exactStaticText(remaining, in: app).exists,
            "Progress remainder is missing: \(remaining)",
            file: file,
            line: line
        )
        let progress = personalProgress(
            label: accessibilityLabel,
            value: accessibilityValue,
            in: app
        )
        XCTAssertTrue(
            progress.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.label,
            accessibilityLabel,
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.value as? String,
            accessibilityValue,
            file: file,
            line: line
        )
    }

    private func assertCumulativeProgress(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["56,000 steps this week"].exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts["14,000 to this week’s goal"].exists,
            file: file,
            line: line
        )
        let progress = personalProgress(
            label: "Week progress",
            value: "56,000 steps this week. 14,000 to this week’s goal.",
            in: app
        )
        XCTAssertTrue(
            progress.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertEqual(progress.label, "Week progress", file: file, line: line)
        XCTAssertEqual(
            progress.value as? String,
            "56,000 steps this week. 14,000 to this week’s goal.",
            file: file,
            line: line
        )
    }

    private func dismissGameTimeAlertIfPresent(in app: XCUIApplication) {
        let alert = app.alerts["GameTime"]
        if alert.waitForExistence(timeout: 1) {
            alert.buttons["OK"].waitAndTap()
        }
    }

    private func openAccountSupport(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4),
            file: file,
            line: line
        )
        let accountSupport = app.buttons["account-support.open"]
        for _ in 0..<12 where !accountSupport.isHittable { app.swipeUp() }
        XCTAssertTrue(accountSupport.isHittable, file: file, line: line)
        accountSupport.tap()
        XCTAssertTrue(
            app.navigationBars["Account & support"]
                .waitForExistence(timeout: 4),
            file: file,
            line: line
        )
    }

    private func healthStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "personal.health.status")
            .firstMatch
    }

    private func personalProgress(
        label: String,
        value: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.progressIndicators
            .matching(identifier: "personal.progress")
            .matching(
                NSPredicate(
                    format: "label == %@ AND value == %@",
                    label,
                    value
                )
            )
            .firstMatch
    }

    private func healthStatus(
        containing fragment: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "personal.health.status",
                fragment
            )
        ).firstMatch
    }

    private func exactStaticText(
        _ label: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    /// Rows that combine a label and a value into one accessibility element
    /// do not surface the label on its own, so match on a fragment.
    private func containing(
        _ fragment: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", fragment)
        ).firstMatch
    }

    private func assertNoForbiddenLanguage(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let forbidden =
            #"(?i)\b(?:friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b"#
        XCTAssertNil(
            labels.range(of: forbidden, options: .regularExpression),
            "Reachable Personal V1 UI contains forbidden copy:\n\(labels)",
            file: file,
            line: line
        )
        XCTAssertNil(
            labels.range(
                of: #"B//B|Better Bet"#,
                options: [.regularExpression, .caseInsensitive]
            ),
            "Reachable UI contains a former public identity:\n\(labels)",
            file: file,
            line: line
        )
    }

    private func launch(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--fixture-mode"] + extraArguments
        if !extraArguments.contains("-UIPreferredContentSizeCategoryName") {
            arguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryL",
            ]
        }
        if !extraArguments.contains("-UIAccessibilityReduceMotionEnabled") {
            arguments += ["-UIAccessibilityReduceMotionEnabled", "NO"]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

private extension XCUIElement {
    func waitAndTap(timeout: TimeInterval = 4) {
        XCTAssertTrue(waitForExistence(timeout: timeout))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "hittable == true AND enabled == true"
            ),
            object: self
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: timeout),
            .completed
        )
        tap()
    }
}
