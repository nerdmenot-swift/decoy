import Foundation
import Testing

@testable import DecoyAdapterKit

/// The Swift integrity layer against every artifact the Node pipeline actually pinned.
///
/// The unit vectors in `SHA512Tests` prove the algorithm. This proves the *contract*: that
/// the Swift port computes the same digest, over the same normalised bytes, as the
/// JavaScript it replaces — for all 51 real artifacts, including the one whose digest
/// deliberately ignores a line.
///
/// If this suite passes, the port cannot silently accept an artifact the old pipeline
/// would have rejected, which is the only property that matters here.
@Suite("Integrity against the real pinned artifacts", .enabled(if: PortFixtures.hasArtifactCache))
struct IntegrityTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let sources = root.appendingPathComponent("Tools/adapters/sources")
    private static let cache = root.appendingPathComponent("Tools/adapters/.cache")

    private struct Descriptor: Decodable {
        struct Artifact: Decodable {
            let name: String
            /// Absent on eleven artifacts. `lib/sources.mjs` falls through to `tar xzf` for
            /// anything that is not `zip` or `tar.xz`, so absent means tgz — and a decoder
            /// that required this silently dropped six whole descriptors.
            let format: String?
            let filename: String?
            let url: String
            let integrity: String
            let ignoreLinesMatching: String?
        }
        let id: String
        let artifacts: [Artifact]?
    }

    /// Every descriptor, and the ones that would not decode.
    ///
    /// Failures are returned rather than swallowed. `compactMap { try? decode }` hid eleven
    /// artifacts behind a field that turned out to be optional, and the suite went green
    /// having checked three quarters of what it claimed to — the same shape as a link check
    /// that reads HTTP status and cannot see a rejection page served with a 200.
    private static func descriptors() -> (ok: [Descriptor], failed: [String]) {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: sources, includingPropertiesForKeys: nil)
        else { return ([], ["could not list \(sources.path)"]) }

        var ok: [Descriptor] = []
        var failed: [String] = []
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
            do {
                ok.append(try JSONDecoder().decode(Descriptor.self, from: Data(contentsOf: url)))
            } catch {
                failed.append("\(url.lastPathComponent): \(error)")
            }
        }
        return (ok, failed)
    }

    /// The cache path `lib/sources.mjs` uses, which the port has to agree with.
    private static func cachedPath(_ id: String, _ artifact: Descriptor.Artifact) -> URL {
        let suffix: String
        if artifact.format == "file" {
            suffix = artifact.filename ?? artifact.name
        } else {
            let extensions = ["zip": "zip", "tar.xz": "tar.xz"]
            suffix = "\(artifact.name).\(artifact.format.flatMap { extensions[$0] } ?? "tgz")"
        }
        return cache.appendingPathComponent("\(id)-\(suffix)")
    }

    @Test("every pinned artifact in the cache matches its recorded digest")
    func everyArtifact() throws {
        var checked = 0
        var missing: [String] = []
        let (descriptors, failed) = Self.descriptors()

        // A descriptor that will not parse is a hole in the check, not a detail.
        for failure in failed { Issue.record("descriptor did not decode — \(failure)") }

        for descriptor in descriptors {
            for artifact in descriptor.artifacts ?? [] {
                let path = Self.cachedPath(descriptor.id, artifact)
                guard let data = try? Data(contentsOf: path) else {
                    missing.append("\(descriptor.id)/\(artifact.name)")
                    continue
                }
                let expectation = try Integrity.Expectation(artifact.integrity)
                #expect(throws: Never.self) {
                    try Integrity.verify(
                        [UInt8](data), against: expectation, source: descriptor.id,
                        url: artifact.url, ignoringLinesMatching: artifact.ignoreLinesMatching)
                }
                checked += 1
            }
        }

        // A fresh clone has no cache, and this suite is about agreement rather than about
        // acquisition — so nothing is asserted about what is absent. Silence would be worse
        // than useless though: a suite that passes having checked zero artifacts is exactly
        // the "green having tested nothing" failure the corpus-gated suites already had.
        if checked == 0 {
            Issue.record(
                "no cached artifacts, so nothing was verified — run `node Tools/adapters/run.mjs`")
        }
        // The count is asserted, not printed. 51 artifacts are declared across the
        // descriptors; anything less means the enumeration lost some, which is how this
        // suite first passed having silently skipped eleven of them.
        let declared = descriptors.reduce(0) { $0 + ($1.artifacts?.count ?? 0) }
        #expect(declared == 51, "expected 51 declared artifacts, enumerated \(declared)")
        #expect(
            checked + missing.count == declared,
            "verified \(checked) + missing \(missing.count) should account for all \(declared)")
        print("integrity: verified \(checked) of \(declared) declared, \(missing.count) not cached")
    }

    @Test("the ignore-lines rule matches JavaScript's")
    func ignoreLines() throws {
        // iana-tld is the only descriptor that uses it, and the whole reason it exists: the
        // serial on line one changes daily whether or not a TLD did.
        let body = "# Version 2026081200, Last Updated Wed\nAAA\nAARP\nZONE"
        let stripped = Integrity.normalised(
            [UInt8](body.utf8), ignoringLinesMatching: "^# Version")
        #expect(String(decoding: stripped, as: UTF8.self) == "AAA\nAARP\nZONE")

        // A serial change must not change the digest; a TLD change must.
        let later = "# Version 2026090100, Last Updated Thu\nAAA\nAARP\nZONE"
        #expect(
            Integrity.digest(Integrity.normalised([UInt8](later.utf8), ignoringLinesMatching: "^# Version"))
                == Integrity.digest(stripped))

        let tampered = "# Version 2026081200, Last Updated Wed\nAAA\nAARP\nEVIL"
        #expect(
            Integrity.digest(
                Integrity.normalised([UInt8](tampered.utf8), ignoringLinesMatching: "^# Version"))
                != Integrity.digest(stripped))
    }

    @Test("a malformed or unsupported integrity string is rejected")
    func malformed() {
        #expect(throws: Integrity.Failure.self) { try Integrity.Expectation("nodashhere") }
        #expect(throws: Integrity.Failure.self) { try Integrity.Expectation("sha512-") }
        #expect(throws: Integrity.Failure.self) { try Integrity.Expectation("md5-abc") }
    }
}
