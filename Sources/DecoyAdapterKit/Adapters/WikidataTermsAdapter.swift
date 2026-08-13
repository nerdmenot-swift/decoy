import Foundation

/// Small closed vocabularies per language, from a committed Wikidata snapshot.
///
/// Fills:
///   <each>   location.direction.cardinal
///   <each>   location.direction.ordinal
///   <each>   person.western_zodiac_sign
///   <each>   person.sex
public struct WikidataTermsAdapter: Adapter {
    public static let id = "wikidata-terms"
    public static let sources = ["wikidata"]

    public init() {}

    /// Iterated in this order so the stats line reads the same as the JavaScript's.
    private static let paths: [(set: String, path: String)] = [
        ("direction_cardinal", "location.direction.cardinal"),
        ("direction_ordinal", "location.direction.ordinal"),
        ("western_zodiac_sign", "person.western_zodiac_sign"),
        ("sex", "person.sex"),
    ]

    /// Wikidata labels are per language; Decoy locales are per language *and* region.
    static func language(of code: String) -> String {
        String(code.split(separator: "_")[0])
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("wikidata-terms.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let terms = root["terms"] as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/wikidata-terms.json is not the expected shape")
        }
        let retrieved = (root["retrieved"] as? String) ?? "unknown"

        var contributions: [String: [String: Definition]] = [:]
        var stats: [(String, String)] = [("retrieved", retrieved)]

        for (set, path) in Self.paths {
            guard let byLanguage = terms[set] as? [String: Any] else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id, detail: "wikidata-terms: no '\(set)' in the committed data")
            }

            var count = 0
            for code in input.locales {
                if code == "base" { continue }
                // English keeps what the authored adapter supplies, so the abbreviations
                // and the words they abbreviate stay in one place and cannot drift apart.
                if Self.language(of: code) == "en" { continue }
                guard let values = byLanguage[Self.language(of: code)] as? [String],
                    !values.isEmpty
                else { continue }
                contributions[code, default: [:]][path] = .list(values.map(Definition.string))
                count += 1
            }
            stats.append((set, String(count)))
        }

        guard !contributions.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "wikidata-terms produced nothing — is data/wikidata-terms.json present?")
        }

        return AdapterOutput(contributions: contributions, stats: stats)
    }
}
