import Foundation

/// Vocabulary by part of speech, from the Open Multilingual Wordnet.
///
/// Fills:
///   <each>   word.noun / word.verb / word.adjective / word.adverb
///
/// Fourteen separate wordnets, each its own source with its own licence, which is why this
/// adapter credits per locale rather than crediting one source for all of them.
public struct WordNetAdapter: Adapter {
    public static let id = "wordnet"
    public static let sources = [
        "omw-cmn", "omw-da", "omw-el", "omw-en", "omw-es", "omw-fi", "omw-he", "omw-hr",
        "omw-id", "omw-it", "omw-ja", "omw-nb", "omw-pl", "omw-sv",
    ]

    public init() {}

    /// Source to the locales it fills. `omw-th` went with the `th` locale in the roster
    /// cut; no other locale used it.
    private static let wordnets: [(source: String, locales: [String])] = [
        ("omw-cmn", ["zh_CN"]), ("omw-da", ["da"]), ("omw-el", ["el"]), ("omw-en", ["en"]),
        ("omw-es", ["es"]), ("omw-fi", ["fi"]), ("omw-he", ["he"]), ("omw-hr", ["hr"]),
        ("omw-id", ["id_ID"]), ("omw-it", ["it"]), ("omw-ja", ["ja"]), ("omw-nb", ["nb_NO"]),
        ("omw-pl", ["pl"]), ("omw-sv", ["sv"]),
    ]

    private static let pathForPos: [String: String] = [
        "n": "word.noun", "v": "word.verb", "a": "word.adjective",
        "s": "word.adjective", "r": "word.adverb",
    ]

    /// A word carrying at least this many senses is common enough to be worth drawing.
    private static let minimumSenses = 2
    /// Below this a filtered list is too thin to be worth the filter, so keep everything.
    private static let viableList = 40

    /// Whether a lemma is a single ordinary word.
    ///
    /// OMW lemmas include multi-word expressions (`abnormal_condition`) and proper nouns.
    /// The lower length bound is script-aware: three characters is reasonable for Latin
    /// and would discard most of Japanese, Chinese and Thai, where words are short.
    static func isOrdinaryWord(_ word: String) -> Bool {
        // `("0"..."9").contains`, not `isNumber`. Swift's `isNumber` is true for anything
        // carrying a Unicode numeric value, which includes the CJK ideographic numerals —
        // 一, 二, 三 — so it threw out forty-eight Japanese words that are ordinary
        // vocabulary rather than digits. The JavaScript's `[0-9]` means ASCII digits, and
        // that is what the rule is for: stripping catalogue numbers out of lemmas.
        if word.contains(where: {
            $0 == " " || $0 == "_" || $0 == "-" || $0 == "." || $0 == "'" || $0 == "\u{2019}"
                || ($0.isASCII && $0.isNumber)
        }) { return false }
        // Proper nouns in cased scripts. For uncased scripts this is identity and passes.
        if word != word.lowercased() { return false }

        // Code points, not Characters, and this one is a decision rather than a
        // transcription. Hebrew lemmas carry niqqud — vowel points, which are combining
        // marks — so "מַשְׁמָעוּתִי" is seven grapheme clusters and thirteen code points. Counting
        // clusters admits words the JavaScript's upper bound rejected, five of them in
        // Hebrew adverbs alone.
        //
        // Arguably clusters are the better measure: the comment above says "characters",
        // and a seven-letter word is not thirteen characters by any reading a speaker
        // would recognise. But that is a judgement about Hebrew orthography, the bound was
        // tuned against these semantics, and a port is the wrong moment to decide it. This
        // reproduces the existing behaviour; changing it is a separate, deliberate call.
        let count = word.unicodeScalars.count
        let isLatin = !word.isEmpty && word.allSatisfy { $0.isASCII && $0.isLowercase && $0.isLetter }
        return isLatin ? (3...14).contains(count) : (1...12).contains(count)
    }

    /// The five entities legal in an XML attribute.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return
            text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Words by path, each carrying the greatest sense count seen for it.
    static func parseLexicon(_ xml: String) -> [String: [String: Int]] {
        var byPos: [String: [String: Int]] = [:]

        for entry in xml.components(separatedBy: "<LexicalEntry").dropFirst() {
            guard let lemmaStart = entry.range(of: "<Lemma ") else { continue }
            guard let writtenForm = Self.attribute("writtenForm", in: entry, from: lemmaStart.upperBound),
                let pos = Self.attribute("partOfSpeech", in: entry, from: lemmaStart.upperBound),
                let path = Self.pathForPos[pos]
            else { continue }

            let word = Self.decodeEntities(writtenForm)
            guard Self.isOrdinaryWord(word) else { continue }

            let senses = entry.components(separatedBy: "<Sense ").count - 1
            byPos[path, default: [:]][word] = max(byPos[path]?[word] ?? 0, senses)
        }
        return byPos
    }

    static func attribute(_ name: String, in text: String, from start: String.Index) -> String? {
        guard let key = text.range(of: "\(name)=\"", range: start..<text.endIndex),
            let end = text.range(of: "\"", range: key.upperBound..<text.endIndex)
        else { return nil }
        return String(text[key.upperBound..<end.lowerBound])
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        var contributions: [String: [String: Definition]] = [:]
        var sourceByLocale: [String: String] = [:]
        var stats: [(String, String)] = []

        for (source, locales) in Self.wordnets {
            let code = String(source.dropFirst("omw-".count))
            let directory = try input.artifact("wn_\(code)", for: Self.id)
            let file = directory.appendingPathComponent("\(source)/\(source).xml")
            let xml = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            let byPos = Self.parseLexicon(xml)

            var paths: [String: Definition] = [:]
            var total = 0
            for (path, words) in byPos {
                let common = words.filter { $0.value >= Self.minimumSenses }.map(\.key)
                // Smaller wordnets have too few polysemous entries for the filter to leave
                // a usable list; there, everything is better than almost nothing.
                let chosen = common.count >= Self.viableList ? common : Array(words.keys)
                guard !chosen.isEmpty else { continue }
                let sorted = CodeUnitOrder.sorted(chosen)
                total += sorted.count
                paths[path] = .list(sorted.map(Definition.string))
            }

            guard !paths.isEmpty else { continue }
            for locale in locales {
                contributions[locale] = paths
                sourceByLocale[locale] = source
            }
            stats.append((code, String(total)))
        }

        return AdapterOutput(
            contributions: contributions, stats: stats, sourceByLocale: sourceByLocale)
    }
}
