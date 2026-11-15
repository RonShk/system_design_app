import XCTest

/// Drives the real app in the simulator: onboarding → daily session (lesson, practice) → recap,
/// relaunch to check persistence, then shift the clock a day and check the review comes back.
/// Set SDT_SHOT_DIR in the scheme or test environment to save screenshots for inspection.
final class EndToEndUITests: XCTestCase {
    private var stateDir: String!
    private var shotDir: String? { ProcessInfo.processInfo.environment["SDT_SHOT_DIR"] }

    override func setUp() {
        continueAfterFailure = false
        stateDir = NSTemporaryDirectory() + "sdt-uitest-\(UUID().uuidString)"
    }

    private func launch(reset: Bool = false, dayOffset: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset ? ["-resetState"] : []
        app.launchEnvironment = ["SDT_STATE_DIR": stateDir, "SDT_DAY_OFFSET": "\(dayOffset)"]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name; a.lifetime = .keepAlways
        add(a)
        if let dir = shotDir {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func tapWhenReady(_ el: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 8) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(el) did not appear")
        var tries = 0
        while !el.isHittable && tries < 12 { app.swipeUp(); tries += 1 }
        el.tap()
    }

    /// Answers whatever question is on screen: picks the correct choice when visible, otherwise reveals.
    private func answerCurrentQuestion(_ app: XCUIApplication, correct: Bool, name: String? = nil) {
        let submit = app.buttons["submit-answer"]
        XCTAssertTrue(submit.waitForExistence(timeout: 8))
        if let name { shot(app, name) }
        let right = app.buttons["choice-correct"].firstMatch
        if correct, right.exists {
            tapWhenReady(right, in: app)
            tapWhenReady(submit, in: app)
        } else if correct, app.buttons["rubric-0"].exists == false, app.textViews["free-input"].exists {
            app.textViews["free-input"].tap()
            app.typeText("My answer")
            app.toolbars.buttons["Done"].firstMatch.tap()
            tapWhenReady(submit, in: app)
            tapWhenReady(app.buttons["rubric-0"], in: app)
            if app.buttons["rubric-1"].exists { tapWhenReady(app.buttons["rubric-1"], in: app) }
            tapWhenReady(app.buttons["record-assessment"], in: app)
        } else {
            tapWhenReady(app.buttons["reveal-answer"], in: app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["feedback-banner"].waitForExistence(timeout: 5))
        if let name { shot(app, name + "-feedback") }
        tapWhenReady(app.buttons["continue"], in: app)
    }

    func testDailySessionPersistsAndReviewComesBackNextDay() {
        var app = launch(reset: true)
        shot(app, "01-onboarding")
        tapWhenReady(app.buttons["onboard-skip"], in: app)
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        shot(app, "02-today")

        // Day 0: lesson, then practice.
        app.buttons["start-session"].tap()
        XCTAssertTrue(app.staticTexts["NEW LESSON"].waitForExistence(timeout: 5))
        shot(app, "03-lesson-top")
        app.swipeUp(); app.swipeUp()
        shot(app, "04-lesson-diagram")
        tapWhenReady(app.buttons["finish-lesson"], in: app)
        var n = 0
        while app.buttons["submit-answer"].waitForExistence(timeout: 3) {
            answerCurrentQuestion(app, correct: n != 1, name: n < 2 ? "05-practice-\(n)" : nil)
            n += 1
        }
        XCTAssertGreaterThanOrEqual(n, 3, "the session should contain retrieval practice")
        XCTAssertTrue(app.descendants(matching: .any)["session-recap"].waitForExistence(timeout: 5))
        shot(app, "06-recap")
        tapWhenReady(app.buttons["recap-done"], in: app)

        // Relaunch: progress must survive.
        app.terminate()
        app = launch()
        XCTAssertTrue(app.staticTexts["Done for today — or keep going"].waitForExistence(timeout: 8), "finished session should persist across relaunch")
        app.tabBars.buttons["Progress"].tap()
        shot(app, "07-progress")
        app.tabBars.buttons["Learn"].tap()
        shot(app, "08-learn")

        // Next day: the concepts come back as reviews.
        app.terminate()
        app = launch(dayOffset: 1)
        tapWhenReady(app.buttons["start-session"], in: app)
        XCTAssertTrue(app.staticTexts["REVIEW"].waitForExistence(timeout: 5), "day-1 session should start with a due review")
        answerCurrentQuestion(app, correct: true, name: "09-review")
        app.buttons["close-session"].tap()

        // Settings shows reminder status and the 3 pm default.
        tapWhenReady(app.buttons["open-settings"], in: app)
        XCTAssertTrue(app.switches["reminder-toggle"].waitForExistence(timeout: 5))
        shot(app, "10-settings")
    }

    func testTopicQuizRecordsSeparateScores() {
        let app = launch(reset: true)
        tapWhenReady(app.buttons["onboard-skip"], in: app)
        XCTAssertTrue(app.buttons["start-session"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Learn"].tap()
        tapWhenReady(app.descendants(matching: .any)["module-foundations"], in: app)
        tapWhenReady(app.descendants(matching: .any)["lesson-fnd-latency-percentiles"], in: app)
        tapWhenReady(app.buttons["lesson-practise"], in: app)
        while app.buttons["submit-answer"].waitForExistence(timeout: 3) { answerCurrentQuestion(app, correct: true) }
        tapWhenReady(app.buttons["sequence-done"], in: app)
        app.tabBars.buttons["Assess"].tap()
        tapWhenReady(app.buttons["quiz-foundations"], in: app)
        while app.buttons["assess-next"].waitForExistence(timeout: 3) {
            let right = app.buttons["choice-correct"].firstMatch
            if right.exists { tapWhenReady(right, in: app) }
            shot(app, "11-quiz")
            app.buttons["assess-next"].tap()
        }
        while app.buttons["grade-next"].waitForExistence(timeout: 3) {
            tapWhenReady(app.buttons["rubric-0"], in: app)
            app.buttons["grade-next"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["assessment-results"].waitForExistence(timeout: 5))
        shot(app, "12-quiz-results")
    }
}
