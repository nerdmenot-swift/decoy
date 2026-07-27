/// Date generation.
///
/// Two layers, deliberately. The arithmetic lives on ``Timestamp``, which imports
/// nothing and is exact integer seconds, so the values are identical on every
/// platform. The `date` namespace sits on top and hands back `Foundation.Date`,
/// because that is what the models being seeded actually use.
///
/// Everything is relative to ``Faker/reference`` rather than to the system clock —
/// see that property for why.
extension Faker {
    /// Date generation as ``Timestamp``, available with or without Foundation.
    public var instant: InstantFaker {
        get { InstantFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct InstantFaker {
    var faker: Faker

    // MARK: - Relative to the reference instant

    /// An instant within `years` before the reference.
    public mutating func past(years: Double = 1) -> Timestamp {
        let span = Int64(years * 365.25 * 86_400)
        return offset(by: -faker.rng.draw(in: 1...Swift.max(1, Int(span))))
    }

    /// An instant within `years` after the reference.
    public mutating func future(years: Double = 1) -> Timestamp {
        let span = Int64(years * 365.25 * 86_400)
        return offset(by: faker.rng.draw(in: 1...Swift.max(1, Int(span))))
    }

    /// An instant within the last `days`.
    public mutating func recent(days: Int = 1) -> Timestamp {
        offset(by: -faker.rng.draw(in: 1...Swift.max(1, days * 86_400)))
    }

    /// An instant within the next `days`.
    public mutating func soon(days: Int = 1) -> Timestamp {
        offset(by: faker.rng.draw(in: 1...Swift.max(1, days * 86_400)))
    }

    /// A uniformly chosen instant in a closed range.
    public mutating func between(_ start: Timestamp, _ end: Timestamp) -> Timestamp {
        let low = Swift.min(start.secondsSinceEpoch, end.secondsSinceEpoch)
        let high = Swift.max(start.secondsSinceEpoch, end.secondsSinceEpoch)
        guard high > low else { return start }
        let span = UInt64(high - low)
        return Timestamp(secondsSinceEpoch: low + Int64(faker.rng.draw(below: span + 1)))
    }

    /// A birthdate for someone in the given age range at the reference instant.
    ///
    /// Ages are computed backwards from the reference, so a record's age stays the
    /// same however long after generation you read it — anchoring to `now` would make
    /// a "25-year-old" fixture quietly turn 26.
    public mutating func birthdate(minAge: Int = 18, maxAge: Int = 80) -> Timestamp {
        precondition(minAge >= 0 && maxAge >= minAge, "invalid age range")
        let youngest = offset(byYears: -minAge)
        let oldest = offset(byYears: -maxAge)
        return between(oldest, youngest)
    }

    private mutating func offset(by seconds: Int) -> Timestamp {
        Timestamp(secondsSinceEpoch: faker.reference.secondsSinceEpoch + Int64(seconds))
    }

    /// Shifts by whole calendar years, preserving month and day where possible.
    ///
    /// 29 February is clamped to the 28th rather than rolling into March, which is
    /// what a reader expects of "the same date, N years earlier".
    private func offset(byYears years: Int) -> Timestamp {
        let c = faker.reference.civil
        let targetYear = c.year + years
        let isLeap =
            (targetYear % 4 == 0 && targetYear % 100 != 0) || targetYear % 400 == 0
        let day = (c.month == 2 && c.day == 29 && !isLeap) ? 28 : c.day
        return Timestamp(
            year: targetYear,
            month: c.month,
            day: day,
            hour: c.hour,
            minute: c.minute,
            second: c.second
        )
    }

    // MARK: - Corpus-backed names

    public mutating func monthName(abbreviated: Bool = false) -> String {
        faker.require("date.month.\(abbreviated ? "abbr" : "wide")")
    }

    public mutating func weekdayName(abbreviated: Bool = false) -> String {
        faker.require("date.weekday.\(abbreviated ? "abbr" : "wide")")
    }

    public mutating func timeZone() -> String {
        faker.require("date.time_zone")
    }
}

// MARK: - Foundation-facing namespace

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

#if canImport(FoundationEssentials) || canImport(Foundation)

    extension Faker {
        /// Date generation as `Foundation.Date`.
        ///
        /// A thin projection of ``instant``, which holds the arithmetic. Unavailable
        /// on targets without any Foundation module — use ``instant`` there.
        public var date: DateFaker {
            get { DateFaker(faker: self) }
            set { self = newValue.faker }
        }
    }

    public struct DateFaker {
        var faker: Faker

        public mutating func past(years: Double = 1) -> Date { faker.instant.past(years: years).date }
        public mutating func future(years: Double = 1) -> Date {
            faker.instant.future(years: years).date
        }
        public mutating func recent(days: Int = 1) -> Date { faker.instant.recent(days: days).date }
        public mutating func soon(days: Int = 1) -> Date { faker.instant.soon(days: days).date }

        public mutating func between(_ start: Date, _ end: Date) -> Date {
            faker.instant.between(Timestamp(start), Timestamp(end)).date
        }

        public mutating func birthdate(minAge: Int = 18, maxAge: Int = 80) -> Date {
            faker.instant.birthdate(minAge: minAge, maxAge: maxAge).date
        }

        public mutating func monthName(abbreviated: Bool = false) -> String {
            faker.instant.monthName(abbreviated: abbreviated)
        }

        public mutating func weekdayName(abbreviated: Bool = false) -> String {
            faker.instant.weekdayName(abbreviated: abbreviated)
        }

        public mutating func timeZone() -> String { faker.instant.timeZone() }
    }

#endif
