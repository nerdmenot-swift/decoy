/// An instant, as whole seconds from the Unix epoch, in UTC.
///
/// Foundation-free on purpose. All of Decoy's date *arithmetic* lives here so it is
/// exact, deterministic, and identical on every platform — `Date` is a `Double`, and
/// accumulating fractional seconds across a million generated rows is how two
/// machines end up disagreeing about a fixture. `Date` bridging is provided on top,
/// where Foundation exists.
public struct Timestamp: Sendable, Hashable, Comparable, CustomStringConvertible {

    /// Whole seconds since 1970-01-01T00:00:00Z.
    public var secondsSinceEpoch: Int64

    public init(secondsSinceEpoch: Int64) {
        self.secondsSinceEpoch = secondsSinceEpoch
    }

    /// Builds an instant from a UTC calendar date.
    public init(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) {
        let days = Self.daysFromCivil(year: year, month: month, day: day)
        self.secondsSinceEpoch =
            days * 86_400 + Int64(hour) * 3_600 + Int64(minute) * 60 + Int64(second)
    }

    public static func < (a: Timestamp, b: Timestamp) -> Bool {
        a.secondsSinceEpoch < b.secondsSinceEpoch
    }

    /// The default anchor for relative date generation: 2026-01-01T00:00:00Z.
    ///
    /// A constant rather than "now", so a fixture generated today and the same fixture
    /// regenerated next year are byte-identical. See ``Faker/reference``.
    public static let decoyReference = Timestamp(year: 2026, month: 1, day: 1)

    // MARK: - Calendar conversion

    /// The UTC calendar components of this instant.
    public var civil: (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        // Floor-divide, so instants before 1970 land on the right day rather than
        // truncating toward zero and landing a day late.
        var days = secondsSinceEpoch / 86_400
        var remainder = secondsSinceEpoch % 86_400
        if remainder < 0 {
            remainder += 86_400
            days -= 1
        }
        let (year, month, day) = Self.civilFromDays(days)
        return (
            year, month, day,
            Int(remainder / 3_600), Int((remainder % 3_600) / 60), Int(remainder % 60)
        )
    }

    /// Day of the week, `0` being Sunday.
    public var weekday: Int {
        var days = secondsSinceEpoch / 86_400
        if secondsSinceEpoch % 86_400 < 0 { days -= 1 }
        // 1970-01-01 was a Thursday, hence the offset of 4.
        return Int(((days + 4) % 7 + 7) % 7)
    }

    /// ISO 8601 in UTC, e.g. `2026-07-27T14:03:09Z`.
    ///
    /// Formatted by hand rather than through a `DateFormatter`, whose output depends
    /// on the host's locale and calendar settings — a fixture written on a machine
    /// configured for the Buddhist calendar must not differ from everyone else's.
    public var iso8601: String {
        let c = civil
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(abs(value))
            return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
        }
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
            + "T\(pad(c.hour, 2)):\(pad(c.minute, 2)):\(pad(c.second, 2))Z"
    }

    public var description: String { iso8601 }

    // MARK: - Days/civil conversion

    /// Days from the epoch for a proleptic Gregorian date.
    ///
    /// Howard Hinnant's `days_from_civil`: branch-free, exact for the whole range of
    /// `Int64`, and requiring no leap-year special cases.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        var y = Int64(year)
        let m = Int64(month)
        let d = Int64(day)
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400  // [0, 399]
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy  // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// The inverse of ``daysFromCivil(year:month:day:)``.
    static func civilFromDays(_ days: Int64) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097  // [0, 146096]
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365  // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)  // [0, 365]
        let mp = (5 * doy + 2) / 153  // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1  // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)  // [1, 12]
        return (Int(y + (m <= 2 ? 1 : 0)), Int(m), Int(d))
    }
}

// MARK: - Foundation bridging

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

#if canImport(FoundationEssentials) || canImport(Foundation)
    extension Timestamp {
        /// This instant as a Foundation `Date`.
        public var date: Date {
            Date(timeIntervalSince1970: Double(secondsSinceEpoch))
        }

        public init(_ date: Date) {
            self.init(secondsSinceEpoch: Int64(date.timeIntervalSince1970.rounded(.down)))
        }
    }
#endif
