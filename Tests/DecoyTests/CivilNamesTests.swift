import Testing

@testable import Decoy

/// Tests French given names, which come from the civil registry rather than from faker.
///
/// The first locale whose names are sourced the way English surnames are: from the office
/// that records the births, with the real frequencies attached. It is the proof that the
/// mechanism works, and the shape every other country has to follow one at a time.
@Suite(
    "Civil registry names",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct CivilNamesTests {

    private func french() throws -> LocaleCorpus {
        try RealCorpus.locale("fr", chain: ["fr", "en", "base"])
    }

    @Test("French given names come from INSEE, not from a fallback")
    func sourced() throws {
        let locale = try french()
        for (path, expected) in [
            ("person.first_name.female", 5_000), ("person.first_name.male", 4_000),
        ] {
            let table = try #require(locale.strings(path))
            #expect(
                table.count > expected,
                "\(path) has \(table.count) names — expected the INSEE list, not faker's"
            )
        }
    }

    /// Weighted, which is the reason to use a registry rather than any list of names.
    ///
    /// Marie and Jean are the commonest names France has recorded since 1900 by a wide
    /// margin, so a weighted draw has to reach them far more often than a uniform one
    /// would. A fixture set with a flat name distribution makes deduplication logic look
    /// flawless because real collision rates never occur.
    @Test("the draw follows real French frequencies")
    func weighted() throws {
        var faker = Faker(seed: 1337, locale: try french())
        var counts: [String: Int] = [:]
        for _ in 0..<20_000 {
            counts[faker.person.firstName(.female), default: 0] += 1
        }
        let marie = counts["Marie"] ?? 0
        #expect(marie > 200, "Marie appeared \(marie) times in 20,000 — expected many more")

        let top = counts.max { $0.value < $1.value }?.key
        #expect(top == "Marie", "the commonest French given name should dominate, got \(top ?? "-")")
    }

    @Test("names are title-cased, not the registry's upper case")
    func titleCased() throws {
        var faker = Faker(seed: 99, locale: try french())
        for _ in 0..<500 {
            let name = faker.person.firstName()
            #expect(name == name.capitalized || name.contains("-") || name.contains(" "),
                "'\(name)' is not in title case")
            #expect(name.first?.isUppercase == true, "'\(name)' does not start capitalised")
            #expect(name != name.uppercased(), "'\(name)' is still in registry upper case")
        }
    }

    /// Compound names have to capitalise after the hyphen, which a naive title-case misses.
    @Test("hyphenated names capitalise both parts")
    func hyphenated() throws {
        let locale = try french()
        let table = try #require(locale.strings("person.first_name.female"))
        let names = (0..<table.count).compactMap { try? table.string(at: $0) }
        let hyphenated = names.filter { $0.contains("-") }
        #expect(hyphenated.count > 100, "expected many compound French names")
        for name in hyphenated.prefix(200) {
            for part in name.split(separator: "-") {
                #expect(
                    part.first?.isUppercase == true,
                    "'\(name)' has a lower-case part after the hyphen"
                )
            }
        }
    }

    /// INSEE's residual buckets are not names and must not reach the corpus.
    @Test("the rare-names bucket is excluded")
    func residualBucketExcluded() throws {
        let locale = try french()
        for path in ["person.first_name.female", "person.first_name.male"] {
            let table = try #require(locale.strings(path))
            let names = (0..<table.count).compactMap { try? table.string(at: $0) }
            #expect(
                !names.contains { $0.hasPrefix("_") },
                "a residual bucket reached \(path)"
            )
        }
    }

    /// The model retrains on whatever wins the merge, so French novel names should now be
    /// learned from INSEE rather than from faker's much smaller list.
    @Test("the French model learned from the registry")
    func modelRetrained() throws {
        let locale = try french()
        guard case .model(let model)? = locale.resolve("person.first_name_model.female") else {
            Issue.record("fr should have a given-name model")
            return
        }
        // faker gave French a few hundred names; INSEE gives thousands, and a model over
        // thousands has visibly more contexts.
        #expect(model.contextCount > 500, "only \(model.contextCount) contexts — trained on what?")

        var faker = Faker(seed: 7, locale: locale, novelNames: true)
        let table = try #require(locale.strings("person.first_name.female"))
        let real = Set((0..<table.count).compactMap { try? table.string(at: $0) })
        for _ in 0..<1_000 {
            #expect(!real.contains(faker.person.firstName(.female)))
        }
    }
}
