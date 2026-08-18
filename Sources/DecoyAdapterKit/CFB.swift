import Foundation

/// The OLE2 container a legacy `.xls` is wrapped in.
///
/// Microsoft's Compound File Binary format: a FAT filesystem in a file, with sectors, a
/// sector allocation table and a directory. `.xlsx` replaced it with a zip, which is why
/// `XLSX` can hand the container to `unzip` and be done. Nothing on a build machine reads
/// this one, so it is read here.
///
/// Only what a spreadsheet needs: streams, the two allocation tables, and the directory.
/// No storages, no property sets, no writing.
enum CFB {

    enum Failure: Error, CustomStringConvertible {
        case notCompoundFile
        case malformed(String)

        var description: String {
            switch self {
            case .notCompoundFile: return "not an OLE2 compound file"
            case .malformed(let detail): return "malformed compound file: \(detail)"
            }
        }
    }

    static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    /// Everything at or above `0xFFFFFFFA` is a marker rather than a sector number.
    static let maxSector: UInt32 = 0xFFFF_FFFA

    struct Stream {
        let name: String
        let start: UInt32
        let size: UInt64
        /// A directory entry's type byte: 2 is a stream, 5 the root.
        let isRoot: Bool
    }

    /// Reads little-endian integers out of a byte array without copying.
    static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    static func u64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        UInt64(u32(bytes, offset)) | UInt64(u32(bytes, offset + 4)) << 32
    }

    /// A parsed container, able to hand back any stream by name.
    struct Reader {
        let bytes: [UInt8]
        let sectorSize: Int
        let miniSectorSize: Int
        let miniCutoff: UInt32
        let fat: [UInt32]
        let miniFAT: [UInt32]
        let streams: [Stream]
        /// The root entry's own stream, which is where every small stream actually lives.
        let miniStream: [UInt8]

        func sector(_ index: UInt32) -> ArraySlice<UInt8> {
            let start = 512 + Int(index) * sectorSize
            let end = min(start + sectorSize, bytes.count)
            guard start < end else { return [][...] }
            return bytes[start..<end]
        }

        /// The sector numbers a stream occupies, in order.
        func chain(from start: UInt32, in table: [UInt32]) -> [UInt32] {
            var out: [UInt32] = []
            var next = start
            // Bounded rather than trusting the table: a corrupt or hostile FAT can point
            // at itself, and a build step should fail rather than spin.
            while next < CFB.maxSector, out.count <= table.count {
                out.append(next)
                guard Int(next) < table.count else { break }
                next = table[Int(next)]
            }
            return out
        }

        func read(_ stream: Stream) -> [UInt8] {
            var out: [UInt8] = []
            if stream.size < UInt64(miniCutoff) && !stream.isRoot {
                // Small streams live inside the root's stream, allocated by the mini FAT.
                for index in chain(from: stream.start, in: miniFAT) {
                    let start = Int(index) * miniSectorSize
                    let end = min(start + miniSectorSize, miniStream.count)
                    if start < end { out += miniStream[start..<end] }
                }
            } else {
                for index in chain(from: stream.start, in: fat) { out += sector(index) }
            }
            return Array(out.prefix(Int(stream.size)))
        }

        func stream(named name: String) -> Stream? {
            streams.first { $0.name == name && !$0.isRoot }
        }
    }

    static func open(_ bytes: [UInt8]) throws -> Reader {
        guard bytes.count > 512, Array(bytes[0..<8]) == signature else {
            throw Failure.notCompoundFile
        }

        let sectorSize = 1 << Int(u16(bytes, 30))
        let miniSectorSize = 1 << Int(u16(bytes, 32))
        let fatCount = Int(u32(bytes, 44))
        let firstDirectory = u32(bytes, 48)
        let miniCutoff = u32(bytes, 56)
        let firstMiniFAT = u32(bytes, 60)
        let miniFATCount = Int(u32(bytes, 64))
        let firstDIFAT = u32(bytes, 68)
        let difatCount = Int(u32(bytes, 72))

        guard sectorSize >= 128, sectorSize <= 1 << 20 else {
            throw Failure.malformed("sector size \(sectorSize)")
        }

        func rawSector(_ index: UInt32) -> ArraySlice<UInt8> {
            let start = 512 + Int(index) * sectorSize
            let end = min(start + sectorSize, bytes.count)
            guard start < end else { return [][...] }
            return bytes[start..<end]
        }

        // The DIFAT lists which sectors hold the FAT. The first 109 entries are in the
        // header; the rest chain through sectors of their own.
        var difat: [UInt32] = (0..<109).map { u32(bytes, 76 + $0 * 4) }
        var next = firstDIFAT
        for _ in 0..<difatCount where next < maxSector {
            let block = Array(rawSector(next))
            let perSector = sectorSize / 4 - 1
            difat += (0..<perSector).map { u32(block, $0 * 4) }
            next = u32(block, sectorSize - 4)
        }

        var fat: [UInt32] = []
        for entry in difat.prefix(fatCount) where entry < maxSector {
            let block = Array(rawSector(entry))
            fat += (0..<(sectorSize / 4)).map { u32(block, $0 * 4) }
        }
        guard !fat.isEmpty else { throw Failure.malformed("no allocation table") }

        // A reader with no mini stream yet, purely to walk chains while building one.
        let bootstrap = Reader(
            bytes: bytes, sectorSize: sectorSize, miniSectorSize: miniSectorSize,
            miniCutoff: miniCutoff, fat: fat, miniFAT: [], streams: [], miniStream: [])

        var miniFAT: [UInt32] = []
        if miniFATCount > 0 {
            for index in bootstrap.chain(from: firstMiniFAT, in: fat) {
                let block = Array(bootstrap.sector(index))
                miniFAT += (0..<(sectorSize / 4)).map { u32(block, $0 * 4) }
            }
        }

        var directory: [UInt8] = []
        for index in bootstrap.chain(from: firstDirectory, in: fat) {
            directory += bootstrap.sector(index)
        }

        var streams: [Stream] = []
        var root: Stream?
        for offset in stride(from: 0, to: directory.count - 127, by: 128) {
            let entry = Array(directory[offset..<(offset + 128)])
            let nameBytes = Int(u16(entry, 64))
            let type = entry[66]
            guard type == 2 || type == 5, nameBytes > 2 else { continue }
            // UTF-16LE, and the length counts the terminating null.
            var scalars = String.UnicodeScalarView()
            for pair in stride(from: 0, to: min(nameBytes - 2, 64), by: 2) {
                let unit = u16(entry, pair)
                if let scalar = Unicode.Scalar(UInt32(unit)) { scalars.append(scalar) }
            }
            let stream = Stream(
                name: String(scalars), start: u32(entry, 116), size: u64(entry, 120),
                isRoot: type == 5)
            if stream.isRoot { root = stream } else { streams.append(stream) }
        }

        // The root's own stream holds every stream below the cutoff.
        var miniStream: [UInt8] = []
        if let root, root.start < maxSector {
            for index in bootstrap.chain(from: root.start, in: fat) {
                miniStream += bootstrap.sector(index)
            }
        }

        return Reader(
            bytes: bytes, sectorSize: sectorSize, miniSectorSize: miniSectorSize,
            miniCutoff: miniCutoff, fat: fat, miniFAT: miniFAT, streams: streams,
            miniStream: miniStream)
    }
}
