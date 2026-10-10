import Foundation
import Testing

@testable import DecoyAdapterKit

/// The three-way reading of an upstream whose bytes are not the pinned ones.
///
/// This is the decision that used to be a coin with one side. Getting it wrong in one
/// direction fails a build over a SharePoint tag; in the other it accepts a document that
/// says something new. Both directions are asserted here, on a temporary tree rather than
/// the real cache, so the test says what the rule is rather than what the current
/// fifty-four upstreams happen to be doing.
@Suite("Upstream verdict")
struct UpstreamVerdictTests {

    /// A store rooted in a fresh directory, and a file in its cache.
    private static func scratch(
        _ filename: String, _ contents: String
    ) throws -> (store: ArtifactStore, file: URL, root: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("decoy-verdict-\(UUID().uuidString)")
        let store = ArtifactStore(root: root)
        try FileManager.default.createDirectory(
            at: store.cacheDirectory, withIntermediateDirectories: true)
        let file = store.cacheDirectory.appendingPathComponent(filename)
        try Data(contents.utf8).write(to: file)
        return (store, file, root)
    }

    private static func artifact(
        _ filename: String, pinning bytes: String
    ) -> SourceDescriptor.Artifact {
        SourceDescriptor.Artifact(
            name: "list", format: "file", filename: filename,
            url: "https://example.invalid/\(filename)",
            integrity: "sha512-" + Integrity.digest(Array(bytes.utf8)),
            ignoreLinesMatching: nil)
    }

    @Test("content unchanged is accepted, and reported")
    func whitespaceOnlyChangeIsAccepted() throws {
        // The CBS case in miniature: the bytes moved, everything the document states did
        // not, and the pipeline may continue — but it has to say so.
        let pinned = "AAA\nBBB\n"
        let (store, file, root) = try Self.scratch("tlds.txt", "AAA\r\nBBB  \r\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = Self.artifact("tlds.txt", pinning: pinned)
        let lock = UpstreamLock(entries: [
            "iana-tld/list": UpstreamLock.Entry(
                content: Integrity.digest(
                    Array(ContentView.renderLines(Array(pinned.utf8), ignoringLinesMatching: nil).text.utf8)),
                view: ContentView.Kind.lines.rawValue,
                bytes: Integrity.digest(Array(pinned.utf8)))
        ])

        let verdict = try store.verdict(
            for: file, artifact: artifact, source: "iana-tld", lock: lock)
        guard case .contentUnchanged(let drift) = verdict else {
            Issue.record("expected the change to be accepted, got \(verdict)")
            return
        }
        #expect(drift.view == "lines/v1")
        #expect(drift.actualBytes != drift.pinnedBytes)
    }

    @Test("a changed value is refused")
    func changedContentIsRefused() throws {
        let pinned = "JUMP\nJUNIPER\nJUSTICE\n"
        let (store, file, root) = try Self.scratch("tlds.txt", "JUMP\nJUSTICE\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = Self.artifact("tlds.txt", pinning: pinned)
        let lock = UpstreamLock(entries: [
            "iana-tld/list": UpstreamLock.Entry(
                content: Integrity.digest(
                    Array(ContentView.renderLines(Array(pinned.utf8), ignoringLinesMatching: nil).text.utf8)),
                view: ContentView.Kind.lines.rawValue,
                bytes: Integrity.digest(Array(pinned.utf8)))
        ])

        #expect(throws: ArtifactStore.Failure.self) {
            _ = try store.verdict(for: file, artifact: artifact, source: "iana-tld", lock: lock)
        }
    }

    @Test("an artifact nobody has recorded is refused, not guessed at")
    func anUnrecordedArtifactIsRefused() throws {
        // Fail closed. Without a recorded content digest there is nothing to compare, and
        // "we have never looked at this" is not a reason to accept it.
        let (store, file, root) = try Self.scratch("tlds.txt", "AAA\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = Self.artifact("tlds.txt", pinning: "BBB\n")
        #expect(throws: ArtifactStore.Failure.self) {
            _ = try store.verdict(
                for: file, artifact: artifact, source: "iana-tld", lock: UpstreamLock())
        }
    }

    @Test("a recorded digest from another view is refused")
    func aStaleViewIsRefused() throws {
        // A renderer that changes has to invalidate what it recorded rather than compare
        // old digests against new rules, which is why the view is named in the lock.
        let (store, file, root) = try Self.scratch("tlds.txt", "AAA\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = Self.artifact("tlds.txt", pinning: "BBB\n")
        let lock = UpstreamLock(entries: [
            "iana-tld/list": UpstreamLock.Entry(
                content: "whatever", view: "lines/v0", bytes: "whatever")
        ])
        #expect(throws: ArtifactStore.Failure.self) {
            _ = try store.verdict(for: file, artifact: artifact, source: "iana-tld", lock: lock)
        }
    }

    @Test("a rejection page cannot pass as an inconsequential change")
    func aRejectionPageIsRefused() throws {
        // The failure `Integrity` exists for: HTTP 200, 247 bytes, and a body that is not
        // the dataset. It has to stay fatal now that some changes are not.
        let (store, file, root) = try Self.scratch(
            "table.json", "<html><body>Request Rejected</body></html>")
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = Self.artifact("table.json", pinning: #"{"a":1}"#)
        let lock = UpstreamLock(entries: [
            "pubchem/list": UpstreamLock.Entry(
                content: Integrity.digest(
                    Array(try ContentView.renderJSON(Array(#"{"a":1}"#.utf8), label: "t").text.utf8)),
                view: ContentView.Kind.json.rawValue,
                bytes: Integrity.digest(Array(#"{"a":1}"#.utf8)))
        ])
        #expect(throws: ArtifactStore.Failure.self) {
            _ = try store.verdict(for: file, artifact: artifact, source: "pubchem", lock: lock)
        }
    }

    // MARK: - The lock

    @Test("the lock round-trips, deferrals included")
    func lockRoundTrips() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("decoy-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var lock = UpstreamLock()
        lock.entries["iso-4217-six/list"] = UpstreamLock.Entry(
            content: "c", view: "xml/v1", bytes: "b", reviewedAt: "2026-10-11",
            note: "two entries gained IsFund")
        lock.deferrals["iana-tld"] = UpstreamLock.Deferral(
            source: "iana-tld", firstSeen: "2026-10-05", expires: "2027-01-03",
            reason: "JUNIPER retired; adopt at the next corpus refresh",
            change: ["base.internet.domain_suffix: 1438 → 1437 entries (-JUNIPER)"])
        try lock.write(to: root)

        let reread = try UpstreamLock.load(from: root)
        #expect(reread.entries["iso-4217-six/list"] == lock.entries["iso-4217-six/list"])
        #expect(reread.deferrals["iana-tld"] == lock.deferrals["iana-tld"])
    }

    @Test("a missing lock reads as empty rather than failing")
    func missingLockIsEmpty() throws {
        // Which is what keeps the fail-closed path honest: no lock means every byte change
        // is fatal, exactly as before any of this existed.
        let empty = try UpstreamLock.load(
            from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(empty.entries.isEmpty)
        #expect(empty.deferrals.isEmpty)
    }
}
