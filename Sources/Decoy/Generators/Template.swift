extension Faker {

    /// Maximum nesting depth when expanding templates.
    ///
    /// Corpus patterns reference generators that themselves return patterns —
    /// `location.street_address` expands `street_pattern`, which expands
    /// `person.firstName`. A cycle in contributed data would otherwise hang
    /// generation, so expansion is bounded rather than trusted.
    private static let maxTemplateDepth = 8

    /// Expands `{{token}}` placeholders, then applies `#`/`!`/`?` substitution.
    ///
    /// The corpus is full of these — 128 strings in `en` alone — because faker stores
    /// composition rules as data rather than code: `"{{person.firstName}}
    /// {{location.street_suffix}}"`. Resolving them here is what makes that data
    /// usable rather than something every generator has to reimplement.
    public mutating func expand(_ template: String) -> String {
        let expanded = expand(template, depth: 0)
        return numerify(expanded)
    }

    /// Scanned by hand rather than with `range(of:)`, which lives in Foundation — the
    /// one import this module does not take.
    private mutating func expand(_ template: String, depth: Int) -> String {
        guard depth < Self.maxTemplateDepth, Self.containsPlaceholder(template) else {
            return template
        }

        let characters = Array(template)
        var out = String()
        out.reserveCapacity(template.count)
        var i = 0

        while i < characters.count {
            guard characters[i] == "{", i + 1 < characters.count, characters[i + 1] == "{" else {
                out.append(characters[i])
                i += 1
                continue
            }

            var scan = i + 2
            var close = -1
            while scan + 1 < characters.count {
                if characters[scan] == "}" && characters[scan + 1] == "}" {
                    close = scan
                    break
                }
                scan += 1
            }
            guard close >= 0 else {
                // Unbalanced braces: emit the remainder verbatim rather than dropping
                // it, so malformed corpus data stays visible instead of being eaten.
                out.append(contentsOf: characters[i...])
                return out
            }

            let token = String(characters[(i + 2)..<close]).trimmedASCIIWhitespace
            out += expand(resolve(token) ?? "", depth: depth + 1)
            i = close + 2
        }
        return out
    }

    /// Resolves a single template token to a value.
    ///
    /// Tokens come in two flavours, because faker's data mixes them: camelCase names
    /// of *generators* (`person.firstName`) and snake_case *corpus paths*
    /// (`location.street_suffix`). Generators are tried first so a token that means
    /// "compose a name" does not resolve to a raw table, then the token is tried as a
    /// path, then as a path with camelCase converted.
    public mutating func resolve(_ token: some StringProtocol) -> String? {
        let name = String(token)

        if let value = resolveGenerator(name) { return value }
        if let value = draw(name) { return value }

        let snake = Self.snakeCased(name)
        if snake != name, let value = draw(snake) { return value }

        // `science.chemical_element.name` reaches into a composite row: the last
        // component is a field, not part of the path.
        if let dot = snake.lastIndex(of: "."), let row = drawRow(String(snake[..<dot])) {
            return row[String(snake[snake.index(after: dot)...])]
        }
        return nil
    }

    /// Tokens backed by a generator rather than by a single table.
    private mutating func resolveGenerator(_ token: String) -> String? {
        switch token {
        case "person.firstName": return person.firstName()
        case "person.lastName": return person.lastName()
        case "person.middleName": return person.middleName()
        case "person.prefix": return person.prefix()
        case "person.suffix": return person.suffix()
        case "person.name": return person.fullName()
        case "person.jobTitle": return person.jobTitle()
        case "company.name": return company.name()
        case "location.street_name", "location.streetName": return location.streetName()
        case "location.city_name", "location.cityName": return location.city()
        case "location.buildingNumber": return location.buildingNumber()
        case "location.secondaryAddress": return location.secondaryAddress()
        case "location.streetAddress": return location.streetAddress()
        case "commerce.product": return commerce.product()
        case "commerce.productMaterial": return commerce.productMaterial()
        case "commerce.productAdjective": return commerce.productAdjective()
        case "commerce.department": return commerce.department()
        case "word.adjective": return word.adjective()
        case "word.noun": return word.noun()
        case "word.verb": return word.verb()
        case "word.adverb": return word.adverb()
        case "color.human": return color.human()
        case "finance.currencyName": return finance.currencyName()
        default: return nil
        }
    }

    /// Whether the string contains `{{`.
    ///
    /// Hand-rolled because `String.contains(_: StringProtocol)` is a Foundation-era
    /// convenience that embedded Swift does not provide; only the `Character` overload
    /// exists there.
    static func containsPlaceholder(_ text: String) -> Bool {
        var previousWasBrace = false
        for character in text {
            if character == "{" {
                if previousWasBrace { return true }
                previousWasBrace = true
            } else {
                previousWasBrace = false
            }
        }
        return false
    }

    /// Converts `firstName` to `first_name`, leaving already-snake_case input alone.
    static func snakeCased(_ input: String) -> String {
        var out = String()
        out.reserveCapacity(input.count + 4)
        for character in input {
            if character.isUppercase {
                out.append("_")
                out.append(Character(character.lowercased()))
            } else {
                out.append(character)
            }
        }
        return out
    }
}

extension String {
    /// Trims ASCII whitespace without reaching for Foundation.
    fileprivate var trimmedASCIIWhitespace: String {
        var result = Substring(self)
        while let first = result.first, first == " " || first == "\t" || first == "\n" {
            result = result.dropFirst()
        }
        while let last = result.last, last == " " || last == "\t" || last == "\n" {
            result = result.dropLast()
        }
        return String(result)
    }
}
