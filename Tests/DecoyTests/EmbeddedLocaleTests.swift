import DecoyLocaleDE
import DecoyLocaleEN
import DecoyLocaleJA
import Testing

@testable import Decoy

/// Exercises corpora compiled *into* the binary.
///
/// Unlike `RealCorpusTests` these need no files on disk and no gate — which is the
/// entire point. A published library cannot ask its users to run the corpus pipeline,
/// and `Bundle.module` is the platform-fragile mechanism this design set out to
/// avoid.
@Suite("Embedded locales")
struct EmbeddedLocaleTests {

    @Test("an embedded corpus loads with no filesystem access")
    func loadsFromBinary() {
        let corpus = DecoyLocaleEN.corpus
        #expect(corpus.stringCount > 12_000)
        #expect(corpus.version == DeclaredCorpusVersion.value)
    }

    @Test("generation works straight out of the box")
    func generation() throws {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        // The whole table, not a fixed count of it. Hard-coding 473 pinned the size of
        // faker's given-name list, so replacing it with 18,387 registry names made a test
        // about "does the module work at all" fail on names that were perfectly valid.
        let table = try #require(DecoyLocaleEN.locale.strings("person.first_name.female"))
        let pool = Set((0..<table.count).compactMap { try? table.string(at: $0) })
        #expect(pool.count > 1_000, "the embedded module should carry the full list")

        for _ in 0..<200 {
            #expect(pool.contains(faker.person.firstName(.female)))
        }
    }

    /// The chain is assembled from separately compiled modules, so this proves the
    /// per-locale targets actually link together rather than each carrying a copy.
    @Test("German falls back through English to base")
    func germanChain() throws {
        let locale = DecoyLocaleDE.locale
        #expect(locale.code == "de")
        #expect(locale.chain.count == 3, "de -> en -> base")

        // Names come from `de` itself — Wikidata's German list, which is smaller than the
        // one it replaced. That is the trade the source change makes: 449 names that can be
        // pointed at a licence, rather than 573 that cannot.
        let german = try #require(locale.strings("person.first_name.female"))
        #expect(german.count == 449)

        // Country codes live only in `base`, two hops away.
        let countries = try #require(locale.composite("location.country_code"))
        #expect(countries.rowCount == 260, "every officially assigned ISO 3166-1 code")
    }

    @Test("locales produce locale-appropriate data")
    func localeSpecificOutput() {
        var german = Faker(seed: 42, locale: DecoyLocaleDE.locale)
        var english = Faker(seed: 42, locale: DecoyLocaleEN.locale)
        #expect(german.person.fullName() != english.person.fullName())

        // Japanese should come back in Japanese script, not romanised or English.
        var japanese = Faker(seed: 7, locale: DecoyLocaleJA.locale)
        var sawNonASCII = false
        for _ in 0..<50 where japanese.person.lastName().unicodeScalars.contains(where: {
            $0.value > 127
        }) {
            sawNonASCII = true
        }
        #expect(sawNonASCII, "ja surnames should use Japanese script")
    }

    @Test("embedded corpora carry their provenance")
    func provenance() throws {
        let table = try #require(DecoyLocaleEN.locale.strings("person.first_name.female"))
        let source = try #require(try DecoyLocaleEN.corpus.source(table.sourceID))
        #expect(source.id == "gender-by-name")
        #expect(source.license == "CC-BY-4.0")
        #expect(source.version == "591")
    }

    @Test("an embedded locale drives Forge end to end")
    func throughForge() {
        struct Customer: Equatable {
            var name = ""
            var email = ""
            var city = ""
        }

        let forge = Forge<Customer>("customer") { Customer() }
            .locale(DecoyLocaleDE.locale)
            .rule(\.name) { $0.person.fullName() }
            .rule(\.email) { $0.internet.email() }
            .rule(\.city) { $0.location.city() }

        let rows = forge.generate(100, seed: 1337)
        #expect(rows.count == 100)
        #expect(rows.allSatisfy { !$0.name.isEmpty && !$0.city.isEmpty })
        #expect(rows.allSatisfy { $0.email.contains("@") })
        #expect(Set(rows.map(\.name)).count > 90, "names should vary")
        #expect(forge.generate(100, seed: 1337) == rows, "and still be reproducible")
    }

    /// Each module decodes its payload exactly once; repeated access must not repeat
    /// the work, or every draw would pay for a 296 KB base64 decode.
    @Test("the decoded corpus is shared, not rebuilt per access")
    func decodedOnce() {
        // Comparing `stringCount` across two accesses proved nothing: a computed
        // property that re-decoded 296 KB on every call would return the same count and
        // pass, which is exactly the regression this test is named for.
        //
        // The byte buffer's address is the evidence. `Corpus` is a struct, so two
        // accesses of a `static let` are copies — but the `[UInt8]` inside is
        // copy-on-write, so both copies share one buffer and report one address.
        // Re-decoding allocates a fresh array, and the addresses diverge.
        let first = DecoyLocaleEN.corpus.byteBufferAddress
        let second = DecoyLocaleEN.corpus.byteBufferAddress
        #expect(
            first == second,
            "the payload is being decoded per access — make `corpus` a `static let`"
        )
    }
}
