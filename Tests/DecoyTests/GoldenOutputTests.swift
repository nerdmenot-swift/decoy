import Testing

@testable import Decoy
@testable import DecoyLocaleDE
@testable import DecoyLocaleEN
@testable import DecoyLocaleJA

/// Pins what a fixed seed actually produces, per shipped locale.
///
/// The README's first promise is that the same seed gives the same rows, and nothing
/// tested it. `SeededRandomTests` pins the RNG to literal values, but the RNG is only
/// the bottom of the stack: which corpus path a generator reads, the order draws happen
/// in, how the weighted algorithm consumes randomness, how a template resolves its
/// tokens — all of it could change without a single test failing, silently rewriting
/// every fixture anybody has committed against a pinned corpus version.
///
/// So these are literals. A diff here is not a bug report, it is the corpus version
/// needing a major bump — and the point is that it cannot happen quietly. Regenerate
/// deliberately, never to turn a red test green.
///
/// Writing them was worth it immediately: the first dump showed a Japanese card number
/// reading `30[0-5]8-118222-9415` and every Japanese email reading exactly
/// `user.user@example.com`. Both had shipped for months.
@Suite(
    "Golden output",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct GoldenOutputTests {

    /// One draw per namespace, chosen to exercise different paths through the stack: a
    /// plain table, a weighted table, a composite row, a template, and a pure algorithm
    /// that touches no corpus at all.
    static func sample(_ locale: LocaleCorpus) -> [String] {
        var f = Faker(seed: 1337, locale: locale)
        return [
            f.person.firstName(),
            f.person.lastName(),
            f.person.fullName(),
            f.location.city(),
            f.location.streetAddress(),
            f.location.country(),
            f.company.name(),
            f.internet.email(),
            f.internet.userAgent(),
            f.commerce.productName(),
            f.finance.iban(),
            f.finance.creditCardNumber(),
            f.word.noun(),
            f.lorem.sentence(),
            f.color.human(),
            f.vehicle.vin(),
            f.system.fileName(),
            f.crypto.ethereumAddress(),
            f.uuidV7(),
        ]
    }

    @Test("English output at seed 1337 is unchanged")
    func english() {
        #expect(
            Self.sample(DecoyLocaleEN.locale) == [
                "Manuela",
                "Raber",
                "Dr. Lurline Fernandez",
                "Duchesne",
                "461 Yasmine Turnpike",
                "Tokelau",
                "Wise - Vanhouten",
                "toy.angel@example.net",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/603.15.49 (KHTML, like Gecko) Version/12_3 Mobile/15E148 Safari/589.72",
                "Bespoke Silk Knife",
                "GB54YXOW09174811822294",
                "5560-2520-6625-3715",
                "sconce",
                "Femen dictio algens cassis.",
                "salmon",
                "ZFMSECJ1UUZWGZZG8",
                "vetustas-apprime.clkp",
                "0x15a7c02c3df7b42682b218815396c08aa5e4979c",
                "019b76da-a800-7d2c-a5fe-a32e6e9a0e93",
            ]
        )
    }

    @Test("German output at seed 1337 is unchanged")
    func german() {
        #expect(
            Self.sample(DecoyLocaleDE.locale) == [
                "Kim",
                "Schlitzer",
                "Dr. Kim Grasse",
                "Erlenmoos",
                "Im Jücherfeld 10b",
                "Mayotte",
                "Dittmer-Kick",
                "jamie.viellehner@example.net",
                "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_15_7) AppleWebKit/575.94.51 (KHTML, like Gecko) Chrome/69.9.3.15 Safari/552.64.75",
                "Intelligent Bamboo Sausages",
                "GB67NYXO80917481182229",
                "3468-602520-66253",
                "feria",
                "Bidens plurifariam capax femen dictio algens cassis novale mel.",
                "Dunkelbraun",
                "MSECJ1UUZWGZZG89E",
                "callis-supter.opf",
                "0xa7c02c3df7b42682b218815396c08aa5e4979c1e",
                "019b76da-a800-790f-87ed-5f11cef5272e",
            ]
        )
    }

    @Test("Japanese output at seed 1337 is unchanged")
    func japanese() {
        #expect(
            Self.sample(DecoyLocaleJA.locale) == [
                "葵",
                "竹下",
                "浅野葵",
                "Iwai",
                "9丁目5番7号",
                "チリ",
                "株式会社角田保険",
                "user479.user938@example.net",
                "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_15_7) AppleWebKit/575.94.51 (KHTML, like Gecko) Chrome/69.9.3.15 Safari/552.64.75",
                "Intelligent Bamboo Sausages",
                "GB67NYXO80917481182229",
                "3468-602520-66253",
                "働き",
                "Bidens plurifariam capax femen dictio algens cassis novale mel.",
                "マゼンタ",
                "MSECJ1UUZWGZZG89E",
                "callis-supter.opf",
                "0xa7c02c3df7b42682b218815396c08aa5e4979c1e",
                "019b76da-a800-790f-87ed-5f11cef5272e",
            ]
        )
    }

    /// The same seed, twice, in one process — separate from the literals above.
    ///
    /// If the literals ever go stale this still holds, so a corpus change shows up as
    /// exactly one failing assertion rather than as reproducibility looking broken.
    @Test("the same seed twice gives the same values")
    func repeatable() {
        #expect(Self.sample(DecoyLocaleEN.locale) == Self.sample(DecoyLocaleEN.locale))
    }

    /// A different seed has to give different values, or the pins above prove nothing.
    @Test("a different seed gives different values")
    func seedMatters() {
        var other = Faker(seed: 7331, locale: DecoyLocaleEN.locale)
        let sample = Self.sample(DecoyLocaleEN.locale)
        let alternative = [
            other.person.firstName(), other.person.lastName(), other.person.fullName(),
        ]
        #expect(Array(sample.prefix(3)) != alternative)
    }
}
