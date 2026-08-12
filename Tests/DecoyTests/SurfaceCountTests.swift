import Foundation
import Testing

@testable import Decoy

/// Pins the size of the public generator surface, so the documented number cannot drift.
///
/// It had drifted three times — the README said 191, `corpus-strategy.md` said 191, and
/// the real figure was 192. Nobody was careless: adding a generator is a one-line change
/// and updating two prose files is not part of it, so the numbers go stale by default.
///
/// This makes them go stale *loudly*. Adding a generator fails this test, and the fix is
/// to update the literal here and the two documents it names — which is the point.
@Suite("Public surface")
struct SurfaceCountTests {

    private static let generatorDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/Decoy/Generators")

    /// Counts `public func` and `public mutating func` inside each `*Faker` namespace.
    ///
    /// Source text rather than reflection, because Decoy carries no reflection at all —
    /// it was removed deliberately, and reintroducing `Mirror` in a test would make the
    /// test the only thing in the package that needs it.
    private static func namespaceMethods() throws -> [String: Int] {
        var counts: [String: Int] = [:]

        for file in try FileManager.default.contentsOfDirectory(
            at: generatorDirectory, includingPropertiesForKeys: nil
        ) where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            var namespace: String?

            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if let name = Self.namespaceName(declaredIn: trimmed) {
                    namespace = name
                    counts[name] = counts[name] ?? 0
                    continue
                }
                guard let current = namespace else { continue }
                if trimmed.hasPrefix("public func ") || trimmed.hasPrefix("public mutating func ") {
                    counts[current, default: 0] += 1
                }
            }
        }
        return counts
    }

    private static func namespaceName(declaredIn line: String) -> String? {
        guard line.hasPrefix("public struct "), line.hasSuffix("Faker {") else { return nil }
        return String(line.dropFirst("public struct ".count).dropLast(" {".count))
    }

    @Test("the generator surface is the size the documentation claims")
    func generatorCount() throws {
        let counts = try Self.namespaceMethods()
        let total = counts.values.reduce(0, +)

        // 28 namespaces and 315 methods. `DateFaker` is compiled only where Foundation
        // is, so a build without it has 20 and 209 — both figures are in the README and
        // in docs/corpus-strategy.md, and both have to move together.
        //
        // It went down rather than up for the first time when `cityPrefix()` and
        // `citySuffix()` were retired: nothing composed a city out of parts any more, so
        // they returned fragments that filled no column.
        //
        // This has already earned its keep three times: `postcode(state:)`,
        // `stateAndPostcode()` and `placeAndPostcode()` each failed it on the way in,
        // which is the whole point.
        #expect(
            counts.count == 28,
            "namespaces: expected 21, found \(counts.count) — \(counts.keys.sorted())"
        )
        #expect(
            total == 315,
            """
            generator methods: expected 227, found \(total).
            If that is intentional, update this literal, README.md and \
            docs/corpus-strategy.md together — they have drifted apart three times.
            Per namespace: \(counts.sorted { $0.key < $1.key })
            """
        )

        let withoutDate = total - (counts["DateFaker"] ?? 0)
        #expect(withoutDate == 297, "without Foundation: expected 209, found \(withoutDate)")
    }

    /// The corpus suites skip rather than fail when the blobs are absent, which is right
    /// — they are build artifacts and a fresh clone has none. But thirty-plus tests
    /// skipping quietly makes a green run look like a full one.
    @Test("a run without a compiled corpus says so")
    func corpusPresenceIsVisible() {
        if !RealCorpus.isAvailable {
            // Not a failure. `swift test` prints this once, and a green run that skipped
            // the integration suites is then distinguishable from one that did not.
            print(
                """

                ────────────────────────────────────────────────────────────────────
                NO COMPILED CORPUS — the integration suites did not run.

                Roughly a third of this package's tests are gated on Corpus/binary,
                which is a build artifact and is not committed. This run exercised
                the ten-path built-in stub instead.

                    node Tools/adapters/run.mjs
                    swift run decoy-compile-corpus Tools/adapters/out Corpus/binary

                ────────────────────────────────────────────────────────────────────

                """
            )
        }
        #expect(Bool(true))
    }
}
