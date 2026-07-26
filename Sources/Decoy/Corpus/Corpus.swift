/// A compiled locale corpus.
///
/// Loaded once and sliced thereafter — no runtime JSON parsing, and nothing reached
/// through `Bundle.module`, which is the most platform-fragile part of SPM and a
/// large share of Fakery's trouble off macOS.
///
/// See `docs/corpus-format.md` for the on-disk layout.
public struct Corpus: Sendable {

    /// The highest format version this build can read.
    public static let supportedFormatVersion: UInt16 = 1

    static let magic: [UInt8] = Array("DECOYBIN".utf8)
    static let headerSize = 32
    static let directoryEntrySize = 24

    private let reader: ByteReader
    private let arena: Arena
    private let chunks: [UInt32: Chunk]

    /// The version of the *data*, which is distinct from the library version.
    ///
    /// `generate(seed:)` is only reproducible with respect to a particular corpus, so
    /// this is part of the reproducibility contract rather than an implementation
    /// detail. Changing an existing value bumps `major`, because it silently changes
    /// every existing user's fixtures.
    public let version: CorpusVersion

    struct Chunk {
        let id: UInt32
        let offset: Int
        let length: Int
    }

    // MARK: - Loading

    public init(bytes: [UInt8]) throws {
        let reader = ByteReader(bytes)
        self.reader = reader

        for (i, expected) in Self.magic.enumerated() where try reader.u8(at: i) != expected {
            throw CorpusError.notADecoyCorpus
        }

        let formatVersion = try reader.u16(at: 8)
        guard formatVersion <= Self.supportedFormatVersion else {
            throw CorpusError.unsupportedFormatVersion(
                found: formatVersion,
                supported: Self.supportedFormatVersion
            )
        }

        self.version = CorpusVersion(
            major: try reader.u16(at: 12),
            minor: try reader.u16(at: 14),
            patch: try reader.u16(at: 16)
        )

        // Chunk directory. Unknown kinds are kept rather than rejected, so a reader
        // built today tolerates a corpus containing chunks it does not understand.
        let chunkCount = Int(try reader.u32(at: 20))
        var chunks = [UInt32: Chunk]()
        for i in 0..<chunkCount {
            let base = Self.headerSize + i * Self.directoryEntrySize
            let kind = try reader.u32(at: base)
            let offset = try reader.checkedInt(try reader.u64(at: base + 8), "chunk offset")
            let length = try reader.checkedInt(try reader.u64(at: base + 16), "chunk length")
            guard offset >= 0, length >= 0, offset + length <= reader.count else {
                throw CorpusError.malformed("chunk \(kind) extends past the end of the file")
            }
            chunks[kind] = Chunk(id: try reader.u32(at: base + 4), offset: offset, length: length)
        }
        self.chunks = chunks

        guard let arenaChunk = chunks[ChunkKind.stringArena.rawValue] else {
            throw CorpusError.missingChunk("string arena")
        }
        self.arena = try Arena(reader: reader, chunk: arenaChunk)

        guard chunks[ChunkKind.index.rawValue] != nil else {
            throw CorpusError.missingChunk("index")
        }
    }

    // MARK: - Lookup

    /// Resolves a dotted path such as `person.first_name.female`.
    ///
    /// Returns `nil` when the locale does not mention the key at all — the caller
    /// should then try the next locale in the fallback chain. A key the locale
    /// explicitly defines as null returns ``Entry/none`` instead, which **stops** the
    /// walk: Azerbaijani has no name prefixes, and falling back to English there would
    /// put English honorifics on Azeri records.
    public func lookup(_ path: String) throws -> Entry? {
        guard let chunk = chunks[ChunkKind.index.rawValue] else { return nil }
        let entryCount = Int(try reader.u32(at: chunk.offset))
        let base = chunk.offset + 4
        let target = SeedDerivation.fnv1a(path)

        // Binary search on the hash, then confirm against the arena, so a collision
        // degrades to a miss rather than to silently wrong data.
        var low = 0
        var high = entryCount - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let entryOffset = base + mid * 24
            let hash = try reader.u64(at: entryOffset)
            if hash < target {
                low = mid + 1
            } else if hash > target {
                high = mid - 1
            } else {
                if let entry = try resolveCollisions(
                    around: mid, base: base, count: entryCount, hash: target, path: path
                ) {
                    return entry
                }
                return nil
            }
        }
        return nil
    }

    /// Walks neighbours sharing a hash until the stored key actually matches.
    private func resolveCollisions(
        around index: Int,
        base: Int,
        count: Int,
        hash: UInt64,
        path: String
    ) throws -> Entry? {
        var first = index
        while first > 0, try reader.u64(at: base + (first - 1) * 24) == hash {
            first -= 1
        }
        var i = first
        while i < count, try reader.u64(at: base + i * 24) == hash {
            let entryOffset = base + i * 24
            if try arena.string(at: try reader.u32(at: entryOffset + 8)) == path {
                return try entry(
                    kind: try reader.u32(at: entryOffset + 12),
                    tableID: try reader.u32(at: entryOffset + 16)
                )
            }
            i += 1
        }
        return nil
    }

    private func entry(kind: UInt32, tableID: UInt32) throws -> Entry {
        switch kind {
        case 0: return .none
        case 1: return .strings(try stringTable(tableID))
        case 2: return .composite(try compositeTable(tableID))
        case 3: return .model(id: tableID)
        default: throw CorpusError.malformed("unknown index entry kind \(kind)")
        }
    }

    // MARK: - Tables

    func stringTable(_ id: UInt32) throws -> StringTable {
        let body = try tableBody(in: .stringTables, id: id)
        let entryCount = Int(try reader.u32(at: body))
        let flags = try reader.u32(at: body + 4)
        return StringTable(
            reader: reader,
            arena: arena,
            count: entryCount,
            hasWeights: flags & 1 != 0,
            sourceID: try reader.u32(at: body + 8),
            indicesOffset: body + 16,
            weightsOffset: body + 16 + entryCount * 4
        )
    }

    func compositeTable(_ id: UInt32) throws -> CompositeTable {
        let body = try tableBody(in: .compositeTables, id: id)
        let fieldCount = Int(try reader.u32(at: body))
        let rowCount = Int(try reader.u32(at: body + 4))
        return CompositeTable(
            reader: reader,
            arena: arena,
            fieldCount: fieldCount,
            rowCount: rowCount,
            sourceID: try reader.u32(at: body + 8),
            fieldNamesOffset: body + 16,
            cellsOffset: body + 16 + fieldCount * 4
        )
    }

    /// Locates one table within a chunk that stores a directory of table offsets.
    private func tableBody(in kind: ChunkKind, id: UInt32) throws -> Int {
        guard let chunk = chunks[kind.rawValue] else {
            throw CorpusError.missingChunk("\(kind)")
        }
        let tableCount = Int(try reader.u32(at: chunk.offset))
        guard Int(id) < tableCount else {
            throw CorpusError.malformed("table \(id) out of range in \(kind) (\(tableCount) tables)")
        }
        let directory = chunk.offset + 4
        let relative = try reader.u64(at: directory + Int(id) * 8)
        let offset = chunk.offset + 4 + (tableCount + 1) * 8
            + (try reader.checkedInt(relative, "table offset"))
        guard offset < chunk.offset + chunk.length else {
            throw CorpusError.malformed("table \(id) in \(kind) points past its chunk")
        }
        return offset
    }

    // MARK: - Provenance

    /// Where a table's data came from. No other faker records this, and without it a
    /// corpus cannot be audited, filtered by license, or checked for staleness.
    public func source(_ id: UInt32) throws -> Source? {
        guard let chunk = chunks[ChunkKind.provenance.rawValue] else { return nil }
        let count = Int(try reader.u32(at: chunk.offset))
        guard Int(id) < count else { return nil }
        let base = chunk.offset + 4 + Int(id) * 24
        return Source(
            id: try arena.string(at: try reader.u32(at: base)),
            license: try arena.string(at: try reader.u32(at: base + 4)),
            url: try arena.string(at: try reader.u32(at: base + 8)),
            version: try arena.string(at: try reader.u32(at: base + 12)),
            retrieved: try arena.string(at: try reader.u32(at: base + 16))
        )
    }

    /// The number of distinct strings in the shared arena.
    public var stringCount: Int { arena.count }
}

// MARK: - Supporting types

enum ChunkKind: UInt32 {
    case stringArena = 1
    case stringTables = 2
    case compositeTables = 3
    case provenance = 4
    case index = 5
    case models = 6
}

public struct CorpusVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: UInt16
    public let minor: UInt16
    public let patch: UInt16

    public init(major: UInt16, minor: UInt16, patch: UInt16) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: CorpusVersion, b: CorpusVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

public struct Source: Sendable, Equatable {
    public let id: String
    public let license: String
    public let url: String
    public let version: String
    public let retrieved: String
}

/// What a path resolves to.
public enum Entry: Sendable {
    /// The locale explicitly defines this key as having no value, which blocks
    /// fallback to a parent locale.
    case none
    case strings(StringTable)
    case composite(CompositeTable)
    /// Reserved for generative models; not yet produced by the compiler.
    case model(id: UInt32)
}

/// The shared, deduplicated string pool.
struct Arena: Sendable {
    private let reader: ByteReader
    private let offsetsBase: Int
    private let bytesBase: Int
    let count: Int

    init(reader: ByteReader, chunk: Corpus.Chunk) throws {
        self.reader = reader
        self.count = Int(try reader.u32(at: chunk.offset))
        self.offsetsBase = chunk.offset + 4
        self.bytesBase = offsetsBase + (count + 1) * 4

        // Validated once here rather than on every access: monotonic offsets are what
        // make each later slice safe without re-checking the neighbouring entry.
        var previous: UInt32 = 0
        for i in 0...count {
            let value = try reader.u32(at: offsetsBase + i * 4)
            guard value >= previous else {
                throw CorpusError.malformed("string arena offsets are not monotonic at \(i)")
            }
            previous = value
        }
        guard bytesBase + Int(previous) <= chunk.offset + chunk.length else {
            throw CorpusError.malformed("string arena bytes extend past the chunk")
        }
    }

    func string(at index: UInt32) throws -> String {
        guard Int(index) < count else {
            throw CorpusError.malformed("string index \(index) out of range (\(count) strings)")
        }
        let start = Int(try reader.u32(at: offsetsBase + Int(index) * 4))
        let end = Int(try reader.u32(at: offsetsBase + (Int(index) + 1) * 4))
        return try reader.string(at: bytesBase + start, length: end - start)
    }
}

/// A list of strings, optionally weighted.
public struct StringTable: Sendable {
    let reader: ByteReader
    let arena: Arena
    public let count: Int
    public let hasWeights: Bool
    public let sourceID: UInt32
    let indicesOffset: Int
    let weightsOffset: Int

    public var isEmpty: Bool { count == 0 }

    public func string(at index: Int) throws -> String {
        guard index >= 0, index < count else {
            throw CorpusError.malformed("string table index \(index) out of range (\(count))")
        }
        return try arena.string(at: try reader.u32(at: indicesOffset + index * 4))
    }

    /// The stored weight, or 1 for an unweighted table.
    public func weight(at index: Int) throws -> UInt32 {
        guard hasWeights else { return 1 }
        guard index >= 0, index < count else {
            throw CorpusError.malformed("weight index \(index) out of range (\(count))")
        }
        return try reader.u32(at: weightsOffset + index * 4)
    }

    /// Draws one entry, honouring weights when present.
    ///
    /// Weighted draws are what make generated data statistically plausible rather than
    /// merely varied — real name distributions are heavily skewed, and uniform
    /// sampling produces collision rates no production dataset would show.
    public func draw(using rng: inout some RandomNumberGenerator) throws -> String? {
        guard count > 0 else { return nil }
        guard hasWeights else {
            return try string(at: Int(rng.draw(below: UInt64(count))))
        }

        var total: UInt64 = 0
        for i in 0..<count { total &+= UInt64(try weight(at: i)) }
        guard total > 0 else { return try string(at: Int(rng.draw(below: UInt64(count)))) }

        var remaining = rng.draw(below: total)
        for i in 0..<count {
            let w = UInt64(try weight(at: i))
            if remaining < w { return try string(at: i) }
            remaining &-= w
        }
        return try string(at: count - 1)
    }
}

/// Rows of correlated fields, drawn together.
///
/// A country is `(alpha2, alpha3, numeric)`. Storing three parallel lists and drawing
/// from each independently produces countries that do not exist — the same failure
/// that yields `city: "Boston", state: "CA", postcode: "10001"`.
public struct CompositeTable: Sendable {
    let reader: ByteReader
    let arena: Arena
    public let fieldCount: Int
    public let rowCount: Int
    public let sourceID: UInt32
    let fieldNamesOffset: Int
    let cellsOffset: Int

    public var isEmpty: Bool { rowCount == 0 }

    public func fieldName(_ index: Int) throws -> String {
        guard index >= 0, index < fieldCount else {
            throw CorpusError.malformed("field index \(index) out of range (\(fieldCount))")
        }
        return try arena.string(at: try reader.u32(at: fieldNamesOffset + index * 4))
    }

    public func value(row: Int, field: Int) throws -> String {
        guard row >= 0, row < rowCount, field >= 0, field < fieldCount else {
            throw CorpusError.malformed("cell (\(row), \(field)) out of range")
        }
        let cell = row * fieldCount + field
        return try arena.string(at: try reader.u32(at: cellsOffset + cell * 4))
    }

    /// Returns a whole row as `field name -> value`, keeping correlated fields together.
    public func row(_ index: Int) throws -> [String: String] {
        guard index >= 0, index < rowCount else {
            throw CorpusError.malformed("row \(index) out of range (\(rowCount))")
        }
        var result = [String: String](minimumCapacity: fieldCount)
        for field in 0..<fieldCount {
            result[try fieldName(field)] = try value(row: index, field: field)
        }
        return result
    }

    public func drawRow(using rng: inout some RandomNumberGenerator) throws -> [String: String]? {
        guard rowCount > 0 else { return nil }
        return try row(Int(rng.draw(below: UInt64(rowCount))))
    }
}
