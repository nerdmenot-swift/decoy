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

        guard case .explicitlyEmpty = try #require(try corpus.lookup("person.prefix")) else {
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

    // MARK: - Encoding shapes

    /// A table of all-new strings occupies a consecutive arena run, so it stores one
    /// starting index instead of one index per entry.
    @Test("contiguous tables round-trip")
    func contiguousTable() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let id = builder.addStringTable(["alpha", "beta", "gamma", "delta"])
        builder.index("run", stringTable: id)
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("run")) else {
            return #expect(Bool(false), "expected a string table")
        }
        #expect(table.isContiguous, "all-new strings should form a run")
        #expect(try (0..<4).map { try table.string(at: $0) } == ["alpha", "beta", "gamma", "delta"])
    }

    /// Strings already interned elsewhere break the run, so the table must fall back
    /// to an explicit index list — and still read back correctly.
    @Test("non-contiguous tables round-trip")
    func nonContiguousTable() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let first = builder.addStringTable(["alpha", "beta", "gamma"])
        // Reuses "alpha" and "gamma", so this table's indices are not consecutive.
        let second = builder.addStringTable(["gamma", "alpha", "epsilon"])
        builder.index("first", stringTable: first)
        builder.index("second", stringTable: second)
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("second")) else {
            return #expect(Bool(false), "expected a string table")
        }
        #expect(table.isContiguous == false)
        #expect(try (0..<3).map { try table.string(at: $0) } == ["gamma", "alpha", "epsilon"])
    }

    /// The case that motivated run encoding: one repeated string in a large table.
    /// An all-or-nothing scheme would write out all 300 indices to accommodate it.
    @Test("run-encoded tables round-trip")
    func runEncodedTable() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        builder.index("earlier", stringTable: builder.addStringTable(["repeated"]))

        var values = (0..<300).map { "value\($0)" }
        values[150] = "repeated"
        values[275] = "value7"
        builder.index("big", stringTable: builder.addStringTable(values))
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("big")) else {
            return #expect(Bool(false), "expected a string table")
        }
        guard case .runs(let runCount) = table.layout else {
            return #expect(Bool(false), "expected run encoding, got \(table.layout)")
        }
        #expect(runCount == 5, "two interruptions should split the table into five runs")
        for i in 0..<300 {
            #expect(try table.string(at: i) == values[i], "entry \(i) misread")
        }
    }

    /// Every entry of every layout must resolve, including the boundaries where a
    /// binary search over runs is most likely to be off by one.
    @Test("run boundaries resolve exactly", arguments: [1, 2, 5, 17, 64])
    func runBoundaries(stride: Int) throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        builder.index("seed", stringTable: builder.addStringTable(["A", "B", "C"]))

        // Interleaving reused strings at varying intervals produces very different
        // run counts, exercising short and long binary searches alike.
        let values = (0..<200).map { $0 % stride == 0 ? "A" : "v\($0)" }
        builder.index("mixed", stringTable: builder.addStringTable(values))
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("mixed")) else {
            return #expect(Bool(false), "expected a string table")
        }
        for i in 0..<200 {
            #expect(try table.string(at: i) == values[i], "stride \(stride), entry \(i)")
        }
    }

    @Test("weights survive on both contiguous and non-contiguous tables")
    func weightsWithBothLayouts() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let run = builder.addStringTable(["p", "q"], weights: [3, 7])
        let reused = builder.addStringTable(["q", "p"], weights: [11, 13])
        builder.index("run", stringTable: run)
        builder.index("reused", stringTable: reused)
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let a) = try #require(try corpus.lookup("run")),
            case .strings(let b) = try #require(try corpus.lookup("reused"))
        else { return #expect(Bool(false), "expected string tables") }

        #expect(a.isContiguous && !b.isContiguous)
        #expect(try a.weight(at: 0) == 3 && a.weight(at: 1) == 7)
        #expect(try b.weight(at: 0) == 11 && b.weight(at: 1) == 13)
        #expect(try b.string(at: 0) == "q")
    }

    /// Lengths under 255 use one byte; anything longer escapes to a `UInt32`. Both
    /// paths must be exercised, and a string either side of the boundary is where an
    /// off-by-one would hide.
    @Test("long strings use the escape encoding", arguments: [0, 1, 253, 254, 255, 256, 70_000])
    func longStrings(length: Int) throws {
        let long = String(repeating: "x", count: length)
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        builder.index("padding", stringTable: builder.addStringTable(["a", "b"]))
        builder.index("long", stringTable: builder.addStringTable([long, "after"]))
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("long")) else {
            return #expect(Bool(false), "expected a string table")
        }
        #expect(try table.string(at: 0).count == length)
        #expect(try table.string(at: 0) == long)
        #expect(try table.string(at: 1) == "after", "the entry after a long string must still resolve")
    }

    /// Only every 16th string is indexed, so reads scan forward. This crosses many
    /// checkpoint boundaries and checks every single string, which is what catches a
    /// mis-sized skip.
    @Test("checkpoint scanning resolves every string")
    func checkpointScanning() throws {
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        // Deliberately varied lengths, including escape-encoded ones, so the forward
        // scan cannot accidentally work by every entry being the same width.
        let values = (0..<200).map { i in
            String(repeating: "\(i % 10)", count: i % 7 == 0 ? 300 : (i % 13) + 1)
        }
        builder.index("many", stringTable: builder.addStringTable(values))
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("many")) else {
            return #expect(Bool(false), "expected a string table")
        }
        for i in 0..<200 {
            #expect(try table.string(at: i) == values[i], "string \(i) misread")
        }
    }

    @Test("unicode survives the length prefix")
    func unicodeStrings() throws {
        let values = ["Müller", "北京", "🇮🇳 भारत", "Ωμέγα", "أبجدية"]
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        builder.index("unicode", stringTable: builder.addStringTable(values))
        let corpus = try Corpus(bytes: builder.build())

        guard case .strings(let table) = try #require(try corpus.lookup("unicode")) else {
            return #expect(Bool(false), "expected a string table")
        }
        // Length is counted in UTF-8 bytes, not characters — a multi-byte string that
        // read back short would mean the prefix was measured in the wrong unit.
        #expect(try (0..<values.count).map { try table.string(at: $0) } == values)
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

    /// An older blob must be refused, not read. Its chunks would parse as plausible
    /// garbage under the current layout, and silently serving wrong data is worse
    /// than failing to load.
    @Test("rejects a format version from the past")
    func rejectsOlderFormat() {
        var bytes = buildSample()
        bytes[8] = 1
        bytes[9] = 0
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
        #expect(bytes[8] == 2 && bytes[9] == 0, "formatVersion 2 as LE u16")
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
