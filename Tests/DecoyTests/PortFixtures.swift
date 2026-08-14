import Foundation

/// Whether the fixtures the pipeline suites compare against are present.
///
/// Two of the three are build outputs a fresh clone does not have: the intermediate JSON
/// and the verified upstream artifacts. The adapter baselines *are* committed, because with
/// the JavaScript gone they are the only record of what each adapter emits.
///
/// The suites deliberately *fail* when a fixture they expect is missing — a check that
/// quietly compares nothing is worse than one that has not been written, because it looks
/// done. That is right on a machine with a populated cache and wrong in a job that
/// legitimately has none, where the failure says nothing about the commit.
///
/// So the suites are gated here instead. Absent fixtures means skipped, which swift-testing
/// reports as a skip rather than a pass, and present fixtures means the strict behaviour is
/// back. The distinction that matters is preserved: nothing ever reports success having
/// compared nothing.
///
/// To run them, build the fixtures first:
///
///     swift run decoy-build-corpus
enum PortFixtures {

    static let adapters = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters")

    /// The intermediate JSON the pipeline emits per locale.
    static var hasIntermediateJSON: Bool {
        FileManager.default.fileExists(
            atPath: adapters.appendingPathComponent("out/locales/en.json").path)
    }

    /// The per-adapter baselines. Committed, so this is true on a fresh clone.
    static var hasContributionDumps: Bool {
        FileManager.default.fileExists(
            atPath: adapters.appendingPathComponent("parity/iana-tld.json").path)
    }

    /// The verified upstream artifacts.
    static var hasArtifactCache: Bool {
        FileManager.default.fileExists(
            atPath: adapters.appendingPathComponent(".cache/iana-tld-tlds-alpha-by-domain.txt").path)
    }

    /// A reference file dumped from a JavaScript module, by path.
    static func hasReference(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
