import Testing

@testable import Decoy

/// Tests the mode that switches every name generator to a trained model.
///
/// Set once rather than per call, because the call site somebody forgets is the one that
/// leaks. The property under test is not "the model works" — that is
/// `SurnameModelTests` — but that turning the mode on actually reaches every name a
/// record is built from, and that leaving it off changes nothing.
@Suite(
    "novelNames mode",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct NovelNamesTests {

    struct Person { var first = ""; var last = "" }

    private func locale(_ code: String) throws -> LocaleCorpus {
        try RealCorpus.locale(code, chain: code == "en" ? ["en", "base"] : [code, "en", "base"])
    }

    private func realNames(_ locale: LocaleCorpus, _ path: String) -> Set<String> {
        guard let table = locale.strings(path) else { return [] }
        return Set((0..<table.count).compactMap { try? table.string(at: $0) })
    }

    /// Off by default. Anything else would rewrite every existing user's fixtures.
    @Test("the mode is off unless asked for")
    func offByDefault() throws {
        let faker = Faker(seed: 1, locale: try locale("en"))
        #expect(!faker.novelNames)
    }

    @Test("off, names come from the real lists")
    func offDrawsRealNames() throws {
        let english = try locale("en")
        let real = realNames(english, "person.last_name.generic")
        var faker = Faker(seed: 5, locale: english)
        let drawn = (0..<2_000).map { _ in faker.person.lastName() }
        let fromList = drawn.filter { real.contains($0) }.count
        #expect(fromList > 1_800, "expected mostly real surnames, got \(fromList)/2000")
    }

    @Test("on, surnames are nobody's")
    func onAvoidsRealSurnames() throws {
        let english = try locale("en")
        let real = realNames(english, "person.last_name.generic")
        var faker = Faker(seed: 5, locale: english, novelNames: true)
        let drawn = (0..<2_000).map { _ in faker.person.lastName() }
        #expect(drawn.allSatisfy { !real.contains($0) }, "a real surname survived the mode")
    }

    /// The guarantee is per field, and stating it precisely matters.
    ///
    /// A generated *first* name may well coincide with a real *surname* — the model that
    /// produced `Miles` was trained on given names and never saw the surname list, so
    /// `Miles` is novel for the field it was drawn for. That is not a leak: a first name
    /// matching somebody's surname identifies nobody. The property that holds, and the
    /// only one worth asserting, is that each component is not a real value *for its own
    /// field*.
    ///
    /// The first version of this test compared every whitespace-separated part of a full
    /// name against the surname list and failed immediately, which looked like a hole in
    /// the mode and was a hole in the test.
    @Test("on, each name component is novel for its own field")
    func componentsAreNovelForTheirField() throws {
        let english = try locale("en")
        let surnames = realNames(english, "person.last_name.generic")
        let givenFemale = realNames(english, "person.first_name.female")
        let givenMale = realNames(english, "person.first_name.male")
        let givenGeneric = realNames(english, "person.first_name.generic")
        let given = givenFemale.union(givenMale).union(givenGeneric)

        var faker = Faker(seed: 9, locale: english, novelNames: true)
        for _ in 0..<2_000 {
            let first = faker.person.firstName()
            let last = faker.person.lastName()
            #expect(!given.contains(first), "'\(first)' is a real given name")
            #expect(!surnames.contains(last), "'\(last)' is a real surname")
        }
    }

    /// The composed form still has to be well-formed, whatever it is made of.
    @Test("on, a full name is still a full name")
    func fullNameIsWellFormed() throws {
        var faker = Faker(seed: 9, locale: try locale("en"), novelNames: true)
        for _ in 0..<500 {
            let full = faker.person.fullName()
            #expect(!full.isEmpty)
            #expect(!full.contains("{{"), "'\(full)' leaked a template")
            #expect(!full.contains("  "), "'\(full)' has a doubled space")
            #expect(full.first != " " && full.last != " ")
        }
    }

    /// The hyphenated pattern is the trap here: it composes two *real* surnames, so a
    /// mode that only swapped the plain draw would still hand back real people joined by
    /// a hyphen.
    @Test("on, the compound surname pattern is bypassed")
    func compoundPatternBypassed() throws {
        let english = try locale("en")
        let real = realNames(english, "person.last_name.generic")
        var faker = Faker(seed: 3, locale: english, novelNames: true)
        for _ in 0..<3_000 {
            let name = faker.person.lastName()
            for part in name.split(separator: "-").map(String.init) {
                #expect(!real.contains(part), "'\(part)' of '\(name)' is a real surname")
            }
        }
    }

    /// A locale whose models were refused must still produce names rather than nothing.
    @Test("a locale with no model falls back rather than failing")
    func fallsBackWhereRefused() throws {
        // Japanese given names are two characters, so a character n-gram cannot
        // generalise and the trainer refuses to ship one. The mode must degrade to the
        // list, not to an empty string.
        var faker = Faker(seed: 1, locale: try locale("ja"), novelNames: true)
        for _ in 0..<200 {
            #expect(!faker.person.firstName().isEmpty)
            #expect(!faker.person.lastName().isEmpty)
        }
    }

    @Test("the mode carries through a Forge to every row")
    func throughAForge() throws {
        let english = try locale("en")
        let real = realNames(english, "person.last_name.generic")
        let people = Forge<Person>("person") { Person() }
            .locale(english)
            .novelNames()
            .rule(\.first) { $0.person.firstName() }
            .rule(\.last) { $0.person.lastName() }
            .generate(2_000, seed: 1337)

        #expect(people.count == 2_000)
        #expect(people.allSatisfy { !$0.last.isEmpty && !$0.first.isEmpty })
        #expect(
            people.allSatisfy { !real.contains($0.last) },
            "a real surname reached a row generated with the mode on"
        )
    }

    @Test("the mode does not disturb reproducibility")
    func stillReproducible() throws {
        let english = try locale("en")
        var a = Faker(seed: 77, locale: english, novelNames: true)
        var b = Faker(seed: 77, locale: english, novelNames: true)
        let first = (0..<100).map { _ in "\(a.person.firstName()) \(a.person.lastName())" }
        let second = (0..<100).map { _ in "\(b.person.firstName()) \(b.person.lastName())" }
        #expect(first == second)
    }

    /// Turning it on has to actually change something, or the tests above pass vacuously.
    @Test("the mode changes what is produced")
    func modeIsNotVacuous() throws {
        let english = try locale("en")
        var off = Faker(seed: 42, locale: english)
        var on = Faker(seed: 42, locale: english, novelNames: true)
        let plain = (0..<50).map { _ in off.person.lastName() }
        let novel = (0..<50).map { _ in on.person.lastName() }
        #expect(plain != novel)
    }
}
