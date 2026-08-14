import Foundation

/// Commerce, finance and grammar vocabulary for the languages English was standing in for.
///
/// Fills, for each locale of each language covered:
///   commerce.product_name.*, commerce.department, finance.account_type,
///   finance.transaction_type, vehicle.type, vehicle.bicycle_type, person.gender,
///   word.preposition / .conjunction / .interjection, company.name_pattern,
///   location.direction.cardinal_abbr / .ordinal_abbr, and person.prefix.* where the
///   language has honorifics of its own.
///
/// ## Data in a data file, composition in code
///
/// The lists live in `data/authored/commerce.json`; the language-to-locale mapping and the
/// loop over it stay here. That split is deliberate. Freezing the *output* per locale
/// would have been simpler and would have thrown away what makes this adapter useful:
/// `LOCALES` says German vocabulary serves `de`, `de_AT` and `de_CH`, so adding a German
/// locale to the roster gives it German commerce data with no edit here at all. A frozen
/// per-locale table would need one.
///
/// Moving the values out of source is worth doing on its own terms — 537 lines of literals
/// in a module is data pretending to be code, and as JSON it diffs and reviews properly.
public struct AuthoredCommerceAdapter: Adapter {
    public static let id = "authored-commerce"
    public static let sources = ["decoy-authored"]

    public init() {}

    /// Path in the corpus, and the key holding its values.
    ///
    /// Ordered, so the emitted paths land in the same sequence the JavaScript produced.
    private static let fields: [(path: String, key: String)] = [
        ("commerce.product_name.adjective", "adjective"),
        ("commerce.product_name.material", "material"),
        ("commerce.product_name.product", "product"),
        ("commerce.department", "department"),
        ("finance.account_type", "accountType"),
        ("finance.transaction_type", "transactionType"),
        ("vehicle.type", "vehicleType"),
        ("vehicle.bicycle_type", "bicycleType"),
        ("person.gender", "gender"),
        ("word.preposition", "preposition"),
        ("word.conjunction", "conjunction"),
        ("word.interjection", "interjection"),
        // The English company pattern joins three surnames with the English word `and`,
        // and every locale inherited it — a German firm came out as `Biber, Gumbel and
        // Happe`. A conjunction is the smallest possible piece of grammar and the most
        // visible when it is the wrong language.
        ("company.name_pattern", "companyNamePattern"),
        // English `N, E, S, W` is not merely unlocalised, it is wrong: German and Dutch
        // abbreviate Ost/Oost to `O`, and the Romance languages abbreviate
        // Oeste/Ouest/Ovest to `O` where English has `W`.
        ("location.direction.cardinal_abbr", "cardinalAbbr"),
        ("location.direction.ordinal_abbr", "ordinalAbbr"),
        // Honorifics, where the language has them. Absent rather than empty for languages
        // that do not, so the block that stops English titles leaking still applies.
        ("person.prefix.female", "prefixFemale"),
        ("person.prefix.male", "prefixMale"),
    ]

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("authored/commerce.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let languages = root["languages"] as? [String: Any],
            let localesFor = root["locales"] as? [String: [String]]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/authored/commerce.json is not the expected shape")
        }

        let roster = Set(input.locales)
        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []

        for language in languages.keys.sorted() {
            guard let spec = languages[language] as? [String: Any],
                let codes = localesFor[language]
            else { continue }

            for code in codes where roster.contains(code) {
                var paths: [String: Definition] = [:]

                // The pattern is a single value stored as one, so it ships as a one-entry
                // list the way every other pattern path does.
                if let pattern = spec["pattern"] as? String {
                    paths["commerce.product_name.pattern"] = .list([.string(pattern)])
                }
                for (path, key) in Self.fields {
                    // Converted generically rather than cast to [String]. Not every field
                    // is a plain list: `company.name_pattern` is weighted, so the entries
                    // are objects — and `as? [String]` on it fails silently, which showed
                    // up as one path simply absent from every locale.
                    guard let raw = spec[key], !(raw is NSNull) else { continue }
                    let value = Definition(json: raw)
                    if case .list(let items) = value, items.isEmpty { continue }
                    paths[path] = value
                }

                contributions[code] = paths
                taken.append(code)
            }
        }

        guard !taken.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "authored-commerce matched no locales")
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("locales", String(taken.count)), ("taken", taken.joined(separator: ",")),
            ])
    }
}
