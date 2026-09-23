import XCTest

/// Session 2 — Sam Rivera depth-path steward walkthrough.
/// Captures screenshots for human review; soft-fails so friction is visible in artifacts.
final class Session2SamStewardUITests: XCTestCase {
    private let shotDir = "/tmp/round-s2"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    @MainActor
    func testSamStewardLaunchB() throws {
        let app = launch(args: ["-stubWorkoutCapture"])
        shot(app, "01-saturday-today")

        // Multi-crew: open switcher → Lunch Break Club
        app.buttons["group.switcher"].tap()
        shot(app, "02-switcher")
        let lunch = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lunch Break Club")).firstMatch
        XCTAssertTrue(lunch.waitForExistence(timeout: 3), "Sam expects Lunch Break in the switcher")
        lunch.tap()
        shot(app, "03-lunch-today")
        XCTAssertTrue(
            app.buttons["group.switcher"].label.contains("Lunch Break Club"),
            "Today should show Lunch Break after switch"
        )

        // Recovery
        if app.buttons["today.rest"].waitForExistence(timeout: 2) {
            app.buttons["today.rest"].tap()
            shot(app, "04-recovery-confirm")
            let use = app.buttons["Use recovery day"]
            if use.waitForExistence(timeout: 2) {
                use.tap()
                shot(app, "05-after-recovery")
            } else {
                app.buttons["Cancel"].tap()
            }
        } else {
            shot(app, "04-no-rest-control")
        }

        // Re-launch fresh for two-clip walk (recovery may have consumed today)
        let walk = launch(args: ["-stubWorkoutCapture"])
        walk.buttons["group.switcher"].tap()
        let lunch2 = walk.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lunch Break Club")).firstMatch
        XCTAssertTrue(lunch2.waitForExistence(timeout: 3))
        lunch2.tap()
        shot(walk, "06-lunch-before-walk")

        if walk.buttons["today.logWorkout"].waitForExistence(timeout: 3) {
            walk.buttons["today.logWorkout"].tap()
            shot(walk, "07-walk-choose")
            if walk.buttons["workoutSession.chooseRecord"].waitForExistence(timeout: 3) {
                walk.buttons["workoutSession.chooseRecord"].tap()
            }
            shot(walk, "07b-walk-prep")
            if walk.buttons["workoutSession.skipCountdown"].waitForExistence(timeout: 3) {
                waitUntilEnabled(walk.buttons["workoutSession.skipCountdown"], timeout: 3)
                walk.buttons["workoutSession.skipCountdown"].tap()
            }
            shot(walk, "08-walk-record-start")
            if walk.buttons["workoutSession.stop"].waitForExistence(timeout: 4) {
                walk.buttons["workoutSession.stop"].tap()
            } else if walk.buttons["workoutSession.record"].waitForExistence(timeout: 1) {
                walk.buttons["workoutSession.record"].tap()
                if walk.buttons["workoutSession.stop"].waitForExistence(timeout: 4) {
                    walk.buttons["workoutSession.stop"].tap()
                }
            }
            shot(walk, "09-walk-review-start")
            if walk.buttons["workoutSession.useClip"].waitForExistence(timeout: 3) {
                walk.buttons["workoutSession.useClip"].tap()
            }
            shot(walk, "10-after-start-clip")
            // Mid-state: title "Start clip saved"; dismiss is Finish later → Today shows Finish workout.
            if walk.buttons["Record finish clip"].waitForExistence(timeout: 3)
                || walk.buttons["workoutSession.recordFinish"].waitForExistence(timeout: 1) {
                if walk.buttons["Finish later"].waitForExistence(timeout: 2) {
                    walk.buttons["Finish later"].tap()
                    shot(walk, "10b-today-pending-finish")
                } else if walk.buttons["Close"].waitForExistence(timeout: 1) {
                    walk.buttons["Close"].tap()
                    shot(walk, "10b-today-pending-finish")
                }
            }
            if walk.buttons["today.logWorkout"].waitForExistence(timeout: 3) {
                XCTAssertTrue(
                    walk.buttons["today.logWorkout"].label.contains("Finish"),
                    "Pending walk should rename CTA to Finish workout"
                )
                walk.buttons["today.logWorkout"].tap()
            }
            // Resuming pending opens choose; Record continues to finish clip.
            if walk.buttons["workoutSession.chooseRecord"].waitForExistence(timeout: 3) {
                walk.buttons["workoutSession.chooseRecord"].tap()
            }
            if walk.buttons["Record finish clip"].waitForExistence(timeout: 2)
                || walk.buttons["workoutSession.recordFinish"].waitForExistence(timeout: 1) {
                let record = walk.buttons["workoutSession.recordFinish"].exists
                    ? walk.buttons["workoutSession.recordFinish"]
                    : walk.buttons["Record finish clip"]
                record.tap()
            }
            shot(walk, "11-finish-prep")
            if walk.buttons["workoutSession.start"].waitForExistence(timeout: 2) {
                walk.buttons["workoutSession.start"].tap()
            }
            if walk.buttons["workoutSession.skipCountdown"].waitForExistence(timeout: 2) {
                waitUntilEnabled(walk.buttons["workoutSession.skipCountdown"], timeout: 3)
                walk.buttons["workoutSession.skipCountdown"].tap()
            }
            if walk.buttons["workoutSession.stop"].waitForExistence(timeout: 4) {
                walk.buttons["workoutSession.stop"].tap()
            } else if walk.buttons["workoutSession.record"].waitForExistence(timeout: 1) {
                walk.buttons["workoutSession.record"].tap()
                if walk.buttons["workoutSession.stop"].waitForExistence(timeout: 4) {
                    walk.buttons["workoutSession.stop"].tap()
                }
            }
            shot(walk, "12-finish-review")
            if walk.buttons["workoutSession.useClip"].waitForExistence(timeout: 3) {
                walk.buttons["workoutSession.useClip"].tap()
            }
            shot(walk, "13-confirm-amount")
            if walk.buttons["checkIn.submit"].waitForExistence(timeout: 3) {
                walk.buttons["checkIn.submit"].tap()
                shot(walk, "14-reveal")
                if walk.buttons["checkIn.done"].waitForExistence(timeout: 4) {
                    walk.buttons["checkIn.done"].tap()
                }
            }
            shot(walk, "15-lunch-after-checkin")
        }

        // Crew + vote on Saturday (switch back)
        walk.buttons["group.switcher"].tap()
        let saturday = walk.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Saturday Crew")).firstMatch
        if saturday.waitForExistence(timeout: 2) { saturday.tap() }
        walk.tabBars.buttons["Crew"].tap()
        shot(walk, "16-saturday-crew")
        if walk.buttons["group.openVote"].waitForExistence(timeout: 2) {
            walk.buttons["group.openVote"].tap()
            shot(walk, "17-vote")
            if walk.buttons["vote.accept"].waitForExistence(timeout: 2) {
                walk.buttons["vote.accept"].tap()
                shot(walk, "18-vote-accepted")
            }
            walk.navigationBars.buttons.firstMatch.tap()
        }

        // Members / menu
        if walk.buttons["group.menu"].waitForExistence(timeout: 2) {
            walk.buttons["group.menu"].tap()
            shot(walk, "19-crew-menu")
            let members = walk.buttons["Members"]
            if members.waitForExistence(timeout: 2) {
                members.tap()
                shot(walk, "20-members")
                walk.swipeUp()
                shot(walk, "21-members-scrolled")
                // Leaving Crew via tab must dismiss the Members sheet.
                walk.tabBars.buttons["You"].tap()
                shot(walk, "22-you")
                XCTAssertTrue(walk.staticTexts["Your crews"].waitForExistence(timeout: 3))
                XCTAssertFalse(walk.navigationBars["Members"].exists)
                let notifications = walk.buttons["Notifications"]
                for _ in 0..<5 where !notifications.exists { walk.swipeUp() }
                if notifications.waitForExistence(timeout: 2) {
                    notifications.tap()
                    shot(walk, "23-notifications")
                    for _ in 0..<4 { walk.swipeUp() }
                    shot(walk, "24-notifications-scrolled")
                }
            }
        }
    }

    @MainActor
    func testSamProposeBuilderNoProposal() throws {
        let app = launch(args: ["-noProposal"])
        app.tabBars.buttons["Crew"].tap()
        shot(app, "P01-crew-propose")
        XCTAssertTrue(app.buttons["group.propose"].waitForExistence(timeout: 3), "Propose should be visible")
        app.buttons["group.propose"].tap()
        shot(app, "P02-builder-workout")
        if app.buttons["builder.continue"].waitForExistence(timeout: 2) {
            app.buttons["builder.continue"].tap()
            shot(app, "P03-builder-target")
            app.buttons["builder.continue"].tap()
            shot(app, "P04-builder-when")
            app.buttons["builder.continue"].tap()
            shot(app, "P05-builder-review")
        }
        if app.buttons["builder.startNow"].waitForExistence(timeout: 3) {
            // Don't start — Sam reviews Put to vote vs Start now
            shot(app, "P06-builder-actions")
            let putToVote = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "vote")).firstMatch
            if putToVote.exists { /* note for canvas */ }
        }
        // Dismiss builder
        if app.buttons["Close"].waitForExistence(timeout: 1) {
            app.buttons["Close"].tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        shot(app, "P07-after-builder")
    }

    @MainActor
    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding", "-resetDemo", "-ephemeralData", "-suppressNotificationPrimer"
        ] + args
        app.launch()
        XCTAssertTrue(app.buttons["group.switcher"].waitForExistence(timeout: 6))
        return app
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \(element) to become enabled")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let data = screenshot.pngRepresentation
        let url = URL(fileURLWithPath: "\(shotDir)/\(name).png")
        try? data.write(to: url)
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}
