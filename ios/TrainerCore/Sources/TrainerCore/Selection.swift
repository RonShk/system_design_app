import Foundation

/// Per-item and per-concept lookups over the attempt log, built once per composition.
public struct History: Sendable {
    public private(set) var lastSeen: [String: Date] = [:]            // item id → last attempt
    public private(set) var lastItem: [String: String] = [:]          // concept id → last item id
    public private(set) var lastFormat: [String: ItemFormat] = [:]    // concept id → format of last item
    public private(set) var lastAttempt: [String: Date] = [:]         // concept id → last attempt
    public private(set) var lastAssessed: [String: Date] = [:]        // concept id → last assessment attempt

    public init(state: AppState) {
        for a in state.attempts.sorted(by: { $0.date < $1.date }) {
            lastSeen[a.itemId] = a.date
            for c in a.conceptIds {
                lastItem[c] = a.itemId
                lastFormat[c] = a.format
                lastAttempt[c] = a.date
                if a.context.isAssessment { lastAssessed[c] = a.date }
            }
        }
    }
}

/// Small deterministic generator so compositions are reproducible in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum ItemSelector {
    /// Chooses an item for a concept so that wording is not memorised:
    /// never the item used last time (if another exists), unseen items first (easiest
    /// first), then the least recently seen, preferring a different format from last time.
    public static func pick(concept: String, pools: Set<ItemPool>, catalog: Catalog, history: History,
                            exclude: Set<String> = [], skills: Set<ItemSkill>? = nil, minDifficulty: Int = 1) -> ItemMeta? {
        var candidates = (catalog.itemsByConcept[concept] ?? []).filter { item in
            pools.contains(item.pool) && !exclude.contains(item.id) && item.difficulty >= minDifficulty
                && (skills?.contains(item.skill) ?? true)
        }
        if candidates.count > 1, let last = history.lastItem[concept] {
            candidates.removeAll { $0.id == last }
        }
        let lastFormat = history.lastFormat[concept]
        return candidates.min { a, b in
            let sa = history.lastSeen[a.id], sb = history.lastSeen[b.id]
            switch (sa, sb) {
            case (nil, .some): return true
            case (.some, nil): return false
            case (.some(let x), .some(let y)) where x != y: return x < y
            default: break
            }
            let fa = a.format == lastFormat, fb = b.format == lastFormat
            if fa != fb { return !fa }
            if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
            return a.id < b.id
        }
    }

    /// Item for a due spaced review. Once a concept's interval is a week or more, the review
    /// doubles as a delayed retention check and prefers an assessment item never seen before.
    public static func reviewItem(concept: String, state: AppState, catalog: Catalog, history: History,
                                  clock: Clock, exclude: Set<String> = []) -> (item: ItemMeta, context: AttemptContext)? {
        let step = state.concepts[concept]?.step ?? 0
        if Scheduler.interval(step: step) >= Mastery.retentionGapDays,
           let it = pick(concept: concept, pools: [.assess], catalog: catalog, history: history, exclude: exclude) {
            let seen = history.lastSeen[it.id]
            let stale = seen.map { clock.today.days(since: clock.day(of: $0)) >= 30 } ?? true
            if stale { return (it, .delayedCheck) }
        }
        if let it = pick(concept: concept, pools: [.practice], catalog: catalog, history: history, exclude: exclude) {
            return (it, .review)
        }
        return nil
    }
}
