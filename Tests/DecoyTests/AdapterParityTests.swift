import Foundation
import Testing

@testable import DecoyAdapterKit

/// Every ported adapter against the JavaScript's output for the same artifacts.
///
/// The harness is the point. Each adapter's contribution was dumped to
/// `out/contributions/<id>.json` before any of them were ported, so a ported adapter is
/// checked against what its predecessor actually produced rather than against a
/// re-description of what it was supposed to produce. Adding an adapter to `ported` below
/// is the whole of wiring it up.
///
/// A dump that is missing fails the suite rather than skipping it: an adapter that quietly
/// verifies nothing is worse than one that is not ported yet, because it looks done.
@Suite("Adapter parity")
struct AdapterParityTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters")

    /// Ported adapters, checked against their dumps.
    private static let ported: [any Adapter] = [
        IANATLDAdapter(),
        OccupationsAdapter(),
        PeriodicTableAdapter(),
        USSurnamesAdapter(),
    ]

    private static func roster() -> (locales: [String], cldr: [String: String?]) {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("locales.json")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let codes = object["locales"] as? [String]
        else { return ([], [:]) }

        var overrides: [String: String?] = [:]
        if let cldr = object["cldr"] as? [String: Any] {
            for (key, value) in cldr { overrides[key] = value as? String }
        }
        return (codes, overrides)
    }

    /// The artifacts an adapter's sources unpacked to, as `lib/sources.mjs` named them.
    private static func artifacts(for adapter: any Adapter) throws -> [String: URL] {
        let store = ArtifactStore(root: root)
        var found: [String: URL] = [:]

        for sourceID in type(of: adapter).sources {
            let descriptorURL = root.appendingPathComponent("sources/\(sourceID).json")
            let descriptor = try JSONDecoder().decode(
                SourceDescriptor.self, from: Data(contentsOf: descriptorURL))

            for artifact in descriptor.artifacts ?? [] {
                let cached = store.cacheDirectory
                    .appendingPathComponent("\(sourceID)-\(artifact.cacheSuffix)")
                // An archive was unpacked beside its download, under the artifact's name.
                let unpacked = store.cacheDirectory
                    .appendingPathComponent("\(sourceID)-\(artifact.name)")
                found[artifact.name] = artifact.isArchive ? unpacked : cached
            }
        }
        return found
    }

    private static func dump(_ id: String) -> [String: [String: Definition]]? {
        let url = root.appendingPathComponent("out/contributions/\(id).json")
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["contributions"] as? [String: [String: Any]]
        else { return nil }
        return raw.mapValues { $0.mapValues(Definition.init(json:)) }
    }

    @Test("every ported adapter reproduces its dump exactly")
    func parity() throws {
        let (locales, cldr) = Self.roster()
        guard !locales.isEmpty else {
            Issue.record("no roster — Tools/adapters/locales.json did not parse")
            return
        }
        var chains: [String: [String]] = [:]
        for code in locales {
            chains[code] = Orchestrator.fallbackChain(code, roster: Set(locales))
        }

        var comparedPaths = 0
        for adapter in Self.ported {
            let id = type(of: adapter).id
            guard let expected = Self.dump(id) else {
                Issue.record(
                    "no dump for \(id) — run `node Tools/adapters/dump-contributions.mjs`")
                continue
            }

            let input = AdapterInput(
                artifacts: try Self.artifacts(for: adapter), locales: locales,
                chains: chains, cldrOverrides: cldr)
            let produced = try adapter.run(input).contributions

            #expect(
                Set(produced.keys) == Set(expected.keys),
                "\(id): contributes to different locales")

            for (code, paths) in expected.sorted(by: { $0.key < $1.key }) {
                let mine = produced[code] ?? [:]
                #expect(
                    Set(mine.keys) == Set(paths.keys),
                    "\(id)/\(code): different paths")

                for (path, value) in paths.sorted(by: { $0.key < $1.key }) {
                    #expect(mine[path] == value, "\(id)/\(code).\(path)")
                    comparedPaths += 1
                }
            }
        }

        let complaint = "no adapter paths compared — the dumps are missing"
        #expect(comparedPaths > 0, "\(complaint)")
        print("adapters: \(Self.ported.count) ported, \(comparedPaths) paths verified")
    }
}
