import Foundation
import Testing

@testable import DecoyAdapterKit

/// The Swift trainer against the models the JavaScript actually produced.
///
/// This is the test the whole n-gram port rests on. These models are what `novelNames()`
/// draws from and they are baked into the corpus, so a trainer that is *nearly* right
/// changes the names people generate while every other check stays green — no error, no
/// crash, just different output than the day before.
///
/// Comparing against the committed intermediate JSON rather than against a fixture is
/// deliberate: the fixture would be something I wrote, and the thing that has to be
/// reproduced is what shipped.
@Suite("N-gram trainer parity", .enabled(if: PortFixtures.hasIntermediateJSON))
struct NGramParityTests {

    private static let out = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters/out/locales")

    /// The trained models the JavaScript emitted, as the JSON carries them.
    private struct StoredModel: Decodable {
        struct Transition: Decodable {
            let symbol: Int
            let weight: Int
        }
        struct Context: Decodable {
            let key: String
            let transitions: [Transition]
        }
        let order: Int
        let alphabet: [String]
        let contexts: [Context]
        let minLength: Int
        let maxLength: Int
    }

    private struct WeightedValue: Decodable {
        let value: String
    }

    private static func json(_ locale: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: out.appendingPathComponent("\(locale).json")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func at(_ root: [String: Any], _ path: String) -> Any? {
        var current: Any? = root
        for key in path.split(separator: ".") {
            guard let node = current as? [String: Any] else { return nil }
            current = node[String(key)]
        }
        return current
    }

    /// The training input: the raw list, duplicates and order intact, because `train`
    /// dedups internally and the surviving order sets the alphabet.
    private static func values(_ root: [String: Any], _ path: String) -> [String]? {
        guard let raw = at(root, path) else { return nil }
        if let strings = raw as? [String] { return strings }
        if let weighted = raw as? [[String: Any]] {
            return weighted.compactMap { $0["value"] as? String }
        }
        return nil
    }

    private static func stored(_ root: [String: Any], _ path: String) -> StoredModel? {
        guard let raw = at(root, path + ".__model"),
            let data = try? JSONSerialization.data(withJSONObject: raw)
        else { return nil }
        return try? JSONDecoder().decode(StoredModel.self, from: data)
    }

    /// Every field the pipeline models, as `Models.modelledFields` lists them.
    private static let modelled = [
        ("person.first_name.female", "person.first_name_model.female"),
        ("person.first_name.male", "person.first_name_model.male"),
        ("person.first_name.generic", "person.first_name_model.generic"),
        ("person.last_name.generic", "person.last_name_model.generic"),
        ("person.last_name.female", "person.last_name_model.female"),
        ("person.last_name.male", "person.last_name_model.male"),
    ]

    @Test("Swift reproduces every model the JavaScript trained")
    func parity() throws {
        var compared = 0
        let locales = ["en", "de", "ja", "fr", "es", "it", "ru", "pl", "tr", "nl", "sv", "cs_CZ"]

        for locale in locales {
            guard let root = Self.json(locale) else { continue }
            for (from, to) in Self.modelled {
                guard let words = Self.values(root, from), let expected = Self.stored(root, to)
                else { continue }

                let actual = try NGram.train(words)
                compared += 1
                let where_ = "\(locale) \(to)"

                #expect(actual.order == expected.order, "\(where_): order")
                #expect(actual.alphabet == expected.alphabet, "\(where_): alphabet")
                #expect(actual.minLength == expected.minLength, "\(where_): minLength")
                #expect(actual.maxLength == expected.maxLength, "\(where_): maxLength")
                #expect(
                    actual.contexts.count == expected.contexts.count,
                    "\(where_): \(actual.contexts.count) contexts vs \(expected.contexts.count)")

                // Contexts in order, keys and every transition. A model can agree on shape
                // and disagree on a single weight, and that single weight is a different
                // name somewhere.
                for (index, pair) in zip(actual.contexts, expected.contexts).enumerated() {
                    let (mine, theirs) = pair
                    guard String(mine.key) == theirs.key else {
                        Issue.record("\(where_): context \(index) key \(mine.key) vs \(theirs.key)")
                        break
                    }
                    guard mine.transitions.count == theirs.transitions.count else {
                        Issue.record("\(where_): context \(index) transition count")
                        break
                    }
                    for (a, b) in zip(mine.transitions, theirs.transitions)
                    where a.symbol != b.symbol || a.weight != b.weight {
                        let mineDesc = "(\(a.symbol),\(a.weight))"
                        let theirsDesc = "(\(b.symbol),\(b.weight))"
                        Issue.record(
                            "\(where_): context \(index) transition \(mineDesc) vs \(theirsDesc)")
                        break
                    }
                }
            }
        }

        // Without this the suite passes on a fresh clone having compared nothing, which is
        // the failure mode this session has already been caught by more than once.
        let complaint = "no intermediate JSON — run the pipeline before trusting this"
        #expect(compared > 0, "\(complaint)")
        print("ngram parity: compared \(compared) trained models")
    }

    /// Insertion-ordered dedup is load-bearing, not tidiness.
    @Test("dedup preserves first-appearance order")
    func dedupOrder() {
        let input = ["beta", "alpha", "beta", "gamma", "alpha"]
        #expect(NGram.distinct(input) == ["beta", "alpha", "gamma"])

        // The consequence in practice: the alphabet follows the surviving order, so a
        // Set-based dedup would renumber every symbol and change every packed context key.
        let forwards = (0..<200).map { "zeta\($0)beta" }
        let backwards: [String] = forwards.reversed()
        let a = try! NGram.train(forwards, order: 3, minCount: 1)
        let b = try! NGram.train(backwards, order: 3, minCount: 1)
        let note = "alphabet order must depend on input order, or this precaution is moot"
        #expect(a.alphabet != b.alphabet, "\(note)")
    }

    @Test("order and pruning thresholds match the JavaScript's rules")
    func thresholds() {
        #expect(NGram.orderFor(count: 99) == nil)
        #expect(NGram.orderFor(count: 100, typicalLength: 10) == 3)
        #expect(NGram.orderFor(count: 5001, typicalLength: 10) == 4)
        // Japanese given names are two characters: the cap that stopped the context
        // spanning an entire name and generating nothing at all.
        #expect(NGram.orderFor(count: 10000, typicalLength: 2) == 2)
        #expect(NGram.minCountFor(5000) == 1)
        #expect(NGram.minCountFor(5001) == 2)
    }
}
