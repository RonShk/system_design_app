import Foundation

/// The mutations the app performs on its state. Views call these; nothing else writes
/// attempts or schedules, so the rules live in one place.
public enum Engine {
    /// Marks a lesson complete: its concepts become Introduced and are scheduled for review.
    public static func completeLesson(_ lessonId: String, state: inout AppState, catalog: Catalog, clock: Clock) {
        guard let lesson = catalog.lessonById[lessonId] else { return }
        if state.lessonsCompleted[lessonId] == nil { state.lessonsCompleted[lessonId] = clock.now() }
        for c in lesson.concepts {
            var r = state.concepts[c] ?? ConceptRecord()
            Scheduler.introduce(&r, clock: clock)
            state.concepts[c] = r
        }
    }

    /// Records an answered (or revealed) item and updates the primary concept's schedule.
    @discardableResult
    public static func record(item: Item, result: CheckResult?, hintsUsed: Int, revealed: Bool,
                              confidence: Confidence?, context: AttemptContext,
                              state: inout AppState, clock: Clock) -> Attempt {
        let assistance: Assistance = revealed ? .revealed : (hintsUsed > 0 ? .hinted : .independent)
        let attempt = Attempt(
            itemId: item.id, conceptIds: item.concepts, date: clock.now(),
            outcome: revealed ? .incorrect : (result?.outcome ?? .incorrect),
            assistance: assistance,
            grading: result?.grading ?? (item.format.isAutoChecked ? .auto : .selfAssessed),
            confidence: confidence, context: context, format: item.format,
            score: revealed ? 0 : (result?.score ?? 0), hintsUsed: hintsUsed)
        state.attempts.append(attempt)
        if let primary = item.concepts.first {
            var r = state.concepts[primary] ?? ConceptRecord()
            Scheduler.record(attempt, on: &r, clock: clock)
            state.concepts[primary] = r
        }
        if state.session != nil, context == .practice || context == .review || context == .application || context == .delayedCheck {
            state.session?.attemptIds.append(attempt.id)
        }
        return attempt
    }

    public static func startSession(state: inout AppState, catalog: Catalog, clock: Clock, minutes: Int? = nil) {
        state.session = SessionComposer.compose(state: state, catalog: catalog, clock: clock, minutes: minutes ?? state.prefs.sessionMinutes)
    }

    /// A session left unfinished on an earlier day is discarded: its reviews are recomputed from what is due now.
    public static func resumableSession(state: AppState, clock: Clock) -> SessionProgress? {
        guard let s = state.session, !s.isFinished, s.day == clock.today else { return nil }
        return s
    }

    public static func advanceSession(state: inout AppState) {
        guard var s = state.session else { return }
        s.index = min(s.index + 1, s.steps.count)
        state.session = s
    }

    /// Days on which at least one item was answered or a lesson completed, most recent first.
    public static func studyDays(state: AppState, clock: Clock) -> [LocalDay] {
        var days = Set(state.attempts.map { clock.day(of: $0.date) })
        for d in state.lessonsCompleted.values { days.insert(clock.day(of: d)) }
        return days.sorted(by: >)
    }
}
