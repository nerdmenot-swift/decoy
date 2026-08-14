import Foundation

/// Given-name counts from the statistical offices that answer a query rather than publish a
/// file.
///
/// Norway returns one table with both sexes in it, distinguished by a prefix on the code
/// rather than by a dimension: `1EMMA` is female Emma and `2JAKOB` is male Jakob. Nothing in
/// the response says so. Slovenia returns two tables, one per sex, each with the names in a
/// dimension of its own.
///
/// Norway is queried as json-stat2 rather than CSV for a concrete reason: its CSV mangles
/// `Ø` to `Z2` and `Å` to `Z3`, which would silently corrupt every Norwegian name containing
/// them. Slovenia's CSV is windows-1250 for the same class of reason.
public enum StatisticsQueries {

    /// The most recent year Norway publishes, asked for explicitly so a re-run is stable.
    public static let norwayYear = "2025"

    public struct Row: Sendable {
        public let name: String
        public let sex: String
        public let count: Double
    }

    public enum Failure: Error, CustomStringConvertible {
        case unexpectedShape(String)
        case tooFewRows(country: String, found: Int)

        public var description: String {
            switch self {
            case .unexpectedShape(let detail): return detail
            case .tooFewRows(let country, let found):
                return "\(country) returned only \(found) names — verify before committing"
            }
        }
    }

    /// A json-stat2 category, walked the way the JavaScript walked it.
    ///
    /// Which is neither document order nor `index` order, and finding that out took two
    /// wrong answers. Slovenia's name codes are integer-like strings — `"3"`, `"19"`,
    /// `"29413"` — and `Object.entries` lists integer-like keys first in ascending numeric
    /// order whatever the document says, so the snapshot is in numeric-code order while the
    /// response is in alphabetical order. `index` says *where a member's value sits*; it is
    /// a third order again, and reading it as the presentation order reorders every name.
    ///
    /// Norway's codes are `1EMMA` and `2JAKOB`, which are not integer-like, so its half of
    /// the file matched from the first attempt and hid the question entirely.
    public static func ordered(category: OrderedJSON) throws -> [(code: String, label: String)] {
        guard let labels = category["label"]?.propertyOrder else {
            throw Failure.unexpectedShape("a category has no label object")
        }
        return labels.compactMap { entry in entry.value.asString.map { (entry.key, $0) } }
    }

    /// Where each member's value sits in the flattened value array.
    public static func positions(category: OrderedJSON) throws -> [String: Int] {
        guard let index = category["index"]?.asObject else {
            throw Failure.unexpectedShape("a category has no index object")
        }
        var found: [String: Int] = [:]
        for entry in index { found[entry.key] = entry.value.asNumber.map(Int.init) }
        return found
    }

    public static func dimension(_ data: OrderedJSON, _ name: String) throws -> OrderedJSON {
        guard let category = data["dimension"]?[name]?["category"] else {
            throw Failure.unexpectedShape("the response has no \(name) dimension")
        }
        return category
    }

    public static func values(_ data: OrderedJSON) throws -> [Double] {
        guard let raw = data["value"]?.asArray else {
            throw Failure.unexpectedShape("the response has no value array")
        }
        return raw.map { $0.asNumber ?? .nan }
    }

    /// Norway: one table, both sexes, sex encoded as the first character of the code.
    ///
    /// Only names held by 200 or more people are published at all, which is Statistics
    /// Norway protecting individuals rather than a sampling choice, and sits at exactly the
    /// threshold `CivilNamesAdapter` applies anyway.
    public static func norway(log: (String) -> Void = { _ in }) async throws -> [Row]? {
        let body: [String: Any] = [
            "query": [
                ["code": "ContentsCode", "selection": ["filter": "item", "values": ["Personer"]]],
                ["code": "Tid", "selection": ["filter": "item", "values": [norwayYear]]],
            ],
            "response": ["format": "json-stat2"],
        ]
        guard
            let data = await Endpoint.pxweb(
                "https://data.ssb.no/api/v0/en/table/10501", body: body, log: log)
        else { return nil }

        let category = try dimension(data, "Fornavn")
        let numbers = try values(data)
        let index = try positions(category: category)

        var rows: [Row] = []
        for (code, label) in try ordered(category: category) {
            guard let position = index[code], position < numbers.count else { continue }
            let count = numbers[position]
            guard count.isFinite, count > 0 else { continue }
            let sex = code.hasPrefix("1") ? "female" : code.hasPrefix("2") ? "male" : nil
            guard let sex else { continue }
            rows.append(Row(name: label, sex: sex, count: count))
        }
        return rows
    }

    /// Slovenia: two tables, one per sex, each a name dimension crossed with years.
    ///
    /// The latest year is taken rather than summed. Slovenia publishes a stock — how many
    /// people hold the name *now* — once per year, so adding the years together would count
    /// the same living person once per year they were alive.
    public static func slovenia(log: (String) -> Void = { _ in }) async throws -> [Row]? {
        var rows: [Row] = []

        for (table, sex) in [("05X1005S", "male"), ("05X1010S", "female")] {
            let body: [String: Any] = [
                "query": [["code": "MERITVE", "selection": ["filter": "item", "values": ["1"]]]],
                "response": ["format": "json-stat2"],
            ]
            guard
                let data = await Endpoint.pxweb(
                    "https://pxweb.stat.si/SiStatData/api/v1/en/Data/\(table).px",
                    body: body, log: log)
            else { return nil }

            let names = try dimension(data, "IME")
            let years = try dimension(data, "LETO")
            let numbers = try values(data)
            let nameIndex = try positions(category: names)
            let yearCount = try positions(category: years).count
            let latest = yearCount - 1

            for (code, label) in try ordered(category: names) {
                // Row-major over (name, measure, year) with one measure selected, so a
                // name's slice is `yearCount` long and the last entry is the most recent.
                guard let position = nameIndex[code] else { continue }
                let offset = position * yearCount + latest
                guard offset < numbers.count else { continue }
                let count = numbers[offset]
                guard count.isFinite, count > 0 else { continue }
                rows.append(Row(name: label, sex: sex, count: count))
            }
            await Endpoint.pause(1.5)
        }
        return rows
    }
}
