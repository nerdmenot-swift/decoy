/// Deterministic primitive draws.
///
/// These deliberately do **not** call the standard library's `random(in:using:)`.
/// Those methods consume the generator in an unspecified way — the algorithm is an
/// implementation detail that is free to change between Swift releases. That is fine
/// for a game, and disqualifying for a library whose entire promise is that seed
/// 1337 produces the same fixtures on your laptop, in CI, and on a colleague's
/// machine running a different toolchain.
///
/// Everything below is specified here, in terms of wrapping integer arithmetic, so
/// the stream depends on the seed alone.
extension RandomNumberGenerator {

    /// Returns a uniformly distributed value in `0..<upperBound`.
    ///
    /// Uses Lemire's multiply-and-shift with rejection: one multiply in the common
    /// case, and unbiased rather than the subtly-skewed modulo approach.
    mutating func draw(below upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0, "upperBound must be positive")

        var product = next().multipliedFullWidth(by: upperBound)
        if product.low < upperBound {
            // Rejection zone: only the low `upperBound` products are unsafe, so this
            // branch is taken with probability < upperBound / 2^64.
            let threshold = (0 &- upperBound) % upperBound
            while product.low < threshold {
                product = next().multipliedFullWidth(by: upperBound)
            }
        }
        return product.high
    }

    /// Returns a uniformly distributed value in the given closed range.
    mutating func draw(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(bitPattern: Int64(range.upperBound))
            &- UInt64(bitPattern: Int64(range.lowerBound))
        // `span + 1` cannot overflow into 0 unless the range spans the whole of
        // Int64, which `ClosedRange<Int>` cannot express in a single value anyway.
        let offset = draw(below: span &+ 1)
        return Int(Int64(bitPattern: UInt64(bitPattern: Int64(range.lowerBound)) &+ offset))
    }

    /// Returns a uniformly distributed value in `0.0..<1.0`.
    ///
    /// Built from the top 53 bits — exactly the mantissa width of `Double`, so every
    /// representable value in the interval is reachable and none is favoured.
    mutating func drawUnitInterval() -> Double {
        Double(next() &>> 11) * (1.0 / 9_007_199_254_740_992.0)  // 1 / 2^53
    }

    /// Returns `true` with the given probability.
    mutating func drawChance(_ probability: Double) -> Bool {
        if probability <= 0 { return false }
        if probability >= 1 { return true }
        return drawUnitInterval() < probability
    }

    /// Returns a uniformly chosen element, or `nil` if the collection is empty.
    mutating func drawElement<C: RandomAccessCollection>(from collection: C) -> C.Element? {
        guard !collection.isEmpty else { return nil }
        let offset = Int(draw(below: UInt64(collection.count)))
        return collection[collection.index(collection.startIndex, offsetBy: offset)]
    }
}
