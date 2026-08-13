import Foundation

/// A minimal reader for the one thing statistical offices keep publishing in: `.xlsx`.
///
/// Four national name registers ship a workbook and nothing else — Spain, Finland, Sweden
/// and the UK all publish Excel with no CSV beside it. Refusing the format means refusing
/// the registers.
///
/// ## What changed in the port
///
/// The JavaScript had to parse the ZIP container by hand: Node gives you raw inflate but
/// not zip, so `lib/xlsx.mjs` reads the central directory itself. Swift has neither, but it
/// already requires `unzip` to unpack pinned archives — so the container is handed to the
/// tool that is already a dependency, and about a hundred lines of central-directory
/// parsing simply do not need to exist. A hand-rolled DEFLATE would have been the
/// alternative, which is a great deal of risk for a build step.
///
/// The XML side is a scanner rather than the original's regexes. Same grammar, same
/// results — `XLSXTests` checks it against the real workbooks — but it does not depend on
/// lazy quantifiers behaving identically across two regex engines.
///
/// ## What it supports, and what it does not
///
/// Shared strings, inline strings, numbers and blank cells: what statistical publications
/// actually contain. Not formulas, date serials, or styles. A file needing more fails on a
/// missing value rather than quietly producing a wrong one.
public enum XLSX {

    public enum Failure: Error, CustomStringConvertible {
        case notReadable(path: String, detail: String)
        case missingMember(String, in: String)

        public var description: String {
            switch self {
            case .notReadable(let path, let detail):
                return "could not read \(path) as a workbook: \(detail)"
            case .missingMember(let member, let path):
                return "\(path) has no \(member) — not an xlsx, or one this cannot read"
            }
        }
    }

    // MARK: - Container

    /// A member's bytes, inflated by `unzip`.
    static func member(_ name: String, in workbook: URL) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["unzip", "-p", workbook.path, name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - XML scanning

    /// The bodies of every `<tag …>…</tag>`, and the attribute text of each opening tag.
    ///
    /// `selfClosing` is not a nicety, it is the difference between agreeing with the
    /// JavaScript and not. Its cell regex accepts `<c r="B7"/>` — a real cell that happens
    /// to be blank, and dropping it would slide the row — while its *row* regex requires a
    /// closing tag, so a `<row r="3" .../>` spacer row is skipped entirely.
    ///
    /// Treating both the same way inserted one empty row into three of the five real
    /// workbooks, which then shifted every later index and surfaced as two completely
    /// unrelated-looking cell mismatches further down the sheet.
    static func elements(_ tag: String, in xml: String, selfClosing: Bool = true)
        -> [(attributes: String, body: String)]
    {
        var found: [(String, String)] = []
        var index = xml.startIndex
        let open = "<\(tag)"
        let close = "</\(tag)>"

        while let start = xml.range(of: open, range: index..<xml.endIndex) {
            // `<row` must not match `<rowBreak`. The character after the name has to end it.
            let after = start.upperBound
            guard after < xml.endIndex else { break }
            let following = xml[after]
            guard following == " " || following == ">" || following == "/" else {
                index = after
                continue
            }
            guard let tagEnd = xml.range(of: ">", range: after..<xml.endIndex) else { break }
            let attributes = String(xml[after..<tagEnd.lowerBound])

            if attributes.hasSuffix("/") {
                if selfClosing { found.append((String(attributes.dropLast()), "")) }
                index = tagEnd.upperBound
                continue
            }
            guard let bodyEnd = xml.range(of: close, range: tagEnd.upperBound..<xml.endIndex)
            else { break }
            found.append((attributes, String(xml[tagEnd.upperBound..<bodyEnd.lowerBound])))
            index = bodyEnd.upperBound
        }
        return found
    }

    /// `name="value"` out of an opening tag's attribute text.
    static func attribute(_ name: String, in attributes: String) -> String? {
        var index = attributes.startIndex
        while let start = attributes.range(of: "\(name)=\"", range: index..<attributes.endIndex) {
            // Guard against `r:id` matching a search for `id`, and `foo:name` for `name`.
            let before =
                start.lowerBound == attributes.startIndex
                ? " " : attributes[attributes.index(before: start.lowerBound)]
            guard before == " " || before == "\"" else {
                index = start.upperBound
                continue
            }
            guard let end = attributes.range(of: "\"", range: start.upperBound..<attributes.endIndex)
            else { return nil }
            return String(attributes[start.upperBound..<end.lowerBound])
        }
        return nil
    }

    /// The five XML entities, plus numeric references, which appear in real name data.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&",
                let semicolon = text.range(of: ";", range: index..<text.endIndex),
                text.distance(from: index, to: semicolon.lowerBound) <= 10
            else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let entity = String(text[text.index(after: index)..<semicolon.lowerBound])
            switch entity {
            case "amp": out.append("&")
            case "lt": out.append("<")
            case "gt": out.append(">")
            case "quot": out.append("\"")
            case "apos": out.append("'")
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
                    let value = UInt32(entity.dropFirst(2), radix: 16),
                    let scalar = Unicode.Scalar(value)
                {
                    out.unicodeScalars.append(scalar)
                } else if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()),
                    let scalar = Unicode.Scalar(value)
                {
                    out.unicodeScalars.append(scalar)
                } else {
                    out.append(contentsOf: text[index...semicolon.lowerBound])
                }
            }
            index = semicolon.upperBound
        }
        return out
    }

    // MARK: - Workbook

    /// The shared string table, where most cell text actually lives.
    ///
    /// An entry can be split across several `<t>` runs when parts of it are formatted
    /// differently, so runs are joined rather than the first taken — `Mª DEL CARMEN`
    /// arrives in two runs in the Spanish file.
    static func sharedStrings(_ xml: String?) -> [String] {
        guard let xml else { return [] }
        return elements("si", in: xml).map { entry in
            decodeEntities(elements("t", in: entry.body).map(\.body).joined())
        }
    }

    /// `B7` -> (row 7, column 1), the column zero-based.
    static func position(of reference: String) -> (row: Int, column: Int)? {
        var letters = ""
        var digits = ""
        for character in reference {
            if character.isUppercase && character.isLetter && digits.isEmpty {
                letters.append(character)
            } else if character.isNumber {
                digits.append(character)
            } else {
                return nil
            }
        }
        guard !letters.isEmpty, let row = Int(digits) else { return nil }
        var column = 0
        for character in letters.unicodeScalars {
            column = column * 26 + Int(character.value) - 64
        }
        return (row, column - 1)
    }

    /// Sheet name to XML part, resolved through the workbook and its relationships.
    static func sheetParts(workbook: String?, relationships: String?) -> [(String, String)] {
        var targets: [String: String] = [:]
        for relationship in elements("Relationship", in: relationships ?? "") {
            guard let id = attribute("Id", in: relationship.attributes),
                var target = attribute("Target", in: relationship.attributes)
            else { continue }
            if target.hasPrefix("/xl/") { target = String(target.dropFirst(4)) }
            else if target.hasPrefix("xl/") { target = String(target.dropFirst(3)) }
            else if target.hasPrefix("/") { target = String(target.dropFirst()) }
            targets[id] = target
        }

        var parts: [(String, String)] = []
        for sheet in elements("sheet", in: workbook ?? "") {
            guard let name = attribute("name", in: sheet.attributes),
                let id = attribute("r:id", in: sheet.attributes),
                let target = targets[id]
            else { continue }
            parts.append((decodeEntities(name), "xl/\(target)"))
        }
        return parts
    }

    /// Reads a workbook into sheet name -> rows, each row an array of cell strings.
    ///
    /// Values come back as strings whatever the cell held, because every caller is about to
    /// parse them itself and a number that arrived as `1063756` is not more trustworthy for
    /// having passed through a float.
    public static func readWorkbook(at path: URL) throws -> [String: [[String]]] {
        let shared = sharedStrings(try member("xl/sharedStrings.xml", in: path))
        let parts = sheetParts(
            workbook: try member("xl/workbook.xml", in: path),
            relationships: try member("xl/_rels/workbook.xml.rels", in: path))
        guard !parts.isEmpty else {
            throw Failure.missingMember("xl/workbook.xml", in: path.lastPathComponent)
        }

        var sheets: [String: [[String]]] = [:]
        for (name, part) in parts {
            guard let xml = try member(part, in: path) else { continue }
            var rows: [[String]] = []

            // selfClosing: false — see `elements`. A spacer row has no closing tag and is
            // not a row.
            for row in elements("row", in: xml, selfClosing: false) {
                var cells: [Int: String] = [:]
                var appended: [String] = []
                var highest = -1

                for cell in elements("c", in: row.body) {
                    let reference = attribute("r", in: cell.attributes)
                    let spot = reference.flatMap { position(of: $0) }
                    let type = attribute("t", in: cell.attributes)

                    var value = ""
                    if !cell.body.isEmpty {
                        if type == "inlineStr" {
                            value = decodeEntities(
                                elements("t", in: cell.body).map(\.body).joined())
                        } else if let raw = elements("v", in: cell.body).first?.body {
                            value =
                                type == "s"
                                ? (Int(raw).flatMap { $0 < shared.count ? shared[$0] : nil } ?? "")
                                : decodeEntities(raw)
                        }
                    }

                    // Placed by its own column rather than appended: a sheet omits empty
                    // cells entirely, and appending would slide everything after a gap one
                    // column to the left.
                    if let spot {
                        cells[spot.column] = value
                        highest = max(highest, spot.column)
                    } else {
                        appended.append(value)
                    }
                }

                let assembled = highest >= 0 ? (0...highest).map { cells[$0] ?? "" } : []
                rows.append(assembled + appended)
            }
            sheets[name] = rows
        }
        return sheets
    }
}
