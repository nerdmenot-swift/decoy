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
                "46 Crosslin Turnpike",
                "Tokelau",
                "Wise LLC",
                "rogers.watts@example.net",
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/195.0.0.0 Safari/537.36",
                "Unbranded Ceramic Keyboard",
                "GB67GQTS40759958091748",
                "4822294168607",
                "cupola",
                "Cespes acervatim nimirum lanx caupo ideo confectio.",
                "silver",
                "G2HTSCH0ZFMSECJ1U",
                "gramen-minute.nsc",
                "0xba2ff23e15a7c02c3df7b42682b218815396c08a",
                "019b76da-a800-7344-9158-d44f1b73b3a1",
            ]
        )
    }

    @Test("German output at seed 1337 is unchanged")
    func german() {
        #expect(
            Self.sample(DecoyLocaleDE.locale) == [
                "Kim",
                "Rummel",
                "Dr. Kim Drangmeister",
                "Erlenmoos",
                "Im Jücherfeld 10b",
                "Mayotte",
                "Biber-Happe",
                "jamie.warnatz@example.net",
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36",
                "Ergonomic Wooden Chair",
                "GB66MGQT74075995809174",
                "3528-1822-2941-6865",
                "blueprint",
                "Frutex cespes acervatim nimirum.",
                "Neonblau",
                "HVL2G2HTSCH0ZFMSE",
                "affinitas-civis.cml",
                "0x8a93ba2ff23e15a7c02c3df7b42682b218815396",
                "019b76da-a800-772a-81ed-c23f73154c93",
            ]
        )
    }

    @Test("Japanese output at seed 1337 is unchanged")
    func japanese() {
        #expect(
            Self.sample(DecoyLocaleJA.locale) == [
                "葵",
                "立松",
                "沓脱葵",
                "Iwai",
                "9丁目5番7号",
                "チリ",
                "株式会社西堀保険",
                "user479.user938@example.net",
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36",
                "Ergonomic Wooden Chair",
                "GB66MGQT74075995809174",
                "3528-1822-2941-6865",
                "コンサルテーション",
                "Frutex cespes acervatim nimirum.",
                "若草色",
                "HVL2G2HTSCH0ZFMSE",
                "affinitas-civis.cml",
                "0x8a93ba2ff23e15a7c02c3df7b42682b218815396",
                "019b76da-a800-772a-81ed-c23f73154c93",
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
