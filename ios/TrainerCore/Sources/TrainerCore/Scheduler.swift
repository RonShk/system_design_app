import Foundation

/// Spaced-review scheduling per concept. See docs/LEARNING_DESIGN.md: the ladder and the
/// step rules are pragmatic design choices, not claimed to be optimal.
public enum Scheduler {
    /// Days until the next review at each step.
    public static let ladder = [1, 3, 7, 14, 30, 60, 120]
    public static var maxStep: Int { ladder.count - 1 }

    public static func interval(step: Int) -> Int { ladder[min(max(step, 0), maxStep)] }

    /// Called when the lesson that teaches a concept is completed.
    public static func introduce(_ record: inout ConceptRecord, clock: Clock) {
        guard record.introducedAt == nil else { return }
        record.introducedAt = clock.now()
        if record.dueDay == nil {
            record.step = 0
            record.dueDay = clock.today.adding(days: interval(step: 0))
        }
    }

    public enum Effect: Equatable, Sendable {
        case advanced       // moved up the ladder
        case held           // same step, rescheduled
        case lapsed         // moved down, due tomorrow
        case tooEarly       // not enough time had passed to count
    }

    /// Updates a concept's schedule after an answer. Returns what happened.
    @discardableResult
    public static func record(_ attempt: Attempt, on record: inout ConceptRecord, clock: Clock) -> Effect {
        let today = clock.today
        let anchor = record.lastReviewedAt ?? record.introducedAt
        let elapsed = anchor.map { today.days(since: clock.day(of: $0)) }
        let current = interval(step: record.step)
        record.lastItemId = attempt.itemId

        if attempt.isFailure {
            let highConfidence = attempt.confidence == .high
            record.step = highConfidence ? 0 : max(0, record.step - 2)
            record.dueDay = today.adding(days: 1)
            record.lastReviewedAt = attempt.date
            record.lapses += 1
            if highConfidence { record.misconception = true }
            return .lapsed
        }

        // A success before half the interval has passed is too easy to count as spaced
        // retrieval; keep the schedule as it is. (First ever answer has no anchor: it counts.)
        if let elapsed, record.dueDay != nil, elapsed * 2 < current {
            return .tooEarly
        }

        record.lastReviewedAt = attempt.date
        if attempt.isIndependentSuccess {
            record.misconception = false
            if record.dueDay == nil {
                // first evidence for a concept that was never formally introduced
                record.step = 0
            } else {
                // Reviewed so late that the gap already covers the next interval: skip a step.
                let next = interval(step: record.step + 1)
                let jump = (elapsed ?? 0) >= next && record.step + 1 < maxStep ? 2 : 1
                record.step = min(maxStep, record.step + jump)
            }
            record.dueDay = today.adding(days: interval(step: record.step))
            return .advanced
        }

        // Correct with a hint, or partially correct.
        if attempt.outcome == .partial { record.step = max(0, record.step - 1) }
        record.dueDay = today.adding(days: interval(step: record.step))
        return .held
    }

    /// Concepts due on or before today, most overdue first; ties in curriculum order.
    public static func dueConcepts(state: AppState, catalog: Catalog, clock: Clock) -> [String] {
        let today = clock.today
        let order = Dictionary(uniqueKeysWithValues: catalog.orderedConcepts.enumerated().map { ($1.id, $0) })
        return state.concepts
            .filter { id, r in catalog.concepts[id] != nil && (r.dueDay.map { $0 <= today } ?? false) }
            .sorted { a, b in
                let da = today.days(since: a.value.dueDay!), db = today.days(since: b.value.dueDay!)
                if da != db { return da > db }
                return (order[a.key] ?? 0) < (order[b.key] ?? 0)
            }
            .map(\.key)
    }

    /// Number of concepts that become due on each of the next `days` days (index 0 = today, including overdue).
    public static func forecast(state: AppState, clock: Clock, days: Int) -> [Int] {
        let today = clock.today
        var out = Array(repeating: 0, count: days)
        for r in state.concepts.values {
            guard let d = r.dueDay else { continue }
            let offset = max(0, d.days(since: today))
            if offset < days { out[offset] += 1 }
        }
        return out
    }
}
