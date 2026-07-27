import Testing

@testable import Decoy

/// Calls every generator against the real English corpus.
///
/// The generators are a mapping from Swift methods to corpus paths, and a wrong path
/// traps at call time rather than at compile time. Nothing but actually invoking each
/// one proves the mapping is right, so this exists to be exhaustive rather than
/// interesting: every method, checked for a non-empty result.
@Suite(
    "Generator coverage",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct GeneratorSmokeTests {

    private func english() throws -> Faker {
        Faker(seed: 20_260_727, locale: try RealCorpus.locale("en", chain: ["en", "base"]))
    }

    /// Runs `body` and requires a non-empty result, naming the generator on failure.
    private func check(
        _ label: String,
        _ faker: inout Faker,
        _ body: (inout Faker) -> String
    ) {
        let value = body(&faker)
        #expect(!value.isEmpty, "\(label) produced an empty string")
    }

    @Test("person generators all resolve")
    func person() throws {
        var f = try english()
        check("firstName", &f) { $0.person.firstName() }
        check("firstName(.female)", &f) { $0.person.firstName(.female) }
        check("firstName(.male)", &f) { $0.person.firstName(.male) }
        check("middleName", &f) { $0.person.middleName() }
        check("lastName", &f) { $0.person.lastName() }
        check("prefix", &f) { $0.person.prefix() }
        check("suffix", &f) { $0.person.suffix() }
        check("fullName", &f) { $0.person.fullName() }
        check("sex", &f) { $0.person.sex() }
        check("gender", &f) { $0.person.gender() }
        check("jobTitle", &f) { $0.person.jobTitle() }
        check("jobDescriptor", &f) { $0.person.jobDescriptor() }
        check("jobArea", &f) { $0.person.jobArea() }
        check("jobType", &f) { $0.person.jobType() }
        check("zodiacSign", &f) { $0.person.zodiacSign() }
        check("bio", &f) { $0.person.bio() }
    }

    @Test("location generators all resolve")
    func location() throws {
        var f = try english()
        check("buildingNumber", &f) { $0.location.buildingNumber() }
        check("streetSuffix", &f) { $0.location.streetSuffix() }
        check("streetName", &f) { $0.location.streetName() }
        check("streetAddress", &f) { $0.location.streetAddress() }
        check("streetAddress(full:)", &f) { $0.location.streetAddress(full: true) }
        check("secondaryAddress", &f) { $0.location.secondaryAddress() }
        check("city", &f) { $0.location.city() }
        check("cityPrefix", &f) { $0.location.cityPrefix() }
        check("citySuffix", &f) { $0.location.citySuffix() }
        check("county", &f) { $0.location.county() }
        check("state", &f) { $0.location.state() }
        check("stateAbbreviation", &f) { $0.location.stateAbbreviation() }
        check("country", &f) { $0.location.country() }
        check("continent", &f) { $0.location.continent() }
        check("timeZone", &f) { $0.location.timeZone() }
        check("postcode", &f) { $0.location.postcode() }
        check("postalAddress", &f) { $0.location.postalAddress() }
        check("direction", &f) { $0.location.direction() }
        check("cardinalDirection", &f) { $0.location.cardinalDirection() }
        check("ordinalDirection", &f) { $0.location.ordinalDirection() }
        check("countryCodeAlpha2", &f) { $0.location.countryCodeAlpha2() }
        check("countryCodeAlpha3", &f) { $0.location.countryCodeAlpha3() }
        #expect(!f.location.language().isEmpty)

        let latitude = f.location.latitude()
        let longitude = f.location.longitude()
        #expect((-90...90).contains(latitude))
        #expect((-180...180).contains(longitude))
    }

    @Test("company, commerce and finance generators all resolve")
    func business() throws {
        var f = try english()
        check("company.name", &f) { $0.company.name() }
        check("company.adjective", &f) { $0.company.adjective() }
        check("company.descriptor", &f) { $0.company.descriptor() }
        check("company.noun", &f) { $0.company.noun() }
        check("company.legalEntityType", &f) { $0.company.legalEntityType() }
        check("company.buzzPhrase", &f) { $0.company.buzzPhrase() }
        check("company.catchPhrase", &f) { $0.company.catchPhrase() }

        check("commerce.department", &f) { $0.commerce.department() }
        check("commerce.product", &f) { $0.commerce.product() }
        check("commerce.productAdjective", &f) { $0.commerce.productAdjective() }
        check("commerce.productMaterial", &f) { $0.commerce.productMaterial() }
        check("commerce.productName", &f) { $0.commerce.productName() }
        check("commerce.productDescription", &f) { $0.commerce.productDescription() }
        check("commerce.price", &f) { $0.commerce.price() }
        check("commerce.ean13", &f) { $0.commerce.ean13() }
        check("commerce.sku", &f) { $0.commerce.sku() }

        check("finance.accountType", &f) { $0.finance.accountType() }
        check("finance.transactionType", &f) { $0.finance.transactionType() }
        check("finance.transactionDescription", &f) { $0.finance.transactionDescription() }
        check("finance.accountNumber", &f) { $0.finance.accountNumber() }
        check("finance.routingNumber", &f) { $0.finance.routingNumber() }
        check("finance.currencyName", &f) { $0.finance.currencyName() }
        check("finance.currencyCode", &f) { $0.finance.currencyCode() }
        check("finance.creditCardNumber", &f) { $0.finance.creditCardNumber() }
        check("finance.iban", &f) { $0.finance.iban() }
        check("finance.bitcoinAddress", &f) { $0.finance.bitcoinAddress() }
    }

    @Test("internet and phone generators all resolve")
    func network() throws {
        var f = try english()
        check("domainSuffix", &f) { $0.internet.domainSuffix() }
        check("domainWord", &f) { $0.internet.domainWord() }
        check("domainName", &f) { $0.internet.domainName() }
        check("url", &f) { $0.internet.url() }
        check("email", &f) { $0.internet.email() }
        check("freeEmail", &f) { $0.internet.freeEmail() }
        check("username", &f) { $0.internet.username() }
        check("password", &f) { $0.internet.password() }
        check("ipv4", &f) { $0.internet.ipv4() }
        check("ipv6", &f) { $0.internet.ipv6() }
        check("macAddress", &f) { $0.internet.macAddress() }
        check("httpMethod", &f) { $0.internet.httpMethod() }
        check("userAgent", &f) { $0.internet.userAgent() }
        check("jwtAlgorithm", &f) { $0.internet.jwtAlgorithm() }
        check("emoji", &f) { $0.internet.emoji() }
        check("hexColor", &f) { $0.internet.hexColor() }
        #expect((1...65_535).contains(f.internet.port()))
        #expect(f.internet.httpStatusCode() > 0)
        for category in InternetFaker.HTTPStatusCategory.allCases {
            #expect(f.internet.httpStatusCode(category) > 0, "status class \(category)")
        }

        for style in PhoneFaker.Style.allCases {
            check("phone.number(\(style))", &f) { $0.phone.number(style) }
        }
        check("phone.imei", &f) { $0.phone.imei() }
    }

    @Test("content generators all resolve")
    func content() throws {
        var f = try english()
        check("word.adjective", &f) { $0.word.adjective() }
        check("word.adverb", &f) { $0.word.adverb() }
        check("word.conjunction", &f) { $0.word.conjunction() }
        check("word.interjection", &f) { $0.word.interjection() }
        check("word.noun", &f) { $0.word.noun() }
        check("word.preposition", &f) { $0.word.preposition() }
        check("word.verb", &f) { $0.word.verb() }
        check("word.words", &f) { $0.word.words() }

        check("lorem.word", &f) { $0.lorem.word() }
        check("lorem.words", &f) { $0.lorem.words() }
        check("lorem.sentence", &f) { $0.lorem.sentence() }
        check("lorem.sentences", &f) { $0.lorem.sentences() }
        check("lorem.paragraph", &f) { $0.lorem.paragraph() }
        check("lorem.paragraphs", &f) { $0.lorem.paragraphs() }
        check("lorem.slug", &f) { $0.lorem.slug() }
        check("lorem.text", &f) { $0.lorem.text() }

        check("color.human", &f) { $0.color.human() }
        check("color.space", &f) { $0.color.space() }
        check("color.hex", &f) { $0.color.hex() }
        check("color.cssRGB", &f) { $0.color.cssRGB() }
    }

    @Test("catalogue generators all resolve")
    func catalogue() throws {
        var f = try english()
        check("vehicle.manufacturer", &f) { $0.vehicle.manufacturer() }
        check("vehicle.model", &f) { $0.vehicle.model() }
        check("vehicle.type", &f) { $0.vehicle.type() }
        check("vehicle.fuel", &f) { $0.vehicle.fuel() }
        check("vehicle.bicycleType", &f) { $0.vehicle.bicycleType() }
        check("vehicle.name", &f) { $0.vehicle.name() }
        check("vehicle.vin", &f) { $0.vehicle.vin() }
        check("vehicle.registrationPlate", &f) { $0.vehicle.registrationPlate() }

        check("animal.type", &f) { $0.animal.type() }
        check("animal.dog", &f) { $0.animal.dog() }
        check("animal.cat", &f) { $0.animal.cat() }
        check("animal.bird", &f) { $0.animal.bird() }
        check("animal.fish", &f) { $0.animal.fish() }
        check("animal.horse", &f) { $0.animal.horse() }
        check("animal.insect", &f) { $0.animal.insect() }
        check("animal.lion", &f) { $0.animal.lion() }
        check("animal.bear", &f) { $0.animal.bear() }
        check("animal.snake", &f) { $0.animal.snake() }
        check("animal.rabbit", &f) { $0.animal.rabbit() }
        check("animal.cow", &f) { $0.animal.cow() }
        check("animal.rodent", &f) { $0.animal.rodent() }
        check("animal.cetacean", &f) { $0.animal.cetacean() }
        check("animal.crocodilia", &f) { $0.animal.crocodilia() }
        check("animal.any", &f) { $0.animal.any() }
        check("animal.petName", &f) { $0.animal.petName() }

        check("food.dish", &f) { $0.food.dish() }
        check("food.ingredient", &f) { $0.food.ingredient() }
        check("food.fruit", &f) { $0.food.fruit() }
        check("food.vegetable", &f) { $0.food.vegetable() }
        check("food.meat", &f) { $0.food.meat() }
        check("food.spice", &f) { $0.food.spice() }
        check("food.adjective", &f) { $0.food.adjective() }
        check("food.ethnicCategory", &f) { $0.food.ethnicCategory() }
        check("food.description", &f) { $0.food.description() }
        check("food.dishName", &f) { $0.food.dishName() }

        check("book.title", &f) { $0.book.title() }
        check("book.author", &f) { $0.book.author() }
        check("book.genre", &f) { $0.book.genre() }
        check("book.publisher", &f) { $0.book.publisher() }
        check("book.series", &f) { $0.book.series() }
        check("book.format", &f) { $0.book.format() }
        check("book.isbn", &f) { $0.book.isbn() }

        check("music.genre", &f) { $0.music.genre() }
        check("music.artist", &f) { $0.music.artist() }
        check("music.album", &f) { $0.music.album() }
        check("music.songName", &f) { $0.music.songName() }
    }

    @Test("technical generators all resolve")
    func technical() throws {
        var f = try english()
        #expect(!f.science.chemicalElement().isEmpty)
        #expect(!f.science.unit().isEmpty)

        check("system.fileExtension", &f) { $0.system.fileExtension() }
        check("system.mimeType", &f) { $0.system.mimeType() }
        check("system.directoryPath", &f) { $0.system.directoryPath() }
        check("system.fileName", &f) { $0.system.fileName() }
        check("system.filePath", &f) { $0.system.filePath() }
        check("system.semver", &f) { $0.system.semver() }

        check("hacker.abbreviation", &f) { $0.hacker.abbreviation() }
        check("hacker.adjective", &f) { $0.hacker.adjective() }
        check("hacker.noun", &f) { $0.hacker.noun() }
        check("hacker.verb", &f) { $0.hacker.verb() }
        check("hacker.ingverb", &f) { $0.hacker.ingverb() }
        check("hacker.phrase", &f) { $0.hacker.phrase() }

        check("database.column", &f) { $0.database.column() }
        check("database.type", &f) { $0.database.type() }
        check("database.collation", &f) { $0.database.collation() }
        check("database.engine", &f) { $0.database.engine() }

        #expect(!f.airline.airline().isEmpty)
        #expect(!f.airline.airport().isEmpty)
        #expect(!f.airline.airplane().isEmpty)
        check("airline.aircraftType", &f) { $0.airline.aircraftType() }
        check("airline.flightNumber", &f) { $0.airline.flightNumber() }
        check("airline.seat", &f) { $0.airline.seat() }
        check("airline.recordLocator", &f) { $0.airline.recordLocator() }

        check("app.name", &f) { $0.app.name() }
        check("app.version", &f) { $0.app.version() }
        check("app.author", &f) { $0.app.author() }

        check("team.creature", &f) { $0.team.creature() }
        check("team.name", &f) { $0.team.name() }
    }

    // MARK: - Correctness beyond non-emptiness

    /// Templates must be fully expanded — a leaked `{{token}}` means the resolver
    /// silently failed and the fixture contains markup instead of data.
    @Test("no generator leaks unexpanded template markup")
    func noLeakedTemplates() throws {
        var f = try english()
        for _ in 0..<200 {
            for value in [
                f.person.fullName(), f.person.jobTitle(), f.person.bio(),
                f.location.streetAddress(full: true), f.location.city(),
                f.location.postalAddress(), f.company.name(),
                f.commerce.productName(), f.commerce.productDescription(),
                f.finance.transactionDescription(), f.hacker.phrase(),
                f.team.name(), f.app.author(), f.internet.userAgent(),
            ] {
                #expect(!value.contains("{{"), "unexpanded template in: \(value)")
                #expect(!value.contains("}}"), "unexpanded template in: \(value)")
                #expect(!value.contains("#"), "unsubstituted digit placeholder in: \(value)")
            }
        }
    }

    /// Checksummed identifiers must actually validate, or every fixture is rejected
    /// by the code most worth testing.
    @Test("checksummed identifiers validate")
    func checksums() throws {
        var f = try english()
        for _ in 0..<200 {
            let card = f.finance.creditCardNumber()
            #expect(Self.passesLuhn(card), "invalid Luhn: \(card)")

            let iban = f.finance.iban()
            #expect(
                FinanceFaker.mod97(String(iban.dropFirst(4)) + String(iban.prefix(4))) == 1,
                "invalid IBAN checksum: \(iban)"
            )

            let isbn = f.book.isbn()
            #expect(isbn.count == 13)
            #expect(Self.passesEAN(isbn), "invalid ISBN-13 check digit: \(isbn)")
            #expect(Self.passesEAN(f.commerce.ean13()))
        }
    }

    /// `!` must yield 2-9, never 0 or 1 — that is the whole reason faker distinguishes
    /// it from `#`. Asserted directly rather than inferred from phone output, because
    /// some formats legitimately begin with a literal `1` country code.
    @Test("the ! digit class excludes 0 and 1")
    func exclamationDigitClass() throws {
        var f = try english()
        for _ in 0..<2_000 {
            let value = f.numerify("!")
            #expect(("2"..."9").contains(value), "! produced \(value)")
        }
        // And a mixed pattern keeps each class in its own position.
        for _ in 0..<500 {
            let value = f.numerify("!##")
            let digits = Array(value).compactMap(\.wholeNumberValue)
            #expect(digits.count == 3)
            #expect(digits[0] >= 2)
        }
    }

    @Test("phone numbers are fully substituted and long enough to dial")
    func phoneNumbers() throws {
        var f = try english()
        for style in PhoneFaker.Style.allCases {
            for _ in 0..<200 {
                let number = f.phone.number(style)
                #expect(!number.contains("#") && !number.contains("!"), "unsubstituted: \(number)")
                #expect(number.compactMap(\.wholeNumberValue).count >= 7, "too short: \(number)")
            }
        }
    }

    @Test("prices format independently of the host locale")
    func priceFormatting() throws {
        var f = try english()
        for _ in 0..<200 {
            let price = f.commerce.price(in: 1...1_000)
            #expect(!price.contains(","), "a comma decimal separator would break parsing")
            let parts = price.split(separator: ".")
            #expect(parts.count == 2 && parts[1].count == 2, "expected two decimals: \(price)")
            #expect(Double(price) != nil, "not parseable: \(price)")
        }
    }

    @Test("VINs exclude the letters ISO 3779 forbids")
    func vinAlphabet() throws {
        var f = try english()
        for _ in 0..<200 {
            let vin = f.vehicle.vin()
            #expect(vin.count == 17)
            #expect(
                !vin.contains("I") && !vin.contains("O") && !vin.contains("Q"),
                "VIN contains a forbidden letter: \(vin)"
            )
        }
    }

    // MARK: - Helpers

    private static func passesLuhn(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard digits.count > 1 else { return false }
        var sum = 0
        for (offset, value) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    private static func passesEAN(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == 13 else { return false }
        return CommerceFaker.eanCheckDigit(String(code.dropLast())) == digits[12]
    }
}
