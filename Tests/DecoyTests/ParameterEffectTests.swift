import Foundation
import Testing

@testable import Decoy

/// Asserts that every parameter on every generator changes what that generator produces.
///
/// `fullName(gender:)` was a no-op for the library's entire life. Nothing caught it because
/// the tests exercised `firstName` *with* a gender and `fullName` *without* one — each
/// method was covered, each parameter was covered, and the pairing of the two was not. That
/// is the gap: coverage measured per method and per parameter can be complete while the
/// cross-product is empty.
///
/// So this walks the cross-product. For each parameter it calls the generator twice from the
/// *same seed*, varying only that argument, and requires the two to disagree on at least one
/// seed. An argument that cannot change the output is either dead or a lie about what the
/// data supports, and both are worth failing over.
///
/// It found one on the first run: `lastName(_ gender:)`. No locale in the corpus carries a
/// gendered surname — `person.last_name` is `.generic` in all sixty-six — so the argument
/// was accepted and discarded everywhere. See the note on `PersonFaker.lastName` for what
/// happened to it.
///
/// ## Why the table is written out by hand
///
/// Swift has no reflection here — it was removed from this package deliberately, and a test
/// that reintroduced `Mirror` would be the only thing in the package needing it. So the
/// cases are literals, which means the table can rot: adding a parameter and forgetting to
/// add a case leaves the suite green and the parameter unwatched, which is precisely the
/// failure this suite exists to prevent, one level up.
///
/// `tableCoversEveryParameter` closes that. It parses the generator sources for parameters
/// and requires the table to name each one, so a new parameter fails the suite until it has
/// a case. The two tests are load-bearing only as a pair.
@Suite(
    "Parameter effect",
    .enabled(if: RealCorpus.isAvailable, "compiled corpus not present — see RealCorpus")
)
struct ParameterEffectTests {

    /// One way of calling a generator, and a label for the failure message.
    ///
    /// The call returns `String` whatever the generator returns, because the comparison only
    /// ever asks whether two results differ — rendering `Date`, `Timestamp`, `Int` and the
    /// coordinate tuple into text costs nothing and keeps one code path.
    struct Variant {
        let label: String
        let call: (inout Faker) -> String

        init(_ label: String, _ call: @escaping (inout Faker) -> String) {
            self.label = label
            self.call = call
        }
    }

    struct ParameterCase {
        /// `Namespace.method`, matching what the source parser produces.
        let method: String
        /// The parameter's *internal* name — `range` for `in range:`, `gender` for
        /// `_ gender:`. Internal names are unique within a signature where external ones
        /// are not: `paragraphs(_ count:, separator:)` has two parameters and one of them
        /// is labelled `_`.
        let parameter: String
        let chain: [String]
        let variants: [Variant]

        var key: String { "\(method):\(parameter)" }

        init(
            _ method: String, _ parameter: String, chain: [String] = ["en", "base"],
            _ variants: [Variant]
        ) {
            self.method = method
            self.parameter = parameter
            self.chain = chain
            self.variants = variants
        }
    }

    /// Enough seeds that a parameter which genuinely narrows a pool will show it.
    ///
    /// Two variants can agree by coincidence — `variableName(_ style:)` returns the same
    /// text in `.camelCase` and `.snakeCase` whenever the name is a single word — so a
    /// single seed proves nothing. Two hundred is far past the point where a live parameter
    /// stays hidden, and the whole suite still runs in about a second.
    static let seeds: [UInt64] = (1...200).map(UInt64.init)

    // MARK: - The table

    static var cases: [ParameterCase] {
        var all: [ParameterCase] = []

        all += [
            ParameterCase(
                "AirlineFaker.flightNumber", "digits",
                [
                    Variant("2") { "\($0.airline.flightNumber(digits: 2))" },
                    Variant("6") { "\($0.airline.flightNumber(digits: 6))" },
                ]),
            ParameterCase(
                "CommerceFaker.price", "range",
                [
                    Variant("1...10") { $0.commerce.price(in: 1...10) },
                    Variant("5000...6000") { $0.commerce.price(in: 5_000...6_000) },
                ]),
            ParameterCase(
                "CommerceFaker.price", "decimals",
                [
                    Variant("0") { $0.commerce.price(decimals: 0) },
                    Variant("3") { $0.commerce.price(decimals: 3) },
                ]),
            ParameterCase(
                "FinanceFaker.accountNumber", "digits",
                [
                    Variant("4") { $0.finance.accountNumber(digits: 4) },
                    Variant("14") { $0.finance.accountNumber(digits: 14) },
                ]),
            ParameterCase(
                "FinanceFaker.creditCardNumber", "issuer",
                [
                    Variant("visa") { $0.finance.creditCardNumber(issuer: "visa") },
                    Variant("jcb") { $0.finance.creditCardNumber(issuer: "jcb") },
                ]),
            ParameterCase(
                "FinanceFaker.iban", "country",
                [
                    Variant("GB") { $0.finance.iban(country: "GB") },
                    Variant("DE") { $0.finance.iban(country: "DE") },
                ]),
        ]

        all += [
            ParameterCase(
                "InternetFaker.email", "firstName",
                [
                    Variant("nil") { $0.internet.email() },
                    Variant("given") { $0.internet.email(firstName: "Ada") },
                ]),
            ParameterCase(
                "InternetFaker.email", "lastName",
                [
                    Variant("nil") { $0.internet.email() },
                    Variant("given") { $0.internet.email(lastName: "Lovelace") },
                ]),
            ParameterCase(
                "InternetFaker.email", "domain",
                [
                    Variant("nil") { $0.internet.email() },
                    Variant("given") { $0.internet.email(domain: "decoy.test") },
                ]),
            ParameterCase(
                "InternetFaker.emoji", "category",
                [
                    Variant("flag") { $0.internet.emoji("flag") },
                    Variant("food") { $0.internet.emoji("food") },
                ]),
            ParameterCase(
                "InternetFaker.httpStatusCode", "category",
                [
                    Variant("informational") { "\($0.internet.httpStatusCode(.informational))" },
                    Variant("serverError") { "\($0.internet.httpStatusCode(.serverError))" },
                ]),
            ParameterCase(
                "InternetFaker.password", "length",
                [
                    Variant("8") { $0.internet.password(length: 8) },
                    Variant("40") { $0.internet.password(length: 40) },
                ]),
            ParameterCase(
                "InternetFaker.url", "secure",
                [
                    Variant("true") { $0.internet.url(secure: true) },
                    Variant("false") { $0.internet.url(secure: false) },
                ]),
            ParameterCase(
                "PhoneFaker.number", "style",
                [
                    Variant("human") { $0.phone.number(.human) },
                    Variant("international") { $0.phone.number(.international) },
                ]),
        ]

        all += [
            ParameterCase(
                "LocationFaker.cardinalDirection", "abbreviated",
                [
                    Variant("false") { $0.location.cardinalDirection(abbreviated: false) },
                    Variant("true") { $0.location.cardinalDirection(abbreviated: true) },
                ]),
            ParameterCase(
                "LocationFaker.direction", "abbreviated",
                [
                    Variant("false") { $0.location.direction(abbreviated: false) },
                    Variant("true") { $0.location.direction(abbreviated: true) },
                ]),
            ParameterCase(
                "LocationFaker.ordinalDirection", "abbreviated",
                [
                    Variant("false") { $0.location.ordinalDirection(abbreviated: false) },
                    Variant("true") { $0.location.ordinalDirection(abbreviated: true) },
                ]),
            ParameterCase(
                "LocationFaker.coordinate", "origin",
                [
                    Variant("nil") { f in
                        let c = f.location.coordinate()
                        return "\(c.latitude),\(c.longitude)"
                    },
                    Variant("(0,0)") { f in
                        let c = f.location.coordinate(near: (latitude: 0, longitude: 0))
                        return "\(c.latitude),\(c.longitude)"
                    },
                ]),
            // `radiusKm` scales an offset from `origin`, so it can only show an effect when
            // there is an origin to offset from. Varying it against the default `nil` origin
            // would compare two unrelated random points and pass for the wrong reason —
            // exactly the false green this suite is meant to be immune to.
            ParameterCase(
                "LocationFaker.coordinate", "radiusKm",
                [
                    Variant("1km") { f in
                        let c = f.location.coordinate(
                            near: (latitude: 0, longitude: 0), radiusKm: 1)
                        return "\(c.latitude),\(c.longitude)"
                    },
                    Variant("500km") { f in
                        let c = f.location.coordinate(
                            near: (latitude: 0, longitude: 0), radiusKm: 500)
                        return "\(c.latitude),\(c.longitude)"
                    },
                ]),
            ParameterCase(
                "LocationFaker.postcode", "abbreviation",
                [
                    Variant("nil") { $0.location.postcode(state: nil) ?? "nil" },
                    Variant("CA") { $0.location.postcode(state: "CA") ?? "nil" },
                ]),
            ParameterCase(
                "LocationFaker.streetAddress", "full",
                [
                    Variant("false") { $0.location.streetAddress(full: false) },
                    Variant("true") { $0.location.streetAddress(full: true) },
                ]),
        ]

        all += [
            ParameterCase(
                "LoremFaker.paragraph", "count",
                [
                    Variant("nil") { $0.lorem.paragraph() },
                    Variant("9") { $0.lorem.paragraph(sentences: 9) },
                ]),
            ParameterCase(
                "LoremFaker.paragraphs", "count",
                [
                    Variant("1") { $0.lorem.paragraphs(1) },
                    Variant("4") { $0.lorem.paragraphs(4) },
                ]),
            ParameterCase(
                "LoremFaker.paragraphs", "separator",
                [
                    Variant("default") { $0.lorem.paragraphs(3) },
                    Variant("pipe") { $0.lorem.paragraphs(3, separator: " | ") },
                ]),
            ParameterCase(
                "LoremFaker.sentence", "count",
                [
                    Variant("nil") { $0.lorem.sentence() },
                    Variant("12") { $0.lorem.sentence(words: 12) },
                ]),
            ParameterCase(
                "LoremFaker.sentences", "count",
                [
                    Variant("1") { $0.lorem.sentences(1) },
                    Variant("5") { $0.lorem.sentences(5) },
                ]),
            ParameterCase(
                "LoremFaker.slug", "count",
                [
                    Variant("2") { $0.lorem.slug(words: 2) },
                    Variant("7") { $0.lorem.slug(words: 7) },
                ]),
            ParameterCase(
                "LoremFaker.text", "maxLength",
                [
                    Variant("30") { $0.lorem.text(maxLength: 30) },
                    Variant("400") { $0.lorem.text(maxLength: 400) },
                ]),
            ParameterCase(
                "LoremFaker.words", "count",
                [
                    Variant("2") { $0.lorem.words(2) },
                    Variant("9") { $0.lorem.words(9) },
                ]),
            ParameterCase(
                "WordFaker.words", "count",
                [
                    Variant("2") { $0.word.words(2) },
                    Variant("9") { $0.word.words(9) },
                ]),
            ParameterCase(
                "SystemFaker.variableName", "style",
                [
                    Variant("camelCase") { $0.system.variableName(.camelCase) },
                    Variant("screamingSnakeCase") { $0.system.variableName(.screamingSnakeCase) },
                ]),
        ]

        // Person. `prefix` needs a locale that actually carries honorifics — `ru` declares
        // `person.prefix` empty, and a locale that supplies nothing for a field would make
        // both variants return "" and fail for a reason that is not about the parameter.
        all += [
            ParameterCase(
                "PersonFaker.firstName", "gender",
                [
                    Variant("female") { $0.person.firstName(.female) },
                    Variant("male") { $0.person.firstName(.male) },
                ]),
            ParameterCase(
                "PersonFaker.middleName", "gender",
                [
                    Variant("female") { $0.person.middleName(.female) },
                    Variant("male") { $0.person.middleName(.male) },
                ]),
            ParameterCase(
                "PersonFaker.fullName", "gender",
                [
                    Variant("female") { $0.person.fullName(.female) },
                    Variant("male") { $0.person.fullName(.male) },
                ]),
            ParameterCase(
                "PersonFaker.prefix", "gender",
                [
                    Variant("female") { $0.person.prefix(.female) },
                    Variant("male") { $0.person.prefix(.male) },
                ]),
        ]

        all += instantCases()
        #if canImport(FoundationEssentials) || canImport(Foundation)
            all += dateCases()
        #endif
        return all
    }

    /// `InstantFaker` — the Foundation-free half of the date surface.
    static func instantCases() -> [ParameterCase] {
        [
            ParameterCase(
                "InstantFaker.between", "start",
                [
                    Variant("1970") { f in
                        "\(f.instant.between(Timestamp(secondsSinceEpoch: 0), Timestamp(secondsSinceEpoch: 1_000_000_000)).secondsSinceEpoch)"
                    },
                    Variant("2001") { f in
                        "\(f.instant.between(Timestamp(secondsSinceEpoch: 999_000_000), Timestamp(secondsSinceEpoch: 1_000_000_000)).secondsSinceEpoch)"
                    },
                ]),
            ParameterCase(
                "InstantFaker.between", "end",
                [
                    Variant("1970+1e9") { f in
                        "\(f.instant.between(Timestamp(secondsSinceEpoch: 0), Timestamp(secondsSinceEpoch: 1_000_000_000)).secondsSinceEpoch)"
                    },
                    Variant("1970+1e6") { f in
                        "\(f.instant.between(Timestamp(secondsSinceEpoch: 0), Timestamp(secondsSinceEpoch: 1_000_000)).secondsSinceEpoch)"
                    },
                ]),
            ParameterCase(
                "InstantFaker.birthdate", "minAge",
                [
                    Variant("18") { "\($0.instant.birthdate(minAge: 18).secondsSinceEpoch)" },
                    Variant("70") { "\($0.instant.birthdate(minAge: 70).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.birthdate", "maxAge",
                [
                    Variant("80") { "\($0.instant.birthdate(maxAge: 80).secondsSinceEpoch)" },
                    Variant("21") { "\($0.instant.birthdate(maxAge: 21).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.future", "years",
                [
                    Variant("1") { "\($0.instant.future(years: 1).secondsSinceEpoch)" },
                    Variant("40") { "\($0.instant.future(years: 40).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.past", "years",
                [
                    Variant("1") { "\($0.instant.past(years: 1).secondsSinceEpoch)" },
                    Variant("40") { "\($0.instant.past(years: 40).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.recent", "days",
                [
                    Variant("1") { "\($0.instant.recent(days: 1).secondsSinceEpoch)" },
                    Variant("900") { "\($0.instant.recent(days: 900).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.soon", "days",
                [
                    Variant("1") { "\($0.instant.soon(days: 1).secondsSinceEpoch)" },
                    Variant("900") { "\($0.instant.soon(days: 900).secondsSinceEpoch)" },
                ]),
            ParameterCase(
                "InstantFaker.unix", "years",
                [
                    Variant("1") { "\($0.instant.unix(years: 1))" },
                    Variant("30") { "\($0.instant.unix(years: 30))" },
                ]),
            ParameterCase(
                "InstantFaker.monthName", "abbreviated",
                [
                    Variant("false") { $0.instant.monthName(abbreviated: false) },
                    Variant("true") { $0.instant.monthName(abbreviated: true) },
                ]),
            ParameterCase(
                "InstantFaker.weekdayName", "abbreviated",
                [
                    Variant("false") { $0.instant.weekdayName(abbreviated: false) },
                    Variant("true") { $0.instant.weekdayName(abbreviated: true) },
                ]),
            ParameterCase(
                "InstantFaker.year", "range",
                [
                    Variant("nil") { "\($0.instant.year())" },
                    Variant("1900...1910") { "\($0.instant.year(in: 1900...1910))" },
                ]),
        ]
    }

    #if canImport(FoundationEssentials) || canImport(Foundation)
        /// `DateFaker` — the same surface returning `Date`, compiled only where Foundation is.
        ///
        /// Every one of these forwards to `InstantFaker`, so they look redundant. They are
        /// not: forwarding is exactly where an argument gets dropped, and a wrapper that
        /// ignores the parameter it was handed is the bug this suite is named after.
        static func dateCases() -> [ParameterCase] {
            [
                ParameterCase(
                    "DateFaker.between", "start",
                    [
                        Variant("1970") { f in
                            "\(f.date.between(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_000_000_000)).timeIntervalSince1970)"
                        },
                        Variant("2001") { f in
                            "\(f.date.between(Date(timeIntervalSince1970: 999_000_000), Date(timeIntervalSince1970: 1_000_000_000)).timeIntervalSince1970)"
                        },
                    ]),
                ParameterCase(
                    "DateFaker.between", "end",
                    [
                        Variant("1970+1e9") { f in
                            "\(f.date.between(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_000_000_000)).timeIntervalSince1970)"
                        },
                        Variant("1970+1e6") { f in
                            "\(f.date.between(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_000_000)).timeIntervalSince1970)"
                        },
                    ]),
                ParameterCase(
                    "DateFaker.birthdate", "minAge",
                    [
                        Variant("18") { "\($0.date.birthdate(minAge: 18).timeIntervalSince1970)" },
                        Variant("70") { "\($0.date.birthdate(minAge: 70).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.birthdate", "maxAge",
                    [
                        Variant("80") { "\($0.date.birthdate(maxAge: 80).timeIntervalSince1970)" },
                        Variant("21") { "\($0.date.birthdate(maxAge: 21).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.future", "years",
                    [
                        Variant("1") { "\($0.date.future(years: 1).timeIntervalSince1970)" },
                        Variant("40") { "\($0.date.future(years: 40).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.past", "years",
                    [
                        Variant("1") { "\($0.date.past(years: 1).timeIntervalSince1970)" },
                        Variant("40") { "\($0.date.past(years: 40).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.recent", "days",
                    [
                        Variant("1") { "\($0.date.recent(days: 1).timeIntervalSince1970)" },
                        Variant("900") { "\($0.date.recent(days: 900).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.soon", "days",
                    [
                        Variant("1") { "\($0.date.soon(days: 1).timeIntervalSince1970)" },
                        Variant("900") { "\($0.date.soon(days: 900).timeIntervalSince1970)" },
                    ]),
                ParameterCase(
                    "DateFaker.unix", "years",
                    [
                        Variant("1") { "\($0.date.unix(years: 1))" },
                        Variant("30") { "\($0.date.unix(years: 30))" },
                    ]),
                ParameterCase(
                    "DateFaker.monthName", "abbreviated",
                    [
                        Variant("false") { $0.date.monthName(abbreviated: false) },
                        Variant("true") { $0.date.monthName(abbreviated: true) },
                    ]),
                ParameterCase(
                    "DateFaker.weekdayName", "abbreviated",
                    [
                        Variant("false") { $0.date.weekdayName(abbreviated: false) },
                        Variant("true") { $0.date.weekdayName(abbreviated: true) },
                    ]),
                ParameterCase(
                    "DateFaker.year", "range",
                    [
                        Variant("nil") { "\($0.date.year())" },
                        Variant("1900...1910") { "\($0.date.year(in: 1900...1910))" },
                    ]),
            ]
        }
    #endif

    // MARK: - The behavioural half

    @Test("every generator parameter changes what the generator produces")
    func everyParameterHasAnEffect() throws {
        var locales: [String: LocaleCorpus] = [:]
        var dead: [String] = []

        for testCase in Self.cases {
            let key = testCase.chain.joined(separator: ">")
            let locale: LocaleCorpus
            if let cached = locales[key] {
                locale = cached
            } else {
                locale = try RealCorpus.locale(testCase.chain[0], chain: testCase.chain)
                locales[key] = locale
            }

            for i in testCase.variants.indices {
                for j in testCase.variants.indices where j > i {
                    var differed = false
                    for seed in Self.seeds {
                        var left = Faker(seed: seed, locale: locale)
                        var right = Faker(seed: seed, locale: locale)
                        if testCase.variants[i].call(&left) != testCase.variants[j].call(&right) {
                            differed = true
                            break
                        }
                    }
                    if !differed {
                        dead.append(
                            "\(testCase.key): \(testCase.variants[i].label) and "
                                + "\(testCase.variants[j].label) agree on all \(Self.seeds.count) seeds")
                    }
                }
            }
        }

        #expect(
            dead.isEmpty,
            """
            \(dead.count) parameter(s) had no effect on the output:
                \(dead.joined(separator: "\n    "))

            An argument that cannot change the result is either dead code or a promise the \
            corpus does not keep. Fix the generator, or remove the parameter and say why.
            """
        )
    }

    // MARK: - The completeness half

    private static let generatorDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/Decoy/Generators")

    @Test("the table covers every parameter the generators declare")
    func tableCoversEveryParameter() throws {
        let declared = try Self.parametersInSource()
        let covered = Set(Self.cases.map(\.key))

        let unwatched = declared.subtracting(covered).sorted()
        let stale = covered.subtracting(declared).sorted()

        #expect(
            unwatched.isEmpty,
            """
            \(unwatched.count) parameter(s) have no case in this file:
                \(unwatched.joined(separator: "\n    "))

            Add one varying only that argument. A parameter with no case is a parameter \
            nothing checks is wired up, which is how fullName(gender:) survived.
            """
        )
        #expect(
            stale.isEmpty,
            """
            \(stale.count) case(s) name a parameter the source no longer declares:
                \(stale.joined(separator: "\n    "))
            """
        )
    }

    /// Every `Namespace.method:parameter` declared under `Sources/Decoy/Generators`.
    ///
    /// Source text rather than reflection, for the same reason `SurfaceCountTests` reads
    /// source: this package carries no reflection and a test should not be the one thing
    /// that reintroduces it.
    static func parametersInSource() throws -> Set<String> {
        var keys: Set<String> = []

        for file in try FileManager.default.contentsOfDirectory(
            at: generatorDirectory, includingPropertiesForKeys: nil
        ) where file.pathExtension == "swift" {
            // `whereSeparator: \.isNewline` rather than splitting on "\n" — Swift's
            // Character is a grapheme cluster and CRLF is one of them, so a Windows
            // checkout splits into zero lines and every check silently passes.
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            var namespace: String?
            for (index, line) in lines.enumerated() {
                if line.hasPrefix("public struct "), line.hasSuffix("Faker {") {
                    namespace = String(
                        line.dropFirst("public struct ".count).dropLast(" {".count))
                    continue
                }
                guard let current = namespace,
                    line.hasPrefix("public func ") || line.hasPrefix("public mutating func "),
                    let openIndex = line.firstIndex(of: "(")
                else { continue }

                let name = line[..<openIndex].split(separator: " ").last.map(String.init) ?? ""

                // A signature may wrap across lines — `email(`, `price(`, `coordinate(` all
                // do — so accumulate until the parameter list's parentheses balance.
                var signature = line
                var offset = index
                var list = Self.parameterList(of: signature)
                while list == nil, offset + 1 < lines.count {
                    offset += 1
                    signature += " " + lines[offset]
                    list = Self.parameterList(of: signature)
                }
                guard let parameters = list, !parameters.trimmingCharacters(in: .whitespaces).isEmpty
                else { continue }

                for parameter in Self.split(parameters) {
                    guard let internalName = Self.internalName(of: parameter) else { continue }
                    keys.insert("\(current).\(name):\(internalName)")
                }
            }
        }
        return keys
    }

    /// The text between a signature's outermost parentheses, or nil if they do not close.
    private static func parameterList(of text: String) -> String? {
        guard let open = text.firstIndex(of: "(") else { return nil }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "(", "[": depth += 1
            case ")", "]":
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<index]) }
            default: break
            }
            index = text.indexAfter(index) ?? index
        }
        return nil
    }

    /// Splits a parameter list on commas that are not inside a tuple or generic.
    private static func split(_ list: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var current = ""
        for character in list {
            switch character {
            case "(", "[", "<": depth += 1
            case ")", "]", ">": depth -= 1
            case "," where depth == 0:
                out.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out
    }

    /// The internal name of one parameter: `range` from `in range: ClosedRange<Int> = ...`.
    private static func internalName(of parameter: String) -> String? {
        let head = parameter.components(separatedBy: " = ").first ?? parameter
        guard let colon = head.firstIndex(of: ":") else { return nil }
        return head[..<colon].split(separator: " ").last.map(String.init)
    }
}

extension String {
    /// `index(after:)` that stops at the end rather than trapping.
    ///
    /// Not named `formIndex(after:)` — the stdlib has one of those with a different shape,
    /// and the overload that compiled would have been chosen by argument label alone.
    fileprivate func indexAfter(_ index: Index) -> Index? {
        index < endIndex ? self.index(after: index) : nil
    }
}
