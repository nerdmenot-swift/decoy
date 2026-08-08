extension Faker {

    /// The longest a generated word may run before the walk is cut off.
    ///
    /// A backed-off n-gram is not guaranteed to terminate: the shortest context is one
    /// symbol, and if the training data never ended a word after that symbol, the
    /// sentinel has no weight and the walk continues. Rare, and cheap to bound.
    static let maxModelLength = 32

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
            if !model.wasTrainedOn(candidate) { return candidate }
        }
        return nil
    }

    /// One unfiltered pass through the model.
    private mutating func walk(_ model: NGramModel) -> String? {
        var symbols: [UInt16] = []
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
        // The longest usable context, shortened one symbol at a time. Length 0 is the
        // start-of-word distribution, which every model has, so the loop always finds
        // something unless the model is empty.
        var length = Swift.min(model.order - 1, history.count)
        while length >= 0 {
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
