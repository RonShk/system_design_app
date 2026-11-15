import Foundation

/// What the learner submitted for one item.
public enum Response: Equatable, Sendable {
    case choice(Int)            // index into Item.choices
    case choices(Set<Int>)
    case number(String)         // raw text as typed
    case ordering([Int])        // indexes into Item.steps, in the order the learner arranged them
    case rubric(Set<Int>)       // rubric points the learner judged their answer to meet
}

public struct CheckResult: Equatable, Sendable {
    public var outcome: Outcome
    public var score: Double
    public var grading: Grading
    public init(outcome: Outcome, score: Double, grading: Grading) {
        self.outcome = outcome; self.score = score; self.grading = grading
    }
}

public enum Checker {
    /// Parses what a person might type for a number: "1,200", "1 200", "1.2e3", "45%", "1.5k", "2M".
    public static func parseNumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        s = s.replacingOccurrences(of: "×10^", with: "e").replacingOccurrences(of: "x10^", with: "e").replacingOccurrences(of: "*10^", with: "e")
        if s.hasSuffix("%") { s.removeLast() }
        var mult = 1.0
        if let last = s.last, s.count > 1 {
            switch last {
            case "k": mult = 1e3; s.removeLast()
            case "m": mult = 1e6; s.removeLast()
            case "b", "g": mult = 1e9; s.removeLast()
            case "t": mult = 1e12; s.removeLast()
            default: break
            }
        }
        guard !s.isEmpty, let v = Double(s), v.isFinite else { return nil }
        return v * mult
    }

    public static func numberMatches(_ value: Double, item: Item) -> Bool {
        guard let answer = item.answer else { return false }
        let diff = abs(value - answer)
        // Small epsilon so a value exactly on the boundary is accepted despite floating point.
        if let abs = item.tolAbs { return diff <= abs + 1e-9 }
        let rel = item.tolerance ?? 0
        return diff <= Swift.abs(answer) * rel + 1e-9
    }

    /// Returns nil when the response does not fit the item's format or cannot be parsed.
    public static func check(_ response: Response, item: Item) -> CheckResult? {
        switch (item.format, response) {
        case (.mcq, .choice(let i)):
            guard let a = item.answer else { return nil }
            let ok = i == Int(a)
            return CheckResult(outcome: ok ? .correct : .incorrect, score: ok ? 1 : 0, grading: .auto)

        case (.multi, .choices(let picked)):
            guard let answers = item.answers, let n = item.choices?.count, n > 0 else { return nil }
            let truth = Set(answers)
            if picked == truth { return CheckResult(outcome: .correct, score: 1, grading: .auto) }
            // Score = share of choices classified correctly; anything short of exact is incorrect.
            let right = (0..<n).filter { picked.contains($0) == truth.contains($0) }.count
            return CheckResult(outcome: .incorrect, score: Double(right) / Double(n), grading: .auto)

        case (.numeric, .number(let raw)):
            guard let v = parseNumber(raw) else { return nil }
            let ok = numberMatches(v, item: item)
            return CheckResult(outcome: ok ? .correct : .incorrect, score: ok ? 1 : 0, grading: .auto)

        case (.order, .ordering(let order)):
            guard let n = item.steps?.count, order.count == n, Set(order) == Set(0..<n) else { return nil }
            if order == Array(0..<n) { return CheckResult(outcome: .correct, score: 1, grading: .auto) }
            // Partial credit by adjacent pairs that are in the right relative order.
            let pairs = zip(order, order.dropFirst()).filter { $0.0 < $0.1 }.count
            return CheckResult(outcome: .incorrect, score: Double(pairs) / Double(max(1, n - 1)) * 0.5, grading: .auto)

        case (.free, .rubric(let met)):
            guard let total = item.rubric?.count, total > 0 else { return nil }
            let count = met.filter { $0 >= 0 && $0 < total }.count
            let score = Double(count) / Double(total)
            let outcome: Outcome = count == total ? .correct : (score >= 0.5 ? .partial : .incorrect)
            return CheckResult(outcome: outcome, score: score, grading: .selfAssessed)

        default:
            return nil
        }
    }
}
