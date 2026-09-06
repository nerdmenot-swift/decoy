import Foundation
import Testing

@testable import DecoyAdapterKit

/// Asserts the numbers in `docs/corpus-strategy.md` against the pipeline they describe.
///
/// That document carries a table of every adapter, its source, its licence and how many
/// locales it fills. It is prose with editorial judgement in it — which register is
/// weighted, which licence had to be read rather than trusted — so it is written by hand
/// rather than generated, and every hand-written number in this repository has eventually
/// been wrong.
///
/// This one was wrong in twelve places at once. It claimed thirty-seven adapters against
/// thirty-nine, `cities` in sixty-seven locales against forty-nine, `wikidata-colours` in
/// twenty-four against forty-two, and it omitted eleven adapters entirely. None of that is
/// carelessness: adding an adapter is a one-line registry change and updating a prose table
/// is not part of it, so the table goes stale by default.
///
/// The fix is the one `SurfaceCountTests` already applies to the generator count. The
/// document stays hand-written, and the numbers in it stop being claims and become
/// assertions — stale means a failing test rather than a confident paragraph.
@Suite("Strategy document")
struct StrategyDocTests {

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    private static var document: String {
        get throws {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent("docs/corpus-strategy.md"),
                encoding: .utf8)
        }
    }

    /// Locales per path, per adapter, from the committed parity dumps.
    ///
    /// The dumps are what each adapter last emitted and are diffed on every build, so they
    /// are the pipeline's own record rather than a second opinion about it.
    private static func localeCounts() throws -> [String: Set<Int>] {
        let directory = repositoryRoot.appendingPathComponent("Tools/adapters/parity")
        var counts: [String: Set<Int>] = [:]

        for file in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            guard
                let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                    as? [String: Any],
                let contributions = root["contributions"] as? [String: Any]
            else { continue }

            var perPath: [String: Int] = [:]
            for (_, paths) in contributions {
                guard let paths = paths as? [String: Any] else { continue }
                for path in paths.keys { perPath[path, default: 0] += 1 }
            }
            // The adapter's own locale total counts too: a row may quote either.
            counts[id] = Set(perPath.values).union([contributions.count])
        }
        return counts
    }

    private static let words: [String: Int] = [
        "thirty-seven": 37, "thirty-eight": 38, "thirty-nine": 39, "forty": 40,
        "forty-one": 41, "forty-two": 42, "fifty-three": 53, "fifty-four": 54,
        "fifty-five": 55, "sixty-four": 64, "sixty-five": 65, "sixty-six": 66,
    ]

    @Test("the adapter and source totals are the ones the pipeline has")
    func headlineTotals() throws {
        let text = try Self.document
        let pattern = /\*\*Built so far\*\* — ([a-z-]+) adapters, ([a-z-]+) sources/
        guard let match = try pattern.firstMatch(in: text) else {
            Issue.record("the 'Built so far' line is gone — this test names it by its text")
            return
        }
        let claimedAdapters = Self.words[String(match.1)]
        let claimedSources = Self.words[String(match.2)]

        let sources = try FileManager.default.contentsOfDirectory(
            at: Self.repositoryRoot.appendingPathComponent("Tools/adapters/sources"),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.count

        #expect(
            claimedAdapters == Adapters.all.count,
            """
            corpus-strategy.md says \(match.1) adapters; the registry has \(Adapters.all.count).
            """)
        #expect(
            claimedSources == sources,
            "corpus-strategy.md says \(match.2) sources; Tools/adapters/sources has \(sources).")
    }

    /// Omission is the failure this catches. Eleven adapters were missing from the table,
    /// and a missing row reads as "this data has no source" to anybody auditing licences.
    @Test("every adapter in the registry appears in the table")
    func noAdapterIsUndocumented() throws {
        // The *first cell* of a row, not the row and not the document. Both looser checks
        // were written and both passed a deliberately broken table: `wikidata-places` is
        // named in the `cities` row's explanation, so "appears in the document" and
        // "appears in some row" were each satisfied by prose while the row itself was gone.
        // The claim being tested is that the adapter has a row of its own, so the test has
        // to look where a row's identity lives.
        var documented: Set<String> = []
        for line in try Self.document.split(whereSeparator: \.isNewline)
        where line.hasPrefix("| `") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count > 1 else { continue }
            // One cell may list several — the authored adapters share a row.
            for id in cells[1].matches(of: /`([a-z0-9-]+)`/) { documented.insert(String(id.1)) }
        }
        let missing = Adapters.all.map(\.adapterID).filter { !documented.contains($0) }.sorted()

        #expect(
            missing.isEmpty,
            """
            \(missing.count) adapter(s) are in the registry and not in corpus-strategy.md:
                \(missing.joined(separator: ", "))

            A missing row reads as "this data came from nowhere" to somebody auditing \
            where the corpus got its values.
            """)
    }

    /// Every `in N locales` claim, checked against what that adapter actually filled.
    @Test("no row claims more locales than its adapter fills")
    func localeClaimsAreTrue() throws {
        let text = try Self.document
        let counts = try Self.localeCounts()
        var wrong: [String] = []

        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("| `") {
            let row = String(line)
            guard let idMatch = try /^\| `([a-z0-9-]+)`/.firstMatch(in: row) else { continue }
            let id = String(idMatch.1)
            guard let valid = counts[id] else { continue }  // a narrative row, not an adapter

            for claim in row.matches(of: /in ([0-9]+)(?:–([0-9]+))? locales/) {
                for number in [claim.1, claim.2].compactMap({ $0 }).compactMap({ Int($0) })
                where !valid.contains(number) {
                    wrong.append(
                        "\(id) claims \(number) locales; it fills "
                            + valid.sorted().map(String.init).joined(separator: "/"))
                }
            }
        }

        #expect(
            wrong.isEmpty,
            """
            \(wrong.count) locale count(s) in corpus-strategy.md do not match the pipeline:
                \(wrong.joined(separator: "\n    "))

            The parity dumps are the source of truth — update the document, not this test.
            """)
    }
}
