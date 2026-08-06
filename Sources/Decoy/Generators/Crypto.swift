/// Cryptocurrency addresses and digests.
///
/// Every address here carries a valid checksum. A wallet, block explorer or input
/// validator will accept these as well-formed — which is the point, since the code worth
/// testing is the code that validates. They are of course not addresses anyone controls,
/// and no key exists for any of them.
extension Faker {
    public var crypto: CryptoFaker {
        get { CryptoFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct CryptoFaker {
    var faker: Faker

    /// Base58 omits `0`, `O`, `I` and `l`, which are the characters people confuse when
    /// transcribing an address by hand.
    private static let base58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    // MARK: - Bitcoin

    /// A pay-to-public-key-hash address, the `1…` form.
    public mutating func bitcoinAddress() -> String {
        base58Check(version: 0x00)
    }

    /// A pay-to-script-hash address, the `3…` form.
    public mutating func p2shAddress() -> String {
        base58Check(version: 0x05)
    }

    /// A native SegWit address, the `bc1q…` form (BIP-173).
    public mutating func bech32Address() -> String {
        var program = [UInt8]()
        for _ in 0..<20 { program.append(UInt8(faker.int(in: 0...255))) }
        return Self.bech32(hrp: "bc", witnessVersion: 0, program: program)
    }

    /// An Ethereum address: `0x` and 40 hex digits.
    ///
    /// Lower-case, which is the canonical unchecksummed form and valid everywhere. The
    /// EIP-55 mixed-case variant encodes a Keccak-256 checksum in the letter casing, and
    /// Keccak is a different permutation from SHA-3 with no other use here — not worth
    /// a second hash implementation for a casing convention.
    public mutating func ethereumAddress() -> String {
        var out = "0x"
        for _ in 0..<40 {
            out.append("0123456789abcdef".randomElementSeeded(&faker))
        }
        return out
    }

    // MARK: - Digests

    /// A 256-bit digest, rendered as 64 hex digits.
    ///
    /// Random bytes rather than the hash of something. A digest is indistinguishable
    /// from uniform random of the same width — that is what makes it a digest — so
    /// hashing an arbitrary input would burn cycles to produce a value with identical
    /// properties.
    public mutating func sha256() -> String { hex(bytes: 32) }

    /// A 512-bit digest, rendered as 128 hex digits.
    public mutating func sha512() -> String { hex(bytes: 64) }

    /// A 160-bit digest, rendered as 40 hex digits.
    public mutating func sha1() -> String { hex(bytes: 20) }

    /// A 128-bit digest, rendered as 32 hex digits.
    public mutating func md5() -> String { hex(bytes: 16) }

    private mutating func hex(bytes count: Int) -> String {
        var out = String()
        out.reserveCapacity(count * 2)
        for _ in 0..<(count * 2) {
            out.append("0123456789abcdef".randomElementSeeded(&faker))
        }
        return out
    }

    // MARK: - Encodings

    /// Builds `version ‖ payload ‖ checksum` and Base58-encodes it.
    ///
    /// The checksum is the first four bytes of the double SHA-256 of everything before
    /// it, which is what a validator recomputes and compares.
    private mutating func base58Check(version: UInt8) -> String {
        var payload: [UInt8] = [version]
        for _ in 0..<20 { payload.append(UInt8(faker.int(in: 0...255))) }
        payload.append(contentsOf: SHA256.doubleHash(payload).prefix(4))
        return Self.base58Encode(payload)
    }

    private static func base58Encode(_ bytes: [UInt8]) -> String {
        // Big-endian base conversion by repeated division over the whole number.
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        // Each leading zero byte is one leading `1`, so the encoding round-trips a
        // payload whose version byte is zero — which every P2PKH address has.
        var out = String()
        for byte in bytes {
            if byte != 0 { break }
            out.append("1")
        }
        for digit in digits.reversed() {
            out.append(base58[Int(digit)])
        }
        return out
    }

    /// BIP-173 Bech32, as used by native SegWit addresses.
    private static func bech32(hrp: String, witnessVersion: UInt8, program: [UInt8]) -> String {
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

        // Bech32 works in 5-bit groups, so the 8-bit witness program is requantised.
        var values: [UInt8] = [witnessVersion]
        var accumulator = 0
        var bits = 0
        for byte in program {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                values.append(UInt8((accumulator >> bits) & 31))
            }
        }
        if bits > 0 { values.append(UInt8((accumulator << (5 - bits)) & 31)) }

        var out = hrp + "1"
        for value in values + checksum(hrp: hrp, values: values) {
            out.append(charset[Int(value)])
        }
        return out
    }

    private static func checksum(hrp: String, values: [UInt8]) -> [UInt8] {
        var expanded = hrp.unicodeScalars.map { UInt8($0.value >> 5) }
        expanded.append(0)
        expanded.append(contentsOf: hrp.unicodeScalars.map { UInt8($0.value & 31) })
        expanded.append(contentsOf: values)
        expanded.append(contentsOf: [0, 0, 0, 0, 0, 0])

        let polymod = bech32Polymod(expanded) ^ 1
        return (0..<6).map { UInt8((polymod >> (5 * (5 - $0))) & 31) }
    }

    /// Exposed so tests can recompute a published address's checksum independently
    /// rather than comparing the generator against itself.
    static func bech32PolymodForTesting(_ values: [UInt8]) -> UInt32 {
        bech32Polymod(values)
    }

    private static func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [
            0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3,
        ]
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ff_ffff) << 5) ^ UInt32(value)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 {
                checksum ^= generator[i]
            }
        }
        return checksum
    }
}

extension String {
    /// Picks one character using the seeded stream.
    fileprivate func randomElementSeeded(_ faker: inout Faker) -> Character {
        let characters = Array(self)
        return characters[faker.int(in: 0...(characters.count - 1))]
    }
}
