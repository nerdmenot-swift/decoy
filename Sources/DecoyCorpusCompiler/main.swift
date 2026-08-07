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
func moduleName(_ code: String) -> String {
    "DecoyLocale" + (code == "base" ? "Base" : code.uppercased())
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

// MARK: - Manifest

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
            retrieved: record.retrieved
        )
    }
    guard let defaultSourceID = sourceIDs[manifest.sourceRecords[0].id] else {
        fail("\(code): no sources declared in the manifest")
    }

    var compiler = LocaleCompiler(
        attribution: manifest.attribution?[code] ?? [:],
        defaultSourceID: defaultSourceID,
        sourceIDs: sourceIDs
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
    manifest: Manifest,
    into directory: URL
) throws {
    let module = moduleName(code)
    let chainExpression = chain
        .map { $0 == code ? "corpus" : "\(moduleName($0)).corpus" }
        .joined(separator: ", ")

    let imports = Set(chain.filter { $0 != code }.map(moduleName)).sorted()
    let importLines = (["import Decoy"] + imports.map { "import \($0)" }).joined(separator: "\n")

    let source = """
        // Generated by decoy-compile-corpus. Do not edit.
        //
        // Corpus for locale `\(code)`, derived from \(manifest.provenance).
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

    var emittedBytes = 0
    for code in wanted {
        guard let bytes = compiled[code], let chain = manifest.locales[code]?.chain else {
            fail("cannot emit \(code): it was not compiled")
        }
        try emitSwiftModule(
            code: code,
            bytes: bytes,
            chain: chain,
            manifest: manifest,
            into: swiftDirectory
        )
        emittedBytes += bytes.count
    }
    print("swift modules   : \(wanted.map(moduleName).joined(separator: ", "))")
    print("  embedding     : \(emittedBytes / 1024) KB of corpus")
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
