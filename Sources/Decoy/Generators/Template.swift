extension Faker {

    /// Maximum nesting depth when expanding templates.
    ///
    /// Corpus patterns reference generators that themselves return patterns —
    /// `location.street_address` expands `street_pattern`, which expands
    /// `person.firstName`. A cycle in contributed data would otherwise hang
    /// generation, so expansion is bounded rather than trusted.
    static let maxTemplateDepth = 8

    /// Tokens expandable in one top-level call, before expansion gives up.
    static let maxTemplateTokens = 256

    /// Expands `{{token}}` placeholders, then applies `#`/`!`/`?` substitution.
    ///
    /// The corpus is full of these — 128 strings in `en` alone — because faker stores
    /// composition rules as data rather than code: `"{{person.firstName}}
    /// {{location.street_suffix}}"`. Resolving them here is what makes that data
    /// usable rather than something every generator has to reimplement.
    public mutating func expand(_ template: String) -> String {
        // Depth is carried on the Faker rather than only down the recursion, because a
        // token can resolve to a *generator*, and that generator starts a fresh
        // expansion of its own pattern. `de`'s street pattern is literally
        // `{{location.street_name}}`, so a token mapping that name back to
        // `streetName()` re-enters here forever — a stack overflow rather than a hang,
        // which the local-only depth counter could never see.
        expansionDepth += 1
        defer { expansionDepth -= 1 }
        guard expansionDepth <= Self.maxTemplateDepth else { return template }

        // The budget spans the whole top-level expansion, including everything the
        // generators it calls expand in turn, so cyclic data cannot multiply its way
        // around the depth cap.
        if expansionDepth == 1 { expansionBudget = Self.maxTemplateTokens }

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

            guard expansionBudget > 0 else {
                // Out of budget: emit the rest verbatim so a cycle is visible as leaked
                // braces rather than silently truncated output.
                out.append(contentsOf: characters[i...])
                return out
            }
            expansionBudget -= 1

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

        // `string.numeric(4)` and friends carry arguments. Tried first because the
        // parenthesised form never matches a corpus path or a bare generator name.
        if name.hasSuffix(")"), let value = resolveCall(name) { return value }

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
    ///
    /// Refuses to re-enter once expansion is already at the depth cap. Returning the
    /// unexpanded template at the cap is the right *output* — a cycle leaks visible braces
    /// rather than vanishing — but letting a generator start a fresh expansion at every
    /// level makes the retries exponential: a self-referential pattern took 56 seconds
    /// before this guard, where the cap alone had only stopped it from crashing.
    private mutating func resolveGenerator(_ token: String) -> String? {
        guard expansionDepth < Self.maxTemplateDepth else { return nil }
        switch token {
        case "person.firstName": return person.firstName()
        case "person.lastName": return person.lastName()
        case "person.middleName": return person.middleName()
        case "person.prefix": return person.prefix()
        case "person.suffix": return person.suffix()
        case "person.name": return person.fullName()
        case "person.jobTitle": return person.jobTitle()
        case "company.name": return company.name()
        // Only the camelCase spellings map to generators. The snake_case forms are real
        // corpus paths and must fall through to `draw`, or a pattern whose whole body is
        // `{{location.street_name}}` resolves to the generator that expands that very
        // pattern.
        case "location.streetName": return location.streetName()
        case "location.cityName": return location.city()
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

        // Aliases faker uses in its patterns that do not match a corpus path. Without
        // these the token resolved to nil and `expand` substituted an empty string, so
        // `location.streetAddress()` returned "791 " in English and "" in Japanese.
        case "location.street": return location.streetName()
        case "location.city": return location.city()
        case "location.zipCode": return location.postcode()
        // Usually a composite, so `draw` cannot reach it and the row's `name` is what a
        // pattern wants — but not everywhere. `en_HK` carries a plain list of three
        // districts, and reading `["name"]` off a string table yielded nothing, so Hong
        // Kong addresses shipped with the district missing.
        case "location.state":
            if let name = location.stateRow()["name"], !name.isEmpty { return name }
            return draw("location.state")
        case "location.country": return location.country()
        // The composite field is `code`, which snake-casing to `currency_code` misses.
        case "finance.currencyCode": return finance.currencyCode()
        // No corpus path at all: a transaction description wants a money figure.
        case "finance.amount": return commerce.price()
        case "company.catchPhrase": return company.catchPhrase()
        case "system.semver": return system.semver()
        // A group node rather than a table, so `draw` returns nil for the bare path.
        case "internet.emoji": return internet.emoji()
        default: return nil
        }
    }

    /// Resolves faker's parenthesised helper tokens.
    ///
    /// faker's patterns call a handful of helpers inline — `{{string.numeric(4)}}`,
    /// `{{number.int({"min":1,"max":9})}}`, `{{helpers.arrayElement(["5.1","5.2"])}}`.
    /// They are 90 of the tokens in the shipped corpus, and every one of them used to
    /// expand to nothing: user agents came out as `AppleWebKit/..` and transaction
    /// descriptions as `a deposit for  at`.
    ///
    /// Deliberately a small fixed grammar rather than a general expression evaluator.
    /// These three shapes are all faker emits, and anything more would be a scripting
    /// language embedded in a data file.
    private mutating func resolveCall(_ token: String) -> String? {
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return nil }
        let name = String(token[token.startIndex..<open])
        let arguments = String(token[token.index(after: open)..<token.index(before: token.endIndex)])
            .trimmedASCIIWhitespace

        switch name {
        case "string.numeric":
            let count = Int(arguments) ?? 1
            return numerify(String(repeating: "#", count: Swift.max(0, count)))

        case "number.int":
            // `{"min": 1, "max": 9}` — read by scanning for the two keys rather than by
            // parsing JSON, because the corpus reader imports nothing and a brace-object
            // parser here would be a second, worse JSON implementation.
            let low = Self.jsonNumber(named: "min", in: arguments) ?? 0
            let high = Self.jsonNumber(named: "max", in: arguments) ?? low
            return String(int(in: Swift.min(low, high)...Swift.max(low, high)))

        // `location.state({"abbreviated":true})`. The bare token is a generator case; the
        // parenthesised form carries the one option faker's patterns pass, and `en_US`'s
        // address pattern is the only thing that uses it.
        case "location.state":
            let field = arguments.contains("\"abbreviated\":true")
                || arguments.contains("\"abbreviated\": true") ? "abbr" : "name"
            let row = location.stateRow()
            if let value = row[field], !value.isEmpty { return value }
            return row["name"] ?? draw("location.state")

        // faker generates a handful of postcodes from a regular expression rather than
        // from a `#`/`?` mask, because Canadian postcodes exclude letters that look like
        // digits: `A[0-9][ABCEGHJ-NPRSTVW-Z] [0-9][ABCEGHJ-NPRSTVW-Z][0-9]` has no D, F,
        // I, O, Q or U in it. Twelve patterns, one per province, and all twelve expanded
        // to nothing — every `en_CA` postcode was an empty string.
        case "helpers.fromRegExp":
            return expandRegExp(arguments)

        case "helpers.arrayElement":
            let items = Self.quotedStrings(in: arguments)
            guard !items.isEmpty else { return nil }
            return pick(items)

        default:
            return nil
        }
    }

    /// Expands the subset of regular expression syntax faker's postcode data uses.
    ///
    /// Literal characters and `[...]` classes, where a class holds single characters,
    /// `a-z` ranges, or both. That is all twelve shipped patterns need, and stopping
    /// there is the point: anchors, alternation, groups and quantifiers would make this a
    /// regex engine living inside a data file, and the corpus is meant to hold data.
    ///
    /// An unbalanced class is emitted verbatim rather than dropped, matching how `expand`
    /// treats unbalanced braces — malformed data should stay visible.
    private mutating func expandRegExp(_ pattern: String) -> String {
        var out = String()
        var rest = Substring(pattern)

        while let next = rest.first {
            guard next == "[" else {
                out.append(next)
                rest = rest.dropFirst()
                continue
            }
            guard let close = rest.firstIndex(of: "]") else {
                out += rest
                return out
            }
            let body = Array(rest[rest.index(after: rest.startIndex)..<close])
            rest = rest[rest.index(after: close)...]

            var alphabet: [Character] = []
            var i = 0
            while i < body.count {
                // `A-Z` is three characters and means the range; a trailing `-` is itself.
                if i + 2 < body.count, body[i + 1] == "-",
                    let low = body[i].asciiValue, let high = body[i + 2].asciiValue, low <= high
                {
                    alphabet.append(contentsOf: (low...high).map { Character(UnicodeScalar($0)) })
                    i += 3
                } else {
                    alphabet.append(body[i])
                    i += 1
                }
            }
            guard !alphabet.isEmpty else { continue }
            out.append(pick(alphabet))
        }
        return out
    }

    /// Reads `"key": 123` out of a brace object without parsing it.
    static func jsonNumber(named key: String, in text: String) -> Int? {
        guard let range = text.range(of: "\"\(key)\"") else { return nil }
        var digits = ""
        var seenColon = false
        for character in text[range.upperBound...] {
            if character == ":" { seenColon = true; continue }
            guard seenColon else { continue }
            if character == "-" && digits.isEmpty { digits.append(character); continue }
            if character.isNumber { digits.append(character); continue }
            if !digits.isEmpty { break }
            if character == " " { continue }
            break
        }
        return Int(digits)
    }

    /// Every double-quoted item in a bracket list.
    static func quotedStrings(in text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inside = false
        for character in text {
            if character == "\"" {
                if inside { items.append(current); current = "" }
                inside.toggle()
                continue
            }
            if inside { current.append(character) }
        }
        return items
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
