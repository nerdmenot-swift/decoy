import Testing

@testable import Decoy

// MARK: - Fixtures under test

private struct User: Equatable {
    var id: Int = 0
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var plan: String = ""
    var deletedAt: Int?
    var orders: [Order] = []
}

private struct Order: Equatable {
    var id: Int = 0
    var total: Double = 0
    var userId: Int = 0
}

/// Same shape as `User`, to prove per-type seed derivation actually separates them.
private struct Account: Equatable {
    var id: Int = 0
    var firstName: String = ""
}

@Suite("Forge")
struct ForgeTests {

    @Test("same seed produces identical output")
    func deterministic() {
        let forge = Forge<User> { User() }
            .rule(\.firstName) { $0.name.firstName() }
            .rule(\.lastName) { $0.name.lastName() }

        #expect(forge.generate(50, seed: 1337) == forge.generate(50, seed: 1337))
    }

    @Test("different seeds produce different output")
    func seedsMatter() {
        let forge = Forge<User> { User() }.rule(\.firstName) { $0.name.firstName() }
        #expect(forge.generate(50, seed: 1) != forge.generate(50, seed: 2))
    }

    /// The correlation bug: two entity types sharing one user-facing seed must not
    /// share a bit stream, or unrelated tables come out suspiciously in lockstep.
    @Test("distinct entity types get independent streams from one seed")
    func perTypeSeedDerivation() {
        let users = Forge<User> { User() }.rule(\.firstName) { $0.name.firstName() }
        let accounts = Forge<Account> { Account() }.rule(\.firstName) { $0.name.firstName() }

        let userNames = users.generate(20, seed: 1337).map(\.firstName)
        let accountNames = accounts.generate(20, seed: 1337).map(\.firstName)

        #expect(userNames != accountNames)
    }

    /// Adding a rule to one entity must not perturb an unrelated entity generated
    /// from the same seed — otherwise fixtures churn every time a model changes.
    @Test("one entity is stable when another changes")
    func entityIsolation() {
        let accounts = Forge<Account> { Account() }.rule(\.firstName) { $0.name.firstName() }
        let before = accounts.generate(10, seed: 99)

        _ = Forge<User> { User() }
            .rule(\.firstName) { $0.name.firstName() }
            .rule(\.lastName) { $0.name.lastName() }
            .generate(10, seed: 99)

        #expect(accounts.generate(10, seed: 99) == before)
    }

    @Test("rules run in declaration order and can read earlier values")
    func derivedRules() {
        let users = Forge<User> { User() }
            .rule(\.firstName) { _ in "Ada" }
            .rule(\.lastName) { _ in "Lovelace" }
            .rule(\.email) { _, user in "\(user.firstName).\(user.lastName)@example.com" }
            .generate(3, seed: 1)

        for user in users {
            #expect(user.email == "Ada.Lovelace@example.com")
        }
    }

    @Test("row index is available to rules")
    func rowIndex() {
        let users = Forge<User> { User() }
            .rule(\.id) { $0.index }
            .generate(5, seed: 1)

        #expect(users.map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test("cycle distributes values round-robin")
    func cycleRoundRobin() {
        let users = Forge<User> { User() }
            .cycle(\.plan, through: ["free", "pro", "team"])
            .generate(7, seed: 1)

        #expect(users.map(\.plan) == ["free", "pro", "team", "free", "pro", "team", "free"])
    }

    @Test("unique rule never repeats a value")
    func uniqueRule() {
        let users = Forge<User> { User() }
            .rule(unique: \.id) { $0.int(in: 1...10_000) }
            .generate(500, seed: 1)

        #expect(Set(users.map(\.id)).count == 500)
    }

    @Test("unique rule throws when the pool is too small")
    func uniqueExhaustion() {
        let forge = Forge<User> { User() }
            .rule(unique: \.plan, attempts: 50) { $0.pick(["a", "b", "c"]) }

        #expect(throws: ForgeError.self) {
            try forge.tryGenerate(10, seed: 1)
        }
    }

    @Test("unique bookkeeping resets between runs")
    func uniqueScopedToRun() {
        let forge = Forge<User> { User() }
            .rule(unique: \.plan, attempts: 50) { $0.pick(["a", "b", "c"]) }

        // Three values, three rows — fine. And fine *again*, because uniqueness is
        // scoped to one generate call rather than to the recipe.
        #expect(forge.generate(3, seed: 1).count == 3)
        #expect(forge.generate(3, seed: 1).count == 3)
    }

    @Test("each populates children per parent")
    func childFanOut() {
        let orders = Forge<Order> { Order() }.rule(\.total) { $0.double(in: 1...100) }
        let users = Forge<User> { User() }
            .each(\.orders, 2...5, of: orders)
            .generate(20, seed: 1337)

        for user in users {
            #expect((2...5).contains(user.orders.count))
        }
        // Children must vary between parents, not be the same batch replayed.
        #expect(users[0].orders != users[1].orders)
    }

    @Test("each is reproducible")
    func childFanOutDeterministic() {
        let orders = Forge<Order> { Order() }.rule(\.total) { $0.double(in: 1...100) }
        let users = Forge<User> { User() }.each(\.orders, 1...4, of: orders)

        #expect(users.generate(10, seed: 7) == users.generate(10, seed: 7))
    }

    @Test("finish runs after every rule")
    func finishers() {
        let users = Forge<User> { User() }
            .rule(\.firstName) { _ in "ada" }
            .finish { _, user in user.firstName = user.firstName.uppercased() }
            .generate(3, seed: 1)

        #expect(users.allSatisfy { $0.firstName == "ADA" })
    }

    @Test("traits override rules without mutating the base recipe")
    func traits() {
        let base = Forge<User> { User() }.rule(\.plan) { _ in "free" }
        let enterprise = Trait<User>("enterprise") { $0.rule(\.plan) { _ in "enterprise" } }

        #expect(base.generate(3, seed: 1, applying: enterprise).allSatisfy { $0.plan == "enterprise" })
        #expect(base.generate(3, seed: 1).allSatisfy { $0.plan == "free" })
    }

    /// Value semantics give factory inheritance away for free.
    @Test("extending a forge leaves the original untouched")
    func valueSemanticsComposition() {
        let base = Forge<User> { User() }.rule(\.plan) { _ in "free" }
        let pro = base.rule(\.plan) { _ in "pro" }

        #expect(base.generate(1, seed: 1)[0].plan == "free")
        #expect(pro.generate(1, seed: 1)[0].plan == "pro")
    }

    @Test("stream matches generate and is lazy")
    func streaming() {
        let forge = Forge<User> { User() }
            .rule(\.id) { $0.index }
            .rule(\.firstName) { $0.name.firstName() }

        let eager = forge.generate(100, seed: 1337)
        let streamed = Array(forge.stream(seed: 1337).prefix(100))

        #expect(eager == streamed)
    }

    @Test("stream is unbounded")
    func streamUnbounded() {
        let forge = Forge<User> { User() }.rule(\.id) { $0.index }
        let ids = forge.stream(seed: 1).prefix(10_000).map(\.id)
        #expect(ids.last == 9_999)
    }

    @Test("referential integrity via pick")
    func referentialIntegrity() {
        let users = Forge<User> { User() }
            .rule(\.id) { $0.index }
            .generate(50, seed: 1337)

        let userIds = Set(users.map(\.id))
        let orders = Forge<Order> { Order() }
            .rule(\.userId) { f in f.pick(users).id }
            .generate(500, seed: 1337)

        #expect(orders.allSatisfy { userIds.contains($0.userId) })
    }

    @Test("generating zero rows is not an error")
    func zeroRows() {
        let forge = Forge<User> { User() }.rule(\.firstName) { $0.name.firstName() }
        #expect(forge.generate(0, seed: 1).isEmpty)
    }

    @Test("one returns a single value matching generate")
    func single() {
        let forge = Forge<User> { User() }.rule(\.firstName) { $0.name.firstName() }
        #expect(forge.one(seed: 42) == forge.generate(1, seed: 42)[0])
    }
}

@Suite("Faker helpers")
struct FakerHelperTests {

    private func faker(_ seed: UInt64 = 1) -> Faker { Faker(seed: seed) }

    @Test("maybe produces a value at roughly the given rate")
    func maybeRate() {
        var f = faker()
        var present = 0
        for _ in 0..<10_000 where f.maybe(chance: 0.1, { _ in 1 }) != nil { present += 1 }
        #expect(abs(Double(present) / 10_000 - 0.1) < 0.02)
    }

    @Test("maybe saturates")
    func maybeSaturates() {
        var f = faker()
        #expect(f.maybe(chance: 0.0, { _ in 1 }) == nil)
        #expect(f.maybe(chance: 1.0, { _ in 1 }) == 1)
    }

    @Test("weighted respects the distribution")
    func weighted() {
        var f = faker()
        var counts = ["a": 0, "b": 0]
        for _ in 0..<10_000 {
            counts[f.weighted([(90, "a"), (10, "b")]), default: 0] += 1
        }
        #expect(abs(Double(counts["a"]!) / 10_000 - 0.9) < 0.02)
    }

    @Test("weighted ignores zero-weight choices")
    func weightedZero() {
        var f = faker()
        for _ in 0..<500 {
            #expect(f.weighted([(0, "never"), (1, "always")]) == "always")
        }
    }

    @Test("weighted with a single choice always returns it")
    func weightedSingle() {
        var f = faker()
        #expect(f.weighted([(1, "only")]) == "only")
    }

    @Test("shuffled is a permutation")
    func shuffled() {
        var f = faker()
        let source = Array(0..<50)
        let result = f.shuffled(source)
        #expect(result.sorted() == source)
        #expect(result != source, "a 50-element shuffle should not return the input order")
    }

    @Test("shuffled handles empty and single-element input")
    func shuffledDegenerate() {
        var f = faker()
        #expect(f.shuffled([Int]()).isEmpty)
        #expect(f.shuffled([7]) == [7])
    }

    @Test("bothify substitutes digits, letters, and literals")
    func bothify() {
        var f = faker()
        for _ in 0..<200 {
            let plate = f.bothify("??-####")
            #expect(plate.count == 7)
            let chars = Array(plate)
            #expect(chars[0].isUppercase && chars[1].isUppercase)
            #expect(chars[2] == "-")
            let digitsOnly = chars[3...6].allSatisfy { $0.isNumber }
            #expect(digitsOnly)
        }
    }

    @Test("numerify leaves non-hash characters alone")
    func numerify() {
        var f = faker()
        let code = f.numerify("SW-###-?")
        #expect(code.hasPrefix("SW-"))
        #expect(code.hasSuffix("-?"), "numerify must not touch '?'")
    }

    @Test("pick(_:from:) returns the requested count")
    func pickMultiple() {
        var f = faker()
        #expect(f.pick(5, from: ["a", "b", "c"]).count == 5)
        #expect(f.pick(0, from: ["a"]).isEmpty)
    }

    @Test("email defaults to the reserved example.com domain")
    func emailIsSafe() {
        var f = faker()
        for _ in 0..<100 {
            #expect(f.internet.email().hasSuffix("@example.com"))
        }
    }

    @Test("email derived from a name contains no unsafe characters")
    func emailSanitises() {
        var f = faker()
        let address = f.internet.email(firstName: "Júlia", lastName: "Bergström")
        #expect(address == "jlia.bergstrm@example.com")
    }

    /// A row marked `.male` must not be handed a name from the female pool — the
    /// whole reason the corpus keeps them separate.
    @Test("gendered first names come from the matching pool")
    func genderedNames() throws {
        let locale = LocaleCorpus.builtIn
        let female = try #require(locale.strings("person.first_name.female"))
        let male = try #require(locale.strings("person.first_name.male"))
        let femalePool = Set(try (0..<female.count).map { try female.string(at: $0) })
        let malePool = Set(try (0..<male.count).map { try male.string(at: $0) })
        #expect(femalePool.isDisjoint(with: malePool), "pools must be distinguishable")

        var f = faker()
        for _ in 0..<200 {
            #expect(femalePool.contains(f.name.firstName(.female)))
            #expect(malePool.contains(f.name.firstName(.male)))
        }
    }
}
