import Testing

@testable import Decoy
@testable import DecoyLocaleDE
@testable import DecoyLocaleEN
@testable import DecoyLocaleJA

/// Guards against templates that expand to nothing.
///
/// The existing `noLeakedTemplates` check asserts only that `{{`, `}}` and `#` are absent
/// from output. An unresolvable token does not leak braces — `expand` substitutes an empty
/// string — so it passed while `location.streetAddress()` returned `"791 "` in English and
/// `""` in Japanese, and every `finance.transactionDescription()` in English had two holes
/// in it. Thirteen distinct tokens were silently expanding to nothing.
@Suite("Template expansion")
struct TemplateExpansionTests {

    private static let locales: [(String, LocaleCorpus)] = [
        ("en", DecoyLocaleEN.locale),
        ("de", DecoyLocaleDE.locale),
        ("ja", DecoyLocaleJA.locale),
    ]

    /// Every `{{token}}` in a string, without the braces.
    private func tokens(in template: String) -> [String] {
        var found: [String] = []
        var rest = Substring(template)
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            found.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return found
    }

    @Test("every token in every shipped pattern resolves to something")
    func everyTokenResolves() throws {
        var unresolved: [String] = []

        for (code, locale) in Self.locales {
            var faker = Faker(seed: 1337, locale: locale)
            // Deduplicated: `en` alone holds ~25,000 surnames, and re-resolving the same
            // handful of tokens once per string turned a sub-second suite into a minute.
            var seen = Set<String>()

            for entry in try locale.chain[0].paths {
                guard case .strings(let table) = try locale.chain[0].entry(for: entry) else {
                    continue
                }
                for index in 0..<table.count {
                    let value = try table.string(at: index)
                    guard value.utf8.contains(UInt8(ascii: "{")) else { continue }
                    for token in tokens(in: value) where seen.insert("\(entry.path)|\(token)").inserted {
                        let resolved = faker.resolve(token)
                        if resolved == nil || resolved!.isEmpty {
                            unresolved.append("\(code): {{\(token)}} in \(entry.path)")
                        }
                    }
                }
            }
        }

        let report = unresolved.prefix(20).joined(separator: "; ")
        #expect(unresolved.isEmpty, "tokens expanding to nothing: \(report)")
    }

    @Test("template-backed generators produce no empty segments")
    func noEmptySegments() {
        // Leading and trailing whitespace is the reliable symptom of a vanished token:
        // `location.streetAddress()` returned "791 " when `{{location.street}}` resolved
        // to nothing.
        //
        // A doubled space is asserted too, now. It was left out on the grounds that
        // faker's own `person.bio_pattern` has `{{person.bio_supporter}}  {{internet.emoji}}`
        // and reproducing the source faithfully is correct — which was the wrong call.
        // That is a typo, not data, every locale inherits it, and it produced 427
        // distinct defective outputs across the corpus.
        for (code, locale) in Self.locales {
            var faker = Faker(seed: 20_260_808, locale: locale)
            for _ in 0..<200 {
                for (label, value) in [
                    ("streetAddress", faker.location.streetAddress()),
                    ("transactionDescription", faker.finance.transactionDescription()),
                    ("userAgent", faker.internet.userAgent()),
                    ("productDescription", faker.commerce.productDescription()),
                    ("companyName", faker.company.name()),
                    ("bio", faker.person.bio()),
                ] {
                    #expect(!value.isEmpty, "\(code) \(label) produced an empty string")
                    #expect(
                        value.first != " " && value.last != " ",
                        "\(code) \(label) has leading or trailing space: '\(value)'"
                    )
                    #expect(
                        !value.contains("  "),
                        "\(code) \(label) has a doubled space: '\(value)'"
                    )
                }
            }
        }
    }

    @Test("a self-referential pattern terminates instead of overflowing the stack")
    func selfReferenceTerminates() {
        // `de`'s street pattern is literally `{{location.street_name}}`. Mapping that
        // token to the generator that expands the pattern re-enters `expand` from the
        // top, which the per-call depth counter cannot see — it crashed with SIGSEGV
        // rather than hanging. The depth now lives on the Faker.
        var builder = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
        let source = builder.addSource(
            id: "test", license: "Apache-2.0", url: "", version: "1", retrieved: ""
        )
        builder.index(
            "location.street_pattern",
            stringTable: builder.addStringTable(["{{location.streetName}}"], source: source)
        )
        builder.index(
            "location.street_name",
            stringTable: builder.addStringTable(["{{location.streetName}}"], source: source)
        )

        var faker = Faker(
            seed: 1,
            locale: LocaleCorpus(code: "t", chain: [try! Corpus(bytes: builder.build())])
        )
        // Reaching this line at all is the assertion.
        _ = faker.location.streetName()
    }

    @Test("helper call syntax resolves rather than vanishing")
    func callSyntax() {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)

        let digits = faker.resolve("string.numeric(4)") ?? ""
        #expect(digits.count == 4)
        let allDigits = digits.allSatisfy { $0.isNumber }
        #expect(allDigits, "got '\(digits)'")

        let bounded = faker.resolve(#"number.int({"min":10,"max":18})"#) ?? ""
        #expect(Int(bounded).map { (10...18).contains($0) } == true, "got '\(bounded)'")

        let chosen = faker.resolve(#"helpers.arrayElement(["5.1","6.0"])"#) ?? ""
        #expect(["5.1", "6.0"].contains(chosen), "got '\(chosen)'")
    }
}

/// Tests for the whitespace tidy applied to expanded templates.
///
/// Newlines are the reason this is not a general "collapse whitespace": a postal address
/// is a multi-line block, and flattening it would run the street into the city.
@Suite("Template whitespace")
struct TemplateWhitespaceTests {

    @Test("runs of spaces collapse to one")
    func collapses() {
        #expect(Faker.tidied("a  b") == "a b")
        #expect(Faker.tidied("a     b") == "a b")
        #expect(Faker.tidied("a b") == "a b")
    }

    @Test("the ends are trimmed, which is what an empty token at an edge leaves")
    func trims() {
        // `{{person.prefix}} {{person.firstName}}` in a locale declaring prefixes empty.
        #expect(Faker.tidied(" Jane Doe") == "Jane Doe")
        #expect(Faker.tidied("Jane Doe ") == "Jane Doe")
        #expect(Faker.tidied("  Jane Doe  ") == "Jane Doe")
    }

    @Test("newlines survive, because a postal address depends on them")
    func keepsNewlines() {
        #expect(Faker.tidied("12 Main St\nBoston") == "12 Main St\nBoston")
        #expect(Faker.tidied("12  Main St\n\nBoston") == "12 Main St\n\nBoston")
    }

    @Test("a multi-line address keeps its shape end to end")
    func postalAddress() {
        guard RealCorpus.isAvailable else { return }
        guard let locale = try? RealCorpus.locale("en", chain: ["en", "base"]) else { return }
        var faker = Faker(seed: 1337, locale: locale)
        for _ in 0..<50 {
            let address = faker.location.postalAddress()
            #expect(!address.contains("  "), "'\(address)'")
            #expect(!address.isEmpty)
        }
    }
}
