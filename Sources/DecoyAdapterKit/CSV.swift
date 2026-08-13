import Foundation

/// A CSV reader for the registry files several adapters pin.
///
/// Written out rather than split on commas, because the registries genuinely use the awkward
/// parts of the format: IANA's status descriptions contain commas, and its JOSE registry
/// quotes fields containing them, with doubled quotes for a literal one. Splitting naively
/// shifts every column after such a row — silently, since a shifted row still parses.
///
/// Blank rows are dropped, matching the pipeline this replaces. A trailing `\r` is stripped
/// so a CRLF file reads the same as an LF one, which matters because these are published by
/// registries with mixed conventions.
public enum CSV {

    /// Rows of fields, quotes resolved.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if quoted {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        // A doubled quote inside a quoted field is one literal quote.
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character.isNewline {
                // `isNewline`, not `== "\n"`. Swift's Character is a grapheme cluster and
                // CRLF is a single one, so on a CRLF file — which these registries are —
                // comparing against "\n" matches nothing at all. The parser saw no line
                // endings, returned the entire file as one row, and the header check passed
                // because the first two fields of that one row really are Value and
                // Description. It then found zero status codes in a file full of them.
                if field.hasSuffix("\r") { field.removeLast() }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        }
        return rows
    }
}
