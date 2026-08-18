import Foundation

/// Korean surnames from KOSIS, the national statistics portal.
///
/// Korea publishes surnames — the 2015 census counts every one held by five people or more
/// — and there is no way to fetch it that a build machine can use. The portal answers only
/// to a registered API key, so this cannot be a pinned artifact with a hash, and a key
/// cannot live in a public repository.
///
/// So it takes the shape Norway and Slovenia already have: run by hand, result committed,
/// diffable by anyone who runs it again. See `Endpoint` for why that is the honest
/// arrangement for a source with no file behind it.
///
/// ## What is not verified here
///
/// Everything below the transform was written against KOSIS's published field list and
/// **has not been run against the live service** — no key was available. The request
/// shape, the table identifier and the meaning of each column are therefore claims, not
/// observations, and the failure messages are written to say which claim broke rather than
/// to fail vaguely. The transform itself is tested against a fixture in the documented
/// shape.
public enum KosisQuery {

    /// Statistics Korea, which publishes the census.
    public static let statisticsKorea = "101"
    public static let endpoint = "https://kosis.kr/openapi/Param/statisticsParameterData.do"

    public enum Failure: Error, CustomStringConvertible {
        case noKey
        case unreadable(String)
        case rejected(String)
        case tooFew(found: Int, wanted: Int)

        public var description: String {
            switch self {
            case .noKey:
                return """
                    no KOSIS key. Register at https://kosis.kr/openapi/ and pass it as
                    KOSIS_API_KEY, or --api-key. The portal answers to nothing else, which
                    is why this is committed rather than fetched by the build.
                    """
            case .unreadable(let detail):
                return "KOSIS returned something this cannot read: \(detail)"
            case .rejected(let message):
                // KOSIS reports errors as a JSON object rather than a status code, so a
                // rejected request looks exactly like a successful one to `curl`.
                return "KOSIS rejected the request: \(message)"
            case .tooFew(let found, let wanted):
                return
                    "only \(found) surnames, expected at least \(wanted) — the table or its "
                    + "column layout has changed; check C1_NM is the surname and DT the count"
            }
        }
    }

    /// One row as KOSIS returns it.
    ///
    /// The portal names its columns positionally — `C1`, `C2`, … — with a parallel
    /// `C1_OBJ_NM` saying what that position *means*. A surname-by-clan table puts the
    /// surname in one and the clan in another, and which is which is a property of the
    /// table rather than of the API.
    public struct Row {
        public let classification: String
        public let value: Double
    }

    /// Sums the counts per surname, dropping the totals row.
    ///
    /// The 2015 table crosses surname with clan origin — 36,744 combinations over about
    /// 250 surnames — so the rows have to be added up rather than taken as they come.
    /// KOSIS marks aggregates with `계` ("total"), and including one would make it the
    /// commonest surname in Korea by a factor of four.
    public static func aggregate(_ rows: [Row], minimum: Int = 100) throws -> [(name: String, count: Double)] {
        var order: [String] = []
        var totals: [String: Double] = [:]

        for row in rows {
            let name = row.classification.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "계", name != "합계", name != "전국" else { continue }
            guard row.value > 0 else { continue }
            if totals[name] == nil { order.append(name) }
            totals[name, default: 0] += row.value
        }

        guard order.count >= minimum else {
            throw Failure.tooFew(found: order.count, wanted: minimum)
        }

        return order.map { (name: $0, count: totals[$0] ?? 0) }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return CodeUnitOrder.before(left.name, right.name)
            }
    }

    /// Reads the rows out of a KOSIS response.
    ///
    /// `C1_NM` is the first classification's label and `DT` the datum. Both arrive as
    /// strings — `DT` included, which is why it is parsed rather than cast.
    public static func rows(from json: Any, classification: String = "C1_NM") throws -> [Row] {
        // An error is an object; a result is an array. That is the only difference.
        if let object = json as? [String: Any] {
            let message =
                (object["errMsg"] as? String) ?? (object["err"] as? String)
                ?? String(describing: object)
            throw Failure.rejected(message)
        }
        guard let array = json as? [[String: Any]] else {
            throw Failure.unreadable("expected an array of rows")
        }

        var out: [Row] = []
        for entry in array {
            guard let name = entry[classification] as? String else { continue }
            let raw = entry["DT"]
            let value: Double?
            if let text = raw as? String {
                value = Double(text.replacingOccurrences(of: ",", with: ""))
            } else {
                value = (raw as? NSNumber)?.doubleValue
            }
            guard let value, value.isFinite else { continue }
            out.append(Row(classification: name, value: value))
        }
        guard !out.isEmpty else {
            throw Failure.unreadable(
                "no row carried both \(classification) and DT — check the classification "
                    + "column; a surname-by-clan table may put the surname in C2")
        }
        return out
    }

    /// The request URL for one table.
    public static func url(key: String, org: String, table: String, period: String)
        -> URL?
    {
        var items = [
            "method": "getList", "apiKey": key, "format": "json", "jsonVD": "Y",
            "orgId": org, "tblId": table, "itmId": "ALL", "objL1": "ALL",
            "prdSe": "Y", "startPrdDe": period, "endPrdDe": period,
        ]
        // Sorted so the URL is stable, which matters only for reading a failure back.
        let query = items.keys.sorted()
            .map { "\($0)=\(Endpoint.encode(items[$0] ?? ""))" }
            .joined(separator: "&")
        items.removeAll()
        return URL(string: "\(endpoint)?\(query)")
    }
}
