#if DEBUG
import XCTest

/// Exercises the ordinary native store and navigation with a local, mutable
/// fixture client. These tests never contact a hosted service or move money.
@MainActor
final class LiveDesignUITests: XCTestCase {
    func testFourLockedScreensUseTheNewNativeShell() {
        continueAfterFailure = false
        for route in ["home", "goal", "challenges", "you"] {
            let app = launch(route)
            for tab in ["home", "challenges", "you"] {
                XCTAssertTrue(app.buttons["beta.tab." + tab].exists)
            }
            switch route {
            case "home":
                XCTAssertTrue(element(app, "live.home.metric").waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["live.home.goal"].exists)
            case "goal":
                XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["What counts"].exists)
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable).count, 1)
                XCTAssertEqual(app.navigationBars.buttons.allElementsBoundByIndex.filter(\.isHittable).count, 0)
            case "challenges":
                XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["live.filter.invited"].exists)
            default:
                XCTAssertTrue(element(app, "profile.count.met").waitForExistence(timeout: 10))
                XCTAssertTrue(element(app, "profile.count.finished").exists)
                XCTAssertTrue(app.buttons["profile.settings"].exists)
            }
            XCTAssertFalse(app.tabBars.buttons["Today"].exists)
            capture(app, name: "live-" + route)
            app.terminate()
        }
    }

    func testFullRulesAreDisclosedAsIndependentModules() {
        continueAfterFailure = false
        let app = launch("goal")
        defer { app.terminate() }
        XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Ends, not included"].exists)
        let rules = app.buttons["live.goal.rules"]
        bring(app, rules); rules.tap()
        let dates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Dates and times")).firstMatch
        XCTAssertTrue(dates.waitForExistence(timeout: 5))
        bring(app, dates)
        XCTAssertEqual(dates.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Ends, not included"].exists)
        dates.tap()
        XCTAssertEqual(dates.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Ends, not included"].waitForExistence(timeout: 5))
        capture(app, name: "live-full-rules-dates")
        let close = app.buttons["Close"]
        bring(app, close, upward: false); close.tap()
        XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 5))
    }

    func testChallengeCreationEntryKeepsTheApprovedNativeFlow() {
        continueAfterFailure = false
        let app = launch("challenges")
        defer { app.terminate() }
        let create = app.buttons["beta.create.open"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let heading = app.staticTexts["beta.create.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        // Mason, September 26: creation asks who it's for before anything else.
        XCTAssertEqual(heading.label, "Who’s it for?")
        let progress = element(app, "beta.create.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "Step 1 of 4, Who")
        for type in ["personal", "friend", "leaderboard"] {
            XCTAssertTrue(app.buttons["beta.create.type." + type].exists)
        }
        XCTAssertFalse(app.buttons["beta.create.back"].exists, "The first step closes instead of going back")
        capture(app, name: "create-type")
        let next = app.buttons["beta.create.continue"]
        app.buttons["beta.create.type.friend"].tap()
        next.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "What’s your goal?"), object: heading)], timeout: 5), .completed)
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 2 of 4, Goal")
        XCTAssertFalse(app.buttons["beta.create.type.leaderboard"].exists)
        XCTAssertFalse(app.buttons["beta.create.advanced"].exists)
        XCTAssertFalse(app.textFields["beta.create.target"].exists)
        for metric in ["steps", "exercise", "distance", "timed"] {
            XCTAssertTrue(app.buttons["beta.create.metric." + metric].exists)
        }
        XCTAssertEqual(app.buttons["beta.create.metric.distance"].label, "Running distance")
        capture(app, name: "create-goal")
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
        next.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Make it a"), object: heading)], timeout: 5), .completed)
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 3 of 4, Challenge")
        capture(app, name: "create-challenge")
        let invite = app.buttons["beta.create.submit"]
        bring(app, invite)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: invite)], timeout: 10), .completed)
        invite.tap()
        let inviteHeading = app.staticTexts["beta.invite.heading"]
        XCTAssertTrue(inviteHeading.waitForExistence(timeout: 10))
        XCTAssertEqual(inviteHeading.label, "Invite friends.")
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 4 of 4, Friends")
        capture(app, name: "create-friends")
        app.buttons["beta.create.close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
    }

    func testSavedFriendLobbyInvitesPickedFriendsThenReturnsHome() {
        continueAfterFailure = false
        let app = launch("challenges")
        defer { app.terminate() }
        let create = app.buttons["beta.create.open"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let next = app.buttons["beta.create.continue"]
        // "Who's it for?" (friend goal preselected), then the goal step.
        for _ in 0..<2 {
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
            next.tap()
        }
        let invite = app.buttons["beta.create.submit"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10)); bring(app, invite)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: invite)], timeout: 10), .completed)
        invite.tap()
        let done = app.buttons["beta.invite.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Choose up to 5. They’ll each review the rules and choose their own goal."].exists)
        XCTAssertEqual(done.label, "Skip for now")
        XCTAssertFalse(app.buttons["beta.invite.links"].exists, "Invitation links stay closed")
        let sam = app.buttons["beta.invite.friend.samr"]
        let priya = app.buttons["beta.invite.friend.priya_n"]
        XCTAssertTrue(sam.waitForExistence(timeout: 10))
        sam.tap(); bring(app, priya); priya.tap()
        XCTAssertTrue(sam.isSelected)
        XCTAssertEqual(element(app, "beta.invite.count").label, "2 of 5 chosen")
        XCTAssertEqual(done.label, "Invite 2 friends")
        capture(app, name: "create-friends-picked")
        bring(app, done); done.tap()
        let saved = app.staticTexts["beta.create.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.label, "Challenge saved.")
        XCTAssertTrue(app.staticTexts["Nobody has agreed yet"].exists)
        XCTAssertTrue(app.staticTexts["You invited 2 friends"].exists)
        XCTAssertTrue(app.staticTexts["You pick the roster"].exists)
        XCTAssertTrue(app.staticTexts["beta.create.saved.summary"].exists)
        XCTAssertFalse(app.staticTexts["What counts"].exists)
        XCTAssertFalse(app.staticTexts["Full rules"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Close'")).allElementsBoundByIndex.filter(\.isHittable).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).count, 0)
        XCTAssertEqual(app.navigationBars.buttons.allElementsBoundByIndex.filter(\.isHittable).count, 0)
        let home = app.buttons["beta.create.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["beta.create.detail"].label, "View challenge")
        capture(app, name: "create-lobby-saved")
        let goal = app.buttons["beta.create.detail"]
        bring(app, goal); goal.tap()
        XCTAssertTrue(app.staticTexts["What counts"].waitForExistence(timeout: 10))
        let backs = app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(backs.count, 1)
        XCTAssertEqual(app.navigationBars.buttons.allElementsBoundByIndex.filter(\.isHittable).count, 0)
        backs[0].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        bring(app, home); home.tap()
        XCTAssertTrue(app.buttons["beta.tab.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["beta.tab.home"].isSelected)
        XCTAssertFalse(saved.exists)
    }

    func testPersonalGoalCreateOffersOutdoorRunsAndSteps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-live-design", "--live-screen=create-personal",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let heading = app.staticTexts["beta.create.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "What’s your goal?")
        XCTAssertTrue(app.staticTexts["Personal goal"].exists)
        let progress = element(app, "beta.create.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "Step 1 of 2, Goal")
        XCTAssertFalse(app.buttons["beta.create.advanced"].exists)
        XCTAssertFalse(app.buttons["beta.create.metric.exercise"].exists)
        XCTAssertFalse(app.buttons["beta.create.metric.timed"].exists)
        let runs = app.buttons["beta.create.metric.distance"]
        let steps = app.buttons["beta.create.metric.steps"]
        XCTAssertTrue(runs.waitForExistence(timeout: 5))
        XCTAssertEqual(runs.label, "Outdoor runs")
        XCTAssertTrue(steps.exists)
        XCTAssertEqual(steps.label, "Steps")
        XCTAssertTrue(steps.isSelected)
        XCTAssertTrue(app.staticTexts["Your steps"].exists)
        XCTAssertTrue(app.textFields["beta.create.target"].exists)
        capture(app, name: "create-personal-goal")
        runs.tap()
        XCTAssertTrue(runs.isSelected)
        XCTAssertFalse(steps.isSelected)
        XCTAssertTrue(app.staticTexts["Your distance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your steps"].exists)
        capture(app, name: "create-personal-goal-distance")
    }

    func testInviteReviewNeedsSeparateConsentAndDeclineUpdatesTheStore() {
        continueAfterFailure = false
        let app = launch("challenges")
        defer { app.terminate() }
        let invited = app.buttons["live.filter.invited"]
        XCTAssertTrue(invited.waitForExistence(timeout: 10)); invited.tap()
        let accept = app.buttons["Accept: review invitation"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5)); accept.tap()
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Review and agree")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        bring(app, review); review.tap()
        let consent = app.switches["beta.consent.toggle"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        bring(app, consent)
        XCTAssertEqual(consent.value as? String, "0", "Reviewing an invitation does not accept it")
        XCTAssertFalse(app.buttons["beta.consent"].isEnabled)
        let close = app.buttons["Close"]
        bring(app, close, upward: false); close.tap()
        let back = app.buttons["Back to Home"]
        bring(app, back, upward: false); back.tap()
        XCTAssertTrue(accept.waitForExistence(timeout: 5), "An unaccepted invitation remains available")
        app.buttons["Decline"].tap()
        let confirm = app.buttons["Decline invitation"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["No invitations waiting."].waitForExistence(timeout: 10),
                      "The real store must complete leave and refresh its invitation page")
        XCTAssertFalse(accept.exists)
        app.buttons["live.filter.finished"].tap()
        XCTAssertTrue(app.staticTexts["October runs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Closed early"].exists)
    }

    func testOnboardingSavesProfileAndAccountSignOutClearsTheNewShell() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "--fixture-onboarding", "--fixture-empty",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        // Nobody under 21 gives us a name or username.
        XCTAssertTrue(app.staticTexts["Before you start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You need an Apple Watch"].exists)
        XCTAssertTrue(labeled(app.staticTexts, "Your activity has to come from an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn’t count.").exists)
        XCTAssertTrue(app.staticTexts["No real money moves. Nothing can be paid out or redeemed."].exists)
        XCTAssertFalse(app.textFields["onboarding.name.input"].exists)
        let proceed = app.buttons["onboarding.age.continue"]
        XCTAssertFalse(proceed.isEnabled, "Continue waits for the 21+ confirmation")
        app.buttons["onboarding.age.under21"].tap()
        let adults = app.alerts["GameTime is for people 21 and older"]
        XCTAssertTrue(adults.waitForExistence(timeout: 5))
        XCTAssertTrue(labeled(adults.staticTexts, "You can’t use GameTime yet. We haven’t saved a profile for you. You can sign out, or use a different Apple account.").exists)
        adults.buttons["Go back"].tap()
        capture(app, name: "onboarding-age")
        app.switches["onboarding.age.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(proceed.isEnabled)
        proceed.tap()
        let name = app.textFields["onboarding.name.input"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your profile"].exists)
        XCTAssertTrue(app.staticTexts["Pick carefully — you can’t change your username yet. Friends need it to send you a request."].exists)
        let submit = app.buttons["onboarding.submit"]
        XCTAssertFalse(submit.isEnabled, "An empty profile cannot be submitted")
        name.tap(); name.typeText("Alex Native")
        let username = app.textFields["onboarding.username.input"]
        username.tap(); username.typeText("alexnative")
        XCTAssertTrue(submit.isEnabled, "A complete profile can be submitted")
        // The keyboard can cover the page button while XCTest still reports it
        // as hittable. Exercise the field's real .onSubmit path instead.
        let keyboardDone = app.keyboards.buttons["Done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        let record = app.buttons["beta.tab.you"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alex Native")).firstMatch.waitForExistence(timeout: 5),
                      "The record must use the newly saved profile")
        app.buttons["profile.settings"].tap()
        let account = settingsLink(app, "Account")
        XCTAssertTrue(account.waitForExistence(timeout: 5)); bring(app, account); account.tap()
        XCTAssertTrue(app.staticTexts["@alexnative"].waitForExistence(timeout: 5))
        let signOut = app.buttons["account-support.sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5)); signOut.tap()
        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sign in"].exists)
        XCTAssertFalse(app.buttons["beta.tab.you"].exists)
        XCTAssertFalse(element(app, "profile.count.met").exists)
        XCTAssertFalse(app.staticTexts["@alexnative"].exists, "Signing out must remove the prior account’s presentation")
    }

    func testNewSettingsPreserveHealthPrivacyAndAccountDeletionConfirmation() {
        continueAfterFailure = false
        let app = launch("you")
        defer { app.terminate() }
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let health = settingsLink(app, "Apple Health")
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        let refresh = app.buttons["settings.health.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); bring(app, refresh); refresh.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: refresh)], timeout: 10), .completed)
        let back = app.buttons["Back"]
        bring(app, back, upward: false); back.tap()
        let privacy = settingsLink(app, "Sharing & privacy")
        XCTAssertTrue(privacy.waitForExistence(timeout: 5)); privacy.tap()
        XCTAssertTrue(app.staticTexts["Missing activity isn’t a loss"].waitForExistence(timeout: 5))
        bring(app, back, upward: false); back.tap()
        let account = settingsLink(app, "Account")
        XCTAssertTrue(account.waitForExistence(timeout: 5)); bring(app, account); account.tap()
        let delete = app.buttons["account-support.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirmation = app.alerts["Delete your account?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Continue"].exists)
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["account-support.sign-out"].waitForExistence(timeout: 5))
        XCTAssertTrue(delete.isEnabled)
        XCTAssertFalse(confirmation.exists, "Cancel must leave the account intact without starting Apple confirmation")
        XCTAssertTrue(app.staticTexts["@alexlee"].exists)
    }

    // MARK: D142 friends

    func testFriendsListAnswersRequestsAndStatesEverySafetyConsequence() {
        continueAfterFailure = false
        let app = launch("friends")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Requests for you"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["If you decline, the request goes away. We don’t tell them."].exists)
        XCTAssertTrue(app.staticTexts["Requests you sent"].exists)
        XCTAssertTrue(app.staticTexts["@rileyc · Sent today"].exists)
        capture(app, name: "friends-list")

        app.buttons["Accept Taylor Kim’s request"].tap()
        XCTAssertTrue(app.staticTexts["You and Taylor are now friends."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Requests for you"].exists)

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sam Rivera")).firstMatch.tap()
        XCTAssertTrue(app.buttons["friends.remove"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["We don’t send a notice when you remove, block or report someone."].exists)
        capture(app, name: "friends-sheet")
        app.buttons["friends.block"].tap()
        let block = app.alerts["Block Sam?"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        XCTAssertTrue(labeled(block.staticTexts, "Sam won’t be able to find you or send you requests, and you’ll stop being friends. If you share a challenge that hasn’t finished, you both leave it. If fewer than two people are left, it won’t count.").exists)
        block.buttons["Cancel"].tap()
        app.buttons["friends.remove"].tap()
        let remove = app.alerts["Remove Sam?"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(remove.staticTexts["You’ll stop being friends. Challenges you already share stay as they are."].exists)
        remove.buttons["Cancel"].tap()

        app.buttons["friends.report"].tap()
        XCTAssertTrue(app.staticTexts["Tell us what’s wrong. We read every report. Sam isn’t told."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["friends.report.send"].isEnabled, "A report needs one of the three reasons")
        app.buttons["Unwanted requests or invitations"].tap()
        app.buttons["friends.report.send"].tap()
        XCTAssertTrue(app.staticTexts["Thanks for telling us"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["We’ll look into it. You can also block them."].exists)
        XCTAssertTrue(app.buttons["Block Sam"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists, "Reports take no free text")
    }

    func testAddAFriendUsesAnExactUsernameAndPlainShareText() {
        continueAfterFailure = false
        let app = launch("friends")
        defer { app.terminate() }
        let add = app.buttons["friends.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let field = app.textFields["friends.username"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Enter your friend’s exact username. They’ll need to accept before you can invite them to a challenge."].exists)
        XCTAssertTrue(app.staticTexts["@alexlee"].exists)
        XCTAssertTrue(app.buttons["Share username"].exists)

        field.typeText("nobody_here\n")
        XCTAssertTrue(labeled(app.staticTexts, "We couldn’t find @nobody_here. Usernames need to match exactly — check the spelling with your friend.").waitForExistence(timeout: 5))

        clear(field); field.typeText("taylork\n")
        XCTAssertTrue(app.staticTexts["taylork already sent you a request. Accept it to become friends."].waitForExistence(timeout: 5))

        clear(field); field.typeText("drew_p\n")
        let send = app.buttons["friends.add.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(app.staticTexts["Request sent. Drew will see it in GameTime and can accept or decline."].waitForExistence(timeout: 5))
        capture(app, name: "friends-add-sent")
    }

    func testBlockedPeopleCanBeUnblockedWithoutRestoringFriendship() {
        continueAfterFailure = false
        let app = launch("friends")
        defer { app.terminate() }
        let blocked = app.buttons["friends.blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 10))
        // On iOS 18 this bottom row can sit beneath the floating tab bar.
        app.swipeUp()
        bring(app, blocked); blocked.tap()
        XCTAssertTrue(app.staticTexts["Blocked people can’t find you or send you requests. They aren’t told."].waitForExistence(timeout: 5))
        app.buttons["Unblock Casey Wu"].tap()
        let alert = app.alerts["Unblock Casey?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Casey will be able to find you and send you requests again. You won’t become friends unless you both agree."].exists)
        alert.buttons["Unblock"].tap()
        XCTAssertTrue(app.staticTexts["No one is blocked"].waitForExistence(timeout: 5))
    }

    func testHomeActionRowsAreOrderedAndLeaveOnceHandled() {
        continueAfterFailure = false
        let app = launch("home")
        defer { app.terminate() }
        XCTAssertTrue(element(app, "home.actions").waitForExistence(timeout: 10))
        let agree = app.staticTexts["Agree to October runs"]
        let request = app.staticTexts["Friend request"]
        let accepted = app.staticTexts["Accepted your request"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        XCTAssertTrue(request.exists)
        XCTAssertTrue(accepted.exists)
        XCTAssertLessThan(agree.frame.minY, request.frame.minY)
        XCTAssertLessThan(request.frame.minY, accepted.frame.minY)
        capture(app, name: "home-action-rows")

        app.buttons["Decline Taylor Kim’s request"].tap()
        XCTAssertTrue(app.staticTexts["Request declined."].waitForExistence(timeout: 5))
        XCTAssertFalse(request.exists)
        app.buttons["Dismiss"].tap()
        XCTAssertFalse(accepted.waitForExistence(timeout: 2))
        XCTAssertTrue(agree.exists)
    }

    func testTextGrowsAndFriendActionsRemainReachableAtLargestSize() {
        continueAfterFailure = false
        var app = launch("friends", textSize: "UICTContentSizeCategoryL")
        let heading = app.staticTexts["Requests for you"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let defaultHeight = heading.frame.height
        capture(app, name: "friends-default-text")
        app.terminate()

        app = launch("friends", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        let largeHeading = app.staticTexts["Requests for you"]
        XCTAssertTrue(largeHeading.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(largeHeading.frame.height, defaultHeight * 1.4,
                             "The app must actually enlarge text, not only rearrange fixed-size labels")
        capture(app, name: "friends-largest-text")
        let accept = app.buttons["Accept Taylor Kim’s request"]
        bring(app, accept); accept.tap()
        XCTAssertTrue(app.staticTexts["You and Taylor are now friends."].waitForExistence(timeout: 5))
        let add = app.buttons["friends.add"]
        bring(app, add, upward: false); add.tap()
        let field = app.textFields["friends.username"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        bring(app, field)
        capture(app, name: "add-friend-largest-text")
        field.tap(); field.typeText("drew_p\n")
        let send = app.buttons["friends.add.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5)); bring(app, send); send.tap()
        XCTAssertTrue(app.staticTexts["Request sent. Drew will see it in GameTime and can accept or decline."].waitForExistence(timeout: 5))
    }

    func testLargestTextKeepsOnboardingConsentAndExitReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "--fixture-onboarding", "--fixture-empty",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Before you start"].waitForExistence(timeout: 10))
        capture(app, name: "onboarding-largest-text")
        let proceed = app.buttons["onboarding.age.continue"]
        XCTAssertFalse(proceed.isEnabled)
        XCTAssertTrue(app.buttons["onboarding.age.under21"].isHittable)
        let age = app.switches["onboarding.age.toggle"]
        bring(app, age)
        // XCTest may mark a partly visible switch as hittable even while the
        // pinned footer covers its right-hand toggle. Reveal the whole row.
        for _ in 0..<8 where age.frame.maxY >= proceed.frame.minY - 12 { app.swipeUp() }
        XCTAssertLessThan(age.frame.maxY, proceed.frame.minY - 12)
        capture(app, name: "onboarding-age-control-largest-text")
        age.tap()
        XCTAssertTrue(proceed.isEnabled)
        proceed.tap()
        XCTAssertTrue(app.textFields["onboarding.name.input"].waitForExistence(timeout: 5))
        capture(app, name: "profile-largest-text")
    }

    /// Friends Phase 4: the system audit on every friends screen, at the
    /// default text size and the largest accessibility size. The audit checks
    /// labels, hit areas, contrast and clipped text; it can't stand in for a
    /// person using VoiceOver. This historical audit keeps its exclusions;
    /// actual font growth is checked by the focused journey above.
    func testFriendsScreensPassTheSystemAccessibilityAuditApartFromTextSize() throws {
        continueAfterFailure = true
        for size in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let label = size == nil ? "default" : "largest"
            var app = launch("friends", textSize: size)
            XCTAssertTrue(app.staticTexts["Requests for you"].waitForExistence(timeout: 10))
            audit(app, "Friends, \(label) text")
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sam Rivera")).firstMatch.tap()
            XCTAssertTrue(app.buttons["friends.remove"].waitForExistence(timeout: 5))
            audit(app, "Friend actions, \(label) text")
            app.terminate()

            app = launch("friends", textSize: size)
            let add = app.buttons["friends.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 10)); bring(app, add); add.tap()
            XCTAssertTrue(app.textFields["friends.username"].waitForExistence(timeout: 5))
            audit(app, "Add a friend, \(label) text")
            app.terminate()

            app = launch("friends", textSize: size)
            let blocked = app.buttons["friends.blocked"]
            XCTAssertTrue(blocked.waitForExistence(timeout: 10)); bring(app, blocked); blocked.tap()
            XCTAssertTrue(app.buttons["Unblock Casey Wu"].waitForExistence(timeout: 5))
            audit(app, "Blocked people, \(label) text")
            app.terminate()

            app = launch("home", textSize: size)
            XCTAssertTrue(element(app, "home.actions").waitForExistence(timeout: 10))
            audit(app, "Home action rows, \(label) text")
            app.terminate()

            app = launch("challenges", textSize: size)
            let create = app.buttons["beta.create.open"]
            XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
            let next = app.buttons["beta.create.continue"]
            // "Who's it for?" (friend goal preselected), then the goal step.
            for _ in 0..<2 {
                XCTAssertTrue(next.waitForExistence(timeout: 10)); bring(app, next); next.tap()
            }
            let submit = app.buttons["beta.create.submit"]
            XCTAssertTrue(submit.waitForExistence(timeout: 10)); bring(app, submit); submit.tap()
            XCTAssertTrue(app.buttons["beta.invite.done"].waitForExistence(timeout: 10))
            audit(app, "Invite friends, \(label) text")
            app.terminate()

            app = XCUIApplication()
            app.launchArguments = ["--fixture-mode", "--fixture-onboarding", "--fixture-empty",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
            app.launch()
            XCTAssertTrue(app.staticTexts["Before you start"].waitForExistence(timeout: 10))
            audit(app, "Before you start, \(label) text")
            app.terminate()
        }
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        // Let a sheet or a refreshed list finish moving before the audit reads it.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 1.5)
        capture(app, name: "audit " + screen)
        var issues: [String] = [], known: [String] = [], textSize = 0
        do {
            try app.performAccessibilityAudit { issue in
                let text = "\(issue.auditType.rawValue) \(issue.compactDescription) — \(issue.element?.label ?? "no element")"
                if issue.auditType == .dynamicType { textSize += 1 }
                else if Self.knownAuditReport(screen, issue.auditType, issue.element?.label) { known.append(text) }
                else { issues.append(text) }
                return true
            }
        } catch { issues.append("audit could not run: \(error)") }
        let note = XCTAttachment(string: "\(screen): \(textSize) fixed-size text elements. Recorded, not failed: "
                                 + known.joined(separator: "; "))
        note.name = "audit notes " + screen; note.lifetime = .keepAlways; add(note)
        XCTAssertTrue(issues.isEmpty, "\(screen): \(issues.joined(separator: "; "))")
    }

    /// Reports the Phase 4 receipt explains instead of failing here. Anything
    /// else, including a new report on these screens, fails the test.
    private static func knownAuditReport(_ screen: String, _ type: XCUIAccessibilityAuditType, _ label: String?) -> Bool {
        switch (type, label) {
        case (.hitRegion, "You"): true                  // the shared tab bar, on every screen
        case (.hitRegion, "3 friends ↗"): true          // the Home goal card, not a friends control
        case (.hitRegion, "Step 1 of 2"): true          // onboarding progress dots, not a control
        case (.hitRegion, nil): screen.hasPrefix("Invite friends") // unnamed, in the shared creation header
        case (.elementDetection, nil): true             // unnamed text the audit can't point to
        case (.contrast, "Add a friend"): screen.hasPrefix("Friends") // the icon-only header button
        // At the largest text size these pages run past the screen: the open
        // keyboard, or the pinned Continue button, covers the lower text until
        // the person scrolls, so the audit reads the cover, not the text.
        case (.contrast, "Find"), (.contrast, "Your username"), (.contrast, "@alexlee"),
             (.contrast, "Send it to a friend so they can add you."):
            screen == "Add a friend, largest text" || screen.hasPrefix("Friend actions")
        case (.contrast, let label?) where label.hasPrefix("Your activity has to come from an Apple Watch"):
            screen == "Before you start, largest text" || screen.hasPrefix("Friend actions")
        // The action sheet renders fully and legibly in its captures; a person checks it.
        case (.contrast, _), (.textClipped, _): screen.hasPrefix("Friend actions")
        default: false
        }
    }

    /// XCUITest subscripts reject identifiers over 128 characters.
    private func labeled(_ query: XCUIElementQuery, _ label: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func clear(_ field: XCUIElement) {
        field.tap()
        if let text = field.value as? String, !text.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
    }

    private func launch(_ route: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-live-design", "--live-screen=" + route,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        XCTAssertTrue(app.buttons["beta.tab.home"].waitForExistence(timeout: 10))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func settingsLink(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func bring(_ app: XCUIApplication, _ target: XCUIElement, upward: Bool = true) {
        for _ in 0..<10 where !target.isHittable {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(target.isHittable, "Expected an actionable control: \(target)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
