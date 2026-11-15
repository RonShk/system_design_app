import Foundation

/// Builds assessments. Assessments draw from the assessment pool, which practice never
/// shows, so a learner has not just seen the solution to what they are being asked.
public enum AssessmentComposer {
    public struct Plan: Equatable, Sendable {
        public var kind: AssessmentKind
        public var moduleId: String?
        public var itemIds: [String]
    }

    private static func introducedConcepts(_ concepts: [Concept], state: AppState) -> [Concept] {
        concepts.filter { state.lessonsCompleted[$0.lessonId] != nil }
    }

    /// Least recently assessed first (never assessed first of all), stable by curriculum order.
    private static func byAssessmentAge(_ concepts: [Concept], history: History) -> [Concept] {
        concepts.enumerated().sorted { a, b in
            let da = history.lastAssessed[a.element.id] ?? .distantPast
            let db = history.lastAssessed[b.element.id] ?? .distantPast
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
    }

    /// Topic quiz over the lessons completed in one module.
    public static func quiz(module: String, state: AppState, catalog: Catalog, count: Int = 10, seed: UInt64 = 0) -> Plan {
        let history = History(state: state)
        let concepts = byAssessmentAge(introducedConcepts(catalog.concepts(in: module), state: state), history: history)
        var ids: [String] = []
        for c in concepts where ids.count < count {
            if let it = ItemSelector.pick(concept: c.id, pools: [.assess], catalog: catalog, history: history, exclude: Set(ids)) {
                ids.append(it.id)
            }
        }
        var rng = SeededGenerator(seed: seed)
        return Plan(kind: .quiz, moduleId: module, itemIds: ids.shuffled(using: &rng))
    }

    /// Concepts last retrieved at least a week ago, tested with items that differ from the last one used.
    public static func delayedCheck(state: AppState, catalog: Catalog, clock: Clock, count: Int = 10, seed: UInt64 = 0) -> Plan {
        let history = History(state: state)
        let today = clock.today
        let eligible = catalog.orderedConcepts.filter { c in
            guard let last = history.lastAttempt[c.id] else { return false }
            return today.days(since: clock.day(of: last)) >= Mastery.retentionGapDays
        }.sorted { (history.lastAttempt[$0.id] ?? .distantPast) < (history.lastAttempt[$1.id] ?? .distantPast) }
        var ids: [String] = []
        for c in eligible where ids.count < count {
            let pick = ItemSelector.pick(concept: c.id, pools: [.assess], catalog: catalog, history: history, exclude: Set(ids))
                ?? ItemSelector.pick(concept: c.id, pools: [.practice], catalog: catalog, history: history, exclude: Set(ids))
            if let pick { ids.append(pick.id) }
        }
        var rng = SeededGenerator(seed: seed)
        return Plan(kind: .delayedCheck, moduleId: nil, itemIds: ids.shuffled(using: &rng))
    }

    /// Mixed quiz across every module studied so far, plus multi-concept items whose concepts are all introduced.
    public static func cumulative(state: AppState, catalog: Catalog, count: Int = 12, seed: UInt64 = 0) -> Plan {
        let history = History(state: state)
        var ids: [String] = []
        let introduced = Set(introducedConcepts(catalog.orderedConcepts, state: state).map(\.id))

        let standalone = catalog.itemMetas
            .filter { $0.pool == .assess && $0.lessonId == nil && $0.caseId == nil && $0.concepts.allSatisfy(introduced.contains) }
            .sorted { (history.lastSeen[$0.id] ?? .distantPast, $0.id) < (history.lastSeen[$1.id] ?? .distantPast, $1.id) }
        ids.append(contentsOf: standalone.prefix(max(1, count / 4)).map(\.id))

        // Round-robin over modules so the quiz spans them.
        var queues = catalog.modules.map { byAssessmentAge(introducedConcepts(catalog.concepts(in: $0.id), state: state), history: history) }
        while ids.count < count && queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where ids.count < count && !queues[i].isEmpty {
                let c = queues[i].removeFirst()
                if let it = ItemSelector.pick(concept: c.id, pools: [.assess], catalog: catalog, history: history, exclude: Set(ids)) {
                    ids.append(it.id)
                }
            }
        }
        var rng = SeededGenerator(seed: seed)
        return Plan(kind: .cumulative, moduleId: nil, itemIds: ids.shuffled(using: &rng))
    }

    /// The final assessment: every item in the final pool, easier first.
    public static func final(catalog: Catalog) -> Plan {
        let items = catalog.itemMetas.filter { $0.pool == .final }.sorted { ($0.difficulty, $0.id) < ($1.difficulty, $1.id) }
        return Plan(kind: .final, moduleId: nil, itemIds: items.map(\.id))
    }

    public static func modulesSpanned(by plan: Plan, catalog: Catalog) -> Set<String> {
        Set(plan.itemIds.flatMap { catalog.itemMetaById[$0]?.concepts ?? [] }.compactMap { catalog.concepts[$0]?.moduleId })
    }

    /// Turns graded answers into a stored summary, keeping automatic and self-assessed scores apart.
    public static func summarise(plan: Plan, attempts: [Attempt], rubricSizes: [String: Int], date: Date) -> AssessmentResult {
        let auto = attempts.filter { $0.grading == .auto }
        let own = attempts.filter { $0.grading == .selfAssessed }
        return AssessmentResult(
            kind: plan.kind, moduleId: plan.moduleId, date: date, itemIds: plan.itemIds,
            autoCorrect: auto.filter { $0.outcome == .correct }.count, autoTotal: auto.count,
            selfPoints: own.reduce(0) { $0 + $1.score * Double(rubricSizes[$1.itemId] ?? 1) },
            selfTotal: own.reduce(0) { $0 + (rubricSizes[$1.itemId] ?? 1) })
    }
}
