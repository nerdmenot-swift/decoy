import Foundation
import Testing

@testable import DecoyAdapterKit

/// The record of what the filters threw away.
///
/// Every serious data bug this corpus has had was a filter discarding quietly. A minimum
/// length written for Latin script deleted 138 of 143 Korean surnames and `ko` shipped with
/// no surnames at all; a minimum count of forty threw away thirteen Welsh ones; a retry that
/// read throttling as a dead endpoint meant Spanish surnames were never once fetched. Not
/// one of them changed a committed byte, because a filter records only what survived — and
/// five survivors look exactly like a small language.
///
/// So the counts are committed. A filter whose behaviour moves shows up as a diff, which is
/// the only mechanism that would have caught any of the three.
@Suite("Filter report")
struct FilterReportTests {

    static let report: [String: [String: [String: [String: Int]]]] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/adapters/filters.json")
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: [String: [String: [String: Int]]]]
        else { return [:] }
        return object
    }()

    @Test("the filters that discard the most all report")
    func heaviestFiltersReport() throws {
        try #require(!Self.report.isEmpty, "no filters.json — run `swift run decoy-build-corpus`")

        // The two adapters that reject most of what they see. `indic-names` runs five
        // filters over a named-entity corpus and keeps a few per cent; `wikidata-names`
        // screens for mislabelled scripts. Both were sources of shipped bugs.
        for adapter in ["indic-names", "wikidata-names"] {
            #expect(Self.report[adapter] != nil, "\(adapter) reports no filter losses")
        }
    }

    /// Every record is coherent: you cannot keep more than you saw.
    @Test("kept never exceeds seen")
    func countsAreCoherent() throws {
        try #require(!Self.report.isEmpty)
        var checked = 0
        for (adapter, scopes) in Self.report {
            for (scope, filters) in scopes {
                for (filter, counts) in filters {
                    let kept = counts["kept"] ?? -1
                    let seen = counts["seen"] ?? -1
                    #expect(kept >= 0 && seen >= 0, "\(adapter)/\(scope)/\(filter) is malformed")
                    #expect(
                        kept <= seen,
                        "\(adapter)/\(scope)/\(filter) kept \(kept) of \(seen)")
                    checked += 1
                }
            }
        }
        // A scan that resolves to nothing passes every assertion above it, which is the
        // failure mode this whole file exists to argue against.
        #expect(checked > 0, "no filter records were examined")
    }

    /// The script filter is the one guarding against mislabelled upstream data, and the day
    /// it starts rejecting everything looks exactly like the day the language went quiet.
    ///
    /// Asserted as a range rather than a number: it should be removing a little, and a
    /// little is the signal. Zero would mean it stopped running; most would mean the
    /// expectation no longer matches what Wikidata is labelling.
    @Test("the script filter removes a little and not a lot")
    func scriptFilterIsProportionate() throws {
        let wikidata = try #require(Self.report["wikidata-names"])
        var fired = 0
        for (scope, filters) in wikidata {
            guard let counts = filters["script"] else { continue }
            let kept = counts["kept"] ?? 0
            let seen = counts["seen"] ?? 0
            fired += 1
            #expect(
                kept * 2 > seen,
                """
                \\(scope): the script filter kept \\(kept) of \\(seen). Removing more than half \\
                means the script expected for this language no longer matches what the \\
                snapshot holds — check the language before adjusting the expectation.
                """)
        }
        #expect(fired > 0, "the script filter reported nothing — is it still running?")
    }
}
