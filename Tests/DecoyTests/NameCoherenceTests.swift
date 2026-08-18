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

    /// Locales with their own given names and no surnames of their own.
    ///
    /// These produced the mirror-image chimera: the chain narrowed to the locale because
    /// it had given names, found no surname there, walked on to English, and returned
    /// `Rivard혁진` — a Census surname welded to a Korean given name.
    static let givenNamesOnly = ["ko", "es", "bn_BD", "cy", "mk"]

    /// Locales with their own surnames and no given names of their own.
    static let surnamesOnly = ["zh_TW", "id_ID", "yo_NG"]

    private func faker(_ code: String, seed: UInt64 = 1337) throws -> Faker {
        Faker(seed: seed, locale: try DecoyLocales.locale(code))
    }

    /// A composed name never mixes two languages, whichever half is missing.
    @Test("a full name never mixes a native part with a fallback one")
    func noChimeras() throws {
        for code in Self.givenNamesOnly + Self.surnamesOnly {
            var native = try faker(code)
            var english = try faker(code)
            english.locale = english.locale.agreeing(
                onAnyOf: [["person.first_name.female", "person.first_name.male",
                           "person.last_name.generic"]])

            // The whole name comes from the fallback, so it equals what the fallback alone
            // would produce. A mixed name could not satisfy this.
            let composed = (0..<5).map { _ in native.person.fullName() }
            let fallback = (0..<5).map { _ in english.person.fullName() }
            #expect(composed == fallback, "\(code) composed a name from two languages")
        }
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
