import Foundation

/// A minimal JSON tree.
///
/// Decoded through `Codable` rather than `JSONSerialization` because the latter
/// hands back `Any` bridged through `NSNumber`, whose behaviour differs between
/// Darwin and swift-corelibs-foundation — and telling an integer from a double
/// through that bridge is exactly the kind of thing that works on a Mac and
/// misbehaves on the Linux CI runner.
indirect public enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "value is not valid JSON"
            )
        }
    }

    public var asString: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return Self.format(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var asObject: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var asArray: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Numbers only. Unlike ``asString`` this does *not* coerce, because a model's
    /// symbol and weight fields have to be numbers — reading `"3"` as 3 would let a
    /// malformed intermediate compile into a model that draws the wrong character.
    public var asNumber: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Formats a number without a trailing `.0`, so `020` stays usable as a string
    /// and integer-valued data does not acquire spurious decimals.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(value)
    }
}
