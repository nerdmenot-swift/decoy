import Testing

@testable import Decoy

/// A corpus shaped like the one `programming-languages.mjs` produces.
///
/// Built inline rather than read from a compiled blob because the locale modules shipped
/// today are still generated from the faker-derived corpus, which has no
/// `system.programming_language`. The generator is what is under test here; the adapter's
/// output is verified separately with `decoy-inspect`.
private func languageCorpus() -> LocaleCorpus {
    var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
    let source = builder.addSource(
        id: "linguist", license: "MIT", url: "", version: "9.4.0", retrieved: "2026-08-07"
    )

    builder.index(
        "system.programming_language",
        compositeTable: builder.addCompositeTable(
            fields: ["name", "extension", "color"],
            rows: [
                ["Swift", ".swift", "#F05138"],
                ["Rust", ".rs", "#dea584"],
                ["Go", ".go", "#00ADD8"],
                ["Haskell", ".hs", ""],
            ],
            source: source
        )
    )
    builder.index(
        "word.adjective",
        stringTable: builder.addStringTable(["quiet", "hollow"], source: source)
    )
    builder.index(
        "word.noun",
        stringTable: builder.addStringTable(["harbour", "ledger"], source: source)
    )

    return LocaleCorpus(code: "test", chain: [try! Corpus(bytes: builder.build())])
}

@Suite("Programming languages")
struct ProgrammingLanguageTests {

    @Test("a row's parts belong to the same language")
    func rowsAreCoherent() {
        // The whole reason this is a composite: drawn independently you get Haskell with
        // a .rs extension in Go's blue.
        let known = [
            "Swift": (".swift", "#F05138"),
            "Rust": (".rs", "#dea584"),
            "Go": (".go", "#00ADD8"),
            "Haskell": (".hs", ""),
        ]

        var f = Faker(seed: 1337, locale: languageCorpus())
        for _ in 0..<200 {
            let row = f.system.programmingLanguage()
            let name = try! #require(row["name"])
            let expected = try! #require(known[name])
            #expect(row["extension"] == expected.0, "\(name) drew the wrong extension")
            #expect(row["color"] == expected.1, "\(name) drew the wrong colour")
        }
    }

    @Test("the name accessor agrees with the row")
    func nameAccessor() {
        var a = Faker(seed: 7, locale: languageCorpus())
        var b = Faker(seed: 7, locale: languageCorpus())
        #expect(a.system.programmingLanguageName() == b.system.programmingLanguage()["name"])
    }

    @Test("a language with no assigned colour yields an empty column, not a missing one")
    func emptyColour() {
        var f = Faker(seed: 3, locale: languageCorpus())
        for _ in 0..<200 {
            let row = f.system.programmingLanguage()
            #expect(row["color"] != nil, "the colour column must exist on every row")
        }
    }

    @Test("a locale with no language data yields an empty row rather than trapping")
    func missingData() {
        var f = Faker(seed: 1, locale: .builtIn)
        #expect(f.system.programmingLanguage().isEmpty)
        #expect(f.system.programmingLanguageName() == "")
    }

    @Test("variable names render in each naming style")
    func variableNameStyles() {
        for style in ContentSystemStyles.all {
            var f = Faker(seed: 42, locale: languageCorpus())
            let name = f.system.variableName(style)
            #expect(!name.isEmpty)
            #expect(
                name.allSatisfy { $0.isLetter || $0 == "_" || $0 == "-" },
                "\(style) produced \(name)"
            )
        }
    }

    @Test("each naming style has its own shape")
    func stylesDiffer() {
        var camel = Faker(seed: 42, locale: languageCorpus())
        var snake = Faker(seed: 42, locale: languageCorpus())
        var pascal = Faker(seed: 42, locale: languageCorpus())
        var screaming = Faker(seed: 42, locale: languageCorpus())

        let c = camel.system.variableName(.camelCase)
        let s = snake.system.variableName(.snakeCase)
        let p = pascal.system.variableName(.pascalCase)
        let u = screaming.system.variableName(.screamingSnakeCase)

        #expect(!c.contains("_"))
        #expect(c.first!.isLowercase)
        #expect(s.contains("_"))
        #expect(s.lowercased() == s)
        #expect(p.first!.isUppercase)
        #expect(u.uppercased() == u)
    }

    @Test("the same seed reproduces the same identifier")
    func deterministic() {
        var a = Faker(seed: 99, locale: languageCorpus())
        var b = Faker(seed: 99, locale: languageCorpus())
        #expect(a.system.variableName() == b.system.variableName())
    }
}

/// Kept out of the test bodies so adding a style fails to compile here rather than
/// silently going untested.
private enum ContentSystemStyles {
    static let all = SystemFaker.NamingStyle.allCases
}
