import Foundation

/// Bloom filters over a model's training set and over a profanity blocklist.
///
/// Two filters ride with every shipped model and they answer different questions. The
/// training filter is what makes `novelNames()` mean anything: a candidate the model
/// produces that is already a real name gets rejected, so the guarantee is "not a value
/// this locale actually has" rather than "probably new". The blocklist filter is what
/// stops a character-level model assembling something offensive by accident.
///
/// Sized from a target false-positive rate rather than a round number of bytes, because
/// the rate is the thing with a meaning: it is the share of novel names thrown away for
/// looking real. 1% costs about 1.2 bytes per name.
public enum BloomFilter {

    public struct Built: Sendable, Equatable {
        public let hashCount: Int
        public let bits: [UInt8]
    }

    public struct Blocklist: Sendable, Equatable {
        public let minLength: Int
        public let dropped: Int
        public let hashCount: Int
        public let bits: [UInt8]
    }

    /// FNV-1a over UTF-8, then a SplitMix-style walk for the remaining hashes.
    ///
    /// The constants are not arbitrary and are not this file's to choose: the *reader* in
    /// `Decoy` recomputes exactly this to test membership, so a filter built any other way
    /// would be a filter nothing can read. `SeedDerivation.fnv1a` is the same function.
    static func build(_ words: [String], falsePositiveRate: Double) -> Built {
        let n = max(words.count, 1)
        let ln2 = Foundation.log(2.0)
        let bits = Int(
            (-Double(n) * Foundation.log(falsePositiveRate) / (ln2 * ln2)).rounded(.up))
        let byteCount = Int((Double(bits) / 8).rounded(.up))
        let hashCount = max(1, Int(((Double(bits) / Double(n)) * ln2).rounded()))
        var filter = [UInt8](repeating: 0, count: byteCount)

        let mix: UInt64 = 0x9E37_79B9_7F4A_7C15
        for word in words {
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325
            for byte in word.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
            for _ in 0..<hashCount {
                let bit = Int(hash % UInt64(byteCount * 8))
                filter[bit >> 3] |= UInt8(1 << (bit % 8))
                hash = hash &* mix
                hash ^= hash >> 29
            }
        }
        return Built(hashCount: hashCount, bits: filter)
    }

    /// The filter over a model's own training set.
    public static func overTrainingSet(_ words: [String], falsePositiveRate: Double = 0.01)
        -> Built
    {
        build(words, falsePositiveRate: falsePositiveRate)
    }

    /// The filter over a profanity blocklist.
    ///
    /// Multi-word entries are dropped because they cannot appear inside a single generated
    /// token, and short ones because a three-letter screen would reject a great many
    /// innocent names. A far lower false-positive rate than the training filter: throwing
    /// away a clean name costs a redraw, and letting one through costs rather more.
    public static func overBlocklist(
        _ terms: [String], falsePositiveRate: Double = 1e-6, minLength: Int = 4
    ) -> Blocklist {
        var seen = Set<String>()
        var kept: [String] = []
        for term in terms {
            let normalised = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalised.count >= minLength, !normalised.contains(" ") else { continue }
            if seen.insert(normalised).inserted { kept.append(normalised) }
        }
        kept.sort()
        let built = build(kept, falsePositiveRate: falsePositiveRate)
        return Blocklist(
            minLength: minLength, dropped: terms.count - kept.count,
            hashCount: built.hashCount, bits: built.bits)
    }
}
