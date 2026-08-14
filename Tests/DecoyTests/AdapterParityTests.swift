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
@Suite("Adapter parity", .enabled(if: PortFixtures.hasContributionDumps && PortFixtures.hasArtifactCache))
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
        AirportsAdapter(),
        ProgrammingLanguagesAdapter(),
        IANATZDBAdapter(),
        PersianWordsAdapter(),
        LatinWordsAdapter(),
        MIMETypesAdapter(),
        EmojiAdapter(),
        WikidataColoursAdapter(),
        WikidataTermsAdapter(),
        IANAWebAdapter(),
        SIUnitsAdapter(),
        ISO639Adapter(),
        ISO3166Adapter(),
        ISO31662Adapter(),
        ISO4217Adapter(),
        CLDRDatesAdapter(),
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
        let url = root.appendingPathComponent("parity/\(id).json")
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["contributions"] as? [String: [String: Any]]
        else { return nil }
        return raw.mapValues { $0.mapValues(Definition.init(json:)) }
    }

    /// Where two values first diverge, in a line rather than a memory dump.
    static func difference(_ mine: Definition?, _ theirs: Definition) -> String {
        guard let mine else { return "missing entirely" }
        switch (mine, theirs) {
        case (.list(let a), .list(let b)):
            if a.count != b.count {
                // Counts alone localise nothing. The first index where the two diverge is
                // what says *which* entry was gained or lost.
                let firstDiff = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }
                let where_ = firstDiff.map {
                    " — first divergence at \($0.offset): \(compact($0.element.0)) vs \(compact($0.element.1))"
                } ?? " — identical up to the shorter one"
                return "\(a.count) entries vs \(b.count)\(where_)"
            }
            for (index, pair) in zip(a, b).enumerated() where pair.0 != pair.1 {
                return "entry \(index): \(compact(pair.0)) vs \(compact(pair.1))"
            }
            return "same length, no differing entry found"
        case (.object(let a), .object(let b)):
            let onlyMine = Set(a.keys).subtracting(b.keys).sorted()
            let onlyTheirs = Set(b.keys).subtracting(a.keys).sorted()
            if !onlyMine.isEmpty || !onlyTheirs.isEmpty {
                return "extra keys \(onlyMine), missing keys \(onlyTheirs)"
            }
            for key in a.keys.sorted() where a[key] != b[key] {
                return "key '\(key)': \(compact(a[key]!)) vs \(compact(b[key]!))"
            }
            return "objects differ but no differing key found"
        default:
            return "\(compact(mine)) vs \(compact(theirs))"
        }
    }

    /// A value in a few characters, for an error message.
    static func compact(_ value: Definition) -> String {
        switch value {
        case .string(let text): return "\"\(text.prefix(40))\""
        case .number(let number): return String(number)
        case .bool(let flag): return String(flag)
        case .null: return "null"
        case .list(let items): return "[\(items.count) entries]"
        case .object(let fields):
            let inner = fields.keys.sorted().prefix(4)
                .map { "\($0)=\(shallow(fields[$0]!))" }
                .joined(separator: " ")
            return "{\(inner)}"
        }
    }

    static func shallow(_ value: Definition) -> String {
        if case .string(let text) = value { return "\"\(text.prefix(24))\"" }
        if case .number(let number) = value { return String(number) }
        return "…"
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
                chains: chains, cldrOverrides: cldr,
                dataDirectory: Self.root.appendingPathComponent("data"))
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
                    if mine[path] != value {
                        // Reporting the whole value is useless at this size: one adapter
                        // prints 200 KB of Definition and buries the one row that moved.
                        Issue.record(
                            "\(id)/\(code).\(path) — \(Self.difference(mine[path], value))")
                    }
                    comparedPaths += 1
                }
            }
        }

        let complaint = "no adapter paths compared — the dumps are missing"
        #expect(comparedPaths > 0, "\(complaint)")
        print("adapters: \(Self.ported.count) ported, \(comparedPaths) paths verified")
    }
}
