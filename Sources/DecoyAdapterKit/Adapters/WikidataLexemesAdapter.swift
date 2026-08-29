import Foundation

/// Everyday nouns per language, from a committed Wikidata lexeme snapshot.
///
/// Fills:
///   <each>   word.noun
///
/// ## Why not another wordnet
///
/// Vocabulary was the widest gap left after streets — fourteen roots of forty-five carried
/// their own words and thirty-one answered in English. The Open Multilingual Wordnet looks
/// like the answer and is not: the fourteen already wired up are exactly the permissively
/// licensed ones. Every remaining OMW language is CC BY-SA or CeCILL-C, which was
/// established by reading the licence each archive declares rather than a table describing
/// them — Arabic BY-SA 3.0, Dutch BY-SA 4.0, French CeCILL-C, Portuguese, Romanian, Slovak
/// and Slovenian all BY-SA.
///
/// Share-alike would put the whole corpus's Apache-2.0 redistribution in question for the
/// sake of one field, and this project's answer to "can this be distributed under
/// Apache-2.0" is checked on every build rather than concluded once.
///
/// Lexemes are a different part of Wikidata from the items the name and colour adapters
/// read: `L`-entities with a lemma, a language and a lexical category, contributed for
/// dictionary purposes. CC0, same endpoint, no new licence to clear.
///
/// ## Where a wordnet exists, it wins
///
/// A wordnet is curated for sense; lexemes are contributed for the dictionary and carry
/// spelling variants and historical forms side by side. So no locale appears in both — the
/// language table for this adapter lists only locales without wordnet vocabulary, and two
/// adapters claiming `word.noun` would be refused by the orchestrator regardless.
///
/// ## Script, again
///
/// Wikidata records the forms a language actually uses, which is not the same as the forms
/// one locale wants. Korean lexemes carry 독재 and 獨裁 — the same word in Hangul and in
/// Hanja — and Turkish carries `curcuna` beside its Ottoman spelling in Arabic script.
/// Neither is an error in Wikidata and both are wrong in a fixture, so the same script
/// expectation the name adapter uses is applied here.
public struct WikidataLexemesAdapter: Adapter {
    public static let id = "wikidata-lexemes"
    public static let sources = ["wikidata"]

    public init() {}

    /// Scripts a locale's vocabulary is written in, where another is a variant this corpus
    /// does not want mixed in. Shares its reasoning with `WikidataNamesAdapter`.
    private static let expectedScript: [String: ClosedRange<UInt32>] = [
        "ko": 0xAC00...0xD7A3,  // Hangul syllables, not Hanja
        "hi": 0x0900...0x097F,
        "bn": 0x0980...0x09FF,
        "pa": 0x0A00...0x0A7F,
        "kn": 0x0C80...0x0CFF,
        "ka": 0x10A0...0x10FF,
        "hy": 0x0530...0x058F,
        "el": 0x0370...0x03FF,
        "he": 0x0590...0x05FF,
        "zh": 0x4E00...0x9FFF,
    ]

    /// Latin-script languages whose lexemes also carry a historical non-Latin spelling.
    ///
    /// Turkish is the case: Wikidata holds the modern Latin form and the Ottoman Arabic one
    /// under the same language, and a Turkish fixture wants the former.
    private static let latinOnly: Set<String> = ["tr", "az", "vi", "cy", "sk", "sl", "cs"]

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let file = input.dataDirectory.appendingPathComponent("wikidata-lexemes.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as? [String: Any],
            let nouns = root["nouns"] as? [String: Any]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "data/wikidata-lexemes.json is not the expected shape")
        }
        let retrieved = (root["retrieved"] as? String) ?? "unknown"
        let roster = Set(input.locales)

        var contributions: [String: [String: Definition]] = [:]
        var taken: [String] = []
        var discarded: [DiscardRecord] = []

        for (code, raw) in nouns.sorted(by: { $0.key < $1.key }) {
            guard roster.contains(code), var list = raw as? [String], !list.isEmpty else {
                continue
            }
            let language = String(code.split(separator: "_")[0])
            let seen = list.count

            if let range = Self.expectedScript[language] {
                list = list.filter { inScript($0, range) }
            } else if Self.latinOnly.contains(language) {
                list = list.filter { isLatin($0) }
            }
            if list.count != seen {
                discarded.append(
                    DiscardRecord(scope: code, filter: "script", kept: list.count, seen: seen))
            }

            // Re-checked after filtering. The fetcher applied the same floor to the unfiltered
            // list, and Korean loses half of its to Hanja — so a language can clear the floor
            // at fetch time and fall under it here, which is the number that matters.
            guard list.count >= WikidataQueries.minimumLexemes else {
                discarded.append(
                    DiscardRecord(scope: code, filter: "floor", kept: 0, seen: list.count))
                continue
            }

            contributions[code] = ["word.noun": .list(list.sorted().map(Definition.string))]
            taken.append("\(code)(\(list.count))")
        }

        guard !taken.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "wikidata-lexemes produced nothing — is data/wikidata-lexemes.json present?")
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("retrieved", retrieved), ("locales", String(taken.count)),
                ("taken", taken.joined(separator: ",")),
            ],
            discarded: discarded)
    }

    private func inScript(_ value: String, _ range: ClosedRange<UInt32>) -> Bool {
        var sawLetter = false
        for scalar in value.unicodeScalars where scalar.properties.isAlphabetic {
            sawLetter = true
            if !range.contains(scalar.value) { return false }
        }
        return sawLetter
    }

    private func isLatin(_ value: String) -> Bool {
        var sawLetter = false
        for scalar in value.unicodeScalars where scalar.properties.isAlphabetic {
            sawLetter = true
            // Basic Latin through Latin Extended-B, which covers every diacritic these
            // languages use without admitting Cyrillic, Arabic or Greek.
            if !(0x0041...0x024F).contains(scalar.value) { return false }
        }
        return sawLetter
    }
}
