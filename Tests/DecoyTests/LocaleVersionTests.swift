import DecoyLocales
import Foundation
import Testing

@testable import Decoy

/// Each locale carries its own data version.
///
/// One number for the whole corpus was too blunt to act on. Adding Hindi moved it for
/// somebody using only English, so their fixtures read as at-risk when nothing they drew
/// from had changed — and a version people are told to pin is only useful if it moves for
/// reasons that concern them.
@Suite("Locale versions")
struct LocaleVersionTests {

    /// The declared table, which is the pipeline's record of what each locale is at.
    static let declared: [String: (version: String, fingerprint: String)] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/adapters/corpus-version.json")
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let table = object["locales"] as? [String: [String: String]]
        else { return [:] }
        return table.compactMapValues { entry in
            entry["version"].map { ($0, entry["fingerprint"] ?? "") }
        }
    }()

    @Test("every locale reports the version the pipeline declared for it")
    func versionsMatchTheDeclaration() throws {
        try #require(!Self.declared.isEmpty, "corpus-version.json declares no locales")
        var checked = 0
        for code in DecoyLocales.available {
            let locale = try DecoyLocales.locale(code)
            let version = try #require(locale.version, "\(code) carries no version")
            let expected = try #require(Self.declared[code]?.version, "\(code) is undeclared")
            #expect(
                version.description == expected,
                "\(code) blob says \(version), corpus-version.json says \(expected)")
            checked += 1
        }
        // A scan that resolves to nothing passes every assertion above it.
        #expect(checked == DecoyLocales.available.count)
    }

    /// Every locale has a fingerprint recorded, which is what makes the build gate real.
    ///
    /// An empty one is not a failure state the gate can see: it treats blank as "never
    /// recorded" and lets the build through, so a locale that lost its fingerprint would
    /// silently stop being checked. That is the shape of failure this project keeps
    /// finding, so it is asserted rather than assumed.
    @Test("every locale has a recorded fingerprint")
    func fingerprintsRecorded() throws {
        try #require(!Self.declared.isEmpty)
        for code in DecoyLocales.available {
            let entry = try #require(Self.declared[code], "\(code) is undeclared")
            #expect(
                !entry.fingerprint.isEmpty,
                "\(code) has no fingerprint — its data is no longer gated on a version bump")
        }
    }

    /// A locale's version is its own, not the corpus release number.
    ///
    /// This is the whole point of the split, so it is asserted directly rather than left to
    /// follow from the other two. The first version of this test compared the locale
    /// version against `Decoy.version` with an `||` escape for the case where they matched
    /// — which they did, so it passed without checking anything.
    @Test("a locale's version is not the corpus release number")
    func independentOfTheReleaseNumber() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/adapters/corpus-version.json")
        let data = try Data(contentsOf: url)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let release = try #require(object["version"] as? String)

        let en = try DecoyLocales.locale("en")
        let version = try #require(en.version)
        #expect(
            version.description != release,
            """
            en reports \(version) and the corpus release is \(release). Equal numbers mean \
            the compiler fell back to stamping the release into every blob, which is what it \
            did before locales had versions of their own.
            """)
    }
}
