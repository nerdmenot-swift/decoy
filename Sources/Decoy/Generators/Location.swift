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

    public mutating func city() -> String {
        if let pattern = faker.draw("location.city_pattern") {
            return faker.expand(pattern)
        }
        return faker.require("location.city_name")
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

    public mutating func cityPrefix() -> String { faker.require("location.city_prefix") }
    public mutating func citySuffix() -> String { faker.require("location.city_suffix") }
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
    public mutating func continent() -> String { faker.require("location.continent") }
    public mutating func timeZone() -> String { faker.require("location.time_zone") }

    /// Postcodes come from a format string, so `#####-####` and `AA# #AA` both work
    /// without the generator knowing which country it is in.
    public mutating func postcode() -> String {
        faker.bothify(faker.require("location.postcode"))
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
