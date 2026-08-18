import Foundation
import Testing

@testable import DecoyAdapterKit

/// The legacy `.xls` reader, against a workbook no other tool here can open.
///
/// Spain's national surname register is the only reason this format is supported: 27,666
/// surnames with population counts, published as BIFF8 inside an OLE2 container and in no
/// other form. The parts that go wrong in a binary format go wrong silently — a
/// misdecoded RK is a plausible number, a mishandled CONTINUE is mojibake from the
/// boundary onwards — so the checks here are on known values rather than on shape.
@Suite("XLS reader", .enabled(if: PortFixtures.hasArtifactCache))
struct XLSTests {

    private static var workbook: URL {
        PortFixtures.adapters.appendingPathComponent(".cache/ine-apellidos-apellidos.xls")
    }

    @Test("RK decoding covers all four encodings")
    func rkEncodings() {
        // Bit 1 set: a signed 30-bit integer in the top bits.
        #expect(XLS.decodeRK(UInt32(1_000) << 2 | 2) == 1000)
        // Bit 0 as well: the same integer, divided by a hundred.
        #expect(XLS.decodeRK(UInt32(1_050) << 2 | 3) == 10.5)
        // Negative, which needs the sign extended from thirty bits rather than thirty-two.
        #expect(XLS.decodeRK(UInt32(bitPattern: Int32(-5)) << 2 | 2) == -5)
        // Bit 1 clear: the top thirty bits of an IEEE double, the rest zeroed.
        let double = Double(bitPattern: UInt64(0x4059_0000) << 32)  // 100.0
        #expect(XLS.decodeRK(0x4059_0000) == double)
    }

    @Test("whole numbers lose the decimal point, as XLSX's do")
    func numberFormatting() {
        #expect(XLS.format(1_446_937) == "1446937")
        #expect(XLS.format(10.5) == "10.5")
        #expect(XLS.format(.nan).isEmpty)
    }

    @Test("the real workbook reads with its strings and counts intact")
    func realWorkbook() throws {
        guard FileManager.default.fileExists(atPath: Self.workbook.path) else { return }
        let sheets = try XLS.readWorkbook(at: Self.workbook)

        // Two sheets, split by how many people hold the surname.
        #expect(sheets.count == 2, "expected two sheets, got \(sheets.keys.sorted())")
        let frequent = try #require(sheets["Apellidos >=100"])
        #expect(frequent.count == 27_666, "expected 27,666 rows, got \(frequent.count)")

        // Checked against the file as INE publishes it, and found by name rather than by
        // counting off the header — the sheet opens with three title lines and two header
        // rows, and pinning that number tests the wrong thing.
        //
        // A CONTINUE mishandled anywhere before this corrupts the string; an RK misdecoded
        // changes the count. Both are silent.
        let garcia = try #require(frequent.first { $0.count > 6 && $0[1] == "GARCIA" })
        #expect(garcia[2] == "1446937", "first-surname count")
        #expect(garcia[6] == "1468824", "combined count")

        // A string from deep in the table, past many CONTINUE boundaries, and one carrying
        // a character that only survives if the wide/compressed flag is re-read at each.
        let names = frequent.compactMap { $0.count > 1 ? $0[1] : nil }
        #expect(names.contains("RODRIGUEZ"))

        // INE withholds the combined figure for thirteen rare surnames by writing
        // 9,999,999 — a number, so it parses, and sorting by it once made ADEEL the
        // commonest surname in Spain ahead of GARCIA.
        let adeel = try #require(frequent.first { $0.count > 6 && $0[1] == "ADEEL" })
        #expect(adeel[6] == "9999999", "the sentinel is still how INE masks a small count")
        #expect(names.contains { $0.contains("Ñ") || $0.contains("ñ") },
                "no surname with an eñe — the encoding flag is being read once, not per segment")
    }
}
