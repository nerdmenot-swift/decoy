import Testing

@testable import Decoy

private func buildSample() -> [UInt8] {
    var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
    let source = builder.addSource(
        id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: ""
    )

    builder.index(
        "person.first_name.female",
        stringTable: builder.addStringTable(["Ada", "Grace"], source: source)
    )
    builder.index(
        "person.name",
        stringTable: builder.addStringTable(["{{first}} {{last}}"], weights: [1], source: source)
    )
    builder.index(
        "location.country_code",
        compositeTable: builder.addCompositeTable(
            fields: ["alpha2", "alpha3"], rows: [["AD", "AND"]], source: source
        )
    )
    builder.indexNull("person.prefix")
    return builder.build()
}

@Suite("Corpus enumeration")
struct CorpusEnumerationTests {

    @Test("lists every indexed path, sorted")
    func listsPaths() throws {
        let corpus = try Corpus(bytes: buildSample())
        let paths = try corpus.paths.map(\.path)

        #expect(
            paths == [
                "location.country_code",
                "person.first_name.female",
                "person.name",
                "person.prefix",
            ],
            "paths are sorted lexicographically, not left in the index's hash order"
        )
    }

    @Test("reports the kind at each path without loading its table")
    func reportsKinds() throws {
        let corpus = try Corpus(bytes: buildSample())
        let kinds = Dictionary(
            uniqueKeysWithValues: try corpus.paths.map { ($0.path, $0.kind) }
        )

        #expect(kinds["person.first_name.female"] == .strings)
        #expect(kinds["location.country_code"] == .composite)
        #expect(
            kinds["person.prefix"] == .explicitlyEmpty,
            "an explicit null is a path the locale defines, not an absent one"
        )
    }

    @Test("enumerated entries resolve to the same tables as lookup")
    func entriesMatchLookup() throws {
        let corpus = try Corpus(bytes: buildSample())

        for pathEntry in try corpus.paths {
            let direct = try #require(try corpus.lookup(pathEntry.path))
            let enumerated = try corpus.entry(for: pathEntry)

            switch (direct, enumerated) {
            case (.strings(let a), .strings(let b)):
                #expect(a.count == b.count)
                #expect(try a.string(at: 0) == (try b.string(at: 0)))
            case (.composite(let a), .composite(let b)):
                #expect(a.rowCount == b.rowCount)
                #expect(try a.row(0) == (try b.row(0)))
            case (.explicitlyEmpty, .explicitlyEmpty):
                break
            default:
                #expect(Bool(false), "\(pathEntry.path) resolved to two different kinds")
            }
        }
    }

    @Test("every path found by enumeration is retrievable by lookup")
    func enumerationAgreesWithLookup() throws {
        let corpus = try Corpus(bytes: buildSample())
        for pathEntry in try corpus.paths {
            #expect(
                try corpus.lookup(pathEntry.path) != nil,
                "enumeration produced '\(pathEntry.path)', which lookup cannot find"
            )
        }
    }

    @Test("an unrecognised kind is reported rather than thrown")
    func unknownKindSurvives() {
        // Forward compatibility has to hold for listing too: inspecting a newer corpus
        // is exactly what you would do to find out why it fails.
        #expect(PathEntry.Kind(raw: 99) == .unknown(99))
        #expect(PathEntry.Kind(raw: 99).raw == 99)
        #expect(PathEntry.Kind(raw: 2) == .composite)
    }

    @Test("every registered source is enumerable, not only the attributed ones")
    func sourcesEnumerate() throws {
        // The distinction this protects: a source registered but never referenced by a
        // table still has to appear, because NOTICE is generated from this. Attribution
        // by table would have silently dropped the ISO 4217 registry from the real corpus.
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let used = builder.addSource(
            id: "used", license: "MIT", url: "https://example.org/used",
            version: "1", retrieved: "2026-08-08"
        )
        _ = builder.addSource(
            id: "registered-but-unreferenced", license: "CC-BY-4.0",
            url: "https://example.org/other", version: "2", retrieved: "2026-08-08"
        )
        builder.index("a.b", stringTable: builder.addStringTable(["x"], source: used))

        let corpus = try Corpus(bytes: builder.build())
        let ids = try corpus.sources.map(\.id)

        #expect(ids.contains("used"))
        #expect(
            ids.contains("registered-but-unreferenced"),
            "a source no table points at is still part of what the corpus was built from"
        )
        #expect(try corpus.sources.first { $0.id == "registered-but-unreferenced" }?.license
            == "CC-BY-4.0")
    }

    @Test("a chain lists the union of its locales, most specific winning")
    func chainUnion() throws {
        var front = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let frontSource = front.addSource(
            id: "front", license: "Apache-2.0", url: "", version: "1", retrieved: ""
        )
        front.index(
            "person.first_name.female",
            stringTable: front.addStringTable(["Sofia"], source: frontSource)
        )

        let locale = LocaleCorpus(
            code: "test",
            chain: [try Corpus(bytes: front.build()), try Corpus(bytes: buildSample())]
        )

        #expect(
            try locale.paths.map(\.path) == [
                "location.country_code",
                "person.first_name.female",
                "person.name",
                "person.prefix",
            ]
        )
        #expect(
            try locale.nativePaths.map(\.path) == ["person.first_name.female"],
            "native paths show only what the front of the chain defines itself"
        )

        // The front corpus wins, matching resolve(_:).
        let entry = try #require(try locale.paths.first { $0.path == "person.first_name.female" })
        guard case .strings(let table) = try locale.chain[0].entry(for: entry) else {
            return #expect(Bool(false), "expected a string table")
        }
        #expect(try table.string(at: 0) == "Sofia")
    }
}
