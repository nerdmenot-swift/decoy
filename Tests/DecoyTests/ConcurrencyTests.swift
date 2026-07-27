import Testing

@testable import Decoy

private struct Row: Equatable, Sendable {
    var index: Int = -1
    var name: String = ""
    var score: Double = 0
}

@Suite("Concurrency and row independence")
struct ConcurrencyTests {

    private var forge: Forge<Row> {
        Forge<Row>("row") { Row() }
            .rule(\.index) { $0.index }
            .rule(\.name) { $0.person.fullName() }
            .rule(\.score) { $0.double(in: 0...100) }
    }

    /// The property that makes parallelism possible: a row depends on its own index
    /// and the seed, not on the rows before it.
    @Test("a slice of rows matches the same slice of the whole run")
    func sliceMatchesWhole() {
        let whole = forge.generate(1_000, seed: 1337)
        let slice = forge.generate(rows: 500..<600, seed: 1337)

        #expect(slice == Array(whole[500..<600]))
    }

    @Test("slices tile the whole run exactly")
    func slicesTile() {
        let whole = forge.generate(1_000, seed: 1337)
        let tiled = stride(from: 0, to: 1_000, by: 137).flatMap {
            forge.generate(rows: $0..<Swift.min($0 + 137, 1_000), seed: 1337)
        }

        #expect(tiled == whole)
    }

    @Test("an empty slice yields nothing")
    func emptySlice() {
        #expect(forge.generate(rows: 40..<40, seed: 1).isEmpty)
    }

    /// A `Forge` crossing an isolation boundary is the whole point of the `Sendable`
    /// work — this test would not compile if it regressed.
    @Test("a forge can be shared across tasks and reassembles into the same run")
    func parallelChunksMatchSequential() async {
        let forge = self.forge
        let sequential = forge.generate(1_000, seed: 1337)
        let chunkSize = 250

        let parallel = await withTaskGroup(of: (Int, [Row]).self) { group in
            for start in stride(from: 0, to: 1_000, by: chunkSize) {
                group.addTask {
                    (start, forge.generate(rows: start..<start + chunkSize, seed: 1337))
                }
            }
            var chunks = [(Int, [Row])]()
            for await chunk in group { chunks.append(chunk) }
            return chunks.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }

        #expect(parallel == sequential)
    }

    /// Concurrent generation must not merely produce *a* valid answer — it must
    /// produce the *same* answer every time, or "reproducible" is worthless the
    /// moment anyone parallelises their seeding.
    @Test("concurrent generation is stable across repeated runs")
    func concurrentIsStable() async {
        let forge = self.forge

        func runConcurrently() async -> [Row] {
            await withTaskGroup(of: (Int, [Row]).self) { group in
                for start in stride(from: 0, to: 400, by: 50) {
                    group.addTask { (start, forge.generate(rows: start..<start + 50, seed: 42)) }
                }
                var chunks = [(Int, [Row])]()
                for await chunk in group { chunks.append(chunk) }
                return chunks.sorted { $0.0 < $1.0 }.flatMap(\.1)
            }
        }

        #expect(await runConcurrently() == (await runConcurrently()))
    }

    /// Neighbouring rows must not accidentally share a stream — a weak row-seed mix
    /// would show up as adjacent rows drawing identical values.
    @Test("adjacent rows are uncorrelated")
    func adjacentRowsDiffer() {
        let rows = forge.generate(500, seed: 1337)
        let scores = rows.map(\.score)
        for i in 1..<scores.count {
            #expect(scores[i] != scores[i - 1])
        }
    }

    @Test("row seeds do not collide across nearby indices")
    func rowSeedsDistinct() {
        let seeds = (0..<10_000).map { SeedDerivation.rowSeed(0xDEAD_BEEF, row: $0) }
        #expect(Set(seeds).count == 10_000)
    }

    @Test("traits survive chunked generation")
    func traitsWithSlices() {
        let boosted = Trait<Row>("boosted") { $0.rule(\.score) { _ in 999 } }
        let slice = forge.generate(rows: 10..<20, seed: 1, applying: boosted)
        #expect(slice.allSatisfy { $0.score == 999 })
    }
}
