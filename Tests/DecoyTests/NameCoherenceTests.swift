import Foundation
import Testing

@testable import Decoy
@testable import DecoyLocales

/// A composed name must come from one language, in both directions.
///
/// `fullName()` narrows the chain to a locale that can supply the whole name rather than
/// assembling one from wherever each part happens to live. Both halves of that have been
/// wrong at different times, and each produced a value that looks fine until somebody who
/// speaks the language sees it.
@Suite("Name coherence")
struct NameCoherenceTests {

    /// The ways a locale can supply a whole name out of its own data.
    ///
    /// Mirrors `fullName()`. A locale qualifies by carrying a surname plus given names in
    /// any one of three shapes: both genders, a single ungendered list, or one gender.
    static let coherentGroups = [
        ["person.first_name.female", "person.first_name.male", "person.last_name.generic"],
        ["person.first_name.generic", "person.last_name.generic"],
        ["person.first_name.male", "person.last_name.generic"],
        ["person.first_name.female", "person.last_name.generic"],
    ]

    private func faker(_ code: String, seed: UInt64 = 1337) throws -> Faker {
        Faker(seed: seed, locale: try DecoyLocales.locale(code))
    }

    /// A composed name is entirely the locale's own, or entirely the fallback's. Never both.
    ///
    /// The two categories used to be hand-written lists — `ko`, `es`, `bn_BD`, `cy`, `mk`
    /// had given names and no surnames; `zh_TW`, `id_ID`, `yo_NG` the reverse. Every one of
    /// those has since been filled, so the lists described a corpus that no longer existed
    /// and the test went on asserting that `mk` *should* answer in English. Derived from
    /// the corpus now, so it cannot outlive what it describes.
    ///
    /// Both directions are checked, which is what stops this being a restatement of the
    /// implementation: a locale that can supply its own name must actually produce one
    /// different from English, and a locale that cannot must produce English *exactly* —
    /// any mixture fails both halves.
    @Test("a full name never mixes a native part with a fallback one")
    func noChimeras() throws {
        var ownNames = 0, fallsBack = 0

        for code in DecoyLocales.available where code != "base" {
            // An `en_*` locale borrowing English surnames is not a chimera; it is English.
            // That exemption is in `fullName()` for the same reason.
            guard code.split(separator: "_").first.map(String.init) != "en" else { continue }

            let locale = try DecoyLocales.locale(code)
            let narrowed = locale.agreeing(onAnyOf: Self.coherentGroups)

            // *Which language* supplies the name, not whether the chain narrowed at all.
            // `de_AT` narrows to `de` and is answered in German — its own language, by
            // inheritance — so counting positions read that as a fallback and demanded it
            // produce English. The question is only ever whether the supplier speaks the
            // same language as the locale asking.
            let codes = DecoyLocales.chain(for: code)
            let supplier = codes[locale.chain.count - narrowed.chain.count]
            let language = { (c: String) in c.split(separator: "_").first.map(String.init) }
            let suppliesItsOwn = language(supplier) == language(code)

            // Compared against English itself, not against this locale narrowed by the
            // same rule the implementation uses — that returns the locale unchanged
            // whenever it *can* supply a name, so "native" and "fallback" came out equal
            // by construction and the comparison asserted nothing.
            var native = try faker(code)
            var english = try faker("en")

            let composed = (0..<5).map { _ in native.person.fullName() }
            let fallback = (0..<5).map { _ in english.person.fullName() }

            if suppliesItsOwn {
                ownNames += 1
                #expect(
                    composed != fallback,
                    "\(code) can supply its own full name but produced the fallback's")
            } else {
                fallsBack += 1
                #expect(
                    composed == fallback,
                    """
                    \(code) cannot supply a whole name, so every part must come from the \
                    fallback — a mixture is the chimera this exists to catch
                    """)
            }
        }

        // Not an assertion about the data, an assertion about the test: if the corpus ever
        // stopped reaching either branch this would pass by exercising nothing.
        #expect(ownNames > 0, "no locale supplied its own name — the positive half ran on nothing")
        print("name coherence: \(ownNames) locales supply their own, \(fallsBack) fall back")
    }

    /// The parts are still native when asked for individually.
    ///
    /// The narrowing is about the *composition*. Somebody asking only for a surname is not
    /// building anything self-contradictory, and losing the native value there would be a
    /// worse trade than the one this makes.
    @Test("the individual generators still return the locale's own values")
    func partsStayNative() throws {
        var korean = try faker("ko")
        let given = (0..<20).map { _ in korean.person.firstName() }
        #expect(
            given.contains { $0.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) } },
            "ko.firstName() should still draw Hangul")

        var taiwanese = try faker("zh_TW")
        let surnames = (0..<20).map { _ in taiwanese.person.lastName() }
        #expect(
            surnames.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } },
            "zh_TW.lastName() should still draw Han")
    }

    /// English regional locales are the exception, and the reason this is not a blanket rule.
    ///
    /// `en_GB` has its own given names from the ONS and no surnames of its own. Borrowing
    /// English surnames is not a chimera, because it is English — so requiring both from
    /// one corpus would have thrown away real data to fix a problem it does not have.
    @Test("an English regional locale keeps its own given names")
    func englishRegionalKeepsItsOwn() throws {
        var british = try faker("en_GB")
        var american = try faker("en")
        let uk = (0..<8).map { _ in british.person.fullName() }
        let us = (0..<8).map { _ in american.person.fullName() }
        #expect(uk != us, "en_GB should not collapse to en — it has its own given names")
    }
}
