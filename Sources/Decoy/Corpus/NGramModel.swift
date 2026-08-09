/// A character-level n-gram model, read in place from the corpus.
///
/// The reason this exists at all: for names, streets and company names a *list* is the
/// wrong primitive. A list repeats after N draws, which is what makes `unique` rules run
/// dry; it is large, because every value is stored; and it is somebody else's data, with
/// whatever that implies. A model trained on a list generates plausible new values
/// indefinitely, in less space than the list it came from.
///
/// ## Layout
///
/// Everything is little-endian, read byte-wise, and nothing is decoded up front — the
/// model is a view over the corpus bytes in the same way `StringTable` is.
///
/// ```
/// u32  sourceID         which upstream the training data came from
/// u32  order            context length is order - 1
/// u32  minLength        shortest word in the training set
/// u32  maxLength        longest word in the training set
/// u32  alphabetCount    symbol 0 is the end-of-word sentinel, not a character
/// u32  arenaIndex       * alphabetCount, each a one-character string
/// u32  contextCount
/// {                     context index, 16-byte stride, sorted by key
///   u64 key             length in the top 8 bits, symbols packed 8 bits each below
///   u32 transitionOffset
///   u32 transitionCount
/// } * contextCount
/// {                     transition blob, 4 bytes each
///   u16 symbol
///   u16 cumulativeWeight
/// } * total
/// u32  filterHashCount  Bloom filter over the training set; see `wasTrainedOn`
/// u32  filterByteCount
/// u8   filterBits       * filterByteCount
/// u32  blockHashCount   Bloom filter over blocked substrings; see `isBlocked`
/// u32  blockMinLength   shortest substring worth testing
/// u32  blockByteCount
/// u8   blockBits        * blockByteCount
/// ```
///
/// The context key is packed into a `u64` rather than stored as a variable-length symbol
/// run so the index keeps a fixed stride and can be binary-searched. Three 16-bit symbols
/// and a length byte fit exactly, which caps the order at 4 and the alphabet at 65,535.
///
/// The first version used 8-bit symbols for a 255-character alphabet and an order of 8.
/// Both halves of that were wrong. Nothing ever wants order 8 — an order-4 model already
/// tracks its training distribution and a longer context memorises — and 255 characters
/// is not an alphabet, it is a Latin-script assumption: the first Chinese locale to reach
/// the trainer had 980 distinct characters in its name lists.
///
/// Weights are cumulative rather than individual so sampling is one binary search
/// instead of a running sum, matching how weighted string tables already draw.
public struct NGramModel: Sendable {

    /// The largest context this model was trained with; contexts are `order - 1` long.
    public let order: Int

    /// The shortest and longest word the training set contained.
    ///
    /// An n-gram has no notion of total length — it only ever decides what comes next —
    /// so a run of individually plausible bigrams can add up to a 28-character surname
    /// when the longest real one is 15. That happened in 0.8% of draws: rare enough to
    /// miss in a sample, common enough to notice in a fixture set. The sampler rejects
    /// outside this range.
    public let minLength: Int
    public let maxLength: Int
    /// Includes the end-of-word sentinel at index 0.
    public let alphabetCount: Int
    public let contextCount: Int
    /// Which upstream the training data came from — attribution survives training.
    public let sourceID: UInt32

    let reader: ByteReader
    let arena: Arena
    let base: Int
    /// Byte offset of the context index.
    let contextsAt: Int
    /// Byte offset of the transition blob.
    let transitionsAt: Int
    /// Byte offset of the Bloom filter's bit array, and its shape.
    let filterAt: Int
    /// The filter's shape. Public so `decoy-inspect` can report what a model costs — a
    /// model's whole claim is that it is smaller than the list it replaces, and the
    /// filter is most of what it spends.
    public let filterHashCount: Int
    public let filterByteCount: Int

    let blockAt: Int
    public let blockHashCount: Int
    public let blockMinLength: Int
    public let blockByteCount: Int

    /// The sentinel that ends a generated word. Never a real character.
    static let endSymbol: UInt16 = 0

    /// Caps implied by packing a context into one `u64`.
    static let maxAlphabet = 65_535
    static let maxOrder = 4

    init(reader: ByteReader, arena: Arena, at offset: Int) throws {
        self.reader = reader
        self.arena = arena
        self.base = offset

        sourceID = try reader.u32(at: offset)
        order = Int(try reader.u32(at: offset + 4))
        minLength = Int(try reader.u32(at: offset + 8))
        maxLength = Int(try reader.u32(at: offset + 12))
        alphabetCount = Int(try reader.u32(at: offset + 16))
        guard order >= 2, order <= Self.maxOrder else {
            throw CorpusError.malformed("model order \(order) outside 2...\(Self.maxOrder)")
        }
        guard alphabetCount >= 1, alphabetCount <= Self.maxAlphabet else {
            throw CorpusError.malformed(
                "model alphabet \(alphabetCount) outside 1...\(Self.maxAlphabet)")
        }

        let alphabetAt = offset + 20
        let countAt = alphabetAt + alphabetCount * 4
        contextCount = Int(try reader.u32(at: countAt))
        contextsAt = countAt + 4

        let transitionCountAt = contextsAt + contextCount * 16
        transitionsAt = transitionCountAt
        // The transition blob's length is implied by the last context's offset+count,
        // so the filter's position is read from the end of it.
        var transitionTotal = 0
        if contextCount > 0 {
            let last = contextsAt + (contextCount - 1) * 16
            transitionTotal =
                Int(try reader.u32(at: last + 8)) / 4 + Int(try reader.u32(at: last + 12))
        }
        let filterHeader = transitionsAt + transitionTotal * 4
        filterHashCount = Int(try reader.u32(at: filterHeader))
        filterByteCount = Int(try reader.u32(at: filterHeader + 4))
        filterAt = filterHeader + 8

        let blockHeader = filterAt + filterByteCount
        blockHashCount = Int(try reader.u32(at: blockHeader))
        blockMinLength = Swift.max(1, Int(try reader.u32(at: blockHeader + 4)))
        blockByteCount = Int(try reader.u32(at: blockHeader + 8))
        blockAt = blockHeader + 12
    }

    /// Whether `word` contains a blocked substring.
    ///
    /// A character model over English will eventually walk into something offensive, and
    /// "statistically unlikely" is not a thing to tell somebody who found it in their
    /// staging database. Every substring from `blockMinLength` up is tested.
    ///
    /// Only hashes ship, never the terms: a list of slurs in a binary is its own problem,
    /// and keeping them out of the string arena means no path-resolution bug can surface
    /// one as a value. Like ``wasTrainedOn(_:)`` the error is one-sided, so this rejects
    /// a few innocent names and never passes a blocked one.
    public func isBlocked(_ word: String) -> Bool {
        guard blockByteCount > 0 else { return false }
        let characters = Array(word.lowercased())
        guard characters.count >= blockMinLength else { return false }
        let bits = UInt64(blockByteCount) * 8

        for start in 0...(characters.count - blockMinLength) {
            for end in (start + blockMinLength)...characters.count {
                var hash = SeedDerivation.fnv1a(String(characters[start..<end]))
                var hit = true
                for _ in 0..<blockHashCount {
                    let bit = hash % bits
                    guard let value = try? reader.u8(at: blockAt + Int(bit / 8)),
                        value & (1 << UInt8(bit % 8)) != 0
                    else {
                        hit = false
                        break
                    }
                    hash = hash &* 0x9E37_79B9_7F4A_7C15
                    hash ^= hash >> 29
                }
                if hit { return true }
            }
        }
        return false
    }

    /// The character a symbol stands for. Symbol 0 is the sentinel and has none.
    func character(_ symbol: UInt16) throws -> String {
        guard symbol != Self.endSymbol, Int(symbol) < alphabetCount else { return "" }
        return try arena.string(at: try reader.u32(at: base + 20 + Int(symbol) * 4))
    }

    /// Packs a context into its index key: length in the top byte, symbols below it.
    ///
    /// Most-recent symbol last, so dropping the *oldest* symbol — which is what backing
    /// off does — is a shift and a mask rather than a rebuild.
    static func key(_ symbols: ArraySlice<UInt16>) -> UInt64 {
        var packed = UInt64(symbols.count) << 56
        for (offset, symbol) in symbols.enumerated() {
            packed |= UInt64(symbol) << (UInt64(offset) * 16)
        }
        return packed
    }

    /// Finds a context by key. `nil` when the model never saw it.
    func context(_ key: UInt64) throws -> (offset: Int, count: Int)? {
        var low = 0
        var high = contextCount - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let entry = contextsAt + mid * 16
            let found = try reader.u64(at: entry)
            if found < key {
                low = mid + 1
            } else if found > key {
                high = mid - 1
            } else {
                return (Int(try reader.u32(at: entry + 8)), Int(try reader.u32(at: entry + 12)))
            }
        }
        return nil
    }

    /// Draws a symbol from a context's distribution.
    ///
    /// Cumulative weights, so this is a binary search over the transitions rather than a
    /// running sum — the same trick weighted string tables use.
    func sample(context: (offset: Int, count: Int), roll: UInt32) throws -> UInt16 {
        let last = transitionsAt + context.offset + (context.count - 1) * 4
        let total = UInt32(try reader.u16(at: last + 2))
        guard total > 0 else { return Self.endSymbol }
        let target = UInt16(roll % total)

        var low = 0
        var high = context.count - 1
        while low < high {
            let mid = low + (high - low) / 2
            if try reader.u16(at: transitionsAt + context.offset + mid * 4 + 2) <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return try reader.u16(at: transitionsAt + context.offset + low * 4)
    }

    /// Whether the training set probably contained `word`.
    ///
    /// A Bloom filter, so the error is one-sided: a `false` is certain, a `true` may be a
    /// collision. That is the direction that makes it safe to reject on. A generated name
    /// that hashes into the filter is discarded and redrawn, so a real person's name can
    /// never be emitted, at the cost of occasionally throwing away a novel name that
    /// happened to collide.
    ///
    /// Getting this backwards — storing the names themselves — would put the training set
    /// in the binary, which is the thing a model is supposed to avoid shipping.
    public func wasTrainedOn(_ word: String) -> Bool {
        guard filterByteCount > 0 else { return false }
        let bits = UInt64(filterByteCount) * 8
        var hash = SeedDerivation.fnv1a(word)
        for _ in 0..<filterHashCount {
            let bit = hash % bits
            let byte = filterAt + Int(bit / 8)
            guard let value = try? reader.u8(at: byte) else { return false }
            if value & (1 << UInt8(bit % 8)) == 0 { return false }
            // Successive probes from one hash, mixed the way the RNG mixes its state, so
            // the k probes are independent without paying for k hashes of the string.
            hash = hash &* 0x9E37_79B9_7F4A_7C15
            hash ^= hash >> 29
        }
        return true
    }
}
