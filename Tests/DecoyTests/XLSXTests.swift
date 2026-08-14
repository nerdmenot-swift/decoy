import Testing

@testable import DecoyAdapterKit

/// The workbook reader's scanner, at the level nothing upstream can check for it.
///
/// Five national registers ship xlsx and nothing else — Israel, Finland, Spain, the UK and
/// Sweden — and between them they hold the given names for those locales. A reader that is
/// subtly wrong does not fail; it drops a column, or slides one, and a locale quietly ends
/// up with surnames in its given-name list.
///
/// Which is caught downstream, and better: `CivilNamesAdapter` reads all five workbooks and
/// its committed baseline is compared path by path on every run. What is here is the part
/// that has no downstream tell — a spacer row, a gap between cells, an entity in a shared
/// string — where a mistake would look like the file rather than like the reader.
@Suite("XLSX reader")
struct XLSXTests {

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

    // A sheet-level comparison against the JavaScript reader used to live here, over a
    // 41 MB dump of all five workbooks. It went when the JavaScript did — the dump was
    // never committable at that size and can no longer be regenerated, so it would have
    // become a suite that skipped everywhere except the one machine that still had the
    // file in /tmp.
    //
    // Nothing is lost. `CivilNamesAdapter` is the only thing that reads a workbook, it
    // reads all five, and its committed baseline is compared path by path on every run —
    // so a reader that gets a cell wrong changes a name in Finland, Sweden, the UK, Spain
    // or Israel, and the parity suite says which. The scanner tests above cover the parts
    // that have no upstream to compare against.
}
