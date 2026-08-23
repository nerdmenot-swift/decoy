import Foundation

/// Given names and surnames per language, from a committed Wikidata snapshot.
///
/// Fills:
///   <each>   person.first_name.female / .male
///   <each>   person.last_name.generic
///
/// Wikidata records that a name exists; a registry records how many people bear it, and
/// that difference is the whole of realistic collision rates. So where a national registry
/// covers a field, this yields — see `deferred`.
public struct WikidataNamesAdapter: Adapter {
    public static let id = "wikidata-names"
    public static let sources = ["wikidata"]

    public init() {}

    /// Iterated in this order so a locale's paths land in the same sequence as before.
    private static let paths: [(kind: String, path: String)] = [
        ("female", "person.first_name.female"),
        ("male", "person.first_name.male"),
        ("surname", "person.last_name.generic"),
    ]

    /// The same floor the fetcher applies, re-checked here because the adapter is what
    /// decides the corpus. See `WikidataQueries.minimumNames` for why it is ten.
    private static let minimumNames = WikidataQueries.minimumNames

    /// Paths a national registry already fills, which this source yields to.
    ///
    /// Per-path rather than per-locale, because the registries are not symmetrical. INSEE
    /// publishes given names and not surnames, so French surnames are Wikidata's to fill
    /// and French given names are not.
    private static let deferred: [String: [String]] = [
        "en": ["female", "male", "surname"],
        "fr": ["female", "male"],
        "pl": ["female", "male"],
        // Surnames yielded to INE as of the refetch that gave Wikidata Spanish surnames
        // at all. It had none before — not because Wikidata lacks them, but because that
        // query kept coming back truncated and the run recorded the category as absent.
        // Once it succeeded, 3,815 arrived and collided with INE's 27,661 weighted ones.
        // The census wins: it is the whole population rather than the notable part of it.
        "es": ["female", "male", "surname"],
        "fi": ["female", "male"],
        "sv": ["female", "male", "surname"],
        "en_GB": ["female", "male"],
        "nb_NO": ["female", "male"],
        "sl_SI": ["female", "male"],
        "az": ["female", "male", "surname"],
        "he": ["female", "male"],
        // Vietnamese given names yield to the name database, which carries 1,571 female and
        // 1,570 male against Wikidata's fifty-seven. They only collided once the floor came
        // down far enough to admit fifty-seven at all.
        "vi": ["female", "male"],
        "zh_TW": ["surname"],
        // Wikidata gave `zh_CN` 41 surnames of which nine were romanisations and three
        // were labels ending in the character for "surname". Most of the rest were rare
        // compounds — 万俟, 南郭, 司空 — because those are what an encyclopaedia finds
        // notable, so a Chinese fixture set read like an English one where everybody is
        // called Featherstonehaugh. `chinese-names` supplies 745 ordinary ones instead.
        "zh_CN": ["surname"],
    ]

    static func language(of code: String) -> String { String(code.split(separator: "_")[0]) }

    /// Serbian is written in both alphabets and Wikidata holds both under `sr`.
    private static let serbianLatin: [Character: String] = [
        "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Ђ": "Đ", "Е": "E", "Ж": "Ž",
        "З": "Z", "И": "I", "Ј": "J", "К": "K", "Л": "L", "Љ": "Lj", "М": "M", "Н": "N",
        "Њ": "Nj", "О": "O", "П": "P", "Р": "R", "С": "S", "Т": "T", "Ћ": "Ć", "У": "U",
        "Ф": "F", "Х": "H", "Ц": "C", "Ч": "Č", "Џ": "Dž", "Ш": "Š",
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ђ": "đ", "е": "e", "ж": "ž",
        "з": "z", "и": "i", "ј": "j", "к": "k", "л": "l", "љ": "lj", "м": "m", "н": "n",
        "њ": "nj", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "ћ": "ć", "у": "u",
        "ф": "f", "х": "h", "ц": "c", "ч": "č", "џ": "dž", "ш": "š",
    ]

    /// Whether every scalar belongs to the named script, or is a mark, punctuation or space.
    ///
    /// Replaces `/^[\p{Script=Latin}\p{Mark}\p{Punctuation}\s]+$/u`. Written against
    /// `Unicode.Scalar.Properties` rather than a regex so the script test is the same one
    /// on every platform, which a regex engine's Unicode tables do not guarantee.
    static func matchesScript(_ value: String, latin: Bool) -> Bool {
        guard !value.isEmpty else { return false }
        for scalar in value.unicodeScalars {
            let properties = scalar.properties
            if properties.isWhitespace { continue }
            let category = properties.generalCategory
            switch category {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation:
                continue
            default:
                break
            }
            let name = properties.name ?? ""
            let inScript = latin ? name.hasPrefix("LATIN") : name.hasPrefix("CYRILLIC")
            if !inScript { return false }
        }
        return true
    }

    /// Whether an ancestor in the chain already supplies this language's names.
    static func ancestorCovers(_ code: String, chain: [String]?, names: [String: Any]) -> Bool {
        let language = Self.language(of: code)
        for ancestor in (chain ?? []).dropFirst() where Self.language(of: ancestor) == language {
            if names[ancestor] != nil || names[Self.language(of: ancestor)] != nil { return true }
        }
        return false
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("wikidata-names.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let names = root["names"] as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/wikidata-names.json is not the expected shape")
        }
        let retrieved = (root["retrieved"] as? String) ?? "unknown"

        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []
        var tooThin: [String] = []

        // Driven by the locale roster rather than by the data file. The other way round
        // matches on exact code and silently skips every locale whose language has no bare
        // entry, which is what left Portuguese, Czech, Slovene, Norwegian, Bengali,
        // Georgian, Serbian and Yoruba fixtures on English names while their names sat in
        // the file.
        for code in input.locales where code != "base" {
            let exact = names[code] as? [String: Any]
            if exact == nil && Self.ancestorCovers(code, chain: input.chains[code], names: names) {
                continue
            }
            guard let sets = exact ?? (names[Self.language(of: code)] as? [String: Any]) else {
                continue
            }

            let scriptSuffix = code.split(separator: "_").last.map(String.init)
            let latin = scriptSuffix == "latin"
            let hasScript = latin || scriptSuffix == "cyrl"

            let deferred =
                Self.deferred[code] ?? Self.deferred[Self.language(of: code)] ?? []
            var contribution: [String: Definition] = [:]

            for (kind, path) in Self.paths {
                if deferred.contains(kind) { continue }
                guard var list = sets[kind] as? [String] else { continue }

                // Converted before filtering, not instead of it. The filter still runs, so
                // anything the table does not cover is dropped rather than shipped
                // half-converted.
                if code == "sr_RS_latin" {
                    var seen = Set<String>()
                    var converted: [String] = []
                    for value in list {
                        let latinised = String(
                            value.map { Self.serbianLatin[$0] ?? String($0) }.joined())
                        if seen.insert(latinised).inserted { converted.append(latinised) }
                    }
                    list = converted
                }
                if hasScript { list = list.filter { Self.matchesScript($0, latin: latin) } }

                if list.count < Self.minimumNames {
                    tooThin.append("\(code).\(kind)(\(list.count))")
                    continue
                }
                contribution[path] = .list(CodeUnitOrder.sorted(list).map(Definition.string))
            }

            if !contribution.isEmpty {
                let total = contribution.values.reduce(0) { sum, value in
                    if case .list(let items) = value { return sum + items.count }
                    return sum
                }
                contributions[code] = contribution
                taken.append("\(code)(\(total))")
            }
        }

        guard !taken.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "wikidata-names produced nothing — is data/wikidata-names.json present?")
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("retrieved", retrieved), ("locales", String(taken.count)),
                ("taken", taken.joined(separator: ",")),
                ("tooThin", tooThin.joined(separator: ",")),
            ])
    }
}
