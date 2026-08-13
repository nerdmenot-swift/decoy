import Foundation

/// Programming languages and their file extensions, from GitHub's Linguist.
///
/// Fills:
///   base    system.programming_language
///
/// ## Reading a JavaScript package without JavaScript
///
/// `linguist-languages` ships one ES module per language — `export default { name: 'Swift',
/// type: 'programming', extensions: ['.swift'], color: '#F05138' }` — re-exported from
/// `index.js` by display name. The Node adapter simply imported it, and its comment was
/// right that importing beats parsing *there*: the runtime does the work and a change of
/// layout fails at import rather than silently matching nothing.
///
/// Swift has no such option, so this reads the four fields it needs out of a shape that is
/// machine-generated and therefore extremely regular. It is not a JavaScript parser and
/// must not be mistaken for one; it is a reader for files a generator emits, and it fails
/// loudly on a count that has moved rather than quietly returning fewer languages.
///
/// The alternative considered was re-pinning to Linguist's own `languages.yml`, which is
/// the genuine upstream rather than a republished derivative. That is the better source and
/// a worse change to make in the middle of a port: it moves provenance, needs a new hash
/// and a licence check, and trades this reader for a YAML one.
public struct ProgrammingLanguagesAdapter: Adapter {
    public static let id = "programming-languages"
    public static let sources = ["linguist"]

    public init() {}

    /// One `key: value` out of an object literal, for the small set of shapes emitted here.
    ///
    /// Values are single-quoted strings, arrays of them, or bare numbers. Nothing nests, no
    /// key is quoted, and no string in this data contains an escaped quote — all of which
    /// is true of the generator's output and none of which is true of JavaScript at large.
    static func field(_ name: String, in source: String) -> String? {
        guard let start = source.range(of: "\n  \(name): ") else { return nil }
        let rest = source[start.upperBound...]

        // An array may be wrapped across lines when it is long — 30 of the 500-odd files
        // do this, C++ among them. Reading to the first newline dropped seventeen
        // languages, and it dropped them into the `withoutExtension` bucket, so the run
        // reported a plausible count and a plausible reason for the shortfall.
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            return String(rest[rest.startIndex...close])
        }

        guard let end = rest.firstIndex(of: "\n") else { return nil }
        var value = String(rest[rest.startIndex..<end])
        if value.hasSuffix(",") { value.removeLast() }
        return value
    }

    /// Either quote style.
    ///
    /// The generator emits single quotes until the string contains an apostrophe, at which
    /// point it switches to double — `name: "Cap'n Proto"`. Handling only single quotes
    /// lost exactly the two languages with an apostrophe in their name, Cap'n Proto and
    /// Ren'Py, and lost them silently: they simply never appeared.
    static func unquote(_ value: String) -> String? {
        guard let first = value.first, first == "'" || first == "\"" else { return nil }
        guard value.count >= 2, value.hasSuffix(String(first)) else { return nil }
        return String(value.dropFirst().dropLast())
    }

    /// `['.swift', '.x']` -> the entries, in order.
    static func stringArray(_ value: String) -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [] }
        return value.dropFirst().dropLast()
            .components(separatedBy: ",")
            .compactMap {
                unquote($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    /// Display name to data file, read from `index.js` so the ordering is the export
    /// ordering the JavaScript iterated rather than the directory's.
    static func exports(in indexSource: String) -> [(name: String, file: String)] {
        var found: [(String, String)] = []
        for line in indexSource.components(separatedBy: "\n") {
            guard line.hasPrefix("export { default as ") else { continue }
            // The export name carries whichever quote the generator chose, for the same
            // reason `unquote` has to: a name containing an apostrophe is double-quoted.
            let afterAs = line.dropFirst("export { default as ".count)
            guard let quote = afterAs.first, quote == "'" || quote == "\"" else { continue }
            let body = afterAs.dropFirst()
            guard let nameEnd = body.range(of: "\(quote) } from './"),
                let fileEnd = body.range(of: "'", range: nameEnd.upperBound..<body.endIndex)
            else { continue }
            found.append((
                String(body[body.startIndex..<nameEnd.lowerBound]),
                String(body[nameEnd.upperBound..<fileEnd.lowerBound])
            ))
        }
        return found
    }

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let directory = try input.artifact("languages", for: Self.id)
        let package = directory.appendingPathComponent("package")
        let index = String(
            decoding: try Data(contentsOf: package.appendingPathComponent("index.js")),
            as: UTF8.self)

        let entries = Self.exports(in: index)
        guard entries.count >= 400 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail: "index.js yielded \(entries.count) exports — the layout has changed")
        }

        var rows: [Definition] = []
        var withoutExtension = 0
        var nonProgramming = 0

        for (name, file) in entries.sorted(by: { $0.name < $1.name }) {
            guard
                let data = try? Data(contentsOf: package.appendingPathComponent(file))
            else { continue }
            let source = String(decoding: data, as: UTF8.self)

            // Linguist classifies markup, data and prose alongside programming languages.
            // JSON and Markdown are not what anyone means by "programming language", and a
            // fixture offering them as one is wrong in a way that is hard to notice.
            guard Self.field("type", in: source).flatMap(Self.unquote) == "programming" else {
                nonProgramming += 1
                continue
            }

            let extensions = Self.field("extensions", in: source).map(Self.stringArray) ?? []
            guard let primary = extensions.first else {
                withoutExtension += 1
                continue
            }

            rows.append(
                .object([
                    "name": .string(Self.field("name", in: source).flatMap(Self.unquote) ?? name),
                    // The first extension is Linguist's primary; the rest are alternates.
                    "extension": .string(primary),
                    // Not every language has an assigned colour, and an empty column keeps
                    // the composite one shape rather than present on some rows only.
                    "color": .string(Self.field("color", in: source).flatMap(Self.unquote) ?? ""),
                ]))
        }

        guard rows.count >= 100 else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id,
                detail:
                    "linguist yielded only \(rows.count) programming languages — the data shape has changed"
            )
        }

        return AdapterOutput(
            contributions: ["base": ["system.programming_language": .list(rows)]],
            stats: [
                ("languages", String(rows.count)),
                ("withoutExtension", String(withoutExtension)),
                ("nonProgramming", String(nonProgramming)),
            ])
    }
}
