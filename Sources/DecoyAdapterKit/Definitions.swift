import Foundation

/// The nested definition tree a locale is built up as, and the rules for combining them.
///
/// A JSON-shaped value rather than a typed model, because that is genuinely what this is:
/// adapters contribute arbitrary nested data — string lists, weighted lists, composite
/// tables, explicit nulls — and the compiler walks the shape rather than a schema. Typing
/// it would mean a case per data kind and a migration every time one is added.
public indirect enum Definition: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// A deliberate empty. Blocks chain inheritance; see `NamePatterns.state`.
    case null
    case list([Definition])
    case object([String: Definition])

    public var asObject: [String: Definition]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Whether two values are both plain objects, which is the only case a merge descends.
    static func bothObjects(_ a: Definition?, _ b: Definition?) -> Bool {
        a?.asObject != nil && b?.asObject != nil
    }
}

extension Definition {
    /// Decodes from what `JSONSerialization` produces.
    public init(json: Any) {
        switch json {
        case let value as String: self = .string(value)
        case let value as [Any]: self = .list(value.map(Definition.init(json:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(Definition.init(json:)))
        case let value as NSNumber:
            // NSNumber does not distinguish a bool from a 0 or 1 by type, only by the
            // ObjC encoding it carries. Getting this wrong turns every `true` into a `1`
            // and changes the emitted JSON.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case is NSNull: self = .null
        default: self = .null
        }
    }

    /// Re-encodes to what `JSONSerialization` accepts.
    public var json: Any {
        switch self {
        case .string(let value): return value
        case .number(let value):
            // Whole numbers go back as integers. JavaScript has one number type and writes
            // `4` rather than `4.0`, so emitting a double would change every count in the
            // intermediate JSON.
            return value == value.rounded() && abs(value) < 9_007_199_254_740_992
                ? Int(value) as Any : value as Any
        case .bool(let value): return value
        case .null: return NSNull()
        case .list(let values): return values.map(\.json)
        case .object(let values): return values.mapValues(\.json)
        }
    }
}

/// Combining contributions into one locale's definitions.
public enum Definitions {

    /// Expands `{"location.country": …}` into the nested shape the compiler walks.
    public static func nest(_ path: String, _ value: Definition) -> [String: Definition] {
        let segments = path.split(separator: ".").map(String.init)
        guard let last = segments.last else { return [:] }
        var node: [String: Definition] = [last: value]
        for segment in segments.dropLast().reversed() {
            node = [segment: .object(node)]
        }
        return node
    }

    /// A real adapter's node replaces whatever sits there, whole.
    ///
    /// Descends only where both sides are plain objects: a list replaces a list rather than
    /// concatenating, which is what makes a claim mean "this table is mine".
    public static func mergeOver(
        _ base: inout [String: Definition], _ incoming: [String: Definition]
    ) {
        for (key, value) in incoming {
            if let existing = base[key]?.asObject, let new = value.asObject {
                var merged = existing
                mergeOver(&merged, new)
                base[key] = .object(merged)
            } else {
                base[key] = value
            }
        }
    }

    /// Every proper ancestor of a dotted path.
    ///
    /// Used to tell "nothing here is claimed" from "something below this is", which is what
    /// stopped a bootstrap adapter copying an unclaimed subtree wholesale and smuggling
    /// back the values a real adapter had claimed further down.
    public static func ancestors(of path: String) -> [String] {
        var found: [String] = []
        var segments = path.split(separator: ".").map(String.init)
        segments.removeLast()
        while !segments.isEmpty {
            found.append(segments.joined(separator: "."))
            segments.removeLast()
        }
        return found
    }
}
