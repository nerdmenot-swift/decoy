import Testing

@testable import Decoy
@testable import DecoyLocaleEN

/// The convenience path, for callers who want plausible data and do not care whether
/// they can produce it again.
///
/// The risk in offering it is that somebody generates something surprising — a name that
/// breaks a layout, a row that trips a validator — and has no way to show it to anybody
/// else. So the seed is always recoverable, and these tests pin that as hard as they pin
/// the randomness itself.
@Suite("Unseeded generation")
struct UnseededTests {

    @Test("a faker made without a seed still knows the one it got")
    func seedIsRecoverable() {
        var faker = Faker(locale: DecoyLocaleEN.locale)
        let captured = faker.seed
        let produced = (0..<5).map { _ in faker.person.fullName() }

        // The whole point: hand the captured seed back and the run returns.
        var again = Faker(seed: captured, locale: DecoyLocaleEN.locale)
        #expect((0..<5).map { _ in again.person.fullName() } == produced)
    }

    @Test("two unseeded fakers do not agree")
    func unseededDiffer() {
        // The default argument is evaluated per call, so each faker draws its own seed.
        // If it were evaluated once, every unseeded faker in a process would be identical
        // — which would look like it worked right up until someone needed variety.
        let seeds = Set((0..<32).map { _ in Faker(locale: DecoyLocaleEN.locale).seed })
        #expect(seeds.count == 32)
    }

    @Test("an explicit seed still wins")
    func explicitSeedHonoured() {
        var a = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        var b = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        #expect(a.seed == 1337)
        #expect(a.person.fullName() == b.person.fullName())
    }

    @Test("forges generate without a seed, and differ when they do")
    func forgeUnseeded() {
        struct Row { var name = "" }
        let forge = Forge<Row>("Row") { Row() }
            .rule(\.name) { $0.person.fullName() }
            .locale(DecoyLocaleEN.locale)

        #expect(forge.generate(3).count == 3)
        #expect(forge.one().name.isEmpty == false)
        #expect(Array(forge.stream().prefix(4)).count == 4)

        // Across enough runs, unseeded output must vary. Comparing two runs alone would
        // flake once in however many distinct first names the corpus holds.
        let firsts = Set((0..<16).map { _ in forge.generate(1)[0].name })
        #expect(firsts.count > 1)
    }

    @Test("a captured seed reproduces a whole forge run")
    func forgeSeedRoundTrip() {
        struct Row { var name = ""; var city = "" }
        let forge = Forge<Row>("Row") { Row() }
            .rule(\.name) { $0.person.fullName() }
            .rule(\.city) { $0.location.city() }
            .locale(DecoyLocaleEN.locale)

        let seed = Decoy.randomSeed()
        let first = forge.generate(20, seed: seed)
        let second = forge.generate(20, seed: seed)
        #expect(first.map(\.name) == second.map(\.name))
        #expect(first.map(\.city) == second.map(\.city))
    }

    @Test("randomSeed spreads across the range")
    func randomSeedSpread() {
        // A generator that only ever returned small values would still pass the tests
        // above while quietly shrinking the space every unseeded run draws from.
        let seeds = (0..<200).map { _ in Decoy.randomSeed() }
        #expect(Set(seeds).count == 200)
        #expect(seeds.contains { $0 > UInt64.max / 2 })
        #expect(seeds.contains { $0 < UInt64.max / 2 })
    }
}
