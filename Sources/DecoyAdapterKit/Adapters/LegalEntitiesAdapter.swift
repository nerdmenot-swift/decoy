import Foundation

/// Legal entity forms — GmbH, SARL, Ltd — from the GLEIF ELF register.
///
/// Fills:
///   <each>   company.legal_entity_type
public struct LegalEntitiesAdapter: Adapter {
    public static let id = "legal-entities"
    public static let sources = ["gleif-elf", "cldr-48"]
    public static let attributeTo: String? = "gleif-elf"

    public init() {}

    private static let minimumForms = 2
    private static let maximumLength = 12

    /// Language codes the register writes differently from the locale roster.
    ///
    /// GLEIF files Norway's forms under `no`, the macrolanguage; the roster carries `nb`,
    /// Bokmål, which is the standard those forms are actually written in. Seventeen
    /// abbreviations — `AS`, `ASA`, `ANS`, `KF`, `SF` — sat unused behind that two-letter
    /// difference, and Norwegian companies got English ones instead.
    ///
    /// Deliberately not a general "try the country's other languages" fallback. That would
    /// hand `hi_IN` India's English forms, which is a different question with a different
    /// answer: India legislates its company forms in English, so `Pvt Ltd` reaching Hindi
    /// through the fallback chain is correct rather than a gap to close here.
    private static let registerLanguage: [String: String] = ["nb": "no"]

    /// An initial run of capitals, two to six of them, followed by a space or the end.
    ///
    /// Replaces `^([\p{Lu}][\p{Lu}.]{1,5})(?=\s|$)`. Deliberately narrow: it recovers `SA`,
    /// `SARL` and `SCP` from the front of a French entity name and leaves `Syndicat de
    /// salariés` alone, because that leads with a word rather than an abbreviation.
    static func leadingAbbreviation(in name: String) -> String? {
        let characters = Array(name)
        guard let first = characters.first, first.isUppercase, first.isLetter else { return nil }

        var length = 1
        while length < characters.count && length < 6 {
            let character = characters[length]
            guard (character.isUppercase && character.isLetter) || character == "." else { break }
            length += 1
        }
        guard length >= 2 else { return nil }
        // The lookahead: what follows must be whitespace or nothing.
        if length < characters.count && !characters[length].isWhitespace { return nil }
        return String(characters[0..<length])
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let likelySubtags = try CLDR.likelySubtags(under: core)
        let rows = CSV.parse(
            String(
                decoding: try Data(contentsOf: try input.artifact("list", for: Self.id)),
                as: UTF8.self))

        guard let header = rows.first else {
            throw AdapterFailure.shapeChanged(adapter: Self.id, detail: "gleif-elf is empty")
        }
        func column(_ name: String) throws -> Int {
            guard let index = header.firstIndex(where: { $0 == name || $0.hasPrefix(name) })
            else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id, detail: "gleif-elf: no '\(name)' column — the schema has changed")
            }
            return index
        }
        let countryColumn = try column("Country Code (ISO 3166-1)")
        let languageColumn = try column("Language Code (ISO 639-1)")
        let nameColumn = try column("Entity Legal Form name Local name")
        let abbreviationsColumn = try column("Abbreviations Local language")
        let statusColumn = try column("ELF Status")

        // (country, language) -> the forms recorded for it. Insertion-ordered, because the
        // emitted list is sorted afterwards but the set must be built the same way.
        var byJurisdiction: [String: [String]] = [:]
        var seenPerJurisdiction: [String: Set<String>] = [:]

        for row in rows.dropFirst() {
            let field = { (index: Int) in index < row.count ? row[index] : "" }
            guard field(statusColumn) == "ACTV" else { continue }
            let country = field(countryColumn).trimmingCharacters(in: .whitespaces)
            let language = field(languageColumn).trimmingCharacters(in: .whitespaces).lowercased()
            guard !country.isEmpty, !language.isEmpty else { continue }

            // Several abbreviations per form, separated by semicolons, and each is a real
            // way of writing it — `KG`, `GmbH & Co. KG` and `Stiftung & Co. KG` are all
            // Kommanditgesellschaften. Interior quotes survive the register's own quoting.
            let declared = field(abbreviationsColumn)
                .components(separatedBy: ";")
                .map {
                    $0.replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty }
            var forms = declared.filter { (2...Self.maximumLength).contains($0.count) }

            // A one-character abbreviation is registry shorthand, not a suffix. Japan
            // records 株 for 株式会社, which is how a form is marked in the commercial
            // register; a Japanese company is 丸野情報株式会社 and never 丸野情報株.
            //
            // Keyed on a short abbreviation *being present*, not on the column being empty.
            // An empty column means the form has no suffix at all, and falling back to the
            // name there fills French with `Congrégation` and `Métropole` — entity
            // categories no company appends to itself.
            if forms.isEmpty && declared.contains(where: { $0.count == 1 }) {
                let name = field(nameColumn).trimmingCharacters(in: .whitespaces)
                if (2...Self.maximumLength).contains(name.count) { forms = [name] }
            }

            // France leaves the abbreviation column empty on almost all of its 255 forms
            // and puts the abbreviation at the front of the name instead — `SARL
            // d'attribution`. Without this France ships five forms and not one is SARL.
            if forms.isEmpty,
                let leading = Self.leadingAbbreviation(
                    in: field(nameColumn).trimmingCharacters(in: .whitespaces))
            {
                forms = [leading]
            }
            guard !forms.isEmpty else { continue }

            let key = "\(country) \(language)"
            for form in forms where seenPerJurisdiction[key, default: []].insert(form).inserted {
                byJurisdiction[key, default: []].append(form)
            }
        }

        guard byJurisdiction.count >= 50 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "gleif-elf yielded \(byJurisdiction.count) jurisdictions — verify before re-pinning"
            )
        }

        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []
        var unmatched: [String] = []

        for code in input.locales where code != "base" {
            guard let region = CLDR.region(for: code, likelySubtags: likelySubtags) else {
                continue
            }
            let root = String(code.split(separator: "_")[0])
            let language = Self.registerLanguage[root] ?? root
            guard let forms = byJurisdiction["\(region) \(language)"],
                forms.count >= Self.minimumForms
            else {
                unmatched.append("\(code)(\(region))")
                continue
            }
            contributions[code] = [
                "company.legal_entity_type": .list(
                    CodeUnitOrder.sorted(forms).map(Definition.string))
            ]
            taken.append("\(code)(\(forms.count))")
        }

        // Reported as discards rather than only as a stats line. Norway sat in this list
        // for as long as the list was prose: seventeen abbreviations the register holds,
        // missed because it files them under `no` and the roster says `nb`. A locale
        // dropping a whole field belongs somewhere a build can check.
        let discarded = unmatched.map {
            DiscardRecord(scope: $0, filter: "no-forms-for-jurisdiction", kept: 0, seen: 1)
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("jurisdictions", String(byJurisdiction.count)),
                ("locales", String(taken.count)),
                ("taken", taken.joined(separator: ",")),
                ("unmatched", unmatched.joined(separator: ",")),
            ],
            discarded: discarded)
    }
}
