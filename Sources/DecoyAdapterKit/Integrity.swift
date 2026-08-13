import Decoy

/// Subresource-integrity checking for pinned upstream artifacts.
///
/// The pipeline's central safety property: an artifact is only ever used if its bytes hash
/// to the value recorded in its descriptor. It is what makes "pinned" mean something, and
/// it is not theoretical — it is what caught `www2.census.gov` answering HTTP 200 with a
/// 247-byte "Request Rejected" page where a 12 MB zip should have been. The fetch
/// succeeded; only the hash objected.
public enum Integrity {

    public enum Failure: Error, CustomStringConvertible {
        case malformed(String)
        case unsupportedAlgorithm(String)
        case mismatch(source: String, url: String, expected: String, actual: String, note: String?)

        public var description: String {
            switch self {
            case .malformed(let value):
                return "malformed integrity string: \(value)"
            case .unsupportedAlgorithm(let algorithm):
                return
                    "unsupported integrity algorithm '\(algorithm)'. Only sha512 is implemented, "
                    + "because every descriptor uses it."
            case .mismatch(let source, let url, let expected, let actual, let note):
                return """
                    integrity mismatch for \(url)
                      expected sha512-\(expected)
                      actual   sha512-\(actual)
                    Upstream changed under a pinned version. Verify the change is legitimate, \
                    then update the integrity hash in sources/\(source).json.\
                    \(note.map { "\n\($0)" } ?? "")
                    """
            }
        }
    }

    /// An SRI string, `sha512-<base64>`.
    public struct Expectation: Sendable, Equatable {
        public let algorithm: String
        public let expected: String

        public init(_ integrity: String) throws {
            guard let separator = integrity.firstIndex(of: "-") else {
                throw Failure.malformed(integrity)
            }
            algorithm = String(integrity[integrity.startIndex..<separator])
            expected = String(integrity[integrity.index(after: separator)...])
            guard algorithm == "sha512" else { throw Failure.unsupportedAlgorithm(algorithm) }
            guard !expected.isEmpty else { throw Failure.malformed(integrity) }
        }
    }

    /// The digest of `bytes` in the form a descriptor records.
    public static func digest(_ bytes: [UInt8]) -> String {
        Base64.encode(SHA512.hash(bytes))
    }

    /// Drops lines an upstream re-issues without meaning, so the digest covers the data.
    ///
    /// IANA regenerates the root zone file with a fresh serial comment whenever the zone is
    /// republished, whether or not a TLD changed. Pinning the raw bytes failed the build
    /// daily for no reason, and a check that cries wolf every morning is one everybody
    /// learns to bypass. Every line that becomes corpus data is still covered.
    ///
    /// The split is on `\n` alone rather than on any newline, deliberately: this has to
    /// reproduce Node's `buffer.toString().split('\n')` byte for byte, and treating a lone
    /// `\r` as a separator would change the digest of any CRLF upstream.
    public static func normalised(_ bytes: [UInt8], ignoringLinesMatching pattern: String?)
        -> [UInt8]
    {
        guard let pattern, !pattern.isEmpty, let regex = try? Regex(pattern) else { return bytes }
        let text = String(decoding: bytes, as: UTF8.self)
        // `firstMatch`, not `wholeMatch`: JavaScript's `RegExp.test` is a search, and this
        // has to agree with it exactly or the digest of the one source that uses this
        // changes and the pin appears to have been tampered with.
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in (try? regex.firstMatch(in: String(line))).flatMap { $0 } == nil }
        return [UInt8](kept.joined(separator: "\n").utf8)
    }

    /// Throws unless `bytes` hash to what the descriptor recorded.
    public static func verify(
        _ bytes: [UInt8],
        against expectation: Expectation,
        source: String,
        url: String,
        ignoringLinesMatching pattern: String? = nil
    ) throws {
        let actual = digest(normalised(bytes, ignoringLinesMatching: pattern))
        guard actual == expectation.expected else {
            throw Failure.mismatch(
                source: source, url: url, expected: expectation.expected, actual: actual,
                note: pattern.map {
                    "(The digest ignores lines matching /\($0)/, so this is a real content "
                        + "change, not a re-issue.)"
                })
        }
    }
}
