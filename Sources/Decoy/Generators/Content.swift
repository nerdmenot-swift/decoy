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

    public var animal: AnimalFaker {
        get { AnimalFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var food: FoodFaker {
        get { FoodFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var book: BookFaker {
        get { BookFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var music: MusicFaker {
        get { MusicFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var science: ScienceFaker {
        get { ScienceFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var system: SystemFaker {
        get { SystemFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var hacker: HackerFaker {
        get { HackerFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var database: DatabaseFaker {
        get { DatabaseFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var airline: AirlineFaker {
        get { AirlineFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var app: AppFaker {
        get { AppFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var team: TeamFaker {
        get { TeamFaker(faker: self) }
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

    public mutating func slug(words count: Int = 3) -> String {
        (0..<count).map { _ in word().asSlug }.joined(separator: "-")
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

// MARK: - Animal

public struct AnimalFaker {
    var faker: Faker

    private static let kinds = [
        "dog", "cat", "snake", "bear", "lion", "cetacean", "insect", "crocodilia",
        "cow", "bird", "fish", "rabbit", "horse", "rodent", "type",
    ]

    public mutating func type() -> String { faker.require("animal.type") }
    public mutating func dog() -> String { faker.require("animal.dog") }
    public mutating func cat() -> String { faker.require("animal.cat") }
    public mutating func bird() -> String { faker.require("animal.bird") }
    public mutating func fish() -> String { faker.require("animal.fish") }
    public mutating func horse() -> String { faker.require("animal.horse") }
    public mutating func insect() -> String { faker.require("animal.insect") }
    public mutating func lion() -> String { faker.require("animal.lion") }
    public mutating func bear() -> String { faker.require("animal.bear") }
    public mutating func snake() -> String { faker.require("animal.snake") }
    public mutating func rabbit() -> String { faker.require("animal.rabbit") }
    public mutating func cow() -> String { faker.require("animal.cow") }
    public mutating func rodent() -> String { faker.require("animal.rodent") }
    public mutating func cetacean() -> String { faker.require("animal.cetacean") }
    public mutating func crocodilia() -> String { faker.require("animal.crocodilia") }
    public mutating func petName() -> String { faker.require("animal.pet_name") }

    /// Any animal, from a randomly chosen family.
    public mutating func any() -> String {
        faker.require("animal.\(faker.pick(Self.kinds))")
    }
}

// MARK: - Food

public struct FoodFaker {
    var faker: Faker

    public mutating func dish() -> String { faker.require("food.dish") }
    public mutating func ingredient() -> String { faker.require("food.ingredient") }
    public mutating func fruit() -> String { faker.require("food.fruit") }
    public mutating func vegetable() -> String { faker.require("food.vegetable") }
    public mutating func meat() -> String { faker.require("food.meat") }
    public mutating func spice() -> String { faker.require("food.spice") }
    public mutating func adjective() -> String { faker.require("food.adjective") }
    public mutating func ethnicCategory() -> String { faker.require("food.ethnic_category") }
    public mutating func description() -> String {
        faker.expand(faker.require("food.description_pattern"))
    }

    /// A composed dish name, e.g. "smoked paprika-crusted lamb".
    public mutating func dishName() -> String {
        faker.expand(faker.require("food.dish_pattern"))
    }
}

// MARK: - Book

public struct BookFaker {
    var faker: Faker

    public mutating func title() -> String { faker.require("book.title") }
    public mutating func author() -> String { faker.require("book.author") }
    public mutating func genre() -> String { faker.require("book.genre") }
    public mutating func publisher() -> String { faker.require("book.publisher") }
    public mutating func series() -> String { faker.require("book.series") }
    public mutating func format() -> String { faker.require("book.format") }

    /// A 13-digit ISBN with a valid check digit.
    public mutating func isbn() -> String {
        let body = "978" + faker.numerify(String(repeating: "#", count: 9))
        return body + String(CommerceFaker.eanCheckDigit(body))
    }
}

// MARK: - Music

public struct MusicFaker {
    var faker: Faker

    public mutating func genre() -> String { faker.require("music.genre") }
    public mutating func artist() -> String { faker.require("music.artist") }
    public mutating func album() -> String { faker.require("music.album") }
    public mutating func songName() -> String { faker.require("music.song_name") }
}

// MARK: - Science

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

public struct HackerFaker {
    var faker: Faker

    public mutating func abbreviation() -> String { faker.require("hacker.abbreviation") }
    public mutating func adjective() -> String { faker.require("hacker.adjective") }
    public mutating func noun() -> String { faker.require("hacker.noun") }
    public mutating func verb() -> String { faker.require("hacker.verb") }
    public mutating func ingverb() -> String { faker.require("hacker.ingverb") }

    public mutating func phrase() -> String {
        faker.expand(faker.require("hacker.phrase"))
    }
}

public struct DatabaseFaker {
    var faker: Faker

    public mutating func column() -> String { faker.require("database.column") }
    public mutating func type() -> String { faker.require("database.type") }
    public mutating func collation() -> String { faker.require("database.collation") }
    public mutating func engine() -> String { faker.require("database.engine") }
}

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

public struct AppFaker {
    var faker: Faker

    public mutating func name() -> String { faker.require("app.name") }
    public mutating func version() -> String { faker.expand(faker.require("app.version")) }
    public mutating func author() -> String { faker.expand(faker.require("app.author")) }
}

public struct TeamFaker {
    var faker: Faker

    public mutating func creature() -> String { faker.require("team.creature") }

    public mutating func name() -> String {
        faker.expand(faker.require("team.name"))
    }
}
