/// Splitting text into lines the way `String.prototype.split('\n')` does.
///
/// The third appearance of one bug, and the first that only shows on another platform.
///
/// Swift's `Character` is an extended grapheme cluster, and CRLF is a single one — so
/// `split(separator: "\n")` finds no line endings at all in a CRLF file. `CSV.parse` hit
/// that and answers it with `Character.isNewline`. Every adapter that reads a plain text
/// file reached instead for Foundation's `components(separatedBy: "\n")`, which searches by
/// UTF-16 code unit on Darwin and therefore worked.
///
/// It does not work on Linux. swift-corelibs-foundation resolves the same call through a
/// grapheme-aware search, so on the Linux CI job the Gender-by-Name register came back as
/// one line 46,000 names long, and the header check reported that the schema had changed
/// while quoting the entire file back at itself. Nine adapters were one CRLF upstream away
/// from the same failure, and the four that already read CRLF files only passed because
/// they happened to be tested on a Mac.
///
/// Splitting on unicode scalars sidesteps the whole question: a scalar `\n` is a scalar
/// `\n` on every platform, and `\r` stays on the end of the line where JavaScript leaves it
/// — which the callers already trim.
public enum Lines {

    /// Every line, keeping a trailing `\r` and a trailing empty line, as `split('\n')` does.
    public static func split(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        lines.append(String(current))
        return lines
    }
}
