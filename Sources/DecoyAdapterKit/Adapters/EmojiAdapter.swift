import Foundation

/// Emoji by category, from the Unicode emoji-test data file.
///
/// Fills:
///   base    internet.emoji.<category>   for ten categories
public struct EmojiAdapter: Adapter {
    public static let id = "emoji"
    public static let sources = ["unicode-emoji"]

    public init() {}

    private static let categoryForGroup: [String: String] = [
        "Smileys & Emotion": "smiley",
        "Animals & Nature": "nature",
        "Food & Drink": "food",
        "Travel & Places": "travel",
        "Activities": "activity",
        "Objects": "object",
        "Symbols": "symbol",
        "Flags": "flag",
    ]

    /// Subgroups of `People & Body` that are anatomy rather than people.
    static func isBodyPart(_ subgroup: String) -> Bool {
        subgroup.hasPrefix("hand") || subgroup == "body-parts"
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = try input.artifact("emoji", for: Self.id)
        let text = String(decoding: try Data(contentsOf: path), as: UTF8.self)

        // Insertion-ordered, because the emitted list is the file's order rather than a
        // sorted one and a Dictionary would lose it.
        var order: [String] = []
        var byCategory: [String: [String]] = [:]
        var group = ""
        var subgroup = ""
        var skipped = 0

        for line in Lines.split(text) {
            if line.hasPrefix("# group:") {
                group = String(line.dropFirst("# group:".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("# subgroup:") {
                subgroup = String(line.dropFirst("# subgroup:".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Only fully-qualified sequences. The file also lists minimally-qualified and
            // unqualified forms of the same emoji — sequences missing a variation
            // selector, which render inconsistently and are present so parsers can
            // recognise them, not so anything emits them.
            guard Self.isFullyQualified(line) else { continue }

            // `Component` is skin-tone swatches and hair colours: modifiers, not emoji
            // anybody sends on their own.
            if group == "Component" {
                skipped += 1
                continue
            }

            let category: String? =
                Self.categoryForGroup[group]
                ?? (group == "People & Body"
                    ? (Self.isBodyPart(subgroup) ? "body" : "person") : nil)
            guard let category else {
                skipped += 1
                continue
            }

            // The emoji itself is the first token after the `#` that follows the status.
            let parts = line.components(separatedBy: "#")
            guard parts.count > 1,
                let emoji = parts[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).first
            else { continue }

            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(String(emoji))
        }

        let categories = byCategory.keys.sorted()
        guard categories.count == 10 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "expected 10 emoji categories, got \(categories.count) "
                    + "(\(categories.joined(separator: ", "))) — the group taxonomy has changed")
        }

        var contributions: [String: Definition] = [:]
        var total = 0
        for category in categories {
            let list = byCategory[category] ?? []
            total += list.count
            // Deduplicated: a handful of sequences appear under more than one subgroup.
            var seen = Set<String>()
            let distinct = list.filter { seen.insert($0).inserted }
            contributions["internet.emoji.\(category)"] = .list(distinct.map(Definition.string))
        }

        return AdapterOutput(
            contributions: ["base": contributions],
            stats: [
                ("total", String(total)), ("categories", String(categories.count)),
                ("skipped", String(skipped)),
            ])
    }

    /// `; fully-qualified` in the status field, allowing any run of spaces after the `;`.
    static func isFullyQualified(_ line: String) -> Bool {
        guard let semicolon = line.firstIndex(of: ";") else { return false }
        let rest = line[line.index(after: semicolon)...]
        return rest.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("fully-qualified")
    }
}
