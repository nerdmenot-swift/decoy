/// A seedable, reproducible random number generator.
///
/// `Xoshiro256**` — fast, statistically solid, and with a 256-bit state that is
/// trivially cheap to copy. It is a `struct` deliberately: seeding in Decoy is
/// always local, threaded through as `inout`, never global. A global mutable seed
/// would be a `Sendable` violation under Swift 6 strict concurrency, and is fragile
/// under code changes besides.
///
/// The algorithm is fully specified in terms of `UInt64` wrapping arithmetic, so a
/// given seed produces an identical stream on every platform Decoy supports.
public struct Xoshiro256StarStar: RandomNumberGenerator, Sendable, Equatable {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    /// Seeds the generator from a single 64-bit value.
    ///
    /// The seed is expanded through SplitMix64, as the reference implementation
    /// recommends. This matters: seeding the state directly from a small integer
    /// leaves too many zero bits, and Xoshiro needs many rounds to recover from a
    /// sparse state. SplitMix64 avoids that, and makes seed `0` as good as any other.
    public init(seed: UInt64) {
        var expander = SplitMix64(seed: seed)
        self.s0 = expander.next()
        self.s1 = expander.next()
        self.s2 = expander.next()
        self.s3 = expander.next()
    }

    public mutating func next() -> UInt64 {
        let result = Self.rotl(s1 &* 5, 7) &* 9
        let t = s1 &<< 17

        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = Self.rotl(s3, 45)

        return result
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x &<< k) | (x &>> (64 &- k))
    }
}

/// Expands a single seed value into a well-distributed 64-bit stream.
///
/// Used only to initialise `Xoshiro256StarStar`'s state; not exposed as a general
/// purpose generator.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
