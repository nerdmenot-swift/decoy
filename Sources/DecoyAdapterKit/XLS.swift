import Foundation

/// A reader for the legacy `.xls` workbook, which statistical offices have not stopped
/// publishing.
///
/// Spain's national surname register is the reason this exists: 27,666 surnames with real
/// population counts, current to 2025, and available in no other format. `XLSX` cannot help
/// — that is a zip of XML and this is an OLE2 container full of binary records — and no
/// tool a build machine is guaranteed to have will convert it. `libreoffice`, `ssconvert`
/// and `catdoc` are all real answers and none of them is installed anywhere.
///
/// So: `CFB` unwraps the container, and this reads the records inside it.
///
/// ## What it supports
///
/// Shared strings, the three numeric encodings, and blanks — which is what a statistical
/// publication contains. Not formulas: their *cached results* are read where the file
/// stores them separately, and a formula whose value lives only in the formula record
/// reads as empty rather than as a wrong number.
public enum XLS {

    public enum Failure: Error, CustomStringConvertible {
        case noWorkbookStream
        case malformed(String)

        public var description: String {
            switch self {
            case .noWorkbookStream:
                return "the compound file has no Workbook stream — not an xls"
            case .malformed(let detail): return "malformed workbook: \(detail)"
            }
        }
    }

    // The record types a data sheet is made of.
    private enum Record {
        static let bof: UInt16 = 0x0809
        static let eof: UInt16 = 0x000A
        static let sst: UInt16 = 0x00FC
        static let continuation: UInt16 = 0x003C
        static let boundSheet: UInt16 = 0x0085
        static let labelSST: UInt16 = 0x00FD
        static let label: UInt16 = 0x0204
        static let number: UInt16 = 0x0203
        static let rk: UInt16 = 0x027E
        static let mulRK: UInt16 = 0x00BD
    }

    /// One record's type and the range of the stream holding its body.
    struct Span {
        let type: UInt16
        let start: Int
        let length: Int
    }

    static func records(in stream: [UInt8]) -> [Span] {
        var out: [Span] = []
        var offset = 0
        while offset + 4 <= stream.count {
            let type = CFB.u16(stream, offset)
            let length = Int(CFB.u16(stream, offset + 2))
            guard offset + 4 + length <= stream.count else { break }
            out.append(Span(type: type, start: offset + 4, length: length))
            offset += 4 + length
        }
        return out
    }

    /// An RK value: a double squeezed into four bytes.
    ///
    /// The low two bits say how. Bit 1 means the remaining thirty are a signed integer;
    /// otherwise they are the *top* thirty bits of an IEEE double with the rest zeroed.
    /// Bit 0 means the result was multiplied by a hundred to keep two decimal places.
    static func decodeRK(_ raw: UInt32) -> Double {
        let value: Double
        if raw & 2 != 0 {
            var integer = Int32(bitPattern: raw >> 2)
            // Sign-extend from thirty bits.
            if integer >= 1 << 29 { integer -= 1 << 30 }
            value = Double(integer)
        } else {
            value = Double(bitPattern: UInt64(raw & 0xFFFF_FFFC) << 32)
        }
        return raw & 1 != 0 ? value / 100 : value
    }

    /// The shared string table, which every text cell points into.
    ///
    /// The awkward part is `CONTINUE`. A table of eighty-six thousand strings does not fit
    /// in one record, and the split can land *inside* a string — at which point the
    /// continuation begins with a fresh flags byte saying whether the remainder is wide or
    /// compressed. A string can therefore change encoding halfway through, and reading it
    /// as one piece yields mojibake from the boundary onwards.
    static func sharedStrings(_ stream: [UInt8], _ spans: [Span]) -> [String] {
        guard let index = spans.firstIndex(where: { $0.type == Record.sst }) else { return [] }

        var buffer: [UInt8] = []
        var boundaries: [Int] = []
        buffer += stream[spans[index].start..<(spans[index].start + spans[index].length)]
        boundaries.append(buffer.count)
        var next = index + 1
        while next < spans.count, spans[next].type == Record.continuation {
            buffer += stream[spans[next].start..<(spans[next].start + spans[next].length)]
            boundaries.append(buffer.count)
            next += 1
        }

        let unique = Int(CFB.u32(buffer, 4))
        var strings: [String] = []
        strings.reserveCapacity(unique)
        var cursor = 8

        for _ in 0..<unique {
            guard cursor + 3 <= buffer.count else { break }
            var remaining = Int(CFB.u16(buffer, cursor))
            cursor += 2
            var flags = buffer[cursor]
            cursor += 1

            var richRuns = 0
            if flags & 8 != 0 {
                richRuns = Int(CFB.u16(buffer, cursor))
                cursor += 2
            }
            var farEast = 0
            if flags & 4 != 0 {
                farEast = Int(CFB.u32(buffer, cursor))
                cursor += 4
            }

            var scalars = String.UnicodeScalarView()
            while remaining > 0, cursor < buffer.count {
                let wide = flags & 1 != 0
                let width = wide ? 2 : 1
                let boundary = boundaries.first { $0 > cursor } ?? buffer.count
                let available = (boundary - cursor) / width
                let take = min(remaining, max(available, 0))

                for step in 0..<take {
                    let at = cursor + step * width
                    let unit = wide ? CFB.u16(buffer, at) : UInt16(buffer[at])
                    if let scalar = Unicode.Scalar(UInt32(unit)) { scalars.append(scalar) }
                }
                cursor += take * width
                remaining -= take

                if remaining > 0 {
                    guard cursor < buffer.count else { break }
                    flags = buffer[cursor]
                    cursor += 1
                }
            }
            cursor += richRuns * 4 + farEast
            strings.append(String(scalars))
        }
        return strings
    }

    /// A number as the sheet would show it, and as `XLSX` hands back its own.
    ///
    /// Whole numbers lose the decimal point: a population count is `1446937`, not
    /// `1446937.0`, and every caller parses these back out of a string.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(value)
    }

    /// Sheet name to rows of cells, matching ``XLSX/readWorkbook(at:)``.
    public static func readWorkbook(at path: URL) throws -> [String: [[String]]] {
        let container = try CFB.open([UInt8](try Data(contentsOf: path)))
        guard let workbook = container.stream(named: "Workbook")
                ?? container.stream(named: "Book")
        else { throw Failure.noWorkbookStream }

        let stream = container.read(workbook)
        let spans = records(in: stream)
        let strings = sharedStrings(stream, spans)

        // Each sheet declares where its own records begin.
        var sheets: [(name: String, offset: Int)] = []
        for span in spans where span.type == Record.boundSheet {
            let body = Array(stream[span.start..<(span.start + span.length)])
            guard body.count > 8 else { continue }
            let position = Int(CFB.u32(body, 0))
            let characters = Int(body[6])
            let wide = body[7] & 1 != 0
            var scalars = String.UnicodeScalarView()
            for step in 0..<characters {
                let at = 8 + step * (wide ? 2 : 1)
                guard at < body.count else { break }
                let unit = wide ? CFB.u16(body, at) : UInt16(body[at])
                if let scalar = Unicode.Scalar(UInt32(unit)) { scalars.append(scalar) }
            }
            sheets.append((String(scalars), position))
        }

        var out: [String: [[String]]] = [:]
        for (index, sheet) in sheets.enumerated() {
            let end = index + 1 < sheets.count ? sheets[index + 1].offset : stream.count
            var cells: [Int: [Int: String]] = [:]

            for span in spans where span.start - 4 >= sheet.offset && span.start - 4 < end {
                let body = Array(stream[span.start..<(span.start + span.length)])
                switch span.type {
                case Record.labelSST:
                    guard body.count >= 10 else { continue }
                    let index = Int(CFB.u32(body, 6))
                    cells[Int(CFB.u16(body, 0)), default: [:]][Int(CFB.u16(body, 2))] =
                        index < strings.count ? strings[index] : ""
                case Record.label:
                    guard body.count >= 8 else { continue }
                    let characters = Int(CFB.u16(body, 6))
                    let wide = body.count > 8 && body[8] & 1 != 0
                    var scalars = String.UnicodeScalarView()
                    for step in 0..<characters {
                        let at = 9 + step * (wide ? 2 : 1)
                        guard at < body.count else { break }
                        let unit = wide ? CFB.u16(body, at) : UInt16(body[at])
                        if let scalar = Unicode.Scalar(UInt32(unit)) { scalars.append(scalar) }
                    }
                    cells[Int(CFB.u16(body, 0)), default: [:]][Int(CFB.u16(body, 2))] =
                        String(scalars)
                case Record.number:
                    guard body.count >= 14 else { continue }
                    let bits = CFB.u64(body, 6)
                    cells[Int(CFB.u16(body, 0)), default: [:]][Int(CFB.u16(body, 2))] =
                        format(Double(bitPattern: bits))
                case Record.rk:
                    guard body.count >= 10 else { continue }
                    cells[Int(CFB.u16(body, 0)), default: [:]][Int(CFB.u16(body, 2))] =
                        format(decodeRK(CFB.u32(body, 6)))
                case Record.mulRK:
                    // One record covering a run of columns, each with its own format index.
                    guard body.count >= 6 else { continue }
                    let row = Int(CFB.u16(body, 0))
                    let first = Int(CFB.u16(body, 2))
                    let count = (body.count - 6) / 6
                    for step in 0..<count {
                        let raw = CFB.u32(body, 4 + step * 6 + 2)
                        cells[row, default: [:]][first + step] = format(decodeRK(raw))
                    }
                default:
                    continue
                }
            }

            var rows: [[String]] = []
            for row in cells.keys.sorted() {
                let line = cells[row] ?? [:]
                let highest = line.keys.max() ?? -1
                rows.append(highest < 0 ? [] : (0...highest).map { line[$0] ?? "" })
            }
            out[sheet.name] = rows
        }
        return out
    }
}
