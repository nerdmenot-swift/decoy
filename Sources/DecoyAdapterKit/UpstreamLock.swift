import Foundation

/// What each pinned artifact *said* last time somebody looked, and what was decided about
/// it.
///
/// The descriptors hold the byte pin, which is the contract with the upstream. This holds
/// the two things the byte pin cannot express: the digest of everything the file states
/// (see `ContentView`), and the record of a human having accepted a change to it. Kept
/// beside the descriptors rather than inside them because a descriptor is written by hand
/// and this file is written by `decoy-repin` — mixing the two would mean a tool rewriting
/// the prose somebody wrote about why a source is trustworthy.
///
/// Committed, because the whole point is that an acceptance is auditable: the digest it
/// accepted, the day, and a sentence saying what moved.
public struct UpstreamLock: Sendable {

    /// One artifact's recorded state.
    public struct Entry: Sendable, Equatable {
        /// The content-view digest, and the recipe that produced it.
        public var content: String
        public var view: String
        /// The byte digest seen when `content` was recorded. The descriptor's `integrity`
        /// is the pin; this is a note of what the bytes looked like at that moment, so a
        /// run can tell "the pin is stale but the content is unchanged" from "nobody has
        /// ever looked at this".
        public var bytes: String
        public var reviewedAt: String?
        public var note: String?

        public init(
            content: String, view: String, bytes: String, reviewedAt: String? = nil,
            note: String? = nil
        ) {
            self.content = content
            self.view = view
            self.bytes = bytes
            self.reviewedAt = reviewedAt
            self.note = note
        }
    }

    /// A data change that has been seen, understood, and deliberately not adopted yet.
    ///
    /// Deferring is legitimate — the corpus is a curated snapshot and adopting a retired
    /// TLD mid-cycle moves everybody's fixtures for no benefit — but only if the deferral
    /// is written down and expires. An entry past `expires` fails the check, so "we will
    /// do it at the next refresh" cannot quietly become "we never did".
    public struct Deferral: Sendable, Equatable {
        public var source: String
        public var firstSeen: String
        public var expires: String
        public var reason: String
        /// The value-level change being deferred, as the builder reported it.
        public var change: [String]

        public init(
            source: String, firstSeen: String, expires: String, reason: String, change: [String]
        ) {
            self.source = source
            self.firstSeen = firstSeen
            self.expires = expires
            self.reason = reason
            self.change = change
        }
    }

    public var entries: [String: Entry]
    public var deferrals: [String: Deferral]

    public init(entries: [String: Entry] = [:], deferrals: [String: Deferral] = [:]) {
        self.entries = entries
        self.deferrals = deferrals
    }

    /// `<source>/<artifact>`, which is how an artifact is addressed everywhere else too.
    public static func key(source: String, artifact: String) -> String { "\(source)/\(artifact)" }

    // MARK: - On disk

    public static let filename = "upstream-lock.json"

    public static func load(from directory: URL) throws -> UpstreamLock {
        let file = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: file) else { return UpstreamLock() }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UpstreamLock()
        }

        var entries: [String: Entry] = [:]
        for (key, value) in (root["artifacts"] as? [String: [String: Any]] ?? [:]) {
            guard let content = value["content"] as? String,
                let view = value["view"] as? String,
                let bytes = value["bytes"] as? String
            else { continue }
            entries[key] = Entry(
                content: content, view: view, bytes: bytes,
                reviewedAt: value["reviewedAt"] as? String, note: value["note"] as? String)
        }

        var deferrals: [String: Deferral] = [:]
        for (key, value) in (root["deferred"] as? [String: [String: Any]] ?? [:]) {
            guard let firstSeen = value["firstSeen"] as? String,
                let expires = value["expires"] as? String,
                let reason = value["reason"] as? String
            else { continue }
            deferrals[key] = Deferral(
                source: key, firstSeen: firstSeen, expires: expires, reason: reason,
                change: value["change"] as? [String] ?? [])
        }

        return UpstreamLock(entries: entries, deferrals: deferrals)
    }

    /// Written sorted and pretty-printed, because it is reviewed in a diff.
    public func write(to directory: URL) throws {
        var artifacts: [String: Any] = [:]
        for (key, entry) in entries {
            var record: [String: Any] = [
                "bytes": entry.bytes, "content": entry.content, "view": entry.view,
            ]
            if let reviewedAt = entry.reviewedAt { record["reviewedAt"] = reviewedAt }
            if let note = entry.note { record["note"] = note }
            artifacts[key] = record
        }

        var deferred: [String: Any] = [:]
        for (key, deferral) in deferrals {
            deferred[key] = [
                "firstSeen": deferral.firstSeen, "expires": deferral.expires,
                "reason": deferral.reason, "change": deferral.change,
            ]
        }

        let root: [String: Any] = [
            "_comment": Self.explanation,
            "artifacts": artifacts,
            "deferred": deferred,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: directory.appendingPathComponent(Self.filename))
    }

    static let explanation = [
        "What each pinned artifact said last time somebody looked, and what was decided.",
        "",
        "`artifacts` records the content digest -- a canonical rendering of everything the",
        "file states, not just the values an adapter reads -- beside the byte digest seen at",
        "the time. A run whose bytes no longer match the descriptor compares content against",
        "this: equal means only the container's own metadata moved and the run continues;",
        "different means the document says something new and the run stops. `view` names the",
        "recipe, so changing a renderer invalidates these rather than silently comparing old",
        "digests against new rules.",
        "",
        "`deferred` records a data change that was understood and deliberately not adopted,",
        "with the day it was first seen and the day the deferral expires. Past that date the",
        "check fails: a snapshot may lag an upstream on purpose, but not by forgetting.",
        "",
        "Written by `decoy-repin`, never by hand.",
    ]
}
