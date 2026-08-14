import Testing

@testable import DecoyAdapterKit

/// The CSV reader, and specifically the line-ending case that keeps recurring.
@Suite("CSV")
struct CSVTests {

    /// CRLF, which is the fourth appearance of this fault line in one sitting.
    ///
    /// Swift's Character is an extended grapheme cluster and `\r\n` is a single one, so
    /// `character == "\n"` matches nothing in a CRLF file. The parser saw no line endings,
    /// returned the whole file as one row, and the caller's header check *passed* — the
    /// first two fields of that single row really were `Value` and `Description` — before
    /// reporting zero status codes in a registry full of them.
    ///
    /// The same cluster rule broke the Windows tests, renumbered the n-gram alphabet for
    /// every language with combining marks, and cost the emoji adapter a keycap. It is
    /// worth one dedicated test.
    @Test("line endings: LF, CRLF and CR all separate rows")
    func lineEndings() {
        let expected = [["Value", "Description"], ["100", "Continue"], ["200", "OK"]]
        #expect(CSV.parse("Value,Description\n100,Continue\n200,OK") == expected)
        #expect(CSV.parse("Value,Description\r\n100,Continue\r\n200,OK") == expected)
        #expect(CSV.parse("Value,Description\r100,Continue\r200,OK") == expected)
    }

    @Test("quoted fields keep their commas")
    func quoting() {
        // IANA quotes references containing commas; splitting on commas shifts every
        // column after such a row, and a shifted row still parses.
        let rows = CSV.parse("100,Continue,\"[RFC9110, Section 15.2.1]\"\n")
        #expect(rows == [["100", "Continue", "[RFC9110, Section 15.2.1]"]])
    }

    @Test("a doubled quote inside a quoted field is one literal quote")
    func escapedQuote() {
        #expect(CSV.parse("a,\"say \"\"hi\"\"\"") == [["a", "say \"hi\""]])
    }

    @Test("blank rows are dropped, trailing content is kept")
    func blanks() {
        #expect(CSV.parse("a,b\n\n\nc,d") == [["a", "b"], ["c", "d"]])
        // No trailing newline: the last row must still arrive.
        #expect(CSV.parse("a,b\nc,d") == [["a", "b"], ["c", "d"]])
    }

    /// The same fault line again, in the plain-text splitter the adapters share.
    ///
    /// This one only failed on Linux. Foundation's `components(separatedBy: "\n")` searches
    /// by UTF-16 code unit on Darwin and through a grapheme-aware path in
    /// swift-corelibs-foundation, so a CRLF register split into 46,000 lines on a Mac and
    /// into one on the Linux CI job — where the header check then reported that the schema
    /// had changed and quoted the entire file back as evidence.
    @Test("Lines.split behaves like split('\\n') on every ending")
    func splitting() {
        #expect(Lines.split("a\nb\nc") == ["a", "b", "c"])
        // The carriage return stays on the end of the line, exactly where JavaScript
        // leaves it, because the callers trim it themselves.
        #expect(Lines.split("a\r\nb\r\nc") == ["a\r", "b\r", "c"])
        // A bare CR is not a line ending to `split('\n')` and must not become one.
        #expect(Lines.split("a\rb") == ["a\rb"])
        // A trailing newline yields a trailing empty line, which callers skip on content.
        #expect(Lines.split("a\n") == ["a", ""])
        #expect(Lines.split("") == [""])
    }
}
