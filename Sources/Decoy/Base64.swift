/// Base64 decoding for embedded corpora.
///
/// Exists because of how a corpus gets into a binary. `Bundle.module` is out — it is
/// the most platform-fragile part of SPM and a large share of Fakery's trouble off
/// macOS. A Swift `[UInt8]` literal is worse: a 296 KB blob as an array literal does
/// not finish type-checking in two minutes. A base64 `StaticString` compiles in 0.07
/// seconds and decodes in about 0.2 ms, so the corpus is ordinary Swift source that
/// links into the binary with no resource lookup at all.
///
/// Foundation-free, so generated locale modules stay as portable as the core.
public enum Base64 {

    /// Decodes standard base64. Whitespace is skipped; other invalid input returns nil.
    public static func decode(_ text: StaticString) -> [UInt8]? {
        text.withUTF8Buffer { decode($0) }
    }

    public static func decode(_ text: some Sequence<UInt8>) -> [UInt8]? {
        var out = [UInt8]()
        var accumulator: UInt32 = 0
        var bitsCollected = 0

        for byte in text {
            // Padding ends the payload; anything after it is ignored.
            if byte == UInt8(ascii: "=") { break }
            if byte == 0x0A || byte == 0x0D || byte == 0x20 || byte == 0x09 { continue }

            guard let value = sextet(byte) else { return nil }
            accumulator = (accumulator << 6) | UInt32(value)
            bitsCollected += 6

            if bitsCollected >= 8 {
                bitsCollected -= 8
                out.append(UInt8truncating(accumulator >> UInt32(bitsCollected)))
            }
        }

        // Leftover bits are the padding remainder and must be zero; anything else
        // means the input was truncated mid-character rather than merely padded.
        guard bitsCollected < 6 else { return nil }
        let mask = (UInt32(1) << UInt32(bitsCollected)) - 1
        guard accumulator & mask == 0 else { return nil }
        return out
    }

    @inline(__always)
    private static func sextet(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "+"): return 62
        case UInt8(ascii: "/"): return 63
        default: return nil
        }
    }

    @inline(__always)
    private static func UInt8truncating(_ value: UInt32) -> UInt8 {
        UInt8(truncatingIfNeeded: value)
    }

    /// Encodes bytes as standard base64 with padding.
    ///
    /// Used by the corpus compiler to generate locale modules; kept here so encoder
    /// and decoder cannot drift apart.
    public static func encode(_ bytes: some Collection<UInt8>) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var out = String()
        out.reserveCapacity((bytes.count + 2) / 3 * 4)

        var buffer: UInt32 = 0
        var pending = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            pending += 8
            while pending >= 6 {
                pending -= 6
                out.append(alphabet[Int((buffer >> UInt32(pending)) & 0x3F)])
            }
        }
        if pending > 0 {
            out.append(alphabet[Int((buffer << UInt32(6 - pending)) & 0x3F)])
        }
        while out.count % 4 != 0 { out.append("=") }
        return out
    }
}
