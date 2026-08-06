import Testing

@testable import Decoy

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

#if canImport(FoundationEssentials)
    import FoundationEssentials
#elseif canImport(Foundation)
    import Foundation
#endif

@Suite("SHA-256")
struct SHA256Tests {

    // FIPS 180-4 / RFC 6234 published vectors. Without these the implementation is
    // "some arithmetic that compiles", and every address checksum built on it is
    // self-consistently wrong.
    @Test("matches the published vectors")
    func vectors() {
        #expect(
            hex(SHA256.hash([])) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            hex(SHA256.hash(Array("abc".utf8)))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(
            hex(SHA256.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)))
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    @Test("handles inputs spanning the padding boundary")
    func paddingBoundary() {
        // 55, 56 and 64 bytes straddle the point where the length no longer fits in the
        // final block and a whole extra block is appended.
        for length in [54, 55, 56, 57, 63, 64, 65] {
            let digest = SHA256.hash([UInt8](repeating: 0x61, count: length))
            #expect(digest.count == 32, "length \(length) produced \(digest.count) bytes")
        }
        #expect(
            hex(SHA256.hash([UInt8](repeating: 0x61, count: 56)))
                == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
        )
    }
}

@Suite("Crypto addresses")
struct CryptoTests {

    private static let base58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// Decodes Base58 and verifies the trailing four bytes are the double-SHA-256 prefix.
    private func base58CheckIsValid(_ address: String) -> Bool {
        var number: [UInt8] = [0]
        for character in address {
            guard let digit = Self.base58.firstIndex(of: character) else { return false }
            var carry = digit
            for i in 0..<number.count {
                carry += Int(number[i]) * 58
                number[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                number.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        var bytes = [UInt8](number.reversed())
        for character in address {
            if character != "1" { break }
            bytes.insert(0, at: 0)
        }
        while bytes.count > 25, bytes.first == 0 { bytes.removeFirst() }

        guard bytes.count == 25 else { return false }
        let body = Array(bytes.prefix(21))
        return Array(bytes.suffix(4)) == Array(SHA256.doubleHash(body).prefix(4))
    }

    @Test("bitcoin addresses carry a verifying checksum")
    func bitcoinChecksum() {
        var f = Faker(seed: 1337)
        for _ in 0..<100 {
            let address = f.crypto.bitcoinAddress()
            #expect(address.hasPrefix("1"), "P2PKH addresses start with 1, got \(address)")
            #expect(base58CheckIsValid(address), "checksum failed for \(address)")
        }
    }

    @Test("P2SH addresses carry a verifying checksum")
    func p2shChecksum() {
        var f = Faker(seed: 99)
        for _ in 0..<100 {
            let address = f.crypto.p2shAddress()
            #expect(address.hasPrefix("3"), "P2SH addresses start with 3, got \(address)")
            #expect(base58CheckIsValid(address), "checksum failed for \(address)")
        }
    }

    @Test("addresses never contain Base58's excluded characters")
    func base58Alphabet() {
        var f = Faker(seed: 7)
        for _ in 0..<200 {
            let address = f.crypto.bitcoinAddress()
            #expect(
                !address.contains(where: { "0OIl".contains($0) }),
                "\(address) contains a character Base58 excludes"
            )
        }
    }

    @Test("bech32 addresses verify against the BIP-173 polymod")
    func bech32Checksum() {
        var f = Faker(seed: 2026)
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

        for _ in 0..<100 {
            let address = f.crypto.bech32Address()
            #expect(address.hasPrefix("bc1q"), "expected a v0 SegWit address, got \(address)")
            #expect(address.lowercased() == address, "bech32 must not be mixed case")

            let data = address.dropFirst(3)  // strip "bc1"
            var values = [UInt8]()
            for character in data {
                guard let index = charset.firstIndex(of: character) else {
                    return #expect(Bool(false), "\(address) has a non-bech32 character")
                }
                values.append(UInt8(index))
            }

            var expanded: [UInt8] = [98 >> 5, 99 >> 5, 0, 98 & 31, 99 & 31]
            expanded.append(contentsOf: values)
            #expect(
                CryptoFaker.bech32PolymodForTesting(expanded) == 1,
                "polymod failed for \(address)"
            )
        }
    }

    @Test("ethereum addresses are 0x and 40 hex digits")
    func ethereumShape() {
        var f = Faker(seed: 5)
        for _ in 0..<100 {
            let address = f.crypto.ethereumAddress()
            #expect(address.hasPrefix("0x"))
            #expect(address.count == 42)
            #expect(address.dropFirst(2).allSatisfy { "0123456789abcdef".contains($0) })
        }
    }

    @Test("digests have the right width")
    func digestWidths() {
        var f = Faker(seed: 1)
        #expect(f.crypto.md5().count == 32)
        #expect(f.crypto.sha1().count == 40)
        #expect(f.crypto.sha256().count == 64)
        #expect(f.crypto.sha512().count == 128)
        var g = Faker(seed: 1)
        #expect(g.crypto.md5().allSatisfy { $0.isHexDigit })
    }

    @Test("the same seed reproduces the same addresses")
    func deterministic() {
        var a = Faker(seed: 4242)
        var b = Faker(seed: 4242)
        #expect(a.crypto.bitcoinAddress() == b.crypto.bitcoinAddress())
        #expect(a.crypto.bech32Address() == b.crypto.bech32Address())
        #expect(a.crypto.sha256() == b.crypto.sha256())
    }

    @Test("finance.bitcoinAddress now produces a valid address too")
    func financeDelegates() {
        var f = Faker(seed: 11)
        let address = f.finance.bitcoinAddress()
        #expect(base58CheckIsValid(address), "checksum failed for \(address)")
    }
}
