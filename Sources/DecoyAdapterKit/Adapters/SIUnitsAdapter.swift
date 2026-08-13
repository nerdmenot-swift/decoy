import Foundation

/// Units of measurement with their symbols, per locale, from CLDR.
///
/// Fills:
///   <each>   science.unit
public struct SIUnitsAdapter: Adapter {
    public static let id = "si-units"
    public static let sources = ["cldr-48"]

    public init() {}

    /// A measurable quantity rather than a formatting rule.
    ///
    /// CLDR's unit table also carries power and prefix patterns — `10p3`, `power2`, `per`
    /// — which describe how to *compose* a unit rather than naming one.
    static func isMeasurable(_ key: String) -> Bool {
        key.contains("-") && !key.hasPrefix("10p") && !key.hasPrefix("power")
            && !key.hasPrefix("per")
    }

    /// The narrow pattern with its placeholder removed: `{0}mi²` becomes `mi²`.
    static func symbol(from narrow: Any?) -> String? {
        guard let entry = narrow as? [String: Any] else { return nil }
        let pattern =
            (entry["unitPattern-count-other"] as? String)
            ?? (entry["unitPattern-count-one"] as? String)
        guard let pattern else { return nil }
        let symbol = pattern.replacingOccurrences(of: "{0}", with: "")
            .trimmingCharacters(in: .whitespaces)
        return symbol.isEmpty ? nil : symbol
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let root = try input.artifact("units", for: Self.id)
        var contributions: [String: [String: Definition]] = [:]
        var unmapped: [String] = []
        var unitCount = 0

        for locale in input.locales {
            guard let cldrCode = CLDR.code(for: locale, overrides: input.cldrOverrides) else {
                continue
            }
            guard let entry = try CLDR.load("units.json", for: cldrCode, under: root),
                let units = entry["units"] as? [String: Any]
            else {
                unmapped.append(locale)
                continue
            }

            let long = (units["long"] as? [String: Any]) ?? [:]
            let narrow = (units["narrow"] as? [String: Any]) ?? [:]

            var rows: [Definition] = []
            for key in long.keys.sorted() where Self.isMeasurable(key) {
                guard let entry = long[key] as? [String: Any],
                    let name = entry["displayName"] as? String,
                    let symbol = Self.symbol(from: narrow[key])
                else { continue }
                // Both columns or neither, so `unit()["symbol"]` is never empty for some
                // draws and populated for others.
                rows.append(.object(["name": .string(name), "symbol": .string(symbol)]))
            }

            if !rows.isEmpty {
                contributions[locale] = ["science.unit": .list(rows)]
                unitCount = max(unitCount, rows.count)
            }
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("units", String(unitCount)), ("locales", String(contributions.count)),
                ("unmapped", unmapped.joined(separator: ",")),
            ])
    }
}
