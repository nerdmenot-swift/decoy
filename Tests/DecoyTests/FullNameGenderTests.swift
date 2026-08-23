import Decoy
import DecoyLocales
import Testing

/// `fullName(_:)` honours the gender it is given.
///
/// It did not, in any locale, for as long as the generator existed. A name's shape is
/// data — `{{person.firstName}} {{person.lastName}}` — and the tokens in it take no
/// arguments, so the gender reached only the fallback branch that runs when a locale has
/// no pattern, which is almost never. `fullName(.female)` and `fullName(.male)` returned
/// character-for-character the same name.
///
/// That is the quiet kind of wrong: not a crash, not a chimera, just a public parameter
/// that did nothing, in a library whose whole argument is that its output can be trusted.
/// Nothing caught it because every test that exercised `fullName` called it without a
/// gender, and every test that exercised gender called `firstName`.
@Suite("Full name gender")
struct FullNameGenderTests {

    /// Locales carrying both gendered given-name lists, in four scripts.
    static let locales = ["en", "de", "fr", "mk", "ja", "ko", "ru"]

    private func names(_ code: String, _ gender: Gender?, seed: UInt64 = 1337, count: Int = 6)
        throws -> [String]
    {
        var faker = Faker(seed: seed, locale: try DecoyLocales.locale(code))
        return (0..<count).map { _ in faker.person.fullName(gender) }
    }

    @Test("asking for a gender changes the name")
    func genderIsHonoured() throws {
        for code in Self.locales {
            let female = try names(code, .female)
            let male = try names(code, .male)
            #expect(female != male, "\(code): fullName(.female) and fullName(.male) agree")
        }
    }

    /// The given name comes from the list that was asked for.
    ///
    /// Checked against the corpus rather than by eye, and on a locale whose names are
    /// space-separated so the given part can be isolated without a tokeniser.
    @Test("the given name is drawn from the requested list")
    func drawsFromTheRightList() throws {
        let locale = try DecoyLocales.locale("de")
        var reference = Faker(seed: 4, locale: locale)
        var female = Set<String>(), male = Set<String>()
        for _ in 0..<400 {
            female.insert(reference.person.firstName(.female))
            male.insert(reference.person.firstName(.male))
        }
        // Names held by both lists prove nothing either way.
        let onlyMale = male.subtracting(female)

        var faker = Faker(seed: 99, locale: locale)
        var checked = 0
        for _ in 0..<60 {
            let parts = faker.person.fullName(.female).split(separator: " ").map(String.init)
            for part in parts where onlyMale.contains(part) {
                Issue.record("a female full name contained \(part), which only the male list has")
            }
            checked += 1
        }
        #expect(checked == 60)
    }

    /// Honorifics follow, because `person.prefix` is gendered too and the pattern carries
    /// it now: `Frau Luise` and `Herr Marc`, not `Herr Luise`.
    @Test("an honorific agrees with the name it introduces")
    func honorificsAgree() throws {
        let female = try names("de", .female, seed: 12, count: 40).joined(separator: " ")
        let male = try names("de", .male, seed: 12, count: 40).joined(separator: " ")
        #expect(female.contains("Frau"), "no female honorific appeared in 40 German names")
        #expect(male.contains("Herr"), "no male honorific appeared in 40 German names")
        #expect(!female.contains("Herr "), "a female name was introduced as Herr")
        #expect(!male.contains("Frau "), "a male name was introduced as Frau")
    }

    /// Asking for nothing still asks for nothing.
    ///
    /// The gender rides on the faker during expansion, so the failure mode that design
    /// invites is one leaking past the call that set it — every later name silently male.
    /// Restored around the expansion, and this is what says so: after a gendered draw, the
    /// ungendered ones must still reach both lists.
    @Test("a gendered call does not affect the next ungendered one")
    func noLeak() throws {
        let locale = try DecoyLocales.locale("de")

        var reference = Faker(seed: 4, locale: locale)
        var female = Set<String>(), male = Set<String>()
        for _ in 0..<400 {
            female.insert(reference.person.firstName(.female))
            male.insert(reference.person.firstName(.male))
        }
        let onlyFemale = female.subtracting(male)

        var faker = Faker(seed: 33, locale: locale)
        _ = faker.person.fullName(.male)

        // If `.male` had stuck, not one of these could be a female-only name.
        var sawFemale = false
        for _ in 0..<60 {
            let parts = faker.person.fullName().split(separator: " ").map(String.init)
            if parts.contains(where: onlyFemale.contains) { sawFemale = true; break }
        }
        #expect(sawFemale, "every ungendered name after a .male call was male — the gender stuck")
    }
}
