/// Fits a character-level n-gram model to a word list.
///
/// A direct port of `lib/ngram.mjs`, and the piece of the pipeline where "close enough" is
/// worthless: these models are what `novelNames()` draws from, they are baked into the
/// corpus, and a subtly different trainer changes the names people generate without
/// changing anything that looks like an error. So the port preserves ordering decisions
/// that a rewrite would naturally tidy away, and `NGramParityTests` compares the output
/// against the models the JavaScript actually produced.
///
/// The reasoning behind the design belongs to the original and is not repeated here; what
/// follows records only what the *port* has to be careful about.
public enum NGram {

    /// The end-of-word sentinel. Alphabet index 0, and never a real character.
    public static let end = 0

    /// Below this many distinct values, a model is not worth building.
    public static let minimumTrainingValues = 100

    public struct Transition: Sendable, Equatable {
        public let symbol: Int
        public let weight: Int
    }

    public struct Context: Sendable, Equatable {
        public let key: UInt64
        public let transitions: [Transition]
    }

    public struct Model: Sendable, Equatable {
        public let order: Int
        public let alphabet: [String]
        public let contexts: [Context]
        public let minLength: Int
        public let maxLength: Int
    }

    public enum Failure: Error, CustomStringConvertible {
        case tooFewValues(Int)
        case orderOutOfRange(Int)
        case alphabetTooLarge(Int)

        public var description: String {
            switch self {
            case .tooFewValues(let count):
                return
                    "\(count) values is below MINIMUM_TRAINING_VALUES (\(minimumTrainingValues))"
            case .orderOutOfRange(let order):
                return "order must be 2...4, got \(order)"
            case .alphabetTooLarge(let count):
                return
                    "\(count) distinct characters exceeds the 65,535 a packed context key allows"
            }
        }
    }

    /// Code points, not Characters.
    ///
    /// Swift's Character is an extended grapheme cluster; JavaScript's `for...of` and
    /// spread iterate Unicode *scalars*. For "и́" — и followed by a combining acute — that
    /// is one Character and two code points, so a Character-based port gives a different
    /// alphabet, different symbol indices, different packed context keys and ultimately
    /// different generated names. Caught by NGramParityTests against the real Russian and
    /// Polish lists; it is the same trap as CRLF being a single Character on Windows.
    ///
    /// The median length, which decides how much context a word can spare.
    public static func typicalLength(_ words: [String]) -> Int {
        guard !words.isEmpty else { return 0 }
        let lengths = words.map { $0.unicodeScalars.count }.sorted()
        return lengths[lengths.count / 2]
    }

    /// The n-gram order, from how much there is to learn from.
    ///
    /// Returns nil below the training floor, matching the JavaScript's `null`.
    public static func orderFor(count: Int, typicalLength: Int = Int.max) -> Int? {
        guard count >= minimumTrainingValues else { return nil }
        let byLength = max(2, typicalLength)
        let bySize = count > 5000 ? 4 : 3
        return min(bySize, byLength, 4)
    }

    /// Transitions seen fewer times than this are dropped.
    public static func minCountFor(_ count: Int) -> Int { count > 5000 ? 2 : 1 }

    /// Insertion-ordered dedup.
    ///
    /// `[...new Set(words)]` in JavaScript preserves first-insertion order, and Swift's Set
    /// does not preserve anything. That difference is not cosmetic: the surviving order
    /// decides the order characters are first seen, which decides their alphabet indices,
    /// which changes every packed context key and every symbol in the model. Using a Set
    /// here would produce a model that is correct and completely different.
    static func distinct(_ words: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        ordered.reserveCapacity(words.count)
        for word in words where seen.insert(word).inserted { ordered.append(word) }
        return ordered
    }

    /// Packs a context into the u64 key the corpus format uses: length in the top byte,
    /// symbols below it, most recent last.
    static func pack(_ symbols: [Int]) -> UInt64 {
        var packed = UInt64(symbols.count) << 56
        for (offset, symbol) in symbols.enumerated() {
            packed |= UInt64(symbol) << UInt64(offset * 16)
        }
        return packed
    }

    /// Counts every (context, next-symbol) pair in `words`.
    public static func train(_ words: [String], order requestedOrder: Int? = nil,
                             minCount requestedMinCount: Int? = nil) throws -> Model {
        let words = distinct(words)
        guard
            let order = requestedOrder
                ?? orderFor(count: words.count, typicalLength: typicalLength(words))
        else { throw Failure.tooFewValues(words.count) }
        guard (2...4).contains(order) else { throw Failure.orderOutOfRange(order) }
        let minCount = requestedMinCount ?? minCountFor(words.count)

        // Alphabet in first-appearance order, so a re-run over the same list is identical.
        var symbolOf: [Unicode.Scalar: Int] = [:]
        var alphabet: [String] = [""]
        for word in words {
            for scalar in word.unicodeScalars where symbolOf[scalar] == nil {
                symbolOf[scalar] = alphabet.count
                alphabet.append(String(scalar))
            }
        }
        guard alphabet.count <= 65535 else { throw Failure.alphabetTooLarge(alphabet.count) }

        // Keyed by the packed context. The JavaScript keys by a comma-joined string and
        // packs afterwards; packing up front is the same mapping because length is part of
        // the key, so [0] and [0,0] cannot collide.
        var counts: [UInt64: [Int: Int]] = [:]
        let padding = [Int](repeating: end, count: order - 1)

        for word in words {
            let symbols = padding + word.unicodeScalars.map { symbolOf[$0]! }
            // One extra step past the end so the model learns where words stop.
            for i in (order - 1)...symbols.count {
                let next = i == symbols.count ? end : symbols[i]
                // Every suffix of the padded window. Length 0 is deliberately absent.
                for length in 1...(order - 1) {
                    let key = pack(Array(symbols[(i - length)..<i]))
                    counts[key, default: [:]][next, default: 0] += 1
                }
            }
        }

        var contexts: [Context] = []
        contexts.reserveCapacity(counts.count)
        for (key, row) in counts {
            let transitions = row
                .filter { $0.value >= minCount }
                // Sorted by symbol so the encoding is stable across runs.
                .sorted { $0.key < $1.key }
                .map { Transition(symbol: $0.key, weight: $0.value) }
            // Pruning can empty a context, and a context with no transitions is a dead end
            // the sampler would have to back out of. Dropped rather than shipped empty.
            if !transitions.isEmpty { contexts.append(Context(key: key, transitions: transitions)) }
        }
        contexts.sort { $0.key < $1.key }

        let lengths = words.map { $0.unicodeScalars.count }
        return Model(
            order: order, alphabet: alphabet, contexts: contexts,
            minLength: lengths.min() ?? Int.max, maxLength: lengths.max() ?? 0)
    }

    /// Draws from a trained model, mirroring `Faker.draw(fromModel:)`.
    ///
    /// Here so the trainer can check its own work before shipping it — see `viability`.
    public static func sample(
        _ model: Model, next32: () -> UInt32, maxLength: Int = 64
    ) -> String {
        var byKey: [UInt64: [Transition]] = [:]
        for context in model.contexts { byKey[context.key] = context.transitions }

        var history = [Int](repeating: end, count: model.order - 1)
        var word = ""
        for _ in 0..<maxLength {
            var transitions: [Transition]?
            var length = model.order - 1
            while length >= 1 && transitions == nil {
                transitions = byKey[pack(Array(history.suffix(length)))]
                length -= 1
            }
            guard let choices = transitions, !choices.isEmpty else { break }

            let total = choices.reduce(0) { $0 + $1.weight }
            var roll = Int(next32()) % total
            var picked = choices[choices.count - 1]
            for transition in choices {
                if roll < transition.weight {
                    picked = transition
                    break
                }
                roll -= transition.weight
            }
            if picked.symbol == end { break }
            word += model.alphabet[picked.symbol]
            history.append(picked.symbol)
        }
        return word
    }

    /// Whether a trained model can generate rather than only recite.
    ///
    /// The backstop: a model whose every candidate is rejected by the Bloom filter is not
    /// a conservative model, it is a generator that returns nothing. The seed and the LCG
    /// constants are fixed and match the JavaScript exactly, because the *decision* this
    /// makes has to be the same one — a model the old pipeline shipped and the new one
    /// refuses is a silently smaller corpus.
    public static func viability(
        _ model: Model, words: [String], draws: Int = 400, minimumNovel: Double = 0.5
    ) -> (novel: Double, viable: Bool) {
        let known = Set(words)
        let lengths = words.map { $0.unicodeScalars.count }
        let low = lengths.min() ?? 0
        let high = lengths.max() ?? 0

        var state: UInt64 = 20_260_809
        let next32: () -> UInt32 = {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt32(truncatingIfNeeded: state >> 32)
        }

        var usable = 0
        for _ in 0..<draws {
            let word = sample(model, next32: next32)
            let length = word.unicodeScalars.count
            if !word.isEmpty && length >= low && length <= high && !known.contains(word) {
                usable += 1
            }
        }
        let novel = Double(usable) / Double(draws)
        return (novel, novel >= minimumNovel)
    }
}
