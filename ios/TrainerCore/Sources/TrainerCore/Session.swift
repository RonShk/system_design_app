import Foundation

public enum SessionStep: Codable, Hashable, Sendable {
    case review(concept: String, item: String, context: AttemptContext)
    case lesson(String)
    case practice(item: String)
    case application(item: String)

    public var itemId: String? {
        switch self {
        case .review(_, let item, _), .practice(let item), .application(let item): item
        case .lesson: nil
        }
    }
}

/// A daily session in progress; persisted so it can be resumed after the app is closed.
public struct SessionProgress: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var day: LocalDay
    public var minutes: Int
    public var steps: [SessionStep]
    public var index: Int = 0
    public var attemptIds: [UUID] = []
    public var isFinished: Bool { index >= steps.count }
}

public enum SessionComposer {
    /// Rough time per question, used only to fit a session into its time budget.
    public static func minutes(for format: ItemFormat) -> Double {
        switch format {
        case .mcq, .multi: 1.0
        case .numeric, .order: 1.5
        case .free: 2.5
        }
    }

    public static func nextLesson(state: AppState, catalog: Catalog) -> LessonMeta? {
        catalog.lessons.first { state.lessonsCompleted[$0.id] == nil }
    }

    /// Builds the plan: due reviews → new lesson → retrieval practice on it → one application problem.
    /// The recap is computed from the session's attempts when it ends.
    public static func compose(state: AppState, catalog: Catalog, clock: Clock, minutes: Int) -> SessionProgress {
        let history = History(state: state)
        var steps: [SessionStep] = []
        var used = Set<String>()

        // 1. Due reviews: about 40% of the time, or all of it when the backlog is large.
        let due = Scheduler.dueConcepts(state: state, catalog: catalog, clock: clock)
        let reviewBudget = Double(minutes) * 0.4
        let catchUp = Double(due.count) > reviewBudget / 1.5 * 3
        var spent = 0.0
        let limit = catchUp ? Double(minutes) : reviewBudget
        for concept in due {
            guard let pick = ItemSelector.reviewItem(concept: concept, state: state, catalog: catalog, history: history, clock: clock, exclude: used) else { continue }
            let cost = self.minutes(for: pick.item.format)
            if spent + cost > limit && !steps.isEmpty { break }
            steps.append(.review(concept: concept, item: pick.item.id, context: pick.context))
            used.insert(pick.item.id)
            spent += cost
        }

        // 2–3. New lesson and practice on it (skipped while catching up on a large backlog).
        var lessonConcepts = Set<String>()
        if !catchUp, let lesson = nextLesson(state: state, catalog: catalog) {
            steps.append(.lesson(lesson.id))
            lessonConcepts = Set(lesson.concepts)
            let want = minutes <= 10 ? 3 : (minutes >= 30 ? 6 : 4)
            for id in practiceItems(for: lesson, catalog: catalog, history: history, count: want, exclude: used) {
                steps.append(.practice(item: id))
                used.insert(id)
            }
        }

        // 4. One application problem on an earlier concept, so practice is interleaved.
        let applied: Set<ItemSkill> = [.design, .diagnose, .estimate, .predict, .compare]
        let earlier = catalog.orderedConcepts.filter {
            !lessonConcepts.contains($0.id) && (state.concepts[$0.id]?.introducedAt != nil)
        }
        let candidates = earlier.compactMap {
            ItemSelector.pick(concept: $0.id, pools: [.practice], catalog: catalog, history: history, exclude: used, skills: applied, minDifficulty: 2)
        }
        let application = candidates.min { a, b in
            let sa = history.lastSeen[a.id] ?? .distantPast, sb = history.lastSeen[b.id] ?? .distantPast
            if sa != sb { return sa < sb }
            let ca = history.lastAttempt[a.primaryConcept] ?? .distantPast, cb = history.lastAttempt[b.primaryConcept] ?? .distantPast
            if ca != cb { return ca < cb }
            return a.id < b.id
        }
        if let application { steps.append(.application(item: application.id)) }

        return SessionProgress(startedAt: clock.now(), day: clock.today, minutes: minutes, steps: steps)
    }

    /// Practice items for a lesson: at least one per concept, varied formats, easier first.
    public static func practiceItems(for lesson: LessonMeta, catalog: Catalog, history: History, count: Int, exclude: Set<String> = []) -> [String] {
        var chosen: [ItemMeta] = []
        var taken = exclude
        var round = 0
        while chosen.count < count && round < count {
            var added = false
            for concept in lesson.concepts where chosen.count < count {
                let usedFormats = Set(chosen.map(\.format))
                let pool = (catalog.itemsByConcept[concept] ?? []).filter { $0.pool == .practice && !taken.contains($0.id) }
                let next = pool.min { a, b in
                    let na = usedFormats.contains(a.format), nb = usedFormats.contains(b.format)
                    if na != nb { return !na }
                    let sa = history.lastSeen[a.id] ?? .distantPast, sb = history.lastSeen[b.id] ?? .distantPast
                    if sa != sb { return sa < sb }
                    if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
                    return a.id < b.id
                }
                if let next { chosen.append(next); taken.insert(next.id); added = true }
            }
            if !added { break }
            round += 1
        }
        return chosen.sorted { ($0.difficulty, $0.id) < ($1.difficulty, $1.id) }.map(\.id)
    }

    public struct Recap: Equatable, Sendable {
        public var answered = 0
        public var independentCorrect = 0
        public var hintedOrPartial = 0
        public var missed = 0
        public var conceptsToRevisit: [String] = []
        public var lessonId: String?
        public var dueTomorrow = 0
        public var nextLessonId: String?
    }

    public static func recap(session: SessionProgress, state: AppState, catalog: Catalog, clock: Clock) -> Recap {
        var r = Recap()
        let ids = Set(session.attemptIds)
        var revisit: [String] = []
        for a in state.attempts where ids.contains(a.id) {
            r.answered += 1
            if a.isIndependentSuccess { r.independentCorrect += 1 }
            else if a.isFailure { r.missed += 1; if !revisit.contains(a.primaryConcept) { revisit.append(a.primaryConcept) } }
            else { r.hintedOrPartial += 1 }
        }
        r.conceptsToRevisit = revisit
        for case .lesson(let id) in session.steps { r.lessonId = id }
        let tomorrow = clock.today.adding(days: 1)
        r.dueTomorrow = state.concepts.values.filter { ($0.dueDay.map { $0 <= tomorrow }) ?? false }.count
        r.nextLessonId = nextLesson(state: state, catalog: catalog)?.id
        return r
    }
}
