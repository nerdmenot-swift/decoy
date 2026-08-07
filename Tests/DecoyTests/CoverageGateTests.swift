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

    /// Shorthand: `at(100, 5_000)` reads better in a table of cases than the initialiser.
    private func at(_ paths: Int, _ values: Int) -> LocaleCoverage {
        LocaleCoverage(paths: paths, values: values)
    }

    private var baseline: CoverageBaseline {
        CoverageBaseline(locales: ["en": at(100, 5_000), "de": at(50, 2_000), "ja": at(40, 1_500)])
    }

    @Test("an unchanged corpus passes")
    func unchanged() {
        let result = compareCoverage(
            measured: ["en": at(100, 5_000), "de": at(50, 2_000), "ja": at(40, 1_500)],
            against: baseline)
        #expect(result.passes)
        #expect(result.regressions.isEmpty)
        #expect(result.improved.isEmpty)
    }

    @Test("a locale losing paths fails, and says by how much")
    func regression() {
        let result = compareCoverage(
            measured: ["en": at(100, 5_000), "de": at(30, 2_000), "ja": at(40, 1_500)],
            against: baseline)

        #expect(!result.passes)
        #expect(result.regressions.count == 1)
        #expect(result.regressions.first?.locale == "de")
        #expect(result.regressions.first?.dimension == .paths)
        #expect(result.regressions.first?.expected == 50)
        #expect(result.regressions.first?.actual == 30)
    }

    /// The gap the path count alone left open.
    ///
    /// `us-surnames` fills one path with 24,889 values. An adapter returning three keeps
    /// the path and loses the data, and a path-only gate reports the corpus as unchanged
    /// — while CI describes it as catching a locale "carrying less of its own data".
    @Test("a locale keeping its paths but losing its values fails")
    func hollowedOut() {
        let result = compareCoverage(
            measured: ["en": at(100, 12), "de": at(50, 2_000), "ja": at(40, 1_500)],
            against: baseline)

        #expect(!result.passes)
        #expect(result.regressions.count == 1)
        #expect(result.regressions.first?.dimension == .values)
        #expect(result.regressions.first?.actual == 12)
    }

    /// Both dimensions, reported separately rather than collapsed into one complaint.
    @Test("losing paths and values reports each")
    func bothDimensions() {
        let result = compareCoverage(
            measured: ["en": at(4, 12), "de": at(50, 2_000), "ja": at(40, 1_500)],
            against: baseline)

        #expect(result.regressions.map(\.dimension) == [.paths, .values])
    }

    @Test("growth passes and is reported, rather than demanding a baseline update")
    func growth() {
        // An improvement must not require an extra commit to make CI green again, or
        // the gate becomes something people route around.
        let result = compareCoverage(
            measured: ["en": at(140, 5_000), "de": at(50, 2_000), "ja": at(40, 1_500)],
            against: baseline)

        #expect(result.passes)
        #expect(result.improved == ["en"])
    }

    @Test("a locale vanishing entirely fails")
    func vanished() {
        // The loudest version of the thing being guarded against, and one a per-locale
        // comparison would otherwise skip over silently.
        let result = compareCoverage(
            measured: ["en": at(100, 5_000), "de": at(50, 2_000)], against: baseline)

        #expect(!result.passes)
        #expect(result.missing == ["ja"])
        #expect(result.regressions.isEmpty, "vanishing is not a regression, it is its own case")
    }

    @Test("a new locale is reported but never fatal")
    func unlisted() {
        let result = compareCoverage(
            measured: [
                "en": at(100, 5_000), "de": at(50, 2_000), "ja": at(40, 1_500),
                "fr": at(25, 900),
            ], against: baseline)

        #expect(result.passes, "adding a locale must not fail the build that added it")
        #expect(result.unlisted == ["fr"])
    }

    @Test("regressions and disappearances are reported together, not one at a time")
    func multipleFailures() {
        // Reporting only the first would mean one CI run per problem.
        let result = compareCoverage(measured: ["en": at(10, 40)], against: baseline)

        #expect(result.regressions.map(\.locale) == ["en", "en"])
        #expect(result.missing == ["de", "ja"])
    }

    @Test("the baseline round-trips through JSON")
    func roundTrip() throws {
        let encoded = try JSONEncoder().encode(baseline)
        #expect(try JSONDecoder().decode(CoverageBaseline.self, from: encoded) == baseline)
    }
}
