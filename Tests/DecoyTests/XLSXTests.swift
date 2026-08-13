import Foundation
import Testing

@testable import DecoyAdapterKit

/// The Swift workbook reader against the JavaScript's reading of the same five files.
///
/// Five national registers ship xlsx and nothing else — Israel, Finland, Spain, the UK and
/// Sweden — and between them they hold the given names for those locales. A reader that is
/// subtly wrong does not fail; it drops a column, or slides one, and a locale quietly ends
/// up with surnames in its given-name list.
///
/// The comparison is against `/tmp/xlsx-node.json`, dumped from the JavaScript reader. When
/// that file is absent the suite says so rather than passing, because a silent skip here
/// would be the third such trap in this session.
@Suite("XLSX reader")
struct XLSXTests {

    private static let cache = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters/.cache")

    private static let reference = URL(fileURLWithPath: "/tmp/xlsx-node.json")

    @Test("shared strings, positions and entities")
    func primitives() {
        // Runs are joined: `Mª DEL CARMEN` arrives split in the Spanish file.
        let xml = "<si><t>Mª </t><t>DEL CARMEN</t></si><si><t>ANA</t></si>"
        #expect(XLSX.sharedStrings(xml) == ["Mª DEL CARMEN", "ANA"])

        #expect(XLSX.position(of: "B7")! == (row: 7, column: 1))
        #expect(XLSX.position(of: "A1")! == (row: 1, column: 0))
        #expect(XLSX.position(of: "AA2")! == (row: 2, column: 26))
        #expect(XLSX.position(of: "notaref") == nil)

        #expect(XLSX.decodeEntities("Ben &amp; Sons") == "Ben & Sons")
        #expect(XLSX.decodeEntities("a&lt;b&gt;c&quot;d&apos;e") == "a<b>c\"d'e")
        #expect(XLSX.decodeEntities("&#233;") == "é")
        #expect(XLSX.decodeEntities("&#x00e9;") == "é")
        // Nothing to decode must survive untouched, including a bare ampersand.
        #expect(XLSX.decodeEntities("plain") == "plain")
    }

    /// The tag scanner must not match a longer name that starts the same way.
    @Test("element scanning does not confuse prefixes")
    func prefixes() {
        let xml = "<rowBreak x=\"1\"/><row r=\"1\"><c r=\"A1\"><v>7</v></c></row>"
        let rows = XLSX.elements("row", in: xml)
        #expect(rows.count == 1)
        #expect(rows[0].body.contains("<v>7</v>"))

        // Likewise attributes: `r:id` must not answer a search for `id`.
        #expect(XLSX.attribute("id", in: "r:id=\"rId3\" name=\"x\"") == nil)
        #expect(XLSX.attribute("r:id", in: "r:id=\"rId3\" name=\"x\"") == "rId3")
    }

    /// A blank cell is omitted from the XML entirely, and must not slide the row.
    @Test("a gap in a row keeps later cells in their own columns")
    func gaps() throws {
        let sheet = """
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
            """
        var built: [String] = []
        for row in XLSX.elements("row", in: sheet) {
            var cells: [Int: String] = [:]
            var highest = -1
            for cell in XLSX.elements("c", in: row.body) {
                guard let reference = XLSX.attribute("r", in: cell.attributes),
                    let spot = XLSX.position(of: reference)
                else { continue }
                cells[spot.column] = XLSX.elements("v", in: cell.body).first?.body ?? ""
                highest = max(highest, spot.column)
            }
            built = (0...highest).map { cells[$0] ?? "" }
        }
        #expect(built == ["0", "", "1"], "the gap at B must survive as an empty cell")
    }

    @Test("every real workbook reads identically to the JavaScript")
    func realWorkbooks() throws {
        guard let data = try? Data(contentsOf: Self.reference),
            let expected = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record(
                "no /tmp/xlsx-node.json — dump it from lib/xlsx.mjs before trusting this suite")
            return
        }

        var compared = 0
        for (file, sheetsRaw) in expected {
            guard let expectedSheets = sheetsRaw as? [String: [[String]]] else { continue }
            let path = Self.cache.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }

            let actual = try XLSX.readWorkbook(at: path)
            #expect(
                Set(actual.keys) == Set(expectedSheets.keys),
                "\(file): sheet names differ")

            for (sheet, expectedRows) in expectedSheets {
                guard let actualRows = actual[sheet] else { continue }
                #expect(
                    actualRows.count == expectedRows.count,
                    "\(file)/\(sheet): \(actualRows.count) rows vs \(expectedRows.count)")

                for (index, pair) in zip(actualRows, expectedRows).enumerated()
                where pair.0 != pair.1 {
                    // One known divergence, and the JavaScript is the one that is wrong.
                    //
                    // Its cell pattern is `<c\b([^>]*)(?:\/>|>…<\/c>)`, and the alternation
                    // does not backtrack: for `<c r="A12"/>` the `[^>]*` swallows the
                    // slash, the `\/>` branch fails, the `>` branch succeeds, and the
                    // self-closing cell consumes the *next* cell. The value then lands in
                    // the wrong column with its shared-string lookup skipped — `23570`
                    // instead of `Miehet kaikki`.
                    //
                    // It survives only because it lands on `Saate`, the DVV cover note.
                    // The adapter reads `Miehet ens` and `Naiset ens`, so nothing wrong
                    // ever reaches the corpus. Named rather than tolerated: if this starts
                    // happening on a sheet that is read, the test says so.
                    if sheet == "Saate" { continue }
                    let mine = pair.0.prefix(6).joined(separator: "|")
                    let theirs = pair.1.prefix(6).joined(separator: "|")
                    Issue.record("\(file)/\(sheet) row \(index): [\(mine)] vs [\(theirs)]")
                    break
                }
                compared += 1
            }
        }
        let complaint = "no workbooks compared — the cache is empty or the dump is stale"
        #expect(compared > 0, "\(complaint)")
        print("xlsx: compared \(compared) sheets against the JavaScript reader")
    }
}
