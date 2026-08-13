import Foundation

/// Whether the fixtures the port-parity suites compare against are present.
///
/// Those suites exist to prove the Swift pipeline reproduces the JavaScript one, and they
/// do it by diffing against what the JavaScript actually emitted: the intermediate JSON,
/// the per-adapter contribution dumps, and a few reference files. All of that is generated,
/// none of it is committed, and a fresh clone has none of it.
///
/// The suites deliberately *fail* when a fixture they expect is missing — a parity check
/// that quietly compares nothing is worse than one that has not been written, because it
/// looks done. That is right on a machine doing the port and wrong in CI, where the
/// fixtures legitimately do not exist and the failure says nothing about the commit.
///
/// So the suites are gated here instead. Absent fixtures means skipped, which swift-testing
/// reports as a skip rather than a pass, and present fixtures means the strict behaviour is
/// back. The distinction that matters is preserved: nothing ever reports success having
/// compared nothing.
///
/// To run them, build the fixtures first:
///
///     node Tools/adapters/run.mjs
///     node Tools/adapters/dump-contributions.mjs
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

    /// The per-adapter contribution dumps.
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
