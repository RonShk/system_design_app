import Foundation

// Models for the JSON produced by scripts/build-content.mjs.

public struct Module: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
}

public struct LessonMeta: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let module: String
    public let order: Int
    public let minutes: Int
    public let objective: String
    public let prereqs: [String]
    public let concepts: [String]
    public let hasDiagram: Bool
}

public struct Concept: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let def: String
    public let lessonId: String
    public let moduleId: String
}

public enum ItemPool: String, Codable, Sendable { case practice, assess, final }
public enum ItemSkill: String, Codable, CaseIterable, Sendable {
    case recall, explain, predict, compare, estimate, diagnose, design, implement
}
public enum ItemFormat: String, Codable, CaseIterable, Sendable {
    case mcq, multi, numeric, order, free
    /// Formats where the learner only has to recognise the answer.
    public var isRecognition: Bool { self == .mcq || self == .multi }
    /// Formats the app can check without the learner's judgement.
    public var isAutoChecked: Bool { self != .free }
}

public struct ItemMeta: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let concepts: [String]
    public let pool: ItemPool
    public let skill: ItemSkill
    public let format: ItemFormat
    public let difficulty: Int
    public let lessonId: String?
    public let caseId: String?
    public var primaryConcept: String { concepts.first ?? "" }
}

public struct SourceRef: Codable, Hashable, Sendable {
    public let ref: String
    public let title: String?
    public let section: String
    public let url: String?
}

public struct Item: Codable, Identifiable, Sendable {
    public let id: String
    public let concepts: [String]
    public let pool: ItemPool
    public let skill: ItemSkill
    public let format: ItemFormat
    public let difficulty: Int
    public let lessonId: String?
    public let caseId: String?
    public let prompt: [Block]
    public let hints: [String]
    public let explanation: [Block]
    public let assumptions: String?
    public let sources: [SourceRef]
    // format-specific
    public let choices: [String]?
    public let answer: Double?        // mcq: index, numeric: value
    public let answers: [Int]?        // multi
    public let tolerance: Double?     // numeric, relative
    public let tolAbs: Double?        // numeric, absolute
    public let unit: String?
    public let steps: [String]?       // order, in the correct order
    public let model: [Block]?        // free
    public let rubric: [String]?      // free
    public var primaryConcept: String { concepts.first ?? "" }
}

public struct Section: Codable, Sendable {
    public let title: String
    public let blocks: [Block]
}

public struct LessonBody: Codable, Sendable {
    public let sections: [Section]
    public let sources: [SourceRef]
}

public struct CaseMeta: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let minutes: Int
    public let prereqs: [String]
    public let concepts: [String]
}

public struct CaseStage: Codable, Sendable {
    public let title: String
    public let prompt: String
    public let blocks: [Block]
}

public struct UnguidedExercise: Codable, Sendable {
    public let prompt: [Block]
    public let rubric: [String]
    public let minutes: Int
}

public struct CaseBody: Codable, Sendable {
    public let stages: [CaseStage]
    public let sources: [SourceRef]
    public let unguided: UnguidedExercise?
}

public struct LabMeta: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let hours: Double?
    public let lessons: [String]
}

// MARK: - Blocks

public struct ListEntry: Codable, Hashable, Sendable {
    public let md: String
    public let level: Int
}

public struct DiagramEdge: Codable, Hashable, Sendable {
    public let from: String
    public let to: String
    public let kind: String   // solid | dashed | lost | note
    public let label: String
    public let note: Bool?
}

public enum Diagram: Hashable, Sendable {
    case flow(rows: [[String]], edges: [DiagramEdge])
    case seq(actors: [String], steps: [DiagramEdge])
}

/// One renderable piece of lesson content. Inline formatting inside `md` strings is Markdown.
public enum Block: Codable, Hashable, Sendable {
    case paragraph(String)
    case heading(String)
    case quote(String)
    case code(text: String, lang: String)
    case list(ordered: Bool, items: [ListEntry])
    case table(head: [String], rows: [[String]])
    case diagram(Diagram)

    private enum K: String, CodingKey { case t, md, text, lang, items, head, rows, kind, edges, actors, steps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "p": self = .paragraph(try c.decode(String.self, forKey: .md))
        case "h": self = .heading(try c.decode(String.self, forKey: .md))
        case "quote": self = .quote(try c.decode(String.self, forKey: .md))
        case "code": self = .code(text: try c.decode(String.self, forKey: .text), lang: (try? c.decode(String.self, forKey: .lang)) ?? "")
        case "ul", "ol": self = .list(ordered: t == "ol", items: try c.decode([ListEntry].self, forKey: .items))
        case "table": self = .table(head: try c.decode([String].self, forKey: .head), rows: try c.decode([[String]].self, forKey: .rows))
        case "diagram":
            let kind = try c.decode(String.self, forKey: .kind)
            if kind == "flow" {
                self = .diagram(.flow(rows: try c.decode([[String]].self, forKey: .rows), edges: try c.decode([DiagramEdge].self, forKey: .edges)))
            } else if kind == "seq" {
                self = .diagram(.seq(actors: try c.decode([String].self, forKey: .actors), steps: try c.decode([DiagramEdge].self, forKey: .steps)))
            } else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown diagram kind \(kind)")
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown block type \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .paragraph(let md): try c.encode("p", forKey: .t); try c.encode(md, forKey: .md)
        case .heading(let md): try c.encode("h", forKey: .t); try c.encode(md, forKey: .md)
        case .quote(let md): try c.encode("quote", forKey: .t); try c.encode(md, forKey: .md)
        case .code(let text, let lang): try c.encode("code", forKey: .t); try c.encode(text, forKey: .text); try c.encode(lang, forKey: .lang)
        case .list(let ordered, let items): try c.encode(ordered ? "ol" : "ul", forKey: .t); try c.encode(items, forKey: .items)
        case .table(let head, let rows): try c.encode("table", forKey: .t); try c.encode(head, forKey: .head); try c.encode(rows, forKey: .rows)
        case .diagram(.flow(let rows, let edges)):
            try c.encode("diagram", forKey: .t); try c.encode("flow", forKey: .kind); try c.encode(rows, forKey: .rows); try c.encode(edges, forKey: .edges)
        case .diagram(.seq(let actors, let steps)):
            try c.encode("diagram", forKey: .t); try c.encode("seq", forKey: .kind); try c.encode(actors, forKey: .actors); try c.encode(steps, forKey: .steps)
        }
    }
}

// MARK: - Catalog

private struct IndexFile: Codable {
    let modules: [Module]
    let lessons: [LessonMeta]
    let concepts: [String: Concept]
    let items: [ItemMeta]
    let cases: [CaseMeta]
    let labs: [LabMeta]
}

/// All bundled content, loaded once at launch and immutable afterwards.
public final class Catalog: @unchecked Sendable {
    public let modules: [Module]
    public let lessons: [LessonMeta]              // in curriculum order
    public let concepts: [String: Concept]
    public let itemMetas: [ItemMeta]
    public let cases: [CaseMeta]
    public let labs: [LabMeta]
    public let items: [String: Item]
    public let lessonBodies: [String: LessonBody]
    public let caseBodies: [String: CaseBody]
    public let labBodies: [String: LessonBody]

    public let lessonById: [String: LessonMeta]
    public let lessonIndex: [String: Int]
    public let itemMetaById: [String: ItemMeta]
    /// Items whose primary concept is the key.
    public let itemsByConcept: [String: [ItemMeta]]

    public enum LoadError: Error { case missing(String) }

    public init(directory: URL) throws {
        func load<T: Decodable>(_ name: String, _ type: T.Type) throws -> T {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { throw LoadError.missing(name) }
            return try JSONDecoder().decode(T.self, from: data)
        }
        let index = try load("index.json", IndexFile.self)
        modules = index.modules
        lessons = index.lessons
        concepts = index.concepts
        itemMetas = index.items
        cases = index.cases
        labs = index.labs
        items = try load("items.json", [String: Item].self)
        lessonBodies = try load("lessons.json", [String: LessonBody].self)
        caseBodies = try load("cases.json", [String: CaseBody].self)
        labBodies = try load("labs.json", [String: LessonBody].self)
        lessonById = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        lessonIndex = Dictionary(uniqueKeysWithValues: lessons.enumerated().map { ($1.id, $0) })
        itemMetaById = Dictionary(uniqueKeysWithValues: itemMetas.map { ($0.id, $0) })
        itemsByConcept = Dictionary(grouping: itemMetas, by: { $0.primaryConcept })
    }

    public func lessons(in module: String) -> [LessonMeta] { lessons.filter { $0.module == module } }
    public func concepts(in module: String) -> [Concept] {
        lessons(in: module).flatMap { $0.concepts.compactMap { concepts[$0] } }
    }
    /// Concepts in curriculum order.
    public var orderedConcepts: [Concept] { lessons.flatMap { $0.concepts.compactMap { concepts[$0] } } }
}
