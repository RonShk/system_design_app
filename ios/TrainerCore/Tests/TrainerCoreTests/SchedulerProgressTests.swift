import XCTest
@testable import TrainerCore

final class SchedulerTests: XCTestCase {
    let catalog = Fixture.catalog()
    let c = "m0-l0-c0"

    private func introduced(_ t: TestClock) -> AppState {
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        return s
    }

    func testIntroducingSchedulesFirstReviewForTomorrow() {
        let t = TestClock("2026-03-02T09:00:00Z")
        let s = introduced(t)
        XCTAssertEqual(s.concepts[c]?.step, 0)
        XCTAssertEqual(s.concepts[c]?.dueDay, LocalDay(year: 2026, month: 3, day: 3))
        XCTAssertNotNil(s.lessonsCompleted["m0-l0"])
    }

    func testCompletingALessonTwiceDoesNotResetItsSchedule() {
        let t = TestClock()
        var s = introduced(t)
        t.advance(days: 1)
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        let before = s.concepts[c]
        t.advance(hours: 1)
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c], before)
    }

    func testSameDaySuccessDoesNotAdvance() {
        let t = TestClock()
        var s = introduced(t)
        t.advance(minutes: 10)
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 0)
        XCTAssertEqual(s.concepts[c]?.dueDay, LocalDay(year: 2026, month: 3, day: 3), "practice right after the lesson must not push the first review out")
    }

    func testIndependentSuccessesClimbTheLadder() {
        let t = TestClock()
        var s = introduced(t)
        var expectedStep = 0
        for (i, item) in ["p1", "p2", "p3", "p1", "p2"].enumerated() {
            // review exactly on the due day each time
            let due = s.concepts[c]!.dueDay!
            t.advance(days: Double(due.days(since: t.clock.today)))
            Fixture.answer("\(c)-\(item)", state: &s, catalog: catalog, clock: t.clock)
            expectedStep += 1
            XCTAssertEqual(s.concepts[c]?.step, expectedStep, "review \(i)")
            XCTAssertEqual(s.concepts[c]?.dueDay, t.clock.today.adding(days: Scheduler.ladder[expectedStep]))
        }
    }

    func testHintedSuccessHoldsTheStep() {
        let t = TestClock()
        var s = introduced(t)
        t.advance(days: 1)
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)        // step 1
        t.advance(days: 3)
        Fixture.answer("\(c)-p2", hints: 1, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 1)
        XCTAssertEqual(s.concepts[c]?.dueDay, t.clock.today.adding(days: 3))
    }

    func testFailureDropsTwoStepsAndIsDueTomorrow() {
        let t = TestClock()
        var s = introduced(t)
        s.concepts[c]?.step = 4
        s.concepts[c]?.lastReviewedAt = t.date
        s.concepts[c]?.dueDay = t.clock.today.adding(days: 30)
        t.advance(days: 30)
        Fixture.answer("\(c)-p1", correct: false, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 2)
        XCTAssertEqual(s.concepts[c]?.dueDay, t.clock.today.adding(days: 1))
        XCTAssertEqual(s.concepts[c]?.lapses, 1)
        XCTAssertEqual(s.concepts[c]?.misconception, false)
    }

    func testRevealCountsAsFailureEvenWhenEarly() {
        let t = TestClock()
        var s = introduced(t)
        s.concepts[c]?.step = 3
        Fixture.answer("\(c)-p2", revealed: true, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 1)
        XCTAssertEqual(s.attempts.last?.assistance, .revealed)
        XCTAssertEqual(s.attempts.last?.outcome, .incorrect)
    }

    func testHighConfidenceFailureResetsAndFlagsMisconception() {
        let t = TestClock()
        var s = introduced(t)
        s.concepts[c]?.step = 5
        t.advance(days: 60)
        Fixture.answer("\(c)-p1", correct: false, confidence: .high, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 0)
        XCTAssertEqual(s.concepts[c]?.misconception, true)
        t.advance(days: 1)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.misconception, false, "an independent success clears the flag")
    }

    func testVeryLateSuccessSkipsAStep() {
        let t = TestClock()
        var s = introduced(t)               // step 0, interval 1; next interval is 3
        t.advance(days: 5)                  // survived a 5-day gap
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 2)
        XCTAssertEqual(s.concepts[c]?.dueDay, t.clock.today.adding(days: 7))
    }

    func testPartialAnswerDropsOneStep() {
        let t = TestClock()
        var s = introduced(t)
        s.concepts[c]?.step = 3
        t.advance(days: 14)
        Fixture.answer("\(c)-p2", partial: true, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.attempts.last?.outcome, .partial)
        XCTAssertEqual(s.concepts[c]?.step, 2)
    }

    func testStepNeverExceedsLadder() {
        let t = TestClock()
        var s = introduced(t)
        s.concepts[c]?.step = Scheduler.maxStep
        t.advance(days: 400)
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, Scheduler.maxStep)
    }

    // Day boundaries and time zones

    func testDueDayUsesLocalCalendarDayNotElapsedHours() {
        // 23:30 local in Los Angeles; one hour later is the next local day.
        let t = TestClock("2026-03-03T07:30:00Z", zone: "America/Los_Angeles")
        var s = introduced(t)
        XCTAssertEqual(s.concepts[c]?.dueDay, LocalDay(year: 2026, month: 3, day: 3))
        XCTAssertTrue(Scheduler.dueConcepts(state: s, catalog: catalog, clock: t.clock).isEmpty)
        t.advance(hours: 1)     // 00:30 on 3 March local
        XCTAssertTrue(Scheduler.dueConcepts(state: s, catalog: catalog, clock: t.clock).contains(c))
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.step, 1, "one calendar day later counts as a spaced review even though only an hour passed")
    }

    func testDaylightSavingChangeDoesNotShiftDueDays() {
        // US DST starts 2026-03-08: that local day is 23 hours long.
        let t = TestClock("2026-03-07T20:00:00Z", zone: "America/New_York")
        let s = introduced(t)
        XCTAssertEqual(s.concepts[c]?.dueDay, LocalDay(year: 2026, month: 3, day: 8))
        let day = LocalDay(year: 2026, month: 3, day: 7)
        XCTAssertEqual(day.adding(days: 1), LocalDay(year: 2026, month: 3, day: 8))
        XCTAssertEqual(day.adding(days: 2), LocalDay(year: 2026, month: 3, day: 9))
        XCTAssertEqual(LocalDay(year: 2026, month: 3, day: 9).days(since: day), 2)
        // Autumn change (25-hour day) as well.
        XCTAssertEqual(LocalDay(year: 2026, month: 11, day: 2).days(since: LocalDay(year: 2026, month: 10, day: 31)), 2)
    }

    func testMonthAndYearRollover() {
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1), LocalDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDay(year: 2028, month: 2, day: 28).adding(days: 1), LocalDay(year: 2028, month: 2, day: 29))
        XCTAssertEqual(LocalDay(string: "2026-03-09")?.description, "2026-03-09")
        XCTAssertNil(LocalDay(string: "2026-13-01"))
    }

    func testTravellingWestDoesNotMakeAReviewDueTwice() {
        let t = TestClock("2026-03-02T22:00:00Z", zone: "Asia/Tokyo")   // 3 March 07:00 in Tokyo
        var s = introduced(t)                                            // due 4 March
        t.advance(days: 1)                                               // 4 March in Tokyo
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(s.concepts[c]?.dueDay, LocalDay(year: 2026, month: 3, day: 7))
        // Same instant seen from Honolulu is still 3 March; nothing is due there.
        var hawaii = Calendar(identifier: .gregorian); hawaii.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let west = Clock(now: { t.date }, calendar: hawaii)
        XCTAssertFalse(Scheduler.dueConcepts(state: s, catalog: catalog, clock: west).contains(c))
    }

    func testDueOrderIsMostOverdueFirst() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 2)
        Engine.completeLesson("m0-l1", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 1)
        XCTAssertEqual(Scheduler.dueConcepts(state: s, catalog: catalog, clock: t.clock), ["m0-l0-c0", "m0-l0-c1", "m0-l1-c0", "m0-l1-c1"])
        XCTAssertEqual(Scheduler.forecast(state: s, clock: t.clock, days: 3), [4, 0, 0])
    }
}

final class ProgressTests: XCTestCase {
    let catalog = Fixture.catalog()
    let c = "m0-l0-c0"

    private func status(_ s: AppState, _ t: TestClock) -> ConceptStatus { Progress.status(of: c, state: s, clock: t.clock) }

    func testStatesFromNotStartedToPracticed() {
        let t = TestClock()
        var s = AppState()
        XCTAssertEqual(status(s, t).state, .notStarted)
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .introduced)
        Fixture.answer("\(c)-p1", correct: false, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .practiced)
    }

    func testOneCorrectAnswerIsNotMastery() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .practiced)
    }

    func testRepeatingTheSameItemIsNotMastery() {
        let t = TestClock()
        var s = AppState()
        for _ in 0..<5 { Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock); t.advance(days: 1) }
        XCTAssertEqual(status(s, t).state, .practiced)
    }

    func testMultipleChoiceAloneIsNotMastery() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-a2", context: .quiz, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .practiced, "two recognition items are not enough")
        Fixture.answer("\(c)-p3", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .demonstrated)
    }

    func testHintedAndRevealedAnswersAreNotEvidence() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", hints: 1, state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", hints: 2, state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p3", revealed: true, state: &s, catalog: catalog, clock: t.clock)
        let st = status(s, t)
        XCTAssertEqual(st.state, .practiced)
        XCTAssertEqual(st.independentSuccesses, 0)
    }

    func testSameDaySuccessIsNeverRetention() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        t.advance(hours: 2)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 6)
        Fixture.answer("\(c)-p3", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .demonstrated, "a 6-day gap is below the threshold")
    }

    func testDelayedSuccessOnADifferentItemIsRetention() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .demonstrated)
        t.advance(days: 7)
        Fixture.answer("\(c)-a1", context: .delayedCheck, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .retained)
    }

    func testDelayedSuccessOnTheSameItemIsNotRetention() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 10)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).state, .demonstrated, "re-answering the remembered question proves little")
    }

    func testNeedsReviewReasons() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertFalse(status(s, t).needsReview)
        Fixture.answer("\(c)-p1", correct: false, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).reviewReason, .lastAnswerWrong)
        t.advance(days: 1)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        XCTAssertFalse(status(s, t).needsReview)
        Fixture.answer("\(c)-p3", correct: false, confidence: .high, state: &s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(status(s, t).reviewReason, .misconception)
    }

    func testOverdueBeyondOwnIntervalNeedsReview() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)   // due +1, interval 1
        t.advance(days: 2)
        XCTAssertFalse(status(s, t).needsReview, "one day late is within tolerance")
        t.advance(days: 1)
        XCTAssertEqual(status(s, t).reviewReason, .overdue)
    }

    func testSelfAssessedAndAutoEvidenceAreCountedSeparately() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p3", state: &s, catalog: catalog, clock: t.clock)
        let st = status(s, t)
        XCTAssertEqual(st.autoSuccesses, 2)
        XCTAssertEqual(st.selfSuccesses, 1)
        XCTAssertEqual(s.attempts.map(\.grading), [.auto, .selfAssessed, .auto])
    }

    func testSummaryCountsCoverageAndRetentionSeparately() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", state: &s, catalog: catalog, clock: t.clock)
        let statuses = Progress.allStatuses(state: s, catalog: catalog, clock: t.clock)
        let sum = Progress.summary(of: catalog.concepts(in: "m0"), statuses: statuses)
        XCTAssertEqual(sum.total, 6)
        XCTAssertEqual(sum.covered, 2)
        XCTAssertEqual(sum.demonstrated, 1)
        XCTAssertEqual(sum.retained, 0)
        XCTAssertEqual(statuses[c], status(s, t))
    }

    func testCalibrationAndWeakConcepts() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", confidence: .high, state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p2", correct: false, confidence: .high, state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("\(c)-p3", correct: false, confidence: .low, state: &s, catalog: catalog, clock: t.clock)
        let cal = Progress.calibration(state: s)
        XCTAssertEqual(cal[.high]?.rate, 0.5)
        XCTAssertEqual(cal[.low]?.rate, 0)
        let weak = Progress.weakConcepts(statuses: Progress.allStatuses(state: s, catalog: catalog, clock: t.clock), state: s, catalog: catalog, limit: 5)
        XCTAssertEqual(weak, [c])
    }
}
