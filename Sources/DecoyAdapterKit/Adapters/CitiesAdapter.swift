import Foundation

/// Real places from a GeoNames-derived gazetteer, keyed to each locale's country.
///
/// Fills:
///   <each>   location.city_name
///   <each>   location.county        where the country has at least twenty
///   <each>   location.place         city / state / state_code, as one row
public struct CitiesAdapter: Adapter {
    public static let id = "cities"
    public static let sources = ["cities-json", "cldr-48"]
    public static let attributeTo: String? = "cities-json"

    public init() {}

    /// Below this a locale would offer three or four counties as if they were the whole
    /// set, which reads as data rather than as a gap. The list stays absent instead.
    private static let minimumCounties = 20

    /// Locales whose geography comes from `WikidataPlacesAdapter` instead.
    ///
    /// This gazetteer romanises everything, which is fine for locales written in Latin and
    /// wrong for the rest: it put a Japanese person in `Abashiri` and a Russian one in
    /// `Abakan`. Sixteen locales now take their cities in their own script, so this yields
    /// those paths rather than fighting over them — two adapters claiming one path is a
    /// refusal in `Orchestrator.merge`, and rightly so.
    ///
    /// Counties go with them and are not replaced. What this supplied for Russian was
    /// `Abakan Urban District`, which is not romanised Russian but an English description
    /// of the administrative type, and no source here has the native equivalent. An honest
    /// gap beats a confident wrong answer.
    ///
    /// The list is derived rather than repeated, so the two adapters cannot disagree about
    /// which locales it covers.
    private static var deferredToNativeScript: Set<String> {
        Set(WikidataQueries.cityLocales.map(\.code))
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let root = try input.artifact("cities", for: Self.id).appendingPathComponent("package")
        let likelySubtags = try CLDR.likelySubtags(under: core)

        func load(_ name: String) throws -> [[String: Any]] {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id, detail: "\(name) is not an array of objects")
            }
            return list
        }

        let cities = try load("cities.json")
        let admin1 = try load("admin1.json")
        // Second-level divisions: US counties, French départements, Japanese districts.
        let admin2 = try load("admin2.json")

        // admin1 codes are country-scoped (`US.CA`, `DE.02`), so the lookup is keyed by the
        // pair — `03` alone means a different subdivision in every country.
        var adminNames: [String: String] = [:]
        for entry in admin1 {
            guard let code = entry["code"] as? String, let name = entry["name"] as? String
            else { continue }
            adminNames[code] = name
        }

        var byCountry: [String: [[String: Any]]] = [:]
        for city in cities {
            guard let name = city["name"] as? String, !name.isEmpty,
                let country = city["country"] as? String, !country.isEmpty
            else { continue }
            byCountry[country, default: []].append(city)
        }

        // Second-level divisions, grouped by the country prefix of their code.
        var countiesByCountry: [String: Set<String>] = [:]
        for entry in admin2 {
            guard let code = entry["code"] as? String, code.count >= 2,
                let name = entry["name"] as? String, !name.isEmpty
            else { continue }
            countiesByCountry[String(code.prefix(2)), default: []].insert(name)
        }

        var contributions: [String: [String: Definition]] = [:]
        var withoutCities: [String] = []
        var countyLocales = 0

        for locale in input.locales where locale != "base" {
            let region = CLDR.region(for: locale, likelySubtags: likelySubtags)
            guard let region, let rows = byCountry[region], !rows.isEmpty else {
                if let region { withoutCities.append("\(locale)(\(region))") }
                continue
            }

            let sorted = rows.sorted {
                ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
            }

            // Yielded whole: cities, the composite and the counties that go with them.
            if Self.deferredToNativeScript.contains(locale) { continue }

            var paths: [String: Definition] = [:]

            let counties = (countiesByCountry[region] ?? []).sorted()
            if counties.count >= Self.minimumCounties {
                countyLocales += 1
                paths["location.county"] = .list(counties.map(Definition.string))
            }

            var seen = Set<String>()
            var names: [Definition] = []
            for city in sorted {
                guard let name = city["name"] as? String, seen.insert(name).inserted else {
                    continue
                }
                names.append(.string(name))
            }
            paths["location.city_name"] = .list(names)

            // Coordinates are deliberately omitted. The gazetteer has them, and a coherent
            // place row arguably wants them, but they are single-use high-entropy strings
            // that never dedup in the arena: for `en` alone 17,019 distinct strings, about
            // a third of the locale's total, tripling the compiled module. `latitude()`
            // and `longitude()` already generate coordinates algorithmically.
            paths["location.place"] = .list(
                sorted.map { city in
                    let country = city["country"] as? String ?? ""
                    let admin = city["admin1"] as? String ?? ""
                    return .object([
                        "city": .string(city["name"] as? String ?? ""),
                        // Empty rather than absent where the gazetteer has no subdivision,
                        // so the composite keeps one shape across every row.
                        "state": .string(adminNames["\(country).\(admin)"] ?? ""),
                        "state_code": .string(admin),
                    ])
                })

            contributions[locale] = paths
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("countyLocales", String(countyLocales)),
                ("cities", String(cities.count)),
                ("countries", String(byCountry.count)),
                ("locales", String(contributions.count)),
                ("withoutCities", withoutCities.joined(separator: ",")),
            ])
    }
}
