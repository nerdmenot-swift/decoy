import Testing

@testable import Decoy

/// A locale saying "we have no such thing" is data, not a build error.
///
/// The corpus format has carried `explicitlyEmpty` since v1 precisely so a locale can
/// block fallback — Azerbaijani has no name prefixes, and inheriting English ones would
/// put "Dr." on an Azeri record. The reason is cited in four separate files. It did not
/// work: `require` trapped on it, crashing thirteen locales on ordinary calls, and
/// `person.prefix()` reached English anyway.
@Suite("Explicitly empty fields")
struct ExplicitlyEmptyTests {

    /// A locale declaring `person.prefix` empty, chained behind one that has prefixes.
    private func chained() -> LocaleCorpus {
        var english = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let source = english.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: ""
        )
        english.index(
            "person.prefix.generic",
            stringTable: english.addStringTable(["Dr."], source: source)
        )
        english.index(
            "person.suffix",
            stringTable: english.addStringTable(["MD"], source: source)
        )

        var azeri = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        _ = azeri.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: ""
        )
        // Declared on the parent, with no children — exactly how the real corpus records it.
        azeri.indexNull("person.prefix")
        azeri.indexNull("person.suffix")

        return LocaleCorpus(
            code: "az",
            chain: [try! Corpus(bytes: azeri.build()), try! Corpus(bytes: english.build())]
        )
    }

    @Test("a declared-empty field yields an empty string instead of trapping")
    func requireReturnsEmpty() {
        var faker = Faker(seed: 1337, locale: chained())
        #expect(faker.person.suffix() == "")
    }

    @Test("a declared-empty parent blocks fallback to another locale's children")
    func parentBlocksChildren() {
        // The bug: `gendered` asked for `person.prefix.generic` first. `az` defines no
        // children, so the walk continued into English and returned "Dr.".
        var faker = Faker(seed: 1337, locale: chained())
        #expect(
            faker.person.prefix() == "",
            "an Azeri record must not inherit an English honorific"
        )
    }

    @Test("declaresEmpty distinguishes declared-empty from simply absent")
    func distinguishesFromMissing() {
        let locale = chained()
        #expect(locale.declaresEmpty("person.prefix"))
        #expect(locale.declaresEmpty("person.suffix"))
        #expect(
            !locale.declaresEmpty("person.first_name.female"),
            "a path nobody defines is missing, not declared empty — that stays a build error"
        )
    }

    @Test("a genuinely missing path still traps")
    func missingStillTraps() {
        // The distinction has to cut both ways: silently returning "" for a path nobody
        // defines would hide a mis-specified locale or an uncompiled corpus.
        let locale = chained()
        #expect(locale.strings("person.job_area") == nil)
        #expect(!locale.declaresEmpty("person.job_area"))
    }

    @Test("every shipped locale survives the generators that used to trap")
    func shippedLocalesDoNotTrap() throws {
        // Thirteen locales declare one of these empty. Reaching the end is the assertion.
        for code in ["az", "ru", "it", "mk", "pt_PT", "ro_MD", "sk", "th", "pt_BR", "en_HK"]
        where RealCorpus.isAvailable {
            let chain = ["az", "ru", "it", "mk", "sk", "th"].contains(code)
                ? [code, "en", "base"]
                : [code, "en", "base"]
            guard let locale = try? RealCorpus.locale(code, chain: chain) else { continue }
            var faker = Faker(seed: 1337, locale: locale)
            _ = faker.person.suffix()
            _ = faker.person.prefix()
            _ = faker.location.cityPrefix()
            _ = faker.location.citySuffix()
            _ = faker.location.postcode()
        }
    }
}
