import Foundation

// Everything the app persists. All types decode leniently (missing keys fall back to
// defaults) so that adding a field never breaks previously stored data.

public enum Outcome: String, Codable, Sendable { case correct, partial, incorrect }

/// How much help the learner had when answering.
public enum Assistance: String, Codable, Sendable {
    case independent   // no hint, answered before seeing the solution
    case hinted        // used at least one hint
    case revealed      // gave up and looked at the answer
}

/// Who decided whether the answer was right.
public enum Grading: String, Codable, Sendable {
    case auto          // checked by the app
    case selfAssessed  // learner compared their answer with a rubric
}

public enum Confidence: String, Codable, CaseIterable, Sendable { case low, medium, high }

public enum AttemptContext: String, Codable, Sendable {
    case practice       // right after a lesson, or manual practice
    case review         // spaced review
    case application    // application problem in a daily session
    case quiz           // topic quiz
    case delayedCheck   // retention check
    case cumulative
    case final
    public var isAssessment: Bool { self == .quiz || self == .delayedCheck || self == .cumulative || self == .final }
}

public struct Attempt: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var itemId: String
    public var conceptIds: [String]
    public var date: Date
    public var outcome: Outcome
    public var assistance: Assistance
    public var grading: Grading
    public var confidence: Confidence?
    public var context: AttemptContext
    public var format: ItemFormat
    public var score: Double        // 0...1
    public var hintsUsed: Int

    public init(id: UUID = UUID(), itemId: String, conceptIds: [String], date: Date, outcome: Outcome,
                assistance: Assistance, grading: Grading, confidence: Confidence? = nil,
                context: AttemptContext, format: ItemFormat, score: Double, hintsUsed: Int = 0) {
        self.id = id; self.itemId = itemId; self.conceptIds = conceptIds; self.date = date
        self.outcome = outcome; self.assistance = assistance; self.grading = grading
        self.confidence = confidence; self.context = context; self.format = format
        self.score = score; self.hintsUsed = hintsUsed
    }

    /// Correct with no help: the only kind of attempt that counts as evidence of mastery.
    public var isIndependentSuccess: Bool { outcome == .correct && assistance == .independent }
    public var isFailure: Bool { outcome == .incorrect || assistance == .revealed }
    public var primaryConcept: String { conceptIds.first ?? "" }
}

/// Spaced-review bookkeeping for one concept.
public struct ConceptRecord: Codable, Hashable, Sendable {
    public var introducedAt: Date?
    public var step: Int = 0
    public var dueDay: LocalDay?
    public var lastReviewedAt: Date?
    public var lastItemId: String?
    public var lapses: Int = 0
    /// Set when a high-confidence answer was wrong; cleared by the next independent success.
    public var misconception: Bool = false

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        introducedAt = try c.decodeIfPresent(Date.self, forKey: .introducedAt)
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 0
        dueDay = try c.decodeIfPresent(LocalDay.self, forKey: .dueDay)
        lastReviewedAt = try c.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        lastItemId = try c.decodeIfPresent(String.self, forKey: .lastItemId)
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        misconception = try c.decodeIfPresent(Bool.self, forKey: .misconception) ?? false
    }
}

public enum CaseMode: String, Codable, Sendable { case guided, unguided, timed }

public struct CaseResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var caseId: String
    public var date: Date
    public var mode: CaseMode
    public var rubricMet: Int
    public var rubricTotal: Int
    public var durationSec: Int
    public init(caseId: String, date: Date, mode: CaseMode, rubricMet: Int, rubricTotal: Int, durationSec: Int) {
        self.caseId = caseId; self.date = date; self.mode = mode
        self.rubricMet = rubricMet; self.rubricTotal = rubricTotal; self.durationSec = durationSec
    }
}

public enum AssessmentKind: String, Codable, Sendable { case quiz, delayedCheck, cumulative, final }

/// Summary of a finished assessment. Scores from automatic and self grading are kept apart.
public struct AssessmentResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var kind: AssessmentKind
    public var moduleId: String?
    public var date: Date
    public var itemIds: [String]
    public var autoCorrect: Int
    public var autoTotal: Int
    public var selfPoints: Double
    public var selfTotal: Int
    public init(kind: AssessmentKind, moduleId: String?, date: Date, itemIds: [String],
                autoCorrect: Int, autoTotal: Int, selfPoints: Double, selfTotal: Int) {
        self.kind = kind; self.moduleId = moduleId; self.date = date; self.itemIds = itemIds
        self.autoCorrect = autoCorrect; self.autoTotal = autoTotal; self.selfPoints = selfPoints; self.selfTotal = selfTotal
    }
}

public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }

public struct Preferences: Codable, Hashable, Sendable {
    public var sessionMinutes: Int = 15
    public var remindersEnabled: Bool = true
    public var reminderHour: Int = 15
    public var reminderMinute: Int = 0
    public var appearance: Appearance = .system
    public var askConfidence: Bool = true
    public var onboarded: Bool = false

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? 15
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 15
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        askConfidence = try c.decodeIfPresent(Bool.self, forKey: .askConfidence) ?? true
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = AppState.currentSchemaVersion
    public var attempts: [Attempt] = []
    public var concepts: [String: ConceptRecord] = [:]
    public var lessonsCompleted: [String: Date] = [:]
    public var caseResults: [CaseResult] = []
    public var labsDone: [String: Date] = [:]
    public var assessments: [AssessmentResult] = []
    public var prefs = Preferences()
    public var session: SessionProgress?
    public var lastExportAt: Date?

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AppState.currentSchemaVersion
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
        concepts = try c.decodeIfPresent([String: ConceptRecord].self, forKey: .concepts) ?? [:]
        lessonsCompleted = try c.decodeIfPresent([String: Date].self, forKey: .lessonsCompleted) ?? [:]
        caseResults = try c.decodeIfPresent([CaseResult].self, forKey: .caseResults) ?? []
        labsDone = try c.decodeIfPresent([String: Date].self, forKey: .labsDone) ?? [:]
        assessments = try c.decodeIfPresent([AssessmentResult].self, forKey: .assessments) ?? []
        prefs = try c.decodeIfPresent(Preferences.self, forKey: .prefs) ?? Preferences()
        session = try c.decodeIfPresent(SessionProgress.self, forKey: .session)
        lastExportAt = try c.decodeIfPresent(Date.self, forKey: .lastExportAt)
    }

    public func attempts(for concept: String) -> [Attempt] {
        attempts.filter { $0.conceptIds.contains(concept) }
    }
}
