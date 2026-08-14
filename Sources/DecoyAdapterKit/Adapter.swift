import Foundation

/// What an adapter is handed and what it gives back.
///
/// One adapter reads one upstream's artifacts and returns paths it claims for particular
/// locales. It never sees another adapter's output and never resolves a chain itself —
/// merge and precedence belong to `Orchestrator`, so an adapter cannot accidentally decide
/// which source wins.
public struct AdapterInput: Sendable {
    /// Artifact name to the file or directory it unpacked to.
    public let artifacts: [String: URL]
    /// The roster, in order.
    public let locales: [String]
    /// Each locale's fallback chain, derived once and handed down.
    public let chains: [String: [String]]
    /// Decoy code to CLDR code, where the automatic rule gets it wrong. A null value means
    /// the locale has no CLDR equivalent and CLDR-sourced adapters should skip it.
    public let cldrOverrides: [String: String?]
    /// `Tools/adapters/data`, holding committed snapshots.
    ///
    /// Two sources are queried rather than downloaded — Wikidata answers SPARQL, and a
    /// query is not a file with a hash — so the result is fetched deliberately by a
    /// separate script, reviewed, and committed. That makes the build reproducible without
    /// pretending a live endpoint is a pinned artifact.
    public let dataDirectory: URL

    public init(
        artifacts: [String: URL], locales: [String], chains: [String: [String]],
        cldrOverrides: [String: String?], dataDirectory: URL
    ) {
        self.artifacts = artifacts
        self.locales = locales
        self.chains = chains
        self.cldrOverrides = cldrOverrides
        self.dataDirectory = dataDirectory
    }

    /// An artifact by name, or a readable failure naming the adapter that wanted it.
    public func artifact(_ name: String, for adapter: String) throws -> URL {
        guard let url = artifacts[name] else {
            throw AdapterFailure.missingArtifact(adapter: adapter, name: name)
        }
        return url
    }
}

public struct AdapterOutput: Sendable {
    /// locale -> path -> value
    public let contributions: [String: [String: Definition]]
    /// Reported on the run's summary line, so a silent change of shape is visible.
    public let stats: [(String, String)]
    /// Where an adapter credits per locale rather than crediting one source for all.
    public let sourceByLocale: [String: String]?

    public init(
        contributions: [String: [String: Definition]],
        stats: [(String, String)] = [],
        sourceByLocale: [String: String]? = nil
    ) {
        self.contributions = contributions
        self.stats = stats
        self.sourceByLocale = sourceByLocale
    }
}

public enum AdapterFailure: Error, CustomStringConvertible {
    case missingArtifact(adapter: String, name: String)
    case shapeChanged(adapter: String, detail: String)

    public var description: String {
        switch self {
        case .missingArtifact(let adapter, let name):
            return "\(adapter): no artifact named '\(name)' — check the source descriptor"
        case .shapeChanged(let adapter, let detail):
            return "\(adapter): \(detail)"
        }
    }
}

/// One upstream, converted.
///
/// The sanity thresholds each adapter carries are not defensive padding. An upstream that
/// changes format usually still parses — into two rows, or into the header repeated a
/// thousand times — and a corpus built from that passes every structural check while being
/// worthless. Failing on an implausible count is the only thing that catches it.
public protocol Adapter: Sendable {
    static var id: String { get }
    /// Every source it reads. Several adapters combine two.
    static var sources: [String] { get }
    /// Which source the tables are credited to, when it reads more than one.
    static var attributeTo: String? { get }

    func run(_ input: AdapterInput) throws -> AdapterOutput

    /// Which adapter this *instance* is, for the handful that stand in for several.
    ///
    /// Defaults to the type's id, which is right for every adapter reading one upstream.
    /// AuthoredListsAdapter is one type serving three ids, because the three differ only
    /// in which data file they read and writing three identical types to satisfy a static
    /// would be ceremony.
    var adapterID: String { get }
}

extension Adapter {
    public static var attributeTo: String? { nil }
    public var adapterID: String { Self.id }
}
