import Foundation
import Testing

@testable import Decoy

/// Emits the vectors a second implementation of Decoy is checked against.
///
/// Decoy is being reimplemented in Go, and the first promise in the README — that a seed
/// produces the same rows — has to hold across both or it is not a promise. Swift is the
/// reference while that port happens, so the reference has to be able to state what it
/// does in a form another language can verify: not prose, and not literals hand-copied
/// into a second test suite, but the actual stream.
///
/// It lives in the test target rather than in a tool because the primitives it pins are
/// deliberately internal. `draw(below:)` and `drawUnitInterval()` are how this library
/// consumes randomness, not API anybody should call, and widening the public surface of a
/// library in order to port it away would be the wrong trade.
///
/// Off by default: it writes a file, which a test has no business doing unasked. Run it
/// when the corpus or a draw primitive has deliberately changed:
///
///     DECOY_WRITE_VECTORS=/path/to/vectors.json swift test --filter ParityVectors
///
/// Each section pins one layer, so a failure in the Go suite says which layer moved: the
/// generator, the primitives built on it, the reader, fallback resolution, or a whole
/// weighted draw, which composes all of them.
@Suite("Parity vectors", .enabled(if: RealCorpus.isAvailable))
struct ParityVectorsTests {

    /// Chains written out rather than derived, so the vectors do not depend on the rule
    /// the other implementation is being checked against.
    static let chains: [(code: String, chain: [String])] = [
        ("base", ["base"]),
        ("en", ["en", "base"]),
        ("de", ["de", "en", "base"]),
        ("ja", ["ja", "en", "base"]),
        // Devanagari, for one reason: Swift counts a string in grapheme clusters and Go
        // has no grapheme segmentation in its standard library. A model's length filter
        // is a character count, so `क` plus a vowel sign is where the two would disagree
        // about whether a candidate is too long. Better to find that here than in
        // somebody's fixtures.
        ("hi_IN", ["hi_IN", "en", "base"]),
    ]

    /// The model-backed paths. Names are the reason models exist.
    static let modelPaths = [
        "person.first_name_model.female",
        "person.first_name_model.male",
        "person.last_name_model.generic",
    ]

    /// The locales a generator can be asked for.
    ///
    /// `base` is excluded: it is the root of every chain and carries the shared,
    /// language-neutral data, not a language's own. Asking it for a given name traps, and
    /// rightly — a caller who reaches `base` directly has no locale at all.
    static var generatorChains: [(code: String, chain: [String])] {
        chains.filter { $0.code != "base" }
    }

    /// The generator surface, one entry per function and argument worth pinning.
    ///
    /// Written out rather than discovered, because the point is to pin a *named* function:
    /// `person.firstName(.female)` is a different promise from `person.firstName()`, and a
    /// reflective sweep would pin neither by name.
    ///
    /// Values are taken with novel names off and then on, in that order, so a port cannot
    /// pass by implementing only the list path.
    static let generatorCases: [(name: String, body: @Sendable (inout Faker) -> String)] = [
        ("person.firstName", { $0.person.firstName() }),
        ("person.firstName(female)", { $0.person.firstName(.female) }),
        ("person.firstName(male)", { $0.person.firstName(.male) }),
        ("person.middleName", { $0.person.middleName() }),
        ("person.lastName", { $0.person.lastName() }),
        ("person.novelLastName", { $0.person.novelLastName() }),
        ("person.prefix", { $0.person.prefix() }),
        ("person.prefix(female)", { $0.person.prefix(.female) }),
        ("person.prefix(male)", { $0.person.prefix(.male) }),
        ("person.suffix", { $0.person.suffix() }),
    ]

    /// Paths chosen to reach every storage layout, weighted and unweighted.
    static let paths = [
        "person.first_name.female",
        "person.first_name.male",
        "person.last_name.generic",
        "person.prefix.generic",
        "location.city_name",
        "location.street_name",
        "internet.domain_suffix",
        "internet.jwt_algorithm",
        "color.space",
        "database.collation",
    ]

    @Test("vectors describe this implementation, and are written when asked")
    func vectors() throws {
        var out: [String: Any] = [:]

        // The generator itself.
        out["rng"] = [0, 1, 1337, 42, UInt64.max].map { seed -> [String: Any] in
            var rng = Xoshiro256StarStar(seed: seed)
            return ["seed": String(seed), "values": (0..<16).map { _ in String(rng.next()) }]
        }

        // The primitives built on it. A correct generator consumed differently still
        // produces different fixtures, and Lemire's rejection is the easy one to get
        // subtly wrong.
        var below: [[String: Any]] = []
        for bound: UInt64 in [1, 2, 3, 7, 10, 100, 1_438, 1 << 32, UInt64.max / 3] {
            var rng = Xoshiro256StarStar(seed: 1337)
            below.append([
                "bound": String(bound),
                "values": (0..<32).map { _ in String(rng.draw(below: bound)) },
            ])
        }

        var unitRNG = Xoshiro256StarStar(seed: 1337)
        // Seventeen significant digits round-trip a Double exactly, so a reader parsing
        // these back gets the bits the generator produced.
        let unit = (0..<16).map { _ in String(format: "%.17g", unitRNG.drawUnitInterval()) }

        var closed: [[String: Any]] = []
        for range in [0...0, 0...1, 1...6, -5...5, 0...999] {
            var rng = Xoshiro256StarStar(seed: 1337)
            closed.append([
                "lower": range.lowerBound, "upper": range.upperBound,
                "values": (0..<16).map { _ in rng.draw(in: range) },
            ])
        }

        var chance: [[String: Any]] = []
        for probability in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var rng = Xoshiro256StarStar(seed: 1337)
            chance.append([
                "probability": probability,
                "values": (0..<16).map { _ in rng.drawChance(probability) },
            ])
        }
        out["draws"] = ["below": below, "unit": unit, "closed": closed, "chance": chance]

        // The reader, as the fully resolved contents of real tables: the arena walk, run
        // decoding and the weight column checked against values rather than a count.
        var tables: [[String: Any]] = []
        for (code, chain) in Self.chains {
            let locale = try RealCorpus.locale(code, chain: chain)
            for path in Self.paths {
                guard let table = locale.strings(path) else {
                    tables.append(["locale": code, "path": path, "present": false])
                    continue
                }
                var entries: [String] = []
                var weights: [Int] = []
                for index in 0..<table.count {
                    entries.append((try table.string(at: index)) ?? "")
                    weights.append(Int(try table.weight(at: index)))
                }
                tables.append([
                    "locale": code, "path": path, "present": true,
                    "count": table.count, "hasWeights": table.hasWeights,
                    "entries": entries, "weights": weights,
                ])
            }
        }
        out["tables"] = tables

        // Composite rows, which exist so that a drawn country is a country that exists.
        var composites: [[String: Any]] = []
        let english = try RealCorpus.locale("en", chain: ["en", "base"])
        for path in ["location.country", "science.chemical_element", "commerce.product"] {
            guard let table = english.composite(path) else {
                composites.append(["path": path, "present": false])
                continue
            }
            var rows: [[String]] = []
            for row in 0..<table.rowCount {
                rows.append(try (0..<table.fieldCount).map { try table.value(row: row, field: $0) })
            }
            composites.append([
                "path": path, "present": true, "fieldCount": table.fieldCount,
                "rowCount": table.rowCount,
                "fields": try (0..<table.fieldCount).map { try table.fieldName($0) },
                "rows": rows,
            ])
        }
        out["composites"] = composites

        // Whole draws, which compose every layer above.
        var draws: [[String: Any]] = []
        for (code, chain) in Self.chains {
            let locale = try RealCorpus.locale(code, chain: chain)
            for path in Self.paths {
                guard let table = locale.strings(path) else { continue }
                var rng = Xoshiro256StarStar(seed: 1337)
                let values = try (0..<12).map { _ in (try table.draw(using: &rng)) ?? "" }
                draws.append(["locale": code, "path": path, "seed": "1337", "values": values])
            }
        }
        out["weightedDraws"] = draws

        // Which locale in the chain answered, which is the rule a `kind == 0` entry
        // exists to interrupt: Azerbaijani has no name prefixes, and English must not
        // fill that gap.
        var fallback: [[String: Any]] = []
        for (code, chain) in Self.chains {
            for path in Self.paths {
                var answered = "none"
                for link in chain {
                    let single = LocaleCorpus(code: link, chain: [try RealCorpus.corpus(link)])
                    if single.declaresEmpty(path) {
                        answered = "\(link):empty"
                        break
                    }
                    if single.has(path) {
                        answered = link
                        break
                    }
                }
                fallback.append(["locale": code, "path": path, "answered": answered])
            }
        }
        out["fallback"] = fallback

        // The n-gram models: their shape, their filters, and what they generate.
        //
        // A model is where the most can go wrong in a port — the backoff, the cumulative
        // search, the packed context key, and one full 64-bit draw consumed per symbol —
        // and where a divergence is least visible, because both sides produce plausible
        // names either way.
        var models: [[String: Any]] = []
        for (code, chain) in Self.chains {
            let locale = try RealCorpus.locale(code, chain: chain)
            for path in Self.modelPaths {
                guard case .model(let model)? = locale.resolve(path) else {
                    models.append(["locale": code, "path": path, "present": false])
                    continue
                }
                var faker = Faker(seed: 1337, locale: locale)
                let values = (0..<12).map { _ in faker.drawModel(path) ?? "" }

                // Probes against both filters, so a port can check them without having to
                // generate a colliding candidate by luck. Drawn values are included
                // because a value the model just produced must *not* be in the training
                // set — that is the guarantee the filter exists to make.
                let probes = values.prefix(4) + ["Smith", "Müller", "", "aaaaaaaa"]
                models.append([
                    "locale": code, "path": path, "present": true,
                    "order": model.order, "minLength": model.minLength,
                    "maxLength": model.maxLength, "alphabetCount": model.alphabetCount,
                    "contextCount": model.contextCount,
                    "filterHashCount": model.filterHashCount,
                    "filterByteCount": model.filterByteCount,
                    "blockHashCount": model.blockHashCount,
                    "blockMinLength": model.blockMinLength,
                    "blockByteCount": model.blockByteCount,
                    "values": values,
                    "probes": probes.map { probe in
                        [
                            "word": probe,
                            "trained": model.wasTrainedOn(probe),
                            "blocked": model.isBlocked(probe),
                        ] as [String: Any]
                    },
                ])
            }
        }
        out["models"] = models

        // The generators themselves, which is what a caller actually touches.
        //
        // Each entry gets a *fresh* faker, deliberately. Sharing one across a list would
        // make every vector depend on the order the list happens to be in, so adding a
        // function tomorrow would rewrite the expected values of every function after it
        // and the port would be chasing its own tail. Keyed by name, independent by
        // construction.
        var generators: [[String: Any]] = []
        for (code, chain) in Self.generatorChains {
            let locale = try RealCorpus.locale(code, chain: chain)
            for (name, body) in Self.generatorCases {
                var values: [String] = []
                for novel in [false, true] {
                    var faker = Faker(seed: 1337, locale: locale, novelNames: novel)
                    values.append(contentsOf: (0..<8).map { _ in body(&faker) })
                }
                generators.append(["locale": code, "name": name, "values": values])
            }
        }
        out["generators"] = generators

        out["_comment"] = [
            "Parity vectors for a second implementation of Decoy, generated by the Swift",
            "one, which is the reference. UInt64 values are strings so a JSON reader whose",
            "numbers are doubles cannot quietly drop bits.",
            "",
            "A diff here means the implementations have diverged, or that a deliberate",
            "corpus change needs these regenerated -- never that a failing test elsewhere",
            "should be relaxed.",
        ]

        // Always computed, so this suite fails if the reference itself breaks; written
        // only when asked.
        #expect(tables.contains { ($0["present"] as? Bool) == true })
        #expect(draws.count > 20)
        #expect(models.contains { ($0["present"] as? Bool) == true })
        #expect(generators.count == Self.generatorChains.count * Self.generatorCases.count)

        guard let destination = ProcessInfo.processInfo.environment["DECOY_WRITE_VECTORS"] else {
            return
        }
        let data = try JSONSerialization.data(
            withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: destination))
        print("wrote \(data.count) bytes of vectors to \(destination)")
    }
}
