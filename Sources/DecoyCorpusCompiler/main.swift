import Decoy
import Foundation

/// Compiles the extractor's JSON into one binary corpus per locale.
///
/// Usage: `decoy-compile-corpus <extractor-out-dir> <output-dir> [--corpus-version X.Y.Z]`

// MARK: - Arguments

struct Options {
    var input: URL
    var output: URL
    var corpusVersion = CorpusVersion(major: 1, minor: 0, patch: 0)
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
        fail("usage: decoy-compile-corpus <extractor-out-dir> <output-dir> [--corpus-version X.Y.Z]")
    }
    var options = Options(
        input: URL(fileURLWithPath: positional[0]),
        output: URL(fileURLWithPath: positional[1])
    )
    if let version { options.corpusVersion = version }
    options.emitSwift = emitSwift
    options.swiftLocales = swiftLocales
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Manifest

struct Manifest: Decodable {
    struct Locale: Decodable {
        let chain: [String]
    }
    let locales: [String: Locale]
    let fakerVersion: String
    let extractedAt: String?

    /// Expands the requested locales to include every locale their chains reach.
    func closure(over requested: [String]) -> [String] {
        var needed = Set<String>()
        for code in requested {
            guard let locale = locales[code] else { continue }
            needed.formUnion(locale.chain)
        }
        return needed.sorted()
    }
}

// MARK: - Compilation

/// Walks a locale's JSON tree, emitting one index entry per leaf.
///
/// Paths are dotted (`person.first_name.female`) and nesting is followed to any
/// depth, so faker's `{ generic, female, male }` structure survives rather than being
/// flattened into one pool — which is the whole reason Decoy vendors faker-js.
struct LocaleCompiler {
    /// Path suffix under which an object node's own keys are stored.
    static let keysSuffix = "__keys"

    let sourceID: UInt32
    private(set) var stats = Stats()

    struct Stats {
        var stringTables = 0
        var weightedTables = 0
        var compositeTables = 0
        var nulls = 0
        var skipped: [String] = []
    }

    mutating func emit(path: String, value: JSONValue, into builder: inout CorpusBuilder) {
        switch value {
        case .null:
            // Recorded rather than omitted: an explicit null blocks locale fallback.
            builder.indexNull(path)
            stats.nulls += 1

        case .string, .number, .bool:
            guard let string = value.asString else { return }
            builder.index(path, stringTable: builder.addStringTable([string], source: sourceID))
            stats.stringTables += 1

        case .object(let members):
            // Sorted so the output is byte-identical across runs.
            let keys = members.keys.sorted()
            for key in keys {
                emit(
                    path: path.isEmpty ? key : "\(path).\(key)",
                    value: members[key]!,
                    into: &builder
                )
            }

            // Some of faker's data is keyed *by* the values you want to draw:
            // `system.mime_type` is a map from "application/json" to its extensions,
            // so the MIME types themselves are the object's keys and would otherwise
            // be unreachable. Emitting a keys table makes every object node drawable.
            if !path.isEmpty && !keys.isEmpty {
                let table = builder.addStringTable(keys, source: sourceID)
                builder.index("\(path).\(LocaleCompiler.keysSuffix)", stringTable: table)
                stats.stringTables += 1
            }

        case .array(let items):
            emitArray(path: path, items: items, into: &builder)
        }
    }

    private mutating func emitArray(
        path: String,
        items: [JSONValue],
        into builder: inout CorpusBuilder
    ) {
        guard let first = items.first else {
            builder.index(path, stringTable: builder.addStringTable([], source: sourceID))
            stats.stringTables += 1
            return
        }

        // Scalars: a plain list of values.
        if first.asObject == nil {
            let strings = items.compactMap(\.asString)
            guard strings.count == items.count else {
                stats.skipped.append("\(path) (mixed element types)")
                return
            }
            builder.index(path, stringTable: builder.addStringTable(strings, source: sourceID))
            stats.stringTables += 1
            return
        }

        let objects = items.compactMap(\.asObject)
        guard objects.count == items.count else {
            stats.skipped.append("\(path) (mixed element types)")
            return
        }

        // `{ value, weight }` is a weighted list, not a two-column record.
        if objects.allSatisfy({ $0["value"] != nil && $0["weight"] != nil }) {
            emitWeighted(path: path, objects: objects, into: &builder)
            return
        }

        emitComposite(path: path, objects: objects, into: &builder)
    }

    private mutating func emitWeighted(
        path: String,
        objects: [[String: JSONValue]],
        into builder: inout CorpusBuilder
    ) {
        var values: [String] = []
        var raw: [Double] = []
        for object in objects {
            guard
                let value = object["value"]?.asString,
                case .number(let weight)? = object["weight"]
            else {
                stats.skipped.append("\(path) (malformed weighted entry)")
                return
            }
            values.append(value)
            raw.append(weight)
        }

        // Scale fractional weights rather than rounding them to 1, which would
        // flatten the distribution the weights exist to express.
        let scale: Double = raw.allSatisfy { $0 == $0.rounded() } ? 1 : 1_000
        let weights = raw.map { UInt32(max(1, ($0 * scale).rounded())) }

        builder.index(
            path,
            stringTable: builder.addStringTable(values, weights: weights, source: sourceID)
        )
        stats.weightedTables += 1
    }

    private mutating func emitComposite(
        path: String,
        objects: [[String: JSONValue]],
        into builder: inout CorpusBuilder
    ) {
        // Union of keys, so a row missing an optional field does not drop the column
        // for every other row.
        var fields: [String] = []
        var seen = Set<String>()
        for object in objects {
            for key in object.keys.sorted() where seen.insert(key).inserted {
                fields.append(key)
            }
        }

        var rows: [[String]] = []
        rows.reserveCapacity(objects.count)
        for object in objects {
            rows.append(fields.map { object[$0]?.asString ?? "" })
        }

        builder.index(
            path,
            compositeTable: builder.addCompositeTable(fields: fields, rows: rows, source: sourceID)
        )
        stats.compositeTables += 1
    }
}

// MARK: - Driver

let options = parseArguments()
let fileManager = FileManager.default

let manifestURL = options.input.appendingPathComponent("manifest.json")
guard let manifestData = try? Data(contentsOf: manifestURL) else {
    fail("cannot read \(manifestURL.path) — run `npm run extract` in Tools/extractor first")
}
let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

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

    var builder = CorpusBuilder(version: options.corpusVersion)
    let sourceID = builder.addSource(
        id: "faker-js",
        license: "MIT",
        url: "https://github.com/faker-js/faker",
        version: manifest.fakerVersion,
        retrieved: manifest.extractedAt ?? "unknown"
    )

    var compiler = LocaleCompiler(sourceID: sourceID)
    compiler.emit(path: "", value: root, into: &builder)

    let bytes = builder.build()

    // Every blob is read back before being written. A corpus that cannot be loaded
    // is worse than a build failure, because it surfaces at a user's first call.
    let verified = try Corpus(bytes: bytes)
    guard verified.version == options.corpusVersion else {
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
        // Corpus for locale `\(code)`, derived from @faker-js/faker \
        \(manifest.fakerVersion) (MIT), retrieved \(manifest.extractedAt ?? "unknown").
        // Regenerate with:
        //   swift run decoy-compile-corpus Tools/extractor/out Corpus/binary \\
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

print("faker version   : \(manifest.fakerVersion)")
print("extracted       : \(manifest.extractedAt ?? "unknown")")
print("corpus version  : \(options.corpusVersion)")
print("locales compiled: \(codes.count)")
print("JSON in         : \(totalJSON / 1024) KB")
print("binary out      : \(totalBytes / 1024) KB")

if !allSkipped.isEmpty {
    print("\nskipped \(allSkipped.count) entries:")
    for entry in allSkipped.prefix(20) { print("  \(entry)") }
    if allSkipped.count > 20 { print("  … and \(allSkipped.count - 20) more") }
}
