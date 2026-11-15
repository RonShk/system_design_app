import XCTest
@testable import TrainerCore

final class PersistenceTests: XCTestCase {
    let catalog = Fixture.catalog()

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
    }

    /// A state with every kind of stored data in it.
    private func richState(_ t: TestClock) -> AppState {
        var s = AppState()
        Engine.completeLesson("m0-l0", state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("m0-l0-c0-p1", confidence: .high, state: &s, catalog: catalog, clock: t.clock)
        Fixture.answer("m0-l0-c0-p2", hints: 1, state: &s, catalog: catalog, clock: t.clock)
        t.advance(days: 1)
        Fixture.answer("m0-l0-c1-p3", correct: false, confidence: .low, context: .review, state: &s, catalog: catalog, clock: t.clock)
        s.caseResults.append(CaseResult(caseId: "case-x", date: t.date, mode: .timed, rubricMet: 4, rubricTotal: 6, durationSec: 1800))
        s.assessments.append(AssessmentResult(kind: .quiz, moduleId: "m0", date: t.date, itemIds: ["m0-l0-c0-a1"], autoCorrect: 0, autoTotal: 0, selfPoints: 1.5, selfTotal: 2))
        s.labsDone["lab-x"] = t.date
        s.prefs.sessionMinutes = 30
        s.prefs.reminderHour = 7
        s.prefs.reminderMinute = 45
        s.prefs.appearance = .dark
        Engine.startSession(state: &s, catalog: catalog, clock: t.clock)
        return s
    }

    func testFreshInstallStartsEmpty() {
        let r = StateStore(directory: tempDir()).load()
        XCTAssertEqual(r.origin, .fresh)
        XCTAssertEqual(r.state, AppState())
        XCTAssertEqual(r.state.prefs.reminderHour, 15, "reminder defaults to 3 pm")
        XCTAssertTrue(r.state.prefs.remindersEnabled)
    }

    func testStateSurvivesRestart() throws {
        let dir = tempDir(), t = TestClock()
        let s = richState(t)
        try StateStore(directory: dir).save(s)
        let r = StateStore(directory: dir).load()
        XCTAssertEqual(r.origin, .main)
        XCTAssertEqual(r.state, s)
    }

    func testCorruptMainFileFallsBackToPreviousCopy() throws {
        let dir = tempDir(), t = TestClock()
        var s = richState(t)
        let store = StateStore(directory: dir)
        try store.save(s)
        let firstSave = s
        s.prefs.sessionMinutes = 10
        try store.save(s)                       // previous copy now holds firstSave
        try Data("{ truncated".utf8).write(to: dir.appendingPathComponent("state.json"))
        let r = StateStore(directory: dir).load()
        XCTAssertEqual(r.origin, .backup)
        XCTAssertEqual(r.state, firstSave)
    }

    func testUnreadableDataIsSetAsideNotDeleted() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
        let r = StateStore(directory: dir).load()
        XCTAssertEqual(r.origin, .corruptSetAside)
        XCTAssertEqual(r.state, AppState())
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        XCTAssertEqual(kept.count, 1)
    }

    func testACorruptMainFileIsNeverCopiedOverAGoodBackup() throws {
        let dir = tempDir(), t = TestClock()
        let good = richState(t)
        try StateStore(directory: dir).save(good)
        try StateStore(directory: dir).save(good)   // main and backup both good
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("state.json"))
        let store = StateStore(directory: dir)
        var s = store.load().state                   // from backup
        s.prefs.sessionMinutes = 20
        try store.save(s)
        let backup = try Migrations.migrate(Data(contentsOf: dir.appendingPathComponent("state.bak.json")))
        XCTAssertEqual(backup, good)
    }

    // Migrations

    func testOldDataMissingNewerFieldsLoadsWithDefaults() throws {
        // What a much older build might have written: no prefs, no session, sparse records.
        let old = """
        {"schemaVersion":1,
         "attempts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","itemId":"m0-l0-c0-p1","conceptIds":["m0-l0-c0"],"date":1772442000000,
                      "outcome":"correct","assistance":"independent","grading":"auto","context":"practice","format":"mcq","score":1,"hintsUsed":0}],
         "concepts":{"m0-l0-c0":{"step":2}},
         "lessonsCompleted":{"m0-l0":1772442000000}}
        """
        let s = try Migrations.migrate(Data(old.utf8))
        XCTAssertEqual(s.attempts.count, 1)
        XCTAssertEqual(s.concepts["m0-l0-c0"]?.step, 2)
        XCTAssertEqual(s.concepts["m0-l0-c0"]?.lapses, 0)
        XCTAssertEqual(s.prefs, Preferences())
        XCTAssertNil(s.session)
    }

    func testMigrationStepsRunInOrderAndKeepAttempts() throws {
        // Simulate a future schema: v1 → v2 renames a field, v2 → v3 adds a derived one.
        let steps: [Int: Migrations.Step] = [
            1: { obj in
                var prefs = obj["prefs"] as? [String: Any] ?? [:]
                if let m = prefs["dailyMinutes"] { prefs["sessionMinutes"] = m; prefs.removeValue(forKey: "dailyMinutes") }
                obj["prefs"] = prefs
            },
            2: { obj in obj["labsDone"] = ["lab-migrated": 1772442000000] },
        ]
        let v1 = """
        {"schemaVersion":1,"prefs":{"dailyMinutes":20},
         "attempts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","itemId":"x","conceptIds":["c"],"date":1772442000000,
                      "outcome":"incorrect","assistance":"hinted","grading":"selfAssessed","context":"review","format":"free","score":0.5,"hintsUsed":1}]}
        """
        let s = try Migrations.migrate(Data(v1.utf8), steps: steps, current: 3)
        XCTAssertEqual(s.schemaVersion, 3)
        XCTAssertEqual(s.prefs.sessionMinutes, 20)
        XCTAssertNotNil(s.labsDone["lab-migrated"])
        XCTAssertEqual(s.attempts.first?.itemId, "x")
        // Starting from v2 only runs the second step.
        let v2 = #"{"schemaVersion":2,"prefs":{"sessionMinutes":25}}"#
        XCTAssertEqual(try Migrations.migrate(Data(v2.utf8), steps: steps, current: 3).prefs.sessionMinutes, 25)
    }

    func testDataFromANewerAppIsRejectedNotMangled() {
        let newer = #"{"schemaVersion":99,"attempts":[]}"#
        XCTAssertThrowsError(try Migrations.migrate(Data(newer.utf8))) {
            XCTAssertEqual($0 as? Migrations.Failure, .newerThanApp(found: 99, supported: AppState.currentSchemaVersion))
        }
        XCTAssertThrowsError(try Migrations.migrate(Data(#"{"schemaVersion":1}"#.utf8), steps: [:], current: 2)) {
            XCTAssertEqual($0 as? Migrations.Failure, .missingStep(from: 1))
        }
        XCTAssertThrowsError(try Migrations.migrate(Data("[1,2]".utf8)))
    }

    func testProgressOnRemovedContentIsKept() throws {
        let t = TestClock()
        var s = richState(t)
        s.attempts.append(Attempt(itemId: "deleted-item", conceptIds: ["deleted-concept"], date: t.date, outcome: .correct,
                                  assistance: .independent, grading: .auto, context: .practice, format: .mcq, score: 1))
        s.concepts["deleted-concept"] = ConceptRecord()
        s.concepts["deleted-concept"]?.dueDay = t.clock.today
        s.lessonsCompleted["deleted-lesson"] = t.date
        let dir = tempDir()
        try StateStore(directory: dir).save(s)
        let loaded = StateStore(directory: dir).load().state
        XCTAssertEqual(loaded, s)
        // Unknown ids are ignored by composition instead of crashing it.
        XCTAssertFalse(Scheduler.dueConcepts(state: loaded, catalog: catalog, clock: t.clock).contains("deleted-concept"))
        _ = SessionComposer.compose(state: loaded, catalog: catalog, clock: t.clock, minutes: 15)
        _ = Progress.allStatuses(state: loaded, catalog: catalog, clock: t.clock)
    }

    // Export / import

    func testExportThenImportRestoresEverythingExceptTheOpenSession() throws {
        let t = TestClock()
        let s = richState(t)
        let data = try Backup.export(s, appVersion: "1.0", clock: t.clock)
        let restored = try Backup.importData(data)
        var expected = s
        expected.session = nil
        XCTAssertEqual(restored, expected)
        // and it survives being stored after a wipe
        let dir = tempDir()
        try StateStore(directory: dir).save(restored)
        XCTAssertEqual(StateStore(directory: dir).load().state, expected)
    }

    func testImportRejectsMalformedFiles() throws {
        XCTAssertThrowsError(try Backup.importData(Data("hello".utf8))) { XCTAssertEqual($0 as? Backup.Failure, .notJSON) }
        XCTAssertThrowsError(try Backup.importData(Data("[]".utf8))) { XCTAssertEqual($0 as? Backup.Failure, .notJSON) }
        XCTAssertThrowsError(try Backup.importData(Data(#"{"format":"something-else","state":{}}"#.utf8))) { XCTAssertEqual($0 as? Backup.Failure, .wrongFormat) }
        XCTAssertThrowsError(try Backup.importData(Data(#"{"format":"system-design-trainer-backup","formatVersion":7,"state":{}}"#.utf8))) {
            XCTAssertEqual($0 as? Backup.Failure, .newerFormat(7))
        }
        XCTAssertThrowsError(try Backup.importData(Data(#"{"format":"system-design-trainer-backup","formatVersion":1}"#.utf8))) {
            XCTAssertEqual($0 as? Backup.Failure, .missingState)
        }
        func envelope(_ state: String) -> Data { Data(#"{"format":"system-design-trainer-backup","formatVersion":1,"state":\#(state)}"#.utf8) }
        let cases = [
            #"{"attempts":"nope"}"#,
            #"{"attempts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","itemId":"x","conceptIds":["c"],"date":1,"outcome":"brilliant","assistance":"independent","grading":"auto","context":"practice","format":"mcq","score":1,"hintsUsed":0}]}"#,
            #"{"attempts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","itemId":"x","conceptIds":["c"],"date":1,"outcome":"correct","assistance":"independent","grading":"auto","context":"practice","format":"mcq","score":7,"hintsUsed":0}]}"#,
            #"{"concepts":{"c":{"step":40}}}"#,
            #"{"concepts":{"c":{"dueDay":"tomorrow"}}}"#,
            #"{"prefs":{"reminderHour":31}}"#,
            #"{"schemaVersion":99}"#,
        ]
        for c in cases {
            XCTAssertThrowsError(try Backup.importData(envelope(c)), c) { error in
                guard case .invalid = error as? Backup.Failure else { return XCTFail("expected .invalid for \(c), got \(error)") }
            }
        }
        XCTAssertNoThrow(try Backup.importData(envelope("{}")), "an empty but well-formed state is a valid backup")
    }
}

final class ReminderTests: XCTestCase {
    func testDefaultIsDailyAtThreePM() {
        let plan = ReminderPlan.plan(prefs: Preferences(), dueCount: 0, nextLessonTitle: nil)
        XCTAssertEqual(plan?.hour, 15)
        XCTAssertEqual(plan?.minute, 0)
        XCTAssertFalse(plan!.body.isEmpty)
    }

    func testDisabledMeansNothingIsScheduled() {
        var p = Preferences()
        p.remindersEnabled = false
        XCTAssertNil(ReminderPlan.plan(prefs: p, dueCount: 5, nextLessonTitle: "X"))
    }

    func testTimeIsClampedAndBodyDescribesWhatIsWaiting() {
        var p = Preferences()
        p.reminderHour = 40; p.reminderMinute = -3
        let plan = ReminderPlan.plan(prefs: p, dueCount: 3, nextLessonTitle: "Quorums")!
        XCTAssertEqual([plan.hour, plan.minute], [23, 0])
        XCTAssertEqual(plan.body, "3 concepts due for review · next lesson: Quorums")
        XCTAssertEqual(ReminderPlan.plan(prefs: Preferences(), dueCount: 1, nextLessonTitle: nil)?.body, "1 concept due for review")
    }

    func testOneFixedIdentifierPreventsDuplicates() {
        XCTAssertEqual(ReminderPlan.identifier, "daily-study-reminder")
        XCTAssertNotEqual(ReminderPlan.identifier, ReminderPlan.testIdentifier)
    }
}

/// Checks on the real bundled content, as the app will load it.
final class BundledContentTests: XCTestCase {
    func testBundledContentLoadsAndIsInternallyConsistent() throws {
        let catalog = try Catalog(directory: Fixture.realContentDirectory())
        XCTAssertFalse(catalog.lessons.isEmpty)
        for l in catalog.lessons {
            XCTAssertNotNil(catalog.lessonBodies[l.id], "lesson body for \(l.id)")
            XCTAssertTrue(l.concepts.allSatisfy { catalog.concepts[$0]?.lessonId == l.id })
            for p in l.prereqs { XCTAssertLessThan(catalog.lessonIndex[p]!, catalog.lessonIndex[l.id]!, "\(p) must precede \(l.id)") }
        }
        XCTAssertEqual(Set(catalog.itemMetas.map(\.id)), Set(catalog.items.keys))
        for item in catalog.items.values {
            XCTAssertTrue(item.concepts.allSatisfy { catalog.concepts[$0] != nil }, item.id)
            XCTAssertFalse(item.sources.isEmpty, "\(item.id) has no source")
            switch item.format {
            case .mcq:
                XCTAssertTrue((0..<item.choices!.count).contains(Int(item.answer!)), item.id)
                XCTAssertEqual(Checker.check(.choice(Int(item.answer!)), item: item)?.outcome, .correct)
            case .multi:
                XCTAssertEqual(Checker.check(.choices(Set(item.answers!)), item: item)?.outcome, .correct)
            case .numeric:
                XCTAssertEqual(Checker.check(.number("\(item.answer!)"), item: item)?.outcome, .correct, item.id)
                XCTAssertEqual(Checker.check(.number("\(item.answer! * 3 + 1)"), item: item)?.outcome, .incorrect, item.id)
            case .order:
                XCTAssertGreaterThanOrEqual(item.steps!.count, 3)
            case .free:
                XCTAssertFalse(item.model!.isEmpty); XCTAssertGreaterThanOrEqual(item.rubric!.count, 2)
            }
            if item.pool == .practice { XCTAssertFalse(item.hints.isEmpty, item.id) }
        }
        // Every concept can be practised and assessed with different items.
        for c in catalog.concepts.values {
            let its = catalog.itemsByConcept[c.id] ?? []
            XCTAssertGreaterThanOrEqual(its.filter { $0.pool == .practice }.count, 2, c.id)
            XCTAssertGreaterThanOrEqual(its.filter { $0.pool == .assess }.count, 1, c.id)
        }
        for c in catalog.cases { XCTAssertEqual(catalog.caseBodies[c.id]?.stages.count, 8, c.id) }
        // A first session can be composed and every step resolves.
        let t = TestClock()
        let plan = SessionComposer.compose(state: AppState(), catalog: catalog, clock: t.clock, minutes: 15)
        XCTAssertFalse(plan.steps.isEmpty)
        for id in plan.steps.compactMap(\.itemId) { XCTAssertNotNil(catalog.items[id]) }
    }
}
