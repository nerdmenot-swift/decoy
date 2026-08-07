import Decoy
import Foundation

// The compiler's testable core, split out of the executable so it can be imported.
//
// `LocaleCompiler.sourceID(for:)` in particular silently mislabelled 2,036 paths in
// `base` before it was fixed, and an executable target with top-level code cannot be
// imported by a test target -- so the rule that decides which licence covers which data
// had no test at all. Attribution is the one thing in this project that has to be right.

public struct Manifest: Decodable {
    public struct Locale: Decodable {
        public let chain: [String]
    }

    /// A pinned upstream the data was derived from.
    public struct SourceRecord: Decodable {
        public let id: String
        public let license: String
        public let url: String
        public let version: String
        public let retrieved: String

        public init(id: String, license: String, url: String, version: String, retrieved: String) {
            self.id = id
            self.license = license
            self.url = url
            self.version = version
            self.retrieved = retrieved
        }
    }

    public let locales: [String: Locale]

    /// Declared by the pipeline in `Tools/adapters/corpus-version.json`.
    public let corpusVersion: String?

    public let sources: [SourceRecord]?
    /// locale -> path -> source id.
    public let attribution: [String: [String: String]]?
    public let generatedAt: String?

    // Retained so a manifest written before faker-js became an adapter still compiles.
    // Costs two optional fields and removes a reason to keep an old blob around.
    public let fakerVersion: String?
    public let extractedAt: String?

    /// The sources to register, however the input described them.
    public var sourceRecords: [SourceRecord] {
        if let sources, !sources.isEmpty { return sources }
        return [
            SourceRecord(
                id: "faker-js",
                license: "MIT",
                url: "https://github.com/faker-js/faker",
                version: fakerVersion ?? "unknown",
                retrieved: extractedAt ?? "unknown"
            )
        ]
    }

    /// The version the pipeline declared, parsed.
    public var declaredCorpusVersion: CorpusVersion? {
        guard let parts = corpusVersion?.split(separator: ".").compactMap({ UInt16($0) }),
            parts.count == 3
        else { return nil }
        return CorpusVersion(major: parts[0], minor: parts[1], patch: parts[2])
    }

    /// A one-line provenance summary for generated source headers.
    ///
    /// Each source carries its own retrieval date, so this reports when the intermediate
    /// was *generated* — conflating the two would misdate the data itself.
    public var provenance: String {
        let date = generatedAt ?? extractedAt ?? "unknown"
        return "\(sourceSummary); generated \(date)"
    }

    /// The same summary without the generation date, for text that gets committed.
    ///
    /// The date belongs in a build log, not in a generated source file. It was
    /// interpolated into every locale module header, which made emission
    /// non-deterministic: CI re-emits the modules and diffs them, so the build failed on
    /// any day but the one the modules were committed. Committing again bought exactly
    /// one more day.
    ///
    /// Nothing is lost by dropping it — every source carries its own `retrieved` date,
    /// which is the date that says something about the data rather than about the machine
    /// that happened to run the compiler.
    public var sourceSummary: String {
        sourceRecords.map { "\($0.id) \($0.version) (\($0.license))" }
            .joined(separator: ", ")
    }

    /// Expands the requested locales to include every locale their chains reach.
    public func closure(over requested: [String]) -> [String] {
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
/// depth, so the `{ generic, female, male }` shape survives rather than being flattened
/// into one pool — which is what lets a name agree with the gender drawn beside it.
public struct LocaleCompiler {

    public init(attribution: [String: String], defaultSourceID: UInt32, sourceIDs: [String: UInt32]) {
        self.attribution = attribution
        self.defaultSourceID = defaultSourceID
        self.sourceIDs = sourceIDs
    }

    /// Path suffix under which an object node's own keys are stored.
    public static let keysSuffix = "__keys"

    /// Per-path attribution, so a corpus assembled from several adapters records which
    /// upstream each field actually came from rather than stamping them all alike.
    public let attribution: [String: String]
    /// Used for paths no adapter claimed, such as the synthetic `__keys` tables.
    public let defaultSourceID: UInt32
    public let sourceIDs: [String: UInt32]

    public private(set) var stats = Stats()

    /// Resolves a path to its source, falling back to the nearest claimed ancestor.
    ///
    /// An adapter claims `system.mime_type` and the compiler then emits hundreds of
    /// paths beneath it — one `extensions` table per media type, plus the `__keys`
    /// tables. Exact matching would attribute all of them to whichever source happened
    /// to be registered first, which is how a corpus ends up mislabelled in a way nobody
    /// notices until a licence audit.
    public func sourceID(for path: String) -> UInt32 {
        var candidate = Substring(path)
        while true {
            if let id = attribution[String(candidate)], let resolved = sourceIDs[id] {
                return resolved
            }
            guard let dot = candidate.lastIndex(of: ".") else { return defaultSourceID }
            candidate = candidate[..<dot]
        }
    }

    public struct Stats {
        public var stringTables = 0
        public var weightedTables = 0
        public var compositeTables = 0
        public var nulls = 0
        public var skipped: [String] = []
    }

    public mutating func emit(path: String, value: JSONValue, into builder: inout CorpusBuilder) {
        switch value {
        case .null:
            // Recorded rather than omitted: an explicit null blocks locale fallback.
            builder.indexNull(path)
            stats.nulls += 1

        case .string, .number, .bool:
            guard let string = value.asString else { return }
            builder.index(path, stringTable: builder.addStringTable([string], source: sourceID(for: path)))
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
                let table = builder.addStringTable(keys, source: sourceID(for: path))
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
            builder.index(path, stringTable: builder.addStringTable([], source: sourceID(for: path)))
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
            builder.index(path, stringTable: builder.addStringTable(strings, source: sourceID(for: path)))
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
            stringTable: builder.addStringTable(values, weights: weights, source: sourceID(for: path))
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
            compositeTable: builder.addCompositeTable(fields: fields, rows: rows, source: sourceID(for: path))
        )
        stats.compositeTables += 1
    }
}
