import Foundation

/// Decoy's own data, for the fields no registry publishes.
///
/// Every other adapter reads somebody else's file. This one does not, which is a deliberate
/// exception to the rule that no data is hand-edited — and the exception is safe because
/// these lists are short, closed, checkable by anyone reading them, and there is nothing to
/// cite: no standards body maintains a register of street-type words or bicycle types.
///
/// ## Two halves, split on purpose
///
/// The **street composition** stays as code. Which languages compound a street name into
/// one word (Schillerstraße), which put the type last (Yıldırım Bulvarı), and which lead
/// with the building number are three small tables plus a rule, and adding a locale to
/// `locales` gives it the whole set. Freezing the output would turn that into twenty-one
/// per-locale copies that no longer follow the rule.
///
/// Everything **else** is frozen as it stands, because it is exactly what it looks like:
/// paths stated against locales, with no rule connecting them.
public struct AuthoredAdapter: Adapter {
    public static let id = "authored"
    public static let sources = ["decoy-authored"]

    public init() {}

    struct Streets {
        let types: [String: [String]]
        let locales: [String: [String]]
        let compounding: Set<String>
        let typeTrails: Set<String>
        let numberLeads: Set<String>
        let buildingNumber: [String]
    }

    /// How a street name is assembled in a language.
    static func pattern(for language: String, _ streets: Streets) -> Definition {
        func weighted(_ surname: String, _ given: String) -> Definition {
            .list([
                .object(["value": .string(surname), "weight": .number(8)]),
                .object(["value": .string(given), "weight": .number(2)]),
            ])
        }
        if streets.compounding.contains(language) {
            // No space, and the surname keeps its capital: Schillerstraße.
            return weighted(
                "{{person.lastName}}{{location.street_suffix}}",
                "{{person.firstName}}{{location.street_suffix}}")
        }
        if streets.typeTrails.contains(language) {
            // English and Turkish both put the type last as a separate word.
            return weighted(
                "{{person.lastName}} {{location.street_suffix}}",
                "{{person.firstName}} {{location.street_suffix}}")
        }
        return weighted(
            "{{location.street_suffix}} {{person.lastName}}",
            "{{location.street_suffix}} {{person.firstName}}")
    }

    /// Whether the building number precedes the street or follows it.
    static func address(for language: String, _ streets: Streets) -> Definition {
        let leads = streets.numberLeads.contains(language)
        let normal =
            leads
            ? "{{location.buildingNumber}} {{location.street}}"
            : "{{location.street}} {{location.buildingNumber}}"
        let full =
            leads
            ? "{{location.buildingNumber}} {{location.street}} {{location.secondaryAddress}}"
            : "{{location.street}} {{location.buildingNumber}} {{location.secondaryAddress}}"
        return .object([
            "normal": .list([.string(normal)]),
            "full": .list([.string(full)]),
        ])
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("authored/authored.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let streetsRaw = root["streets"] as? [String: Any],
            let literal = root["literal"] as? [String: [String: Any]]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/authored/authored.json is not the expected shape")
        }

        let streets = Streets(
            types: (streetsRaw["types"] as? [String: [String]]) ?? [:],
            locales: (streetsRaw["locales"] as? [String: [String]]) ?? [:],
            compounding: Set((streetsRaw["compounding"] as? [String]) ?? []),
            typeTrails: Set((streetsRaw["typeTrails"] as? [String]) ?? []),
            numberLeads: Set((streetsRaw["numberLeads"] as? [String]) ?? []),
            buildingNumber: (streetsRaw["buildingNumber"] as? [String]) ?? [])

        var contributions: [String: [String: Definition]] = [:]

        // Composed first, so the frozen half merges on top of it exactly as the JavaScript's
        // object spread did — `...streetContributions()` came first there too.
        for language in streets.locales.keys.sorted() {
            guard let suffixes = streets.types[language] else { continue }
            for code in streets.locales[language] ?? [] {
                contributions[code] = [
                    "location.street_suffix": .list(suffixes.map(Definition.string)),
                    "location.street_pattern": Self.pattern(for: language, streets),
                    "location.street_address": Self.address(for: language, streets),
                    "location.building_number": .list(
                        streets.buildingNumber.map(Definition.string)),
                ]
            }
        }

        // The frozen half merges on top, except where the JavaScript replaced the whole
        // entry. It builds its contributions as an object literal whose explicit keys come
        // *after* `...streetContributions()`, and object spread replaces a key outright
        // rather than merging into it — so an explicit entry for a locale that also has
        // street data silently discards that street data.
        //
        // fr_CA is the only collision: it belongs to the French street family and gets an
        // explicit entry for Canadian postcodes, so its own blob carries no street paths at
        // all. Harmless in effect, because fr_CA resolves streets through `fr` — but it is
        // an accident of object spread rather than a decision, and reproducing it by
        // accident again would be worse than naming it.
        let replaces = Set((root["replaces"] as? [String]) ?? [])
        for (code, paths) in literal {
            let converted = paths.mapValues(Definition.init(json:))
            if replaces.contains(code) {
                contributions[code] = converted
            } else {
                for (path, value) in converted { contributions[code, default: [:]][path] = value }
            }
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [("lists", "38")])
    }
}
