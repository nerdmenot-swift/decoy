import Foundation
import Testing

@testable import DecoyCorpusKit

/// Tests for the gate that stops the corpus quietly losing data.
///
/// Worth testing precisely because the thing it guards is invisible: the corpus is a
/// build artifact nobody diffs, so an adapter that stops emitting leaves every other test
/// passing.
@Suite("Coverage gate")
struct CoverageGateTests {

    private let baseline = CoverageBaseline(locales: ["en": 100, "de": 50, "ja": 40])

    @Test("an unchanged corpus passes")
    func unchanged() {
        let result = compareCoverage(
            measured: ["en": 100, "de": 50, "ja": 40], against: baseline)
        #expect(result.passes)
        #expect(result.regressions.isEmpty)
        #expect(result.improved.isEmpty)
    }

    @Test("a locale losing paths fails, and says by how much")
    func regression() {
        let result = compareCoverage(
            measured: ["en": 100, "de": 30, "ja": 40], against: baseline)

        #expect(!result.passes)
        #expect(result.regressions.count == 1)
        #expect(result.regressions.first?.locale == "de")
        #expect(result.regressions.first?.expected == 50)
        #expect(result.regressions.first?.actual == 30)
    }

    @Test("growth passes and is reported, rather than demanding a baseline update")
    func growth() {
        // An improvement must not require an extra commit to make CI green again, or
        // the gate becomes something people route around.
        let result = compareCoverage(
            measured: ["en": 140, "de": 50, "ja": 40], against: baseline)

        #expect(result.passes)
        #expect(result.improved == ["en"])
    }

    @Test("a locale vanishing entirely fails")
    func vanished() {
        // The loudest version of the thing being guarded against, and one a per-locale
        // comparison would otherwise skip over silently.
        let result = compareCoverage(measured: ["en": 100, "de": 50], against: baseline)

        #expect(!result.passes)
        #expect(result.missing == ["ja"])
        #expect(result.regressions.isEmpty, "vanishing is not a regression, it is its own case")
    }

    @Test("a new locale is reported but never fatal")
    func unlisted() {
        let result = compareCoverage(
            measured: ["en": 100, "de": 50, "ja": 40, "fr": 25], against: baseline)

        #expect(result.passes, "adding a locale must not fail the build that added it")
        #expect(result.unlisted == ["fr"])
    }

    @Test("regressions and disappearances are reported together, not one at a time")
    func multipleFailures() {
        // Reporting only the first would mean one CI run per problem.
        let result = compareCoverage(measured: ["en": 10], against: baseline)

        #expect(result.regressions.map(\.locale) == ["en"])
        #expect(result.missing == ["de", "ja"])
    }

    @Test("the baseline round-trips through JSON")
    func roundTrip() throws {
        let encoded = try JSONEncoder().encode(baseline)
        #expect(try JSONDecoder().decode(CoverageBaseline.self, from: encoded) == baseline)
    }
}
