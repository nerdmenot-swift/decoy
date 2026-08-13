import Testing

@testable import DecoyAdapterKit

/// SHA-512 against the published vectors.
///
/// This exists because the alternative to writing SHA-512 was taking swift-crypto as the
/// package's first external dependency. That trade is only defensible if the
/// implementation is actually right, and "it produced a plausible-looking hex string" is
/// not evidence. The cases below are the ones where a hand-rolled implementation really
/// fails: the empty input, the exact block boundary, and the lengths either side of it
/// where the padding rule changes.
@Suite("SHA-512")
struct SHA512Tests {

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func hash(_ string: String) -> String {
        hex(SHA512.hash([UInt8](string.utf8)))
    }

    @Test("FIPS 180-4 published vectors")
    func published() {
        // The empty string. Gets the padding rule wrong and this is what changes first.
        #expect(
            hash("") == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
                + "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")

        #expect(
            hash("abc") == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                + "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")

        // 112 bytes: two blocks, and the length field lands in the second.
        #expect(
            hash(
                "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
                    + "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")
                == "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018"
                + "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909")
    }

    /// The padding boundary, which is where an off-by-one lives.
    ///
    /// A message is padded to 112 bytes mod 128, so at 111, 112 and 113 bytes the block
    /// count changes. An implementation that pads with `>=` instead of `!=`, or that
    /// forgets 112 needs a whole extra block, passes every short vector and fails here.
    ///
    /// These digests were produced by `shasum -a 512` rather than written from memory,
    /// which is the only way a test like this is worth anything.
    @Test("lengths around the block boundary")
    func boundary() {
        let expected: [Int: String] = [
            111: "fa9121c7b32b9e01733d034cfc78cbf67f926c7ed83e82200ef8681819692176"
                + "0b4beff48404df811b953828274461673c68d04e297b0eb7b2b4d60fc6b566a2",
            112: "c01d080efd492776a1c43bd23dd99d0a2e626d481e16782e75d54c2503b5dc32"
                + "bd05f0f1ba33e568b88fd2d970929b719ecbb152f58f130a407c8830604b70ca",
            113: "55ddd8ac210a6e18ba1ee055af84c966e0dbff091c43580ae1be703bdb85da31"
                + "acf6948cf5bd90c55a20e5450f22fb89bd8d0085e39f85a86cc46abbca75e24d",
            127: "828613968b501dc00a97e08c73b118aa8876c26b8aac93df128502ab360f91ba"
                + "b50a51e088769a5c1eff4782ace147dce3642554199876374291f5d921629502",
            128: "b73d1929aa615934e61a871596b3f3b33359f42b8175602e89f7e06e5f658a24"
                + "3667807ed300314b95cacdd579f3e33abdfbe351909519a846d465c59582f321",
            129: "4f681e0bd53cda4b5a2041cc8a06f2eabde44fb16c951fbd5b87702f07aeab61"
                + "1565b19c47fde30587177ebb852e3971bbd8d3fd30da18d71037dfbd98420429",
        ]
        for (length, digest) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(
                hash(String(repeating: "a", count: length)) == digest,
                "\(length) bytes of 'a'")
        }
    }

    @Test("a byte changed anywhere changes the digest")
    func sensitivity() {
        // The property the integrity check actually relies on. A hash that ignored, say,
        // the final block would still pass the vectors above if they were short enough.
        let base = [UInt8](repeating: 7, count: 5000)
        let first = SHA512.hash(base)
        for position in [0, 127, 128, 2499, 4999] {
            var altered = base
            altered[position] ^= 1
            #expect(SHA512.hash(altered) != first, "byte \(position) did not affect the digest")
        }
    }

    @Test("length is always 64 bytes")
    func width() {
        for count in [0, 1, 55, 111, 112, 127, 128, 129, 1000] {
            #expect(SHA512.hash([UInt8](repeating: 0, count: count)).count == 64)
        }
    }
}
