import Foundation

/// Where a learner stands on one concept, derived from the attempt history.
public enum ConceptState: Int, Comparable, CaseIterable, Sendable {
    case notStarted, introduced, practiced, demonstrated, retained
    public static func < (a: ConceptState, b: ConceptState) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .notStarted: "Not started"
        case .introduced: "Introduced"
        case .practiced: "Practiced"
        case .demonstrated: "Demonstrated"
        case .retained: "Retained"
        }
    }
}

public struct ConceptStatus: Equatable, Sendable {
    /// Highest level of evidence reached so far.
    public var state: ConceptState
    /// True when recent evidence says the concept has slipped; shown instead of `state`.
    public var needsReview: Bool
    public var reviewReason: ReviewReason?
    public var independentSuccesses: Int
    public var autoSuccesses: Int
    public var selfSuccesses: Int
    public var attempts: Int
    public var lastAttempt: Date?
}

public enum ReviewReason: String, Sendable {
    case lastAnswerWrong = "Last answer was wrong or revealed"
    case overdue = "Overdue for review"
    case misconception = "Confident answer was wrong"
}

public enum Progress {
    /// Days that must separate two retrievals before a success counts as retention.
    public static let retentionGapDays = 7

    public static func status(of conceptId: String, state: AppState, clock: Clock) -> ConceptStatus {
        status(attempts: state.attempts(for: conceptId).sorted { $0.date < $1.date },
               record: state.concepts[conceptId], clock: clock)
    }

    /// `attempts` must be this concept's attempts in chronological order.
    public static func status(attempts: [Attempt], record: ConceptRecord?, clock: Clock) -> ConceptStatus {
        let wins = attempts.filter(\.isIndependentSuccess)
        let distinctItems = Set(wins.map(\.itemId))
        let hasNonRecognition = wins.contains { !$0.format.isRecognition }
        let demonstrated = distinctItems.count >= 2 && hasNonRecognition

        // Retained: an independent success at least `retentionGapDays` after the previous
        // retrieval of this concept, on a different item from that previous retrieval.
        var delayedSuccess = false
        for (i, a) in attempts.enumerated() where i > 0 && a.isIndependentSuccess {
            let prev = attempts[i - 1]
            let gap = clock.day(of: a.date).days(since: clock.day(of: prev.date))
            if gap >= retentionGapDays && prev.itemId != a.itemId { delayedSuccess = true; break }
        }

        var level: ConceptState = .notStarted
        if record?.introducedAt != nil { level = .introduced }
        if !attempts.isEmpty { level = .practiced }
        if demonstrated { level = .demonstrated }
        if demonstrated && delayedSuccess { level = .retained }

        var reason: ReviewReason?
        if record?.misconception == true {
            reason = .misconception
        } else if let last = attempts.last, last.isFailure {
            reason = .lastAnswerWrong
        } else if let r = record, let due = r.dueDay {
            // Overdue by more than the concept's own interval.
            if clock.today.days(since: due) > Scheduler.interval(step: r.step) { reason = .overdue }
        }

        return ConceptStatus(
            state: level, needsReview: reason != nil, reviewReason: reason,
            independentSuccesses: wins.count,
            autoSuccesses: wins.filter { $0.grading == .auto }.count,
            selfSuccesses: wins.filter { $0.grading == .selfAssessed }.count,
            attempts: attempts.count, lastAttempt: attempts.last?.date)
    }

    public struct Summary: Equatable, Sendable {
        public var total = 0
        public var counts: [ConceptState: Int] = [:]
        public var needsReview = 0
        /// Coverage: concepts at least introduced.
        public var covered: Int { total - (counts[.notStarted] ?? 0) }
        public var demonstrated: Int { (counts[.demonstrated] ?? 0) + (counts[.retained] ?? 0) }
        public var retained: Int { counts[.retained] ?? 0 }
    }

    /// Status of every concept in one pass over the attempt log.
    public static func allStatuses(state: AppState, catalog: Catalog, clock: Clock) -> [String: ConceptStatus] {
        var byConcept: [String: [Attempt]] = [:]
        for a in state.attempts.sorted(by: { $0.date < $1.date }) {
            for c in a.conceptIds { byConcept[c, default: []].append(a) }
        }
        var out: [String: ConceptStatus] = [:]
        for id in catalog.concepts.keys {
            out[id] = status(attempts: byConcept[id] ?? [], record: state.concepts[id], clock: clock)
        }
        return out
    }

    public static func summary(of concepts: [Concept], statuses: [String: ConceptStatus]) -> Summary {
        var s = Summary()
        for c in concepts {
            guard let st = statuses[c.id] else { continue }
            s.total += 1
            s.counts[st.state, default: 0] += 1
            if st.needsReview { s.needsReview += 1 }
        }
        return s
    }

    /// Concepts worth extra attention, weakest first: flagged for review, then low success rate.
    public static func weakConcepts(statuses: [String: ConceptStatus], state: AppState, catalog: Catalog, limit: Int) -> [String] {
        var scored: [(id: String, score: Double)] = []
        for c in catalog.orderedConcepts {
            guard let st = statuses[c.id], st.attempts > 0 else { continue }
            let attempts = state.attempts(for: c.id)
            let recent = attempts.suffix(5)
            let rate = Double(recent.filter(\.isIndependentSuccess).count) / Double(recent.count)
            if st.needsReview || (recent.count >= 2 && rate < 0.5) {
                scored.append((c.id, (st.needsReview ? -1 : 0) + rate))
            }
        }
        return scored.sorted { $0.score < $1.score }.prefix(limit).map(\.id)
    }

    public struct Calibration: Equatable, Sendable {
        public var total = 0
        public var correct = 0
        public var rate: Double? { total == 0 ? nil : Double(correct) / Double(total) }
    }

    /// How often answers were right at each stated confidence level.
    public static func calibration(state: AppState) -> [Confidence: Calibration] {
        var out: [Confidence: Calibration] = [:]
        for a in state.attempts {
            guard let c = a.confidence, a.assistance != .revealed else { continue }
            out[c, default: Calibration()].total += 1
            if a.outcome == .correct { out[c, default: Calibration()].correct += 1 }
        }
        return out
    }
}
