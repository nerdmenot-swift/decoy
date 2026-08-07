import Testing

@testable import Decoy
@testable import DecoyCorpusKit

/// Tests for the rule that decides which source — and therefore which licence — covers
/// each path in a compiled corpus.
///
/// This had no test until now, and it had a real bug: exact matching credited every path
/// beneath a claimed one to whichever source happened to be registered first, silently
/// mislabelling 2,036 paths in `base` as MIT/mime-db. Nobody notices that until a licence
/// audit, which is the worst possible time.
@Suite("Path attribution")
struct AttributionTests {

    private func compiler(
        claiming attribution: [String: String],
        sources: [String: UInt32],
        default defaultID: UInt32 = 0
    ) -> LocaleCompiler {
        LocaleCompiler(attribution: attribution, defaultSourceID: defaultID, sourceIDs: sources)
    }

    @Test("an exactly claimed path resolves to its own source")
    func exactClaim() {
        let subject = compiler(
            claiming: ["location.country": "cldr"],
            sources: ["cldr": 7]
        )
        #expect(subject.sourceID(for: "location.country") == 7)
    }

    @Test("a path beneath a claim inherits it")
    func nearestAncestor() {
        // The real case: mime-db claims `system.mime_type` and the compiler then emits
        // thousands of paths beneath it, one per media type, none matching exactly.
        let subject = compiler(
            claiming: ["system.mime_type": "mime-db"],
            sources: ["mime-db": 3]
        )
        #expect(subject.sourceID(for: "system.mime_type.application/json.extensions") == 3)
        #expect(subject.sourceID(for: "system.mime_type.__keys") == 3)
    }

    @Test("the nearest claim wins over a more distant one")
    func nearestBeatsFurthest() {
        // Two sources claiming different depths of the same tree is not hypothetical:
        // faker-js claims whole categories and the adapters claim paths inside them.
        let subject = compiler(
            claiming: ["system": "faker-js", "system.mime_type": "mime-db"],
            sources: ["faker-js": 1, "mime-db": 3]
        )
        #expect(subject.sourceID(for: "system.mime_type.image/png.extensions") == 3)
        #expect(
            subject.sourceID(for: "system.directory_path") == 1,
            "a sibling of the claimed node keeps the outer claim"
        )
    }

    @Test("an unclaimed path falls back to the default source, not to a neighbour")
    func unclaimedFallsBack() {
        let subject = compiler(
            claiming: ["location.country": "cldr"],
            sources: ["cldr": 7],
            default: 99
        )
        #expect(subject.sourceID(for: "person.first_name.female") == 99)
        #expect(
            subject.sourceID(for: "location.city") == 99,
            "sharing a prefix with a claimed path is not the same as being beneath it"
        )
    }

    @Test("a claim naming an unregistered source falls back rather than crediting it")
    func unregisteredSource() {
        // Attribution and registration come from different parts of the manifest, so
        // they can disagree. Crediting a source that was never registered would write a
        // dangling id into the blob.
        let subject = compiler(
            claiming: ["location.country": "not-registered"],
            sources: ["cldr": 7],
            default: 99
        )
        #expect(subject.sourceID(for: "location.country") == 99)
    }

    @Test("a single-segment path is attributable")
    func topLevelClaim() {
        // faker-js claims bare category names like `person`, with no dot in them at all.
        let subject = compiler(claiming: ["person": "faker-js"], sources: ["faker-js": 1])
        #expect(subject.sourceID(for: "person") == 1)
        #expect(subject.sourceID(for: "person.first_name.female") == 1)
    }

    @Test("paths containing dots inside a segment still attribute correctly")
    func dottedSegments() {
        // Media types carry dots — `application/vnd.ms-excel` — so the walk up the path
        // passes through positions that are not really segment boundaries. It has to
        // keep walking rather than give up at the first one that is not claimed.
        let subject = compiler(
            claiming: ["system.mime_type": "mime-db"],
            sources: ["mime-db": 3],
            default: 99
        )
        #expect(
            subject.sourceID(for: "system.mime_type.application/vnd.ms-excel.extensions") == 3
        )
    }
}
