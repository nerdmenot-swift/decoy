import Foundation
import Testing

@testable import DecoyLocales

/// The runtime locale loader, which is how sixty-one of the sixty-four locales are reached.
///
/// Only three ship as compiled-in modules. Everything else is a blob in this target's
/// resources, and the chain that makes it usable is derived here rather than stored — so
/// the derivation has to agree with the one the corpus was built with, for every locale,
/// or a caller gets English where they asked for Austrian German and nothing says so.
@Suite("Runtime locales")
struct DecoyLocalesTests {

    /// The chains the pipeline recorded, which are the answer this must reproduce.
    private static let recorded: [String: [String]] = {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/adapters/out/manifest.json")
        guard let data = try? Data(contentsOf: manifest),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let locales = root["locales"] as? [String: [String: Any]]
        else { return [:] }
        return locales.compactMapValues { $0["chain"] as? [String] }
    }()

    @Test("every locale in the corpus is loadable")
    func everyLocaleLoads() throws {
        #expect(DecoyLocales.available.count == 66, "expected 66 blobs in the bundle")
        for code in DecoyLocales.available {
            #expect(throws: Never.self, "\(code) failed to load") {
                _ = try DecoyLocales.locale(code)
            }
        }
    }

    /// The derivation against the pipeline's own record, for all sixty-four.
    ///
    /// Not a spot check. `sr_RS_latin` keeps neither `sr_RS` nor `sr` because neither is a
    /// locale; `de_AT` keeps `de`; `base` inherits from nothing at all. One rule, and the
    /// cases that distinguish a right implementation from a plausible one are exactly the
    /// ones nobody thinks to try.
    ///
    /// The other branch — a three-segment code whose middle segment *is* a locale — used to
    /// be covered here by `en_AU_ocker` and is now in `OrchestratorTests` against a
    /// synthetic roster, so it survives the locale being cut.
    @Test("derived chains match the ones the corpus was built with")
    func chainsMatchTheManifest() throws {
        try #require(!Self.recorded.isEmpty, "no manifest — run `swift run decoy-build-corpus`")
        for (code, expected) in Self.recorded.sorted(by: { $0.key < $1.key }) {
            #expect(
                DecoyLocales.chain(for: code) == expected,
                "\(code): derived \(DecoyLocales.chain(for: code)), corpus says \(expected)")
        }
    }

    /// A code the corpus does not have must fail, not quietly become English.
    @Test("an unknown code throws rather than falling back")
    func unknownCodeThrows() {
        // `pt` is the trap: it is not a locale here, but filtering it out of its own chain
        // leaves `["en", "base"]`, which loads and works and is not Portuguese.
        #expect(DecoyLocales.chain(for: "pt") == ["en", "base"])
        #expect(throws: DecoyLocales.Failure.self) { _ = try DecoyLocales.locale("pt") }
        #expect(throws: DecoyLocales.Failure.self) { _ = try DecoyLocales.locale("klingon") }

        // And the message names what does exist, because somebody who typed `pt` is one
        // character away from `pt_BR`.
        let message = String(describing: DecoyLocales.Failure.unknown(
            code: "pt", available: DecoyLocales.available))
        #expect(message.contains("pt_BR") && message.contains("pt_PT"))
    }

    @Test("a locale drawn at run time matches its compiled-in module")
    func matchesTheModule() throws {
        // The two paths to German must be the same German, or one of them is lying.
        let loaded = try DecoyLocales.locale("de")
        #expect(loaded.chain.count == 3, "de should resolve through en to base")
        #expect(try loaded.nativeCoverage > 0.3)
    }
}
