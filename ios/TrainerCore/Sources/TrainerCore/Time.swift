import Foundation

/// A calendar day in the learner's local time zone, stored as "YYYY-MM-DD".
/// Review due dates are days, not instants, so travelling across time zones or a
/// daylight-saving change never makes a review due at an odd hour.
public struct LocalDay: Codable, Hashable, Comparable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public init?(string: String) {
        let p = string.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = LocalDay(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad day \(s)"))
        }
        self = d
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // Day arithmetic goes through a fixed UTC calendar at noon so DST never shifts a day.
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var utcNoon: Date {
        LocalDay.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> LocalDay {
        LocalDay(LocalDay.utc.date(byAdding: .day, value: days, to: utcNoon)!, calendar: LocalDay.utc)
    }

    /// Whole days from `other` to `self` (positive when `self` is later).
    public func days(since other: LocalDay) -> Int {
        LocalDay.utc.dateComponents([.day], from: other.utcNoon, to: utcNoon).day!
    }
}

/// Injected source of "now" and the local calendar, so tests control time.
public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    public var calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public var today: LocalDay { LocalDay(now(), calendar: calendar) }
    public func day(of date: Date) -> LocalDay { LocalDay(date, calendar: calendar) }

    public static func fixed(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Clock {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return Clock(now: { date }, calendar: cal)
    }
}
