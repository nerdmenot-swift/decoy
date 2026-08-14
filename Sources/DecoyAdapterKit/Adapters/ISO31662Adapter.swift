import Foundation

/// Country subdivisions — states, provinces, Länder — from CLDR.
///
/// Fills:
///   <each>   location.state
///   <each>   location.state_abbr
public struct ISO31662Adapter: Adapter {
    public static let id = "iso-3166-2"
    public static let sources = ["cldr-48"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let subdivisionsRoot = try input.artifact("subdivisions", for: Self.id)

        let likelySubtags = try CLDR.likelySubtags(under: core)
        guard !likelySubtags.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "CLDR likelySubtags.json is not the expected shape")
        }

        // English only: the subdivision names are the same records whatever locale reads
        // them, so reading one file rather than one per locale is a consequence of that
        // decision rather than an optimisation.
        let file = subdivisionsRoot.appendingPathComponent("package/subdivisions/en/en.json")
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let subdivisions = CLDR.at(root, "subdivisions", "localeDisplayNames", "subdivisions")
                as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "CLDR subdivisions en.json is not the expected shape")
        }

        // Group by country once: `usca` -> US, `debw` -> DE.
        var byRegion: [String: [(name: String, code: String)]] = [:]
        for key in subdivisions.keys.sorted() {
            guard let name = subdivisions[key] as? String else { continue }
            let characters = Array(key)
            guard characters.count > 2,
                characters[0].isLowercase, characters[0].isLetter,
                characters[1].isLowercase, characters[1].isLetter,
                characters[2...].allSatisfy({
                    ($0.isLowercase && $0.isLetter) || $0.isNumber
                })
            else { continue }
            let country = String(characters[0...1]).uppercased()
            let suffix = String(characters[2...]).uppercased()
            byRegion[country, default: []].append((name, suffix))
        }
        for key in byRegion.keys {
            byRegion[key]?.sort { $0.name < $1.name }
        }

        var contributions: [String: [String: Definition]] = [:]
        var withoutSubdivisions: [String] = []

        for locale in input.locales where locale != "base" {
            let region = CLDR.region(for: locale, likelySubtags: likelySubtags)
            guard let region, let rows = byRegion[region], !rows.isEmpty else {
                if let region { withoutSubdivisions.append("\(locale)(\(region))") }
                continue
            }

            contributions[locale] = [
                // A composite, so a row needing both gets them from the same subdivision.
                // Parallel lists would pair Bavaria with Hamburg's code and pass most
                // validators.
                "location.state": .list(
                    rows.map { .object(["name": .string($0.name), "abbr": .string($0.code)]) }),
                // The flat list too, because `stateAbbreviation()` fills a column of its
                // own and should not have to draw a whole row to do it. Same values, from
                // the same rows, so the two cannot disagree.
                "location.state_abbr": .list(rows.map { .string($0.code) }),
            ]
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("countries", String(byRegion.count)),
                ("subdivisions", String(subdivisions.count)),
                ("locales", String(contributions.count)),
                ("withoutSubdivisions", withoutSubdivisions.joined(separator: ",")),
            ])
    }
}
