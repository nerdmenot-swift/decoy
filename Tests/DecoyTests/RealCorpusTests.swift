import Foundation
import Testing

@testable import Decoy

/// Tests against the actual compiled corpus rather than the built-in stub.
///
/// The blobs are build artifacts, not committed, so these are skipped when absent
/// rather than failing. `cd Tools/adapters && node run.mjs`, then
/// `swift run decoy-compile-corpus Tools/adapters/out Corpus/binary --corpus-version 2.0.0`.
///
/// Loading from disk is a stopgap: there is no mechanism yet for embedding a corpus
/// into a built binary without `Bundle.module`.
enum RealCorpus {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Corpus/binary")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("en.decoy").path)
    }

    static func corpus(_ code: String) throws -> Corpus {
        let url = directory.appendingPathComponent("\(code).decoy")
        return try Corpus(bytes: [UInt8](try Data(contentsOf: url)))
    }

    /// Builds a locale with its fallback chain, mirroring what the extractor verified
    /// against faker's own resolution.
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
        #expect(corpus.version == CorpusVersion(major: 8, minor: 0, patch: 0))
    }

    @Test("provenance survives compilation")
    func provenance() throws {
        let corpus = try RealCorpus.corpus("en")
        let table = try #require(
            LocaleCorpus(code: "en", chain: [corpus]).strings("person.first_name.female")
        )
        let source = try #require(try corpus.source(table.sourceID))
        #expect(source.id == "faker-js")
        #expect(source.license == "MIT")
        #expect(source.version == "10.5.0")
        #expect(!source.retrieved.isEmpty, "a retrieval date is the point of provenance")
    }

    @Test("gendered name pools survived the round trip")
    func genderedPools() throws {
        let locale = try RealCorpus.locale("en", chain: ["en", "base"])
        let female = try #require(locale.strings("person.first_name.female"))
        let male = try #require(locale.strings("person.first_name.male"))
        let generic = try #require(locale.strings("person.first_name.generic"))

        #expect(female.count == 473)
        #expect(male.count == 473)
        #expect(generic.count == 2_240)
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

    /// Documents a real coverage gap rather than asserting the data is fine.
    ///
    /// `ta_IN` is a locale with no person names at all, so a Tamil-locale record
    /// currently falls through to English. This test exists to fail loudly on the day
    /// someone fixes it, and to keep the gap visible until then.
    @Test("known gap: ta_IN has no person names")
    func tamilCoverageGap() throws {
        let taIN = try RealCorpus.locale("ta_IN", chain: ["ta_IN", "en", "base"])
        let taOnly = try RealCorpus.locale("ta_IN", chain: ["ta_IN"])

        #expect(
            taOnly.has("person.first_name.female") == false,
            "if this now passes, ta_IN gained names — delete this test"
        )
        // With the chain it silently resolves, which is exactly the problem.
        #expect(taIN.has("person.first_name.female"))
    }

    @Test("every locale compiles to a loadable corpus")
    func allLocalesLoad() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: RealCorpus.directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "decoy" }

        #expect(files.count == 76)
        for file in files {
            let corpus = try Corpus(bytes: [UInt8](try Data(contentsOf: file)))
            #expect(corpus.stringCount > 0, "\(file.lastPathComponent) is empty")
        }
    }
}
