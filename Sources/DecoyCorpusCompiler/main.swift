import Decoy
import DecoyCorpusKit
import Foundation

/// Compiles the adapter pipeline's JSON into one binary corpus per locale.
///
/// Usage: `decoy-compile-corpus <adapters-out-dir> <output-dir> [--corpus-version X.Y.Z]`
///
/// The version comes from the manifest, which the pipeline fills from
/// `Tools/adapters/corpus-version.json`. The flag is an override for one-off builds.

// MARK: - Arguments

struct Options {
    var input: URL
    var output: URL
    /// Set from the manifest, which carries the version the pipeline declared.
    /// `--corpus-version` overrides it; there is deliberately no default, because a
    /// default is what let CI silently build 1.0.0 while the tests asserted 11.0.0.
    var corpusVersion: CorpusVersion?
    /// Where to write generated Swift locale modules, if anywhere.
    var emitSwift: URL?
    /// Which locales to generate modules for. Their fallback chains are pulled in
    /// automatically, so asking for `de` also generates `en` and `base`.
    var swiftLocales: [String] = []
}

/// The module and type name for a locale's generated source.
/// The `Package.swift` name for a locale: `de_AT` -> `DE_AT`, `base` -> `Base`.
func moduleSuffix(_ code: String) -> String {
    code == "base" ? "Base" : code.uppercased()
}

func moduleName(_ code: String) -> String {
    "DecoyLocale" + moduleSuffix(code)
}

func parseArguments() -> Options {
    var positional: [String] = []
    var version: CorpusVersion?
    var emitSwift: URL?
    var swiftLocales: [String] = []
    var i = 1
    let args = CommandLine.arguments

    while i < args.count {
        if args[i] == "--emit-swift", i + 1 < args.count {
            emitSwift = URL(fileURLWithPath: args[i + 1])
            i += 2
        } else if args[i] == "--locales", i + 1 < args.count {
            swiftLocales = args[i + 1].split(separator: ",").map(String.init)
            i += 2
        } else if args[i] == "--corpus-version", i + 1 < args.count {
            let parts = args[i + 1].split(separator: ".").compactMap { UInt16($0) }
            guard parts.count == 3 else { fail("--corpus-version must look like 1.0.0") }
            version = CorpusVersion(major: parts[0], minor: parts[1], patch: parts[2])
            i += 2
        } else {
            positional.append(args[i])
            i += 1
        }
    }

    guard positional.count == 2 else {
        fail("usage: decoy-compile-corpus <adapters-out-dir> <output-dir> [--corpus-version X.Y.Z]")
    }
    var options = Options(
        input: URL(fileURLWithPath: positional[0]),
        output: URL(fileURLWithPath: positional[1])
    )
    options.corpusVersion = version
    options.emitSwift = emitSwift
    options.swiftLocales = swiftLocales
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Driver

let options = parseArguments()
let fileManager = FileManager.default

let manifestURL = options.input.appendingPathComponent("manifest.json")
guard let manifestData = try? Data(contentsOf: manifestURL) else {
    fail("cannot read \(manifestURL.path) — run `node run.mjs` in Tools/adapters first")
}
let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

/// The flag wins if given, otherwise the version the pipeline declared.
///
/// Refusing to guess is the point. A default here is exactly what let CI build a 1.0.0
/// corpus while the tests asserted 11.0.0 — the mismatch surfaced as two failing
/// assertions rather than as the missing input it actually was.
guard let corpusVersion = options.corpusVersion ?? manifest.declaredCorpusVersion else {
    fail(
        "no corpus version: \(manifestURL.lastPathComponent) declares none and "
            + "--corpus-version was not given. Set it in Tools/adapters/corpus-version.json."
    )
}

try fileManager.createDirectory(at: options.output, withIntermediateDirectories: true)

var totalBytes = 0
var totalJSON = 0
var compiled: [String: [UInt8]] = [:]
/// Per locale, the source ids its own tables were attributed to — for the module headers.
var usedSources: [String: Set<String>] = [:]
var allSkipped: [String] = []
let codes = manifest.locales.keys.sorted()

for code in codes {
    let jsonURL = options.input
        .appendingPathComponent("locales")
        .appendingPathComponent("\(code).json")
    guard let data = try? Data(contentsOf: jsonURL) else {
        fail("missing locale file for \(code)")
    }
    totalJSON += data.count

    let root = try JSONDecoder().decode(JSONValue.self, from: data)

    var builder = CorpusBuilder(version: corpusVersion)

    // Every declared source is registered in every locale, whether or not that locale
    // draws on it. A few dozen bytes buys a stable source ID across the whole corpus,
    // which is what makes "show me everything still derived from X" answerable.
    var sourceIDs: [String: UInt32] = [:]
    for record in manifest.sourceRecords {
        sourceIDs[record.id] = builder.addSource(
            id: record.id,
            license: record.license,
            url: record.url,
            version: record.version,
            retrieved: record.retrieved,
            copyright: record.copyright ?? ""
        )
    }
    guard let defaultSourceID = sourceIDs[manifest.sourceRecords[0].id] else {
        fail("\(code): no sources declared in the manifest")
    }

    var compiler = LocaleCompiler(
        attribution: manifest.attribution?[code] ?? [:],
        defaultSourceID: defaultSourceID,
        sourceIDs: sourceIDs,
        keyTables: Set(manifest.keyTables ?? [])
    )
    compiler.emit(path: "", value: root, into: &builder)

    let bytes = builder.build()

    // Every blob is read back before being written. A corpus that cannot be loaded
    // is worse than a build failure, because it surfaces at a user's first call.
    let verified = try Corpus(bytes: bytes)
    guard verified.version == corpusVersion else {
        fail("\(code): verification read-back produced the wrong corpus version")
    }

    let outURL = options.output.appendingPathComponent("\(code).decoy")
    try Data(bytes).write(to: outURL)
    totalBytes += bytes.count
    allSkipped.append(contentsOf: compiler.stats.skipped)
    compiled[code] = bytes

    let idByNumber = Dictionary(uniqueKeysWithValues: sourceIDs.map { ($0.value, $0.key) })
    usedSources[code] = Set(compiler.usedSourceIDs.compactMap { idByNumber[$0] })
}

// MARK: - Swift locale modules

/// Emits a Swift module per locale, embedding its corpus as a base64 `StaticString`.
///
/// This is how a corpus reaches a built binary. `Bundle.module` is avoided — it is the
/// most platform-fragile part of SPM. A `[UInt8]` literal is worse: 296 KB of array
/// literal does not finish type-checking in two minutes, where the equivalent base64
/// string literal compiles in 0.07 seconds and decodes in about 0.2 ms.
func emitSwiftModule(
    code: String,
    bytes: [UInt8],
    chain: [String],
    sources: [String],
    coverage: (own: Int, resolvable: Int),
    into directory: URL
) throws {
    let module = moduleName(code)
    let inheritedFrom = chain.count > 1
        ? "; the rest arrive from \(chain.dropFirst().joined(separator: ", "))"
        : ", which is all of them — this corpus has nothing behind it"
    let percent = coverage.resolvable == 0
        ? 0
        : Int((Double(coverage.own) / Double(coverage.resolvable) * 100).rounded())
    let chainExpression = chain
        .map { $0 == code ? "corpus" : "\(moduleName($0)).corpus" }
        .joined(separator: ", ")

    let imports = Set(chain.filter { $0 != code }.map(moduleName)).sorted()
    let importLines = (["import Decoy"] + imports.map { "import \($0)" }).joined(separator: "\n")

    let source = """
        // Generated by decoy-compile-corpus. Do not edit.
        //
        // Corpus for locale `\(code)`, derived from:
        //   \(sources.isEmpty ? "no attributed sources" : sources.joined(separator: ", "))
        //
        // These are the sources this locale's chain draws on, not every source Decoy
        // compiles — the header used to list all of them, so this file claimed to be
        // derived from a Persian spellchecker regardless of the language. A table merged
        // from several upstreams is credited to its primary here; NOTICE, generated from
        // the provenance chunk, is the complete record.
        // Regenerate with:
        //   swift run decoy-compile-corpus <intermediate-dir> Corpus/binary \\
        //     --emit-swift Sources --locales <codes>

        \(importLines)

        public enum \(module) {

            /// The compiled corpus for this locale alone, without its fallback chain.
            public static let corpus: Corpus = {
                guard let bytes = Base64.decode(payload) else {
                    fatalError("\(module): embedded corpus is not valid base64")
                }
                do {
                    return try Corpus(bytes: bytes)
                } catch {
                    fatalError("\(module): embedded corpus failed to load — \\(error)")
                }
            }()

            /// This locale with its fallback chain: \(chain.joined(separator: " -> ")).
            ///
            /// Defines \(coverage.own) of the \(coverage.resolvable) language-bearing
            /// paths in its chain (\(percent)%)\(inheritedFrom).
            ///
            /// Measured from the compiled blobs, so it describes what shipped rather than
            /// an intention. `locale.fallbackWarning()` is the same fact as a value, and
            /// `decoy-inspect --coverage Corpus/binary` is the whole table.
            public static let locale = LocaleCorpus(code: "\(code)", chain: [\(chainExpression)])

            private static let payload: StaticString = "\(Base64.encode(bytes))"
        }

        """

    let folder = directory.appendingPathComponent(module)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try source.write(
        to: folder.appendingPathComponent("\(module).swift"),
        atomically: true,
        encoding: .utf8
    )
}

if let swiftDirectory = options.emitSwift {
    let wanted = manifest.closure(over: options.swiftLocales)
    guard !wanted.isEmpty else { fail("--emit-swift requires --locales") }

    // A module SwiftPM does not know about is not a module: `--emit-swift --locales
    // pt_BR` wrote `Sources/DecoyLocalePT_BR/` with no matching target, so the directory
    // compiled nothing and importing it failed with an error naming neither the flag nor
    // the manifest.
    //
    // Reported *after* writing, not before. Refusing to write until the target exists
    // reads as the safer order and is unbuildable: SwiftPM will not compile anything —
    // including this compiler — while a declared target has no directory, so adding the
    // line first means the command that creates the directory can no longer run. Emit,
    // then say what is left to do. A mistyped code cannot get this far; `closure(over:)`
    // drops codes the roster does not know, which leaves `--locales` empty.
    //
    // A text scan rather than a parse: `Package.swift` is a program, and shelling out to
    // SwiftPM to ask what targets exist would be a far larger dependency than reading the
    // one array that names them.
    let packageURL = swiftDirectory.deletingLastPathComponent()
        .appendingPathComponent("Package.swift")
    func undeclaredTargets() -> [String] {
        guard let text = try? String(contentsOf: packageURL, encoding: .utf8),
            let start = text.range(of: "let locales:"),
            let end = text.range(of: "\n]", range: start.upperBound..<text.endIndex)
        else { return [] }
        let declared = Set(
            text[start.upperBound..<end.lowerBound]
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard let open = line.firstIndex(of: "\""),
                        let close = line[line.index(after: open)...].firstIndex(of: "\"")
                    else { return nil }
                    return String(line[line.index(after: open)..<close])
                }
        )
        return wanted.filter { !declared.contains(moduleSuffix($0)) }
    }

    var emittedBytes = 0
    for code in wanted {
        guard let bytes = compiled[code], let chain = manifest.locales[code]?.chain else {
            fail("cannot emit \(code): it was not compiled")
        }
        // The union over the chain: `de_AT` resolves through `de` and `base`, so its
        // module is derived from what those carry as much as from its own tables.
        let chainSources = Set(chain.flatMap { usedSources[$0] ?? [] }).sorted()

        // Measured from the blobs rather than taken from the compiler's own bookkeeping,
        // so the number in the module describes what shipped.
        let chainCorpora = try chain.map { try Corpus(bytes: compiled[$0] ?? []) }
        let resolved = LocaleCorpus(code: code, chain: chainCorpora)
        try emitSwiftModule(
            code: code,
            bytes: bytes,
            chain: chain,
            sources: chainSources,
            coverage: (try resolved.nativePaths.count, try resolved.languageBearingPathCount),
            into: swiftDirectory
        )
        emittedBytes += bytes.count
    }
    print("swift modules   : \(wanted.map(moduleName).joined(separator: ", "))")
    print("  embedding     : \(emittedBytes / 1024) KB of corpus")

    let undeclared = undeclaredTargets()
    if !undeclared.isEmpty {
        // The exact lines, not a description of them. The chain has to be right and in
        // order, and it is already known here — making the reader reconstruct it from the
        // manifest is the step where this goes wrong.
        let lines = undeclared.map { code -> String in
            let chain = (manifest.locales[code]?.chain ?? []).dropFirst()
                .map { "\"\(moduleSuffix($0))\"" }
                .joined(separator: ", ")
            return "    (\"\(moduleSuffix(code))\", [\(chain)]),"
        }
        print(
            """

            ── one step left ──────────────────────────────────────────────────
            \(undeclared.map(moduleName).joined(separator: ", ")) \
            \(undeclared.count == 1 ? "was" : "were") written, but \
            \(packageURL.lastPathComponent) declares no such target, so \
            \(undeclared.count == 1 ? "it compiles" : "they compile") nothing and \
            cannot be imported.

            Add to the `locales` array in \(packageURL.lastPathComponent):

            \(lines.joined(separator: "\n"))

            Order is the fallback chain, most specific first. `LocaleModuleTests`
            fails until this is done.
            ───────────────────────────────────────────────────────────────────
            """
        )
    }
}

print("sources         : \(manifest.provenance)")
print("corpus version  : \(corpusVersion)")
print("locales compiled: \(codes.count)")
print("JSON in         : \(totalJSON / 1024) KB")
print("binary out      : \(totalBytes / 1024) KB")

if !allSkipped.isEmpty {
    print("\nskipped \(allSkipped.count) entries:")
    for entry in allSkipped.prefix(20) { print("  \(entry)") }
    if allSkipped.count > 20 { print("  … and \(allSkipped.count - 20) more") }
}
