import Foundation

/// Airports with IATA codes, from the OpenFlights-derived airport dataset.
///
/// Fills:
///   base    airline.airport
public struct AirportsAdapter: Adapter {
    public static let id = "airports"
    public static let sources = ["airport-data"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("airports", for: Self.id)
        let file = directory.appendingPathComponent("package/airports.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file))

        // Published as an array in some releases and as an object keyed by code in others.
        let entries: [[String: Any]]
        if let list = raw as? [[String: Any]] {
            entries = list
        } else if let keyed = raw as? [String: Any] {
            entries = keyed.values.compactMap { $0 as? [String: Any] }
        } else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "airports.json is neither an array nor an object")
        }

        var rows: [(name: String, iataCode: String)] = []
        var withoutCode = 0

        for airport in entries {
            let name = (airport["name"] as? String) ?? ""
            let iata = (airport["iata"] as? String) ?? ""
            // Airports with no IATA assignment are recorded as `\N` or an empty string. A
            // three-letter code is the whole point of the field, so those are dropped
            // rather than emitted with a blank no validator would accept.
            let coded =
                iata.count == 3
                && iata.allSatisfy { $0.isUppercase && $0.isLetter && $0.isASCII }
            guard !name.isEmpty, coded else {
                withoutCode += 1
                continue
            }
            rows.append((name, iata))
        }

        rows.sort { $0.iataCode < $1.iataCode }

        guard rows.count >= 3000 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "airport-data yielded only \(rows.count) coded airports — schema changed")
        }

        let table = rows.map {
            Definition.object(["name": .string($0.name), "iataCode": .string($0.iataCode)])
        }

        return AdapterOutput(
            contributions: ["base": ["airline.airport": .list(table)]],
            stats: [
                ("airports", String(rows.count)), ("withoutIataCode", String(withoutCode)),
            ])
    }
}
