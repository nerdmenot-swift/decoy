extension Faker {
    public var location: LocationFaker {
        get { LocationFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct LocationFaker {
    var faker: Faker

    // MARK: - Streets

    public mutating func buildingNumber() -> String {
        faker.expand(faker.require("location.building_number"))
    }

    public mutating func streetSuffix() -> String { faker.require("location.street_suffix") }

    /// A street name from the locale's own pattern.
    ///
    /// English builds streets from surnames (`"Kowalski Ridge"`); other locales use a
    /// fixed list. The pattern lives in the corpus so neither is hard-coded.
    public mutating func streetName() -> String {
        if let pattern = faker.draw("location.street_pattern") {
            return faker.expand(pattern)
        }
        return faker.require("location.street_name")
    }

    public mutating func streetAddress(full: Bool = false) -> String {
        let path = full ? "location.street_address.full" : "location.street_address.normal"
        if let pattern = faker.draw(path) {
            return faker.expand(pattern)
        }
        return "\(buildingNumber()) \(streetName())"
    }

    public mutating func secondaryAddress() -> String {
        faker.expand(faker.require("location.secondary_address"))
    }

    // MARK: - Places

    /// A city in this locale's country.
    ///
    /// The gazetteer first, the composition pattern only as a fallback — and that order
    /// was the wrong way round until the street work went looking at it. faker composes
    /// city names from a prefix, a given name and a suffix, because it had no gazetteer:
    /// "Lake Jenniferville", "Port Karlchester". Decoy has had 180,022 real cities from
    /// GeoNames since the cities adapter landed, and was shadowing all of them with the
    /// invented form in the sixty-nine locales faker gave a pattern to.
    ///
    /// Real place names are better fake data. They geocode, they look right to somebody
    /// who lives there, and the only thing the invented form has over them is that it
    /// cannot accidentally name a real town — which for a city, unlike a person, is not a
    /// problem anybody has.
    /// Every chain reaches `en`, which has 19,000 US cities, so this cannot come up
    /// empty. The composition fallback that used to sit here is gone with the data —
    /// `decoy-validate` reported the branch as a call no locale could answer, which is
    /// what a fallback becomes once the thing it was falling back from is the only case.
    public mutating func city() -> String {
        faker.require("location.city_name")
    }

    /// A city and the subdivision it is actually in, as one row.
    ///
    /// `city: "Boston", state: "CA"` passes most validators and is nonsense, and it is
    /// what every faker produces, because the two are drawn independently. Drawing the
    /// pair together is the only way they cannot disagree — and for a library aimed at
    /// database seeding, `corpus-strategy.md` argues that matters more than referential
    /// integrity does.
    ///
    /// `city()` and `state()` stay independent draws, because most rows want one or the
    /// other and pairing them would halve the variety for no benefit.
    public mutating func place() -> [String: String] {
        faker.drawRow("location.place") ?? [:]
    }

    /// A city, the subdivision it is in, and a postcode from inside that subdivision.
    ///
    /// The row `corpus-strategy.md` opens its "coherent records" section with:
    /// `city: "Boston", state: "CA", postcode: "10001"` passes most validators and is
    /// nonsense, and it is what every faker produces, because the three are independent
    /// draws.
    ///
    /// The city and subdivision come from one gazetteer row, so they cannot disagree.
    /// The postcode is drawn from that subdivision's own range where the locale has one
    /// — the United States and Canada — and falls back to the national mask elsewhere,
    /// because GeoNames codes subdivisions its own way and only the US codes coincide
    /// with the ISO ones the postcode ranges are keyed by.
    ///
    /// `stateCode` is empty where the gazetteer has no subdivision for that city.
    public mutating func placeAndPostcode()
        -> (city: String, state: String, stateCode: String, postcode: String)
    {
        let row = place()
        let code = row["state_code"] ?? ""
        return (
            row["city"] ?? city(),
            row["state"] ?? "",
            code,
            postcode(state: code) ?? postcode()
        )
    }

    public mutating func county() -> String { faker.require("location.county") }
    /// A subdivision as a coherent `(name, abbr)` row.
    ///
    /// Drawn together so the parts agree. `state()` and `stateAbbreviation()` are
    /// independent draws by design — they fill separate columns — but a row that must
    /// hold both needs them from the same subdivision, and `Bavaria` paired with `HH`
    /// passes most validators while being nonsense.
    public mutating func stateRow() -> [String: String] {
        faker.drawRow("location.state") ?? [:]
    }

    public mutating func state() -> String {
        // Composite where an adapter supplied one, a plain list where the bootstrap
        // corpus still does. Both shapes are live during the migration.
        if let row = faker.drawRow("location.state"), let name = row["name"] { return name }
        return faker.require("location.state")
    }

    public mutating func stateAbbreviation() -> String {
        if let row = faker.drawRow("location.state"), let abbr = row["abbr"] { return abbr }
        return faker.require("location.state_abbr")
    }
    public mutating func country() -> String { faker.require("location.country") }

    /// A continent in the locale's own language.
    ///
    /// Six, not seven: CLDR follows UN M49 and models the Americas as one region, and a
    /// library that split them would be asserting a schoolroom convention that much of
    /// the world does not use.
    public mutating func continent() -> String { faker.require("location.continent") }
    public mutating func timeZone() -> String { faker.require("location.time_zone") }

    /// Postcodes come from a format string, so `#####-####` and `AA# #AA` both work
    /// without the generator knowing which country it is in.
    public mutating func postcode() -> String {
        faker.bothify(faker.require("location.postcode"))
    }

    /// A postcode that belongs to `state`, where the locale knows the difference.
    ///
    /// `postcode()` draws from a national mask, so a US address could pair Alaska with a
    /// Florida ZIP. Three locales carry real per-subdivision ranges — `en_US` has 52,
    /// `en_CA` 13 — and all of them were compiled and unreachable, which is why this
    /// exists: a hundred paths of correct data that nothing could draw.
    ///
    /// The key is the subdivision's abbreviation, matching ``stateRow()``'s `abbr`, so a
    /// coherent address is `let s = stateRow(); postcode(state: s["abbr"])`.
    ///
    /// Returns `nil` when the locale has no ranges or does not know that subdivision —
    /// `nil` rather than a national postcode, because silently ignoring the constraint is
    /// how you get an Alaskan address in Florida and never find out.
    public mutating func postcode(state abbreviation: String?) -> String? {
        guard let abbreviation,
            let pattern = faker.draw("location.postcode_by_state.\(abbreviation)")
        else { return nil }
        return faker.bothify(faker.expand(pattern))
    }

    /// A subdivision and a postcode drawn from inside it.
    ///
    /// The correlated form, for the same reason ``countryCode()`` returns a triple: two
    /// independent draws produce a pairing that does not exist.
    public mutating func stateAndPostcode() -> (state: String, abbr: String, postcode: String) {
        let row = stateRow()
        let name = row["name"] ?? ""
        let abbr = row["abbr"] ?? ""
        return (name, abbr, postcode(state: abbr) ?? postcode())
    }

    /// A full postal address in the locale's own layout.
    public mutating func postalAddress() -> String {
        faker.expand(faker.require("location.postal_address"))
    }

    // MARK: - Correlated records

    /// An ISO 3166-1 country as a coherent `(alpha2, alpha3, numeric)` triple.
    ///
    /// Drawn as one row, so the parts always agree — three independent draws would
    /// produce countries that do not exist.
    public mutating func countryCode() -> [String: String] {
        faker.drawRow("location.country_code") ?? [:]
    }

    public mutating func countryCodeAlpha2() -> String { countryCode()["alpha2"] ?? "" }
    public mutating func countryCodeAlpha3() -> String { countryCode()["alpha3"] ?? "" }

    /// A language as a coherent `(name, alpha2, alpha3)` row.
    public mutating func language() -> [String: String] {
        faker.drawRow("location.language") ?? [:]
    }

    // MARK: - Directions and coordinates

    public mutating func direction(abbreviated: Bool = false) -> String {
        let ordinal = faker.bool()
        let key = ordinal ? "ordinal" : "cardinal"
        return faker.require("location.direction.\(key)\(abbreviated ? "_abbr" : "")")
    }

    public mutating func cardinalDirection(abbreviated: Bool = false) -> String {
        faker.require("location.direction.cardinal\(abbreviated ? "_abbr" : "")")
    }

    public mutating func ordinalDirection(abbreviated: Bool = false) -> String {
        faker.require("location.direction.ordinal\(abbreviated ? "_abbr" : "")")
    }

    public mutating func latitude() -> Double {
        (faker.double(in: -90...90) * 10_000).rounded() / 10_000
    }

    public mutating func longitude() -> Double {
        (faker.double(in: -180...180) * 10_000).rounded() / 10_000
    }

    /// A coordinate pair, optionally within a radius of an origin.
    public mutating func coordinate(
        near origin: (latitude: Double, longitude: Double)? = nil,
        radiusKm: Double = 10
    ) -> (latitude: Double, longitude: Double) {
        guard let origin else { return (latitude(), longitude()) }
        // One degree of latitude is ~111 km everywhere; longitude narrows with the
        // cosine of latitude, so ignoring that would stretch points near the poles.
        let radiusDegrees = radiusKm / 111.0
        let angle = faker.double(in: 0...(2 * Double.pi))
        let distance = (faker.double(in: 0...1)).squareRoot() * radiusDegrees
        let latitudeRadians = origin.latitude * Double.pi / 180
        let cosine = Swift.max(0.01, _cos(latitudeRadians))
        return (
            ((origin.latitude + distance * _sin(angle)) * 10_000).rounded() / 10_000,
            ((origin.longitude + distance * _cos(angle) / cosine) * 10_000).rounded() / 10_000
        )
    }
}

// Minimal trigonometry so the core module keeps importing nothing.
// Argument reduction plus a Taylor series is ample for jittering a coordinate.
private func _sin(_ x: Double) -> Double {
    var value = x.truncatingRemainder(dividingBy: 2 * Double.pi)
    if value > Double.pi { value -= 2 * Double.pi }
    if value < -Double.pi { value += 2 * Double.pi }
    let x2 = value * value
    var term = value
    var sum = value
    for n in 1...7 {
        term *= -x2 / Double((2 * n) * (2 * n + 1))
        sum += term
    }
    return sum
}

private func _cos(_ x: Double) -> Double { _sin(x + Double.pi / 2) }
