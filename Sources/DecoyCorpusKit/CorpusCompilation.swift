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
        /// The upstream's own copyright line, verbatim. Empty where it states none.
        public let copyright: String?
        public let url: String
        public let version: String
        public let retrieved: String

        public init(
            id: String, license: String, copyright: String? = nil,
            url: String, version: String, retrieved: String
        ) {
            self.id = id
            self.license = license
            self.copyright = copyright
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

    /// Object nodes whose *keys* are data, declared by the adapter that produced them.
    ///
    /// The compiler emits a `__keys` table for these and for nothing else. It used to
    /// emit one under every object node, which was 2,225 tables of which one is read.
    public let keyTables: [String]?

    /// The sources to register.
    ///
    /// The fallback here used to synthesise a faker-js record from `fakerVersion` and
    /// `extractedAt`, for manifests written before faker-js became an adapter like any
    /// other. No such manifest can be produced any more — `run.mjs` is the only writer
    /// and has emitted `sources` since — so the branch was unreachable and the two
    /// fields it read were decoded from nothing.
    public var sourceRecords: [SourceRecord] { sources ?? [] }

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
        "\(sourceSummary); generated \(generatedAt ?? "unknown")"
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

    public init(
        attribution: [String: String],
        defaultSourceID: UInt32,
        sourceIDs: [String: UInt32],
        keyTables: Set<String> = []
    ) {
        self.attribution = attribution
        self.defaultSourceID = defaultSourceID
        self.sourceIDs = sourceIDs
        self.keyTables = keyTables
    }

    /// Path suffix under which an object node's own keys are stored.
    public static let keysSuffix = "__keys"

    /// Per-path attribution, so a corpus assembled from several adapters records which
    /// upstream each field actually came from rather than stamping them all alike.
    public let attribution: [String: String]
    /// Used for paths no adapter claimed, such as the synthetic `__keys` tables.
    public let defaultSourceID: UInt32
    public let sourceIDs: [String: UInt32]

    /// Object nodes whose keys are data, declared by the adapters that produce them.
    ///
    /// Empty by default, which means no `__keys` tables at all. That is the right
    /// default: emitting one everywhere produced 2,225 tables across the corpus of which
    /// exactly one — `system.mime_type.__keys` — is ever read, and 1,015 of them held
    /// the single string `"extensions"`.
    public let keyTables: Set<String>

    public private(set) var stats = Stats()

    /// The sources this locale's own tables were actually attributed to.
    ///
    /// Every locale's provenance chunk registers all twenty-eight sources, because the
    /// blob records what the corpus was built from. That is right for the blob and wrong
    /// for a module header: `DecoyLocaleJA` credited Lilak, a Persian spellchecker
    /// dictionary that contributes nothing to Japanese, alongside twenty-six others it
    /// never touches.
    public private(set) var usedSourceIDs: Set<UInt32> = []

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

    /// What the compiler could not represent.
    ///
    /// Only `skipped` is reported. The four counters beside it — string, weighted and
    /// composite tables, and nulls — were incremented at eleven call sites and read at
    /// none, which made them look like a summary somebody was consuming.
    public struct Stats {
        public var skipped: [String] = []
    }

    public mutating func emit(path: String, value: JSONValue, into builder: inout CorpusBuilder) {
        // Recorded here rather than at each `addStringTable` call: every emission —
        // scalar, array, weighted, composite and the recursive object walk — passes
        // through this one method, so one line cannot fall out of step with five.
        usedSourceIDs.insert(sourceID(for: path))

        switch value {
        case .null:
            // Recorded rather than omitted: an explicit null blocks locale fallback.
            builder.indexNull(path)

        case .string, .number, .bool:
            guard let string = value.asString else { return }
            builder.index(path, stringTable: builder.addStringTable([string], source: sourceID(for: path)))

        case .object(let members) where members["__model"] != nil:
            // A trained n-gram rather than a node to walk into. Marked with a reserved
            // key instead of inferred from shape, because a model *is* an object of
            // arrays and guessing would make an ordinary contribution that happened to
            // have the right keys compile into something unreadable.
            emitModel(path: path, value: members["__model"]!, into: &builder)

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

            // Some data is keyed *by* the values you want to draw: `system.mime_type`
            // is a map from "application/json" to its extensions, so the media types
            // themselves are the object's keys and would otherwise be unreachable.
            //
            // Only for nodes an adapter has declared. Emitting one everywhere is not a
            // harmless over-supply — `person.first_name` is an object too, and its keys
            // are `generic`, `female` and `male`, so a `__keys` table there offers
            // "female" as something to draw.
            if !path.isEmpty && !keys.isEmpty && keyTables.contains(path) {
                let table = builder.addStringTable(keys, source: sourceID(for: path))
                builder.index("\(path).\(LocaleCompiler.keysSuffix)", stringTable: table)
            }

        case .array(let items):
            emitArray(path: path, items: items, into: &builder)
        }
    }

    /// Encodes a `__model` object into the corpus's model chunk.
    ///
    /// The intermediate carries the trained counts rather than the packed bytes, so the
    /// binary layout stays a decision this compiler makes. The trainer's job is the
    /// statistics; encoding them is not its business, and a pipeline emitting raw corpus
    /// bytes would have to be re-run for a format change it has nothing to do with.
    private mutating func emitModel(
        path: String,
        value: JSONValue,
        into builder: inout CorpusBuilder
    ) {
        guard let model = value.asObject,
            let order = model["order"]?.asNumber.map(Int.init),
            let alphabet = model["alphabet"]?.asArray?.compactMap(\.asString),
            let rawContexts = model["contexts"]?.asArray,
            let minLength = model["minLength"]?.asNumber.map(Int.init),
            let maxLength = model["maxLength"]?.asNumber.map(Int.init),
            let hashCount = model["filterHashCount"]?.asNumber.map(Int.init),
            let filter = model["filterBits"]?.asString
        else {
            stats.skipped.append("\(path) (malformed model)")
            return
        }

        // Base64 rather than an array of numbers: the filter for English surnames is
        // 29 KB, which is 100 KB of decimal digits and commas in the intermediate.
        guard let bits = Base64.decode(Array(filter.utf8)) else {
            stats.skipped.append("\(path) (model filter is not base64)")
            return
        }

        var contexts: [(key: UInt64, transitions: [(symbol: UInt16, weight: UInt32)])] = []
        contexts.reserveCapacity(rawContexts.count)
        for entry in rawContexts {
            // The key is a string because a u64 context key does not survive a JSON
            // number: JavaScript would round it and the context would land in the wrong
            // place in a sorted index, which reads as a model that has simply forgotten
            // things.
            guard let object = entry.asObject,
                let key = object["key"]?.asString.flatMap(UInt64.init),
                let transitions = object["transitions"]?.asArray
            else {
                stats.skipped.append("\(path) (malformed context)")
                return
            }
            let parsed = transitions.compactMap { item -> (UInt16, UInt32)? in
                guard let pair = item.asObject,
                    let symbol = pair["symbol"]?.asNumber.map({ UInt16($0) }),
                    let weight = pair["weight"]?.asNumber.map({ UInt32($0) })
                else { return nil }
                return (symbol, weight)
            }
            guard parsed.count == transitions.count, !parsed.isEmpty else {
                stats.skipped.append("\(path) (malformed transition)")
                return
            }
            contexts.append((key, parsed))
        }

        // Optional so a model can be compiled before a screen exists for its language;
        // `decoy-validate` is where "this model ships without a screen" should be caught,
        // not here, because a compiler that refuses is a compiler someone works around.
        let blockHashCount = model["blockHashCount"]?.asNumber.map(Int.init) ?? 0
        let blockMinLength = model["blockMinLength"]?.asNumber.map(Int.init) ?? 4
        let blockBits =
            model["blockBits"]?.asString.flatMap { Base64.decode(Array($0.utf8)) } ?? []

        let id = builder.addModel(
            order: order,
            minLength: minLength,
            maxLength: maxLength,
            alphabet: alphabet,
            contexts: contexts,
            filterHashCount: hashCount,
            filterBits: bits,
            blockHashCount: blockHashCount,
            blockMinLength: blockMinLength,
            blockBits: blockBits,
            source: sourceID(for: path)
        )
        builder.index(path, model: id)
    }

    private mutating func emitArray(
        path: String,
        items: [JSONValue],
        into builder: inout CorpusBuilder
    ) {
        guard let first = items.first else {
            builder.index(path, stringTable: builder.addStringTable([], source: sourceID(for: path)))
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
    }
}
