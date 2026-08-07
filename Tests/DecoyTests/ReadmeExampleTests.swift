import Foundation
import Testing

@testable import Decoy
@testable import DecoyLocaleDE

/// Compiles the README's examples.
///
/// The parallel-generation example did not compile: it called `generate(rows:seed:)` on
/// `users`, which is the `[User]` array the previous example produced rather than the
/// forge that produced it. Pointed at the forge it would have trapped instead — that
/// forge has a `unique` rule, and `generate(rows:seed:)` refuses those, because separate
/// chunks cannot see each other's values.
///
/// A headline example that does not compile is worse than no example. This suite exists
/// so the ones in the README are the ones that were run.
@Suite("README examples")
struct ReadmeExampleTests {

    struct Event {
        var id = UUID()
        var kind: String = ""
    }

    @Test("the parallel-generation example compiles and reassembles in order")
    func parallelGeneration() async {
        let events = Forge<Event>("event") { Event() }
            .rule(\.id) { $0.uuidV7Value() }
            .rule(\.kind) { $0.pick(["click", "view", "purchase"]) }

        let chunks = await withTaskGroup(of: (Int, [Event]).self) { group in
            for start in stride(from: 0, to: 400, by: 100) {
                group.addTask { (start, events.generate(rows: start..<start + 100, seed: 1337)) }
            }
            return await group.reduce(into: [Int: [Event]]()) { $0[$1.0] = $1.1 }
        }
        let all = chunks.keys.sorted().flatMap { chunks[$0]! }

        #expect(all.count == 400)
        #expect(
            all.map(\.id) == events.generate(400, seed: 1337).map(\.id),
            "chunked generation must reassemble into exactly the sequential result"
        )
    }
}
