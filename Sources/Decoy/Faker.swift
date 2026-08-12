/// The generation context handed to every rule.
///
/// A `struct`, so it is `Sendable` and a `Forge` can be shared across tasks.
///
/// Rules read like `$0.name.firstName()`, which needs namespaces (`name`,
/// `internet`, …) to advance a shared RNG. That normally forces a reference type.
/// The way out is a computed property with both a getter and a setter: Swift
/// evaluates `$0.name.firstName()` as get-namespace → call mutating method →
/// write namespace back, so the RNG advances through a value type. See
/// ``Faker/name`` for the pattern each namespace follows.
public struct Faker: Sendable {

    /// The generator backing every draw. Exposed so custom generators written
    /// outside Decoy can participate in the same deterministic stream.
    public var rng: Xoshiro256StarStar

    /// How many template expansions are currently on the stack.
    ///
    /// Internal because it is a recursion guard, not a knob. It has to live here rather
    /// than as a parameter because a template token can resolve to a generator, and that
    /// generator expands its own pattern from the top — so the depth has to survive
    /// leaving and re-entering `expand`.
    var expansionDepth = 0

    /// Tokens still allowed in the current top-level expansion.
    ///
    /// Depth alone does not bound the *work*: a cyclic pattern re-expands its own result
    /// at every level, so the retries multiply even though none of them recurses past the
    /// cap. A self-referential pattern took 84 seconds under a depth-only guard. Real
    /// corpora never come close to this budget — the deepest shipped pattern expands
    /// about a dozen tokens.
    var expansionBudget = 0

    /// The zero-based index of the row currently being generated.
    ///
    /// Useful for monotonic primary keys and collision-free derived values:
    /// `.rule(\.email) { "user\($0.index)@example.com" }`.
    public internal(set) var index: Int

    /// The locale and its fallback chain, which every generator reads through.
    ///
    /// Settable only from inside the module, so a caller cannot change it mid-stream.
    /// ``PersonFaker/fullName(_:)`` narrows it for the length of one composition, to
    /// keep a name's pattern and its parts from arriving in different languages.
    public internal(set) var locale: LocaleCorpus

    /// Whether name generators should produce names no real person has.
    ///
    /// Off by default, and that default is the conservative one rather than the safe one:
    /// `person.lastName()` draws from a list of 24,889 real American surnames weighted by
    /// how many people actually bear each, and turning that off silently would change
    /// every existing fixture and throw away the frequency realism the Census adapter was
    /// built for.
    ///
    /// Set it once — here, or with ``Forge/novelNames(_:)`` — and every name generator
    /// switches to a trained model where the locale has one. Measured over ten thousand
    /// draws in `en`: off, 9,499 surnames belong to real people; on, none do.
    ///
    /// A per-call flag was the alternative and it is the wrong shape. The call site you
    /// forget is the one that matters, and "did every developer remember at every call"
    /// is not a property anybody can audit.
    ///
    /// Locales with no model for a field fall back to the list, so this is a preference
    /// rather than a guarantee. 133 models across 48 locales today; the fields and
    /// locales without one are listed by `decoy-validate`.
    public let novelNames: Bool

    /// The instant that "past" and "future" are relative to.
    ///
    /// Deliberately **not** the system clock. Every other faker anchors `past()` to
    /// now, which quietly means seed 1337 produces different fixtures tomorrow than it
    /// did today — a reproducibility hole in exactly the libraries that promise
    /// reproducibility. Anchoring to a fixed instant closes it; override this when you
    /// want dates to sit near a particular moment.
    public let reference: Timestamp

    /// The seed this faker was created with.
    ///
    /// Worth reading precisely when you did *not* choose it. An unseeded faker takes one
    /// from the system, and without this the run would be unreproducible — so a fixture
    /// that turns up something surprising could never be shown to anybody else. Print it
    /// and pass it back to `Faker(seed:)` to get the same run again.
    public let seed: UInt64

    /// Creates a faker.
    ///
    /// `seed` defaults to a fresh system-drawn value, so callers who only want plausible
    /// data can ignore seeding entirely:
    ///
    /// ```swift
    /// var faker = Faker(locale: DecoyLocaleEN.locale)
    /// faker.person.fullName()
    /// ```
    ///
    /// The default is evaluated per call, so two fakers made this way differ. Pass a seed
    /// when the values need to be the same twice, and read ``seed`` to recover the one
    /// that was chosen for you.
    public init(
        seed: UInt64 = Decoy.randomSeed(),
        index: Int = 0,
        locale: LocaleCorpus = .builtIn,
        reference: Timestamp = .decoyReference,
        novelNames: Bool = false
    ) {
        self.seed = seed
        self.rng = Xoshiro256StarStar(seed: seed)
        self.index = index
        self.locale = locale
        self.reference = reference
        self.novelNames = novelNames
    }

    // MARK: - Corpus access

    /// Draws one string from the table at `path`, honouring weights when present.
    ///
    /// Returns `nil` when no locale in the chain supplies the key, so callers can
    /// choose between a fallback and a hard failure.
    public mutating func draw(_ path: String) -> String? {
        guard let table = locale.strings(path), !table.isEmpty else { return nil }
        return try? table.draw(using: &rng)
    }

    /// Draws one string from `path`, or traps with an actionable message.
    ///
    /// Missing corpus data is a configuration error the developer must fix — a wrong
    /// locale, or a corpus that was never compiled — so it fails loudly rather than
    /// silently substituting English and leaving the problem to be noticed by a native
    /// speaker looking at production-shaped fixtures.
    ///
    /// A locale that *declares* the field empty is a different thing entirely, and yields
    /// `""`. Azerbaijani has no name prefixes and Russian no name suffixes; that is a fact
    /// about the language, not a build error, and there is nothing the caller could fix.
    /// A full name assembled from parts simply gets nothing appended, which is the correct
    /// rendering.
    public mutating func require(_ path: String) -> String {
        if let value = draw(path) { return value }
        if locale.declaresEmpty(path) { return "" }

        preconditionFailure(
            "Decoy: locale '\(locale.code)' has no data for '\(path)'. "
                + "Either the locale lacks this field or its corpus was not compiled."
        )
    }

    /// Draws a whole row from the composite table at `path`, keeping correlated
    /// fields consistent with one another.
    public mutating func drawRow(_ path: String) -> [String: String]? {
        guard let table = locale.composite(path), !table.isEmpty else { return nil }
        return try? table.drawRow(using: &rng)
    }

    // MARK: - Primitive draws

    /// Returns a uniformly distributed integer in the given closed range.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        rng.draw(in: range)
    }

    /// Returns a uniformly distributed double in the given closed range.
    public mutating func double(in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + rng.drawUnitInterval() * span
    }

    /// Returns `true` with the given probability, defaulting to an even coin flip.
    public mutating func bool(chance: Double = 0.5) -> Bool {
        rng.drawChance(chance)
    }

    // MARK: - Selection

    /// Returns a uniformly chosen element of `collection`.
    ///
    /// Traps on an empty collection: for fixture generation an empty source is a
    /// bug in the caller's setup, and silently returning `nil` would push a
    /// confusing optional through every rule.
    public mutating func pick<C: RandomAccessCollection>(_ collection: C) -> C.Element {
        guard let element = rng.drawElement(from: collection) else {
            preconditionFailure(
                "Faker.pick was given an empty collection. "
                    + "Generate the source rows before the rows that reference them."
            )
        }
        return element
    }

    /// Returns `count` elements chosen uniformly *with* replacement.
    public mutating func pick<C: RandomAccessCollection>(
        _ count: Int,
        from collection: C
    ) -> [C.Element] {
        precondition(count >= 0, "count must not be negative")
        var result = [C.Element]()
        result.reserveCapacity(count)
        for _ in 0..<count { result.append(pick(collection)) }
        return result
    }

    /// Returns a uniformly ordered shuffle of `collection`.
    ///
    /// Fisher–Yates, implemented here rather than via the standard library's
    /// `shuffled(using:)` so the result depends only on the seed and not on the
    /// toolchain version.
    public mutating func shuffled<C: RandomAccessCollection>(_ collection: C) -> [C.Element] {
        var result = Array(collection)
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int(rng.draw(below: UInt64(i + 1)))
            result.swapAt(i, j)
        }
        return result
    }

    /// Returns a value chosen in proportion to its weight.
    ///
    /// Weights need not sum to 1 — they are normalised. This is how you get
    /// realistic distributions instead of uniform noise: most accounts on the free
    /// plan, a few on enterprise.
    ///
    /// ```swift
    /// f.weighted([(70, "free"), (25, "pro"), (5, "enterprise")])
    /// ```
    public mutating func weighted<Value>(_ choices: [(weight: Double, value: Value)]) -> Value {
        precondition(!choices.isEmpty, "weighted requires at least one choice")
        let total = choices.reduce(0.0) { $0 + Swift.max(0, $1.weight) }
        precondition(total > 0, "weighted requires at least one positive weight")

        var remaining = rng.drawUnitInterval() * total
        for choice in choices {
            remaining -= Swift.max(0, choice.weight)
            if remaining < 0 { return choice.value }
        }
        return choices[choices.count - 1].value  // floating-point tail
    }

    // MARK: - Optionality

    /// Produces a value with the given probability, otherwise `nil`.
    ///
    /// The argument is the chance of *getting a value*, which is the reading the
    /// call site suggests. Note this is the inverse of Bogus's `OrNull`, where the
    /// argument is the chance of null — a genuine source of confusion, so the label
    /// is required here.
    ///
    /// ```swift
    /// .rule(\.deletedAt) { $0.maybe(chance: 0.1) { $0.date.past() } }  // 10% deleted
    /// ```
    public mutating func maybe<Value>(
        chance: Double,
        _ body: (inout Faker) throws -> Value
    ) rethrows -> Value? {
        guard rng.drawChance(chance) else { return nil }
        return try body(&self)
    }

    // MARK: - Patterned strings

    /// Replaces `#` with a digit `0-9` and `!` with a digit `2-9`.
    ///
    /// `!` is faker's convention for positions that cannot be `0` or `1` — North
    /// American area codes and exchange prefixes, for instance, so `!##-!##-####`
    /// yields a number that is structurally valid rather than merely digit-shaped.
    public mutating func numerify(_ pattern: String) -> String {
        substitute(pattern, digits: "#", letters: nil, either: nil)
    }

    /// Replaces `?` with a random uppercase letter.
    ///
    /// `#` and `*` are left alone — use ``bothify(_:)`` for a pattern mixing them.
    public mutating func letterify(_ pattern: String) -> String {
        substitute(pattern, digits: nil, letters: "?", either: nil)
    }

    /// Replaces `#` with a digit, `%` with a digit `1-9`, `!` with a digit `2-9`, `?` with
    /// an uppercase letter, and `*` with either a digit or a letter.
    ///
    /// `%` exists for the leading position of anything counted from one. A house number is
    /// the case that produced it: `###` yields `0` about one time in a thousand and
    /// `Kobelstraße 0` is not an address, and a Japanese block written `0番` is not one
    /// either. `!` was already here for NANP area codes, which cannot begin with 0 *or* 1 —
    /// a different constraint that would wrongly forbid house number 1.
    ///
    /// The workhorse for postcodes, SKUs, licence plates and phone numbers:
    /// `f.bothify("??-####")` → `"KJ-8813"`.
    public mutating func bothify(_ pattern: String) -> String {
        substitute(pattern, digits: "#", letters: "?", either: "*")
    }

    private mutating func substitute(
        _ pattern: String,
        digits: Character?,
        letters: Character?,
        either: Character?
    ) -> String {
        var out = String()
        out.reserveCapacity(pattern.count)
        for character in pattern {
            if let digits, character == digits {
                out.append(randomDigit())
            } else if character == "!" {
                out.append(randomDigit(from: 2))
            } else if character == "%" {
                out.append(randomDigit(from: 1))
            } else if let letters, character == letters {
                out.append(randomLetter())
            } else if let either, character == either {
                out.append(bool() ? randomDigit() : randomLetter())
            } else {
                out.append(character)
            }
        }
        return out
    }

    private mutating func randomDigit(from lowest: UInt64 = 0) -> Character {
        Character(String(lowest + rng.draw(below: 10 - lowest)))
    }

    private mutating func randomLetter() -> Character {
        let offset = UInt8(rng.draw(below: 26))
        return Character(UnicodeScalar(UInt8(ascii: "A") + offset))
    }
}
