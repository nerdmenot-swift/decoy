import Foundation

/// A pinned upstream, as `Tools/adapters/sources/<id>.json` declares it.
///
/// The shape is dictated by the JSON that already exists rather than by what would be
/// tidiest, because the port has to read the same descriptors the JavaScript did — the
/// files are the contract, and rewriting them would mean re-verifying 51 upstreams.
public struct SourceDescriptor: Decodable, Sendable {

    public struct Artifact: Decodable, Sendable {
        public let name: String
        /// Absent on eleven of the fifty-one. The pipeline falls through to `tar xzf`
        /// for anything that is not `zip` or `tar.xz`, so absent means tgz. Requiring it
        /// here is what made the first pass of the integrity check silently skip six whole
        /// descriptors while reporting success.
        public let format: String?
        public let filename: String?
        public let url: String
        public let integrity: String
        /// Lines the digest deliberately does not cover. See `Integrity.normalised`.
        public let ignoreLinesMatching: String?

        /// The cache filename, which has to match what the JavaScript wrote or every
        /// artifact appears uncached on the first Swift run and is re-fetched.
        public var cacheSuffix: String {
            if format == "file" { return filename ?? name }
            let extensions = ["zip": "zip", "tar.xz": "tar.xz"]
            return "\(name).\(format.flatMap { extensions[$0] } ?? "tgz")"
        }

        public var isArchive: Bool { format != "file" }
    }

    /// Where a source states its own version, rather than it being transcribed.
    ///
    /// Exists because iana-tld's digest ignores its serial line by design, so the
    /// transcribed version drifted with nothing able to notice — the descriptor claimed
    /// 2026080700 while the file that compiled in said 2026081200.
    public let id: String
    public let name: String?
    public let license: String
    /// The upstream's own copyright line, verbatim. Empty where it states none.
    public let copyright: String?
    public let url: String
    public let version: String
    public let retrieved: String
    public let artifacts: [Artifact]?

    /// The provenance record that travels with the data into the compiled corpus.
    public var provenance: Provenance {
        Provenance(
            id: id, license: license, copyright: copyright ?? "", url: url,
            version: version, retrieved: retrieved)
    }

    public struct Provenance: Encodable, Sendable, Equatable {
        public let id: String
        public let license: String
        public let copyright: String
        public let url: String
        public let version: String
        public let retrieved: String
    }
}
