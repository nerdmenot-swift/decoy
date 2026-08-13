import Foundation

/// Persian filler vocabulary, from the Lilak spell-checking dictionary.
///
/// Fills:
///   fa    lorem.word
public struct PersianWordsAdapter: Adapter {
    public static let id = "persian-words"
    public static let sources = ["lilak"]

    public init() {}

    private static let keep = 10_000
    private static let minimumLength = 3

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("lilak", for: Self.id)
        let file = directory.appendingPathComponent("fa-IR/fa-IR.dic")
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)

        // The first line of a .dic file is the entry count, not an entry.
        let lines = text.components(separatedBy: "\n").dropFirst()

        var words: [String] = []
        for line in lines {
            // `word/FLAGS` — the affix flags describe inflection and are not part of the
            // word.
            let word = (line.components(separatedBy: "/").first ?? "")
                .trimmingCharacters(in: .whitespaces)
            if word.isEmpty { continue }

            // Latin letters and digits mark abbreviations and units; the zero-width
            // non-joiner marks multi-part compounds that read as two words.
            let unwanted = word.unicodeScalars.contains { scalar in
                let value = scalar.value
                let isASCIILetterOrDigit =
                    (value >= 48 && value <= 57) || (value >= 65 && value <= 90)
                    || (value >= 97 && value <= 122)
                return isASCIILetterOrDigit || value == 0x2E || value == 0x200C
            }
            if unwanted { continue }
            if word.unicodeScalars.contains(where: { CharacterSet.whitespaces.contains($0) }) {
                continue
            }
            // Length in code points, matching JavaScript's `.length` for this data: every
            // character here is in the BMP, so units and scalars agree.
            if word.unicodeScalars.count < Self.minimumLength { continue }

            words.append(word)
        }

        guard words.count >= 10_000 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "Lilak yielded only \(words.count) words — the format has changed")
        }

        // Shortest first, then alphabetically, keep the first ten thousand, then sort for
        // the corpus. The two-stage sort is the selection rule: short words make better
        // filler, and re-sorting afterwards is what the table wants.
        var seen = Set<String>()
        var distinct: [String] = []
        for word in words where seen.insert(word).inserted { distinct.append(word) }

        let kept =
            distinct
            .sorted {
                let left = $0.unicodeScalars.count
                let right = $1.unicodeScalars.count
                return left == right ? $0 < $1 : left < right
            }
            .prefix(Self.keep)
            .sorted()

        return AdapterOutput(
            contributions: ["fa": ["lorem.word": .list(kept.map(Definition.string))]],
            stats: [("available", String(words.count)), ("kept", String(kept.count))])
    }
}
