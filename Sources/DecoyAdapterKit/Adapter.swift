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
    /// Some sources are queried rather than downloaded — Wikidata answers SPARQL and the
    /// statistical offices answer PxWeb, and a query is not a file with a hash — so the
    /// result is fetched deliberately by `decoy-fetch`, reviewed, and committed. That makes
    /// the build reproducible without pretending a live endpoint is a pinned artifact.
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

/// What one filter removed, and from what.
///
/// Every serious data bug this corpus has had was a filter discarding quietly. A minimum
/// length written for Latin script deleted 138 of 143 Korean surnames; a minimum count of
/// forty threw away thirteen Welsh ones; a retry that read throttling as a dead endpoint
/// meant Spanish surnames were never once fetched. None left a trace, because a filter
/// records only what survived — and five survivors look exactly like a small language.
///
/// Recorded per adapter, per scope, per filter, and written to `Tools/adapters/filters.json`
/// where a diff makes a change in behaviour visible. `kept 5 of 143` on a line nobody reads
/// is better than nothing; the same in a file CI diffs is what would actually have caught it.
public struct DiscardRecord: Sendable {
    /// The locale or language the filter was applied to.
    public let scope: String
    /// Which filter, named for what it rejects rather than how it works.
    public let filter: String
    public let kept: Int
    public let seen: Int

    public init(scope: String, filter: String, kept: Int, seen: Int) {
        self.scope = scope
        self.filter = filter
        self.kept = kept
        self.seen = seen
    }

    public var dropped: Int { seen - kept }
}

public struct AdapterOutput: Sendable {
    /// locale -> path -> value
    public let contributions: [String: [String: Definition]]
    /// Reported on the run's summary line, so a silent change of shape is visible.
    public let stats: [(String, String)]
    /// Where an adapter credits per locale rather than crediting one source for all.
    public let sourceByLocale: [String: String]?
    /// What this adapter's filters removed on the way.
    public let discarded: [DiscardRecord]

    public init(
        contributions: [String: [String: Definition]],
        stats: [(String, String)] = [],
        sourceByLocale: [String: String]? = nil,
        discarded: [DiscardRecord] = []
    ) {
        self.contributions = contributions
        self.stats = stats
        self.sourceByLocale = sourceByLocale
        self.discarded = discarded
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

    /// Which sources this *instance* reads, for the same handful.
    ///
    /// Instance rather than static for a reason that cost a wrong attribution: the three
    /// authored-list adapters share a type but not an upstream — `common-knowledge` is its
    /// own descriptor with its own licence and URL, while the other two are `decoy-authored`
    /// — so a static let credited 76 English paths to the wrong source and left
    /// `common-knowledge` out of the manifest, and therefore out of NOTICE, entirely.
    var adapterSources: [String] { get }
}

extension Adapter {
    public static var attributeTo: String? { nil }
    public var adapterID: String { Self.id }
    public var adapterSources: [String] { Self.sources }
}
