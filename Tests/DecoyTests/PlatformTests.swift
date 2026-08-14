import Testing

@testable import DecoyAdapterKit

/// The places where the same code does something different on another platform.
///
/// Every one of these was found by CI rather than by reading, and each looked like a data
/// problem rather than a platform one: a register whose schema had apparently changed, a
/// missing archive tool on a machine that ships it. They are collected here because the
/// pattern is what matters — the corpus build runs on macOS, Linux and Windows, and a
/// difference that only shows on one of them is the kind nobody notices until it ships.
@Suite("Platform differences")
struct PlatformTests {

    /// Line splitting, in the plain-text reader the adapters share.
    ///
    /// The same fault line as `CSVTests.lineEndings`, and this one only failed on Linux. Foundation's `components(separatedBy: "\n")` searches
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

    /// The tools the corpus build shells out to have to be findable where it runs.
    ///
    /// Not a tautology on Windows, which is where this failed: the environment spells the
    /// variable `Path`, Swift's dictionary lookup is case-sensitive, and the build reported
    /// "`tar` is not installed" on a machine that ships tar in System32.
    @Test("the archive tools resolve on this platform")
    func toolsResolve() {
        #expect(!Shell.searchDirectories().isEmpty, "no search path at all")
        #expect(Shell.locate("tar") != nil, "tar is not findable")
        let (tool, _) = Shell.extraction(format: "zip", archive: "a.zip", into: "out")
        #expect(Shell.locate(tool) != nil, "\(tool) is not findable")
    }
}
