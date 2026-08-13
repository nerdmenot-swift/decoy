import Foundation

/// HTTP status codes and JOSE signature algorithms, from the IANA registries.
///
/// Fills:
///   base    internet.http_status_code.<class>
///   base    internet.jwt_algorithm
///
/// `base`: a status code is the same in every language.
public struct IANAWebAdapter: Adapter {
    public static let id = "iana-web"
    public static let sources = ["iana-http-status", "iana-jose"]

    public init() {}

    private static let statusClasses: [Character: String] = [
        "1": "informational",
        "2": "success",
        "3": "redirection",
        "4": "clientError",
        "5": "serverError",
    ]

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let statusRows = CSV.parse(
            String(
                decoding: try Data(contentsOf: try input.artifact("status", for: Self.id)),
                as: UTF8.self))
        guard let statusHeader = statusRows.first, statusHeader.count >= 2,
            statusHeader[0] == "Value", statusHeader[1] == "Description"
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "IANA status header is \((statusRows.first ?? []).joined(separator: ","))"
                    + " — the schema has changed")
        }

        var byClass: [String: [Int]] = [:]
        for row in statusRows.dropFirst() {
            guard row.count >= 2 else { continue }
            let value = row[0]
            let description = row[1].trimmingCharacters(in: .whitespaces)

            // The registry carries reserved and unassigned ranges as rows too. Those are
            // not status codes anybody returns, and the description says so.
            guard value.count == 3, value.allSatisfy(\.isNumber) else { continue }
            let lowered = description.lowercased()
            if lowered == "unassigned" || lowered == "(unused)" || lowered.hasPrefix("reserved") {
                continue
            }
            guard let first = value.first, let klass = Self.statusClasses[first],
                let code = Int(value)
            else { continue }
            byClass[klass, default: []].append(code)
        }

        let total = byClass.values.reduce(0) { $0 + $1.count }
        guard total >= 40 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "IANA yielded \(total) status codes — verify before re-pinning")
        }

        let joseRows = CSV.parse(
            String(
                decoding: try Data(contentsOf: try input.artifact("jose", for: Self.id)),
                as: UTF8.self))
        guard let joseHeader = joseRows.first, joseHeader.first == "Algorithm Name" else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "IANA JOSE header is \(joseRows.first?.first ?? "") — the schema has changed")
        }

        // `alg` usage only. The registry also lists `enc` algorithms, which name a content
        // encryption method rather than a signature algorithm, and a JWT header's `alg`
        // field never carries one.
        var seen = Set<String>()
        var jwt: [String] = []
        for row in joseRows.dropFirst() {
            guard let name = row.first, row.count >= 3 else { continue }
            let usage = row[2]
            guard Self.mentionsAlg(usage) else { continue }
            let usable =
                !name.isEmpty
                && name.allSatisfy {
                    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-")
                }
            guard usable, seen.insert(name).inserted else { continue }
            jwt.append(name)
        }
        jwt.sort()

        guard jwt.count >= 10 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "IANA yielded \(jwt.count) JOSE algorithms — verify before re-pinning")
        }

        var contributions: [String: Definition] = [:]
        for (klass, codes) in byClass {
            contributions["internet.http_status_code.\(klass)"] = .list(
                codes.sorted().map { .number(Double($0)) })
        }
        contributions["internet.jwt_algorithm"] = .list(jwt.map(Definition.string))

        return AdapterOutput(
            contributions: ["base": contributions],
            stats: [("statusCodes", String(total)), ("jwtAlgorithms", String(jwt.count))])
    }

    /// `\balg\b` — the whole word, not a substring of another.
    ///
    /// The distinction matters: the usage column carries values like `alg`, `JWE alg`, and
    /// `enc`, and a plain `contains("alg")` would also match nothing useful here today but
    /// would quietly start matching if a future value were `algorithm`.
    static func mentionsAlg(_ usage: String) -> Bool {
        let isWordCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        let words = usage.split(whereSeparator: { !isWordCharacter($0) })
        return words.contains("alg")
    }
}
