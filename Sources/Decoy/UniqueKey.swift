/// A value that can act as a uniqueness key.
///
/// `rule(unique:)` has to remember what it has already produced, across rules whose
/// value types differ. The obvious tool is `AnyHashable`, but it is unavailable in
/// embedded Swift, and `Hashable` is the wrong contract besides: Swift's `Hasher` is
/// seeded randomly per process, so `hashValue` is not a stable identity — exactly the
/// kind of hidden non-determinism this library exists to avoid.
///
/// Conformances ship for every type a unique database column realistically holds, so
/// most callers never see this protocol. Conform your own type by returning something
/// that is stable across processes.
public protocol UniqueKey {
    /// A representation that is identical in every process, for the same value.
    var decoyUniqueKey: String { get }
}

extension String: UniqueKey {
    public var decoyUniqueKey: String { self }
}

extension Substring: UniqueKey {
    public var decoyUniqueKey: String { String(self) }
}

extension Character: UniqueKey {
    public var decoyUniqueKey: String { String(self) }
}

extension Bool: UniqueKey {
    public var decoyUniqueKey: String { self ? "true" : "false" }
}

extension Int: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension Int8: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension Int16: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension Int32: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension Int64: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension UInt: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension UInt8: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension UInt16: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension UInt32: UniqueKey { public var decoyUniqueKey: String { String(self) } }
extension UInt64: UniqueKey { public var decoyUniqueKey: String { String(self) } }

extension Timestamp: UniqueKey {
    public var decoyUniqueKey: String { String(secondsSinceEpoch) }
}

/// Covers enums and the wrapper types people give identifiers, e.g.
/// `struct UserID: RawRepresentable { let rawValue: String }`.
extension RawRepresentable where RawValue: UniqueKey {
    public var decoyUniqueKey: String { rawValue.decoyUniqueKey }
}

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

#if canImport(FoundationEssentials) || canImport(Foundation)
    extension UUID: UniqueKey {
        public var decoyUniqueKey: String { uuidString }
    }
#endif
