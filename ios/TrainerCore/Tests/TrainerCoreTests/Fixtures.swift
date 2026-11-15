import Foundation
import XCTest
@testable import TrainerCore

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    var date: Date
    let calendar: Calendar

    init(_ iso: String = "2026-03-02T09:00:00Z", zone: String = "UTC") {
        date = ISO8601DateFormatter().date(from: iso)!
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        calendar = c
    }
    var clock: Clock { Clock(now: { [unowned self] in self.date }, calendar: calendar) }
    func advance(days: Double = 0, hours: Double = 0, minutes: Double = 0) {
        date = date.addingTimeInterval(days * 86400 + hours * 3600 + minutes * 60)
    }
    func set(_ iso: String) { date = ISO8601DateFormatter().date(from: iso)! }
}

enum Fixture {
    /// Synthetic catalog: `modules` modules × `lessonsPerModule` lessons, each with 2 concepts.
    /// Every concept gets practice items p1 (mcq), p2 (free), p3 (numeric, skill estimate, difficulty 2)
    /// and assessment items a1 (free), a2 (mcq).
    static func catalog(modules: Int = 2, lessonsPerModule: Int = 3, standalone: Bool = true, finals: Int = 2) -> Catalog {
        var mods: [[String: Any]] = [], lessons: [[String: Any]] = [], concepts: [String: Any] = [:]
        var metas: [[String: Any]] = [], items: [String: Any] = [:], bodies: [String: Any] = [:]
        func add(_ id: String, _ cs: [String], _ pool: String, _ skill: String, _ format: String, _ diff: Int, lesson: String?) {
            let meta: [String: Any] = ["id": id, "concepts": cs, "pool": pool, "skill": skill, "format": format, "difficulty": diff,
                                       "lessonId": lesson as Any? ?? NSNull(), "caseId": NSNull()]
            metas.append(meta)
            var full = meta
            full["prompt"] = [["t": "p", "md": "Question \(id)?"]]
            full["hints"] = ["hint"]
            full["explanation"] = [["t": "p", "md": "Because."]]
            full["sources"] = [["ref": "s", "title": "S", "section": "1", "url": "https://example.com"]]
            switch format {
            case "mcq": full["choices"] = ["a", "b", "c"]; full["answer"] = 1
            case "multi": full["choices"] = ["a", "b", "c"]; full["answers"] = [0, 2]
            case "numeric": full["answer"] = 100; full["tolerance"] = 0.1; full["unit"] = "ms"
            case "order": full["steps"] = ["one", "two", "three"]
            default: full["model"] = [["t": "p", "md": "Model."]]; full["rubric"] = ["point one", "point two"]
            }
            items[id] = full
        }
        for m in 0..<modules {
            let mid = "m\(m)"
            mods.append(["id": mid, "title": "Module \(m)", "summary": "s"])
            for l in 0..<lessonsPerModule {
                let lid = "\(mid)-l\(l)"
                let cids = ["\(lid)-c0", "\(lid)-c1"]
                lessons.append(["id": lid, "title": "Lesson \(lid)", "module": mid, "order": l + 1, "minutes": 5,
                                "objective": "o", "prereqs": [String](), "concepts": cids, "hasDiagram": false])
                bodies[lid] = ["sections": [["title": "Intuition", "blocks": [["t": "p", "md": "text"]]]], "sources": [Any]()]
                for c in cids {
                    concepts[c] = ["id": c, "name": "Concept \(c)", "def": "d", "lessonId": lid, "moduleId": mid]
                    add("\(c)-p1", [c], "practice", "recall", "mcq", 1, lesson: lid)
                    add("\(c)-p2", [c], "practice", "explain", "free", 2, lesson: lid)
                    add("\(c)-p3", [c], "practice", "estimate", "numeric", 2, lesson: lid)
                    add("\(c)-a1", [c], "assess", "diagnose", "free", 2, lesson: lid)
                    add("\(c)-a2", [c], "assess", "predict", "mcq", 2, lesson: lid)
                }
            }
        }
        if standalone, modules >= 2 {
            add("cum-1", ["m0-l0-c0", "m1-l0-c0"], "assess", "design", "free", 3, lesson: nil)
        }
        for f in 0..<finals { add("final-\(f)", ["m0-l0-c0"], "final", "design", "free", 3, lesson: nil) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ obj: Any) {
            try! JSONSerialization.data(withJSONObject: obj).write(to: dir.appendingPathComponent(name))
        }
        write("index.json", ["modules": mods, "lessons": lessons, "concepts": concepts, "items": metas, "cases": [Any](), "labs": [Any]()])
        write("items.json", items)
        write("lessons.json", bodies)
        write("cases.json", [String: Any]())
        write("labs.json", [String: Any]())
        return try! Catalog(directory: dir)
    }

    /// Answers an item the way a learner would and records it through the engine.
    @discardableResult
    static func answer(_ itemId: String, correct: Bool = true, hints: Int = 0, revealed: Bool = false, partial: Bool = false,
                       confidence: Confidence? = nil, context: AttemptContext = .practice,
                       state: inout AppState, catalog: Catalog, clock: Clock) -> Attempt {
        let item = catalog.items[itemId]!
        let response: Response
        switch item.format {
        case .mcq: response = .choice(correct ? Int(item.answer!) : (Int(item.answer!) + 1) % item.choices!.count)
        case .multi: response = .choices(correct ? Set(item.answers!) : [])
        case .numeric: response = .number(correct ? "\(item.answer!)" : "\(item.answer! * 10 + 7)")
        case .order: response = .ordering(correct ? Array(0..<item.steps!.count) : Array((0..<item.steps!.count).reversed()))
        case .free:
            let n = item.rubric!.count
            response = .rubric(partial ? [0] : (correct ? Set(0..<n) : []))
        }
        let result = Checker.check(response, item: item)
        XCTAssertNotNil(result)
        return Engine.record(item: item, result: result, hintsUsed: hints, revealed: revealed, confidence: confidence,
                             context: context, state: &state, clock: clock)
    }

    static func realContentDirectory(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("SystemDesignTrainer/Resources/content")
    }
}
