import Testing

@testable import Decoy

@Suite("Timestamp")
struct TimestampTests {

    /// Pinned against values that can be checked by hand, because every date this
    /// library produces is built on this conversion.
    @Test(
        "civil dates convert to known epoch seconds",
        arguments: [
            (1970, 1, 1, Int64(0)),
            (1970, 1, 2, 86_400),
            (1969, 12, 31, -86_400),
            (2000, 1, 1, 946_684_800),
            (2000, 2, 29, 951_782_400),  // leap day in a century divisible by 400
            (1900, 3, 1, -2_203_891_200),  // 1900 was *not* a leap year
            (2026, 1, 1, 1_767_225_600),
            (2038, 1, 19, 2_147_472_000),  // past the 32-bit cliff
            (2100, 3, 1, 4_107_542_400),  // 2100 is not a leap year either
        ]
    )
    func civilToEpoch(year: Int, month: Int, day: Int, expected: Int64) {
        let stamp = Timestamp(year: year, month: month, day: day)
        #expect(stamp.secondsSinceEpoch == expected)
    }

    @Test(
        "the conversion round-trips",
        arguments: [
            (1970, 1, 1), (1969, 7, 20), (1900, 1, 1), (2000, 2, 29), (2026, 7, 27),
            (2400, 12, 31), (1583, 6, 15),
        ]
    )
    func roundTrip(year: Int, month: Int, day: Int) {
        let civil = Timestamp(year: year, month: month, day: day, hour: 13, minute: 45, second: 7)
            .civil
        #expect(civil.year == year && civil.month == month && civil.day == day)
        #expect(civil.hour == 13 && civil.minute == 45 && civil.second == 7)
    }

    /// Pre-epoch instants are where a truncating division lands a day late.
    @Test("dates before 1970 land on the right day")
    func negativeEpoch() {
        let stamp = Timestamp(secondsSinceEpoch: -1)
        let civil = stamp.civil
        #expect(civil.year == 1969 && civil.month == 12 && civil.day == 31)
        #expect(civil.hour == 23 && civil.minute == 59 && civil.second == 59)
    }

    @Test("every day of a leap year round-trips")
    func leapYearExhaustive() {
        var day = Timestamp(year: 2024, month: 1, day: 1).secondsSinceEpoch
        let end = Timestamp(year: 2025, month: 1, day: 1).secondsSinceEpoch
        var count = 0
        while day < end {
            let civil = Timestamp(secondsSinceEpoch: day).civil
            let rebuilt = Timestamp(year: civil.year, month: civil.month, day: civil.day)
            #expect(rebuilt.secondsSinceEpoch == day, "failed at \(civil)")
            day += 86_400
            count += 1
        }
        #expect(count == 366, "2024 is a leap year")
    }

    @Test(
        "weekday is correct",
        arguments: [
            (1970, 1, 1, 4),  // Thursday
            (2000, 1, 1, 6),  // Saturday
            (2026, 7, 27, 1),  // Monday
            (1969, 7, 20, 0),  // Sunday
        ]
    )
    func weekday(year: Int, month: Int, day: Int, expected: Int) {
        #expect(Timestamp(year: year, month: month, day: day).weekday == expected)
    }

    @Test("ISO 8601 formatting is zero-padded and host-independent")
    func iso8601() {
        #expect(Timestamp(year: 1970, month: 1, day: 1).iso8601 == "1970-01-01T00:00:00Z")
        #expect(
            Timestamp(year: 2026, month: 7, day: 27, hour: 4, minute: 3, second: 9).iso8601
                == "2026-07-27T04:03:09Z"
        )
        #expect(Timestamp(year: 999, month: 12, day: 31).iso8601 == "0999-12-31T00:00:00Z")
    }

    #if canImport(FoundationEssentials) || canImport(Foundation)
        @Test("Foundation bridging round-trips")
        func foundationBridge() {
            let stamp = Timestamp(year: 2026, month: 7, day: 27, hour: 12)
            #expect(Timestamp(stamp.date) == stamp)
            #expect(stamp.date.timeIntervalSince1970 == Double(stamp.secondsSinceEpoch))
        }
    #endif
}

@Suite("Date generation")
struct DateGenerationTests {

    private func faker(_ seed: UInt64 = 1337) -> Faker { Faker(seed: seed) }

    /// The reproducibility property every other faker gets wrong: anchoring to the
    /// system clock means the same seed yields different fixtures tomorrow.
    @Test("generation is anchored to a constant, not the clock")
    func anchoredToReference() {
        var f = faker()
        let past = f.instant.past()
        #expect(past < Timestamp.decoyReference)
        #expect(Timestamp.decoyReference == Timestamp(year: 2026, month: 1, day: 1))

        // Same seed, same value — the point of the exercise.
        var g = faker()
        #expect(g.instant.past() == past)
    }

    @Test("the reference is overridable")
    func customReference() {
        let anchor = Timestamp(year: 1999, month: 6, day: 15)
        var f = Faker(seed: 1, reference: anchor)
        let past = f.instant.past()
        #expect(past < anchor)
        #expect(past > Timestamp(year: 1998, month: 6, day: 14))
    }

    @Test("past and future stay on their own side of the reference")
    func direction() {
        var f = faker()
        for _ in 0..<500 {
            #expect(f.instant.past() < Timestamp.decoyReference)
            #expect(f.instant.future() > Timestamp.decoyReference)
            #expect(f.instant.recent(days: 7) < Timestamp.decoyReference)
            #expect(f.instant.soon(days: 7) > Timestamp.decoyReference)
        }
    }

    @Test("recent stays inside its window")
    func recentWindow() {
        var f = faker()
        let earliest = Timestamp(
            secondsSinceEpoch: Timestamp.decoyReference.secondsSinceEpoch - 7 * 86_400
        )
        for _ in 0..<500 {
            let value = f.instant.recent(days: 7)
            #expect(value >= earliest && value < Timestamp.decoyReference)
        }
    }

    @Test("between honours its bounds and tolerates reversed arguments")
    func between() {
        var f = faker()
        let start = Timestamp(year: 2020, month: 1, day: 1)
        let end = Timestamp(year: 2021, month: 1, day: 1)
        for _ in 0..<500 {
            let value = f.instant.between(start, end)
            #expect(value >= start && value <= end)
            let reversed = f.instant.between(end, start)
            #expect(reversed >= start && reversed <= end)
        }
    }

    @Test("between with identical bounds returns that instant")
    func betweenDegenerate() {
        var f = faker()
        let point = Timestamp(year: 2020, month: 5, day: 5)
        #expect(f.instant.between(point, point) == point)
    }

    /// Ages are computed from the reference, so a "25-year-old" fixture does not
    /// quietly turn 26 the following year.
    @Test("birthdates fall in the requested age range")
    func birthdate() {
        var f = faker()
        for _ in 0..<500 {
            let born = f.instant.birthdate(minAge: 18, maxAge: 65)
            let age = Timestamp.decoyReference.civil.year - born.civil.year
            #expect((17...66).contains(age), "age \(age) outside range")
        }
    }

    @Test("a single-age range is honoured")
    func birthdateExactAge() {
        var f = faker()
        for _ in 0..<100 {
            let born = f.instant.birthdate(minAge: 30, maxAge: 30)
            #expect(born.civil.year == Timestamp.decoyReference.civil.year - 30)
        }
    }

    @Test("month and weekday names come from the corpus")
    func names() {
        var f = faker()
        #expect(!f.instant.monthName().isEmpty)
        #expect(!f.instant.monthName(abbreviated: true).isEmpty)
        #expect(!f.instant.weekdayName().isEmpty)
        #expect(!f.instant.timeZone().isEmpty)
    }

    @Test("dates generated through Forge are reproducible")
    func throughForge() {
        struct Row: Equatable {
            var created = Timestamp(secondsSinceEpoch: 0)
        }
        let forge = Forge<Row>("row") { Row() }.rule(\.created) { $0.instant.past(years: 5) }
        #expect(forge.generate(100, seed: 7) == forge.generate(100, seed: 7))
    }

    @Test("Forge can override the reference instant")
    func forgeReference() {
        struct Row: Equatable {
            var created = Timestamp(secondsSinceEpoch: 0)
        }
        let anchor = Timestamp(year: 1990, month: 1, day: 1)
        let rows = Forge<Row>("row") { Row() }
            .reference(anchor)
            .rule(\.created) { $0.instant.past(years: 1) }
            .generate(50, seed: 3)

        #expect(rows.allSatisfy { $0.created < anchor })
        #expect(rows.allSatisfy { $0.created > Timestamp(year: 1988, month: 12, day: 31) })
    }

    #if canImport(FoundationEssentials) || canImport(Foundation)
        @Test("the Date namespace mirrors the Timestamp one")
        func dateNamespace() {
            var a = faker()
            var b = faker()
            #expect(a.date.past().timeIntervalSince1970 == Double(b.instant.past().secondsSinceEpoch))

            var f = faker()
            #expect(!f.date.monthName().isEmpty)
            #expect(f.date.birthdate(minAge: 20, maxAge: 20).timeIntervalSince1970 > 0)
        }
    #endif
}
