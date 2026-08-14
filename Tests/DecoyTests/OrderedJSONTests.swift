import Foundation
import Testing

@testable import DecoyAdapterKit

/// The reader and writer the query snapshots are kept in.
///
/// Both exist because `JSONSerialization` loses the order of an object's keys and indents
/// with two spaces. Those sound like preferences and are not: the four snapshots under
/// `Tools/adapters/data/` are committed to be *diffed by hand*, so a re-run that reorders
/// 8,688 names or reflows every line hides the actual change inside the noise.
@Suite("Ordered JSON")
struct OrderedJSONTests {

    // MARK: - Writing

    @Test("indents with one space, the way JSON.stringify(x, null, 1) does")
    func indentation() {
        let document = OrderedJSON.object([
            ("retrieved", .string("2026-08-09")),
            ("terms", .object([("sex", .array([.string("male"), .string("female")]))])),
        ])
        #expect(
            document.rendered == """
                {
                 "retrieved": "2026-08-09",
                 "terms": {
                  "sex": [
                   "male",
                   "female"
                  ]
                 }
                }
                """)
    }

    @Test("keeps the order it was given, not a sorted one")
    func ordering() {
        let document = OrderedJSON.object([
            ("zulu", .integer(1)), ("alpha", .integer(2)), ("mike", .integer(3)),
        ])
        #expect(document.rendered == "{\n \"zulu\": 1,\n \"alpha\": 2,\n \"mike\": 3\n}")
    }

    @Test("empty containers stay on one line")
    func empties() {
        #expect(OrderedJSON.object([]).rendered == "{}")
        #expect(OrderedJSON.array([]).rendered == "[]")
    }

    @Test("non-ASCII goes out as itself")
    func unicode() {
        // Five `\\u` escapes would be unreadable in the file this exists to make readable.
        #expect(OrderedJSON.string("אילול").rendered == "\"אילול\"")
        #expect(OrderedJSON.string("茶色").rendered == "\"茶色\"")
        #expect(OrderedJSON.string("a\"b\\c\nd").rendered == "\"a\\\"b\\\\c\\nd\"")
    }

    @Test("a whole number goes back as an integer")
    func wholeNumbers() {
        // JavaScript has one number type and writes `4`, not `4.0`, so every count in the
        // file would change shape otherwise.
        #expect(OrderedJSON.double(2353).rendered == "2353")
        #expect(OrderedJSON.double(2.5).rendered == "2.5")
    }

    // MARK: - Reading

    @Test("round-trips what it writes")
    func roundTrip() throws {
        let source = """
            {"a":[1,2.5,"x",true,false,null],"b":{"c":"\\u00e9\\ud83d\\ude00"}}
            """
        let parsed = try OrderedJSON.parse(Data(source.utf8))
        #expect(parsed["a"]?.asArray?.count == 6)
        #expect(parsed["b"]?["c"]?.asString == "é😀")
    }

    @Test("multi-byte text decodes as text, not as bytes")
    func multiByte() throws {
        // Decoded a run at a time rather than a byte at a time: a Hebrew letter is two
        // bytes, and decoding them singly yields replacement characters.
        let parsed = try OrderedJSON.parse(Data("{\"k\":\"שלום 茶色\"}".utf8))
        #expect(parsed["k"]?.asString == "שלום 茶色")
    }

    /// The ordering rule that cost two wrong answers before it was found.
    ///
    /// `Object.keys` lists integer-like keys first, ascending *numerically*, and only then
    /// everything else in insertion order. Slovenia's statistics office keys its names that
    /// way and lists them alphabetically in the document, so document order, `index` order
    /// and enumeration order are three different sequences over the same 8,688 names.
    @Test("integer-like keys enumerate numerically, ahead of the rest")
    func propertyOrder() throws {
        let parsed = try OrderedJSON.parse(
            Data("{\"3\":\"Aaron\",\"19\":\"Abas\",\"29413\":\"Abbas\",\"41\":\"Abdija\"}".utf8))
        #expect(parsed.asObject?.map(\.key) == ["3", "19", "29413", "41"])
        #expect(parsed.propertyOrder?.map(\.key) == ["3", "19", "41", "29413"])

        // Norway's codes are `1EMMA` and `2JAKOB`, which are not integer-like — so its half
        // of the same file keeps insertion order and hid the question entirely.
        let mixed = try OrderedJSON.parse(Data("{\"2JAKOB\":1,\"7\":2,\"1EMMA\":3}".utf8))
        #expect(mixed.propertyOrder?.map(\.key) == ["7", "2JAKOB", "1EMMA"])
    }

    @Test("what counts as an array index is the canonical decimal form only")
    func arrayIndices() {
        #expect(OrderedJSON.isArrayIndex("0"))
        #expect(OrderedJSON.isArrayIndex("29413"))
        #expect(!OrderedJSON.isArrayIndex("03"))
        #expect(!OrderedJSON.isArrayIndex("-1"))
        #expect(!OrderedJSON.isArrayIndex("3.0"))
        #expect(!OrderedJSON.isArrayIndex(""))
        #expect(!OrderedJSON.isArrayIndex("4294967295"))
    }
}
