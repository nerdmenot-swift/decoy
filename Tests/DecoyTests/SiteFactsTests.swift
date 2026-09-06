import DecoyLocales
import Foundation
import Testing

@testable import Decoy

/// Asserts the factual claims in the hand-written documentation pages.
///
/// The generated reference pages cannot go stale — `website/scripts/extract.ts` derives
/// them by calling the library, and CI diffs the result. The hand-written pages have no
/// such protection, and they are the ones a new reader meets first.
///
/// They had drifted badly. `install.md` told readers the package was not published and to
/// depend on `branch: "main"` — after 1.0.0 was tagged, released and live. It also claimed
/// the corpus held sixty-four locales when it holds sixty-five, and that the built-in stub
/// defines eleven paths when it defines ten. `locales.md` said eight locales carried half a
/// name and named five that had since been given the other half.
///
/// Every one of those was found by reading, which is exactly why they had survived: reading
/// is what nobody does again after the first time. The claims below are the ones that were
/// wrong, restated as assertions so the next drift is a red test.
@Suite("Documentation claims")
struct SiteFactsTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func page(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every hand-written page a reader can reach.
    private static let pages = [
        "README.md",
        "website/src/content/docs/start/install.md",
        "website/src/content/docs/start/quick-start.md",
        "website/src/content/docs/start/cheatsheet.md",
        "website/src/content/docs/guides/locales.md",
        "website/src/content/docs/guides/forges.md",
        "website/src/content/docs/guides/seeds.md",
        "website/src/content/docs/guides/testing.md",
        "website/src/content/docs/guides/seeding-a-database.md",
    ]

    /// The failure that prompted this suite: the site told people 1.0.0 did not exist.
    ///
    /// Phrased as a search for the *claim* rather than for one sentence, because the banner
    /// that was wrong said "Not published yet" and the README said "Status: 1.0 in
    /// progress" — two wordings of one stale fact, and grepping for either would have
    /// missed the other.
    @Test("no page claims the package is unreleased")
    func nothingClaimsUnreleased() throws {
        let claims = [
            "not published", "not tagged", "in progress", "will not resolve",
            "until it is cut", "depend on the branch",
        ]
        var found: [String] = []
        for path in Self.pages {
            let text = try Self.page(path).lowercased()
            for claim in claims where text.contains(claim) {
                found.append("\(path): \"\(claim)\"")
            }
        }
        #expect(
            found.isEmpty,
            """
            \(found.count) page(s) still describe Decoy as unreleased:
                \(found.joined(separator: "\n    "))

            1.0.0 is tagged and published. A page telling a reader to depend on a branch \
            sends them somewhere the release notes do not describe.
            """)
    }

    @Test("the locale counts the prose quotes are the ones that ship")
    func localeCounts() throws {
        let shipping = DecoyLocales.available.filter { $0 != "base" }.count
        let words = ["sixty-three": 63, "sixty-four": 64, "sixty-five": 65, "sixty-six": 66]

        var wrong: [String] = []
        for path in Self.pages {
            // Lowercased, because these words start sentences. The first version of this
            // check was case-sensitive and slept through "Sixty-four compile" — a stale
            // count sitting at the top of a paragraph, which is where they usually sit.
            let text = try Self.page(path).lowercased()
            for (word, value) in words where text.contains(word) && value != shipping {
                // `sixty-six` is legitimate where the sentence counts blobs rather than
                // locales — `base` is a blob and not a locale anybody selects.
                if value == shipping + 1 && text.contains("\(word) locales compile") { continue }
                wrong.append("\(path) says \(word) where \(shipping) locales ship")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.count) stale count(s):\n    \(wrong.joined(separator: "\n    "))")
    }

    /// `install.md` describes the stub by its size, and the size moved.
    @Test("the built-in stub is the size the docs say")
    func builtInSize() throws {
        let text = try Self.page("website/src/content/docs/start/install.md")
        // Counted the way a reader would check it: paths the stub can actually answer.
        let stub = LocaleCorpus.builtIn
        let known = ["person.first_name.female", "person.first_name.male",
                     "person.last_name.generic", "internet.domain_suffix",
                     "internet.example_email", "date.month.wide", "date.month.abbr",
                     "date.weekday.wide", "date.weekday.abbr", "location.time_zone"]
        let present = known.filter { stub.resolve($0) != nil }.count
        #expect(present == 10, "the stub answers \(present) of the ten paths the docs name")
        #expect(
            text.contains("ten paths"),
            "install.md no longer says 'ten paths'; the stub answers \(present)")
    }

    /// The claim that drifted furthest: a list of locales carrying half a name, five of
    /// which had since been given the other half.
    @Test("the half-named locales are the ones the guide names")
    func halfNamedLocales() throws {
        var givenOnly: [String] = []
        var surnameOnly: [String] = []
        for code in DecoyLocales.available where code != "base" {
            let locale = try DecoyLocales.locale(code)
            let given = locale.supplies(.givenNames)
            let surname = locale.supplies(.surnames)
            if given && !surname { givenOnly.append(code) }
            if surname && !given { surnameOnly.append(code) }
        }
        #expect(
            givenOnly == ["en_GB"] && surnameOnly.isEmpty,
            """
            The half-named locales have changed: given-only \(givenOnly.sorted()), \
            surname-only \(surnameOnly.sorted()).
            website/src/content/docs/guides/locales.md names them in prose — update it.
            """)
    }
}
