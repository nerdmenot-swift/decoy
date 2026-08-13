import Foundation

/// Language names with their ISO 639-1 and 639-2/3 codes, per locale, from CLDR.
///
/// Fills:
///   <each>   location.language
public struct ISO639Adapter: Adapter {
    public static let id = "iso-639"
    public static let sources = ["cldr-48"]

    public init() {}

    /// The ISO 639-2/3 to 639-1 mapping, out of CLDR's alias table.
    ///
    /// CLDR records three-letter codes as "overlong" aliases of their two-letter
    /// equivalents — the same relationship 639-2 has to 639-1, expressed for a different
    /// purpose. Reading it here avoids taking on a second source for one column.
    static func alphaMapping(_ aliases: [String: Any]) -> [String: String] {
        guard let languageAlias = aliases["languageAlias"] as? [String: Any] else { return [:] }
        var alpha3For: [String: String] = [:]

        // Sorted, because "first alias wins" needs a defined order: CLDR lists the
        // bibliographic variant second where both exist, and dictionary iteration would
        // pick between them at random.
        for code in languageAlias.keys.sorted() {
            guard code.count == 3, code.allSatisfy({ $0.isLowercase && $0.isLetter }),
                let alias = languageAlias[code] as? [String: Any],
                (alias["_reason"] as? String) == "overlong",
                let replacement = alias["_replacement"] as? String,
                replacement.count == 2, replacement.allSatisfy({ $0.isLowercase && $0.isLetter })
            else { continue }
            if alpha3For[replacement] == nil { alpha3For[replacement] = code }
        }
        return alpha3For
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let names = try input.artifact("localenames", for: Self.id)

        let aliasFile = core.appendingPathComponent("package/supplemental/aliases.json")
        guard
            let aliasRoot = try JSONSerialization.jsonObject(with: Data(contentsOf: aliasFile))
                as? [String: Any],
            let aliases = CLDR.at(aliasRoot, "supplemental", "metadata", "alias")
                as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "CLDR aliases.json is not the expected shape")
        }
        let alpha3For = Self.alphaMapping(aliases)

        var contributions: [String: [String: Definition]] = [:]
        var unmapped: [String] = []
        var languageCount = 0

        for locale in input.locales {
            guard let cldrCode = CLDR.code(for: locale, overrides: input.cldrOverrides) else {
                continue
            }
            guard let entry = try CLDR.load("languages.json", for: cldrCode, under: names),
                let table = CLDR.at(entry, "localeDisplayNames", "languages") as? [String: Any]
            else {
                unmapped.append(locale)
                continue
            }

            // Only languages with all three columns. A row missing its alpha-3 would make
            // `location.language().alpha3` empty for some draws and not others, which is a
            // worse failure than the language simply not appearing.
            var rows: [Definition] = []
            for alpha2 in table.keys.sorted() {
                guard alpha2.count == 2, alpha2.allSatisfy({ $0.isLowercase && $0.isLetter }),
                    let alpha3 = alpha3For[alpha2],
                    let name = table[alpha2] as? String, !name.isEmpty
                else { continue }
                rows.append(
                    .object([
                        "alpha2": .string(alpha2), "alpha3": .string(alpha3),
                        "name": .string(name),
                    ]))
            }

            if !rows.isEmpty {
                contributions[locale] = ["location.language": .list(rows)]
                if languageCount == 0 { languageCount = rows.count }
            }
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("languages", String(languageCount)),
                ("locales", String(contributions.count)),
                ("unmapped", unmapped.joined(separator: ",")),
            ])
    }
}
