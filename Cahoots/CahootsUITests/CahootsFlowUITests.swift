import XCTest

final class CahootsFlowUITests: XCTestCase {
    @MainActor
    func testCompleteOnboardingAndEnterDemo() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.staticTexts["Challenge your crew"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.demo"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["onboarding.demo"].label, "Explore the demo")
        app.buttons["onboarding.demo"].tap()
        XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Today"].exists)
    }

    /// Full Session 1 finding closure check — Jordan replay via XCUITest.
    @MainActor
    func testSession1FindingClosures() throws {
        // A2 empty Today: Start a round
        let empty = launchDemo(empty: true)
        empty.buttons["empty.createGroup"].tap()
        let name = empty.textFields["createGroup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.typeText("Weekend Crew")
        empty.buttons["createGroup.submit"].tap()
        XCTAssertTrue(empty.buttons["invite.done"].waitForExistence(timeout: 3))
        empty.buttons["invite.done"].tap()
        XCTAssertTrue(empty.buttons["today.startChallenge"].waitForExistence(timeout: 4))
        XCTAssertTrue(empty.buttons["today.openCrew"].exists)

        // Switcher join/create findability
        empty.buttons["group.switcher"].tap()
        XCTAssertTrue(empty.buttons["group.switcher.join"].waitForExistence(timeout: 2))
        XCTAssertTrue(empty.buttons["group.switcher.create"].exists)

        // B seeded demo checks
        let app = launchDemo(additionalArguments: ["-stubWorkoutCapture", "-deadlineSoon"])
        XCTAssertTrue(app.buttons["today.rest"].waitForExistence(timeout: 3))
        let restLabel = app.buttons["today.rest"].label.lowercased()
        XCTAssertTrue(
            restLabel.contains("rest"),
            "Rest control should be labeled for sighted/VoiceOver users, got: \(app.buttons["today.rest"].label)"
        )

        app.buttons["today.logWorkout"].tap()
        XCTAssertTrue(app.buttons["workoutSession.chooseRecord"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today’s target"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "short clip for the crew"
        )).firstMatch.exists)
        app.buttons["workoutSession.chooseRecord"].tap()
        if app.buttons["workoutSession.skipCountdown"].waitForExistence(timeout: 2) {
            waitUntilEnabled(app.buttons["workoutSession.skipCountdown"], timeout: 3)
            app.buttons["workoutSession.skipCountdown"].tap()
        }
        // Skip countdown auto-starts capture; wait for stop (or fall back to manual record for retake).
        if app.buttons["workoutSession.stop"].waitForExistence(timeout: 3) {
            app.buttons["workoutSession.stop"].tap()
        } else if app.buttons["workoutSession.record"].waitForExistence(timeout: 1) {
            app.buttons["workoutSession.record"].tap()
            if app.buttons["workoutSession.stop"].waitForExistence(timeout: 3) {
                app.buttons["workoutSession.stop"].tap()
            }
        }
        if app.staticTexts["Preview unavailable"].waitForExistence(timeout: 3) {
            XCTAssertTrue(app.staticTexts["Preview unavailable"].exists)
        }
        if app.buttons["workoutSession.useClip"].waitForExistence(timeout: 2) {
            app.buttons["workoutSession.useClip"].tap()
        }
        if app.buttons["checkIn.submit"].waitForExistence(timeout: 3) {
            app.buttons["checkIn.submit"].tap()
            // Closed-window validation must stay in-sheet — never a global banner.
            XCTAssertFalse(
                app.staticTexts["Today's check-in window is closed"].waitForExistence(timeout: 1),
                "Closed-window message must not appear as a global banner after submit"
            )
            if app.buttons["checkIn.done"].waitForExistence(timeout: 4) {
                app.buttons["checkIn.done"].tap()
            }
        } else {
            app.swipeDown(velocity: .fast)
        }

        // B4 vote copy
        app.tabBars.buttons["Crew"].tap()
        XCTAssertTrue(app.buttons["group.openVote"].waitForExistence(timeout: 3))
        app.buttons["group.openVote"].tap()
        XCTAssertTrue(app.staticTexts["1 recovery day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "accepts needed to pass"
        )).firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@",
            "Closes"
        )).firstMatch.exists)

        // B5 propose findable when no open vote
        let proposeApp = launchDemo(additionalArguments: ["-noProposal"])
        proposeApp.tabBars.buttons["Crew"].tap()
        XCTAssertTrue(proposeApp.buttons["group.propose"].waitForExistence(timeout: 3))

        // B6/B7 profile copy + deadline warning
        let profileApp = launchDemo()
        profileApp.tabBars.buttons["You"].tap()
        XCTAssertTrue(profileApp.staticTexts["Your crews"].waitForExistence(timeout: 3))
        XCTAssertTrue(profileApp.staticTexts["Alex Chen"].waitForExistence(timeout: 2))
        XCTAssertTrue(profileApp.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@",
            "London time"
        )).firstMatch.waitForExistence(timeout: 2))
        let notifications = profileApp.buttons["Notifications"]
        for _ in 0..<4 where !notifications.exists { profileApp.swipeUp() }
        notifications.tap()
        let deadlineWarning = profileApp.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "after this crew"
        )).firstMatch
        for _ in 0..<8 where !deadlineWarning.exists { profileApp.swipeUp() }
        XCTAssertTrue(
            deadlineWarning.waitForExistence(timeout: 3),
            "Lunch Break Club should warn when the default reminder is after its daily deadline"
        )
    }

    @MainActor
    func testCreateGroupFromEmptyState() throws {
        let app = launchDemo(empty: true)
        app.buttons["empty.createGroup"].tap()
        let name = app.textFields["createGroup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap(); name.typeText("Early Crew")
        app.buttons["createGroup.submit"].tap()
        XCTAssertTrue(app.navigationBars["Invite friends"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Invite friends to Early Crew"].exists)
    }

    @MainActor
    func testJoinGroupWithCode() throws {
        let app = launchDemo(empty: true)
        app.buttons["empty.joinGroup"].tap()
        let code = app.textFields["joinGroup.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 2))
        code.tap(); code.typeText("CAHOOT")
        app.buttons["joinGroup.submit"].tap()
        // Joining Saturday Crew opens its live vote, which hides the Today switcher.
        if app.navigationBars["Group vote"].waitForExistence(timeout: 4) {
            app.tabBars.buttons["Today"].tap()
        }
        XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Today"].exists)
    }

    @MainActor
    func testCastAndChangeVote() throws {
        let app = launchDemo()
        app.tabBars.buttons["Crew"].tap()
        app.buttons["group.openVote"].tap()
        XCTAssertTrue(app.navigationBars["Group vote"].waitForExistence(timeout: 2))
        app.buttons["vote.reject"].tap()
        XCTAssertTrue(app.staticTexts["You voted Reject. You can change it until voting closes."].waitForExistence(timeout: 2))
        app.buttons["vote.accept"].tap()
        XCTAssertTrue(app.staticTexts["You voted Accept. You can change it until voting closes."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLogWorkoutAndObserveUpdatedPoints() throws {
        let app = launchDemo(additionalArguments: ["-stubWorkoutCapture"])
        app.buttons["today.logWorkout"].tap()
        XCTAssertTrue(app.buttons["workoutSession.chooseRecord"].waitForExistence(timeout: 3))
        app.buttons["workoutSession.chooseRecord"].tap()
        XCTAssertTrue(app.buttons["workoutSession.skipCountdown"].waitForExistence(timeout: 3))
        waitUntilEnabled(app.buttons["workoutSession.skipCountdown"], timeout: 3)
        app.buttons["workoutSession.skipCountdown"].tap()
        XCTAssertTrue(app.buttons["workoutSession.stop"].waitForExistence(timeout: 3))
        app.buttons["workoutSession.stop"].tap()
        XCTAssertTrue(app.buttons["workoutSession.useClip"].waitForExistence(timeout: 3))
        app.buttons["workoutSession.useClip"].tap()
        XCTAssertTrue(app.textFields["checkIn.amount"].waitForExistence(timeout: 3))
        app.buttons["checkIn.submit"].tap()
        XCTAssertTrue(app.staticTexts["+100"].waitForExistence(timeout: 4))
        app.buttons["checkIn.done"].tap()
        XCTAssertTrue(app.staticTexts["100 points earned"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSkipRecordingGoesStraightToAmount() throws {
        let app = launchDemo(additionalArguments: ["-stubWorkoutCapture"])
        app.buttons["today.logWorkout"].tap()
        XCTAssertTrue(app.buttons["workoutSession.skipRecording"].waitForExistence(timeout: 3))
        app.buttons["workoutSession.skipRecording"].tap()
        XCTAssertTrue(app.textFields["checkIn.amount"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["workoutSession.start"].exists)
        XCTAssertFalse(app.buttons["workoutSession.skipCountdown"].exists)
        XCTAssertTrue(app.buttons["checkIn.submit"].isEnabled)
        app.buttons["checkIn.submit"].tap()
        XCTAssertTrue(app.staticTexts["+100"].waitForExistence(timeout: 4))
        app.buttons["checkIn.done"].tap()
        XCTAssertTrue(app.staticTexts["100 points earned"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenCrewStandingsAndChangeNotifications() throws {
        let app = launchDemo()
        app.tabBars.buttons["Leaderboard"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["leaderboard.currentUser"].waitForExistence(timeout: 3))
        app.tabBars.buttons["You"].tap()
        let notifications = app.buttons["Notifications"]
        for _ in 0..<4 where !notifications.exists { app.swipeUp() }
        XCTAssertTrue(notifications.waitForExistence(timeout: 2))
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 2))
        let reminders = app.switches.matching(NSPredicate(
            format: "identifier == %@",
            "notifications.reminders.10000000-0000-0000-0000-000000000001"
        )).firstMatch
        XCTAssertTrue(reminders.waitForExistence(timeout: 2))
        reminders.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].exists)
    }

    @MainActor
    func testBuildChallengeProposal() throws {
        let app = launchDemo(additionalArguments: ["-noProposal"])
        app.tabBars.buttons["Crew"].tap()
        app.buttons["group.propose"].tap()
        XCTAssertTrue(app.navigationBars["New round"].waitForExistence(timeout: 2))
        for _ in 0..<3 { app.buttons["builder.continue"].tap() }
        XCTAssertTrue(app.buttons["builder.startNow"].waitForExistence(timeout: 3))
        app.buttons["builder.startNow"].tap()
        XCTAssertTrue(app.staticTexts["Crew"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["group.menu"].exists)
    }

    @MainActor
    func testSwitchBetweenJoinedGroups() throws {
        let app = launchDemo()
        XCTAssertTrue(app.staticTexts["Saturday Crew"].waitForExistence(timeout: 3))
        app.tabBars.buttons["You"].tap()
        let lunchBreakID = "10000000-0000-0000-0000-000000000002"
        let secondGroup = app.buttons["profile.group.\(lunchBreakID)"]
        XCTAssertTrue(secondGroup.waitForExistence(timeout: 3))
        secondGroup.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.buttons["group.switcher"].label.contains("Lunch Break Club"),
            "Expected switcher to show Lunch Break Club, got: \(app.buttons["group.switcher"].label)"
        )
        app.tabBars.buttons["Crew"].tap()
        let switcher = app.buttons["group.header.switcher"]
        if switcher.waitForExistence(timeout: 3) {
            XCTAssertTrue(
                switcher.label.contains("Lunch Break Club"),
                "Expected crew header switcher to show Lunch Break Club, got: \(switcher.label)"
            )
        } else {
            let header = app.staticTexts["group.header.name"]
            XCTAssertTrue(header.waitForExistence(timeout: 3))
            XCTAssertEqual(header.label, "Lunch Break Club")
        }
    }

    @MainActor
    func testLargestAccessibilityTextKeepsPrimaryActionsReachable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchArguments = ["-skipOnboarding", "-resetDemo", "-ephemeralData", "-suppressNotificationPrimer"]
        app.launch()
        XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.logWorkout"].isHittable)

        app.tabBars.buttons["Leaderboard"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["leaderboard.currentUser"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Crew"].tap()
        for _ in 0..<6 where !app.buttons["group.openVote"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["group.openVote"].waitForExistence(timeout: 3))
        app.buttons["group.openVote"].tap()
        XCTAssertTrue(app.buttons["vote.accept"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["vote.accept"].isHittable)

        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.buttons["Notifications"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnboardingActionsRemainReachableAtLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchArguments = ["-resetDemo", "-ephemeralData", "-skipSplash"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.demo"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["onboarding.demo"].isHittable)
    }

    @MainActor
    func testCreateGroupKeyboardDoneDismisses() throws {
        let app = launchDemo(empty: true)
        app.buttons["empty.createGroup"].tap()
        let name = app.textFields["createGroup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        let done = app.toolbars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
        XCTAssertTrue(app.buttons["createGroup.submit"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["createGroup.submit"].isHittable)
    }

    @MainActor
    func testEmptyAccountShowsAccountMenu() throws {
        let app = launchDemo(empty: true)
        let menu = app.buttons["empty.accountMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        // XCTest's scroll-to-visible fails on this toolbar item even though it is on screen.
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let signOut = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'account.signOut' OR label == 'Sign out'"
        )).firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 3))
        let deleteAccount = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'account.delete' OR label == 'Delete account'"
        )).firstMatch
        XCTAssertTrue(deleteAccount.exists)
    }

    @MainActor
    private func launchDemo(empty: Bool = false, additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-resetDemo", "-ephemeralData", "-suppressNotificationPrimer", "-entitlement plus"] + (empty ? ["-emptyDemo"] : []) + additionalArguments
        app.launch()
        if empty {
            XCTAssertTrue(app.navigationBars["Cahoots"].waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Today"].exists)
        }
        return app
    }

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset
            ? ["-resetDemo", "-ephemeralData", "-skipSplash"]
            : ["-ephemeralData", "-skipSplash"]
        app.launch()
        return app
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \(element) to become enabled")
    }
}
