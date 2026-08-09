extension Faker {
    public var word: WordFaker {
        get { WordFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var lorem: LoremFaker {
        get { LoremFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var color: ColorFaker {
        get { ColorFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var vehicle: VehicleFaker {
        get { VehicleFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var system: SystemFaker {
        get { SystemFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var science: ScienceFaker {
        get { ScienceFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var airline: AirlineFaker {
        get { AirlineFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var database: DatabaseFaker {
        get { DatabaseFaker(faker: self) }
        set { self = newValue.faker }
    }
}

// MARK: - Word

public struct WordFaker {
    var faker: Faker

    public mutating func adjective() -> String { faker.require("word.adjective") }
    public mutating func adverb() -> String { faker.require("word.adverb") }
    public mutating func conjunction() -> String { faker.require("word.conjunction") }
    public mutating func interjection() -> String { faker.require("word.interjection") }
    public mutating func noun() -> String { faker.require("word.noun") }
    /// Closed-class function words, which Decoy authors rather than cites.
    ///
    /// These three were briefly deleted along with faker's lists, on the reasoning that
    /// nobody needs a generated preposition. That was the wrong trade: a feature should
    /// not disappear because no institution publishes a list of English prepositions.
    /// They are a closed class, so what is written in `authored.mjs` is very nearly the
    /// complete set rather than a sample of one.
    public mutating func preposition() -> String { faker.require("word.preposition") }
    public mutating func verb() -> String { faker.require("word.verb") }

    public mutating func words(_ count: Int = 3) -> String {
        (0..<count).map { _ in noun() }.joined(separator: " ")
    }
}

// MARK: - Lorem

public struct LoremFaker {
    var faker: Faker

    public mutating func word() -> String { faker.require("lorem.word") }

    public mutating func words(_ count: Int = 3) -> String {
        (0..<count).map { _ in word() }.joined(separator: " ")
    }

    public mutating func sentence(words count: Int? = nil) -> String {
        let n = count ?? faker.int(in: 3...10)
        var text = words(n)
        // Capitalise without Foundation's locale-sensitive `capitalized`, which would
        // make output depend on the host's locale settings.
        if let first = text.first {
            text.replaceSubrange(text.startIndex...text.startIndex, with: first.uppercased())
        }
        return text + "."
    }

    public mutating func sentences(_ count: Int = 3) -> String {
        (0..<count).map { _ in sentence() }.joined(separator: " ")
    }

    public mutating func paragraph(sentences count: Int? = nil) -> String {
        sentences(count ?? faker.int(in: 3...7))
    }

    public mutating func paragraphs(_ count: Int = 3, separator: String = "\n\n") -> String {
        (0..<count).map { _ in paragraph() }.joined(separator: separator)
    }

    /// A URL-safe slug of `count` words.
    ///
    /// Words that reduce to nothing in ASCII are replaced with a numbered placeholder
    /// rather than a bare `user`: every Japanese filename was `user-user.<ext>`, which
    /// is one string repeated for every row. A real romanization needs per-script data
    /// Decoy does not carry, so the placeholder stays visible — but it is at least
    /// distinct per draw, which is what a filename or a URL is for.
    public mutating func slug(words count: Int = 3) -> String {
        (0..<count)
            .map { _ in
                let slug = word().asciiSlug
                return slug.isEmpty ? "word\(faker.int(in: 100...999))" : slug
            }
            .joined(separator: "-")
    }

    public mutating func text(maxLength: Int = 200) -> String {
        var out = sentence()
        while out.count < maxLength {
            let next = sentence()
            if out.count + next.count + 1 > maxLength { break }
            out += " " + next
        }
        return out
    }
}

// MARK: - Colour

public struct ColorFaker {
    var faker: Faker

    public mutating func human() -> String { faker.require("color.human") }
    public mutating func space() -> String { faker.require("color.space") }

    public mutating func hex() -> String {
        var out = "#"
        for _ in 0..<6 { out.append(faker.pick(Array("0123456789abcdef"))) }
        return out
    }

    public mutating func rgb() -> (red: Int, green: Int, blue: Int) {
        (faker.int(in: 0...255), faker.int(in: 0...255), faker.int(in: 0...255))
    }

    public mutating func cssRGB() -> String {
        let (r, g, b) = rgb()
        return "rgb(\(r), \(g), \(b))"
    }
}

// MARK: - Vehicle

public struct VehicleFaker {
    var faker: Faker

    public mutating func manufacturer() -> String { faker.require("vehicle.manufacturer") }
    public mutating func model() -> String { faker.require("vehicle.model") }
    public mutating func type() -> String { faker.require("vehicle.type") }
    public mutating func fuel() -> String { faker.require("vehicle.fuel") }
    public mutating func bicycleType() -> String { faker.require("vehicle.bicycle_type") }

    public mutating func name() -> String { "\(manufacturer()) \(model())" }

    /// A 17-character VIN.
    ///
    /// `I`, `O` and `Q` are excluded by ISO 3779 precisely because they look like
    /// digits, so a VIN containing them would be rejected by anything that checks.
    public mutating func vin() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        return String((0..<17).map { _ in faker.pick(alphabet) })
    }

    public mutating func registrationPlate() -> String {
        faker.bothify("??-###-??")
    }
}

// MARK: - Airline

/// Air travel.
///
/// Restored after the v1 scope cut, unlike the other domain vocabularies dropped with it.
/// Airports carry IATA and ICAO codes, which are real published identifiers rather than a
/// curated word list, so `airline.airport` is sourced from the registry. Airline and
/// aircraft names remain faker-derived: those are trademarks, and no permissive registry
/// publishes them.
public struct AirlineFaker {
    var faker: Faker

    /// An airline as a coherent `(name, iataCode)` row.
    public mutating func airline() -> [String: String] {
        faker.drawRow("airline.airline") ?? [:]
    }

    /// An airport as a coherent `(name, iataCode)` row.
    public mutating func airport() -> [String: String] {
        faker.drawRow("airline.airport") ?? [:]
    }

    /// An aircraft as a coherent `(name, iataTypeCode)` row.
    public mutating func airplane() -> [String: String] {
        faker.drawRow("airline.airplane") ?? [:]
    }

    public mutating func aircraftType() -> String { airplane()["name"] ?? "" }

    public mutating func flightNumber(digits: Int = 4) -> String {
        faker.numerify(String(repeating: "#", count: digits))
    }

    public mutating func seat() -> String {
        "\(faker.int(in: 1...60))\(faker.pick(Array("ABCDEF")))"
    }

    public mutating func recordLocator() -> String {
        faker.bothify("??????").uppercased()
    }
}

// MARK: - Science

/// Chemical elements and units.
///
/// Kept in scope where the other small vocabularies were not: elements are IUPAC-published
/// and SI units are standardised, so this is a fact table with a real registry behind it
/// rather than a curated word list. It still needs an adapter to stop being faker-derived.
public struct ScienceFaker {
    var faker: Faker

    /// A chemical element as a coherent `(symbol, name, atomicNumber)` row.
    public mutating func chemicalElement() -> [String: String] {
        faker.drawRow("science.chemical_element") ?? [:]
    }

    /// A unit as a coherent `(name, symbol)` row.
    public mutating func unit() -> [String: String] {
        faker.drawRow("science.unit") ?? [:]
    }
}

// MARK: - System

public struct SystemFaker {
    var faker: Faker

    /// A MIME type, drawn from the keys of the corpus's MIME map.
    ///
    /// faker stores this as `{"application/json": {extensions: [...]}}`, so the values
    /// you want are the object's keys — reachable through the compiler's `__keys`
    /// table.
    public mutating func mimeType() -> String {
        faker.require("system.mime_type.__keys")
    }

    /// A programming language as a coherent `(name, extension, color)` row.
    ///
    /// Drawn as one row so the parts agree — independently you get Haskell with a `.rs`
    /// extension in Go's blue. `color` is Linguist's assigned hex and is empty for the
    /// languages it has not assigned one.
    public mutating func programmingLanguage() -> [String: String] {
        faker.drawRow("system.programming_language") ?? [:]
    }

    /// Just the name, for the common case.
    public mutating func programmingLanguageName() -> String {
        programmingLanguage()["name"] ?? ""
    }

    /// An identifier in the shape source code actually uses.
    ///
    /// Built from the locale's own words, so a German locale yields a German-looking
    /// identifier — which is what code written by German speakers often contains, and
    /// what makes a fixture exercise your Unicode handling rather than dodge it.
    public mutating func variableName(_ style: NamingStyle = .camelCase) -> String {
        let words = [faker.require("word.adjective"), faker.require("word.noun")]
            .map { $0.filter(\.isLetter).lowercased() }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "value" }

        func capitalized(_ value: String) -> String {
            guard let first = value.first else { return value }
            return first.uppercased() + value.dropFirst()
        }

        switch style {
        case .camelCase:
            return words[0] + words.dropFirst().map(capitalized).joined()
        case .pascalCase:
            return words.map(capitalized).joined()
        case .snakeCase:
            return words.joined(separator: "_")
        case .kebabCase:
            return words.joined(separator: "-")
        case .screamingSnakeCase:
            return words.joined(separator: "_").uppercased()
        }
    }

    public enum NamingStyle: Sendable, CaseIterable {
        case camelCase
        case pascalCase
        case snakeCase
        case kebabCase
        case screamingSnakeCase
    }

    /// A file extension consistent with a randomly chosen MIME type.
    ///
    /// Drawn *through* the MIME type rather than from a flat list, so `.json` never
    /// comes back paired with `image/png` if a caller asks for both.
    public mutating func fileExtension() -> String {
        let type = mimeType()
        return faker.draw("system.mime_type.\(type).extensions") ?? "bin"
    }

    public mutating func directoryPath() -> String { faker.require("system.directory_path") }

    public mutating func fileName() -> String {
        "\(faker.lorem.slug(words: 2)).\(fileExtension())"
    }

    public mutating func filePath() -> String {
        "\(directoryPath())/\(fileName())"
    }

    public mutating func semver() -> String {
        "\(faker.int(in: 0...9)).\(faker.int(in: 0...20)).\(faker.int(in: 0...30))"
    }
}

// MARK: - Hacker, database, airline, app, team

public struct DatabaseFaker {
    var faker: Faker

    public mutating func column() -> String { faker.require("database.column") }
    public mutating func type() -> String { faker.require("database.type") }
    public mutating func collation() -> String { faker.require("database.collation") }
    public mutating func engine() -> String { faker.require("database.engine") }
}

