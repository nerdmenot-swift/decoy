extension Faker {

    /// The longest a generated word may run before the walk is cut off.
    ///
    /// A backed-off n-gram is not guaranteed to terminate: the shortest context is one
    /// symbol, and if the training data never ended a word after that symbol, the
    /// sentinel has no weight and the walk continues. Rare, and cheap to bound.
    ///
    /// Deliberately far above any real word. This is a runaway guard, not a length
    /// policy — the model carries the training set's own range and the sampler rejects
    /// outside it, so cutting the walk short here would silently truncate a candidate
    /// into something that looks like a valid short name instead of discarding it.
    static let maxModelLength = 64

    /// How many times to redraw when a candidate lands in the training set.
    ///
    /// Each rejection is independent, so exhausting this means the model is degenerate —
    /// trained on so little that it mostly reproduces its input. Trapping there is right:
    /// the alternative is emitting a real person's name, and a corpus that cannot avoid
    /// that should fail loudly at build time rather than quietly at run time.
    static let maxModelAttempts = 24

    /// Draws a value from a trained n-gram at `path`, or `nil` if the chain has no model
    /// there.
    public mutating func drawModel(_ path: String) -> String? {
        guard case .model(let model)? = locale.resolve(path) else { return nil }
        return draw(fromModel: model)
    }

    /// Generates one novel value from `model`.
    ///
    /// The walk keeps a window of the last `order - 1` symbols and asks the model what
    /// follows. When that exact context was never seen — which is most of them, because a
    /// model that had seen every context would be a list — it drops the oldest symbol and
    /// asks again. That is the backoff, and it is what lets the model produce sequences
    /// its training data never contained while still obeying the language's shape.
    ///
    /// **A generated value is never a training-set member.** Every candidate is checked
    /// against the model's Bloom filter and redrawn on a hit. The filter's error is
    /// one-sided, so this rejects some novel values too — the cost of the guarantee, and
    /// the right direction to be wrong in. Fake data that turns out to be a real person's
    /// name is the failure this library cannot have.
    public mutating func draw(fromModel model: NGramModel) -> String? {
        for _ in 0..<Self.maxModelAttempts {
            guard let candidate = walk(model), !candidate.isEmpty else { continue }
            // Length first: it is a count rather than seven hash probes, and it rejects
            // more often than the filter does.
            let length = candidate.count
            guard length >= model.minLength, length <= model.maxLength else { continue }
            if !model.wasTrainedOn(candidate) { return candidate }
        }
        return nil
    }

    /// One unfiltered pass through the model.
    private mutating func walk(_ model: NGramModel) -> String? {
        // Left-padded with the sentinel, so "nothing generated yet" is a real context
        // rather than the empty one. The empty context would be the marginal distribution
        // over every character in the training data, not the start-of-word distribution,
        // and a walk that begins there produces words that start mid-word: `ster`, `rda`,
        // `uck`. The trainer pads identically.
        var symbols = [UInt16](repeating: NGramModel.endSymbol, count: model.order - 1)
        var out = String()

        for _ in 0..<Self.maxModelLength {
            guard let next = step(model, history: symbols) else { break }
            if next == NGramModel.endSymbol { break }
            guard let character = try? model.character(next), !character.isEmpty else { break }
            out += character
            symbols.append(next)
        }
        return out.isEmpty ? nil : out
    }

    /// Asks the model for the next symbol, backing off to shorter contexts.
    private mutating func step(_ model: NGramModel, history: [UInt16]) -> UInt16? {
        // The longest usable context, shortened one symbol at a time. Padding guarantees
        // the history is at least `order - 1` long, so length 1 always exists — the loop
        // stops there rather than at 0, because an empty context would mean the marginal
        // distribution and the trainer does not record one.
        var length = model.order - 1
        while length >= 1 {
            let window = history.suffix(length)
            // Swift flattens `try?` over an optional return, so this is one level of
            // optionality: a throw and a miss both read as nil, and both mean "back off".
            if let context = try? model.context(NGramModel.key(window)) {
                let roll = UInt32(truncatingIfNeeded: rng.next())
                return try? model.sample(context: context, roll: roll)
            }
            length -= 1
        }
        return nil
    }
}
