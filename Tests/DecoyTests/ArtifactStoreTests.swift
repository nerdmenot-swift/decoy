import Foundation
import Testing

@testable import DecoyAdapterKit

/// Acquisition, against the cache the JavaScript pipeline actually populated.
///
/// The point of these is agreement, not coverage. If the Swift store computes a different
/// cache filename, or accepts a file the old one would have rejected, the first Swift run
/// silently re-downloads fifty-one artifacts or — much worse — builds a corpus from bytes
/// nothing checked.
@Suite("Artifact store", .enabled(if: PortFixtures.hasArtifactCache))
struct ArtifactStoreTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters")

    private static func descriptor(_ id: String) throws -> SourceDescriptor {
        let url = root.appendingPathComponent("sources/\(id).json")
        return try JSONDecoder().decode(SourceDescriptor.self, from: Data(contentsOf: url))
    }

    /// The cache naming rule, which decides whether an existing cache is still readable.
    @Test("cache filenames match the ones already on disk")
    func cacheNaming() throws {
        let store = ArtifactStore(root: Self.root)
        var checked = 0
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.root.appendingPathComponent("sources"), includingPropertiesForKeys: nil)

        for file in files where file.pathExtension == "json" {
            let descriptor = try JSONDecoder().decode(
                SourceDescriptor.self, from: Data(contentsOf: file))
            for artifact in descriptor.artifacts ?? [] {
                let expected = store.cacheDirectory
                    .appendingPathComponent("\(descriptor.id)-\(artifact.cacheSuffix)")
                let complaint =
                    "\(descriptor.id)/\(artifact.name) — Swift would look at "
                    + "\(expected.lastPathComponent), which is not where it was cached"
                #expect(
                    FileManager.default.fileExists(atPath: expected.path), "\(complaint)")
                checked += 1
            }
        }
        #expect(checked == 62, "expected 62 artifacts, checked \(checked)")
    }

    /// A cached file is re-verified, never trusted.
    ///
    /// The tampering happens on a copy in memory rather than on the file in `.cache`. The
    /// first version wrote the corrupted bytes to the real cache and restored them in a
    /// `defer`, which is safe only if nothing else reads that file meanwhile — and
    /// swift-testing runs tests in parallel, so `IANATLDAdapter` read it mid-corruption and
    /// reported `entry 378: "evil" vs "exchange"`. A test that mutates shared state on disk
    /// is a test that fails somebody else.
    @Test("a corrupted cache entry is rejected and re-fetched, not used")
    func corruptedCache() throws {
        let store = ArtifactStore(root: Self.root)
        let descriptor = try Self.descriptor("iana-tld")
        let artifact = try #require(descriptor.artifacts?.first)
        let cached = store.cacheDirectory
            .appendingPathComponent("iana-tld-\(artifact.cacheSuffix)")
        let original = try Data(contentsOf: cached)

        // A plausible-looking file with one TLD swapped: exactly what a tampered mirror
        // would serve, and the case the digest exists for.
        let tampered = String(decoding: original, as: UTF8.self)
            .replacingOccurrences(of: "\nZONE", with: "\nEVIL")
        #expect(tampered != String(decoding: original, as: UTF8.self), "nothing was tampered")

        let expectation = try Integrity.Expectation(artifact.integrity)
        // The real bytes still verify …
        #expect(throws: Never.self) {
            try Integrity.verify(
                [UInt8](original), against: expectation, source: "iana-tld",
                url: artifact.url, ignoringLinesMatching: artifact.ignoreLinesMatching)
        }
        // … and the altered ones do not.
        #expect(throws: Integrity.Failure.self) {
            try Integrity.verify(
                [UInt8](Data(tampered.utf8)), against: expectation, source: "iana-tld",
                url: artifact.url, ignoringLinesMatching: artifact.ignoreLinesMatching)
        }
    }

    /// The two upstreams no build machine can reach resolve from vendor/.
    @Test("vendored artifacts are found and verified")
    func vendored() throws {
        let store = ArtifactStore(root: Self.root)
        for id in ["dvv-etunimet", "us-census-surnames"] {
            let descriptor = try Self.descriptor(id)
            let artifact = try #require(descriptor.artifacts?.first)
            let vendored = store.vendorDirectory
                .appendingPathComponent("\(id)-\(artifact.cacheSuffix)")
            #expect(
                FileManager.default.fileExists(atPath: vendored.path),
                "\(id) is unreachable from a build machine and must be vendored")

            let data = try Data(contentsOf: vendored)
            let expectation = try Integrity.Expectation(artifact.integrity)
            #expect(throws: Never.self) {
                try Integrity.verify(
                    [UInt8](data), against: expectation, source: id, url: artifact.url,
                    ignoringLinesMatching: artifact.ignoreLinesMatching)
            }
        }
    }

    /// A recorded version must not move when the data has not.
    ///
    /// `iana-tld` is the case that proves it. Its digest deliberately ignores the leading
    /// `# Version` serial, because IANA republishes the root zone whenever it is
    /// regenerated and the serial moves with all 1,438 entries identical. The descriptor
    /// used to then *read* that same serial back as its version, which put a
    /// daily-changing number into the provenance chunk — inside the committed blob — so a
    /// rebuild on a new day produced different locale modules for a zone that had not
    /// moved. CI caught it as stale modules, which reads like somebody forgot to
    /// regenerate rather than like an upstream serial ticking over.
    ///
    /// The version is transcribed now. This asserts the two halves cannot drift apart
    /// again: what the descriptor states is what the manifest records.
    @Test("a version that is ignored for hashing is not adopted for provenance")
    func versionIsStable() throws {
        let descriptor = try Self.descriptor("iana-tld")
        let artifact = try #require(descriptor.artifacts?.first)
        #expect(
            artifact.ignoreLinesMatching == "^# Version",
            "the digest no longer ignores the serial — this test guards the wrong thing")

        let manifestURL = Self.root.appendingPathComponent("out/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sources = root["sources"] as? [[String: Any]]
        else { return }

        let recorded = sources.first { $0["id"] as? String == "iana-tld" }?["version"] as? String
        #expect(
            recorded == descriptor.version,
            """
            the manifest records \(recorded ?? "nothing") and the descriptor states \
            \(descriptor.version). A version read out of a file whose serial changes daily \
            churns the corpus for no reason; transcribe it instead.
            """)
    }
}
