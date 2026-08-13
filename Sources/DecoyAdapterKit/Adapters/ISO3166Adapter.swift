import Foundation

/// Country codes and localised country names, from CLDR.
///
/// Fills:
///   base     location.country_code
///   <each>   location.country
///   <each>   location.continent
public struct ISO3166Adapter: Adapter {
    public static let id = "iso-3166"
    public static let sources = ["cldr-48"]

    public init() {}

    /// Numeric codes at or above this are user-assigned rather than ISO-allocated.
    private static let userAssignedFloor = 900

    /// The UN M49 macro regions CLDR uses for continents, plus Antarctica.
    ///
    /// Six rather than seven: CLDR models the Americas as one region (019), because M49
    /// does. Splitting it would assert a schoolroom convention half the world does not use.
    private static let continentCodes = ["002", "019", "142", "150", "009", "AQ"]

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let names = try input.artifact("localenames", for: Self.id)

        let file = core.appendingPathComponent("package/supplemental/codeMappings.json")
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let mappings = CLDR.at(root, "supplemental", "codeMappings") as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "CLDR codeMappings.json is not the expected shape")
        }

        // Officially assigned entries only: a real two-letter code carrying both an
        // alpha-3 and a numeric outside the user-assigned range.
        var assigned: [(alpha2: String, alpha3: String, numeric: String)] = []
        for alpha2 in mappings.keys.sorted() {
            guard alpha2.count == 2, alpha2.allSatisfy({ $0.isUppercase && $0.isLetter }),
                let mapping = mappings[alpha2] as? [String: Any],
                let alpha3 = mapping["_alpha3"] as? String, !alpha3.isEmpty,
                let numeric = mapping["_numeric"] as? String, !numeric.isEmpty,
                let value = Int(numeric), value < Self.userAssignedFloor
            else { continue }
            assigned.append((alpha2, alpha3, numeric))
        }
        let known = Set(assigned.map(\.alpha2))

        var contributions: [String: [String: Definition]] = [:]
        var unmapped: [String] = []

        // The code triple is language-neutral, so it belongs in `base` where every locale
        // reaches it. Splitting it into three parallel lists would generate countries that
        // do not exist, which is why the format carries composite records at all.
        contributions["base"] = [
            "location.country_code": .list(
                assigned.map {
                    .object([
                        "alpha2": .string($0.alpha2), "alpha3": .string($0.alpha3),
                        "numeric": .string($0.numeric),
                    ])
                })
        ]

        for locale in input.locales {
            guard let cldrCode = CLDR.code(for: locale, overrides: input.cldrOverrides) else {
                continue
            }
            guard let entry = try CLDR.load("territories.json", for: cldrCode, under: names),
                let territories = CLDR.at(entry, "localeDisplayNames", "territories")
                    as? [String: Any]
            else {
                unmapped.append(locale)
                continue
            }

            // CLDR carries alternates such as `CD-alt-variant` and `HK-alt-short`. The
            // plain key is the standard form; the alternates are editorial choices there is
            // no basis to make here.
            var countryNames: [Definition] = []
            for key in territories.keys.sorted()
            where !key.contains("-alt-") && known.contains(key) {
                if let name = territories[key] as? String {
                    countryNames.append(.string(name))
                }
            }

            // Continents come from the same file, under the M49 codes. Worth taking
            // because they are otherwise a one-locale curiosity.
            let continents = Self.continentCodes.compactMap { territories[$0] as? String }
                .map(Definition.string)

            guard !countryNames.isEmpty || !continents.isEmpty else { continue }
            var paths: [String: Definition] = [:]
            if !countryNames.isEmpty { paths["location.country"] = .list(countryNames) }
            if !continents.isEmpty { paths["location.continent"] = .list(continents) }
            contributions[locale] = paths
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("countries", String(assigned.count)),
                ("locales", String(contributions.count - 1)),
                ("unmapped", unmapped.joined(separator: ",")),
            ])
    }
}
