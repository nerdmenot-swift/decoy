import DecoyLocales
import Foundation
import Testing

@testable import Decoy

/// Coverage is answerable from the library, not only from a table in the repository.
///
/// A user choosing a locale wants to know whether it will produce names in their language
/// before they ship fixtures built on it. That was previously discoverable only by reading
/// `docs/locale-support.md`, which meant the answer lived outside the thing being asked
/// about — and nothing stopped the table and the corpus disagreeing.
@Suite("Locale coverage")
struct LocaleCoverageTests {

    /// The claim the API exists to support: ask before you depend on it.
    @Test("a locale reports which fields it answers for itself")
    func suppliesReportsNativeFields() throws {
        let hindi = try DecoyLocales.locale("hi_IN")
        #expect(hindi.supplies(.givenNames), "hi_IN carries Devanagari given names")
        #expect(hindi.supplies(.surnames))
        #expect(!hindi.supplies(.streets), "no locale but a handful carries street names")

        let english = try DecoyLocales.locale("en")
        for field in LocaleField.allCases {
            #expect(english.supplies(field), "en should supply \(field.title) itself")
        }
    }

    /// `supplies` asks the locale, not the chain.
    ///
    /// `de_AT` generates German names — through `de`, which is the point of the chain — but
    /// it does not carry them. Reporting `true` would make the answer useless for deciding
    /// where data comes from, which is the only reason to ask.
    @Test("inherited data is not reported as native")
    func inheritanceIsNotOwnership() throws {
        let austrian = try DecoyLocales.locale("de_AT")
        #expect(!austrian.supplies(.givenNames), "de_AT inherits German names rather than carrying them")
        #expect(austrian.supplies(.postcodes), "but its own postcodes are its own")

        // And the composed name is German regardless, because the chain still resolves.
        var faker = Faker(seed: 1337, locale: austrian)
        #expect(!faker.person.fullName().isEmpty)
    }

    /// The three fields no locale but English is expected to carry are excluded from the
    /// tier, or the top of the scale would be unreachable for everybody.
    @Test("English-only fields do not count against other locales")
    func englishOnlyExcludedFromTier() throws {
        for field in LocaleField.englishOnly {
            #expect(!LocaleField.achievable.contains(field))
        }
        #expect(LocaleField.achievable.count == LocaleField.allCases.count - 3)

        // A locale reaching `complete` has everything achievable, while still reporting
        // `false` for the English-only three — so the tier is not quietly counting them.
        let spanish = try DecoyLocales.locale("es")
        #expect(spanish.tier == .complete)
        #expect(!spanish.supplies(.jobTitles))
    }

    @Test("nativeFields agrees with supplies")
    func nativeFieldsAgrees() throws {
        for code in DecoyLocales.available where code != "base" {
            let locale = try DecoyLocales.locale(code)
            let listed = Set(locale.nativeFields)
            let asked = Set(LocaleField.allCases.filter(locale.supplies))
            #expect(listed == asked, "\(code): nativeFields and supplies disagree")
        }
    }

    /// The published table is generated from this API, so they cannot drift — and this is
    /// what says so rather than trusting that they were generated together.
    @Test("the published matrix matches what the library reports")
    func matrixMatchesTheAPI() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/locale-support.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = text.split(separator: "\n").filter { $0.hasPrefix("| `") }
        try #require(!rows.isEmpty, "no table rows in docs/locale-support.md")

        var checked = 0
        for row in rows {
            let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2 else { continue }
            let code = cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            guard DecoyLocales.available.contains(code) else { continue }
            let locale = try DecoyLocales.locale(code)

            #expect(cells[1] == locale.tier.rawValue, "\(code): table says tier \(cells[1])")
            for (index, field) in LocaleField.allCases.enumerated() {
                let published = cells[index + 2] == "✓"
                #expect(
                    published == locale.supplies(field),
                    "\(code) \(field.title): table says \(cells[index + 2])")
            }
            checked += 1
        }
        #expect(checked == DecoyLocales.available.count - 1, "base has no row; every other locale should")
    }

    /// The bar a locale has to clear to be in the roster at all.
    ///
    /// The roster used to be a list somebody maintained, inherited from faker-js, which is
    /// how `en_BORK` and `en_AU_ocker` sat in it carrying thirteen and twenty-six paths of
    /// their own and no names in any language. Declaring the bar and letting a test enforce
    /// it means a locale is present because data supports it, not because it was there
    /// yesterday.
    ///
    /// Two different bars, because the two kinds of locale earn their place differently:
    ///
    /// - a **language root** has to carry its own given names *and* surnames. A root that
    ///   inherits both generates another language under its own name, which is the one
    ///   outcome a locale must never produce.
    /// - a **regional variant** may inherit its names — `de_AT` should generate German
    ///   names, that is what the chain is for — but has to add *something* material of its
    ///   own. A variant that adds nothing is an alias, and an alias is better spelled as
    ///   one.
    ///
    /// This passes today for all sixty-six. It is here so that it keeps passing.
    @Test("every locale in the roster earns its place")
    func rosterMeetsTheBar() throws {
        // What counts as material for a regional variant: the fields where a country
        // genuinely differs from its language's parent.
        let material: [LocaleField] = [
            .givenNames, .surnames, .cities, .streets, .postcodes, .addresses, .phoneNumbers,
            .subdivisions,
        ]

        var failures: [String] = []
        for code in DecoyLocales.available where code != "base" {
            let locale = try DecoyLocales.locale(code)

            if code.contains("_") {
                if !material.contains(where: locale.supplies) {
                    failures.append(
                        "\(code) is a regional variant that adds nothing of its own — it is an "
                            + "alias for its parent and should be spelled as one")
                }
            } else {
                if !locale.supplies(.givenNames) || !locale.supplies(.surnames) {
                    failures.append(
                        "\(code) is a language root without its own "
                            + (locale.supplies(.givenNames) ? "surnames" : "given names")
                            + " — it would generate another language under its own name")
                }
            }
        }

        #expect(
            failures.isEmpty,
            """
            \(failures.count) locale(s) do not clear the roster bar:
                \(failures.joined(separator: "\n    "))

            Either find the data, or drop the locale from Tools/adapters/locales.json.
            """
        )
    }
}
