import Foundation

/// A canonical rendering of everything a pinned artifact *states*, as opposed to its bytes.
///
/// The byte pin answers "are these the bytes we recorded". That is the wrong question to
/// fail a build on, and three weeks of red Mondays said so: the CBS re-tagged a spreadsheet
/// in SharePoint and SIX added an attribute the adapter does not read. Neither changed a
/// generated value, both stopped the pipeline, and each cost an investigation that ended in
/// "nothing happened".
///
/// The right question has three answers, not two, and this type supplies the middle one:
///
/// - the **extracted data** moved — a corpus decision, enforced against `parity/`;
/// - everything the file states is **unchanged** and only the container's own metadata
///   differs — provably inconsequential, so the pipeline accepts it;
/// - the file states **something different** — stop, and say what.
///
/// A content view is deliberately *total*: it covers every value the document carries, not
/// the subset an adapter happens to read today. A new column, a new attribute, a changed
/// footnote, a row the filters currently drop — all of those move the content digest even
/// though no generated value changes. That is the point. The narrow "did our output change"
/// question is already answered downstream, and answering only that one here would mean
/// accepting changes nobody has looked at.
///
/// ## What is excluded, and why that list is short
///
/// Only container metadata, and only where the container is a zip of parts: `docProps/`
/// and `customXml/`, which hold the authoring system's own bookkeeping — taxonomy tags,
/// datastore GUIDs, revision counters. Those are what a CMS rewrites when somebody
/// re-files a document, and they cannot reach the corpus because no adapter opens them.
/// Everything else in the container, every worksheet and the shared-strings table
/// included, is covered.
///
/// ## Fail closed
///
/// `render` throws for a format with no view rather than returning something permissive.
/// An artifact whose format cannot be rendered keeps the old behaviour exactly — a byte
/// mismatch is fatal — which is why adding views one format at a time is safe. A file that
/// will not parse is also fatal, so the 247-byte "Request Rejected" page that `Integrity`
/// was built to catch can never be mistaken for an inconsequential change.
public enum ContentView {

    public enum Failure: Error, CustomStringConvertible {
        case unsupported(artifact: String, detail: String)
        case unreadable(artifact: String, detail: String)

        public var description: String {
            switch self {
            case .unsupported(let artifact, let detail):
                return "no content view for \(artifact): \(detail)"
            case .unreadable(let artifact, let detail):
                return "could not read \(artifact) as its declared format: \(detail)"
            }
        }
    }

    /// Which view a file gets, by what the descriptor says it is.
    ///
    /// Named and versioned, because the digest means nothing without the recipe that
    /// produced it: a change to a renderer has to invalidate the recorded digests rather
    /// than silently compare old values against new rules.
    public enum Kind: String, Sendable {
        case lines = "lines/v1"
        case json = "json/v1"
        case xml = "xml/v1"
        case zipContainer = "zip-container/v1"
    }

    public struct Rendering: Sendable {
        public let kind: Kind
        public let digest: String
        /// The canonical rendering itself. Kept beside the cache rather than committed, so a
        /// re-pin can diff two documents instead of comparing two digests.
        public let text: String
        /// A short, human-readable summary of the document's shape, for reports: the thing
        /// a reviewer compares at a glance before reading a diff.
        public let shape: String
    }

    /// The view for an artifact, or nil when this pipeline has none for it.
    public static func kind(for artifact: SourceDescriptor.Artifact) -> Kind? {
        // Archives are not rendered. Their members would each need a view of their own, and
        // every archive-backed upstream is pinned at a URL carrying its own version, so
        // none of them is in the class this exists to quieten.
        guard artifact.format == "file" else { return nil }
        let name = (artifact.filename ?? artifact.name).lowercased()
        if name.hasSuffix(".xlsx") || name.hasSuffix(".xlsm") { return .zipContainer }
        if name.hasSuffix(".json") { return .json }
        if name.hasSuffix(".xml") { return .xml }
        if name.hasSuffix(".txt") || name.hasSuffix(".csv") || name.hasSuffix(".tsv") {
            return .lines
        }
        return nil
    }

    /// The canonical rendering of `file`, by the view its descriptor implies.
    public static func render(
        _ file: URL, artifact: SourceDescriptor.Artifact, source: String
    ) throws -> Rendering {
        let label = "\(source)/\(artifact.name)"
        guard let kind = kind(for: artifact) else {
            throw Failure.unsupported(
                artifact: label,
                detail: artifact.format == "file"
                    ? "\(artifact.filename ?? artifact.name) is not one of txt, csv, tsv, json, "
                        + "xml, xlsx"
                    : "format '\(artifact.format ?? "tgz")' is an archive")
        }

        let data: Data
        do { data = try Data(contentsOf: file) } catch {
            throw Failure.unreadable(artifact: label, detail: "\(error)")
        }

        let canonical: String
        let shape: String
        switch kind {
        case .lines:
            let rendered = renderLines(
                [UInt8](data), ignoringLinesMatching: artifact.ignoreLinesMatching)
            canonical = rendered.text
            shape = "\(rendered.lines) lines"
        case .json:
            let rendered = try renderJSON([UInt8](data), label: label)
            canonical = rendered.text
            shape = rendered.shape
        case .xml:
            let rendered = try renderXML([UInt8](data), label: label)
            canonical = rendered.text
            shape = rendered.shape
        case .zipContainer:
            let rendered = try renderZipContainer(file, label: label)
            canonical = rendered.text
            shape = rendered.shape
        }

        return Rendering(
            kind: kind, digest: Integrity.digest([UInt8](canonical.utf8)), text: canonical,
            shape: shape)
    }

    // MARK: - Line-oriented text

    /// Lines, with the noise a publisher's export tooling varies freely removed.
    ///
    /// A BOM, CRLF against LF, trailing blanks at the end of a line or the end of a file:
    /// all of those change when somebody re-saves a file through a different tool and none
    /// of them can change a parsed value, because every adapter trims. `ignoreLinesMatching`
    /// is applied here too, so the view agrees with the byte pin about what the digest is
    /// not covering instead of having a second, different opinion.
    static func renderLines(_ bytes: [UInt8], ignoringLinesMatching pattern: String?)
        -> (text: String, lines: Int)
    {
        var scalars = String(decoding: bytes, as: UTF8.self)
        if scalars.hasPrefix("\u{FEFF}") { scalars.removeFirst() }
        let regex = pattern.flatMap { $0.isEmpty ? nil : try? Regex($0) }

        var kept: [String] = []
        for line in Lines.split(scalars) {
            var trimmed = line
            while trimmed.hasSuffix("\r") || trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") {
                trimmed.removeLast()
            }
            if let regex, (try? regex.firstMatch(in: trimmed)).flatMap({ $0 }) != nil {
                continue
            }
            kept.append(trimmed)
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        return (kept.joined(separator: "\n"), kept.count)
    }

    // MARK: - JSON

    /// JSON as a canonical token stream, with object keys sorted and number literals kept
    /// verbatim.
    ///
    /// Re-serialising through `JSONSerialization` would have been three lines, and would
    /// have made the digest depend on how a given platform's Foundation prints a `Double`.
    /// These digests are committed and compared on macOS, Linux and Windows, so `1.0e2`
    /// has to stay the characters the upstream wrote rather than becoming whatever the host
    /// thinks that number looks like.
    static func renderJSON(_ bytes: [UInt8], label: String) throws -> (text: String, shape: String)
    {
        var scanner = JSONScanner(String(decoding: bytes, as: UTF8.self))
        let value: JSONValue
        do { value = try scanner.parse() } catch {
            throw Failure.unreadable(artifact: label, detail: "\(error)")
        }
        var out = ""
        value.write(into: &out)
        return (out, value.shape)
    }

    /// Just enough JSON to canonicalise one: values keep their source text, objects sort.
    enum JSONValue {
        case null
        case bool(Bool)
        /// The literal as written, never re-formatted.
        case number(String)
        case string(String)
        case array([JSONValue])
        case object([(key: String, value: JSONValue)])

        func write(into out: inout String) {
            switch self {
            case .null: out += "null"
            case .bool(let flag): out += flag ? "true" : "false"
            case .number(let literal): out += literal
            case .string(let text): out += "\"\(text)\""
            case .array(let items):
                out += "["
                for (index, item) in items.enumerated() {
                    if index > 0 { out += "," }
                    item.write(into: &out)
                }
                out += "]"
            case .object(let pairs):
                out += "{"
                // Sorted by UTF-8 bytes, which is an ordering every platform agrees on,
                // unlike `<` on String with its locale-independent but collation-shaped
                // rules for anything outside ASCII.
                let sorted = pairs.sorted {
                    Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8))
                }
                for (index, pair) in sorted.enumerated() {
                    if index > 0 { out += "," }
                    out += "\"\(pair.key)\":"
                    pair.value.write(into: &out)
                }
                out += "}"
            }
        }

        var shape: String {
            switch self {
            case .array(let items): return "array of \(items.count)"
            case .object(let pairs): return "object with \(pairs.count) keys"
            default: return "scalar"
            }
        }
    }

    struct JSONScanner {
        enum Broken: Error, CustomStringConvertible {
            case unexpected(String, at: Int)
            var description: String {
                switch self {
                case .unexpected(let what, let offset):
                    return "unexpected \(what) at offset \(offset)"
                }
            }
        }

        private let scalars: [Character]
        private var index = 0

        init(_ text: String) { scalars = Array(text) }

        mutating func parse() throws -> JSONValue {
            let value = try value()
            skipWhitespace()
            guard index == scalars.count else {
                throw Broken.unexpected("trailing content", at: index)
            }
            return value
        }

        private mutating func skipWhitespace() {
            while index < scalars.count, scalars[index] == " " || scalars[index] == "\n"
                || scalars[index] == "\r" || scalars[index] == "\t"
            {
                index += 1
            }
        }

        private mutating func value() throws -> JSONValue {
            skipWhitespace()
            guard index < scalars.count else { throw Broken.unexpected("end of input", at: index) }
            switch scalars[index] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t", "f", "n": return try keyword()
            default: return try number()
            }
        }

        private mutating func object() throws -> JSONValue {
            index += 1  // {
            var pairs: [(key: String, value: JSONValue)] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard index < scalars.count, scalars[index] == "\"" else {
                    throw Broken.unexpected("object key", at: index)
                }
                let key = try string()
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else {
                    throw Broken.unexpected("':'", at: index)
                }
                index += 1
                pairs.append((key, try value()))
                skipWhitespace()
                guard index < scalars.count else {
                    throw Broken.unexpected("end of input", at: index)
                }
                if scalars[index] == "," {
                    index += 1
                    continue
                }
                if scalars[index] == "}" {
                    index += 1
                    return .object(pairs)
                }
                throw Broken.unexpected("'\(scalars[index])'", at: index)
            }
        }

        private mutating func array() throws -> JSONValue {
            index += 1  // [
            var items: [JSONValue] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try value())
                skipWhitespace()
                guard index < scalars.count else {
                    throw Broken.unexpected("end of input", at: index)
                }
                if scalars[index] == "," {
                    index += 1
                    continue
                }
                if scalars[index] == "]" {
                    index += 1
                    return .array(items)
                }
                throw Broken.unexpected("'\(scalars[index])'", at: index)
            }
        }

        /// The source text of a string, escapes left exactly as written.
        ///
        /// Unescaping would mean re-escaping to render, and two encoders that disagree about
        /// whether `/` or `é` needs a backslash would produce two different digests for one
        /// document.
        private mutating func string() throws -> String {
            index += 1  // opening quote
            var out = ""
            while index < scalars.count {
                let character = scalars[index]
                if character == "\\" {
                    guard index + 1 < scalars.count else {
                        throw Broken.unexpected("escape at end of input", at: index)
                    }
                    out.append(character)
                    out.append(scalars[index + 1])
                    index += 2
                    continue
                }
                if character == "\"" {
                    index += 1
                    return out
                }
                out.append(character)
                index += 1
            }
            throw Broken.unexpected("unterminated string", at: index)
        }

        private mutating func keyword() throws -> JSONValue {
            for (text, value) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)] {
                if scalars.count - index >= text.count,
                    String(scalars[index..<index + text.count]) == text
                {
                    index += text.count
                    return value
                }
            }
            throw Broken.unexpected("'\(scalars[index])'", at: index)
        }

        private mutating func number() throws -> JSONValue {
            let start = index
            while index < scalars.count, "0123456789+-.eE".contains(scalars[index]) {
                index += 1
            }
            guard index > start else { throw Broken.unexpected("'\(scalars[index])'", at: index) }
            return .number(String(scalars[start..<index]))
        }
    }

    // MARK: - XML

    /// XML as one line per node: elements with their attributes sorted, text collapsed.
    ///
    /// Attribute order and inter-element whitespace are both free for a serialiser to
    /// change and neither carries meaning, so they are normalised away. Everything that
    /// carries meaning is kept, including comments — a publisher who adds a note to the
    /// document said something, and this view's job is to notice that rather than to judge
    /// whether it matters.
    static func renderXML(_ bytes: [UInt8], label: String) throws -> (text: String, shape: String) {
        let text = String(decoding: bytes, as: UTF8.self)
        var out: [String] = []
        var elements = 0
        var index = text.startIndex

        while let open = text[index...].firstIndex(of: "<") {
            let between = text[index..<open]
            let collapsed = between.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !collapsed.isEmpty { out.append("T \(collapsed)") }

            guard let close = text[open...].firstIndex(of: ">") else {
                throw Failure.unreadable(artifact: label, detail: "unterminated tag")
            }
            let tag = String(text[text.index(after: open)..<close])
            if tag.hasPrefix("!--") {
                // Comments may legitimately contain '>' before their terminator.
                guard let end = text.range(of: "-->", range: open..<text.endIndex) else {
                    throw Failure.unreadable(artifact: label, detail: "unterminated comment")
                }
                let body = text[text.index(open, offsetBy: 4)..<end.lowerBound]
                out.append("C \(body.split(whereSeparator: \.isWhitespace).joined(separator: " "))")
                index = end.upperBound
                continue
            }
            out.append(renderTag(tag))
            if !tag.hasPrefix("/"), !tag.hasPrefix("?"), !tag.hasPrefix("!") { elements += 1 }
            index = text.index(after: close)
        }

        let trailing = text[index...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !trailing.isEmpty { out.append("T \(trailing)") }

        guard elements > 0 else {
            throw Failure.unreadable(artifact: label, detail: "no XML elements")
        }
        return (out.joined(separator: "\n"), "\(elements) elements")
    }

    /// One tag, as `E name attr=value …` with attributes in a stable order.
    static func renderTag(_ tag: String) -> String {
        var body = tag
        let selfClosing = body.hasSuffix("/")
        if selfClosing { body.removeLast() }
        if body.hasPrefix("/") { return "E/ \(body.dropFirst().trimmingCharacters(in: .whitespaces))" }

        let scanner = Array(body)
        var index = 0
        func skipWhitespace() {
            while index < scanner.count, scanner[index] == " " || scanner[index] == "\n"
                || scanner[index] == "\r" || scanner[index] == "\t"
            { index += 1 }
        }
        skipWhitespace()
        let nameStart = index
        while index < scanner.count, !" \n\r\t=".contains(scanner[index]) { index += 1 }
        let name = String(scanner[nameStart..<index])

        var attributes: [String] = []
        while index < scanner.count {
            skipWhitespace()
            guard index < scanner.count else { break }
            let keyStart = index
            while index < scanner.count, !" \n\r\t=".contains(scanner[index]) { index += 1 }
            let key = String(scanner[keyStart..<index])
            if key.isEmpty { break }
            skipWhitespace()
            guard index < scanner.count, scanner[index] == "=" else {
                attributes.append(key)
                continue
            }
            index += 1
            skipWhitespace()
            var value = ""
            if index < scanner.count, scanner[index] == "\"" || scanner[index] == "'" {
                let quote = scanner[index]
                index += 1
                while index < scanner.count, scanner[index] != quote {
                    value.append(scanner[index])
                    index += 1
                }
                if index < scanner.count { index += 1 }
            } else {
                while index < scanner.count, !" \n\r\t".contains(scanner[index]) {
                    value.append(scanner[index])
                    index += 1
                }
            }
            attributes.append("\(key)=\(value)")
        }

        attributes.sort { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        let prefix = selfClosing ? "E! " : "E "
        return ([prefix + name] + attributes).joined(separator: " ")
    }

    // MARK: - Zip containers

    /// Container metadata an authoring system rewrites on its own schedule.
    ///
    /// The enumerated scope of the one place this pipeline accepts a change without asking.
    /// Both directories hold the CMS's bookkeeping — content-type taxonomy terms, datastore
    /// GUIDs, revision counters — and no adapter opens either: a workbook reaches an adapter
    /// through `XLSX`, which reads `xl/workbook.xml`, `xl/worksheets/*` and
    /// `xl/sharedStrings.xml` and nothing else.
    static let containerMetadata = ["docProps/", "customXml/"]

    /// Every member of the container, by name, each digested under its own view.
    ///
    /// Entry order and per-entry timestamps are not covered, because a zip writer chooses
    /// both and neither is content. Names are, so a member appearing or disappearing shows.
    static func renderZipContainer(_ file: URL, label: String) throws
        -> (text: String, shape: String)
    {
        let members: [String]
        do { members = try Shell.zipListing(of: file.path) } catch {
            throw Failure.unreadable(artifact: label, detail: "could not list members: \(error)")
        }
        guard !members.isEmpty else {
            throw Failure.unreadable(artifact: label, detail: "not a zip container")
        }

        var lines: [String] = []
        var covered = 0
        for member in members.sorted() {
            if containerMetadata.contains(where: { member.hasPrefix($0) }) { continue }
            if member.hasSuffix("/") { continue }
            let (tool, arguments) = Shell.member(member, of: file.path)
            let result: (status: Int32, output: Data, stderr: String)
            do { result = try Shell.run(tool, arguments, captureOutput: true) } catch {
                throw Failure.unreadable(artifact: label, detail: "reading \(member): \(error)")
            }
            guard result.status == 0 else {
                throw Failure.unreadable(
                    artifact: label, detail: "reading \(member): \(result.stderr)")
            }
            // XML members go through the XML view so that a re-serialised part with the
            // same content compares equal; anything else is covered as raw bytes.
            let digest: String
            if member.lowercased().hasSuffix(".xml") || member.lowercased().hasSuffix(".rels") {
                digest = Integrity.digest(
                    [UInt8](try renderXML([UInt8](result.output), label: "\(label):\(member)").text.utf8))
            } else {
                digest = Integrity.digest([UInt8](result.output))
            }
            lines.append("\(member) \(digest)")
            covered += 1
        }

        guard covered > 0 else {
            throw Failure.unreadable(
                artifact: label, detail: "every member is container metadata")
        }
        return (lines.joined(separator: "\n"), "\(covered) members")
    }
}
