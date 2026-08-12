/// A reusable recipe for generating values of `T`.
///
/// `Forge` is a value type, and that is load-bearing rather than incidental: every
/// builder method returns a copy, so specialising a recipe is just assignment.
/// Where other factory libraries need an explicit inheritance feature, Swift gives
/// it away:
///
/// ```swift
/// let users  = Forge<User>("user") { User() }.rule(\.name) { $0.person.fullName() }
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

    /// The locale every generated row draws from.
    private var localeCorpus: LocaleCorpus = .builtIn

    /// Whether `locale(_:)` was called, as opposed to the default still standing.
    ///
    /// A nested forge should speak the parent’s language without being told twice,
    /// but only where it has not chosen one of its own — so this records the
    /// difference between "unset" and "set, and happens to be the built-in".
    private var localeWasSet = false

    /// The instant relative date generation is anchored to.
    private var referenceInstant: Timestamp = .decoyReference
    private var wantsNovelNames = false

    private struct Step: Sendable {
        let apply: @Sendable (inout Faker, inout T, inout [Set<UInt64>]) throws -> Void
    }

    /// Identifies this entity when deriving its seed stream.
    private let entityName: String

    /// Creates a recipe.
    ///
    /// - Parameter name: Identifies this entity's seed stream. Two forges with
    ///   different names draw independent streams from the same seed, so unrelated
    ///   tables do not come out correlated.
    ///
    /// The name is required rather than derived from the type. Reflecting on
    /// `T.self` would work, but it would tie every fixture to the type's
    /// fully-qualified name — renaming `User` to `Account`, or moving it to another
    /// module, would silently change all of its generated data. An explicit name puts
    /// that under your control, and makes the seed contract visible at the call site.
    public init(_ name: String, _ factory: @escaping @Sendable () -> T) {
        self.entityName = name
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
    /// .rule(\.firstName) { $0.person.firstName() }
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
    public func rule<Value: UniqueKey & Sendable>(
        unique keyPath: any WritableKeyPath<T, Value> & Sendable,
        label: String? = nil,
        attempts: Int = 1_000,
        _ body: @escaping @Sendable (inout Faker) throws -> Value
    ) -> Forge {
        precondition(attempts > 0, "attempts must be positive")
        var copy = self
        let slot = copy.uniqueSlots
        copy.uniqueSlots += 1

        // Named by ordinal unless the caller supplies something better. Describing
        // the key path would read nicer but costs reflection, and the message stays
        // actionable without it.
        let described = label ?? "unique rule #\(slot) (pass `label:` to name it)"
        copy.steps.append(
            Step { faker, target, used in
                for _ in 0..<attempts {
                    let candidate = try body(&faker)
                    // Membership is tracked by a 64-bit digest rather than the value.
                    // A collision would make this re-draw a value it has not actually
                    // produced, which costs one extra attempt and leaves the guarantee
                    // -- that no duplicate is ever emitted -- exactly intact.
                    let digest = SeedDerivation.fnv1a(candidate.decoyUniqueKey)
                    if used[slot].insert(digest).inserted {
                        target[keyPath: keyPath] = candidate
                        return
                    }
                }
                throw ForgeError.uniqueConstraintExhausted(
                    property: described,
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
            // The child inherits the parent's locale, anchor and name mode unless it
            // chose its own. Without this a nested forge fell back to the ten-path stub
            // and trapped on the first word it drew, after the parent had already been
            // configured correctly -- which read as a corpus problem rather than a
            // missing call.
            let resolved = child.localeWasSet ? child : child.inheriting(from: self)
            target[keyPath: keyPath] = try resolved.runGenerate(rows: 0..<n, seed: childSeed)
        }
    }

    /// Populates a nested collection with exactly `count` children per parent.
    ///
    /// `each(\.posts, 3, of: posts)` rather than `each(\.posts, 3...3, of: posts)`,
    /// which is the shape a fixture with a fixed fan-out actually wants.
    public func each<Child>(
        _ keyPath: any WritableKeyPath<T, [Child]> & Sendable,
        _ count: Int,
        of child: Forge<Child>
    ) -> Forge {
        each(keyPath, count...count, of: child)
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

    /// Returns a copy that generates from the given locale.
    ///
    /// ```swift
    /// let users = Forge<User>("user") { User() }.locale(german)
    /// ```
    ///
    /// Because a `LocaleCorpus` is just a fallback chain, this is also how you supply
    /// your own data — see ``LocaleCorpus/overlaid(by:)``.
    public func locale(_ locale: LocaleCorpus) -> Forge {
        var copy = self
        copy.localeCorpus = locale
        copy.localeWasSet = true
        return copy
    }

    /// Returns a copy whose name generators produce names no real person has.
    ///
    /// Set once for the whole forge rather than per rule, because the rule somebody
    /// forgets is the one that leaks. See ``Faker/novelNames`` for what it costs and what
    /// it does not cover.
    ///
    /// ```swift
    /// let users = Forge<User>("user") { User() }
    ///     .locale(DecoyLocaleEN.locale)
    ///     .novelNames()
    /// ```
    public func novelNames(_ enabled: Bool = true) -> Forge {
        var copy = self
        copy.wantsNovelNames = enabled
        return copy
    }

    /// Copies the ambient settings a nested forge should share with its parent.
    ///
    /// Deliberately not the rules or the traits: only the configuration a child would
    /// otherwise have to repeat.
    func inheriting<Parent>(from parent: Forge<Parent>) -> Forge {
        var copy = self
        copy.localeCorpus = parent.ambientLocale
        copy.referenceInstant = parent.ambientReference
        copy.wantsNovelNames = parent.ambientNovelNames
        return copy
    }

    var ambientLocale: LocaleCorpus { localeCorpus }
    var ambientReference: Timestamp { referenceInstant }
    var ambientNovelNames: Bool { wantsNovelNames }

    /// Returns a copy whose relative dates are anchored to `instant`.
    ///
    /// Defaults to a fixed constant rather than the system clock, so regenerating a
    /// fixture next year reproduces it exactly. See ``Faker/reference``.
    public func reference(_ instant: Timestamp) -> Forge {
        var copy = self
        copy.referenceInstant = instant
        return copy
    }

    /// Returns a copy with the given traits applied.
    public func applying(_ traits: Trait<T>...) -> Forge {
        traits.reduce(self) { $1.transform($0) }
    }

    private func appending(
        _ apply: @escaping @Sendable (inout Faker, inout T, inout [Set<UInt64>]) throws -> Void
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
    public func generate(_ count: Int, seed: UInt64 = Decoy.randomSeed(),
                         applying traits: Trait<T>...) -> [T] {
        precondition(count >= 0, "count must not be negative")
        return trapping { try runGenerate(rows: 0..<count, seed: seed, traits: traits) }
    }

    /// Generates `count` values, throwing on rule failure or unique exhaustion.
    public func tryGenerate(
        _ count: Int,
        seed: UInt64 = Decoy.randomSeed(),
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
    /// Unlike the whole-run entry points, this has no default seed. Its purpose is
    /// reproducing a slice of one particular run, and a per-call default would hand each
    /// chunk a different seed — silently producing something that is not a slice of
    /// anything.
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
    public func one(seed: UInt64 = Decoy.randomSeed(), applying traits: Trait<T>...) -> T {
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
    public func stream(seed: UInt64 = Decoy.randomSeed(),
                       applying traits: Trait<T>...) -> ForgeSequence<T> {
        ForgeSequence(run: makeRun(seed: seed, traits: traits, startingAt: 0))
    }

    func runGenerate(rows: Range<Int>, seed: UInt64, traits: [Trait<T>] = []) throws -> [T] {
        var run = makeRun(seed: seed, traits: traits, startingAt: rows.lowerBound)
        var result = [T]()
        result.reserveCapacity(rows.count)
        do {
            for _ in rows {
                result.append(try run.nextOrThrow())
            }
        } catch let error as ForgeError {
            // A trait is the usual reason a unique pool runs dry: `.admin` narrowing a
            // role, or a trait pinning a field to one of three values while ten thousand
            // rows are asked for. Naming the traits applied turns "the pool is too small"
            // into something you can act on without bisecting the call site.
            //
            // This is also what `Trait.name` is *for*. It was a stored property nothing
            // read, kept on the argument that a caller might want to log it — which is a
            // use case, not an implementation.
            throw error.mentioning(traits.map(\.name))
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
            baseSeed: SeedDerivation.derive(seed, entity: resolved.entityName),
            locale: resolved.localeCorpus,
            reference: resolved.referenceInstant,
            novelNames: resolved.wantsNovelNames,
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
    private let steps: [@Sendable (inout Faker, inout T, inout [Set<UInt64>]) throws -> Void]
    private let finishers: [@Sendable (inout Faker, inout T) throws -> Void]
    private let baseSeed: UInt64
    private let locale: LocaleCorpus
    private let reference: Timestamp
    private let novelNames: Bool
    private var used: [Set<UInt64>]
    private var row: Int

    init(
        factory: @escaping @Sendable () -> T,
        steps: [@Sendable (inout Faker, inout T, inout [Set<UInt64>]) throws -> Void],
        finishers: [@Sendable (inout Faker, inout T) throws -> Void],
        uniqueSlots: Int,
        baseSeed: UInt64,
        locale: LocaleCorpus,
        reference: Timestamp,
        novelNames: Bool,
        startingAt row: Int
    ) {
        self.factory = factory
        self.steps = steps
        self.finishers = finishers
        self.baseSeed = baseSeed
        self.locale = locale
        self.reference = reference
        self.novelNames = novelNames
        self.used = Array(repeating: [], count: uniqueSlots)
        self.row = row
    }

    mutating func nextOrThrow() throws -> T {
        var faker = Faker(
            seed: SeedDerivation.rowSeed(baseSeed, row: row),
            index: row,
            locale: locale,
            reference: reference,
            novelNames: novelNames
        )
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
///
/// ## Naming this alongside swift-testing
///
/// swift-testing exports a protocol also called `Trait`, so a file importing both cannot
/// spell this one — and `Decoy.Trait` does not help, because the `Decoy` enum shadows the
/// module of the same name. Since fixtures mostly live in tests, that collision is likely.
///
/// Disambiguate with a selective import in the file declaring the extension:
///
/// ```swift
/// import Testing
/// import struct Decoy.Trait
/// import Decoy
/// ```
///
/// Only the declaration needs it. Call sites use static-member lookup (`applying: .admin`),
/// which never names the type.
public struct Trait<T>: Sendable {
    /// What the trait is called.
    ///
    /// Read when a unique constraint runs dry: a trait narrowing a field to three values
    /// while ten thousand rows are requested is the usual cause, and the failure names
    /// the traits in force rather than leaving you to bisect the call site.
    public let name: String
    let transform: @Sendable (Forge<T>) -> Forge<T>

    public init(_ name: String, _ transform: @escaping @Sendable (Forge<T>) -> Forge<T>) {
        self.name = name
        self.transform = transform
    }
}

public enum ForgeError: Error, CustomStringConvertible {
    case uniqueConstraintExhausted(property: String, attempts: Int, traits: [String] = [])

    public var description: String {
        switch self {
        case .uniqueConstraintExhausted(let property, let attempts, let traits):
            let applied = traits.isEmpty
                ? ""
                : " Traits applied: \(traits.joined(separator: ", ")) — a trait narrowing "
                    + "this field is the usual cause."
            return """
                could not find an unused value for \(property) in \(attempts) attempts. \
                The source pool is probably smaller than the number of rows requested.\
                \(applied)
                """
        }
    }

    /// Returns the same error carrying the names of the traits in force when it was
    /// thrown. The rule closure cannot know them — traits are applied by transforming
    /// the forge — so they are attached on the way out.
    func mentioning(_ traits: [String]) -> ForgeError {
        guard !traits.isEmpty else { return self }
        switch self {
        case .uniqueConstraintExhausted(let property, let attempts, let existing):
            return .uniqueConstraintExhausted(
                property: property, attempts: attempts, traits: existing + traits)
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

    /// Gives each entity its own stream from one user-facing seed.
    ///
    /// Without this, `Forge<User>` and `Forge<Order>` seeded 1337 would draw
    /// identical bits, correlating unrelated tables and making a rule added to
    /// `User` silently shift every `Order`.
    static func derive(_ seed: UInt64, entity: String) -> UInt64 {
        var expander = SplitMix64(seed: seed ^ fnv1a(entity))
        return expander.next()
    }

    /// Gives each row its own stream, so rows do not depend on their predecessors.
    static func rowSeed(_ base: UInt64, row: Int) -> UInt64 {
        let mixed = base ^ (UInt64(bitPattern: Int64(row)) &* 0x9E37_79B9_7F4A_7C15)
        var expander = SplitMix64(seed: mixed)
        return expander.next()
    }
}
