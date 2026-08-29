import Foundation

/// Postcode shapes and address layouts, from Google's libaddressinput.
///
/// Fills:
///   <each>   location.postcode         a mask, e.g. `###-####`
///   <each>   location.postal_address   a template of corpus tokens
public struct PostalAdapter: Adapter {
    public static let id = "postal"
    public static let sources = ["libaddressinput", "cldr-48"]
    public static let attributeTo: String? = "libaddressinput"

    public init() {}

    /// Converts a postcode regex to a generation mask, or nil where it cannot be one.
    ///
    /// `#` is a digit and `?` a letter, matching the corpus's mask vocabulary. A pattern
    /// narrower than "any digit" or "any letter" — `[ABD-HJLNP-UW-Z]`, which is a real
    /// constraint in several countries — has no mask, and inventing one would generate
    /// invalid postcodes that look right.
    public static func mask(for pattern: String) -> String? {
        var source = pattern

        // A pattern that is *entirely* one optional group says the postcode is optional in
        // that country, not that it has none: Nigeria writes `(\d{6})?` and Honduras
        // `(?:\d{5})?`. Read as a trailing group — which it also is — the rule below strips
        // the whole thing, leaves an empty mask, and the country loses a postcode it has.
        // Four countries were dropped that way. The shape wanted is what is inside.
        if let inner = Self.wholePatternOptionalGroup(in: source) { source = inner }

        // An optional trailing group is a real alternative rather than an error — the US
        // +4 is written about as often as it is not — but a mask is one shape, so the
        // shorter form is taken and the extension dropped.
        if let range = Self.trailingOptionalGroup(in: source) { source.removeSubrange(range) }

        // A *leading* optional group is the same decision at the other end. Armenia's
        // `(37)?\d{4}` carries the Soviet-era six-digit prefix ahead of the modern
        // four-digit code, and Oman's `(PC )?\d{3}` a label rather than part of the code.
        // Both are what the country writes when it writes the long form, so the base form
        // is the one to generate.
        if let range = Self.leadingOptionalGroup(in: source) { source.removeSubrange(range) }

        if source.contains(where: { $0 == "|" || $0 == "(" || $0 == ")" }) { return nil }

        var mask = ""
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            var unit: String

            if index + 1 < characters.count, characters[index] == "\\", characters[index + 1] == "d"
            {
                unit = "#"
                index += 2
            } else if characters[index] == "[" {
                guard let close = characters[index...].firstIndex(of: "]") else { return nil }
                let set = String(characters[(index + 1)..<close])
                if set == "0-9" {
                    unit = "#"
                } else if set == "A-Z" {
                    unit = "?"
                } else if !set.isEmpty
                    && set.allSatisfy({ $0 == " " || $0 == "-" || $0 == "\\" })
                {
                    let literal = set.replacingOccurrences(of: "\\", with: "")
                    guard let first = literal.first else { return nil }
                    unit = String(first)
                } else {
                    return nil
                }
                index = close + 1
            } else if characters[index].isASCII
                && (characters[index].isLetter || characters[index].isNumber
                    || characters[index] == " " || characters[index] == "-")
            {
                unit = String(characters[index])
                index += 1
            } else if characters[index] == "\\", index + 1 < characters.count {
                unit = String(characters[index + 1])
                index += 2
            } else {
                return nil
            }

            var repeatCount = 1
            if index < characters.count, characters[index] == "{" {
                guard let close = characters[index...].firstIndex(of: "}") else { return nil }
                let bounds = String(characters[(index + 1)..<close]).components(separatedBy: ",")
                let chosen = bounds.last.flatMap { $0.isEmpty ? bounds.first : $0 } ?? ""
                guard let value = Int(chosen), (1...12).contains(value) else { return nil }
                repeatCount = value
                index = close + 1
            } else if index < characters.count, characters[index] == "?" {
                index += 1
                // An optional *separator* is kept, because it is what people write: a
                // Japanese postcode is `154-0023` and a Brazilian CEP `01310-100`, and both
                // regexes mark the hyphen optional because both are also valid without it.
                // Dropping it gave `#######`, which is correct and unrecognisable.
                if unit != " " && unit != "-" { continue }
            }

            mask += String(repeating: unit, count: repeatCount)
        }
        return mask.isEmpty ? nil : mask
    }

    /// The range of a trailing `(...)?` or `(?:...)?` group, if the pattern ends in one.
    static func trailingOptionalGroup(in pattern: String) -> Range<String.Index>? {
        guard pattern.hasSuffix(")?") else { return nil }
        let closing = pattern.index(pattern.endIndex, offsetBy: -2)
        // Innermost open paren before it, with no nesting inside — matching `[^()]*`.
        var index = closing
        while index > pattern.startIndex {
            index = pattern.index(before: index)
            if pattern[index] == ")" { return nil }
            if pattern[index] == "(" { return index..<pattern.endIndex }
        }
        return nil
    }

    /// The contents of a `(...)?` or `(?:...)?` that spans the whole pattern.
    ///
    /// Nil unless the group really is the entire pattern, so `(37)?\d{4}` is not caught
    /// here — that one has a base form outside the group and belongs to
    /// ``leadingOptionalGroup(in:)``.
    static func wholePatternOptionalGroup(in pattern: String) -> String? {
        guard pattern.hasPrefix("("), pattern.hasSuffix(")?") else { return nil }
        var inner = String(pattern.dropFirst().dropLast(2))
        if inner.hasPrefix("?:") { inner = String(inner.dropFirst(2)) }
        guard !inner.isEmpty,
            !inner.contains(where: { $0 == "(" || $0 == ")" || $0 == "|" })
        else { return nil }
        return inner
    }

    /// The range of a leading `(...)?` or `(?:...)?`, if the pattern opens with one.
    static func leadingOptionalGroup(in pattern: String) -> Range<String.Index>? {
        guard pattern.hasPrefix("("), let close = pattern.firstIndex(of: ")") else { return nil }
        let mark = pattern.index(after: close)
        guard mark < pattern.endIndex, pattern[mark] == "?" else { return nil }
        // No nesting inside, matching the `[^()]*` the trailing form requires.
        guard !pattern[pattern.index(after: pattern.startIndex)..<close].contains("(") else {
            return nil
        }
        return pattern.startIndex..<pattern.index(after: mark)
    }

    /// libaddressinput's placeholders, mapped to the corpus's template tokens.
    private static let fields: [Character: String] = [
        "N": "{{person.name}}",
        "A": "{{location.streetAddress}}",
        "C": "{{location.city}}",
        "S": "{{location.state}}",
        "Z": "{{location.zipCode}}",
    ]

    /// Converts an address format to a template.
    ///
    /// `%O` — organisation — is dropped rather than mapped to a company name: an address is
    /// for a person here, and half of them would otherwise arrive care of a business. The
    /// sublocality fields go for the same reason, since nothing supplies a district.
    public static func template(for format: String) -> String {
        var out = ""
        let characters = Array(format)
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else {
                out.append(characters[index])
                index += 1
                continue
            }
            index += 1
            guard index < characters.count else { break }
            let code = characters[index]
            if code == "n" {
                out.append("\n")
            } else if let field = Self.fields[code] {
                out += field
            }
            index += 1
        }

        // Dropping fields leaves blank lines and doubled spaces behind.
        return
            Lines.split(out)
            .map { line -> String in
                var collapsed = ""
                var lastWasSpace = false
                for character in line {
                    if character == " " {
                        if !lastWasSpace { collapsed.append(character) }
                        lastWasSpace = true
                    } else {
                        collapsed.append(character)
                        lastWasSpace = false
                    }
                }
                return collapsed.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let likelySubtags = try CLDR.likelySubtags(under: core)
        let text = String(
            decoding: try Data(contentsOf: try input.artifact("countryinfo", for: Self.id)),
            as: UTF8.self)

        var byRegion: [String: [String: Any]] = [:]
        for line in Lines.split(text) {
            guard line.hasPrefix("data/"), let equals = line.firstIndex(of: "=") else { continue }
            let region = String(line[line.index(line.startIndex, offsetBy: 5)..<equals])
            guard region.count == 2, region.allSatisfy({ $0.isUppercase && $0.isLetter })
            else { continue }
            let json = String(line[line.index(after: equals)...])
            guard json.hasPrefix("{"), json.hasSuffix("}"),
                let entry = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                    as? [String: Any]
            else {
                // A malformed row is skipped rather than fatal: the file carries
                // subdivision rows too, and only the country ones matter here.
                continue
            }
            byRegion[region] = entry
        }

        guard byRegion.count >= 200 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "libaddressinput yielded \(byRegion.count) countries — the shape has changed")
        }

        var contributions: [String: [String: Definition]] = [:]
        var masks = 0
        var templates = 0
        var unmasked: [String] = []

        for code in input.locales where code != "base" {
            guard let region = CLDR.region(for: code, likelySubtags: likelySubtags),
                let entry = byRegion[region]
            else { continue }

            var contribution: [String: Definition] = [:]
            if let zip = entry["zip"] as? String {
                if let mask = Self.mask(for: zip) {
                    contribution["location.postcode"] = .list([.string(mask)])
                    masks += 1
                } else {
                    unmasked.append("\(code)(\(region))")
                }
            }
            if let format = entry["fmt"] as? String {
                let template = Self.template(for: format)
                if template.contains("{{") {
                    contribution["location.postal_address"] = .list([.string(template)])
                    templates += 1
                }
            }
            if !contribution.isEmpty { contributions[code] = contribution }
        }

        // Reported as a discard, not just a stats line. A country whose regex cannot become
        // a mask is a locale silently losing a field, which is the shape of every serious
        // bug this pipeline has had — and the four that `wholePatternOptionalGroup` now
        // rescues sat in this list, counted, for as long as the list was only prose.
        let discarded = unmasked.map {
            DiscardRecord(scope: $0, filter: "unmaskable", kept: 0, seen: 1)
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("countries", String(byRegion.count)), ("postcodes", String(masks)),
                ("addresses", String(templates)),
                ("unmasked", unmasked.joined(separator: ",")),
            ],
            discarded: discarded)
    }
}
