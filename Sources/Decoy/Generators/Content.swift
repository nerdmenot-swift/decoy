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
    /// They are a closed class, so what the authored data records is very nearly the
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

    // MARK: - Errors

    /// An error message from any layer.
    ///
    /// These exist because every application has an error column and nothing generates
    /// one, so they get seeded with lorem — which tells you nothing about how the column
    /// behaves when something 120 characters long, carrying punctuation and a quoted
    /// identifier, actually lands in it. That shape is the whole value here.
    public mutating func errorMessage() -> String {
        switch faker.int(in: 0...3) {
        case 0: return databaseError()
        case 1: return httpError()
        case 2: return runtimeError()
        default: return validationError()
        }
    }

    /// A database error, phrased the way Postgres and MySQL phrase them.
    public mutating func databaseError() -> String {
        faker.bothify(faker.expand(faker.require("system.error_database")))
    }

    /// An HTTP-layer failure, from the client's side of the wire.
    public mutating func httpError() -> String {
        faker.bothify(faker.expand(faker.require("system.error_http")))
    }

    /// A runtime failure, in the register a stack trace summary uses.
    public mutating func runtimeError() -> String {
        faker.bothify(faker.expand(faker.require("system.error_runtime")))
    }

    /// A validation failure, in the register a form or an API returns to a caller.
    public mutating func validationError() -> String {
        faker.bothify(faker.expand(faker.require("system.error_validation")))
    }

    /// The subsystem an error names — `billing`, `search-indexer`. Generic by design:
    /// the shape of a service name anywhere, not a real product's module list.
    public mutating func component() -> String { faker.require("system.error_component") }
}

// MARK: - Hacker, database, airline, app, team

public struct DatabaseFaker {
    var faker: Faker

    public mutating func column() -> String { faker.require("database.column") }
    public mutating func type() -> String { faker.require("database.type") }
    public mutating func collation() -> String { faker.require("database.collation") }
    public mutating func engine() -> String { faker.require("database.engine") }
}


// MARK: - Whimsy

extension Faker {
    public var whimsy: WhimsyFaker {
        get { WhimsyFaker(faker: self) }
        set { self = newValue.faker }
    }
}

/// Invented things, for the columns a schema has and no registry describes.
///
/// The one namespace in Decoy with nothing to verify, and it is worth being precise about
/// why that is allowed rather than treating it as a relaxation.
///
/// Everywhere else, a value answers to something: a German street type is right or wrong, a
/// Polish name frequency is right or wrong, `AG` either is Antigua's ISO code or it is not.
/// The whole apparatus of pinned sources and integrity hashes exists so those can be
/// checked, and the price of it is that data nobody publishes cannot ship.
///
/// Here there is no fact of the matter. `The Amber Cartographers` is not a correct or an
/// incorrect band name; `Operation Silent Meridian` is not a mis-transcription of anything.
/// No speaker can find an error, no registry can contradict it, no upstream can change
/// underneath it. The verification machinery has nothing to bite on, and its absence
/// therefore costs nothing.
///
/// That licence is narrower than "amusing content is fine". A list of real animals is a
/// factual claim and wants a source; a list of real bands is somebody's trademark and wants
/// a lawyer. What is free is *composition* — ordinary English words assembled by a pattern
/// into something that did not exist before.
public struct WhimsyFaker {
    var faker: Faker

    /// A project codename, in the military register or the shy one.
    public mutating func codename() -> String {
        faker.expand(faker.require("whimsy.codename_pattern"))
    }

    /// A band name.
    public mutating func bandName() -> String {
        faker.expand(faker.require("whimsy.band_pattern"))
    }

    /// A meeting room, named the way offices actually name them.
    public mutating func roomName() -> String {
        faker.expand(faker.require("whimsy.room_pattern"))
    }

    /// A conference talk title.
    public mutating func talkTitle() -> String {
        faker.expand(faker.require("whimsy.talk_pattern"))
    }

    /// A Wi-Fi network name.
    ///
    /// The one whole-string list here rather than a composition, because the humour is in
    /// the specific pun and a generator would reproduce the shape without the joke.
    public mutating func ssid() -> String { faker.require("whimsy.ssid") }

    /// Why the incident happened, for the ticket and postmortem columns every internal
    /// tool has. Plausible rather than absurd: a fixture that reads as obviously fake
    /// stops being useful for judging how the column looks when it is full.
    public mutating func excuse() -> String { faker.require("whimsy.excuse") }

    /// A pub name, in the oldest naming grammar here.
    ///
    /// The form predates literacy: a sign had to be describable by somebody who could not
    /// read it, which is why these compose concrete things. A crimson heron can be painted
    /// on a board; `The Abstract Synergy` cannot.
    public mutating func pubName() -> String {
        faker.expand(faker.require("whimsy.pub_pattern"))
    }

    /// A board game title.
    public mutating func boardGame() -> String {
        faker.expand(faker.require("whimsy.board_game_pattern"))
    }

    /// How a board game plays — worker placement, deck-building, trick-taking.
    ///
    /// A factual term of art rather than an invention, the way `IPA` is a style of beer.
    /// The titles compose because a list of real board games is a list of trademarks; the
    /// mechanics are a category anybody can check and nobody owns.
    public mutating func gameMechanic() -> String { faker.require("whimsy.game_mechanic") }

    /// A racehorse name.
    ///
    /// Named under a real constraint worth honouring: eighteen characters, and no
    /// duplicate of a horse still running. Short evocative pairs are what that rule
    /// produces, and it is why the naming reads the way it does.
    public mutating func horseName() -> String {
        faker.expand(faker.require("whimsy.horse_pattern"))
    }

    /// A paint or nail-varnish colour, a genre built on the name saying nothing about the
    /// colour. `Restless Tundra` could be any shade, which is the joke.
    public mutating func paintColour() -> String {
        faker.expand(faker.require("whimsy.paint_pattern"))
    }

    /// A ship name, naval or merchant.
    public mutating func shipName() -> String {
        faker.expand(faker.require("whimsy.ship_pattern"))
    }

    public mutating func adjective() -> String { faker.require("whimsy.adjective") }
    public mutating func creature() -> String { faker.require("whimsy.creature") }
    public mutating func object() -> String { faker.require("whimsy.object") }
    public mutating func place() -> String { faker.require("whimsy.place") }

    /// An alliterative release name, in the manner of `Feral Falcon`.
    ///
    /// The alliteration is the point, and it is a property of this function rather than of
    /// any list: a creature is drawn first, then an adjective sharing its initial. That
    /// ordering matters — drawing the adjective first and hunting for a creature to match
    /// fails on the letters with no creature at all, where this way every creature has at
    /// least one adjective waiting.
    ///
    /// Falls back to an unmatched pair rather than trapping. A letter with no adjective is
    /// a gap in two authored lists, not a reason to crash somebody's fixture run, and
    /// `Feral Wombat` is a worse release name rather than a wrong one.
    public mutating func releaseName() -> String {
        let animal = creature()
        guard let initial = animal.first,
            let pool = faker.locale.strings("whimsy.adjective")
        else { return "\(adjective()) \(animal)" }

        var matching: [String] = []
        for index in 0..<pool.count {
            guard let word = try? pool.string(at: index) else { continue }
            if word.first == initial { matching.append(word) }
        }
        guard !matching.isEmpty else { return "\(adjective()) \(animal)" }
        return "\(faker.pick(matching)) \(animal)"
    }

    // MARK: - Institutions

    /// A restaurant name.
    public mutating func restaurantName() -> String {
        faker.expand(faker.require("whimsy.restaurant_pattern"))
    }

    /// A cuisine, which is a category rather than a claim — `Lebanese` classifies a
    /// restaurant the way `IPA` classifies a beer.
    public mutating func cuisine() -> String { faker.require("whimsy.cuisine") }

    /// A dish, as a menu writes one: a treatment, a thing, and something it sits on.
    public mutating func dishName() -> String {
        faker.expand(faker.require("whimsy.dish_pattern"))
    }

    /// A school name.
    public mutating func schoolName() -> String {
        faker.expand(faker.require("whimsy.school_pattern"))
    }

    /// An academic department, for the column a university admin system has.
    public mutating func faculty() -> String { faker.require("whimsy.faculty") }

    // MARK: - Invented people and places

    /// A superhero alias.
    ///
    /// Composed rather than listed for the reason the whole namespace exists: a list of
    /// real ones is a list of trademarks belonging to two companies.
    public mutating func superheroName() -> String {
        faker.expand(faker.require("whimsy.superhero_pattern"))
    }

    /// A superpower.
    public mutating func superpower() -> String { faker.require("whimsy.power") }

    /// A mountain, named the way a survey names one rather than the way a myth does.
    public mutating func peakName() -> String {
        faker.bothify(faker.expand(faker.require("whimsy.peak_pattern")))
    }

    /// A star, in the two registers astronomy uses: a catalogue designation or a
    /// constellation-and-Bayer form.
    public mutating func starName() -> String {
        faker.bothify(faker.expand(faker.require("whimsy.star_pattern")))
    }

    /// Technobabble — a sentence with the shape of technical advice and no content.
    ///
    /// This is the one that came back from the scope cut. `hacker phrases` were excluded
    /// because faker's were a word list nobody could account for; composed from this
    /// project's own vocabulary there is nothing to be wrong about, because the sentence
    /// does not mean anything.
    public mutating func technobabble() -> String {
        faker.expand(faker.require("whimsy.technobabble_pattern"))
    }
}


// MARK: - Sport

extension Faker {
    public var sport: SportFaker {
        get { SportFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var beverage: BeverageFaker {
        get { BeverageFaker(faker: self) }
        set { self = newValue.faker }
    }
}

/// Clubs, grounds and competitions, invented rather than listed.
///
/// Football club naming is a small and very well-defined grammar — British clubs are
/// `{place} {suffix}` almost without exception, and the suffix set is closed enough that a
/// supporter could recite it. What makes composing them safe is that the places come from
/// this project's invented landscape pool rather than from real towns: the pattern is
/// authentic and the input is not, so `Fjord Rovers` cannot collide with anybody's club.
///
/// A list of real clubs would be a list of trademarks, which is exactly what removed the
/// `team` namespace from this project in the first place.
public struct SportFaker {
    var faker: Faker

    public mutating func club() -> String {
        faker.expand(faker.require("sport.club_pattern"))
    }

    public mutating func venue() -> String {
        faker.expand(faker.require("sport.venue_pattern"))
    }

    public mutating func trophy() -> String {
        faker.expand(faker.require("sport.trophy_pattern"))
    }

    /// The sport itself, which is a fact rather than an invention — football is a sport in
    /// the way a saloon is a body style, and neither is anybody's property.
    public mutating func discipline() -> String { faker.require("sport.discipline") }

    /// The suffix alone, for a caller assembling a club name their own way.
    public mutating func clubSuffix() -> String { faker.require("sport.club_suffix") }
}

// MARK: - Beverage

/// Drinks, split the way everything else here is: the **style** is a fact and the **name**
/// is an invention.
///
/// An IPA is a style of beer and a Merlot is a grape, in the way a saloon is a body style —
/// generic terms anybody can check, carried for the same reason `vehicle.type` is. What
/// composes is the brand on the label, because a list of real breweries is a list of real
/// trademarks, and that is what got `music` and `book` cut from this project.
public struct BeverageFaker {
    var faker: Faker

    public mutating func beer() -> String {
        faker.expand(faker.require("beverage.beer_pattern"))
    }

    public mutating func brewery() -> String {
        faker.expand(faker.require("beverage.brewery_pattern"))
    }

    /// Whisky, where the naming convention is itself the joke — `Glen` is simply Gaelic
    /// for valley, and half of Speyside is named that way.
    public mutating func whisky() -> String {
        faker.expand(faker.require("beverage.whisky_pattern"))
    }

    public mutating func wine() -> String {
        faker.expand(faker.require("beverage.wine_pattern"))
    }

    public mutating func cocktail() -> String {
        faker.expand(faker.require("beverage.cocktail_pattern"))
    }

    public mutating func beerStyle() -> String { faker.require("beverage.beer_style") }
    public mutating func grape() -> String { faker.require("beverage.grape") }
    public mutating func ageStatement() -> String { faker.require("beverage.age_statement") }

    /// A coffee, as a roaster labels one.
    public mutating func coffee() -> String {
        faker.expand(faker.require("beverage.coffee_pattern"))
    }

    /// A tea blend.
    public mutating func tea() -> String {
        faker.expand(faker.require("beverage.tea_pattern"))
    }

    public mutating func roast() -> String { faker.require("beverage.roast") }
    public mutating func teaBase() -> String { faker.require("beverage.tea_base") }
}
