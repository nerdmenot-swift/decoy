/// Seeded identifiers.
///
/// These live directly on ``Faker`` rather than in a namespace because they are
/// primitives like ``Faker/numerify(_:)``, not a category of corpus data — nothing here
/// reads the corpus at all.
///
/// The reason this exists is narrow and important. `Foundation.UUID()` draws from the
/// system's random source, so a rule written `{ _ in UUID() }` produces a different value
/// on every run — in the one field most likely to be a primary key. That is a
/// reproducibility hole in a library whose entire promise is that seed 1337 yields
/// identical fixtures forever, and it cannot be fixed by seeding anything, because
/// `UUID()` never consults a generator you control.
extension Faker {

    /// A random (version 4) UUID, drawn from the seeded stream.
    ///
    /// ```swift
    /// .rule(\.id) { $0.uuid() }
    /// ```
    public mutating func uuid() -> String {
        var bytes = randomUUIDBytes()

        // Version 4 in the high nibble of byte 6, and the RFC 4122 variant in the top
        // two bits of byte 8. Without these the string is 32 random hex digits that no
        // UUID parser will accept as a v4.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return Self.format(bytes)
    }

    /// A time-ordered (version 7) UUID, drawn from the seeded stream.
    ///
    /// Version 7 puts a millisecond timestamp in the leading 48 bits, so identifiers
    /// sort in creation order — which is why databases prefer them to v4 for primary
    /// keys: index inserts stay at the right-hand edge of the B-tree instead of
    /// scattering.
    ///
    /// The timestamp comes from ``Faker/reference`` offset by ``Faker/index``, not from
    /// the system clock. Rows therefore sort in row order, and a fixture regenerated next
    /// year is byte-identical to one generated today.
    public mutating func uuidV7() -> String {
        var bytes = randomUUIDBytes()

        let milliseconds = reference.secondsSinceEpoch * 1_000 + Int64(index)
        // Big-endian, most significant byte first, as the layout requires.
        for i in 0..<6 {
            bytes[i] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - i)))
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return Self.format(bytes)
    }

    /// Sixteen bytes from the seeded generator.
    private mutating func randomUUIDBytes() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        // Two 64-bit draws rather than sixteen 8-bit ones: the generator's output is
        // 64 bits wide, so this consumes exactly two steps of the stream.
        for _ in 0..<2 {
            let word = rng.next()
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return bytes
    }

    private static let hexDigits: [Character] = Array("0123456789abcdef")

    /// Renders sixteen bytes in the canonical 8-4-4-4-12 form.
    private static func format(_ bytes: [UInt8]) -> String {
        var out = String()
        out.reserveCapacity(36)
        for (i, byte) in bytes.enumerated() {
            if i == 4 || i == 6 || i == 8 || i == 10 { out.append("-") }
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0F)])
        }
        return out
    }
}

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

#if canImport(FoundationEssentials) || canImport(Foundation)

    extension Faker {

        /// ``uuid()`` as a `Foundation.UUID`.
        ///
        /// Separate from ``uuid()`` for the same reason ``Faker/date`` is separate from
        /// ``Faker/instant``: the value is decided without Foundation, and Foundation
        /// appears only at the edge where the models being seeded need its type.
        public mutating func uuidValue() -> UUID {
            // The string is generated here, so a parse failure would be a bug in
            // `format(_:)` rather than bad input.
            UUID(uuidString: uuid())!
        }

        /// ``uuidV7()`` as a `Foundation.UUID`.
        public mutating func uuidV7Value() -> UUID {
            UUID(uuidString: uuidV7())!
        }
    }

#endif
