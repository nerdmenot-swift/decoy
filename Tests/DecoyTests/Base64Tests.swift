import Testing

@testable import Decoy

@Suite("Base64")
struct Base64Tests {

    /// RFC 4648 test vectors, which pin the padding cases a hand-rolled decoder gets
    /// wrong — one and two leftover bytes.
    @Test(
        "matches the RFC 4648 vectors",
        arguments: [
            ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
        ]
    )
    func rfcVectors(plain: String, encoded: String) throws {
        #expect(Base64.encode(Array(plain.utf8)) == encoded)
        let decoded = try #require(Base64.decode(Array(encoded.utf8)))
        #expect(String(decoding: decoded, as: UTF8.self) == plain)
    }

    @Test("round-trips every byte value at every length offset")
    func roundTripExhaustive() throws {
        // Lengths 0-260 cover all three padding remainders many times over, with
        // every byte value appearing in every position within a triplet.
        for length in 0...260 {
            let bytes = (0..<length).map { UInt8(($0 * 7 + length) % 256) }
            let decoded = try #require(Base64.decode(Array(Base64.encode(bytes).utf8)))
            #expect(decoded == bytes, "failed at length \(length)")
        }
    }

    @Test("decodes from a StaticString")
    func staticString() throws {
        let decoded = try #require(Base64.decode("SGVsbG8sIOS4lueVjA==" as StaticString))
        #expect(String(decoding: decoded, as: UTF8.self) == "Hello, 世界")
    }

    @Test("skips whitespace, so wrapped literals decode")
    func whitespace() throws {
        let decoded = try #require(Base64.decode(Array("Zm9v\n YmFy\r\n".utf8)))
        #expect(String(decoding: decoded, as: UTF8.self) == "foobar")
    }

    @Test("rejects characters outside the alphabet")
    func rejectsInvalid() {
        #expect(Base64.decode(Array("Zm9v!".utf8)) == nil)
        #expect(Base64.decode(Array("Zm9-v".utf8)) == nil)
    }

    /// A truncated payload leaves non-zero bits that padding alone cannot explain.
    /// Accepting it would silently yield a short, corrupt corpus.
    @Test("rejects a truncated payload")
    func rejectsTruncated() {
        #expect(Base64.decode(Array("Zg".utf8)) != nil, "'Zg' is a valid unpadded 'f'")
        #expect(Base64.decode(Array("Zh".utf8)) == nil, "stray low bits mean truncation")
    }

    @Test("survives all 256 byte values")
    func allByteValues() throws {
        let bytes = (0...255).map { UInt8($0) }
        let decoded = try #require(Base64.decode(Array(Base64.encode(bytes).utf8)))
        #expect(decoded == bytes)
    }
}
