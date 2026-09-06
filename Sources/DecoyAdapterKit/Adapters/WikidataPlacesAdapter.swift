import Foundation

/// City names in the script the country actually writes them in.
///
/// Fills, for the sixteen locales in `WikidataQueries.cityLocales`:
///   <each>   location.city_name
///   <each>   location.place        city / state / state_code, as one row
///
/// ## What was wrong
///
/// The corpus's gazetteer is GeoNames-derived and romanises everything, so every locale
/// outside Latin script generated its people in one script and its geography in another: a
/// Japanese row read 神戸あんじゅ living in `Abashiri`, a Russian one Зоил Алявдин in
/// `Abakan`. The published matrix marked Cities native for all forty-three roots, which
/// made the single field it showed as universally covered the one that was wrong in every
/// non-Latin language.
///
/// It survived a long time because nothing about it looks like a bug. The field is
/// populated, the values are real places, and the only tell is that they are spelled in
/// somebody else's alphabet.
///
/// ## Why the pair is fetched together
///
/// `location.place` exists so that a city and its subdivision cannot disagree —
/// `corpus-strategy.md` opens its coherent-records argument with `city: "Boston",
/// state: "CA"`, which passes most validators and is nonsense. Replacing only the city
/// would have reintroduced exactly that, in a new form: a native city beside a romanised
/// state. So the containment comes from Wikidata's `P131` in the same query as the label,
/// which is better grounded than the admin-code join the gazetteer needs.
///
/// `state_code` is empty here. The gazetteer supplies GeoNames' own subdivision codes and
/// Wikidata does not have them; empty rather than absent keeps the composite one shape
/// across every row, which is the rule `CitiesAdapter` already follows.
///
/// ## What this deliberately does not touch
///
/// `location.state` stays with ISO 3166-2. That standard romanises on purpose — `JP-13` is
/// `Tôkyô` — so its names are correct *as ISO names*, and they carry the subdivision codes
/// that a Wikidata label cannot. `state()` therefore answers with the standard's name and
/// `place()` with the name people write on an envelope, which is a real distinction rather
/// than an oversight.
///
/// `location.county` is dropped for these locales rather than replaced. The gazetteer gave
/// Russian `Abakan Urban District` — not romanised Russian but an English description of
/// the administrative type — and an honest gap beats that.
public struct WikidataPlacesAdapter: Adapter {
    public static let id = "wikidata-places"
    public static let sources = ["wikidata"]

    public init() {}

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("wikidata-cities.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let places = root["places"] as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/wikidata-cities.json is not the expected shape")
        }
        let retrieved = (root["retrieved"] as? String) ?? "unknown"
        let roster = Set(input.locales)

        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []
        var discarded: [DiscardRecord] = []

        for entry in WikidataQueries.cityLocales {
            guard roster.contains(entry.code) else { continue }
            guard let rows = places[entry.code] as? [[String: String]], !rows.isEmpty else {
                continue
            }

            let cities = rows.compactMap { $0["city"] }
            guard cities.count >= WikidataQueries.minimumCities else {
                // Re-checked here and not only at fetch time. The snapshot is committed and
                // can be edited; a floor that only ran against the endpoint would not notice.
                discarded.append(
                    DiscardRecord(
                        scope: entry.code, filter: "floor", kept: 0, seen: cities.count))
                continue
            }

            contributions[entry.code] = [
                "location.city_name": .list(CodeUnitOrder.sorted(cities).map(Definition.string)),
                "location.place": .list(
                    rows.map { row in
                        .object([
                            "city": .string(row["city"] ?? ""),
                            "state": .string(row["state"] ?? ""),
                            "state_code": .string(""),
                        ])
                    }),
            ]
            taken.append("\(entry.code)(\(cities.count))")
        }

        guard !taken.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "wikidata-places produced nothing — is data/wikidata-cities.json present?")
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("retrieved", retrieved), ("locales", String(taken.count)),
                ("taken", taken.joined(separator: ",")),
            ],
            discarded: discarded)
    }
}
