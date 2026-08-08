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
    private var models: [ModelSpec] = []
    private var sources: [SourceSpec] = []
    private var indexEntries: [IndexEntry] = []

    private struct StringTableSpec {
        var indices: [UInt32]
        var weights: [UInt32]?
        var sourceID: UInt32
    }

    /// A trained n-gram, as handed in. Encoded at `build()` like everything else.
    private struct ModelSpec {
        let order: Int
        /// Alphabet index 0 is the end-of-word sentinel and interns as the empty string.
        let alphabet: [UInt32]
        /// Sorted by packed key, which is what makes the index binary-searchable.
        let contexts: [(key: UInt64, transitions: [(symbol: UInt16, weight: UInt32)])]
        let filterHashCount: Int
        let filterBits: [UInt8]
        let sourceID: UInt32
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
        var copyright: UInt32
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
                retrieved: intern(""),
                copyright: intern("")
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
        retrieved: String,
        copyright: String = ""
    ) -> UInt32 {
        sources.append(
            SourceSpec(
                id: intern(id),
                license: intern(license),
                url: intern(url),
                version: intern(version),
                retrieved: intern(retrieved),
                copyright: intern(copyright)
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

    /// Adds a trained character-level n-gram.
    ///
    /// `contexts` maps a symbol sequence to the distribution over what follows it, with
    /// symbol 0 meaning end-of-word. Weights are given individually and made cumulative
    /// here, because a caller thinking in counts should not have to think in prefix sums.
    ///
    /// `filterBits` is a Bloom filter over the training set. It is not optional in
    /// practice: without it the sampler cannot promise that a generated name is not a
    /// real one, which is the difference between fake data and undisclosed PII.
    @discardableResult
    public mutating func addModel(
        order: Int,
        alphabet: [String],
        contexts: [(key: UInt64, transitions: [(symbol: UInt16, weight: UInt32)])],
        filterHashCount: Int,
        filterBits: [UInt8],
        source: UInt32 = 0
    ) -> UInt32 {
        precondition(order >= 2 && order <= NGramModel.maxOrder, "order must be 2...8")
        precondition(
            alphabet.count >= 1 && alphabet.count <= NGramModel.maxAlphabet,
            "the alphabet must be 1...255 symbols, including the sentinel"
        )
        precondition(alphabet[0].isEmpty, "alphabet index 0 is the end-of-word sentinel")
        precondition(
            contexts.allSatisfy { !$0.transitions.isEmpty },
            "a context with no transitions would be a dead end in the walk"
        )

        models.append(
            ModelSpec(
                order: order,
                alphabet: alphabet.map { intern($0) },
                contexts: contexts.sorted { $0.key < $1.key },
                filterHashCount: filterHashCount,
                filterBits: filterBits,
                sourceID: source
            )
        )
        return UInt32(models.count - 1)
    }

    // MARK: - Index

    public mutating func index(_ path: String, stringTable id: UInt32) {
        addIndexEntry(path, kind: 1, tableID: id)
    }

    public mutating func index(_ path: String, compositeTable id: UInt32) {
        addIndexEntry(path, kind: 2, tableID: id)
    }

    public mutating func index(_ path: String, model id: UInt32) {
        addIndexEntry(path, kind: 3, tableID: id)
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
        let modelChunk = buildModels()
        let provenanceChunk = buildProvenance()
        let indexChunk = buildIndex()

        var payloads: [(kind: UInt32, payload: [UInt8])] = [
            (ChunkKind.stringArena.rawValue, arena),
            (ChunkKind.stringTables.rawValue, stringTablesChunk),
            (ChunkKind.compositeTables.rawValue, compositeChunk),
            (ChunkKind.provenance.rawValue, provenanceChunk),
            (ChunkKind.index.rawValue, indexChunk),
        ]
        // Omitted entirely when nothing trained one, so a corpus without models is
        // byte-identical to one built before models existed.
        if !models.isEmpty {
            payloads.append((ChunkKind.models.rawValue, modelChunk))
        }
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

    /// How many strings sit between indexed positions in the arena.
    ///
    /// Sets the space/time trade directly: a checkpoint costs 4 bytes and bounds the
    /// forward scan on lookup. At 16 the index costs a quarter of a byte per string
    /// and no lookup skips more than 15 length prefixes.
    static let checkpointInterval = 16

    private func buildArena() -> [UInt8] {
        var body = [UInt8]()
        var checkpoints = [UInt32]()

        for (index, string) in internedStrings.enumerated() {
            if index % Self.checkpointInterval == 0 {
                checkpoints.append(UInt32(body.count))
            }
            let utf8 = Array(string.utf8)
            if utf8.count < Int(Arena.escape) {
                body.append(UInt8(utf8.count))
            } else {
                body.append(Arena.escape)
                body.appendLE(UInt32(utf8.count))
            }
            body.append(contentsOf: utf8)
        }

        var out = [UInt8]()
        out.appendLE(UInt32(internedStrings.count))
        out.appendLE(UInt32(Self.checkpointInterval))
        out.appendLE(UInt32(checkpoints.count))
        for checkpoint in checkpoints { out.appendLE(checkpoint) }
        out.append(contentsOf: body)
        return out
    }

    /// Encodes every model. See ``NGramModel`` for the layout and why it is that shape.
    private func buildModels() -> [UInt8] {
        var bodies = [[UInt8]]()
        for model in models {
            var body = [UInt8]()
            body.appendLE(model.sourceID)
            body.appendLE(UInt32(model.order))
            body.appendLE(UInt32(model.alphabet.count))
            for symbol in model.alphabet { body.appendLE(symbol) }
            body.appendLE(UInt32(model.contexts.count))

            // Transitions are laid out first so their offsets are known while the index
            // is written, which is the same reason the chunk directory precedes the
            // chunk bodies.
            var transitions = [UInt8]()
            var index = [UInt8]()
            for context in model.contexts {
                index.appendLE(context.key)
                index.appendLE(UInt32(transitions.count))
                index.appendLE(UInt32(context.transitions.count))

                // Cumulative weights are stored as `u16`, which halves the transition
                // blob — it is the bulk of a model, 22,000 entries for English surnames.
                // A context whose counts exceed 65,535 is scaled down proportionally,
                // with every non-zero weight kept at least 1 so a rare transition cannot
                // be silently deleted by rounding. Sampling only needs the ratios.
                let total = context.transitions.reduce(0) { $0 + UInt64($1.weight) }
                let scale = total > UInt64(UInt16.max) ? total : UInt64(UInt16.max)
                var cumulative: UInt16 = 0
                for transition in context.transitions {
                    let scaled = UInt16(
                        Swift.max(
                            1,
                            UInt64(transition.weight) * UInt64(UInt16.max) / scale))
                    cumulative = cumulative &+ scaled
                    transitions.appendLE(transition.symbol)
                    transitions.appendLE(cumulative)
                }
            }
            body.append(contentsOf: index)
            body.append(contentsOf: transitions)
            body.appendLE(UInt32(model.filterHashCount))
            body.appendLE(UInt32(model.filterBits.count))
            body.append(contentsOf: model.filterBits)
            bodies.append(body)
        }
        return packTables(bodies)
    }

    private func buildStringTables() -> [UInt8] {
        var bodies = [[UInt8]]()
        for table in stringTables {
            // Interning happens in insertion order, so a table's strings land in
            // consecutive arena slots except where a string was already seen. Encoding
            // the result as runs matters more than it sounds: an all-or-nothing scheme
            // lets a single repeat in a 2,240-entry table force every index to be
            // stored, and only ~6% of entries are repeats.
            let runs = Self.runs(in: table.indices)

            var flags: UInt32 = 0
            if table.weights != nil { flags |= 1 }

            var body = [UInt8]()
            body.appendLE(UInt32(table.indices.count))

            if runs.count == 1 {
                flags |= 2  // contiguous: the start index alone describes the table
                body.appendLE(flags)
                body.appendLE(table.sourceID)
                body.appendLE(runs[0].arena)
            } else if runs.count * 3 < table.indices.count {
                flags |= 4  // runs are smaller than one index per entry
                body.appendLE(flags)
                body.appendLE(table.sourceID)
                body.appendLE(UInt32(runs.count))
                for run in runs {
                    body.appendLE(run.logical)
                    body.appendLE(run.arena)
                    body.appendLE(run.length)
                }
            } else {
                body.appendLE(flags)
                body.appendLE(table.sourceID)
                body.appendLE(UInt32(0))
                for index in table.indices { body.appendLE(index) }
            }

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

    /// Collapses arena indices into maximal ascending consecutive runs.
    ///
    /// Each run records where it starts in the table, where it starts in the arena,
    /// and how long it is, so a reader can binary-search rather than walk.
    private static func runs(
        in indices: [UInt32]
    ) -> [(logical: UInt32, arena: UInt32, length: UInt32)] {
        var result: [(logical: UInt32, arena: UInt32, length: UInt32)] = []
        for (position, index) in indices.enumerated() {
            if let last = result.last, index == last.arena &+ last.length {
                result[result.count - 1].length += 1
            } else {
                result.append((logical: UInt32(position), arena: index, length: 1))
            }
        }
        return result
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
            // The slot the format reserved from the start. A copyright holder is what a
            // licence notice actually needs, and it fits here without a version bump or
            // a change to the 24-byte stride.
            out.appendLE(source.copyright)
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
