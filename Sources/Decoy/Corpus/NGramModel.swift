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
/// u32  alphabetCount    symbol 0 is the end-of-word sentinel, not a character
/// u32  arenaIndex       * alphabetCount, each a one-character string
/// u32  contextCount
/// {                     context index, 16-byte stride, sorted by key
///   u64 key             length in the top 8 bits, symbols packed 8 bits each below
///   u32 transitionOffset
///   u32 transitionCount
/// } * contextCount
/// {                     transition blob
///   u16 symbol
///   u16 (reserved)
///   u32 cumulativeWeight
/// } * total
/// u32  filterHashCount  Bloom filter over the training set; see `wasTrainedOn`
/// u32  filterByteCount
/// u8   filterBits       * filterByteCount
/// ```
///
/// The context key is packed into a `u64` rather than stored as a variable-length symbol
/// run so the index keeps a fixed stride and can be binary-searched. That caps the
/// alphabet at 255 symbols and the order at 8, which is far past anything useful: an
/// order-4 model of English surnames already reproduces its training distribution
/// closely, and a larger one mostly memorises.
///
/// Weights are cumulative rather than individual so sampling is one binary search
/// instead of a running sum, matching how weighted string tables already draw.
public struct NGramModel: Sendable {

    /// The largest context this model was trained with; contexts are `order - 1` long.
    public let order: Int
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

    /// The sentinel that ends a generated word. Never a real character.
    static let endSymbol: UInt16 = 0

    /// Caps implied by packing a context into one `u64`.
    static let maxAlphabet = 255
    static let maxOrder = 8

    init(reader: ByteReader, arena: Arena, at offset: Int) throws {
        self.reader = reader
        self.arena = arena
        self.base = offset

        sourceID = try reader.u32(at: offset)
        order = Int(try reader.u32(at: offset + 4))
        alphabetCount = Int(try reader.u32(at: offset + 8))
        guard order >= 2, order <= Self.maxOrder else {
            throw CorpusError.malformed("model order \(order) outside 2...\(Self.maxOrder)")
        }
        guard alphabetCount >= 1, alphabetCount <= Self.maxAlphabet else {
            throw CorpusError.malformed("model alphabet \(alphabetCount) outside 1...255")
        }

        let alphabetAt = offset + 12
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
                Int(try reader.u32(at: last + 8)) / 8 + Int(try reader.u32(at: last + 12))
        }
        let filterHeader = transitionsAt + transitionTotal * 8
        filterHashCount = Int(try reader.u32(at: filterHeader))
        filterByteCount = Int(try reader.u32(at: filterHeader + 4))
        filterAt = filterHeader + 8
    }

    /// The character a symbol stands for. Symbol 0 is the sentinel and has none.
    func character(_ symbol: UInt16) throws -> String {
        guard symbol != Self.endSymbol, Int(symbol) < alphabetCount else { return "" }
        return try arena.string(at: try reader.u32(at: base + 12 + Int(symbol) * 4))
    }

    /// Packs a context into its index key: length in the top byte, symbols below it.
    ///
    /// Most-recent symbol last, so dropping the *oldest* symbol — which is what backing
    /// off does — is a shift and a mask rather than a rebuild.
    static func key(_ symbols: ArraySlice<UInt16>) -> UInt64 {
        var packed = UInt64(symbols.count) << 56
        for (offset, symbol) in symbols.enumerated() {
            packed |= UInt64(symbol & 0xFF) << (UInt64(offset) * 8)
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
        let last = transitionsAt + context.offset + (context.count - 1) * 8
        let total = try reader.u32(at: last + 4)
        guard total > 0 else { return Self.endSymbol }
        let target = roll % total

        var low = 0
        var high = context.count - 1
        while low < high {
            let mid = low + (high - low) / 2
            if try reader.u32(at: transitionsAt + context.offset + mid * 8 + 4) <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return try reader.u16(at: transitionsAt + context.offset + low * 8)
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
