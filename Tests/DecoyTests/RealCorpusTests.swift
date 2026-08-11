import Foundation
import Testing

@testable import Decoy

/// Tests against the actual compiled corpus rather than the built-in stub.
///
/// The blobs are build artifacts, not committed, so these are skipped when absent
/// rather than failing:
///
///     cd Tools/adapters && node run.mjs
///     swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
///
/// The version comes from `Tools/adapters/corpus-version.json`, so there is no flag to
/// get wrong — an earlier revision of this comment documented a version that produced a
/// corpus failing the assertion twenty lines below it.
///
/// Loading from disk is what makes these tests span all sixty-four locales. Shipping
/// code does not do this — `DecoyLocaleEN` and its siblings embed their corpus as a
/// base64 `StaticString`, so a built binary carries no files. Only four locales have
/// modules, and reading the blobs directly is how the other sixty get tested.
enum RealCorpus {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Corpus/binary")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("en.decoy").path)
    }

    /// Every locale with a compiled blob on disk.
    static func availableCodes() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".decoy") }
            .map { String($0.dropLast(6)) }
            .sorted()
    }

    static func corpus(_ code: String) throws -> Corpus {
        let url = directory.appendingPathComponent("\(code).decoy")
        return try Corpus(bytes: [UInt8](try Data(contentsOf: url)))
    }

    /// Builds a locale with its fallback chain, mirroring what the faker-js adapter
    /// verifies against faker's own resolution on every run.
    static func locale(_ code: String, chain: [String]) throws -> LocaleCorpus {
        LocaleCorpus(code: code, chain: try chain.map { try corpus($0) })
    }
}

@Suite(
    "Compiled corpus",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct RealCorpusTests {

    @Test("the English corpus loads and is substantial")
    func englishLoads() throws {
        let corpus = try RealCorpus.corpus("en")
        #expect(corpus.stringCount > 12_000, "en should carry over 12k distinct strings")
        #expect(corpus.version == DeclaredCorpusVersion.value)
    }

    @Test("provenance survives compilation")
    func provenance() throws {
        let corpus = try RealCorpus.corpus("en")
        let table = try #require(
            LocaleCorpus(code: "en", chain: [corpus]).strings("person.first_name.female")
        )
        let source = try #require(try corpus.source(table.sourceID))
        #expect(source.id == "gender-by-name")
        #expect(source.license == "CC-BY-4.0")
        #expect(source.version == "591")
        #expect(!source.retrieved.isEmpty, "a retrieval date is the point of provenance")
    }

    @Test("gendered name pools survived the round trip")
    func genderedPools() throws {
        let locale = try RealCorpus.locale("en", chain: ["en", "base"])
        let female = try #require(locale.strings("person.first_name.female"))
        let male = try #require(locale.strings("person.first_name.male"))

        #expect(female.count > 15_000)
        #expect(male.count > 10_000)

        // No `generic` pool, and its absence is the assertion. This used to pin 2,240 —
        // faker's list of names used for *either* gender, which is not what Decoy means
        // by `generic`. Decoy reads `generic` as the pool to draw from when the caller
        // named no gender, and prefers it over the gendered lists, so importing the one
        // as the other made `firstName()` draw from 2,240 names instead of 30,000 here
        // and from exactly one in Japanese. See `withoutUnisexSubset` in the adapter.
        #expect(
            locale.strings("person.first_name.generic") == nil,
            "a locale with gendered pools should not also carry a unisex subset as `generic`"
        )
    }

    @Test("generating from the real corpus produces varied, correct names")
    func generation() throws {
        let locale = try RealCorpus.locale("en", chain: ["en", "base"])
        let female = try #require(locale.strings("person.first_name.female"))
        let pool = Set(try (0..<female.count).map { try female.string(at: $0) })

        var faker = Faker(seed: 1337, locale: locale)
        var produced = Set<String>()
        for _ in 0..<500 { produced.insert(faker.person.firstName(.female)) }

        #expect(produced.isSubset(of: pool))
        #expect(produced.count > 200, "500 draws from 473 names should be well spread")
    }

    /// The chain is resolved at lookup, not baked in at compile time, so `de_AT`
    /// inherits from `de` without carrying a copy of it.
    @Test("fallback reaches through the chain")
    func fallbackChain() throws {
        let deAT = try RealCorpus.locale("de_AT", chain: ["de_AT", "de", "en", "base"])
        // `country_code` lives only in `base`, three hops down the chain.
        let countries = try #require(deAT.composite("location.country_code"))
        #expect(countries.rowCount == 260, "ISO 3166-1 officially assigned count")
        #expect(try countries.fieldName(0) == "alpha2")

        // And a whole row stays internally consistent.
        var rng = Xoshiro256StarStar(seed: 5)
        let row = try #require(try countries.drawRow(using: &rng))
        #expect(row["alpha2"]?.count == 2 && row["alpha3"]?.count == 3)
    }

    @Test("weighted name patterns kept their weights")
    func weightedPatterns() throws {
        let locale = try RealCorpus.locale("ar", chain: ["ar", "en", "base"])
        let patterns = try #require(locale.strings("person.name"))
        #expect(patterns.hasWeights, "faker ships weighted name patterns for ar")
        let weights = try (0..<patterns.count).map { try patterns.weight(at: $0) }
        #expect(weights.contains { $0 != weights[0] }, "weights should not all be equal")
    }

    /// The invariant that replaced a documented gap.
    ///
    /// This used to be a test asserting `ta_IN` had no person names, kept so the gap stayed
    /// visible. The roster cut removed `ta_IN` and eleven others on exactly that criterion,
    /// so the gap is now empty and can be enforced instead of merely recorded.
    ///
    /// A *language root* is a locale with no same-language ancestor to inherit from, so
    /// whatever it does not supply comes from English. A root with no names of its own
    /// generates English people wearing its postcode — the "Tamil records named Jennifer
    /// Williams" failure the fallback-coverage gate exists to catch, and the one thing a
    /// caller cannot discover from the type system.
    ///
    /// Regional variants are deliberately exempt: `en_US` and `de_AT` supply no names
    /// either, but they inherit from `en` and `de`, which is their own language.
    ///
    /// Surnames alone satisfy this — `vi`, `zh_CN`, `zh_TW`, `id_ID` and `yo_NG` supply
    /// those and inherit given names. That mixing is a known wart, not a silent one.
    @Test("every language root supplies personal names of its own")
    func everyLanguageRootHasNames() throws {
        let codes = try RealCorpus.availableCodes().filter { $0 != "base" }
        let roster = Set(codes)
        let roots = codes.filter { code in
            let language = String(code.prefix(while: { $0 != "_" }))
            return language == code || !roster.contains(language)
        }

        #expect(roots.count > 30, "sanity: the root set should be most of the roster")

        for code in roots {
            let own = try RealCorpus.locale(code, chain: [code])
            let hasNames =
                own.has("person.first_name.female") || own.has("person.first_name.male")
                || own.has("person.last_name.generic") || own.has("person.last_name.male")
                || own.has("person.last_name.female")
            #expect(
                hasNames,
                """
                '\(code)' is a language root with no personal names of its own, so every \
                person it generates is English. Either give it a name source or drop it \
                from Tools/adapters/locales.json — see the roster comment there.
                """
            )
        }
    }

    @Test("every locale compiles to a loadable corpus")
    func allLocalesLoad() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: RealCorpus.directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "decoy" }

        #expect(files.count == 64)
        for file in files {
            let corpus = try Corpus(bytes: [UInt8](try Data(contentsOf: file)))
            #expect(corpus.stringCount > 0, "\(file.lastPathComponent) is empty")
        }
    }
}
