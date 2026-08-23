import Foundation

/// Nepali given names and surnames, which no register publishes.
///
/// Fills:
///   ne_NP   person.first_name.female
///   ne_NP   person.first_name.male
///   ne_NP   person.last_name.generic
///
/// ## Why Nepal has no statistics office here
///
/// `CivilNamesAdapter` reads twelve national registers, and not one of them is South Asian.
/// That is not an oversight: India's Census publishes some two hundred tables under GODL
/// and none of them counts names, and Nepal, Pakistan, Sri Lanka and Bangladesh publish
/// nothing comparable either. The absence is in the world's open data rather than in the
/// search, which is why this region leans on aggregate compilations where Europe leans on
/// censuses.
///
/// ## Nepal only
///
/// The file covers a hundred and six countries and this adapter takes one, because a locale
/// needs *both* halves of a name in *one* script:
///
/// - **Sri Lanka** has fifty surnames and no given names. Wikidata's only Sinhala given
///   names are six, in Sinhala script, and pairing those with Latin surnames is a chimera
///   inside a single name. So `si_LK` is not viable, for the same reason Telugu, Marathi
///   and Odia have no locale.
/// - **India** is covered better by Wikidata's Hindi, which carries 211 given names in
///   Devanagari against this file's twenty in Latin.
/// - **Bangladesh** is covered better by Wikidata's Bengali — 270 and 246 against ten.
///
/// ## Romanised, deliberately
///
/// Nepali is written in Devanagari, and the file's Nepali *surnames* carry both scripts
/// while its given names are Latin only. Devanagari surnames beside Latin given names is
/// precisely the mixture this corpus refuses, so the romanised column is taken for both.
/// Romanised Nepali names are what passports, airline systems and English-language records
/// hold, which makes them a real form rather than a transliteration invented here.
///
/// ## Unweighted
///
/// The file carries counts for some countries and not for Nepal. Weighting the list from
/// anything else would mean inventing a distribution and shipping it as measured, which is
/// the refusal `az-adlar` and `vietnamese-names` already make.
public struct PopularNamesAdapter: Adapter {
    public static let id = "popular-names"
    public static let sources = ["popular-names"]

    public init() {}

    /// The country column, and the locale it fills.
    private static let country = "NP"
    private static let locale = "ne_NP"

    /// Below these the upstream has changed shape rather than merely been updated.
    ///
    /// Set under what it currently yields — ten given names per gender and twenty-four
    /// surnames — to catch a file that arrives empty or re-keyed, not to pin a number that
    /// may move. Ten a side is thin, and it is the whole of what anybody publishes.
    private static let minimumGiven = 8
    private static let minimumSurnames = 15

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        guard input.locales.contains(Self.locale) else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster no longer carries `\(Self.locale)`")
        }

        var contribution: [String: Definition] = [:]
        var stats: [(String, String)] = []

        let forenames = try rows(input, "forenames")
        for (kind, code) in [("female", "F"), ("male", "M")] {
            let names = distinct(
                forenames.filter { $0["Gender"] == code }.compactMap { romanized($0) })
            guard names.count >= Self.minimumGiven else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id,
                    detail: "\(Self.country) \(kind) yielded \(names.count) given names")
            }
            contribution["person.first_name.\(kind)"] = .list(names.map(Definition.string))
            stats.append((kind, String(names.count)))
        }

        let surnames = distinct(try rows(input, "surnames").compactMap { romanized($0) })
        guard surnames.count >= Self.minimumSurnames else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "\(Self.country) yielded \(surnames.count) surnames")
        }
        contribution["person.last_name.generic"] = .list(surnames.map(Definition.string))
        stats.append(("surname", String(surnames.count)))

        return AdapterOutput(contributions: [Self.locale: contribution], stats: stats)
    }

    /// The rows for this adapter's country, as dictionaries keyed by the header.
    ///
    /// The files are UTF-8 with a byte order mark, so the first header reads `\u{FEFF}Country`
    /// unless it is stripped — and a lookup for `Country` then finds nothing, which reads
    /// as "this file has no countries" rather than as an encoding detail.
    private func rows(_ input: AdapterInput, _ artifact: String) throws -> [[String: String]] {
        let url = try input.artifact(artifact, for: Self.id)
        var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let table = CSV.parse(text)
        guard let header = table.first, header.contains("Country") else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "\(artifact): no `Country` column in \(table.first ?? [])")
        }
        return table.dropFirst().compactMap { row in
            guard row.count == header.count else { return nil }
            let entry = Dictionary(uniqueKeysWithValues: zip(header, row))
            return entry["Country"] == Self.country ? entry : nil
        }
    }

    /// The romanised spelling, which is the column both name kinds share.
    private func romanized(_ row: [String: String]) -> String? {
        let name = (row["Romanized Name"] ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func distinct(_ names: [String]) -> [String] {
        var seen = Set<[UInt16]>()
        return CodeUnitOrder.sorted(names.filter { seen.insert(CodeUnitOrder.key($0)).inserted })
    }
}
