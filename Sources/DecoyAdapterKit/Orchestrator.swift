import Foundation

/// Combines every adapter's contribution into one set of locale definitions.
///
/// The rules came from the JavaScript pipeline and are not restated here beyond what the
/// port had to be careful about. One thing is deliberately *not* carried over: the
/// `fallback` path and `mergeBeneath`, forty lines of subtle "lay this underneath unless
/// something below it is claimed" logic that existed so faker-js could be removed one
/// field at a time. faker is
/// gone and nothing declares `fallback` any more, so porting it would have been porting
/// dead code — and dead code with enough subtlety in it to look load-bearing.
public struct Orchestrator {

    public struct Contribution: Sendable {
        public let id: String
        public let attributeTo: String
        public let isFallback: Bool
        /// locale -> path -> value
        public let contributions: [String: [String: Definition]]
        /// locale -> source id, where an adapter credits per locale rather than per source.
        public let sourceByLocale: [String: String]?

        public init(
            id: String, attributeTo: String, isFallback: Bool,
            contributions: [String: [String: Definition]], sourceByLocale: [String: String]?
        ) {
            self.id = id
            self.attributeTo = attributeTo
            self.isFallback = isFallback
            self.contributions = contributions
            self.sourceByLocale = sourceByLocale
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unknownLocale(adapter: String, code: String)
        case conflict(adapter: String, other: String, claim: String)
        case fallbackUnsupported(adapter: String)

        public var description: String {
            switch self {
            case .unknownLocale(let adapter, let code):
                return "\(adapter) produced locale '\(code)', which is not in the roster"
            case .conflict(let adapter, let other, let claim):
                return "\(adapter) and \(other) both define \(claim)"
            case .fallbackUnsupported(let adapter):
                return
                    "\(adapter) declares itself a fallback, and the fallback merge was not "
                    + "carried into the Swift pipeline because nothing used it once faker-js "
                    + "was removed with faker-js. Reinstate mergeBeneath before relying on it."
            }
        }
    }

    public struct Result: Sendable {
        public let definitions: [String: [String: Definition]]
        /// locale -> path -> source id
        public let attribution: [String: [String: String]]
    }

    public let roster: Set<String>

    public init(roster: Set<String>) { self.roster = roster }

    /// Merges in the order given. Order is the adapters' filename order, which is what
    /// the builder iterates, and it matters only for which of two conflicting adapters is
    /// named first in the error — a conflict is refused rather than resolved.
    public func merge(_ adapters: [Contribution]) throws -> Result {
        var definitions: [String: [String: Definition]] = [:]
        var attribution: [String: [String: String]] = [:]
        var claims = Set<String>()

        for adapter in adapters {
            guard !adapter.isFallback else {
                throw Failure.fallbackUnsupported(adapter: adapter.id)
            }

            for (code, paths) in adapter.contributions.sorted(by: { $0.key < $1.key }) {
                guard roster.contains(code) else {
                    throw Failure.unknownLocale(adapter: adapter.id, code: code)
                }
                definitions[code] = definitions[code] ?? [:]
                attribution[code] = attribution[code] ?? [:]

                for (path, value) in paths.sorted(by: { $0.key < $1.key }) {
                    // Two equal-precedence adapters claiming one path is a decision about
                    // which source wins, and it is made deliberately rather than by
                    // filename order.
                    let claim = "\(code).\(path)"
                    if claims.contains(claim) {
                        throw Failure.conflict(
                            adapter: adapter.id,
                            other: attribution[code]?[path] ?? "another adapter",
                            claim: claim)
                    }
                    claims.insert(claim)

                    var locale = definitions[code] ?? [:]
                    Definitions.mergeOver(&locale, Definitions.nest(path, value))
                    definitions[code] = locale
                    attribution[code]?[path] = adapter.sourceByLocale?[code] ?? adapter.attributeTo
                }
            }
        }
        return Result(definitions: definitions, attribution: attribution)
    }

    /// The fallback chain for a locale: itself, its ancestors, then English, then base.
    ///
    /// Filtered against the roster at the end rather than while building, which matters for
    /// a code whose middle segment is not itself a locale — `en_AU_ocker` keeps `en_AU` and
    /// `en` and drops nothing in between.
    public static func fallbackChain(_ code: String, roster: Set<String>) -> [String] {
        if code == "base" { return ["base"] }

        let parts = code.split(separator: "_").map(String.init)
        var chain: [String] = []
        for count in stride(from: parts.count, through: 1, by: -1) {
            chain.append(parts.prefix(count).joined(separator: "_"))
        }
        if !chain.contains("en") { chain.append("en") }
        chain.append("base")

        var seen = Set<String>()
        return chain.filter { roster.contains($0) && seen.insert($0).inserted }
    }
}
