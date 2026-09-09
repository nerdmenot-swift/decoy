import Testing

@testable import Decoy

/// `DecoyFaker` exists so a file can import Decoy alongside another module that also
/// exports a `Faker`.
///
/// Swift resolves a bare type reference across every imported module at once, so two
/// `Faker`s in scope make `func takes(_ f: Faker)` fail with "'Faker' is ambiguous for type
/// lookup". The usual fix — qualify with the module, `Decoy.Faker` — does not work here,
/// because this module also declares `enum Decoy` and a type shadows its module in that
/// position: the compiler looks inside the enum and reports "'Faker' is not a member type
/// of enum 'Decoy.Decoy'". Swift has no import aliasing either.
///
/// Verified against a real second module that exports its own `Faker`: the ambiguity
/// reproduces, `Decoy.Faker` fails, and this alias resolves it.
@Suite("Type aliases")
struct TypeAliasTests {

    @Test("DecoyFaker is Faker, not a wrapper around it")
    func aliasIsTheSameType() {
        #expect(DecoyFaker.self == Faker.self)
    }

    /// The alias has to be usable exactly where the type is, or it solves nothing.
    @Test("the alias generates the same values as the type")
    func aliasGeneratesIdentically() {
        var viaAlias = DecoyFaker(seed: 1337, locale: .builtIn)
        var viaType = Faker(seed: 1337, locale: .builtIn)
        #expect(viaAlias.person.firstName() == viaType.person.firstName())
        #expect(viaAlias.internet.domainSuffix() == viaType.internet.domainSuffix())
    }
}
