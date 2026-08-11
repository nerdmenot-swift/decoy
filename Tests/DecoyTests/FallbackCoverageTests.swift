import Testing

@testable import Decoy
@testable import DecoyLocaleDE
@testable import DecoyLocaleEN
@testable import DecoyLocaleJA

/// Tests the signal that tells a caller their locale is mostly somebody else's data.
///
/// `decoy-inspect --coverage` has measured this since the gate was built, but only for
/// whoever runs the inspector. A user who imports `DecoyLocaleTA_IN` and generates a
/// million rows has no way to learn that eleven fields are Tamil and the rest are
/// English — which is the "Tamil records named Jennifer Williams" failure, arriving
/// silently.
@Suite("Fallback coverage")
struct FallbackCoverageTests {

    /// A two-corpus chain: a thin front locale behind a full one.
    private func chained(ownPaths: Int) -> LocaleCorpus {
        var parent = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let parentSource = parent.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: "")
        for i in 0..<10 {
            parent.index(
                "person.field\(i)",
                stringTable: parent.addStringTable(["value"], source: parentSource))
        }

        var child = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let childSource = child.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: "")
        for i in 0..<ownPaths {
            child.index(
                "person.field\(i)",
                stringTable: child.addStringTable(["eigen"], source: childSource))
        }

        // Three corpora, so the last one is treated as the language-neutral tail the way
        // a real chain's `base` is.
        var neutral = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let neutralSource = neutral.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: "")
        for i in 0..<500 {
            neutral.index(
                "system.mime\(i)",
                stringTable: neutral.addStringTable(["x"], source: neutralSource))
        }

        return LocaleCorpus(
            code: "xx",
            chain: [
                try! Corpus(bytes: child.build()),
                try! Corpus(bytes: parent.build()),
                try! Corpus(bytes: neutral.build()),
            ]
        )
    }

    @Test("coverage is the share of language-bearing paths the locale defines itself")
    func coverage() throws {
        #expect(try chained(ownPaths: 10).nativeCoverage == 1.0)
        #expect(try chained(ownPaths: 5).nativeCoverage == 0.5)
        #expect(try chained(ownPaths: 0).nativeCoverage == 0.0)
    }

    /// The bug this denominator exists to avoid.
    ///
    /// Counting everything the chain resolves put Japanese at 5%, because `base` carries
    /// 1,016 media-type paths and there is no Japanese answer to `image/png`. A coverage
    /// number that moves when someone adds media types is not measuring the language.
    @Test("the language-neutral tail is not counted against the locale")
    func neutralTailExcluded() throws {
        let locale = chained(ownPaths: 5)
        #expect(try locale.paths.count > 500, "the tail really is most of the chain")
        #expect(
            try locale.languageBearingPathCount == 10,
            "only the parent's fields are things a locale could supply"
        )
    }

    @Test("inheritedPaths names what is missing, not just how much")
    func inherited() throws {
        let inherited = try chained(ownPaths: 7).inheritedPaths
        #expect(inherited == ["person.field7", "person.field8", "person.field9"])
    }

    @Test("the warning fires below the threshold and stays quiet above it")
    func warning() {
        #expect(chained(ownPaths: 1).fallbackWarning() != nil)
        #expect(chained(ownPaths: 9).fallbackWarning() == nil)
        // The default threshold is 0.3, and the boundary belongs to the passing side.
        #expect(chained(ownPaths: 3).fallbackWarning() == nil)
        #expect(chained(ownPaths: 2).fallbackWarning() != nil)
    }

    @Test("the warning names the locale and says where to look")
    func warningContent() throws {
        let message = try #require(chained(ownPaths: 1).fallbackWarning())
        #expect(message.contains("'xx'"))
        #expect(message.contains("10%"))
        #expect(message.contains("decoy-inspect"))
    }

    /// A single-corpus chain has no fallback, so it cannot be mostly fallback.
    @Test("a chain with nothing behind it never warns")
    func noChain() {
        #expect(LocaleCorpus.builtIn.fallbackWarning() == nil)
    }

    @Test("the shipped locales are above the threshold")
    func shippedLocales() throws {
        for (code, locale) in [
            ("en", DecoyLocaleEN.locale), ("de", DecoyLocaleDE.locale),
            ("ja", DecoyLocaleJA.locale),
        ] {
            let warning = locale.fallbackWarning()
            #expect(warning == nil, "\(code): \(warning ?? "")")
        }
    }

    /// The assertion this API is shaped for, written the way a user would write it.
    ///
    /// The threshold is a caller's judgement rather than a quality bar, and the number
    /// here is chosen to sit below where the shipped non-English locales actually land.
    ///
    /// It moved down twice, both times because English-only content was added rather than
    /// because a locale lost anything, and the third time it would have moved the reasoning
    /// was reversed instead. `LocaleCorpus.bearsLanguage` now excludes the invented
    /// namespaces, on the grounds that its own contract is *a field a locale could
    /// translate* and an invented pub name is not one. Japanese went from 28% to 46%
    /// without gaining a byte, which is the measure of how much the old denominator was
    /// distorting.
    ///
    /// The threshold has stayed at 0.3 since, and the value of leaving it there is that it
    /// now means something: a locale below it really is mostly somebody else's language,
    /// rather than mostly this library's jokes.
    ///
    /// A ceiling still exists, and it is smaller than it was. Job descriptors, department
    /// names and marketing adjectives remain English-only and still count, because those
    /// *are* fields a locale could translate and no registry has. So no locale but English
    /// reaches 100%, and a threshold set as though one could would still be wrong.
    @Test("a caller can assert on coverage in their own tests")
    func usableAsAnAssertion() throws {
        #expect(try DecoyLocaleJA.locale.nativeCoverage > 0.3)
    }
}
