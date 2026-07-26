/// Bounds-checked little-endian reads over a byte buffer.
///
/// Every integer is assembled byte by byte rather than loaded through a pointer cast.
/// That costs a few shifts and buys two things a compiled corpus needs: no alignment
/// requirement, so tables can sit at any offset; and no dependence on host byte order,
/// so a blob compiled on an arm64 Mac is valid on a big-endian target. Loading a
/// `UInt32` via `withMemoryRebound` would be faster and would silently produce
/// garbage on the first big-endian machine that ran it.
struct ByteReader: Sendable {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int { bytes.count }

    @inline(__always)
    private func require(_ offset: Int, _ size: Int) throws {
        guard offset >= 0, size >= 0, offset &+ size <= bytes.count else {
            throw CorpusError.truncated(offset: offset, needed: size, available: bytes.count)
        }
    }

    @inline(__always)
    func u8(at offset: Int) throws -> UInt8 {
        try require(offset, 1)
        return bytes[offset]
    }

    @inline(__always)
    func u16(at offset: Int) throws -> UInt16 {
        try require(offset, 2)
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    @inline(__always)
    func u32(at offset: Int) throws -> UInt32 {
        try require(offset, 4)
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    @inline(__always)
    func u64(at offset: Int) throws -> UInt64 {
        try require(offset, 8)
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[offset + i]) << (8 * UInt64(i))
        }
        return value
    }

    /// Decodes a UTF-8 string from a byte range.
    ///
    /// Invalid UTF-8 is repaired rather than rejected: a single bad byte in a 1.5 MB
    /// arena should not make an entire corpus unloadable.
    func string(at offset: Int, length: Int) throws -> String {
        try require(offset, length)
        return String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
    }

    /// Converts a `UInt64` field to `Int`, rejecting values a 32-bit platform cannot
    /// address rather than trapping on the conversion.
    func checkedInt(_ value: UInt64, _ field: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw CorpusError.malformed("\(field) (\(value)) exceeds the addressable range")
        }
        return Int(value)
    }
}

public enum CorpusError: Error, CustomStringConvertible {
    case notADecoyCorpus
    case unsupportedFormatVersion(found: UInt16, supported: UInt16)
    case truncated(offset: Int, needed: Int, available: Int)
    case malformed(String)
    case missingChunk(String)

    public var description: String {
        switch self {
        case .notADecoyCorpus:
            return "not a Decoy corpus: magic bytes do not match"
        case .unsupportedFormatVersion(let found, let supported):
            return """
                corpus format version \(found) is newer than this build understands \
                (\(supported)). Update Decoy, or pin an older corpus.
                """
        case .truncated(let offset, let needed, let available):
            return "corpus truncated: needed \(needed) bytes at \(offset), file is \(available)"
        case .malformed(let detail):
            return "corpus malformed: \(detail)"
        case .missingChunk(let name):
            return "corpus is missing its required \(name) chunk"
        }
    }
}
