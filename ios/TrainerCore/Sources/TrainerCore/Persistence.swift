import Foundation

enum Coding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}

// MARK: - Migrations

/// Upgrades stored JSON from any earlier schema version to the current one.
/// A step for version N rewrites the raw JSON object from schema N to schema N+1.
/// Rules for future changes: adding an optional field needs no step (decoding fills
/// defaults); renaming or restructuring needs a step and a bump of
/// `AppState.currentSchemaVersion`. Attempts are never dropped by a migration.
public enum Migrations {
    public typealias Step = (inout [String: Any]) throws -> Void

    public enum Failure: Error, Equatable {
        case notAnObject
        case newerThanApp(found: Int, supported: Int)
        case missingStep(from: Int)
    }

    /// Registered steps, keyed by the version they upgrade *from*.
    public static let steps: [Int: Step] = [:]

    public static func migrate(_ data: Data, steps: [Int: Step] = Migrations.steps,
                               current: Int = AppState.currentSchemaVersion) throws -> AppState {
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.notAnObject }
        obj = try upgrade(obj, steps: steps, current: current)
        return try Coding.decoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    static func upgrade(_ object: [String: Any], steps: [Int: Step], current: Int) throws -> [String: Any] {
        var obj = object
        var version = (obj["schemaVersion"] as? Int) ?? 1
        if version > current { throw Failure.newerThanApp(found: version, supported: current) }
        while version < current {
            guard let step = steps[version] else { throw Failure.missingStep(from: version) }
            try step(&obj)
            version += 1
            obj["schemaVersion"] = version
        }
        return obj
    }
}

// MARK: - Store

/// Saves the state as JSON in a directory, keeping the previous good copy as a backup.
public final class StateStore {
    public enum Origin: Equatable, Sendable {
        case fresh              // nothing stored yet
        case main               // loaded normally
        case backup             // main file unreadable; previous copy used
        case corruptSetAside    // neither copy readable; files kept for inspection, state reset
    }

    private let directory: URL
    private var mainIsValid = false
    private var mainURL: URL { directory.appendingPathComponent("state.json") }
    private var backupURL: URL { directory.appendingPathComponent("state.bak.json") }

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func load() -> (state: AppState, origin: Origin) {
        let fm = FileManager.default
        let hasMain = fm.fileExists(atPath: mainURL.path), hasBackup = fm.fileExists(atPath: backupURL.path)
        if !hasMain && !hasBackup { return (AppState(), .fresh) }
        if hasMain, let data = try? Data(contentsOf: mainURL), let s = try? Migrations.migrate(data) {
            mainIsValid = true
            return (s, .main)
        }
        if hasBackup, let data = try? Data(contentsOf: backupURL), let s = try? Migrations.migrate(data) {
            return (s, .backup)
        }
        // Never delete unreadable data: move it aside so it can be inspected or re-imported.
        let stamp = Int(Date().timeIntervalSince1970)
        if hasMain { try? fm.moveItem(at: mainURL, to: directory.appendingPathComponent("state.corrupt-\(stamp).json")) }
        if hasBackup { try? fm.moveItem(at: backupURL, to: directory.appendingPathComponent("state.bak.corrupt-\(stamp).json")) }
        return (AppState(), .corruptSetAside)
    }

    public func save(_ state: AppState) throws {
        var s = state
        s.schemaVersion = AppState.currentSchemaVersion
        let data = try Coding.encoder().encode(s)
        let fm = FileManager.default
        // Keep the previous copy as a backup, but only if it is readable: a damaged main
        // file must never replace a good backup.
        if !mainIsValid, let old = try? Data(contentsOf: mainURL), (try? Migrations.migrate(old)) != nil {
            mainIsValid = true
        }
        if mainIsValid, fm.fileExists(atPath: mainURL.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: mainURL, to: backupURL)
        }
        try data.write(to: mainURL, options: .atomic)
        mainIsValid = true
    }
}

// MARK: - Export / import

public enum Backup {
    public static let formatName = "system-design-trainer-backup"
    public static let formatVersion = 1

    public enum Failure: Error, Equatable {
        case notJSON
        case wrongFormat
        case newerFormat(Int)
        case missingState
        case invalid(String)
    }

    public static func export(_ state: AppState, appVersion: String, clock: Clock) throws -> Data {
        var s = state
        s.session = nil     // an in-progress session is not meaningful on another install
        let stateObj = try JSONSerialization.jsonObject(with: Coding.encoder().encode(s))
        let envelope: [String: Any] = [
            "format": formatName,
            "formatVersion": formatVersion,
            "exportedAt": Int(clock.now().timeIntervalSince1970 * 1000),
            "appVersion": appVersion,
            "state": stateObj,
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted])
    }

    /// Validates and decodes an export. Throws without side effects, so the caller only
    /// replaces existing data after this succeeds.
    public static func importData(_ data: Data) throws -> AppState {
        guard let any = try? JSONSerialization.jsonObject(with: data), let obj = any as? [String: Any] else { throw Failure.notJSON }
        guard obj["format"] as? String == formatName else { throw Failure.wrongFormat }
        let fv = obj["formatVersion"] as? Int ?? 0
        guard fv >= 1 else { throw Failure.wrongFormat }
        guard fv <= formatVersion else { throw Failure.newerFormat(fv) }
        guard let stateObj = obj["state"] as? [String: Any] else { throw Failure.missingState }
        let state: AppState
        do {
            state = try Migrations.migrate(JSONSerialization.data(withJSONObject: stateObj))
        } catch let f as Migrations.Failure {
            throw Failure.invalid("\(f)")
        } catch {
            throw Failure.invalid("state does not match the expected structure")
        }
        try validate(state)
        return state
    }

    static func validate(_ s: AppState) throws {
        for a in s.attempts {
            guard a.score >= 0, a.score <= 1 else { throw Failure.invalid("attempt score out of range") }
            guard !a.itemId.isEmpty, a.hintsUsed >= 0 else { throw Failure.invalid("attempt is missing its item") }
        }
        for (id, r) in s.concepts {
            guard (0...Scheduler.maxStep).contains(r.step), r.lapses >= 0 else { throw Failure.invalid("review step out of range for \(id)") }
        }
        guard (0...23).contains(s.prefs.reminderHour), (0...59).contains(s.prefs.reminderMinute) else {
            throw Failure.invalid("reminder time out of range")
        }
        guard (5...120).contains(s.prefs.sessionMinutes) else { throw Failure.invalid("session length out of range") }
    }
}

// MARK: - Reminders

/// Pure description of the daily reminder; the app turns it into a local notification.
public struct ReminderPlan: Equatable, Sendable {
    /// One fixed identifier: scheduling again replaces the pending request, so there is never a duplicate.
    public static let identifier = "daily-study-reminder"
    public static let testIdentifier = "test-study-reminder"

    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String

    /// Returns nil when reminders are off. A calendar trigger with only hour and minute
    /// fires at that wall-clock time in whatever time zone the phone is in.
    public static func plan(prefs: Preferences, dueCount: Int, nextLessonTitle: String?) -> ReminderPlan? {
        guard prefs.remindersEnabled else { return nil }
        let hour = min(max(prefs.reminderHour, 0), 23), minute = min(max(prefs.reminderMinute, 0), 59)
        var parts: [String] = []
        if dueCount > 0 { parts.append("\(dueCount) concept\(dueCount == 1 ? "" : "s") due for review") }
        if let nextLessonTitle { parts.append("next lesson: \(nextLessonTitle)") }
        let body = parts.isEmpty ? "A short session keeps what you learned." : parts.joined(separator: " · ").capitalizedFirst
        return ReminderPlan(hour: hour, minute: minute, title: "Time for system design", body: body)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
