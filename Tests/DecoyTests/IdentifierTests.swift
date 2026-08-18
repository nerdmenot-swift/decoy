import Testing

@testable import Decoy

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

@Suite("Identifiers")
struct IdentifierTests {

    private func faker(seed: UInt64 = 1337, index: Int = 0) -> Faker {
        Faker(seed: seed, index: index, locale: .builtIn)
    }

    @Test("v4 has the canonical shape")
    func v4Shape() {
        var f = faker()
        let value = f.uuid()

        #expect(value.count == 36)
        #expect(value.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12])
        #expect(value.allSatisfy { $0 == "-" || $0.isHexDigit })
        #expect(value.lowercased() == value, "canonical UUIDs are lowercase")
    }

    @Test("v4 sets the version and variant bits")
    func v4Bits() {
        var f = faker()
        for _ in 0..<200 {
            let value = f.uuid()
            let groups = value.split(separator: "-")
            #expect(groups[2].first == "4", "version nibble must be 4, got \(value)")
            #expect(
                "89ab".contains(groups[3].first!),
                "variant nibble must be 8-b, got \(value)"
            )
        }
    }

    @Test("v7 sets its own version and variant bits")
    func v7Bits() {
        var f = faker()
        for _ in 0..<200 {
            let value = f.uuidV7()
            let groups = value.split(separator: "-")
            #expect(groups[2].first == "7", "version nibble must be 7, got \(value)")
            #expect("89ab".contains(groups[3].first!))
        }
    }

    // The whole reason this type exists: Foundation's UUID() would fail this.
    @Test("the same seed produces the same identifier")
    func deterministic() {
        var a = faker()
        var b = faker()
        #expect(a.uuid() == b.uuid())
        #expect(a.uuidV7() == b.uuidV7())
    }

    @Test("different seeds produce different identifiers")
    func seedsDiffer() {
        var a = faker(seed: 1)
        var b = faker(seed: 2)
        #expect(a.uuid() != b.uuid())
    }

    @Test("successive draws differ and do not repeat")
    func noRepeats() {
        var f = faker()
        let values = (0..<1_000).map { _ in f.uuid() }
        #expect(Set(values).count == values.count, "the stream repeated a UUID")
    }

    @Test("v7 identifiers sort in row order")
    func v7Ordering() {
        // Row independence means row 5 is the same value whether generated alone or as
        // part of a run, so the ordering property has to hold across separate Fakers.
        let values = (0..<50).map { index -> String in
            var f = faker(index: index)
            return f.uuidV7()
        }
        #expect(values == values.sorted(), "v7 must be lexicographically time-ordered")
    }

    @Test("v7 timestamps derive from the reference, not the clock")
    func v7UsesReference() {
        var f = Faker(seed: 1337, locale: .builtIn, reference: Timestamp(year: 2000, month: 1, day: 1))
        let value = f.uuidV7()

        let hex = value.split(separator: "-").prefix(2).joined()
        let milliseconds = Int64(hex, radix: 16)!
        #expect(milliseconds / 1_000 == Timestamp(year: 2000, month: 1, day: 1).secondsSinceEpoch)
    }

    #if canImport(FoundationEssentials) || canImport(Foundation)
        @Test("the Foundation projection matches the string form")
        func foundationProjection() {
            var a = faker()
            var b = faker()
            #expect(a.uuidValue().uuidString.lowercased() == b.uuid())

            var c = faker()
            var d = faker()
            #expect(c.uuidV7Value().uuidString.lowercased() == d.uuidV7())
        }
    #endif
}
