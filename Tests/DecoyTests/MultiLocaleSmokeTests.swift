import Testing

@testable import Decoy

/// Runs every generator against every shipped locale, not just English.
///
/// `GeneratorSmokeTests` calls all 192 methods, and calls all of them against `en`. That
/// is the locale most likely to work, because it is the one every fallback chain ends at
/// — so the suite is blind to exactly the failures that matter most. Japanese street
/// addresses came out empty and nothing noticed, because no test ever asked Japanese for
/// one.
///
/// Deliberately shaped as "call it, assert it produced something" rather than as
/// per-locale expectations. A locale-specific assertion would need somebody who reads the
/// language to write it; a non-empty result is checkable by anybody and catches the whole
/// class of bug this missed.
@Suite(
    "Every locale",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct MultiLocaleSmokeTests {

    /// The three human-language locales that ship as Swift modules — `base` is the
    /// fourth module but is language-neutral data rather than something to generate
    /// people from. Exercised through the on-disk blobs so this suite and
    /// `RealCorpusTests` agree about what they are testing.
    static let shipped = ["en", "de", "ja"]

    /// Every generator that returns a `String` and has no required arguments.
    ///
    /// Grouped by namespace so a failure names one, and kept as closures so adding a
    /// generator here is the same one-line edit as adding it to the smoke suite.
    static func allGenerators() -> [(String, (inout Faker) -> String)] {
        [
            ("person.firstName", { $0.person.firstName() }),
            ("person.firstName(.female)", { $0.person.firstName(.female) }),
            ("person.firstName(.male)", { $0.person.firstName(.male) }),
            ("person.lastName", { $0.person.lastName() }),
            ("person.fullName", { $0.person.fullName() }),
            ("person.sex", { $0.person.sex() }),
            ("person.jobTitle", { $0.person.jobTitle() }),
            ("person.bio", { $0.person.bio() }),
            ("person.ssn", { $0.person.ssn() }),
            ("person.bloodType", { $0.person.bloodType() }),
            ("location.city", { $0.location.city() }),
            ("location.streetName", { $0.location.streetName() }),
            ("location.streetAddress", { $0.location.streetAddress() }),
            ("location.streetAddress(full:)", { $0.location.streetAddress(full: true) }),
            ("location.postalAddress", { $0.location.postalAddress() }),
            ("location.country", { $0.location.country() }),
            ("location.timeZone", { $0.location.timeZone() }),
            // Both namespaces read one path now, so both have to be exercised.
            ("date.timeZone", { $0.date.timeZone() }),
            ("company.name", { $0.company.name() }),
            ("company.catchPhrase", { $0.company.catchPhrase() }),
            ("commerce.productName", { $0.commerce.productName() }),
            ("commerce.productDescription", { $0.commerce.productDescription() }),
            ("commerce.department", { $0.commerce.department() }),
            ("commerce.price", { $0.commerce.price() }),
            ("finance.iban", { $0.finance.iban() }),
            ("finance.creditCardNumber", { $0.finance.creditCardNumber() }),
            ("finance.currencyName", { $0.finance.currencyName() }),
            ("finance.transactionDescription", { $0.finance.transactionDescription() }),
            ("internet.email", { $0.internet.email() }),
            ("internet.username", { $0.internet.username() }),
            ("internet.url", { $0.internet.url() }),
            ("internet.userAgent", { $0.internet.userAgent() }),
            ("internet.emoji", { $0.internet.emoji() }),
            ("internet.domainName", { $0.internet.domainName() }),
            ("word.noun", { $0.word.noun() }),
            ("word.verb", { $0.word.verb() }),
            ("word.adjective", { $0.word.adjective() }),
            ("lorem.word", { $0.lorem.word() }),
            ("lorem.sentence", { $0.lorem.sentence() }),
            ("lorem.paragraph", { $0.lorem.paragraph() }),
            ("lorem.slug", { $0.lorem.slug() }),
            ("color.human", { $0.color.human() }),
            ("color.hex", { $0.color.hex() }),
            ("vehicle.vin", { $0.vehicle.vin() }),
            ("system.fileName", { $0.system.fileName() }),
            ("system.mimeType", { $0.system.mimeType() }),
            ("system.semver", { $0.system.semver() }),
            ("science.unit", { $0.science.unit()["name"] ?? "" }),
            ("airline.airline", { $0.airline.airline()["name"] ?? "" }),
            ("crypto.ethereumAddress", { $0.crypto.ethereumAddress() }),
            ("phone.number", { $0.phone.number() }),
            ("phone.imei", { $0.phone.imei() }),
            ("uuidV7", { $0.uuidV7() }),
        ]
    }

    @Test("every generator produces a value in every shipped locale", arguments: shipped)
    func everyGenerator(_ code: String) throws {
        let chain = code == "en" ? ["en", "base"] : [code, "en", "base"]
        var faker = Faker(seed: 20_260_808, locale: try RealCorpus.locale(code, chain: chain))

        for (label, generator) in Self.allGenerators() {
            let value = generator(&faker)
            #expect(!value.isEmpty, "\(code): \(label) produced an empty string")
            #expect(
                value.first != " " && value.last != " ",
                "\(code): \(label) has a leading or trailing space — '\(value)'"
            )
            #expect(!value.contains("{{"), "\(code): \(label) leaked a template — '\(value)'")
        }
    }

    /// The wider sweep: not just the ones with modules, but every compiled blob.
    ///
    /// Cheaper than it looks — one pass per locale, and it is the only thing standing
    /// between a locale nobody has heard of and a trap on first use.
    @Test("no shipped locale traps on any generator")
    func everyLocale() throws {
        let codes = try RealCorpus.availableCodes()
        try #require(codes.count > 60, "expected the full locale set, found \(codes.count)")

        for code in codes where code != "base" {
            let chain = code == "en" ? ["en", "base"] : [code, "en", "base"]
            guard let locale = try? RealCorpus.locale(code, chain: chain) else { continue }
            var faker = Faker(seed: 4242, locale: locale)
            for (label, generator) in Self.allGenerators() {
                // Reaching the end without trapping is most of the assertion. An empty
                // result is legitimate here in a way it is not above: a locale may
                // declare a field explicitly empty, which is data rather than a fault.
                let value = generator(&faker)
                #expect(!value.contains("{{"), "\(code): \(label) leaked a template")
                // Checked across all seventy-six rather than the three above, because
                // the doubled space that shipped came from `en` and every locale
                // inherited it.
                #expect(!value.contains("  "), "\(code): \(label) has a doubled space")
            }
        }
    }

    /// A generator that always returns the same value passes every other test here.
    ///
    /// This suite asserts that a call produces something, and the bug it missed produced
    /// something every time: `Faker(locale: ja).person.firstName()` returned `葵` for all
    /// five hundred seeds, because faker's `first_name.generic` is a list of names used
    /// for *either* gender rather than the general pool, and Japanese had exactly one.
    /// Twenty-nine locales carried such a list and eight were collapsed to a single name,
    /// with thousands of gendered names sitting unread beside them.
    ///
    /// So variety is its own assertion — measured against the names the locale *holds*,
    /// not against a fixed number.
    ///
    /// A constant threshold cannot express this. Set high, it fails Maldivian for having
    /// fourteen male given names, which is a gap in the world's open data rather than a
    /// fault in the code. Set low enough to pass Maldivian, it would have passed Japanese
    /// returning one name out of five thousand. The defect is always a *ratio*: the draw
    /// reaching far less than the locale has.
    ///
    /// So the expectation is the smaller of twenty and the pool — where "the pool" is the
    /// largest one the draw could legitimately use, which for an ungendered call is the
    /// gendered lists together rather than whichever list it happened to pick. That is
    /// what makes the collapse visible: Japanese had 5,240 names to reach and reached one.
    @Test("no locale's names collapse to less than it holds")
    func namesVary() throws {
        let codes = try RealCorpus.availableCodes()

        for code in codes where code != "base" {
            let chain = code == "en" ? ["en", "base"] : [code, "en", "base"]
            guard let locale = try? RealCorpus.locale(code, chain: chain) else { continue }

            func size(_ path: String) -> Int { locale.strings(path)?.count ?? 0 }

            // An ungendered draw may use `generic`, but the gendered lists are what the
            // locale actually holds — so a tiny `generic` beside large gendered pools is
            // measured against the large ones, which is the whole point.
            for field in ["first_name", "last_name"] {
                let generic = size("person.\(field).generic")
                let female = size("person.\(field).female")
                let male = size("person.\(field).male")
                let cases: [(String, Int, (inout Faker) -> String)] = [
                    ("\(field)()", max(generic, female + male), {
                        field == "first_name" ? $0.person.firstName() : $0.person.lastName()
                    }),
                    // A gendered draw uses the gendered list and only falls back to
                    // `generic` when there is none, so that is what it is measured
                    // against. Taking the larger of the two would fail Azerbaijani for
                    // drawing its ten real female surnames instead of the eighty-two
                    // ungendered ones sitting beside them, which is correct behaviour:
                    // Azerbaijani surnames inflect, and -ova is not interchangeable with -ov.
                    ("\(field)(.female)", female > 0 ? female : generic, {
                        field == "first_name"
                            ? $0.person.firstName(.female) : $0.person.lastName(.female)
                    }),
                    ("\(field)(.male)", male > 0 ? male : generic, {
                        field == "first_name"
                            ? $0.person.firstName(.male) : $0.person.lastName(.male)
                    }),
                ]

                for (label, pool, draw) in cases where pool > 0 {
                    var seen = Set<String>()
                    for seed in 0..<200 {
                        var faker = Faker(seed: UInt64(seed), locale: locale)
                        seen.insert(draw(&faker))
                    }
                    let expected = min(20, pool)
                    let complaint =
                        "\(code): \(label) produced \(seen.count) distinct values over 200 "
                        + "seeds from a pool of \(pool) — \(seen.sorted().prefix(4))"
                    #expect(seen.count >= expected, "\(complaint)")
                }
            }
        }
    }
}
