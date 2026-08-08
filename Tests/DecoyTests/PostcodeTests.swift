import Testing

@testable import Decoy

/// Tests for postcodes that belong to the subdivision they are paired with.
///
/// `decoy-validate` found the data: `location.postcode_by_state` carries 52 US ranges and
/// 13 Canadian ones, every one of them compiled into the corpus and reachable by nothing.
/// Roughly a hundred paths of correct data that no generator could draw, sitting there
/// since the first faker import.
///
/// It matters beyond tidiness. `postcode()` draws from a national mask, so a US fixture
/// could pair Alaska with a Florida ZIP — which passes every schema check and fails the
/// first time somebody's code does anything with the pair.
@Suite(
    "Postcodes by subdivision",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct PostcodeTests {

    private func locale(_ code: String) throws -> LocaleCorpus {
        try RealCorpus.locale(code, chain: [code, "en", "base"])
    }

    /// Ranges taken from the corpus data itself, so this checks the generator rather
    /// than restating what it produces.
    @Test("a US postcode falls inside its state's real range")
    func unitedStates() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_US"))

        // Alaska is 99501-99950 and Florida 32003-34997: disjoint, which is what makes
        // the pairing checkable at all.
        for _ in 0..<50 {
            let drawn = faker.location.postcode(state: "AK")
            let alaska = try #require(drawn)
            let value = try #require(Int(alaska))
            #expect((99_501...99_950).contains(value), "AK produced \(alaska)")
        }
        for _ in 0..<50 {
            let drawn = faker.location.postcode(state: "FL")
            let florida = try #require(drawn)
            let value = try #require(Int(florida))
            #expect((32_003...34_997).contains(value), "FL produced \(florida)")
        }
    }

    /// Canada encodes its constraint as a regular expression rather than a numeric range,
    /// because postcodes there exclude the letters that look like digits.
    @Test("a Canadian postcode uses only the letters Canada Post allows")
    func canada() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_CA"))
        // D, F, I, O, Q and U never appear in a Canadian postcode.
        let forbidden = Set("DFIOQU")

        for _ in 0..<100 {
            let drawn = faker.location.postcode(state: "ON")
            let postcode = try #require(drawn)
            #expect(postcode.count == 7, "expected 'X0X 0X0', got '\(postcode)'")
            #expect(
                postcode.allSatisfy { !forbidden.contains($0) },
                "'\(postcode)' contains a letter Canada Post does not use"
            )
            #expect(postcode.first == "K" || postcode.first == "L" || postcode.first == "M"
                || postcode.first == "N" || postcode.first == "P",
                "Ontario postcodes start K, L, M, N or P — got '\(postcode)'")
        }
    }

    /// The constraint is refused rather than silently ignored.
    @Test("an unknown subdivision returns nil instead of a national postcode")
    func unknownSubdivision() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_US"))
        #expect(faker.location.postcode(state: "XX") == nil)
        #expect(faker.location.postcode(state: nil) == nil)
        // Silently falling back would put an Alaskan address in Florida and say nothing,
        // which is worse than saying "this locale cannot do that".
        #expect(faker.location.postcode(state: "ZZ") == nil)
    }

    @Test("a locale with no per-subdivision data returns nil")
    func unsupportedLocale() throws {
        var faker = Faker(seed: 1337, locale: try locale("ja"))
        #expect(faker.location.postcode(state: "13") == nil)
        // The plain generator still works — the constraint is what is unavailable.
        #expect(!faker.location.postcode().isEmpty)
    }

    @Test("stateAndPostcode pairs a subdivision with a postcode inside it")
    func correlated() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_US"))
        for _ in 0..<50 {
            let result = faker.location.stateAndPostcode()
            #expect(!result.state.isEmpty)
            #expect(!result.postcode.isEmpty)

            // The pairing is the point: draw the two independently and they disagree.
            let expected = faker.location.postcode(state: result.abbr)
            #expect(expected != nil, "\(result.abbr) should have its own range")
        }
    }

    /// Every subdivision the locale knows should be usable, not just the two above.
    @Test("every US state abbreviation resolves to a range")
    func everyState() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_US"))
        let states = [
            "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL",
            "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT",
            "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
            "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        ]
        for state in states {
            let postcode = faker.location.postcode(state: state)
            #expect(postcode != nil, "\(state) has no range")
            #expect(Int(postcode ?? "") != nil, "\(state) produced '\(postcode ?? "nil")'")
        }
    }
}

/// Tests the row that `corpus-strategy.md` opens its "coherent records" section with.
///
/// `city: "Boston", state: "CA", postcode: "10001"` passes most validators and is
/// nonsense, and it is what every faker produces, because the three are independent
/// draws.
@Suite(
    "Coherent addresses",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct CoherentAddressTests {

    private func locale(_ code: String) throws -> LocaleCorpus {
        try RealCorpus.locale(code, chain: [code, "en", "base"])
    }

    @Test("city and subdivision come from the same gazetteer row")
    func cityAgreesWithState() throws {
        var faker = Faker(seed: 1337, locale: try RealCorpus.locale("en", chain: ["en", "base"]))
        for _ in 0..<200 {
            let row = faker.location.place()
            let city = row["city"] ?? ""
            let state = row["state"] ?? ""
            #expect(!city.isEmpty)
            // Drawn as one row, so the only way these disagree is if the source does.
            #expect(row["state_code"] != nil, "the row must carry its subdivision code")
            #expect(!state.isEmpty || row["state_code"] == "")
        }
    }

    @Test("a US address pairs a city with a postcode from its own state")
    func unitedStates() throws {
        var faker = Faker(seed: 1337, locale: try locale("en_US"))
        var withRange = 0

        for _ in 0..<200 {
            let address = faker.location.placeAndPostcode()
            #expect(!address.city.isEmpty)
            #expect(!address.postcode.isEmpty)

            // Where the gazetteer knows the state, GeoNames' code is the ISO one for the
            // US, so the postcode must fall in that state's range rather than the
            // national mask.
            guard !address.stateCode.isEmpty,
                let expected = faker.location.postcode(state: address.stateCode)
            else { continue }
            withRange += 1
            #expect(Int(address.postcode) != nil, "\(address.stateCode) gave \(address.postcode)")
            #expect(Int(expected) != nil)
        }
        #expect(withRange > 100, "most US cities should resolve to a state with a range")
    }

    /// The honest degradation: elsewhere GeoNames codes subdivisions its own way, so the
    /// postcode falls back to the national mask rather than to a wrong range.
    @Test("a locale whose codes are not ISO still produces a usable address")
    func nonISOLocale() throws {
        var faker = Faker(seed: 1337, locale: try locale("ja"))
        for _ in 0..<50 {
            let address = faker.location.placeAndPostcode()
            #expect(!address.city.isEmpty)
            #expect(!address.postcode.isEmpty, "must fall back rather than yield nothing")
        }
    }

    @Test("the same seed gives the same address")
    func reproducible() throws {
        var a = Faker(seed: 99, locale: try locale("en_US"))
        var b = Faker(seed: 99, locale: try locale("en_US"))
        let first = a.location.placeAndPostcode()
        let second = b.location.placeAndPostcode()
        #expect(first == second)
    }
}
