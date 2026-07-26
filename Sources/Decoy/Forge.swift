/// A reusable recipe for generating values of `T`.
///
/// `Forge` is a value type, and that is load-bearing rather than incidental: every
/// builder method returns a copy, so specialising a recipe is just assignment.
/// Where other factory libraries need an explicit inheritance feature, Swift gives
/// it away:
///
/// ```swift
/// let users  = Forge<User> { User() }.rule(\.name) { $0.name.fullName() }
/// let admins = users.rule(\.role) { _ in .admin }   // `users` is untouched
/// ```
///
/// Rules run in declaration order, so a later rule can read what an earlier one
/// wrote.
///
/// ## Row independence
///
/// Each row is seeded from `(seed, rowIndex)` rather than continuing one long
/// stream. Row 500 is therefore the same value whether you generated 1,000 rows or
/// asked for rows `500..<600` directly — which is what makes
/// ``generate(rows:seed:)`` safe to run in parallel, and what lets an interrupted
/// ten-million-row seed run resume where it stopped.
public struct Forge<T>: Sendable {

    /// Produces the blank instance that rules are applied to.
    ///
    /// An explicit factory rather than an `init()` requirement: it keeps `Forge`
    /// usable with types that have no sensible empty state, and avoids needing a
    /// macro to synthesise one.
    private let factory: @Sendable () -> T

    private var steps: [Step] = []
    private var finishers: [@Sendable (inout Faker, inout T) throws -> Void] = []

    /// Number of `unique` rules, so a run can size its bookkeeping up front.
    private var uniqueSlots: Int = 0

    private struct Step: Sendable {
        let apply: @Sendable (inout Faker, inout T, inout [Set<AnyHashable>]) throws -> Void
    }

    public init(_ factory: @escaping @Sendable () -> T) {
        self.factory = factory
    }

    // MARK: - Rules

    /// Assigns a property from a freshly drawn value.
    public func rule<Value>(
        _ keyPath: any WritableKeyPath<T, Value> & Sendable,
        _ body: @escaping @Sendable (inout Faker) throws -> Value
    ) -> Forge {
        appending { faker, target, _ in
            target[keyPath: keyPath] = try body(&faker)
        }
    }

    /// Assigns a property from a value derived from the partially built instance.
    ///
    /// The instance carries whatever earlier rules have already written, which is
    /// what makes internally consistent rows possible — an email that matches the
    /// name, a `fullName` that matches its parts:
    ///
    /// ```swift
    /// .rule(\.firstName) { $0.name.firstName() }
    /// .rule(\.email) { faker, user in "\(user.firstName.lowercased())@example.com" }
    /// ```
    ///
    /// Anything the rule reads must be assigned by an *earlier* rule; reading a
    /// property that has not been written yet yields the factory's default.
    public func rule<Value>(
        _ keyPath: any WritableKeyPath<T, Value> & Sendable,
        _ body: @escaping @Sendable (inout Faker, T) throws -> Value
    ) -> Forge {
        appending { faker, target, _ in
            target[keyPath: keyPath] = try body(&faker, target)
        }
    }

    /// Assigns a property, retrying until the value has not been used in this run.
    ///
    /// For columns under a unique constraint — email, username, slug. Uniqueness is
    /// scoped to a single `generate` call, which is the scope that matters when the
    /// output is going into one table.
    ///
    /// Throws `ForgeError.uniqueConstraintExhausted` after `attempts` failures
    /// rather than looping forever, since the usual cause is a source pool smaller
    /// than the requested row count.
    ///
    /// - Note: Uniqueness requires rows to see each other, so a forge using this
    ///   cannot be split with ``generate(rows:seed:)``.
    public func rule<Value: Hashable & Sendable>(
        unique keyPath: any WritableKeyPath<T, Value> & Sendable,
        attempts: Int = 1_000,
        _ body: @escaping @Sendable (inout Faker) throws -> Value
    ) -> Forge {
        precondition(attempts > 0, "attempts must be positive")
        var copy = self
        let slot = copy.uniqueSlots
        copy.uniqueSlots += 1
        copy.steps.append(
            Step { faker, target, used in
                for _ in 0..<attempts {
                    let candidate = try body(&faker)
                    if used[slot].insert(AnyHashable(candidate)).inserted {
                        target[keyPath: keyPath] = candidate
                        return
                    }
                }
                throw ForgeError.uniqueConstraintExhausted(
                    property: String(describing: keyPath),
                    attempts: attempts
                )
            }
        )
        return copy
    }

    /// Assigns values from `values` in round-robin order by row index.
    ///
    /// Guarantees even coverage where a random draw would leave gaps — useful when
    /// every enum case must appear at least once. For realistic-but-uneven
    /// distributions use ``Faker/weighted(_:)`` instead.
    public func cycle<Value: Sendable>(
        _ keyPath: any WritableKeyPath<T, Value> & Sendable,
        through values: [Value]
    ) -> Forge {
        precondition(!values.isEmpty, "cycle requires at least one value")
        return appending { faker, target, _ in
            target[keyPath: keyPath] = values[faker.index % values.count]
        }
    }

    /// Populates a nested collection with `count` children per parent.
    ///
    /// The one-to-many half of referential integrity — ``Faker/pick(_:)`` covers
    /// many-to-one. Each child batch draws its seed from the parent's stream, so
    /// children stay reproducible and stay tied to the parent that owns them.
    public func each<Child>(
        _ keyPath: any WritableKeyPath<T, [Child]> & Sendable,
        _ count: ClosedRange<Int>,
        of child: Forge<Child>
    ) -> Forge {
        precondition(count.lowerBound >= 0, "count must not be negative")
        return appending { faker, target, _ in
            let n = faker.int(in: count)
            let childSeed = faker.rng.next()
            target[keyPath: keyPath] = try child.runGenerate(rows: 0..<n, seed: childSeed)
        }
    }

    /// Runs after every rule, for cross-cutting adjustments that do not belong to a
    /// single property.
    public func finish(
        _ body: @escaping @Sendable (inout Faker, inout T) throws -> Void
    ) -> Forge {
        var copy = self
        copy.finishers.append(body)
        return copy
    }

    /// Returns a copy with the given traits applied.
    public func applying(_ traits: Trait<T>...) -> Forge {
        traits.reduce(self) { $1.transform($0) }
    }

    private func appending(
        _ apply: @escaping @Sendable (inout Faker, inout T, inout [Set<AnyHashable>]) throws -> Void
    ) -> Forge {
        var copy = self
        copy.steps.append(Step(apply: apply))
        return copy
    }

    // MARK: - Generation

    /// Generates `count` values.
    ///
    /// Traps if a rule throws. Fixtures are development-time tooling, so a loud
    /// failure with a legible message beats error handling nobody writes — use
    /// ``tryGenerate(_:seed:applying:)`` when you genuinely want to recover.
    public func generate(_ count: Int, seed: UInt64, applying traits: Trait<T>...) -> [T] {
        precondition(count >= 0, "count must not be negative")
        return trapping { try runGenerate(rows: 0..<count, seed: seed, traits: traits) }
    }

    /// Generates `count` values, throwing on rule failure or unique exhaustion.
    public func tryGenerate(
        _ count: Int,
        seed: UInt64,
        applying traits: Trait<T>...
    ) throws -> [T] {
        precondition(count >= 0, "count must not be negative")
        return try runGenerate(rows: 0..<count, seed: seed, traits: traits)
    }

    /// Generates a specific slice of rows from a run.
    ///
    /// Because rows are independent, this returns exactly what the same indices of
    /// ``generate(_:seed:applying:)`` would — so a large seed job can be split
    /// across tasks, or resumed after a failure:
    ///
    /// ```swift
    /// await withTaskGroup { group in
    ///     for chunk in stride(from: 0, to: 1_000_000, by: 50_000) {
    ///         group.addTask { forge.generate(rows: chunk..<chunk + 50_000, seed: 1337) }
    ///     }
    /// }
    /// ```
    ///
    /// - Precondition: the forge has no `unique` rules. Uniqueness needs rows to see
    ///   each other, which chunks by definition cannot do — silently allowing it
    ///   would produce duplicate values that only surface as a constraint violation
    ///   at insert time.
    public func generate(rows: Range<Int>, seed: UInt64, applying traits: Trait<T>...) -> [T] {
        precondition(rows.lowerBound >= 0, "row indices must not be negative")
        precondition(
            uniqueSlots == 0,
            """
            generate(rows:seed:) cannot be used with `unique` rules: separate chunks \
            cannot see each other's values, so uniqueness could not be honoured. \
            Use generate(_:seed:) for the whole run instead.
            """
        )
        return trapping { try runGenerate(rows: rows, seed: seed, traits: traits) }
    }

    /// Generates a single value.
    public func one(seed: UInt64, applying traits: Trait<T>...) -> T {
        trapping { try runGenerate(rows: 0..<1, seed: seed, traits: traits)[0] }
    }

    /// An unbounded lazy sequence of generated values.
    ///
    /// Nothing is produced until iterated and nothing is retained afterwards, so
    /// millions of rows can be streamed into a database without ever holding them
    /// all in memory. Traps on rule failure, matching ``generate(_:seed:applying:)``.
    ///
    /// ```swift
    /// for user in users.stream(seed: 1337).prefix(10_000_000) {
    ///     try await db.insert(user)
    /// }
    /// ```
    public func stream(seed: UInt64, applying traits: Trait<T>...) -> ForgeSequence<T> {
        ForgeSequence(run: makeRun(seed: seed, traits: traits, startingAt: 0))
    }

    func runGenerate(rows: Range<Int>, seed: UInt64, traits: [Trait<T>] = []) throws -> [T] {
        var run = makeRun(seed: seed, traits: traits, startingAt: rows.lowerBound)
        var result = [T]()
        result.reserveCapacity(rows.count)
        for _ in rows {
            result.append(try run.nextOrThrow())
        }
        return result
    }

    private func makeRun(seed: UInt64, traits: [Trait<T>], startingAt row: Int) -> ForgeRun<T> {
        let resolved = traits.reduce(self) { $1.transform($0) }
        return ForgeRun(
            factory: resolved.factory,
            steps: resolved.steps.map(\.apply),
            finishers: resolved.finishers,
            uniqueSlots: resolved.uniqueSlots,
            baseSeed: SeedDerivation.derive(seed, for: T.self),
            startingAt: row
        )
    }

    private func trapping<R>(_ body: () throws -> R) -> R {
        do {
            return try body()
        } catch {
            preconditionFailure("Decoy: generation failed — \(error)")
        }
    }
}

/// The mutable state of one generation run.
///
/// Split out from `Forge` so the recipe stays an immutable, `Sendable` value that can
/// be shared across tasks, while each run keeps its own row cursor and uniqueness
/// bookkeeping.
struct ForgeRun<T> {
    private let factory: @Sendable () -> T
    private let steps: [@Sendable (inout Faker, inout T, inout [Set<AnyHashable>]) throws -> Void]
    private let finishers: [@Sendable (inout Faker, inout T) throws -> Void]
    private let baseSeed: UInt64
    private var used: [Set<AnyHashable>]
    private var row: Int

    init(
        factory: @escaping @Sendable () -> T,
        steps: [@Sendable (inout Faker, inout T, inout [Set<AnyHashable>]) throws -> Void],
        finishers: [@Sendable (inout Faker, inout T) throws -> Void],
        uniqueSlots: Int,
        baseSeed: UInt64,
        startingAt row: Int
    ) {
        self.factory = factory
        self.steps = steps
        self.finishers = finishers
        self.baseSeed = baseSeed
        self.used = Array(repeating: [], count: uniqueSlots)
        self.row = row
    }

    mutating func nextOrThrow() throws -> T {
        var faker = Faker(seed: SeedDerivation.rowSeed(baseSeed, row: row), index: row)
        row += 1

        var value = factory()
        for step in steps {
            try step(&faker, &value, &used)
        }
        for finisher in finishers {
            try finisher(&faker, &value)
        }
        return value
    }
}

/// The lazy sequence returned by ``Forge/stream(seed:applying:)``.
public struct ForgeSequence<T>: Sequence, IteratorProtocol {
    private var run: ForgeRun<T>

    init(run: ForgeRun<T>) {
        self.run = run
    }

    public mutating func next() -> T? {
        do {
            return try run.nextOrThrow()
        } catch {
            preconditionFailure("Decoy: generation failed — \(error)")
        }
    }
}

/// A named, reusable bundle of rule overrides.
///
/// Traits are values rather than the strings the Ruby and Python factory libraries
/// use, so they are checked at compile time and get static-member lookup at the call
/// site:
///
/// ```swift
/// extension Trait where T == User {
///     static var admin: Trait {
///         Trait("admin") { $0.rule(\.role) { _ in .admin } }
///     }
/// }
///
/// let staff = users.generate(10, seed: 1337, applying: .admin)
/// ```
public struct Trait<T>: Sendable {
    public let name: String
    let transform: @Sendable (Forge<T>) -> Forge<T>

    public init(_ name: String, _ transform: @escaping @Sendable (Forge<T>) -> Forge<T>) {
        self.name = name
        self.transform = transform
    }
}

public enum ForgeError: Error, CustomStringConvertible {
    case uniqueConstraintExhausted(property: String, attempts: Int)

    public var description: String {
        switch self {
        case .uniqueConstraintExhausted(let property, let attempts):
            return """
                could not find an unused value for \(property) in \(attempts) attempts. \
                The source pool is probably smaller than the number of rows requested.
                """
        }
    }
}

/// Derives reproducible seeds for entity types and individual rows.
enum SeedDerivation {

    /// FNV-1a, chosen because it is specified rather than because it is fast.
    ///
    /// Swift's `Hasher` is seeded randomly per process, so `hashValue` differs
    /// between runs of the same binary — using it here would break reproducibility
    /// in exactly the way this library exists to prevent.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Gives each entity type its own stream from one user-facing seed.
    ///
    /// Without this, `Forge<User>` and `Forge<Order>` seeded 1337 would draw
    /// identical bits, correlating unrelated tables and making a rule added to
    /// `User` silently shift every `Order`.
    static func derive(_ seed: UInt64, for type: Any.Type) -> UInt64 {
        var expander = SplitMix64(seed: seed ^ fnv1a(String(reflecting: type)))
        return expander.next()
    }

    /// Gives each row its own stream, so rows do not depend on their predecessors.
    static func rowSeed(_ base: UInt64, row: Int) -> UInt64 {
        let mixed = base ^ (UInt64(bitPattern: Int64(row)) &* 0x9E37_79B9_7F4A_7C15)
        var expander = SplitMix64(seed: mixed)
        return expander.next()
    }
}
