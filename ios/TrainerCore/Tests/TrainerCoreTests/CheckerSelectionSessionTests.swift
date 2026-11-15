import XCTest
@testable import TrainerCore

final class CheckerTests: XCTestCase {
    let catalog = Fixture.catalog()
    private func item(_ suffix: String) -> Item { catalog.items["m0-l0-c0-\(suffix)"]! }

    private func numeric(answer: Double, tolerance: Double? = nil, tolAbs: Double? = nil) -> Item {
        var obj: [String: Any] = ["id": "n", "concepts": ["c"], "pool": "practice", "skill": "estimate", "format": "numeric",
                                  "difficulty": 1, "prompt": [Any](), "hints": [String](), "explanation": [Any](), "sources": [Any](),
                                  "answer": answer, "unit": "x"]
        if let tolerance { obj["tolerance"] = tolerance }
        if let tolAbs { obj["tolAbs"] = tolAbs }
        return try! JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    func testMultipleChoice() {
        XCTAssertEqual(Checker.check(.choice(1), item: item("p1"))?.outcome, .correct)
        XCTAssertEqual(Checker.check(.choice(0), item: item("p1"))?.outcome, .incorrect)
        XCTAssertEqual(Checker.check(.choice(1), item: item("p1"))?.grading, .auto)
    }

    func testMultiSelectNeedsExactSet() {
        let obj: [String: Any] = ["id": "m", "concepts": ["c"], "pool": "practice", "skill": "recall", "format": "multi", "difficulty": 1,
                                  "prompt": [Any](), "hints": [String](), "explanation": [Any](), "sources": [Any](),
                                  "choices": ["a", "b", "c", "d"], "answers": [0, 2]]
        let it = try! JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(Checker.check(.choices([0, 2]), item: it)?.outcome, .correct)
        let partial = Checker.check(.choices([0]), item: it)!
        XCTAssertEqual(partial.outcome, .incorrect)
        XCTAssertEqual(partial.score, 0.75, accuracy: 1e-9)
        XCTAssertEqual(Checker.check(.choices([0, 1, 2]), item: it)?.outcome, .incorrect, "an extra wrong choice is not correct")
    }

    func testRelativeToleranceBoundaries() {
        let it = numeric(answer: 200, tolerance: 0.1)
        for ok in ["200", "180", "220", "180.0", "2e2", "0.2k"] { XCTAssertEqual(Checker.check(.number(ok), item: it)?.outcome, .correct, ok) }
        for bad in ["179.9", "220.1", "0", "-200", "2000"] { XCTAssertEqual(Checker.check(.number(bad), item: it)?.outcome, .incorrect, bad) }
    }

    func testAbsoluteToleranceBoundaries() {
        let it = numeric(answer: 99.8, tolAbs: 0.06)
        XCTAssertEqual(Checker.check(.number("99.8"), item: it)?.outcome, .correct)
        XCTAssertEqual(Checker.check(.number("99.86"), item: it)?.outcome, .correct)
        XCTAssertEqual(Checker.check(.number("99.74%"), item: it)?.outcome, .correct)
        XCTAssertEqual(Checker.check(.number("99.9"), item: it)?.outcome, .incorrect)
        XCTAssertEqual(Checker.check(.number("99"), item: it)?.outcome, .incorrect)
    }

    func testZeroAndNegativeAnswers() {
        XCTAssertEqual(Checker.check(.number("0"), item: numeric(answer: 0, tolAbs: 0))?.outcome, .correct)
        XCTAssertEqual(Checker.check(.number("0.1"), item: numeric(answer: 0, tolAbs: 0))?.outcome, .incorrect)
        XCTAssertEqual(Checker.check(.number("-52"), item: numeric(answer: -50, tolerance: 0.05))?.outcome, .correct)
        XCTAssertEqual(Checker.check(.number("-53"), item: numeric(answer: -50, tolerance: 0.05))?.outcome, .incorrect)
    }

    func testNumberParsing() {
        XCTAssertEqual(Checker.parseNumber(" 1,200 "), 1200)
        XCTAssertEqual(Checker.parseNumber("1 200 000"), 1_200_000)
        XCTAssertEqual(Checker.parseNumber("1.5e3"), 1500)
        XCTAssertEqual(Checker.parseNumber("1.5k"), 1500)
        XCTAssertEqual(Checker.parseNumber("2M"), 2_000_000)
        XCTAssertEqual(Checker.parseNumber("3x10^4"), 30000)
        XCTAssertEqual(Checker.parseNumber("45%"), 45)
        XCTAssertNil(Checker.parseNumber(""))
        XCTAssertNil(Checker.parseNumber("abc"))
        XCTAssertNil(Checker.parseNumber("k"))
        XCTAssertNil(Checker.parseNumber("1.2.3"))
        XCTAssertNil(Checker.check(.number("lots"), item: numeric(answer: 1, tolerance: 0.1)), "unparseable input is not graded as wrong")
    }

    func testOrdering() {
        let obj: [String: Any] = ["id": "o", "concepts": ["c"], "pool": "practice", "skill": "recall", "format": "order", "difficulty": 1,
                                  "prompt": [Any](), "hints": [String](), "explanation": [Any](), "sources": [Any](), "steps": ["a", "b", "c", "d"]]
        let it = try! JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(Checker.check(.ordering([0, 1, 2, 3]), item: it)?.outcome, .correct)
        XCTAssertEqual(Checker.check(.ordering([1, 0, 2, 3]), item: it)?.outcome, .incorrect)
        XCTAssertNil(Checker.check(.ordering([0, 1, 2]), item: it))
        XCTAssertNil(Checker.check(.ordering([0, 0, 2, 3]), item: it))
    }

    func testRubricSelfAssessment() {
        let it = item("p2")   // rubric of 2 points
        XCTAssertEqual(Checker.check(.rubric([0, 1]), item: it), CheckResult(outcome: .correct, score: 1, grading: .selfAssessed))
        XCTAssertEqual(Checker.check(.rubric([1]), item: it)?.outcome, .partial)
        XCTAssertEqual(Checker.check(.rubric([]), item: it)?.outcome, .incorrect)
        XCTAssertEqual(Checker.check(.rubric([0, 1, 9]), item: it)?.score, 1, "indexes outside the rubric are ignored")
    }

    func testResponseOfTheWrongKindIsRejected() {
        XCTAssertNil(Checker.check(.number("1"), item: item("p1")))
        XCTAssertNil(Checker.check(.choice(0), item: item("p2")))
    }
}

final class SelectionTests: XCTestCase {
    let catalog = Fixture.catalog()
    let c = "m0-l0-c0"

    func testNeverRepeatsThePreviousItemAndCyclesThroughAll() {
        let t = TestClock()
        var s = AppState()
        var seen: [String] = []
        for _ in 0..<6 {
            let pick = ItemSelector.pick(concept: c, pools: [.practice], catalog: catalog, history: History(state: s))!
            XCTAssertNotEqual(pick.id, seen.last)
            seen.append(pick.id)
            Fixture.answer(pick.id, state: &s, catalog: catalog, clock: t.clock)
            t.advance(days: 1)
        }
        XCTAssertEqual(Set(seen.prefix(3)).count, 3, "all three practice items are used before any repeats")
    }

    func testPrefersADifferentFormatFromLastTime() {
        let t = TestClock()
        var s = AppState()
        Fixture.answer("\(c)-p1", state: &s, catalog: catalog, clock: t.clock)   // mcq
        let pick = ItemSelector.pick(concept: c, pools: [.practice, .assess], catalog: catalog, history: History(state: s))!
        XCTAssertNotEqual(pick.format, .mcq)
    }

    func testPracticeSelectionNeverReturnsAssessmentItems() {
        let s = AppState()
        for concept in catalog.concepts.keys {
            let pick = ItemSelector.pick(concept: concept, pools: [.practice], catalog: catalog, history: History(state: s))
            XCTAssertEqual(pick?.pool, .practice)
        }
    }

    func testLongIntervalReviewBecomesADelayedCheckWithAnUnseenAssessmentItem() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        let early = ItemSelector.reviewItem(concept: c, state: s, catalog: catalog, history: History(state: s), clock: t.clock)!
        XCTAssertEqual(early.context, .review)
        XCTAssertEqual(early.item.pool, .practice)
        s.concepts[c]?.step = 2
        let late = ItemSelector.reviewItem(concept: c, state: s, catalog: catalog, history: History(state: s), clock: t.clock)!
        XCTAssertEqual(late.context, .delayedCheck)
        XCTAssertEqual(late.item.pool, .assess)
    }
}

final class SessionTests: XCTestCase {
    let catalog = Fixture.catalog()

    func testFirstSessionIsLessonThenPractice() {
        let t = TestClock()
        let plan = SessionComposer.compose(state: AppState(), catalog: catalog, clock: t.clock, minutes: 15)
        XCTAssertEqual(plan.steps.first, .lesson("m0-l0"))
        XCTAssertEqual(plan.steps.count, 5)
        let practice = plan.steps.dropFirst().compactMap(\.itemId).map { catalog.itemMetaById[$0]! }
        XCTAssertTrue(practice.allSatisfy { $0.pool == .practice && $0.lessonId == "m0-l0" })
        XCTAssertEqual(Set(practice.map(\.primaryConcept)).count, 2, "both concepts of the lesson are practised")
        XCTAssertGreaterThanOrEqual(Set(practice.map(\.format)).count, 2)
    }

    func testOrderIsReviewsLessonPracticeApplication() {
        let t = TestClock()
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 1)
        let plan = SessionComposer.compose(state: s, catalog: catalog, clock: t.clock, minutes: 15)
        let kinds = plan.steps.map { step -> String in
            switch step { case .review: "review"; case .lesson: "lesson"; case .practice: "practice"; case .application: "application" }
        }
        XCTAssertEqual(kinds, ["review", "review", "lesson", "practice", "practice", "practice", "practice", "application"])
        XCTAssertEqual(plan.steps[2], .lesson("m0-l1"))
        guard case .application(let app) = plan.steps.last! else { return XCTFail() }
        let meta = catalog.itemMetaById[app]!
        XCTAssertTrue(["m0-l0-c0", "m0-l0-c1"].contains(meta.primaryConcept), "application problem comes from an earlier lesson")
        XCTAssertGreaterThanOrEqual(meta.difficulty, 2)
        XCTAssertEqual(Set(plan.steps.compactMap(\.itemId)).count, plan.steps.compactMap(\.itemId).count, "no item appears twice")
    }

    func testShortSessionsAreSmallerAndLargeBacklogsSkipNewLessons() {
        let t = TestClock()
        var s = AppState()
        XCTAssertEqual(SessionComposer.compose(state: s, catalog: catalog, clock: t.clock, minutes: 10).steps.count, 4)
        XCTAssertEqual(SessionComposer.compose(state: s, catalog: catalog, clock: t.clock, minutes: 30).steps.count, 7)
        let big = Fixture.catalog(modules: 2, lessonsPerModule: 6)
        for l in big.lessons.prefix(8) { Engine.completeLesson(l.id, state: &s, catalog: big, clock: t.clock) }
        t.advance(days: 2)
        let plan = SessionComposer.compose(state: s, catalog: big, clock: t.clock, minutes: 15)
        XCTAssertFalse(plan.steps.contains { if case .lesson = $0 { true } else { false } }, "16 due concepts: catch up first")
        XCTAssertGreaterThan(plan.steps.count, 6)
    }

    /// End to end with a controlled clock: lesson → practice → spaced reviews → delayed check → Retained,
    /// persisting and reloading between days.
    func testLearningAConceptFromLessonToRetention() throws {
        let t = TestClock("2026-03-02T15:00:00Z")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString)")
        var s = StateStore(directory: dir).load().state
        let c = "m0-l0-c0"

        func runSession() throws {
            Engine.startSession(state: &s, catalog: catalog, clock: t.clock)
            while let session = Engine.resumableSession(state: s, clock: t.clock) {
                switch session.steps[session.index] {
                case .lesson(let id): Engine.completeLesson(id, state: &s, catalog: catalog, clock: t.clock)
                case .review(_, let item, let context): Fixture.answer(item, context: context, state: &s, catalog: catalog, clock: t.clock)
                case .practice(let item): Fixture.answer(item, context: .practice, state: &s, catalog: catalog, clock: t.clock)
                case .application(let item): Fixture.answer(item, context: .application, state: &s, catalog: catalog, clock: t.clock)
                }
                Engine.advanceSession(state: &s)
                t.advance(minutes: 1)
            }
            // close the app and open it again
            try StateStore(directory: dir).save(s)
            let reloaded = StateStore(directory: dir).load()
            XCTAssertEqual(reloaded.origin, .main)
            XCTAssertEqual(reloaded.state, s)
            s = reloaded.state
        }

        try runSession()   // day 0: lesson + practice
        XCTAssertEqual(Progress.status(of: c, state: s, clock: t.clock).state, .demonstrated)
        XCTAssertEqual(s.concepts[c]?.step, 0, "same-day practice does not advance the schedule")
        let recap = SessionComposer.recap(session: s.session!, state: s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(recap.answered, 4)
        XCTAssertEqual(recap.lessonId, "m0-l0")
        XCTAssertEqual(recap.dueTomorrow, 2)

        var contexts: [AttemptContext] = []
        for _ in 0..<12 where Progress.status(of: c, state: s, clock: t.clock).state != .retained {
            let due = s.concepts[c]!.dueDay!
            t.advance(days: Double(max(1, due.days(since: t.clock.today))))
            XCTAssertTrue(Scheduler.dueConcepts(state: s, catalog: catalog, clock: t.clock).contains(c))
            try runSession()
            contexts.append(contentsOf: s.attempts.filter { $0.primaryConcept == c && t.clock.day(of: $0.date) == t.clock.today }.map(\.context))
        }
        let status = Progress.status(of: c, state: s, clock: t.clock)
        XCTAssertEqual(status.state, .retained)
        XCTAssertTrue(contexts.contains(.delayedCheck), "retention was shown on an assessment item that practice never used")
        XCTAssertGreaterThanOrEqual(s.concepts[c]!.step, 3)
        // No two consecutive retrievals of the concept used the same item.
        let seq = s.attempts.filter { $0.primaryConcept == c }.map(\.itemId)
        XCTAssertFalse(zip(seq, seq.dropFirst()).contains { $0 == $1 })
    }

    func testUnfinishedSessionResumesSameDayButNotTheNext() {
        let t = TestClock()
        var s = AppState()
        Engine.startSession(state: &s, catalog: catalog, clock: t.clock)
        Engine.advanceSession(state: &s)
        XCTAssertEqual(Engine.resumableSession(state: s, clock: t.clock)?.index, 1)
        t.advance(days: 1)
        XCTAssertNil(Engine.resumableSession(state: s, clock: t.clock))
    }
}

final class AssessmentTests: XCTestCase {
    let catalog = Fixture.catalog()

    private func studied(_ t: TestClock, lessons: [String]) -> AppState {
        var s = AppState()
        for l in lessons {
            Engine.completeLesson(l, state: &s, catalog: catalog, clock: t.clock)
            for id in SessionComposer.practiceItems(for: catalog.lessonById[l]!, catalog: catalog, history: History(state: s), count: 6) {
                Fixture.answer(id, state: &s, catalog: catalog, clock: t.clock)
            }
        }
        return s
    }

    func testQuizUsesOnlyUnseenAssessmentItemsFromCompletedLessons() {
        let t = TestClock()
        let s = studied(t, lessons: ["m0-l0", "m0-l1"])
        let plan = AssessmentComposer.quiz(module: "m0", state: s, catalog: catalog)
        XCTAssertEqual(plan.itemIds.count, 4)
        let seen = Set(s.attempts.map(\.itemId))
        for id in plan.itemIds {
            let m = catalog.itemMetaById[id]!
            XCTAssertEqual(m.pool, .assess)
            XCTAssertFalse(seen.contains(id), "assessment items are never shown during practice")
            XCTAssertTrue(["m0-l0", "m0-l1"].contains(m.lessonId!))
        }
        XCTAssertTrue(AssessmentComposer.quiz(module: "m1", state: s, catalog: catalog).itemIds.isEmpty)
    }

    func testRetakingAQuizPrefersItemsNotUsedBefore() {
        let t = TestClock()
        var s = studied(t, lessons: ["m0-l0"])
        let first = AssessmentComposer.quiz(module: "m0", state: s, catalog: catalog)
        for id in first.itemIds { Fixture.answer(id, context: .quiz, state: &s, catalog: catalog, clock: t.clock) }
        let second = AssessmentComposer.quiz(module: "m0", state: s, catalog: catalog)
        XCTAssertTrue(Set(first.itemIds).isDisjoint(with: second.itemIds))
    }

    func testCumulativeSpansModulesAndIncludesMultiConceptItems() {
        let t = TestClock()
        let s = studied(t, lessons: ["m0-l0", "m0-l1", "m1-l0"])
        let plan = AssessmentComposer.cumulative(state: s, catalog: catalog)
        XCTAssertEqual(AssessmentComposer.modulesSpanned(by: plan, catalog: catalog), ["m0", "m1"])
        XCTAssertTrue(plan.itemIds.contains("cum-1"))
        XCTAssertTrue(plan.itemIds.allSatisfy { catalog.itemMetaById[$0]!.pool == .assess })
        let onlyOne = studied(t, lessons: ["m0-l0"])
        XCTAssertFalse(AssessmentComposer.cumulative(state: onlyOne, catalog: catalog).itemIds.contains("cum-1"),
                       "a multi-concept item waits until all its concepts are introduced")
    }

    func testDelayedCheckOnlyCoversConceptsLeftAloneForAWeek() {
        let t = TestClock()
        var s = studied(t, lessons: ["m0-l0"])
        XCTAssertTrue(AssessmentComposer.delayedCheck(state: s, catalog: catalog, clock: t.clock).itemIds.isEmpty)
        t.advance(days: 5)
        Fixture.answer("m0-l0-c1-p1", state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 3)
        let plan = AssessmentComposer.delayedCheck(state: s, catalog: catalog, clock: t.clock)
        XCTAssertEqual(plan.itemIds.map { catalog.itemMetaById[$0]!.primaryConcept }, ["m0-l0-c0"])
    }

    func testFinalUsesOnlyTheFinalPool() {
        let plan = AssessmentComposer.final(catalog: catalog)
        XCTAssertEqual(plan.itemIds, ["final-0", "final-1"])
        let practiceOrQuiz = AssessmentComposer.quiz(module: "m0", state: studied(TestClock(), lessons: ["m0-l0"]), catalog: catalog).itemIds
        XCTAssertTrue(Set(plan.itemIds).isDisjoint(with: practiceOrQuiz))
    }

    func testSummaryKeepsAutoAndSelfScoresApart() {
        let t = TestClock()
        var s = studied(t, lessons: ["m0-l0"])
        let plan = AssessmentComposer.Plan(kind: .quiz, moduleId: "m0", itemIds: ["m0-l0-c0-a1", "m0-l0-c0-a2", "m0-l0-c1-a1", "m0-l0-c1-a2"])
        let attempts = [
            Fixture.answer("m0-l0-c0-a1", partial: true, context: .quiz, state: &s, catalog: catalog, clock: t.clock),
            Fixture.answer("m0-l0-c0-a2", context: .quiz, state: &s, catalog: catalog, clock: t.clock),
            Fixture.answer("m0-l0-c1-a1", context: .quiz, state: &s, catalog: catalog, clock: t.clock),
            Fixture.answer("m0-l0-c1-a2", correct: false, context: .quiz, state: &s, catalog: catalog, clock: t.clock),
        ]
        let r = AssessmentComposer.summarise(plan: plan, attempts: attempts, rubricSizes: ["m0-l0-c0-a1": 2, "m0-l0-c1-a1": 2], date: t.date)
        XCTAssertEqual([r.autoCorrect, r.autoTotal], [1, 2])
        XCTAssertEqual(r.selfPoints, 3)
        XCTAssertEqual(r.selfTotal, 4)
    }
}
