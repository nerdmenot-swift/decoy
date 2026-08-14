import Testing

@testable import DecoyAdapterKit

/// The places the civil-name registers make Swift and JavaScript disagree.
///
/// `CivilNamesTests` checks what the compiled corpus holds; this checks the reader that
/// produced it. The parity suite covers the adapter end to end, but only where an artifact
/// cache exists — these run anywhere, and they are the cases that would otherwise be caught
/// by nothing, because each produces plausible output rather than an error.
@Suite("Civil names adapter")
struct CivilNamesAdapterTests {

    // MARK: - Casing

    @Test("Turkic i keeps its dot through a round trip")
    func turkicCasing() {
        // The register spells it İbrahim already. Lower-casing under `az` has to give a
        // dotless `i` so that upper-casing it gives the dot back — the default mapping
        // produces `i` plus a combining dot above, and re-capitalising that leaves the mark
        // stranded on a capital I.
        #expect(CivilNamesAdapter.titleCase("İbrahim", locale: "az") == "İbrahim")
        #expect(CivilNamesAdapter.titleCase("İBRAHİM", locale: "az") == "İbrahim")
        #expect(Array("İbrahim".unicodeScalars.prefix(2)) == ["\u{0130}", "b"])

        // Dotless: `ABBASALI` is Abbasalı, not Abbasali.
        #expect(CivilNamesAdapter.titleCase("ABBASALI", locale: "az") == "Abbasalı")
        #expect(CivilNamesAdapter.titleCase("ABBASALI", locale: "fr") == "Abbasali")

        // The same input under a non-Turkic locale takes the default mapping, which is the
        // behaviour every other register wants.
        #expect(CivilNamesAdapter.titleCase("İBRAHİM", locale: "tr") == "İbrahim")

        // A dotted capital written in two pieces lowercases with the dot absorbed, and the
        // bare `I` later in the same word does not — `İbrahım`, dotted then dotless, which
        // is the pair of rules working against each other in one word.
        #expect(CivilNamesAdapter.titleCase("I\u{0307}BRAHIM", locale: "az") == "İbrahım")
    }

    @Test("a boundary is a hyphen, an apostrophe or a space")
    func boundaries() {
        #expect(CivilNamesAdapter.titleCase("JEAN-PIERRE", locale: "fr") == "Jean-Pierre")
        #expect(CivilNamesAdapter.titleCase("MARIE THÉRÈSE", locale: "fr") == "Marie Thérèse")
        #expect(CivilNamesAdapter.titleCase("N'GUESSAN", locale: "fr") == "N'Guessan")
        // Nothing else counts: a full stop is not a boundary, so `St.john` stays as it is
        // rather than becoming `St.John`.
        #expect(CivilNamesAdapter.titleCase("ST.JOHN", locale: "en") == "St.john")
    }

    // MARK: - Number

    @Test("Number trims the carriage return every one of these files ends a row with")
    func numbers() {
        #expect(CivilNamesAdapter.number("2618994\r") == 2_618_994)
        #expect(CivilNamesAdapter.number("") == 0)
        // The CBS withholds a value as `..` and the ONS redacts a count of one or two as
        // `[x]`. Both have to read as absent rather than as zero-with-a-warning.
        #expect(CivilNamesAdapter.number("..") == nil)
        #expect(CivilNamesAdapter.number("[x]") == nil)
    }

    @Test("a feminine surname marker is dropped, an unclosed bracket is not")
    func parentheticals() {
        #expect(CivilNamesAdapter.withoutParentheticals("Abbasov (a)") == "Abbasov ")
        #expect(CivilNamesAdapter.withoutParentheticals("Abbasov (a") == "Abbasov (a")
        #expect(CivilNamesAdapter.withoutParentheticals("A (b) c (d)") == "A  c ")
    }

    // MARK: - Keys

    @Test("canonically equivalent spellings stay apart")
    func codeUnitKeys() {
        // Taiwan's surname register holds both, and they are not the same name: 25 people
        // are recorded under the compatibility ideograph and 282,185 under the ordinary
        // one. Summing them puts the compatibility spelling's bearers over the threshold
        // that should have dropped them.
        let ordinary = "\u{5468}"
        let compatibility = "\u{2F83F}"
        #expect(ordinary == compatibility, "Swift compares these equal — that is the hazard")
        #expect(CodeUnitOrder.key(ordinary) != CodeUnitOrder.key(compatibility))

        var totals: [[UInt16]: Int] = [:]
        totals[CodeUnitOrder.key(ordinary), default: 0] += 282_185
        totals[CodeUnitOrder.key(compatibility), default: 0] += 25
        #expect(totals.count == 2)
    }
}
