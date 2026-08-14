import Foundation

/// Top-level domains, from the IANA root zone database.
///
/// TLDs are language-neutral, so this lives in `base`.
///
/// Fills:
///   base    internet.domain_suffix
public struct IANATLDAdapter: Adapter {
    public static let id = "iana-tld"
    public static let sources = ["iana-tld"]

    public init() {}

    /// Internationalised TLDs are published in Punycode (`XN--P1AI` for `рф`).
    ///
    /// Kept, and kept in that form. A domain name containing the Unicode label is not what
    /// DNS resolves or what a database column stores — the A-label is the real value, and
    /// decoding it would produce addresses that fail a round trip through any resolver.
    private static let punycodePrefix = "XN--"

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = try input.artifact("tlds", for: Self.id)
        let text = String(decoding: try Data(contentsOf: path), as: UTF8.self)

        // Split on "\n" alone, matching the JavaScript. `\.isNewline` would additionally
        // treat a lone CR as a separator, and CRLF as one — either of which changes what a
        // line is if IANA ever republishes with different endings.
        let lines = Lines.split(text)

        // Reported, not asserted. IANA bumps this serial on every regeneration whether or
        // not a TLD changed, so failing on it would fail the build daily; the descriptor's
        // digest ignores the serial line and covers the delegations, which is the real
        // check. `versionFrom` in the descriptor reads it into provenance.
        let serial =
            lines.first
            .flatMap { line -> String? in
                guard line.hasPrefix("# Version ") else { return nil }
                let rest = line.dropFirst("# Version ".count)
                let digits = rest.prefix { $0.isNumber }
                return digits.isEmpty ? nil : String(digits)
            } ?? "unknown"

        var suffixes: [String] = []
        var internationalised = 0
        for line in lines.dropFirst() {
            let tld = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if tld.isEmpty || tld.hasPrefix("#") { continue }
            if tld.hasPrefix(Self.punycodePrefix) { internationalised += 1 }
            // Lower-cased: IANA publishes upper-case, but a domain suffix appears in a
            // hostname, and hostnames are conventionally lower-case wherever one is stored.
            suffixes.append(tld.lowercased())
        }

        guard suffixes.count >= 500 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "root zone parsed to only \(suffixes.count) TLDs — the format has changed")
        }

        return AdapterOutput(
            contributions: [
                "base": ["internet.domain_suffix": .list(suffixes.sorted().map(Definition.string))]
            ],
            stats: [
                ("tlds", String(suffixes.count)),
                ("internationalised", String(internationalised)),
                ("serial", serial),
            ])
    }
}
