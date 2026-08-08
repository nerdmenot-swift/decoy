import Foundation
import Testing

/// Keeps `Package.swift`, the emitted module directories and the locale roster agreeing.
///
/// Four of seventy-six locales ship as Swift modules; the other seventy-two compile to
/// `.decoy` and are emitted on demand. That is a deliberate deferral rather than an
/// oversight, and the reason is the checkout rather than the build. SwiftPM compiles only
/// the locale targets a consumer depends on — measured: an app importing `DecoyLocaleDE`
/// builds `DE`, `EN` and `Base` and never touches the others — but it clones the whole
/// repository, so ~14 MB of base64 string literals would land in every consumer's
/// `.build/checkouts` whether or not one of them is compiled.
///
/// A deferral with a working mechanism is fine. A deferral with a mechanism that silently
/// half-works is not, and this one did: `--emit-swift --locales pt_BR` wrote
/// `Sources/DecoyLocalePT_BR/` with no matching target, so the directory compiled nothing
/// and importing it failed with an error naming neither the flag nor the manifest.
///
/// The compiler refuses that now. These tests guard the other direction — a target
/// declared with no directory behind it, or a chain that disagrees with the roster.
@Suite("Locale modules")
struct LocaleModuleTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    /// The `locales` array from `Package.swift`, as `(name, chain)` pairs.
    ///
    /// Read as text. `Package.swift` is a program, and asking SwiftPM what it declares
    /// would mean a subprocess and a build directory to check three lines.
    private static func declaredLocales() throws -> [(name: String, chain: [String])] {
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        guard let start = manifest.range(of: "let locales:"),
            let end = manifest.range(of: "\n]", range: start.upperBound..<manifest.endIndex)
        else { return [] }

        return manifest[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .compactMap { line -> (String, [String])? in
                let quoted = line.split(separator: "\"").enumerated()
                    .filter { $0.offset % 2 == 1 }
                    .map { String($0.element) }
                guard let name = quoted.first else { return nil }
                return (name, Array(quoted.dropFirst()))
            }
    }

    @Test("every declared locale target has a module directory behind it")
    func declaredHasDirectory() throws {
        for (name, _) in try Self.declaredLocales() {
            let file = Self.root
                .appendingPathComponent("Sources/DecoyLocale\(name)/DecoyLocale\(name).swift")
            let complaint =
                "Package.swift declares \(name) but Sources/DecoyLocale\(name)/ is missing. "
                + "Emit it with: swift run decoy-compile-corpus Tools/adapters/out "
                + "Corpus/binary --emit-swift Sources --locales <codes>"
            #expect(FileManager.default.fileExists(atPath: file.path), "\(complaint)")
        }
    }

    @Test("every module directory is a declared target")
    func directoryIsDeclared() throws {
        let declared = Set(try Self.declaredLocales().map(\.name))
        let directories = try FileManager.default.contentsOfDirectory(
            atPath: Self.root.appendingPathComponent("Sources").path
        ).filter { $0.hasPrefix("DecoyLocale") }

        for directory in directories.sorted() {
            let name = String(directory.dropFirst("DecoyLocale".count))
            let complaint =
                "Sources/\(directory)/ exists but Package.swift declares no such target, so "
                + "it compiles nothing and cannot be imported"
            #expect(declared.contains(name), "\(complaint)")
        }
    }

    /// The chain is the part that is easy to get wrong by hand, and getting it wrong is
    /// silent: a module with a short chain resolves fewer paths and falls back to
    /// nothing, which reads as missing data rather than as a manifest error.
    @Test("each declared chain matches the locale roster")
    func chainsMatchRoster() throws {
        let manifestURL = Self.root.appendingPathComponent("Tools/adapters/out/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let locales = object["locales"] as? [String: [String: Any]]
        else {
            // The manifest is a build artifact; a fresh clone has none.
            return
        }

        for (name, chain) in try Self.declaredLocales() {
            let code = name == "Base" ? "base" : name.lowercased()
            // `PT_BR` is `pt_BR` upstream: the second part keeps its case.
            let candidates = [code, name, name.replacingOccurrences(of: "_", with: "_")]
            guard
                let entry = candidates.compactMap({ locales[$0] }).first
                    ?? locales.first(where: { $0.key.uppercased() == name })?.value,
                let expected = entry["chain"] as? [String]
            else {
                Issue.record("\(name) is declared in Package.swift but is not in the roster")
                continue
            }

            let expectedSuffixes = expected.dropFirst().map {
                $0 == "base" ? "Base" : $0.uppercased()
            }
            #expect(
                chain == Array(expectedSuffixes),
                "\(name) declares chain \(chain), roster says \(Array(expectedSuffixes))"
            )
        }
    }

    /// `Base` is a target and must not be a product.
    @Test("Base is buildable but not importable on its own")
    func baseIsNotAProduct() throws {
        let manifest = try String(
            contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let complaint =
            "DecoyLocaleBase must stay out of products — it is language-neutral data, and "
            + "roughly 45 of the corpus-backed generators trap against it"
        #expect(!manifest.contains("\"DecoyLocaleBase\"]"), "\(complaint)")
    }
}
