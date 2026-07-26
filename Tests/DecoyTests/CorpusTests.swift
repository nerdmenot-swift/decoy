import Testing

@testable import Decoy

private func buildSample() -> [UInt8] {
    var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 2, patch: 3))
    let faker = builder.addSource(
        id: "faker-js",
        license: "MIT",
        url: "https://github.com/faker-js/faker",
        version: "10.5.0",
        retrieved: "2026-07-27"
    )

    let names = builder.addStringTable(["Ada", "Grace", "Katherine"], source: faker)
    let patterns = builder.addStringTable(
        ["{{first}} {{last}}", "{{prefix}} {{first}} {{last}}"],
        weights: [95, 5],
        source: faker
    )
    let countries = builder.addCompositeTable(
        fields: ["alpha2", "alpha3", "numeric"],
        rows: [["AD", "AND", "020"], ["AE", "ARE", "784"], ["AF", "AFG", "004"]],
        source: faker
    )

    builder.index("person.first_name.female", stringTable: names)
    builder.index("person.name_pattern", stringTable: patterns)
    builder.index("location.country_code", compositeTable: countries)
    builder.indexNull("person.prefix")
    return builder.build()
}

@Suite("Corpus format")
struct CorpusTests {

    @Test("round-trips string tables")
    func roundTripStrings() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .strings(let table) = try #require(try corpus.lookup("person.first_name.female"))
        else { return #expect(Bool(false), "expected a string table") }

        #expect(table.count == 3)
        #expect(try table.string(at: 0) == "Ada")
        #expect(try table.string(at: 2) == "Katherine")
        #expect(table.hasWeights == false)
        #expect(try table.weight(at: 0) == 1, "an unweighted table reports weight 1")
    }

    @Test("preserves the corpus version")
    func version() throws {
        let corpus = try Corpus(bytes: buildSample())
        #expect(corpus.version == CorpusVersion(major: 1, minor: 2, patch: 3))
        #expect(corpus.version.description == "1.2.3")
    }

    @Test("round-trips weights")
    func roundTripWeights() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .strings(let table) = try #require(try corpus.lookup("person.name_pattern"))
        else { return #expect(Bool(false), "expected a string table") }

        #expect(table.hasWeights)
        #expect(try table.weight(at: 0) == 95)
        #expect(try table.weight(at: 1) == 5)
    }

    /// The reason weights exist: real distributions are skewed, and a uniform draw
    /// would return the rare pattern half the time.
    @Test("weighted draws follow the stored distribution")
    func weightedDraw() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .strings(let table) = try #require(try corpus.lookup("person.name_pattern"))
        else { return #expect(Bool(false), "expected a string table") }

        var rng = Xoshiro256StarStar(seed: 1337)
        var common = 0
        let trials = 20_000
        for _ in 0..<trials where try table.draw(using: &rng) == "{{first}} {{last}}" {
            common += 1
        }
        #expect(abs(Double(common) / Double(trials) - 0.95) < 0.02)
    }

    @Test("unweighted draws stay in the table")
    func unweightedDraw() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .strings(let table) = try #require(try corpus.lookup("person.first_name.female"))
        else { return #expect(Bool(false), "expected a string table") }

        var rng = Xoshiro256StarStar(seed: 7)
        var seen = Set<String>()
        for _ in 0..<500 { seen.insert(try #require(try table.draw(using: &rng))) }
        #expect(seen == ["Ada", "Grace", "Katherine"])
    }

    /// Composite rows are the fix for `city: "Boston", state: "CA"` — the fields must
    /// travel together or they contradict each other.
    @Test("composite rows keep correlated fields together")
    func compositeRows() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .composite(let table) = try #require(try corpus.lookup("location.country_code"))
        else { return #expect(Bool(false), "expected a composite table") }

        #expect(table.fieldCount == 3)
        #expect(table.rowCount == 3)
        #expect(try table.fieldName(0) == "alpha2")
        #expect(try table.row(1) == ["alpha2": "AE", "alpha3": "ARE", "numeric": "784"])

        var rng = Xoshiro256StarStar(seed: 3)
        let valid: Set<String> = ["AD", "AE", "AF"]
        for _ in 0..<200 {
            let row = try #require(try table.drawRow(using: &rng))
            #expect(valid.contains(row["alpha2"]!))
            // The triple must be internally consistent, never mixed across rows.
            switch row["alpha2"]! {
            case "AD": #expect(row["alpha3"] == "AND" && row["numeric"] == "020")
            case "AE": #expect(row["alpha3"] == "ARE" && row["numeric"] == "784")
            default: #expect(row["alpha3"] == "AFG" && row["numeric"] == "004")
            }
        }
    }

    @Test("round-trips provenance")
    func provenance() throws {
        let corpus = try Corpus(bytes: buildSample())
        guard case .strings(let table) = try #require(try corpus.lookup("person.first_name.female"))
        else { return #expect(Bool(false), "expected a string table") }

        let source = try #require(try corpus.source(table.sourceID))
        #expect(source.id == "faker-js")
        #expect(source.license == "MIT")
        #expect(source.version == "10.5.0")
        #expect(source.retrieved == "2026-07-27")
    }

    @Test("source 0 is always present so any table can reference it")
    func unattributedSource() throws {
        let corpus = try Corpus(bytes: buildSample())
        #expect(try corpus.source(0)?.id == "unattributed")
    }

    /// An explicit null must be distinguishable from an absent key: one stops the
    /// fallback walk, the other continues it.
    @Test("explicit null is distinct from a missing key")
    func nullVersusMissing() throws {
        let corpus = try Corpus(bytes: buildSample())

        guard case .none = try #require(try corpus.lookup("person.prefix")) else {
            return #expect(Bool(false), "an explicitly null key must resolve to .none")
        }
        #expect(try corpus.lookup("person.nonexistent") == nil)
    }

    @Test("deduplicates repeated strings into one arena entry")
    func dedup() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let a = builder.addStringTable(["Ada", "Grace", "Ada"])
        let b = builder.addStringTable(["Ada", "Grace"])
        builder.index("a", stringTable: a)
        builder.index("b", stringTable: b)
        let corpus = try Corpus(bytes: builder.build())

        // "", "unattributed", "Ada", "Grace", "a", "b" -- five distinct plus the empty
        // reserved slot, with "Ada" and "Grace" stored once despite four occurrences.
        #expect(corpus.stringCount == 6)
    }

    @Test("an empty table draws nil rather than trapping")
    func emptyTable() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let empty = builder.addStringTable([])
        builder.index("empty", stringTable: empty)
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("empty")) else {
            return #expect(Bool(false), "expected a string table")
        }
        var rng = Xoshiro256StarStar(seed: 1)
        #expect(table.isEmpty)
        #expect(try table.draw(using: &rng) == nil)
    }

    @Test("handles many keys, exercising the binary search")
    func manyKeys() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        for i in 0..<5_000 {
            let id = builder.addStringTable(["value\(i)"])
            builder.index("category.key\(i)", stringTable: id)
        }
        let corpus = try Corpus(bytes: builder.build())

        for i in stride(from: 0, to: 5_000, by: 137) {
            guard case .strings(let table) = try #require(try corpus.lookup("category.key\(i)")) else {
                return #expect(Bool(false), "expected a string table for key\(i)")
            }
            #expect(try table.string(at: 0) == "value\(i)")
        }
        #expect(try corpus.lookup("category.key5000") == nil)
    }

    @Test("building the same input twice is byte-identical")
    func deterministicOutput() {
        #expect(buildSample() == buildSample())
    }
}

@Suite("Corpus validation")
struct CorpusValidationTests {

    @Test("rejects a file that is not a corpus")
    func rejectsBadMagic() {
        var bytes = buildSample()
        bytes[0] = 0x00
        #expect(throws: CorpusError.self) { try Corpus(bytes: bytes) }
    }

    @Test("rejects a format version from the future")
    func rejectsNewerFormat() {
        var bytes = buildSample()
        bytes[8] = 0xFF  // formatVersion low byte
        bytes[9] = 0x00
        #expect(throws: CorpusError.self) { try Corpus(bytes: bytes) }
    }

    @Test("rejects a truncated file")
    func rejectsTruncation() {
        let bytes = buildSample()
        #expect(throws: CorpusError.self) { try Corpus(bytes: Array(bytes.prefix(bytes.count / 2))) }
        #expect(throws: CorpusError.self) { try Corpus(bytes: []) }
    }

    /// Locks the on-disk encoding to little-endian regardless of the host.
    ///
    /// Asserting the actual bytes is the only way to catch a refactor that starts
    /// writing host-native integers — which would pass every other test in this file
    /// on an x86 or arm64 machine and produce garbage on the first big-endian target.
    @Test("integers are encoded little-endian")
    func littleEndianEncoding() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 0x0102, minor: 3, patch: 4))
        builder.index("x", stringTable: builder.addStringTable(["v"]))
        let bytes = builder.build()

        #expect(Array(bytes[0..<8]) == Array("DECOYBIN".utf8))
        #expect(bytes[8] == 1 && bytes[9] == 0, "formatVersion 1 as LE u16")
        // 0x0102 little-endian is [0x02, 0x01]; big-endian would be [0x01, 0x02].
        #expect(bytes[12] == 0x02 && bytes[13] == 0x01, "corpusMajor as LE u16")
        #expect(bytes[14] == 3 && bytes[15] == 0)
        #expect(bytes[20] == 5 && bytes[21] == 0, "five chunks as LE u32")

        let corpus = try Corpus(bytes: bytes)
        #expect(corpus.version.major == 0x0102)
    }

    /// A reader built today must carry a corpus containing chunks it does not
    /// understand, or adding generative model chunks later would break every
    /// previously shipped build.
    @Test("tolerates an unknown chunk kind")
    func toleratesUnknownChunks() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        builder.index("greeting", stringTable: builder.addStringTable(["hello"]))
        builder.addRawChunk(kind: 99, payload: Array("a chunk from the future".utf8))

        let corpus = try Corpus(bytes: builder.build())
        guard case .strings(let table) = try #require(try corpus.lookup("greeting")) else {
            return #expect(Bool(false), "expected a string table")
        }
        #expect(try table.string(at: 0) == "hello")
    }

    /// A required chunk going missing is a different failure, and must still be caught.
    @Test("rejects a corpus missing a required chunk")
    func rejectsMissingArena() {
        var bytes = buildSample()
        bytes[32] = 99  // relabel the arena chunk as something unknown
        #expect(throws: CorpusError.self) { try Corpus(bytes: bytes) }
    }
}
