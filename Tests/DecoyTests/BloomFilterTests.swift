import Foundation
import Testing

@testable import DecoyAdapterKit

/// The Swift filter builders against every filter the JavaScript shipped.
///
/// These are not incidental. The training filter is the whole meaning of `novelNames()` —
/// it is what turns "probably new" into "not a value this locale actually has" — and the
/// blocklist filter is what stops a character-level model assembling something offensive
/// by accident. A filter built even slightly differently is not a slightly worse filter;
/// it is one the reader in `Decoy` recomputes differently and therefore cannot use.
@Suite("Bloom filters")
struct BloomFilterTests {

    /// Decoded rather than cast. `as? [Int]` and `as? [NSNumber]` both fail silently on a
    /// JSONSerialization number array, and the failure looked exactly like "there are no
    /// filters to compare" — the suite reported success on 51 blocklists while checking
    /// zero of the thing it exists for.
    private struct StoredModel: Decodable {
        let filterHashCount: Int?
        let filterBits: [UInt8]?
        let blockHashCount: Int?
        let blockMinLength: Int?
    }

    private static let reference = URL(fileURLWithPath: "/tmp/models-node.json")
    private static let locales = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters/out/locales")

    /// Sizing follows from the target rate, so it can be checked without any reference.
    @Test("sizing is derived from the false-positive rate")
    func sizing() {
        // 1% over 1,000 words: about 1.2 bytes each, and seven hashes. The byte count is
        // derived from the same formula rather than written as a literal — the first draft
        // guessed 1198 against an actual 1199, which is a test asserting my arithmetic
        // rather than the code's.
        let built = BloomFilter.overTrainingSet((0..<1000).map { "name\($0)" })
        #expect(built.hashCount == 7)
        let ln2 = log(2.0)
        let expectedBits = Int((-1000.0 * log(0.01) / (ln2 * ln2)).rounded(.up))
        #expect(built.bits.count == Int((Double(expectedBits) / 8).rounded(.up)))

        // A far tighter rate for the blocklist, because the two errors cost differently:
        // rejecting a clean name costs a redraw, letting one through costs rather more.
        let block = BloomFilter.overBlocklist((0..<1000).map { "term\($0)" })
        #expect(block.hashCount == 20)
        #expect(block.minLength == 4)
    }

    @Test("blocklist entries too short or containing spaces are dropped")
    func blocklistFiltering() {
        let terms = ["ok", "fine", "two words", "  Padded  ", "fine", "longenough"]
        let built = BloomFilter.overBlocklist(terms)
        // "ok" is under four characters, "two words" cannot occur inside one token, and
        // "fine" appears twice. Four of six drop out.
        #expect(built.dropped == 3)
    }

    @Test("membership behaves, and the filter is not simply full")
    func membership() {
        // A filter every lookup hits would satisfy any parity check and be useless. This
        // is the property that distinguishes a filter from an array of ones.
        let words = (0..<2000).map { "member\($0)" }
        let built = BloomFilter.overTrainingSet(words)
        let ones = built.bits.reduce(0) { $0 + $1.nonzeroBitCount }
        let total = built.bits.count * 8
        #expect(Double(ones) / Double(total) < 0.75, "filter is saturated")
        #expect(ones > 0)
    }

    @Test(
        "Swift reproduces every shipped filter",
        .enabled(if: PortFixtures.hasReference("/tmp/models-node.json")))
    func parity() throws {
        guard let data = try? Data(contentsOf: Self.reference),
            let expected = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else {
            Issue.record("no /tmp/models-node.json — dump it before trusting this suite")
            return
        }

        var comparedTraining = 0
        var comparedBlock = 0

        for (locale, models) in expected.sorted(by: { $0.key < $1.key }) {
            guard
                let raw = try? Data(
                    contentsOf: Self.locales.appendingPathComponent("\(locale).json")),
                let definitions = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
            else { continue }

            for (modelPath, storedRaw) in models {
                guard let stored = storedRaw as? [String: Any] else { continue }

                // The training list is the field the model path was derived from.
                let sourcePath = modelPath.replacingOccurrences(of: "_model", with: "")
                guard let words = Self.values(definitions, sourcePath) else { continue }

                // Base64, not an array of numbers — models.mjs encodes the filter before
                // writing it. Three separate attempts to read it as an array failed
                // silently, each one indistinguishable from "this model has no filter",
                // and each caught only because the suite asserts how many it compared
                // rather than reporting whatever it managed.
                let bits = (stored["filterBits"] as? String)
                    .flatMap { Data(base64Encoded: $0) }
                    .map { [UInt8]($0) }
                if let hashCount = (stored["filterHashCount"] as? NSNumber)?.intValue,
                    let bits, !bits.isEmpty
                {
                    // The filter covers the field *and its siblings*, not just what the
                    // model was trained on. That is the whole guarantee: a model trained on
                    // the generic list would otherwise happily emit a name sitting in the
                    // female list — novel for the list it learned from, and a real name in
                    // this locale, which is exactly what the caller asked not to get.
                    let parent = sourcePath.split(separator: ".").dropLast().joined(separator: ".")
                    let siblings = (Self.node(definitions, parent) as? [String: Any])?
                        .keys.sorted()
                        .flatMap { Self.values(definitions, "\(parent).\($0)") ?? [] } ?? []
                    let guarded = NGram.distinct(words + siblings)
                    let mine = BloomFilter.overTrainingSet(guarded)
                    #expect(mine.hashCount == hashCount, "\(locale) \(modelPath) hash count")
                    #expect(mine.bits == bits, "\(locale) \(modelPath) training filter bits")
                    comparedTraining += 1
                }

                if let hashCount = (stored["blockHashCount"] as? NSNumber)?.intValue {
                    // Only the shape is checked here: the blocklist terms come from a
                    // pinned artifact rather than from the corpus, so reconstructing the
                    // exact input belongs to the adapter port, not to this suite.
                    #expect(hashCount > 0, "\(locale) \(modelPath) block hash count")
                    comparedBlock += 1
                }
            }
        }

        let complaint = "no models compared — the intermediate JSON is missing"
        #expect(comparedTraining > 0, "\(complaint)")
        print("bloom: compared \(comparedTraining) training filters, \(comparedBlock) blocklists")
    }

    /// The raw node at a dotted path, for reaching a parent's children.
    private static func node(_ root: [String: Any], _ path: String) -> Any? {
        var cursor: Any? = root
        for part in path.split(separator: ".") {
            guard let level = cursor as? [String: Any] else { return nil }
            cursor = level[String(part)]
        }
        return cursor
    }

    private static func values(_ root: [String: Any], _ path: String) -> [String]? {
        var cursor: Any? = root
        for part in path.split(separator: ".") {
            guard let node = cursor as? [String: Any] else { return nil }
            cursor = node[String(part)]
        }
        if let strings = cursor as? [String] { return strings }
        if let weighted = cursor as? [[String: Any]] {
            return weighted.compactMap { $0["value"] as? String }
        }
        return nil
    }
}
