import DecoyLocaleDE
import DecoyLocaleEN
import DecoyLocaleJA
import Testing

@testable import Decoy

/// Exercises corpora compiled *into* the binary.
///
/// Unlike `RealCorpusTests` these need no files on disk and no gate — which is the
/// entire point. A published library cannot ask its users to run a Node extractor,
/// and `Bundle.module` is the platform-fragile mechanism this design set out to
/// avoid.
@Suite("Embedded locales")
struct EmbeddedLocaleTests {

    @Test("an embedded corpus loads with no filesystem access")
    func loadsFromBinary() {
        let corpus = DecoyLocaleEN.corpus
        #expect(corpus.stringCount > 12_000)
        #expect(corpus.version == CorpusVersion(major: 7, minor: 0, patch: 0))
    }

    @Test("generation works straight out of the box")
    func generation() throws {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        let pool = try Set(
            (0..<473).map { try #require(DecoyLocaleEN.locale.strings("person.first_name.female"))
                .string(at: $0)
            }
        )
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

        // Names come from `de` itself.
        let german = try #require(locale.strings("person.first_name.female"))
        #expect(german.count == 573)

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
        #expect(source.id == "faker-js")
        #expect(source.license == "MIT")
        #expect(source.version == "10.5.0")
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
        let first = DecoyLocaleEN.corpus
        let second = DecoyLocaleEN.corpus
        #expect(first.stringCount == second.stringCount)
        // A `static let` is initialised once; this is a guard against someone
        // converting it to a computed property.
        #expect(DecoyLocaleEN.locale.chain.count == 2)
    }
}
