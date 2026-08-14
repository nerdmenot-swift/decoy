import Foundation

/// Telephone number shapes per country, from libphonenumber's metadata.
///
/// Fills:
///   <each>   phone_number.format.national / .human / .international
public struct PhoneFormatsAdapter: Adapter {
    public static let id = "phone-formats"
    public static let sources = ["libphonenumber", "cldr-48"]
    public static let attributeTo: String? = "libphonenumber"

    public init() {}

    private static let nanpCountryCode = "1"

    struct Territory {
        let countryCode: String
        let national: [String]
        /// Kept apart from `national` because they differ by exactly the trunk prefix, and
        /// deriving one from the other by stripping a leading zero guesses at what the
        /// source states.
        let international: [String]
        let isMain: Bool
    }

    /// `[7-9]` and `8,10` expand to the set of lengths they name.
    static func parseLengths(_ declared: String?) -> Set<Int>? {
        guard let declared else { return nil }
        var lengths = Set<Int>()
        for part in declared.components(separatedBy: ",") {
            if part.hasPrefix("["), part.hasSuffix("]"), part.contains("-") {
                let inner = part.dropFirst().dropLast().components(separatedBy: "-")
                if inner.count == 2, let low = Int(inner[0]), let high = Int(inner[1]), low <= high
                {
                    for value in low...high { lengths.insert(value) }
                }
            } else if !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) {
                lengths.insert(value)
            }
        }
        return lengths.isEmpty ? nil : lengths
    }

    static func element(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"),
            let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.lowerBound..<end.upperBound])
    }

    static func attribute(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: " \(name)=\""),
            let end = xml.range(of: "\"", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    static func lengths(in territory: String, element name: String) -> Set<Int>? {
        guard let section = element(name, in: territory),
            let declared = attribute("national", in: section)
        else { return nil }
        return parseLengths(declared)
    }

    /// The shorter of the fixed-line and mobile length sets, which is the safer target.
    static func targetLengths(_ territory: String) -> Set<Int>? {
        let fixedLine = lengths(in: territory, element: "fixedLine")
        let mobile = lengths(in: territory, element: "mobile")
        guard let fixedLine else { return mobile }
        guard let mobile else { return fixedLine }
        return mobile.count <= fixedLine.count ? mobile : fixedLine
    }

    /// Each capturing group's `{min,max}` bounds, or nil if the pattern is not that shape.
    static func groupBounds(_ pattern: String) -> [(low: Int, high: Int)]? {
        var bounds: [(Int, Int)] = []
        let characters = Array(pattern)
        var index = 0

        while index < characters.count {
            guard characters[index] == "(" else {
                index += 1
                continue
            }
            var cursor = index + 1
            // The group body: either `\d` or a `[...]` class.
            if cursor + 1 < characters.count, characters[cursor] == "\\", characters[cursor + 1] == "d" {
                cursor += 2
            } else if cursor < characters.count, characters[cursor] == "[" {
                guard let close = characters[cursor...].firstIndex(of: "]") else {
                    index += 1
                    continue
                }
                cursor = close + 1
            } else {
                index += 1
                continue
            }

            var low = 1
            var high = 1
            if cursor < characters.count, characters[cursor] == "{" {
                guard let close = characters[cursor...].firstIndex(of: "}") else {
                    index += 1
                    continue
                }
                let parts = String(characters[(cursor + 1)..<close]).components(separatedBy: ",")
                guard let first = Int(parts[0]) else {
                    index += 1
                    continue
                }
                low = first
                high = parts.count > 1 ? (Int(parts[1]) ?? first) : first
                cursor = close + 1
            }

            guard cursor < characters.count, characters[cursor] == ")" else {
                index += 1
                continue
            }
            bounds.append((low, high))
            index = cursor + 1
        }
        return bounds.isEmpty ? nil : bounds
    }

    /// Picks one concrete length per group, given the total lengths the country allows.
    static func resolveLengths(_ bounds: [(low: Int, high: Int)], _ lengths: Set<Int>) -> [Int]? {
        let fixed = bounds.reduce(0) { $0 + ($1.low == $1.high ? $1.low : 0) }
        let variable = bounds.filter { $0.low != $0.high }
        if variable.isEmpty { return lengths.contains(fixed) ? bounds.map(\.low) : nil }
        if variable.count > 1 { return nil }

        let (low, high) = variable[0]
        let achievable = lengths.filter { $0 - fixed >= low && $0 - fixed <= high }
            .sorted(by: >)
        guard let longest = achievable.first else { return nil }
        let share = longest - fixed
        return bounds.map { $0.low == $0.high ? $0.low : share }
    }

    /// `$1 $2-$3` becomes a digit mask of the resolved group lengths.
    static func mask(from template: String, lengths: [Int], nanp: Bool) -> String? {
        var out = ""
        let characters = Array(template)
        var index = 0

        while index < characters.count {
            guard let marker = characters[index...].firstIndex(of: "$") else {
                out += String(characters[index...])
                break
            }
            out += String(characters[index..<marker])
            guard marker + 1 < characters.count,
                let group = characters[marker + 1].wholeNumberValue,
                group >= 1, group <= lengths.count
            else { return nil }
            let length = lengths[group - 1]
            // Only the first digit of the first two groups is constrained, which is the
            // area code and the exchange. The subscriber number may begin with anything.
            let leading = nanp && group <= 2 ? "!" : "#"
            out += leading + String(repeating: "#", count: length - 1)
            index = marker + 2
        }
        return out
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let core = try input.artifact("core", for: Self.id)
        let likelySubtags = try CLDR.likelySubtags(under: core)
        let xml = String(
            decoding: try Data(contentsOf: try input.artifact("metadata", for: Self.id)),
            as: UTF8.self)

        // Split rather than matched: a `<territory …>…</territory>` block has no nested
        // territories, so slicing between the opening and closing tags is exact.
        var territories: [String] = []
        var cursor = xml.startIndex
        while let open = xml.range(of: "<territory ", range: cursor..<xml.endIndex),
            let close = xml.range(of: "</territory>", range: open.upperBound..<xml.endIndex)
        {
            territories.append(String(xml[open.lowerBound..<close.upperBound]))
            cursor = close.upperBound
        }

        guard territories.count >= 200 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "libphonenumber metadata yielded \(territories.count) territories — the shape has changed"
            )
        }

        var byRegion: [String: Territory] = [:]
        var order: [String] = []

        for territory in territories {
            guard let id = Self.attribute("id", in: territory), id.count == 2,
                id.allSatisfy({ $0.isUppercase && $0.isLetter }),
                let countryCode = Self.attribute("countryCode", in: territory),
                countryCode.allSatisfy(\.isNumber)
            else { continue }

            let nanp = countryCode == Self.nanpCountryCode
            let nationalPrefix = Self.attribute("nationalPrefix", in: territory)
            let allowed = Self.targetLengths(territory)

            var national: [String] = []
            var international: [String] = []

            var formatCursor = territory.startIndex
            while let open = territory.range(of: "<numberFormat", range: formatCursor..<territory.endIndex),
                let close = territory.range(
                    of: "</numberFormat>", range: open.upperBound..<territory.endIndex)
            {
                let format = String(territory[open.lowerBound..<close.upperBound])
                formatCursor = close.upperBound

                guard let pattern = Self.attribute("pattern", in: format),
                    let templateBlock = Self.element("format", in: format),
                    let allowed
                else { continue }
                let template = String(
                    templateBlock.dropFirst("<format>".count).dropLast("</format>".count))

                guard let bounds = Self.groupBounds(pattern),
                    let lengths = Self.resolveLengths(bounds, allowed),
                    let mask = Self.mask(from: template, lengths: lengths, nanp: nanp)
                else { continue }

                // The trunk prefix, where the country uses one. `$NP$FG` means "national
                // prefix then the formatted number" — the leading 0 a French or German
                // number is written with domestically and dropped internationally.
                let rule = Self.attribute("nationalPrefixFormattingRule", in: format)
                let domestic: String
                if let rule, let nationalPrefix {
                    domestic = rule.replacingOccurrences(of: "$NP", with: nationalPrefix)
                        .replacingOccurrences(of: "$FG", with: mask)
                } else {
                    domestic = mask
                }

                if !national.contains(domestic) { national.append(domestic) }
                if !international.contains(mask) { international.append(mask) }
            }

            guard !national.isEmpty else { continue }
            if byRegion[id] == nil { order.append(id) }
            byRegion[id] = Territory(
                countryCode: countryCode, national: national, international: international,
                isMain: territory.contains(" mainCountryForCode=\"true\""))
        }

        // A country sharing a calling code with another carries no formats of its own —
        // Canada has none because the United States is the main country for code 1, and
        // the two write numbers identically. Inheriting from the main country is what
        // libphonenumber itself does at format time.
        var mainByCode: [String: Territory] = [:]
        for id in order {
            guard let entry = byRegion[id], entry.isMain else { continue }
            mainByCode[entry.countryCode] = entry
        }
        for territory in territories {
            guard let id = Self.attribute("id", in: territory), byRegion[id] == nil,
                let countryCode = Self.attribute("countryCode", in: territory),
                let inherited = mainByCode[countryCode]
            else { continue }
            byRegion[id] = inherited
        }

        var contributions: [String: [String: Definition]] = [:]
        var withoutFormats: [String] = []

        for code in input.locales where code != "base" {
            let region = CLDR.region(for: code, likelySubtags: likelySubtags)
            guard let region, let entry = byRegion[region] else {
                if let region { withoutFormats.append("\(code)(\(region))") }
                continue
            }

            contributions[code] = [
                "phone_number.format.national": .list(entry.national.map(Definition.string)),
                // `human` is what `phone.number()` draws by default, and a national-format
                // number is what a person writes down.
                "phone_number.format.human": .list(entry.national.map(Definition.string)),
                "phone_number.format.international": .list(
                    entry.international.map { .string("+\(entry.countryCode) \($0)") }),
            ]
        }

        return AdapterOutput(
            contributions: contributions,
            stats: [
                ("territories", String(byRegion.count)),
                ("locales", String(contributions.count)),
                ("withoutFormats", withoutFormats.joined(separator: ",")),
            ])
    }
}
