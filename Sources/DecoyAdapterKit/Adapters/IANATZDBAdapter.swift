import Foundation

/// IANA time zones, from `zone1970.tab`.
///
/// Fills:
///   base    location.time_zone   — `date.timeZone()` reads this path too
public struct IANATZDBAdapter: Adapter {
    public static let id = "iana-tzdb"
    public static let sources = ["iana-tzdb"]

    public init() {}

    /// The canonical zone list. Field 3 is the zone name; the first two are the country
    /// codes and coordinates, which nothing here wants.
    static func zones(in table: String) -> [String] {
        var found = Set<String>()
        for line in Lines.split(table) {
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3 else { continue }
            let name = fields[2].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { found.insert(name) }
        }
        return found.sorted()
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("tzdata", for: Self.id)
        let file = directory.appendingPathComponent("zone1970.tab")
        let table = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        let list = Self.zones(in: table)

        guard !list.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "zone1970.tab parsed to zero zones — the format has changed")
        }

        return AdapterOutput(
            contributions: ["base": ["location.time_zone": .list(list.map(Definition.string))]],
            stats: [("zones", String(list.count))])
    }
}
