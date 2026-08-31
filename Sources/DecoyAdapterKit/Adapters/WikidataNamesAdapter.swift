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
        // ...but not `en_IN`, which is looked up by exact code before its language and so
        // needs to say so. It yields nothing: `en`'s three sets are deferred to the US
        // Census, and applying that rule to India — which is what the language fallback
        // does — is how an Indian locale came to produce "Jennifer Williams" beside a
        // Mumbai postcode. Its names are the romanised Indian ones and Wikidata is their
        // only source here.
        "en_IN": [],
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
        // The three Indian locales yield their surnames to `naamapadam`, which carries
        // between nine hundred and twelve hundred each against Wikidata's nought to twelve.
        // Same script on both sides, so this one really is only about volume.
        "kn_IN": ["surname"], "pa_IN": ["surname"],
        // Nepali surnames yield to `popular-names`, and the reason is script rather than
        // size. Wikidata's twelve are Devanagari; the only Nepali *given* names anybody
        // publishes are romanised, so Devanagari surnames beside them would be a chimera
        // inside one name. The romanised set of twenty-four keeps the whole name in one
        // script. See PopularNamesAdapter for why Nepal is romanised at all.
        "ne_NP": ["surname"],
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

    /// The script a language's names are written in, where another script is a mistake
    /// rather than a variant spelling.
    ///
    /// Wikidata labels are contributed by hand and the language tag is not enforced against
    /// the characters, so a `hi` label can hold Bengali and a `pa` label Urdu. Small
    /// numbers — one or two per list — but they compose: `hi_IN` produced
    /// `स्वप्निल চৌধুরী`, a Devanagari given name beside a Bengali surname, which is a
    /// chimera inside one name rather than across a fallback.
    ///
    /// Only for languages with a single settled script. Serbian is deliberately absent: it
    /// is written in two, and `sr_RS_latin` is handled by the transliteration table above.
    private static let expectedScript: [String: ClosedRange<UInt32>] = [
        "hi": 0x0900...0x097F,  // Devanagari
        "bn": 0x0980...0x09FF,  // Bengali
        "pa": 0x0A00...0x0A7F,  // Gurmukhi
        "gu": 0x0A80...0x0AFF,  // Gujarati
        "or": 0x0B00...0x0B7F,  // Odia
        "ta": 0x0B80...0x0BFF,  // Tamil
        "te": 0x0C00...0x0C7F,  // Telugu
        "kn": 0x0C80...0x0CFF,  // Kannada
        "ml": 0x0D00...0x0D7F,  // Malayalam
        "si": 0x0D80...0x0DFF,  // Sinhala
        "ka": 0x10A0...0x10FF,  // Georgian
        "hy": 0x0530...0x058F,  // Armenian
        "el": 0x0370...0x03FF,  // Greek
        "he": 0x0590...0x05FF,  // Hebrew
        "ko": 0xAC00...0xD7A3,  // Hangul syllables
    ]

    /// Every letter in `value` belongs to `range`. Marks, spaces and punctuation pass.
    static func inScript(_ value: String, _ range: ClosedRange<UInt32>) -> Bool {
        guard !value.isEmpty else { return false }
        var sawLetter = false
        for scalar in value.unicodeScalars {
            guard scalar.properties.isAlphabetic else { continue }
            sawLetter = true
            if !range.contains(scalar.value) { return false }
        }
        return sawLetter
    }

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
        var discarded: [DiscardRecord] = []

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
                let beforeScript = list.count
                if hasScript { list = list.filter { Self.matchesScript($0, latin: latin) } }
                if let range = Self.expectedScript[Self.language(of: code)] {
                    list = list.filter { Self.inScript($0, range) }
                }
                // The script filters, which are the ones with no other trace. They exist
                // because a `hi` label held Bengali and a `pa` label Urdu — one or two per
                // list, contributed by hand and never validated against the characters —
                // and they compose into `स्वप्निल চৌধুরী`. A filter guarding against
                // mislabelled upstream data is exactly the one you want to watch, because
                // the day it starts rejecting everything looks identical to the day the
                // language went quiet.
                if list.count != beforeScript {
                    discarded.append(
                        DiscardRecord(
                            scope: "\(code).\(kind)", filter: "script",
                            kept: list.count, seen: beforeScript))
                }

                if list.count < Self.minimumNames {
                    tooThin.append("\(code).\(kind)(\(list.count))")
                    discarded.append(
                        DiscardRecord(
                            scope: "\(code).\(kind)", filter: "floor",
                            kept: 0, seen: list.count))
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
            ],
            discarded: discarded)
    }
}
