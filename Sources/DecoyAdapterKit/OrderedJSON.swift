import Foundation

/// JSON written the way `JSON.stringify(value, null, 1)` writes it.
///
/// The committed query snapshots are diffed by hand — that is the whole point of committing
/// them rather than hashing a server's answer — so how they are formatted is not cosmetic.
/// `JSONSerialization` indents with two spaces and orders a dictionary's keys by whatever
/// the hash gives, and either alone would turn every re-run into a whole-file diff with the
/// actual change buried in it.
///
/// So: one space per level, and objects keep the order they were built in.
public indirect enum OrderedJSON {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int)
    case double(Double)
    case array([OrderedJSON])
    case object([(key: String, value: OrderedJSON)])

    public var rendered: String {
        var out = ""
        write(into: &out, depth: 0)
        return out
    }

    private func write(into out: inout String, depth: Int) {
        let indent = String(repeating: " ", count: depth + 1)
        let closing = String(repeating: " ", count: depth)

        switch self {
        case .null:
            out += "null"

        case .bool(let flag):
            out += flag ? "true" : "false"

        case .string(let text):
            out += Self.quoted(text)

        case .integer(let value):
            out += String(value)

        case .double(let value):
            // JavaScript has one number type and writes `4` rather than `4.0`, so a whole
            // number goes back as an integer or every count in the file changes shape.
            if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                out += String(Int(value))
            } else {
                out += String(value)
            }

        case .array(let items):
            guard !items.isEmpty else {
                out += "[]"
                return
            }
            out += "[\n"
            for (offset, item) in items.enumerated() {
                out += indent
                item.write(into: &out, depth: depth + 1)
                out += offset == items.count - 1 ? "\n" : ",\n"
            }
            out += closing + "]"

        case .object(let members):
            guard !members.isEmpty else {
                out += "{}"
                return
            }
            out += "{\n"
            for (offset, member) in members.enumerated() {
                out += indent + Self.quoted(member.key) + ": "
                member.value.write(into: &out, depth: depth + 1)
                out += offset == members.count - 1 ? "\n" : ",\n"
            }
            out += closing + "}"
        }
    }

    /// A JSON string literal.
    ///
    /// Non-ASCII passes through as itself, which is what `JSON.stringify` does and what
    /// makes these files readable: a Hebrew given name is worth more in the diff as `אילול`
    /// than as five `\u` escapes.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let other where other.value < 0x20:
                out += String(format: "\\u%04x", other.value)
            case let other:
                out.unicodeScalars.append(other)
            }
        }
        return out + "\""
    }
}

// MARK: - Reading

extension OrderedJSON {

    /// Convenience accessors, for walking a decoded response.
    public var asObject: [(key: String, value: OrderedJSON)]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public var asArray: [OrderedJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var asString: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    public var asNumber: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    public subscript(key: String) -> OrderedJSON? {
        asObject?.first { $0.key == key }?.value
    }

    public enum ParseFailure: Error, CustomStringConvertible {
        case malformed(at: Int)

        public var description: String {
            switch self {
            case .malformed(let offset): return "not JSON, at byte \(offset)"
            }
        }
    }

    /// Parses JSON, keeping every object's keys in the order the document states them.
    ///
    /// `JSONSerialization` gives a `Dictionary`, which does not. That is usually harmless
    /// and was not here: Slovenia's statistics office lists a category's `label` keys in one
    /// order and its `index` in another, and reading either as though it were the other
    /// reorders 8,688 names in a file whose whole purpose is to be diffed by hand.
    public static func parse(_ data: Data) throws -> OrderedJSON {
        var scanner = Scanner(bytes: [UInt8](data))
        let value = try scanner.value()
        scanner.skipWhitespace()
        return value
    }

    struct Scanner {
        let bytes: [UInt8]
        var offset = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipWhitespace() {
            while offset < bytes.count,
                bytes[offset] == 0x20 || bytes[offset] == 0x09 || bytes[offset] == 0x0A
                    || bytes[offset] == 0x0D
            {
                offset += 1
            }
        }

        mutating func expect(_ byte: UInt8) throws {
            guard offset < bytes.count, bytes[offset] == byte else {
                throw ParseFailure.malformed(at: offset)
            }
            offset += 1
        }

        mutating func value() throws -> OrderedJSON {
            skipWhitespace()
            guard offset < bytes.count else { throw ParseFailure.malformed(at: offset) }

            switch bytes[offset] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"):
                try literal("true")
                return .bool(true)
            case UInt8(ascii: "f"):
                try literal("false")
                return .bool(false)
            case UInt8(ascii: "n"):
                try literal("null")
                return .null
            default: return try number()
            }
        }

        mutating func literal(_ text: String) throws {
            for byte in text.utf8 { try expect(byte) }
        }

        mutating func object() throws -> OrderedJSON {
            try expect(UInt8(ascii: "{"))
            var members: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "}") {
                offset += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                let key = try string()
                skipWhitespace()
                try expect(UInt8(ascii: ":"))
                members.append((key, try value()))
                skipWhitespace()
                guard offset < bytes.count else { throw ParseFailure.malformed(at: offset) }
                if bytes[offset] == UInt8(ascii: ",") {
                    offset += 1
                    continue
                }
                try expect(UInt8(ascii: "}"))
                return .object(members)
            }
        }

        mutating func array() throws -> OrderedJSON {
            try expect(UInt8(ascii: "["))
            var items: [OrderedJSON] = []
            skipWhitespace()
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "]") {
                offset += 1
                return .array(items)
            }
            while true {
                items.append(try value())
                skipWhitespace()
                guard offset < bytes.count else { throw ParseFailure.malformed(at: offset) }
                if bytes[offset] == UInt8(ascii: ",") {
                    offset += 1
                    continue
                }
                try expect(UInt8(ascii: "]"))
                return .array(items)
            }
        }

        mutating func string() throws -> String {
            try expect(UInt8(ascii: "\""))
            var scalars = String.UnicodeScalarView()
            // A `😀` pair is two escapes and one scalar, so a pending high
            // surrogate is held until its partner arrives.
            var pendingHigh: UInt32? = nil

            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == UInt8(ascii: "\"") {
                    offset += 1
                    if let high = pendingHigh, let scalar = Unicode.Scalar(high) {
                        scalars.append(scalar)
                    }
                    return String(scalars)
                }
                if byte == UInt8(ascii: "\\") {
                    offset += 1
                    guard offset < bytes.count else { throw ParseFailure.malformed(at: offset) }
                    let escape = bytes[offset]
                    offset += 1

                    if escape == UInt8(ascii: "u") {
                        guard offset + 4 <= bytes.count,
                            let code = UInt32(
                                String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self),
                                radix: 16)
                        else { throw ParseFailure.malformed(at: offset) }
                        offset += 4

                        if let high = pendingHigh {
                            pendingHigh = nil
                            if (0xDC00...0xDFFF).contains(code) {
                                let combined =
                                    0x10000 + ((high - 0xD800) << 10) + (code - 0xDC00)
                                if let scalar = Unicode.Scalar(combined) {
                                    scalars.append(scalar)
                                }
                                continue
                            }
                            if let scalar = Unicode.Scalar(high) { scalars.append(scalar) }
                        }
                        if (0xD800...0xDBFF).contains(code) {
                            pendingHigh = code
                        } else if let scalar = Unicode.Scalar(code) {
                            scalars.append(scalar)
                        }
                        continue
                    }

                    if let high = pendingHigh, let scalar = Unicode.Scalar(high) {
                        scalars.append(scalar)
                        pendingHigh = nil
                    }
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    default: throw ParseFailure.malformed(at: offset)
                    }
                    continue
                }

                if let high = pendingHigh, let scalar = Unicode.Scalar(high) {
                    scalars.append(scalar)
                    pendingHigh = nil
                }
                // A run of literal bytes, decoded as UTF-8 in one go rather than one byte
                // at a time — a Hebrew name is two bytes per letter and decoding them
                // singly would produce replacement characters.
                let start = offset
                while offset < bytes.count, bytes[offset] != UInt8(ascii: "\""),
                    bytes[offset] != UInt8(ascii: "\\")
                {
                    offset += 1
                }
                scalars.append(
                    contentsOf: String(decoding: bytes[start..<offset], as: UTF8.self)
                        .unicodeScalars)
            }
            throw ParseFailure.malformed(at: offset)
        }

        mutating func number() throws -> OrderedJSON {
            let start = offset
            var isInteger = true
            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e")
                    || byte == UInt8(ascii: "E")
                {
                    isInteger = false
                } else if !((UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                    || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+"))
                {
                    break
                }
                offset += 1
            }
            guard offset > start else { throw ParseFailure.malformed(at: offset) }
            let text = String(decoding: bytes[start..<offset], as: UTF8.self)
            if isInteger, let value = Int(text) { return .integer(value) }
            guard let value = Double(text) else { throw ParseFailure.malformed(at: start) }
            return .double(value)
        }
    }
}

extension OrderedJSON {

    /// Whether a key is what ECMAScript calls an array index.
    ///
    /// Canonical decimal only: `"3"` is one, `"03"` and `"3.0"` and `"-1"` are not, and the
    /// value must fit below 2^32 - 1.
    static func isArrayIndex(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 10, key.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return false }
        if key.count > 1 && key.hasPrefix("0") { return false }
        guard let value = UInt64(key) else { return false }
        return value < 4_294_967_295
    }

    /// An object's members in JavaScript's own property-enumeration order.
    ///
    /// Not document order, and this is not a stylistic choice. `Object.keys` lists
    /// integer-like keys first, ascending *numerically*, and only then the rest in insertion
    /// order — so an object whose keys are `"3"`, `"19"`, `"29413"`, `"41"` enumerates as 3,
    /// 19, 41, … , 29413 however the document happens to list them.
    ///
    /// Slovenia's name codes are exactly that shape. Reading the file in document order put
    /// all 8,688 Slovenian names in a different sequence from the committed snapshot, which
    /// is a whole-file diff in something whose purpose is to be diffed by hand.
    public var propertyOrder: [(key: String, value: OrderedJSON)]? {
        guard let members = asObject else { return nil }
        let indices = members.enumerated()
            .filter { Self.isArrayIndex($0.element.key) }
            .sorted { (UInt64($0.element.key) ?? 0) < (UInt64($1.element.key) ?? 0) }
            .map(\.element)
        let rest = members.filter { !Self.isArrayIndex($0.key) }
        return indices + rest
    }
}
