import Testing

@testable import Decoy

/// Tests the model chunk end to end: built, encoded, read back, sampled.
///
/// Chunk kind 6 and index kind 3 were reserved from the first version of the format and
/// implemented by nothing, which is why the enum cases were deleted during the audit —
/// support that exists only to be exhaustively switched over reads as support that is
/// there. These tests are what make them real.
@Suite("N-gram models")
struct NGramModelTests {

    /// Builds a model over a tiny alphabet by hand, so the expected output is calculable
    /// rather than merely plausible.
    ///
    /// Alphabet: sentinel, `a`, `b`. Start goes to `a`. After `a` comes `b`. After `b`
    /// the word ends. The only string this model can produce is `"ab"`.
    ///
    /// The start context is `[sentinel]`, not the empty one: the walk is left-padded, so
    /// "nothing generated yet" is a real context. An empty context would mean the
    /// marginal distribution over the whole training set, which is a different thing and
    /// is why an earlier version generated words starting mid-word.
    private func deterministicCorpus(filterBits: [UInt8] = [], hashes: Int = 0) -> Corpus {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let source = builder.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: "")

        let end = NGramModel.endSymbol
        let a: UInt16 = 1
        let b: UInt16 = 2

        let model = builder.addModel(
            order: 2,
            minLength: 1,
            maxLength: 8,
            alphabet: ["", "a", "b"],
            contexts: [
                (NGramModel.key([end][...]), [(a, 1)]),
                (NGramModel.key([a][...]), [(b, 1)]),
                (NGramModel.key([b][...]), [(end, 1)]),
            ],
            filterHashCount: hashes,
            filterBits: filterBits,
            source: source
        )
        builder.index("person.last_name", model: model)
        return try! Corpus(bytes: builder.build())
    }

    @Test("a model round-trips through the binary format")
    func roundTrip() throws {
        let corpus = deterministicCorpus()
        let entry = try #require(try corpus.lookup("person.last_name"))
        guard case .model(let model) = entry else {
            Issue.record("expected a model, got \(entry)")
            return
        }
        #expect(model.order == 2)
        #expect(model.alphabetCount == 3)
        #expect(model.contextCount == 3)
        #expect(try model.character(1) == "a")
        #expect(try model.character(2) == "b")
        #expect(try model.character(NGramModel.endSymbol) == "", "the sentinel is not a character")
    }

    @Test("the walk follows the transitions it was given")
    func deterministicWalk() {
        let corpus = deterministicCorpus()
        var faker = Faker(seed: 1337, locale: LocaleCorpus(code: "t", chain: [corpus]))
        // Every path through this model spells "ab", so any seed must produce it.
        for seed in [1, 7, 99, 12345] {
            var f = Faker(seed: UInt64(seed), locale: faker.locale)
            #expect(f.drawModel("person.last_name") == "ab")
        }
        #expect(faker.drawModel("person.last_name") == "ab")
    }

    @Test("a path with no model returns nil rather than trapping")
    func missingModel() {
        let corpus = deterministicCorpus()
        var faker = Faker(seed: 1, locale: LocaleCorpus(code: "t", chain: [corpus]))
        #expect(faker.drawModel("person.first_name") == nil)
    }

    /// The guarantee the whole layer stands on.
    @Test("a candidate in the training set is never emitted")
    func rejectsTrainingSetMembers() {
        // A filter with every bit set says yes to everything, so every candidate looks
        // like a training-set member and the sampler must give up rather than emit one.
        let corpus = deterministicCorpus(
            filterBits: [UInt8](repeating: 0xFF, count: 64), hashes: 3)
        var faker = Faker(seed: 1337, locale: LocaleCorpus(code: "t", chain: [corpus]))
        #expect(
            faker.drawModel("person.last_name") == nil,
            "the only string this model can produce is in the filter, so it must produce none"
        )
    }

    @Test("an empty filter lets everything through")
    func emptyFilter() {
        let corpus = deterministicCorpus(filterBits: [], hashes: 0)
        var faker = Faker(seed: 1337, locale: LocaleCorpus(code: "t", chain: [corpus]))
        #expect(faker.drawModel("person.last_name") == "ab")
    }

    /// The Bloom filter's error must be one-sided, or rejecting on it is unsafe.
    @Test("the filter never reports a false negative")
    func filterIsOneSided() {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let words = (0..<500).map { "name\($0)" }

        // Build the filter the way a trainer would.
        var bits = [UInt8](repeating: 0, count: 2048)
        let hashes = 4
        for word in words {
            var hash = SeedDerivation.fnv1a(word)
            for _ in 0..<hashes {
                let bit = hash % UInt64(bits.count * 8)
                bits[Int(bit / 8)] |= 1 << UInt8(bit % 8)
                hash = hash &* 0x9E37_79B9_7F4A_7C15
                hash ^= hash >> 29
            }
        }

        let model = builder.addModel(
            order: 2, alphabet: ["", "a"],
            contexts: [(NGramModel.key([0][...]), [(1, 1)])],
            filterHashCount: hashes, filterBits: bits)
        builder.index("t", model: model)
        let corpus = try! Corpus(bytes: builder.build())
        guard case .model(let read)? = try? corpus.lookup("t") else {
            Issue.record("model did not round-trip")
            return
        }

        for word in words {
            #expect(read.wasTrainedOn(word), "'\(word)' was trained on and must be reported")
        }
    }

    @Test("model paths enumerate with the right kind")
    func enumeration() throws {
        let corpus = deterministicCorpus()
        let entry = try #require(try corpus.paths.first { $0.path == "person.last_name" })
        #expect(entry.kind == .model)
    }

    /// A corpus with no models must not carry the chunk, so nothing that existed before
    /// models changes size.
    @Test("a corpus without models is unchanged")
    func noChunkWhenUnused() {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let source = builder.addSource(
            id: "t", license: "Apache-2.0", url: "", version: "1", retrieved: "")
        builder.index("a.b", stringTable: builder.addStringTable(["x"], source: source))
        let corpus = try! Corpus(bytes: builder.build())
        #expect((try? corpus.model(0)) == nil, "there should be no models chunk at all")
    }
}

/// Tests the shipped surname model against the list it was trained on.
///
/// The unit tests above use a hand-built model whose output is calculable. These check
/// the real one, because the properties that matter — that it never emits a real name,
/// that it does not run out, that it looks like English — are properties of the training
/// rather than of the encoding.
@Suite(
    "Surname model",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct SurnameModelTests {

    private func english() throws -> LocaleCorpus {
        try RealCorpus.locale("en", chain: ["en", "base"])
    }

    private func censusNames(_ locale: LocaleCorpus) -> Set<String> {
        guard let table = locale.strings("person.last_name.generic") else { return [] }
        return Set((0..<table.count).compactMap { try? table.string(at: $0) })
    }

    /// The guarantee. Ten thousand draws, and not one of them a real person's surname.
    ///
    /// This is the difference between fake data and undisclosed PII, and it is the reason
    /// the model carries a Bloom filter over its training set rather than trusting that
    /// an n-gram will not reproduce its input. It reproduces it constantly — roughly a
    /// quarter of raw walks land on a real name at this order.
    @Test("no generated surname is a real one")
    func neverEmitsARealName() throws {
        let locale = try english()
        let real = censusNames(locale)
        try #require(real.count > 20_000, "expected the full Census list")

        var faker = Faker(seed: 1337, locale: locale)
        var emitted: [String] = []
        for _ in 0..<10_000 {
            let name = faker.person.novelLastName()
            if real.contains(name) { emitted.append(name) }
        }
        #expect(emitted.isEmpty, "emitted \(emitted.count) real surnames: \(emitted.prefix(5))")
    }

    /// The reason the model exists: a list of 24,889 names cannot fill a unique column
    /// past 24,889 rows, and a model has no such ceiling.
    @Test("draws stay overwhelmingly distinct")
    func staysDistinct() throws {
        var faker = Faker(seed: 1337, locale: try english())
        var seen = Set<String>()
        for _ in 0..<10_000 { seen.insert(faker.person.novelLastName()) }
        #expect(seen.count > 8_000, "only \(seen.count) distinct in 10,000 draws")
    }

    /// An n-gram decides what comes next, never how long the word is, so nothing stops a
    /// run of plausible bigrams from adding up to a 28-character surname. It did, in 0.8%
    /// of draws, until the model started carrying its training set's length range.
    @Test("lengths stay inside the training set's range")
    func lengthsAreRealistic() throws {
        let locale = try english()
        let real = censusNames(locale)
        let shortest = real.map(\.count).min() ?? 1
        let longest = real.map(\.count).max() ?? 1

        var faker = Faker(seed: 4242, locale: locale)
        for _ in 0..<5_000 {
            let name = faker.person.novelLastName()
            #expect(
                name.count >= shortest && name.count <= longest,
                "'\(name)' is \(name.count) characters; real names are \(shortest)...\(longest)"
            )
        }
    }

    /// Output has to look like the language, not merely be novel.
    @Test("generated surnames look like English surnames")
    func lookPlausible() throws {
        var faker = Faker(seed: 99, locale: try english())
        for _ in 0..<2_000 {
            let name = faker.person.novelLastName()
            #expect(name.first?.isUppercase == true, "'\(name)' does not start with a capital")
            #expect(
                name.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == " " },
                "'\(name)' contains something no surname does"
            )
            // Every real surname has a vowel or a Y. A run without one is the classic
            // n-gram failure and would be visible immediately in a fixture set.
            #expect(
                name.lowercased().contains(where: { "aeiouy".contains($0) }),
                "'\(name)' has no vowel"
            )
        }
    }

    @Test("the same seed gives the same names")
    func reproducible() throws {
        var a = Faker(seed: 7, locale: try english())
        var b = Faker(seed: 7, locale: try english())
        let first = (0..<50).map { _ in a.person.novelLastName() }
        let second = (0..<50).map { _ in b.person.novelLastName() }
        #expect(first == second)
    }

    /// A locale with no model must still answer, rather than trapping or returning "".
    @Test("a locale without a model falls back to its list")
    func fallsBack() throws {
        let japanese = try RealCorpus.locale("ja", chain: ["ja", "en", "base"])
        var faker = Faker(seed: 1, locale: japanese)
        let name = faker.person.novelLastName()
        #expect(!name.isEmpty)
    }
}
