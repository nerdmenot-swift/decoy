import Testing

@testable import Decoy

@Suite("Xoshiro256**")
struct SeededRandomTests {

    /// The whole library rests on this: a seed must produce one specific stream,
    /// forever, on every platform. If this test ever fails, every fixture anyone has
    /// committed has silently changed meaning — so it is pinned to literal values
    /// rather than to a property.
    @Test("stream is pinned to known values")
    func knownAnswers() {
        var g = Xoshiro256StarStar(seed: 1337)
        #expect(g.next() == 0xAD0A_A0A0_4F82_2EDC)
        #expect(g.next() == 0xD081_5851_CE88_5DEF)
        #expect(g.next() == 0xC70B_1747_1E26_3E43)
        #expect(g.next() == 0xEE4D_7F13_899D_E194)
        #expect(g.next() == 0x2DE1_AF70_1A88_7873)
        #expect(g.next() == 0xA78D_7678_94DA_656D)
    }

    /// Seed 0 is the case a naive implementation gets wrong — a sparse initial state
    /// takes many rounds to mix. SplitMix64 expansion is what makes it behave.
    @Test("seed zero is not degenerate")
    func seedZero() {
        var g = Xoshiro256StarStar(seed: 0)
        #expect(g.next() == 0x99EC_5F36_CB75_F2B4)
        #expect(g.next() == 0xBF6E_1F78_4956_452A)
        #expect(g.next() == 0x1A5F_849D_4933_E6E0)
        #expect(g.next() == 0x6AA5_94F1_262D_2D2C)
    }

    @Test("same seed replays the same stream")
    func reproducible() {
        var a = Xoshiro256StarStar(seed: 42)
        var b = Xoshiro256StarStar(seed: 42)
        for _ in 0..<1_000 {
            #expect(a.next() == b.next())
        }
    }

    @Test("adjacent seeds diverge immediately")
    func seedsDiverge() {
        var a = Xoshiro256StarStar(seed: 1)
        var b = Xoshiro256StarStar(seed: 2)
        // Not merely "eventually different" — SplitMix64 expansion should make the
        // very first output differ for neighbouring seeds.
        #expect(a.next() != b.next())
    }

    /// It is a value type, and that is load-bearing: `Forge` copies generators to
    /// give sub-generations independent, still-deterministic streams.
    @Test("copying forks the stream")
    func valueSemantics() {
        var original = Xoshiro256StarStar(seed: 7)
        _ = original.next()

        var fork = original
        let a = original.next()
        let b = fork.next()

        #expect(a == b, "a copy taken at the same point must replay identically")
        #expect(original == fork)
    }
}

@Suite("Deterministic draws")
struct DrawTests {

    @Test("draw(below:) stays in range", arguments: [1, 2, 3, 7, 10, 255, 1_000] as [UInt64])
    func drawBelowInRange(bound: UInt64) {
        var g = Xoshiro256StarStar(seed: 99)
        for _ in 0..<2_000 {
            #expect(g.draw(below: bound) < bound)
        }
    }

    @Test("draw(below:) reaches every value")
    func drawBelowCoversRange() {
        var g = Xoshiro256StarStar(seed: 5)
        var seen = Set<UInt64>()
        for _ in 0..<1_000 { seen.insert(g.draw(below: 6)) }
        #expect(seen == [0, 1, 2, 3, 4, 5])
    }

    @Test("draw(below: 1) is always zero")
    func drawBelowOne() {
        var g = Xoshiro256StarStar(seed: 5)
        for _ in 0..<100 { #expect(g.draw(below: 1) == 0) }
    }

    @Test("draw(in:) honours closed-range bounds, including negatives")
    func drawInClosedRange() {
        var g = Xoshiro256StarStar(seed: 11)
        var sawLow = false
        var sawHigh = false
        for _ in 0..<5_000 {
            let v = g.draw(in: -5...5)
            #expect(v >= -5 && v <= 5)
            if v == -5 { sawLow = true }
            if v == 5 { sawHigh = true }
        }
        #expect(sawLow, "lower bound must be reachable")
        #expect(sawHigh, "upper bound must be reachable — an off-by-one here is silent")
    }

    @Test("draw(in:) handles a single-value range")
    func drawInSingleValue() {
        var g = Xoshiro256StarStar(seed: 11)
        for _ in 0..<100 { #expect(g.draw(in: 3...3) == 3) }
    }

    @Test("drawUnitInterval stays in [0, 1)")
    func unitInterval() {
        var g = Xoshiro256StarStar(seed: 3)
        for _ in 0..<10_000 {
            let v = g.drawUnitInterval()
            #expect(v >= 0.0 && v < 1.0)
        }
    }

    @Test("drawChance saturates at both ends")
    func chanceSaturates() {
        var g = Xoshiro256StarStar(seed: 3)
        for _ in 0..<100 {
            #expect(g.drawChance(0.0) == false)
            #expect(g.drawChance(1.0) == true)
            #expect(g.drawChance(-1.0) == false)
            #expect(g.drawChance(2.0) == true)
        }
    }

    @Test("drawChance is roughly calibrated")
    func chanceCalibrated() {
        var g = Xoshiro256StarStar(seed: 3)
        var hits = 0
        let trials = 20_000
        for _ in 0..<trials where g.drawChance(0.25) { hits += 1 }
        let rate = Double(hits) / Double(trials)
        // Deterministic seed, so this is a fixed value, not a flaky assertion.
        #expect(abs(rate - 0.25) < 0.02)
    }

    @Test("drawElement returns nil for an empty collection")
    func drawElementEmpty() {
        var g = Xoshiro256StarStar(seed: 3)
        #expect(g.drawElement(from: [Int]()) == nil)
    }

    @Test("drawElement only returns members")
    func drawElementMembership() {
        var g = Xoshiro256StarStar(seed: 3)
        let source = ["a", "b", "c", "d"]
        for _ in 0..<500 {
            let picked = g.drawElement(from: source)
            #expect(picked != nil)
            #expect(source.contains(picked!))
        }
    }

    /// A slice whose `startIndex` is not zero is what breaks a naive
    /// `collection[offset]`. `.pick(_:)` on a filtered array of already-generated
    /// rows hits this constantly, and the failure is an out-of-bounds trap.
    @Test("drawElement respects a non-zero startIndex")
    func drawElementSliceOffset() {
        var g = Xoshiro256StarStar(seed: 3)
        let backing = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let source = backing[6...]
        #expect(source.startIndex == 6)

        var seen = Set<Int>()
        for _ in 0..<500 {
            let picked = g.drawElement(from: source)
            #expect(picked != nil)
            #expect(source.contains(picked!))
            seen.insert(picked!)
        }
        #expect(seen == [6, 7, 8, 9])
    }

    /// A collection whose `Index` is genuinely not `Int`.
    @Test("drawElement works on non-Int-indexed collections")
    func drawElementNonIntIndices() {
        var g = Xoshiro256StarStar(seed: 3)
        let source = [1, 2, 3, 4].reversed()
        for _ in 0..<200 {
            let picked = g.drawElement(from: source)
            #expect(picked != nil)
            #expect(source.contains(picked!))
        }
    }
}
