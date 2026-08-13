import Foundation

/// Colour names per language, from a committed Wikidata snapshot.
///
/// Fills:
///   <each>   color.human
public struct WikidataColoursAdapter: Adapter {
    public static let id = "wikidata-colours"
    public static let sources = ["wikidata"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("wikidata-colours.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let colours = root["colours"] as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/wikidata-colours.json is not the expected shape")
        }
        let retrieved = (root["retrieved"] as? String) ?? "unknown"
        let roster = Set(input.locales)

        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []

        for (code, raw) in colours.sorted(by: { $0.key < $1.key }) {
            guard roster.contains(code) else { continue }
            // English keeps the CSS named set. A Wikidata list would be a lateral move at
            // best, and it would cost the one colour source in the corpus citing a standard.
            if code == "en" { continue }
            guard let list = raw as? [String], !list.isEmpty else { continue }
            contributions[code] = ["color.human": .list(list.sorted().map(Definition.string))]
            taken.append("\(code)(\(list.count))")
        }

        guard !taken.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "wikidata-colours produced nothing — is data/wikidata-colours.json present?")
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("retrieved", retrieved), ("locales", String(taken.count)),
                ("taken", taken.joined(separator: ",")),
            ])
    }
}
