/// A compiled locale corpus.
///
/// Loaded once and sliced thereafter — no runtime JSON parsing, and nothing reached
/// through `Bundle.module`, which is the most platform-fragile part of SPM and a
/// large share of Fakery's trouble off macOS.
///
/// See `docs/corpus-format.md` for the on-disk layout.
public struct Corpus: Sendable {

    /// The format version this build reads.
    ///
    /// Version 2 replaced version 1's fixed-width arena offsets and per-entry table
    /// indices with length-prefixed strings and contiguous runs, which cut roughly
    /// 40% off a compiled locale.
    public static let supportedFormatVersion: UInt16 = 2

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

        // Exact match, not `<=`. An older blob's chunks would parse as garbage rather
        // than fail, and reading a stale corpus silently is worse than refusing it.
        // Backward compatibility becomes worth building once a version has shipped.
        let formatVersion = try reader.u16(at: 8)
        guard formatVersion == Self.supportedFormatVersion else {
            throw CorpusError.unsupportedFormatVersion(
                found: formatVersion,
                supported: Self.supportedFormatVersion
            )
        }

        // Documented as "reserved, must be 0" at three offsets, and never read until
        // now. A reserved field nobody checks is not reserved — it is a field a future
        // writer can start using while every existing reader silently ignores it, which
        // is the failure the reservation was meant to prevent.
        let reserved =
            UInt64(try reader.u16(at: 10)) | UInt64(try reader.u16(at: 18))
            | (try reader.u64(at: 24))
        guard reserved == 0 else {
            throw CorpusError.malformed("a reserved header field is non-zero")
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

        guard let indexChunk = chunks[ChunkKind.index.rawValue] else {
            throw CorpusError.missingChunk("index")
        }

        // `lookup` binary-searches this, so an unsorted index does not fail — it returns
        // "no such path" for data that is right there, and the locale falls through to
        // its parent. That is a wrong *value*, silently, which is the one failure mode
        // this format cannot tolerate. Documented as a load-time check since v1 and
        // never actually performed.
        //
        // O(n) over 24-byte entries: 2,072 of them in the largest blob, so under a
        // microsecond against the 0.2 ms the base64 decode already costs.
        let indexCount = Int(try reader.u32(at: indexChunk.offset))
        var previous: UInt64 = 0
        for i in 0..<indexCount {
            let hash = try reader.u64(at: indexChunk.offset + 4 + i * 24)
            guard hash >= previous else {
                throw CorpusError.malformed("index is not sorted by key hash")
            }
            previous = hash
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
        case 0: return .explicitlyEmpty
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
        let extra = try reader.u32(at: body + 12)

        let layout: StringTable.Layout
        let payloadSize: Int
        if flags & 2 != 0 {
            layout = .contiguous(first: extra)
            payloadSize = 0
        } else if flags & 4 != 0 {
            layout = .runs(count: Int(extra))
            payloadSize = Int(extra) * 12
        } else {
            layout = .explicit
            payloadSize = entryCount * 4
        }

        return StringTable(
            reader: reader,
            arena: arena,
            count: entryCount,
            hasWeights: flags & 1 != 0,
            layout: layout,
            sourceID: try reader.u32(at: body + 8),
            payloadOffset: body + 16,
            weightsOffset: body + 16 + payloadSize
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
            retrieved: try arena.string(at: try reader.u32(at: base + 16)),
            copyright: try arena.string(at: try reader.u32(at: base + 20))
        )
    }

    /// Every source registered in this corpus, in id order.
    ///
    /// The compiler registers all of them in every locale, whether or not a table draws
    /// on one, so this is the record of what the corpus was *built from* — where
    /// ``source(_:)`` answers what a particular table was *attributed to*. The two differ
    /// whenever a table merges several upstreams and is credited to the primary: the
    /// currency tables take their numeric codes from the ISO 4217 registry but are
    /// attributed to CLDR, so walking tables alone would omit the registry entirely.
    ///
    /// Generating attribution from tables rather than from this is how a NOTICE ends up
    /// silently short of a source that was genuinely used.
    public var sources: [Source] {
        get throws {
            guard let chunk = chunks[ChunkKind.provenance.rawValue] else { return [] }
            let count = Int(try reader.u32(at: chunk.offset))
            return try (0..<count).compactMap { try source(UInt32($0)) }
        }
    }

    /// The number of distinct strings in the shared arena.
    public var stringCount: Int { arena.count }

    // MARK: - Enumeration

    /// Every path this corpus defines, sorted lexicographically.
    ///
    /// Without this a corpus is effectively write-only: ``lookup(_:)`` retrieves a path
    /// only if the caller already knows it exists, so the set of valid paths lives
    /// nowhere but in the generators' source, and "which locale covers what" cannot be
    /// answered at all. Coverage reporting, corpus inspection and validating a `Forge`'s
    /// rules up front all need the set, not a membership test.
    ///
    /// Costs nothing in the format: the index already stores each path's own string —
    /// interned in the shared arena, and read back to confirm hash matches during
    /// lookup — so this is a sequential walk of data that was there for other reasons.
    public var paths: [PathEntry] {
        get throws {
            guard let chunk = chunks[ChunkKind.index.rawValue] else { return [] }
            let entryCount = Int(try reader.u32(at: chunk.offset))
            let base = chunk.offset + 4

            var result = [PathEntry]()
            result.reserveCapacity(entryCount)
            for i in 0..<entryCount {
                let entryOffset = base + i * 24
                result.append(
                    PathEntry(
                        path: try arena.string(at: try reader.u32(at: entryOffset + 8)),
                        kind: PathEntry.Kind(raw: try reader.u32(at: entryOffset + 12)),
                        tableID: try reader.u32(at: entryOffset + 16)
                    )
                )
            }

            // Stored order is by hash, which is arbitrary to anyone reading the output.
            result.sort { $0.path < $1.path }
            return result
        }
    }

    /// Resolves an enumerated entry without searching the index again.
    ///
    /// ``paths`` already carries the kind and table ID, so dumping a whole corpus costs
    /// one walk rather than a binary search per path.
    public func entry(for pathEntry: PathEntry) throws -> Entry {
        try entry(kind: pathEntry.kind.raw, tableID: pathEntry.tableID)
    }
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

    /// The upstream's own copyright line, verbatim, or empty where it states none.
    ///
    /// Stored in the field the provenance chunk reserved from the start. Without it a
    /// notice can name a licence but not whose work it covers, which is most of what MIT
    /// and CC BY actually ask for.
    public let copyright: String
}

/// One path in a corpus, as produced by ``Corpus/paths``.
///
/// Carries what sits at the path but not the table itself, so listing a corpus does not
/// construct every table in it.
public struct PathEntry: Sendable, Equatable {
    public let path: String
    public let kind: Kind

    /// Which table the entry points at, for ``Corpus/entry(for:)``.
    let tableID: UInt32

    /// What kind of thing a path holds.
    public enum Kind: Sendable, Equatable {
        /// Defined as deliberately having no value, which blocks locale fallback.
        case explicitlyEmpty
        case strings
        case composite
        case model
        /// Written by a newer compiler than this reader understands.
        ///
        /// Reported rather than thrown, matching how the chunk directory treats kinds
        /// it does not know: enumeration must not be the one operation a
        /// forward-compatible corpus cannot survive, or inspecting a newer blob to
        /// find out why it fails would itself fail.
        case unknown(UInt32)

        init(raw: UInt32) {
            switch raw {
            case 0: self = .explicitlyEmpty
            case 1: self = .strings
            case 2: self = .composite
            case 3: self = .model
            default: self = .unknown(raw)
            }
        }

        var raw: UInt32 {
            switch self {
            case .explicitlyEmpty: 0
            case .strings: 1
            case .composite: 2
            case .model: 3
            case .unknown(let raw): raw
            }
        }
    }
}

/// What a path resolves to.
public enum Entry: Sendable {
    /// The locale explicitly defines this key as having no value, which blocks
    /// fallback to a parent locale.
    ///
    /// Named to avoid colliding with `Optional.none`: lookups return `Entry?`, and
    /// `case .none` would then be ambiguous between "no entry" and "an entry saying
    /// there is deliberately nothing" -- which are the two things this distinguishes.
    case explicitlyEmpty
    case strings(StringTable)
    case composite(CompositeTable)
    /// Reserved for generative models; not yet produced by the compiler.
    case model(id: UInt32)
}

/// The shared, deduplicated string pool.
///
/// Strings are stored back to back with a length prefix, and only every
/// `checkpointInterval`-th position is indexed. Corpus strings average ~10.6 bytes,
/// so a fixed 4-byte offset per string cost 38% of the text it pointed at; a one-byte
/// length plus a sparse checkpoint costs about 1.25 bytes instead.
///
/// The trade is a short forward scan — at most `checkpointInterval - 1` length-prefix
/// skips — on each access, which is cheap next to constructing the `String`.
struct Arena: Sendable {
    /// Marks a length that did not fit in one byte; a `UInt32` follows.
    static let escape: UInt8 = 0xFF

    private let reader: ByteReader
    private let checkpointsBase: Int
    private let bytesBase: Int
    private let bytesLimit: Int
    private let interval: Int
    let count: Int

    init(reader: ByteReader, chunk: Corpus.Chunk) throws {
        self.reader = reader
        self.count = Int(try reader.u32(at: chunk.offset))
        self.interval = Int(try reader.u32(at: chunk.offset + 4))
        let checkpointCount = Int(try reader.u32(at: chunk.offset + 8))
        self.checkpointsBase = chunk.offset + 12
        self.bytesBase = checkpointsBase + checkpointCount * 4
        self.bytesLimit = chunk.offset + chunk.length

        guard interval > 0 else {
            throw CorpusError.malformed("string arena checkpoint interval must be positive")
        }
        let expected = count == 0 ? 0 : (count + interval - 1) / interval
        guard checkpointCount == expected else {
            throw CorpusError.malformed(
                "string arena has \(checkpointCount) checkpoints, expected \(expected)"
            )
        }
        guard bytesBase <= bytesLimit else {
            throw CorpusError.malformed("string arena checkpoints extend past the chunk")
        }

        // Checkpoints must advance, or a lookup could scan backwards forever.
        var previous: UInt32 = 0
        for i in 0..<checkpointCount {
            let value = try reader.u32(at: checkpointsBase + i * 4)
            guard i == 0 ? value == 0 : value > previous else {
                throw CorpusError.malformed("string arena checkpoints are not increasing at \(i)")
            }
            previous = value
        }
    }

    /// Returns the byte length of the string starting at `position`, and where its
    /// text begins.
    private func header(at position: Int) throws -> (length: Int, text: Int) {
        let first = try reader.u8(at: position)
        if first != Self.escape {
            return (Int(first), position + 1)
        }
        return (Int(try reader.u32(at: position + 1)), position + 5)
    }

    func string(at index: UInt32) throws -> String {
        guard Int(index) < count else {
            throw CorpusError.malformed("string index \(index) out of range (\(count) strings)")
        }
        let target = Int(index)
        let checkpoint = Int(try reader.u32(at: checkpointsBase + (target / interval) * 4))

        var position = bytesBase + checkpoint
        for _ in 0..<(target % interval) {
            let (length, text) = try header(at: position)
            position = text + length
        }

        let (length, text) = try header(at: position)
        guard text + length <= bytesLimit else {
            throw CorpusError.malformed("string \(index) extends past the arena")
        }
        return try reader.string(at: text, length: length)
    }
}

/// A list of strings, optionally weighted.
public struct StringTable: Sendable {
    let reader: ByteReader
    let arena: Arena
    public let count: Int
    public let hasWeights: Bool

    /// How the table's arena indices are stored.
    ///
    /// The builder interns in insertion order, so a table's strings land in
    /// consecutive arena slots wherever they were new. Storing that as runs rather
    /// than one index per entry is what keeps the table chunk small — and it has to be
    /// runs rather than a single all-or-nothing flag, because one repeated string in a
    /// 2,240-entry table would otherwise force every index to be written out.
    enum Layout: Sendable {
        /// One run: the whole table is consecutive from this arena index.
        case contiguous(first: UInt32)
        /// `count` triples of (logical start, arena start, length).
        case runs(count: Int)
        /// One arena index per entry.
        case explicit
    }

    let layout: Layout
    public let sourceID: UInt32
    let payloadOffset: Int
    let weightsOffset: Int

    public var isEmpty: Bool { count == 0 }

    /// True when the entire table is one consecutive arena run.
    var isContiguous: Bool {
        if case .contiguous = layout { return true }
        return false
    }

    public func string(at index: Int) throws -> String {
        guard index >= 0, index < count else {
            throw CorpusError.malformed("string table index \(index) out of range (\(count))")
        }
        return try arena.string(at: try arenaIndex(for: index))
    }

    private func arenaIndex(for index: Int) throws -> UInt32 {
        switch layout {
        case .contiguous(let first):
            return first &+ UInt32(index)

        case .explicit:
            return try reader.u32(at: payloadOffset + index * 4)

        case .runs(let runCount):
            // Binary search for the last run beginning at or before `index`; runs are
            // written in ascending logical order, so this is well defined.
            var low = 0
            var high = runCount - 1
            var found = 0
            while low <= high {
                let mid = low + (high - low) / 2
                let logical = Int(try reader.u32(at: payloadOffset + mid * 12))
                if logical <= index {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            let base = payloadOffset + found * 12
            let logical = Int(try reader.u32(at: base))
            let arenaStart = try reader.u32(at: base + 4)
            let length = Int(try reader.u32(at: base + 8))
            guard index - logical < length else {
                throw CorpusError.malformed("string table run does not cover index \(index)")
            }
            return arenaStart &+ UInt32(index - logical)
        }
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

extension Corpus {
    /// The address of the backing byte buffer, for tests that need to tell one decode
    /// from two.
    ///
    /// `Corpus` is a value type, so identity is not observable at the struct level and
    /// "was this decoded once?" cannot be asked directly. The `[UInt8]` inside is
    /// copy-on-write, though, so every copy of a single decode shares one buffer and
    /// reports one address, while a second decode allocates its own.
    ///
    /// Not `public`: this is an implementation detail that happens to be observable, and
    /// exposing it would invite someone to build on an address that is only stable for
    /// as long as the corpus is alive.
    var byteBufferAddress: UInt {
        reader.bytes.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    }
}
