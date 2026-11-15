import Foundation
import Observation
import SwiftUI
import TrainerCore

/// Owns the catalog and the persisted state; every mutation goes through here so it is saved.
@MainActor
@Observable
final class AppModel {
    let catalog: Catalog
    private(set) var state: AppState
    private(set) var loadOrigin: StateStore.Origin
    private(set) var saveError: String?
    let clock: Clock
    let reminders = ReminderService()

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private var statusCache: [String: ConceptStatus]?

    init() {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment

        // Test hooks: an isolated state directory and a shifted clock, so UI tests can
        // start clean and "wait" days without waiting.
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SystemDesignTrainer", isDirectory: true)
        if let custom = env["SDT_STATE_DIR"] { dir = URL(fileURLWithPath: custom, isDirectory: true) }
        if args.contains("-resetState") { try? FileManager.default.removeItem(at: dir) }
        let offsetDays = Double(env["SDT_DAY_OFFSET"] ?? "") ?? 0
        clock = Clock(now: { Date().addingTimeInterval(offsetDays * 86_400) }, calendar: .current)

        do {
            catalog = try Catalog(directory: Bundle.main.resourceURL!)
        } catch {
            fatalError("Bundled content is missing or unreadable: \(error)")
        }
        store = StateStore(directory: dir)
        let loaded = store.load()
        state = loaded.state
        loadOrigin = loaded.origin
    }

    // MARK: Derived

    var statuses: [String: ConceptStatus] {
        if let statusCache { return statusCache }
        let s = Mastery.allStatuses(state: state, catalog: catalog, clock: clock)
        statusCache = s
        return s
    }
    func status(_ concept: String) -> ConceptStatus? { statuses[concept] }
    var dueConcepts: [String] { Scheduler.dueConcepts(state: state, catalog: catalog, clock: clock) }
    var nextLesson: LessonMeta? { SessionComposer.nextLesson(state: state, catalog: catalog) }
    var resumableSession: SessionProgress? { Engine.resumableSession(state: state, clock: clock) }
    func isCompleted(_ lesson: LessonMeta) -> Bool { state.lessonsCompleted[lesson.id] != nil }
    var studiedToday: Bool { Engine.studyDays(state: state, clock: clock).first == clock.today }

    // MARK: Mutations

    private func mutate(_ change: (inout AppState) -> Void) {
        var s = state
        change(&s)
        state = s
        statusCache = nil
        persist()
    }

    private func persist() {
        do { try store.save(state); saveError = nil }
        catch { saveError = "Progress could not be saved: \(error.localizedDescription)" }
    }

    func completeLesson(_ id: String) {
        mutate { Engine.completeLesson(id, state: &$0, catalog: catalog, clock: clock) }
        refreshReminder()
    }

    @discardableResult
    func record(item: Item, result: CheckResult?, hintsUsed: Int, revealed: Bool, confidence: Confidence?, context: AttemptContext) -> Attempt {
        var attempt: Attempt!
        mutate {
            attempt = Engine.record(item: item, result: result, hintsUsed: hintsUsed, revealed: revealed,
                                    confidence: confidence, context: context, state: &$0, clock: clock)
        }
        return attempt
    }

    func startSession(minutes: Int? = nil) {
        mutate { Engine.startSession(state: &$0, catalog: catalog, clock: clock, minutes: minutes) }
    }
    func advanceSession() { mutate { Engine.advanceSession(state: &$0) } }
    func addAssessment(_ r: AssessmentResult) { mutate { $0.assessments.append(r) } }
    func addCaseResult(_ r: CaseResult) { mutate { $0.caseResults.append(r) } }
    func setLabDone(_ id: String, done: Bool) { mutate { $0.labsDone[id] = done ? clock.now() : nil } }

    func updatePrefs(_ change: (inout Preferences) -> Void) {
        mutate { change(&$0.prefs) }
        refreshReminder()
    }

    // MARK: Backup

    func exportData() throws -> Data {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let data = try Backup.export(state, appVersion: v, clock: clock)
        mutate { $0.lastExportAt = clock.now() }
        return data
    }

    /// Replaces all progress with a validated backup. Throws without changing anything if the file is not valid.
    func importData(_ data: Data) throws {
        let imported = try Backup.importData(data)
        mutate { $0 = imported }
        refreshReminder()
    }

    func resetProgress() {
        mutate {
            let prefs = $0.prefs
            $0 = AppState()
            $0.prefs = prefs
        }
        refreshReminder()
    }

    // MARK: Reminders

    func refreshReminder() {
        let plan = ReminderPlan.plan(prefs: state.prefs, dueCount: dueTomorrowCount, nextLessonTitle: nextLesson?.title)
        Task { await reminders.apply(plan) }
    }

    /// What will be waiting at the next reminder: everything due by tomorrow.
    private var dueTomorrowCount: Int {
        let tomorrow = clock.today.adding(days: 1)
        return state.concepts.filter { catalog.concepts[$0.key] != nil && ($0.value.dueDay.map { $0 <= tomorrow } ?? false) }.count
    }
}
