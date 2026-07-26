/// Builds a binary corpus.
///
/// Lives in the Foundation-free module rather than in the compiler tool, because
/// registering a custom corpus is a supported use: domain-specific data — medical
/// codes, tickers, SKUs — should not require forking Decoy or running Node.
///
/// See `docs/corpus-format.md` for the layout this produces.
public struct CorpusBuilder {

    private var version: CorpusVersion
    private var internedStrings: [String] = []
    private var internTable: [String: UInt32] = [:]

    private var stringTables: [StringTableSpec] = []
    private var compositeTables: [CompositeTableSpec] = []
    private var sources: [SourceSpec] = []
    private var indexEntries: [IndexEntry] = []

    private struct StringTableSpec {
        var indices: [UInt32]
        var weights: [UInt32]?
        var sourceID: UInt32
    }

    private struct CompositeTableSpec {
        var fieldNames: [UInt32]
        var cells: [UInt32]
        var fieldCount: Int
        var rowCount: Int
        var sourceID: UInt32
    }

    private struct SourceSpec {
        var id: UInt32
        var license: UInt32
        var url: UInt32
        var version: UInt32
        var retrieved: UInt32
    }

    private struct IndexEntry {
        var hash: UInt64
        var key: UInt32
        var kind: UInt32
        var tableID: UInt32
    }

    public init(version: CorpusVersion) {
        self.version = version
        // Source 0 is reserved so every table can reference something, even when its
        // provenance is genuinely unknown.
        _ = intern("")
        sources.append(
            SourceSpec(
                id: intern("unattributed"),
                license: intern(""),
                url: intern(""),
                version: intern(""),
                retrieved: intern("")
            )
        )
    }

    // MARK: - Interning

    /// Returns the arena index for a string, adding it only if unseen.
    ///
    /// Deduplication is not incidental: across faker-js's 76 locales, 21.2% of string
    /// occurrences are repeats, and `de_AT` duplicates all 1,145 of `de`'s first names.
    private mutating func intern(_ string: String) -> UInt32 {
        if let existing = internTable[string] { return existing }
        let index = UInt32(internedStrings.count)
        internedStrings.append(string)
        internTable[string] = index
        return index
    }

    // MARK: - Content

    @discardableResult
    public mutating func addSource(
        id: String,
        license: String,
        url: String,
        version: String,
        retrieved: String
    ) -> UInt32 {
        sources.append(
            SourceSpec(
                id: intern(id),
                license: intern(license),
                url: intern(url),
                version: intern(version),
                retrieved: intern(retrieved)
            )
        )
        return UInt32(sources.count - 1)
    }

    @discardableResult
    public mutating func addStringTable(
        _ strings: [String],
        weights: [UInt32]? = nil,
        source: UInt32 = 0
    ) -> UInt32 {
        precondition(
            weights == nil || weights!.count == strings.count,
            "weights must align one-to-one with strings"
        )
        stringTables.append(
            StringTableSpec(
                indices: strings.map { intern($0) },
                weights: weights,
                sourceID: source
            )
        )
        return UInt32(stringTables.count - 1)
    }

    @discardableResult
    public mutating func addCompositeTable(
        fields: [String],
        rows: [[String]],
        source: UInt32 = 0
    ) -> UInt32 {
        precondition(!fields.isEmpty, "a composite table needs at least one field")
        precondition(
            rows.allSatisfy { $0.count == fields.count },
            "every row must supply exactly one value per field"
        )
        compositeTables.append(
            CompositeTableSpec(
                fieldNames: fields.map { intern($0) },
                cells: rows.flatMap { $0.map { intern($0) } },
                fieldCount: fields.count,
                rowCount: rows.count,
                sourceID: source
            )
        )
        return UInt32(compositeTables.count - 1)
    }

    // MARK: - Index

    public mutating func index(_ path: String, stringTable id: UInt32) {
        addIndexEntry(path, kind: 1, tableID: id)
    }

    public mutating func index(_ path: String, compositeTable id: UInt32) {
        addIndexEntry(path, kind: 2, tableID: id)
    }

    /// Records a key the locale explicitly defines as having no value.
    ///
    /// Distinct from omitting the key: this **blocks** fallback to a parent locale.
    /// Azerbaijani has no name prefixes, and inheriting English ones would put English
    /// honorifics on Azeri records.
    public mutating func indexNull(_ path: String) {
        addIndexEntry(path, kind: 0, tableID: 0)
    }

    private mutating func addIndexEntry(_ path: String, kind: UInt32, tableID: UInt32) {
        indexEntries.append(
            IndexEntry(
                hash: SeedDerivation.fnv1a(path),
                key: intern(path),
                kind: kind,
                tableID: tableID
            )
        )
    }

    // MARK: - Forward compatibility

    private var rawChunks: [(kind: UInt32, payload: [UInt8])] = []

    /// Attaches a chunk of an arbitrary kind.
    ///
    /// Exists so forward compatibility is testable rather than merely asserted: a
    /// reader must carry a corpus containing chunks it does not understand, or adding
    /// generative models later would break every previously shipped build. This is
    /// also the hook those model chunks will use.
    mutating func addRawChunk(kind: UInt32, payload: [UInt8]) {
        rawChunks.append((kind, payload))
    }

    // MARK: - Serialisation

    public func build() -> [UInt8] {
        let arena = buildArena()
        let stringTablesChunk = buildStringTables()
        let compositeChunk = buildCompositeTables()
        let provenanceChunk = buildProvenance()
        let indexChunk = buildIndex()

        var payloads: [(kind: UInt32, payload: [UInt8])] = [
            (ChunkKind.stringArena.rawValue, arena),
            (ChunkKind.stringTables.rawValue, stringTablesChunk),
            (ChunkKind.compositeTables.rawValue, compositeChunk),
            (ChunkKind.provenance.rawValue, provenanceChunk),
            (ChunkKind.index.rawValue, indexChunk),
        ]
        payloads.append(contentsOf: rawChunks)

        var out = [UInt8]()
        out.reserveCapacity(
            Corpus.headerSize + payloads.count * Corpus.directoryEntrySize
                + payloads.reduce(0) { $0 + $1.1.count }
        )

        out.append(contentsOf: Corpus.magic)
        out.appendLE(UInt16(Corpus.supportedFormatVersion))
        out.appendLE(UInt16(0))  // flags
        out.appendLE(version.major)
        out.appendLE(version.minor)
        out.appendLE(version.patch)
        out.appendLE(UInt16(0))  // reserved
        out.appendLE(UInt32(payloads.count))
        out.appendLE(UInt64(0))  // reserved

        // Chunk bodies follow the directory, so their offsets are known before writing.
        var cursor = Corpus.headerSize + payloads.count * Corpus.directoryEntrySize
        for (kind, payload) in payloads {
            out.appendLE(kind)
            out.appendLE(UInt32(0))  // id
            out.appendLE(UInt64(cursor))
            out.appendLE(UInt64(payload.count))
            cursor += payload.count
        }
        for (_, payload) in payloads {
            out.append(contentsOf: payload)
        }
        return out
    }

    private func buildArena() -> [UInt8] {
        var offsets = [UInt32]()
        offsets.reserveCapacity(internedStrings.count + 1)
        var body = [UInt8]()
        var running: UInt32 = 0
        for string in internedStrings {
            offsets.append(running)
            let utf8 = Array(string.utf8)
            body.append(contentsOf: utf8)
            running += UInt32(utf8.count)
        }
        offsets.append(running)

        var out = [UInt8]()
        out.appendLE(UInt32(internedStrings.count))
        for offset in offsets { out.appendLE(offset) }
        out.append(contentsOf: body)
        return out
    }

    private func buildStringTables() -> [UInt8] {
        var bodies = [[UInt8]]()
        for table in stringTables {
            var body = [UInt8]()
            body.appendLE(UInt32(table.indices.count))
            body.appendLE(UInt32(table.weights == nil ? 0 : 1))
            body.appendLE(table.sourceID)
            body.appendLE(UInt32(0))  // reserved
            for index in table.indices { body.appendLE(index) }
            if let weights = table.weights {
                for weight in weights { body.appendLE(weight) }
            }
            bodies.append(body)
        }
        return packTables(bodies)
    }

    private func buildCompositeTables() -> [UInt8] {
        var bodies = [[UInt8]]()
        for table in compositeTables {
            var body = [UInt8]()
            body.appendLE(UInt32(table.fieldCount))
            body.appendLE(UInt32(table.rowCount))
            body.appendLE(table.sourceID)
            body.appendLE(UInt32(0))  // reserved
            for name in table.fieldNames { body.appendLE(name) }
            for cell in table.cells { body.appendLE(cell) }
            bodies.append(body)
        }
        return packTables(bodies)
    }

    /// Writes a table count, a directory of relative offsets, then the bodies.
    private func packTables(_ bodies: [[UInt8]]) -> [UInt8] {
        var out = [UInt8]()
        out.appendLE(UInt32(bodies.count))
        var running: UInt64 = 0
        for body in bodies {
            out.appendLE(running)
            running += UInt64(body.count)
        }
        out.appendLE(running)  // terminator
        for body in bodies { out.append(contentsOf: body) }
        return out
    }

    private func buildProvenance() -> [UInt8] {
        var out = [UInt8]()
        out.appendLE(UInt32(sources.count))
        for source in sources {
            out.appendLE(source.id)
            out.appendLE(source.license)
            out.appendLE(source.url)
            out.appendLE(source.version)
            out.appendLE(source.retrieved)
            out.appendLE(UInt32(0))  // reserved
        }
        return out
    }

    private func buildIndex() -> [UInt8] {
        // Sorted by hash so the reader can binary-search; ties broken by key index to
        // keep the output byte-identical across builds of the same input.
        let sorted = indexEntries.sorted {
            $0.hash != $1.hash ? $0.hash < $1.hash : $0.key < $1.key
        }
        var out = [UInt8]()
        out.appendLE(UInt32(sorted.count))
        for entry in sorted {
            out.appendLE(entry.hash)
            out.appendLE(entry.key)
            out.appendLE(entry.kind)
            out.appendLE(entry.tableID)
            out.appendLE(UInt32(0))  // reserved
        }
        return out
    }
}

extension [UInt8] {
    /// Appends an integer in little-endian order, byte by byte.
    ///
    /// Matches `ByteReader`'s deliberately host-independent reads — writing through a
    /// pointer cast would embed the build machine's byte order in the artifact.
    mutating func appendLE<T: FixedWidthInteger & UnsignedInteger>(_ value: T) {
        for i in 0..<(T.bitWidth / 8) {
            append(UInt8(truncatingIfNeeded: value >> (8 * i)))
        }
    }
}
