import Foundation

/// Latin filler vocabulary, from Whitaker's Words.
///
/// Fills:
///   base    lorem.word
///
/// `base`, not `en`. Lorem is filler rather than language: every locale lacking its own
/// falls through to it.
///
/// ## Two things the port has to get exactly right
///
/// The dictionary is **latin1**, not UTF-8. Decoding it as UTF-8 mangles every accented
/// byte, and because the fields are fixed-width *byte* offsets, a multi-byte decode would
/// also shift every column — silently, producing plausible-looking rubbish rather than an
/// error.
///
/// And the layout is columnar: characters 0–19 are the first stem, 19–38 the second, and
/// everything from 76 is the part-of-speech codes and the gloss. Those are positions in a
/// byte-oriented file, so they are applied to bytes and the result decoded, not the other
/// way round.
public struct LatinWordsAdapter: Adapter {
    public static let id = "latin-words"
    public static let sources = ["whitakers-words"]

    public init() {}

    /// Whitaker's frequency codes, most frequent first. A, B and C are the words that
    /// actually appear in classical texts; the rest are hapax legomena and inscriptions.
    private static let frequent: Set<Character> = ["A", "B", "C"]

    private static let stem1 = 0..<19
    private static let stem2 = 19..<38
    private static let codes = 76

    /// latin1 is a byte-per-character mapping, so this cannot fail the way UTF-8 can.
    static func latin1(_ bytes: ArraySlice<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = try input.artifact("dictionary", for: Self.id)
        let data = [UInt8](try Data(contentsOf: path))

        var words = Set<String>()
        var entries = 0

        // Split on bytes, so a line is a line regardless of what encoding its contents are.
        var start = data.startIndex
        while start <= data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            defer { start = end + 1 }
            let line = data[start..<end]
            if end == data.endIndex && line.isEmpty { break }

            guard line.count >= 100 else { continue }
            entries += 1

            let base = line.startIndex
            let stem1 = Self.latin1(line[(base + Self.stem1.lowerBound)..<(base + Self.stem1.upperBound)])
                .trimmingCharacters(in: .whitespaces)
            let stem2 = Self.latin1(line[(base + Self.stem2.lowerBound)..<(base + Self.stem2.upperBound)])
                .trimmingCharacters(in: .whitespaces)
            let tail = Self.latin1(line[(base + Self.codes)...])
            let parts = tail.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
                .map(String.init)
            guard !parts.isEmpty else { continue }

            // AGE AREA GEO FREQ SOURCE — five single letters between the codes and the
            // gloss. The fourth is the frequency.
            guard let frequency = Self.frequency(in: Self.latin1(line)),
                Self.frequent.contains(frequency)
            else { continue }

            // Latin has no digits, no spaces inside a headword, and nothing shorter than
            // three letters worth using as filler.
            let usable =
                (3...14).contains(stem1.count)
                && stem1.allSatisfy { $0.isASCII && $0.isLetter }
            guard usable else { continue }

            let pos = parts[0]
            let declension = parts.count > 1 ? parts[1] : ""
            let nominativeIsWhole =
                (pos == "N" || pos == "ADJ") && declension == "3" && !stem2.isEmpty
                && stem2 != stem1
            if nominativeIsWhole || pos == "ADV" { words.insert(stem1.lowercased()) }
        }

        guard entries >= 30_000, words.count >= 1_000 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "Whitaker's dictionary yielded \(words.count) words from \(entries) entries — "
                    + "the fixed-width layout has changed")
        }

        return AdapterOutput(
            contributions: ["base": ["lorem.word": .list(words.sorted().map(Definition.string))]],
            stats: [("entries", String(entries)), ("words", String(words.count))])
    }

    /// The fourth of five consecutive single capitals, which is the frequency code.
    ///
    /// Matches `\b([A-Z]) ([A-Z]) ([A-Z]) ([A-Z]) ([A-Z]) ` — five capitals each followed
    /// by a space, the run starting at a word boundary.
    static func frequency(in line: String) -> Character? {
        let characters = Array(line)
        var index = 0
        while index + 9 < characters.count {
            let isBoundary =
                index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber)
            if isBoundary {
                var matched = true
                for step in 0..<5 {
                    let letter = characters[index + step * 2]
                    let space = characters[index + step * 2 + 1]
                    if !(letter.isUppercase && letter.isASCII && letter.isLetter) || space != " " {
                        matched = false
                        break
                    }
                }
                if matched { return characters[index + 6] }
            }
            index += 1
        }
        return nil
    }
}
