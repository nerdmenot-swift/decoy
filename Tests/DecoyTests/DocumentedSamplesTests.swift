import Decoy
import DecoyLocaleDE
import DecoyLocaleEN
import DecoyLocaleJA
import Testing

/// Every sample value printed in the hand-written documentation, asserted.
///
/// The generated reference pages cannot go stale — `website/scripts/extract.ts` derives
/// them by calling the library, and CI diffs the result. The hand-written pages had no
/// such protection, and `ReadmeExampleTests` only checks that the README's snippets
/// *compile*, which a wrong comment survives happily.
///
/// So four of fifteen published values were wrong, in two distinct ways:
///
/// - Three had drifted. `de.commerce.productName()` said "Praktische Sofas aus Leder" and
///   the corpus had moved under it. That is the ordinary kind, and this suite is the
///   answer to it.
/// - One was never right. install.md claimed `company.name()` returns "Crosslin inc." as
///   the *second* draw, a value that belongs to the *third* draw of a different snippet.
///   A faker is a stream, so the same call at a different position gives a different
///   answer — which quick-start.md explains, two paragraphs below the page that got it
///   wrong. Copying a line between examples is exactly how that mistake is made.
///
/// Each test names the file it is quoting. When one fails, the fix is to run the snippet,
/// put the real value in the documentation and put it here — in that order, so the docs
/// are corrected from output rather than from a guess.
@Suite("Documented samples")
struct DocumentedSamplesTests {

    /// `website/src/content/docs/start/quick-start.md` — "A faker is a stream".
    ///
    /// The page promises these five strings in this order on any machine, on any day. The
    /// order is the assertion: drawing them in another order gives other values, and a
    /// suite that checked them individually against fresh fakers would pass while the
    /// documented sequence was wrong.
    @Test("quick-start's five-string stream")
    func stream() {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        #expect(faker.person.fullName() == "Riley Bonneau")
        #expect(faker.location.streetAddress() == "12289 Seaman Divide")
        #expect(faker.company.name() == "Crosslin inc.")
        #expect(faker.internet.email() == "david.paul@example.net")
        #expect(faker.person.jobTitle() == "Implemented frame Designer")
    }

    /// `website/src/content/docs/start/install.md` — the first snippet anybody runs.
    ///
    /// Two draws, not five. `company.name()` is the second call here and the third call in
    /// quick-start, and the two values differ for that reason alone.
    @Test("install's first snippet")
    func install() {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        #expect(faker.person.fullName() == "Riley Bonneau")
        #expect(faker.company.name() == "Foote COOP")
    }

    /// `website/src/content/docs/start/quick-start.md` — "The same seed, twice".
    @Test("the same seed gives the same name")
    func sameSeed() {
        var a = Faker(seed: 42, locale: DecoyLocaleEN.locale)
        var b = Faker(seed: 42, locale: DecoyLocaleEN.locale)
        #expect(a.person.fullName() == "Penny Syverson")
        #expect(b.person.fullName() == "Penny Syverson")
    }

    /// `website/src/content/docs/start/quick-start.md` — "Another language".
    ///
    /// The page's claim is about shape, not vocabulary: a German address puts the number
    /// after the street. That is what makes the address line worth pinning.
    @Test("German at seed 2024")
    func german() {
        var de = Faker(seed: 2024, locale: DecoyLocaleDE.locale)
        #expect(de.person.fullName() == "Benning Blaha")
        #expect(de.location.streetAddress() == "Grubergasse 17")
        #expect(de.commerce.productName() == "Leichte Hemden aus Seide")
        #expect(de.finance.accountType() == "Sparkonto")
    }

    /// `website/src/content/docs/start/quick-start.md` — "Another language", second half.
    @Test("Japanese at seed 2024")
    func japanese() {
        var ja = Faker(seed: 2024, locale: DecoyLocaleJA.locale)
        #expect(ja.person.fullName() == "竹川しゅうこ")
        #expect(ja.company.name() == "十文字製薬合名会社")
    }
}
