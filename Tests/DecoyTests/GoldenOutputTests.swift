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
                "Rivard",
                "Dr. Charity Foote",
                "West Daniellafield",
                "6109 W 7th Street",
                "Canada",
                "Wise Inc",
                "rogers.conlan@example.net",
                "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_15_7) AppleWebKit/575.94.51 (KHTML, like Gecko) Chrome/69.9.3.15 Safari/552.64.75",
                "Intelligent Aluminum Shirt",
                "GB67NYXO80917481182229",
                "3468-602520-66253",
                "feria",
                "Autem terebro bonus dolore defluo agnosco candidus succedo sopor.",
                "gold",
                "MSECJ1UUZWGZZG89E",
                "bestia-verumtamen.opf",
                "0xa7c02c3df7b42682b218815396c08aa5e4979c1e",
                "019b76da-a800-790f-87ed-5f11cef5272e",
            ]
        )
    }

    @Test("German output at seed 1337 is unchanged")
    func german() {
        #expect(
            Self.sample(DecoyLocaleDE.locale) == [
                "Kim",
                "Schäfer",
                "Nikita Engel",
                "Burkhardtdorf",
                "Ulmenweg 6",
                "Chile",
                "Zapletal UG",
                "luka.dittmer@example.net",
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/554.84.93 (KHTML, like Gecko) Version/16.1 Safari/562.58.56",
                "Intelligent Bronze Tuna",
                "GB23EMGQ77407599580917",
                "3711-822294-16869",
                "Bewusstsein",
                "Deleniti numquam perferendis rerum.",
                "Neonblau",
                "HVL2G2HTSCH0ZFMSE",
                "illo-tempora.cml",
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
                "若林",
                "長尾 葵",
                "北奥村市",
                "5丁目7番2号",
                "アルバニア",
                "越智, 角田 and 吉井",
                "user479.user860@example.org",
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/108.0",
                "Intelligent Bronze Tuna",
                "GB23EMGQ77407599580917",
                "3711-822294-16869",
                "コンサルテーション",
                "約 難しい まぎらす 待遇.",
                "若草色",
                "HVL2G2HTSCH0ZFMSE",
                "word342-word566.osf",
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
