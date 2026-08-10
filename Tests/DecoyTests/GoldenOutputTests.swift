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
                "Felix",
                "Bonneau",
                "Michael Sullivan",
                "Sleepy Hollow",
                "6109 David Key",
                "India",
                "Conlan LC",
                "vincent.ashley@example.com",
                "Mozilla/5.0 (Linux; Android 11; SM-G994B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36",
                "Recycled Linen Ball",
                "GB37TNYX58091748118222",
                "3529-1686-0252-0661",
                "demurrage",
                "Confectio pestis bidens plurifariam capax femen dictio.",
                "black",
                "H0ZFMSECJ1UUZWGZZ",
                "aviditas-turbedo.viv",
                "0x3e15a7c02c3df7b42682b218815396c08aa5e497",
                "019b76da-a800-7e1b-8199-e6853d0b58fe",
            ]
        )
    }

    @Test("German output at seed 1337 is unchanged")
    func german() {
        #expect(
            Self.sample(DecoyLocaleDE.locale) == [
                "Ruediger",
                "Warburg",
                "Brechtold Claußen",
                "Sonnenberg",
                "Bramsonstraße 881",
                "Ungarn",
                "Siemer, Goebel und Kostner",
                "jochen.wode@example.com",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/177.0",
                "Ergonomische Mützen aus Beton",
                "GB54YXOW09174811822294",
                "5560-2520-6625-3715",
                "sconce",
                "Femen dictio algens cassis.",
                "Türkisblau",
                "ZFMSECJ1UUZWGZZG8",
                "vetustas-apprime.clkp",
                "0x15a7c02c3df7b42682b218815396c08aa5e4979c",
                "019b76da-a800-7d2c-a5fe-a32e6e9a0e93",
            ]
        )
    }

    @Test("Japanese output at seed 1337 is unchanged")
    func japanese() {
        #expect(
            Self.sample(DecoyLocaleJA.locale) == [
                "昌利",
                "錦織",
                "三辺なおか",
                "Togoshi",
                "7丁目2番1号",
                "マヨット",
                "丸野情報合資会社",
                "user938.user610@example.org",
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
                "Intelligent Cotton Pants",
                "GB16TSMB75995809174811",
                "3528-2294-1686-0254",
                "三半期",
                "Nimirum lanx caupo.",
                "ラベンダー色",
                "L2G2HTSCH0ZFMSECJ",
                "paululum-flagrans.osf",
                "0x93ba2ff23e15a7c02c3df7b42682b218815396c0",
                "019b76da-a800-783c-ab24-f4688481d57a",
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
