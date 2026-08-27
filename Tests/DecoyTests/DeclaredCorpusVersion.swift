import Foundation

@testable import Decoy

/// The versions the pipeline declares, read from the file that declares them.
///
/// Exists so no test hardcodes the number. It previously lived in the compiler's default,
/// whichever `--corpus-version` flag was typed, and two separate assertions — so every
/// bump broke two tests by hand, and CI built `1.0.0` while the tests demanded `11.0.0`.
///
/// Located the same way ``RealCorpus/directory`` finds the compiled blobs: relative to
/// `#filePath`, because a test bundle has no reliable notion of the repository root and
/// `Bundle.module` is the mechanism this package set out to avoid.
enum DeclaredCorpusVersion {

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    private struct Declaration: Decodable {
        let version: String
    }

    /// Parsed from `Tools/adapters/corpus-version.json`.
    ///
    /// A failure here is a broken checkout rather than a broken corpus, so it traps with
    /// the reason instead of returning an optional every caller would have to unwrap.
    static let value: CorpusVersion = {
        let url = repositoryRoot.appendingPathComponent("Tools/adapters/corpus-version.json")
        guard let data = try? Data(contentsOf: url) else {
            fatalError("cannot read \(url.path) — the corpus version is declared there")
        }
        guard let declaration = try? JSONDecoder().decode(Declaration.self, from: data) else {
            fatalError("\(url.lastPathComponent) has no `version` field")
        }
        let parts = declaration.version.split(separator: ".").compactMap { UInt16($0) }
        guard parts.count == 3 else {
            fatalError("corpus version '\(declaration.version)' is not X.Y.Z")
        }
        return CorpusVersion(major: parts[0], minor: parts[1], patch: parts[2])
    }()

    /// What a single locale declares, which is what its blob is stamped with.
    ///
    /// `value` above is the corpus *release* number and no blob carries it any more. A test
    /// that compares a locale against the release number is asserting the thing the
    /// per-locale split exists to stop being true, so the two are separate here rather than
    /// one figure used for both.
    static func forLocale(_ code: String) -> CorpusVersion? {
        let url = repositoryRoot.appendingPathComponent("Tools/adapters/corpus-version.json")
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let table = object["locales"] as? [String: [String: String]],
            let declared = table[code]?["version"]
        else { return nil }
        let parts = declared.split(separator: ".").compactMap { UInt16($0) }
        guard parts.count == 3 else { return nil }
        return CorpusVersion(major: parts[0], minor: parts[1], patch: parts[2])
    }
}
