import Foundation
import Testing

@testable import DecoyAdapterKit

/// The renderers behind the one place this pipeline accepts a change without asking.
///
/// A content view decides whether a moved upstream stops the build. Too strict and the
/// weekly check goes back to crying wolf over a re-saved spreadsheet; too loose and it
/// waves through a changed value, which is the failure that actually matters. Both
/// directions are checked here, on the shapes the real upstreams produced: SIX adding an
/// attribute nobody reads, the CBS re-tagging a workbook in SharePoint, IANA retiring a
/// top-level domain.
@Suite("Content views")
struct ContentViewTests {

    // MARK: - Lines

    @Test("a re-saved text file renders identically")
    func linesIgnoreSerialisationNoise() {
        let unix = ContentView.renderLines(Array("AAA\nBBB\nCCC\n".utf8), ignoringLinesMatching: nil)
        let windows = ContentView.renderLines(
            Array("\u{FEFF}AAA\r\nBBB  \r\nCCC\r\n\r\n".utf8), ignoringLinesMatching: nil)
        // A BOM, CRLF, a trailing space and a trailing blank line: four things a publisher's
        // export tooling varies freely and none of which can change a parsed value.
        #expect(unix.text == windows.text)
        #expect(unix.lines == 3)
    }

    @Test("a retired entry does not")
    func linesNoticeAMissingValue() {
        let before = ContentView.renderLines(
            Array("JUMP\nJUNIPER\nJUSTICE\n".utf8), ignoringLinesMatching: nil)
        let after = ContentView.renderLines(Array("JUMP\nJUSTICE\n".utf8), ignoringLinesMatching: nil)
        #expect(before.text != after.text)
        #expect(after.lines == 2)
    }

    @Test("the ignored serial line is ignored, and only it")
    func linesHonourTheIgnorePattern() {
        let pattern = "^# Version"
        let monday = ContentView.renderLines(
            Array("# Version 2026081700\nAAA\nBBB\n".utf8), ignoringLinesMatching: pattern)
        let tuesday = ContentView.renderLines(
            Array("# Version 2026101000\nAAA\nBBB\n".utf8), ignoringLinesMatching: pattern)
        #expect(monday.text == tuesday.text)

        let moved = ContentView.renderLines(
            Array("# Version 2026101000\nAAA\n".utf8), ignoringLinesMatching: pattern)
        #expect(moved.text != monday.text)
    }

    // MARK: - JSON

    @Test("key order and whitespace are not content")
    func jsonCanonicalisesShape() throws {
        let one = try ContentView.renderJSON(Array(#"{"b":1,"a":[2,3]}"#.utf8), label: "t")
        let two = try ContentView.renderJSON(
            Array("{\n  \"a\" : [ 2, 3 ],\n  \"b\" : 1\n}".utf8), label: "t")
        #expect(one.text == two.text)
    }

    @Test("number literals are kept as written")
    func jsonKeepsLiterals() throws {
        // Re-serialising through Foundation would make this depend on how a given platform
        // prints a Double, and these digests are compared on three of them.
        let rendered = try ContentView.renderJSON(Array(#"{"mass":1.00794e0}"#.utf8), label: "t")
        #expect(rendered.text.contains("1.00794e0"))
    }

    @Test("a changed value is a changed document")
    func jsonNoticesAValue() throws {
        let before = try ContentView.renderJSON(Array(#"{"a":1}"#.utf8), label: "t")
        let after = try ContentView.renderJSON(Array(#"{"a":2}"#.utf8), label: "t")
        #expect(before.text != after.text)
    }

    @Test("a truncated document is refused, not rendered")
    func jsonFailsClosed() {
        // The 247-byte "Request Rejected" page that the byte pin was built to catch must
        // never reach a verdict of "inconsequential".
        #expect(throws: (any Error).self) {
            try ContentView.renderJSON(Array(#"{"a":"#.utf8), label: "t")
        }
    }

    // MARK: - XML

    @Test("attribute order and inter-element whitespace are not content")
    func xmlCanonicalisesShape() throws {
        let one = try ContentView.renderXML(
            Array(#"<r><e a="1" b="2">x</e></r>"#.utf8), label: "t")
        let two = try ContentView.renderXML(
            Array("<r>\n  <e b=\"2\" a=\"1\">x</e>\n</r>".utf8), label: "t")
        #expect(one.text == two.text)
    }

    @Test("an added attribute is content, even one nothing reads")
    func xmlNoticesAnAddedAttribute() throws {
        // SIX's republication, exactly: `IsFund="true"` on two of 280 entries. The adapter
        // reads only CcyNbr, so no generated value moved — and this still has to notice,
        // because "no adapter reads it today" is not the same as "it does not matter".
        let before = try ContentView.renderXML(
            Array("<l><CcyNm>Unidad Previsional</CcyNm></l>".utf8), label: "t")
        let after = try ContentView.renderXML(
            Array(#"<l><CcyNm IsFund="true">Unidad Previsional</CcyNm></l>"#.utf8), label: "t")
        #expect(before.text != after.text)
    }

    @Test("a comment is content too")
    func xmlKeepsComments() throws {
        let plain = try ContentView.renderXML(Array("<r><e>1</e></r>".utf8), label: "t")
        let annotated = try ContentView.renderXML(
            Array("<r><!-- superseded, see 2027 release --><e>1</e></r>".utf8), label: "t")
        #expect(plain.text != annotated.text)
    }

    @Test("something that is not XML is refused")
    func xmlFailsClosed() {
        #expect(throws: (any Error).self) {
            try ContentView.renderXML(Array("Request Rejected".utf8), label: "t")
        }
    }

    // MARK: - Which view, and whether there is one

    @Test("the view follows the declared format")
    func kindFollowsTheDescriptor() {
        func artifact(_ filename: String, format: String = "file") -> SourceDescriptor.Artifact {
            SourceDescriptor.Artifact(
                name: "a", format: format, filename: filename, url: "https://example.invalid/a",
                integrity: "sha512-x", ignoreLinesMatching: nil)
        }
        #expect(ContentView.kind(for: artifact("names.xlsx")) == .zipContainer)
        #expect(ContentView.kind(for: artifact("list-one.xml")) == .xml)
        #expect(ContentView.kind(for: artifact("table.json")) == .json)
        #expect(ContentView.kind(for: artifact("tlds.txt")) == .lines)
        #expect(ContentView.kind(for: artifact("frequencies.csv")) == .lines)
        // Fail closed: no view means a byte change stays fatal, which is where every
        // format started.
        #expect(ContentView.kind(for: artifact("apellidos.xls")) == nil)
        #expect(ContentView.kind(for: artifact("db.zip", format: "zip")) == nil)
    }

    @Test("only the authoring system's own directories are excluded")
    func containerScopeIsEnumerated() {
        // The whole of the deliberate loosening, in one assertion. Anything added to this
        // list is a decision to stop noticing a change, so the list is the test.
        #expect(ContentView.containerMetadata == ["docProps/", "customXml/"])
    }
}
