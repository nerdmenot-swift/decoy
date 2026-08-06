import Decoy
import Foundation

/// Inspects compiled corpora: what is in one, what a path holds, and which locales
/// actually carry their own data.
///
/// Exists because a corpus was previously unreadable without knowing its paths in
/// advance. Once data is sourced here rather than inherited from faker-js, "what do we
/// have" stops being answerable by reading somebody else's repository.
///
/// Usage:
///   decoy-inspect <file.decoy>                 summary
///   decoy-inspect <file.decoy> --paths [glob]  every path, with kind and size
///   decoy-inspect <file.decoy> --path <path>   the values at one path
///   decoy-inspect --coverage <dir> [--against <code>]
///                                              native coverage across a directory

// MARK: - Arguments

enum Command {
    case summary(URL)
    case paths(URL, filter: String?)
    case values(URL, path: String)
    case coverage(URL, against: String)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let usage = """
    usage:
      decoy-inspect <file.decoy>                      summary
      decoy-inspect <file.decoy> --paths [substring]  list paths
      decoy-inspect <file.decoy> --path <path>        show values at one path
      decoy-inspect --coverage <dir> [--against en]   native coverage per locale
    """

func parse() -> Command {
    var positional: [String] = []
    var pathsFilter: String??
    var singlePath: String?
    var coverageDirectory: URL?
    var against = "en"

    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        switch args[i] {
        case "--paths":
            // The filter is optional, so only consume the next argument if it is one.
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                pathsFilter = .some(args[i + 1])
                i += 2
            } else {
                pathsFilter = .some(nil)
                i += 1
            }
        case "--path":
            guard i + 1 < args.count else { fail("--path needs a value") }
            singlePath = args[i + 1]
            i += 2
        case "--coverage":
            guard i + 1 < args.count else { fail("--coverage needs a directory") }
            coverageDirectory = URL(fileURLWithPath: args[i + 1])
            i += 2
        case "--against":
            guard i + 1 < args.count else { fail("--against needs a locale code") }
            against = args[i + 1]
            i += 2
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            positional.append(args[i])
            i += 1
        }
    }

    if let directory = coverageDirectory { return .coverage(directory, against: against) }
    guard positional.count == 1 else { fail(usage) }
    let file = URL(fileURLWithPath: positional[0])

    if let singlePath { return .values(file, path: singlePath) }
    if let pathsFilter { return .paths(file, filter: pathsFilter) }
    return .summary(file)
}

// MARK: - Loading

func load(_ url: URL) -> Corpus {
    guard let data = try? Data(contentsOf: url) else {
        fail("cannot read \(url.path)")
    }
    do {
        return try Corpus(bytes: [UInt8](data))
    } catch {
        fail("\(url.lastPathComponent) is not a readable corpus — \(error)")
    }
}

/// The namespace a path belongs to: `person.first_name.female` -> `person`.
func namespace(_ path: String) -> String {
    String(path.prefix { $0 != "." })
}

func describe(_ kind: PathEntry.Kind) -> String {
    switch kind {
    case .explicitlyEmpty: "null"
    case .strings: "strings"
    case .composite: "composite"
    case .model: "model"
    case .unknown(let raw): "unknown(\(raw))"
    }
}

/// How many values sit at a path, for the listing's size column.
func size(of entry: Entry) -> String {
    switch entry {
    case .strings(let table): "\(table.count)\(table.hasWeights ? "w" : "")"
    case .composite(let table): "\(table.rowCount)x\(table.fieldCount)"
    case .explicitlyEmpty: "—"
    case .model: "model"
    }
}

// MARK: - Commands

func summary(_ url: URL) throws {
    let corpus = load(url)
    let paths = try corpus.paths

    var byKind: [String: Int] = [:]
    var byNamespace: [String: Int] = [:]
    var values = 0
    var sourceIDs = Set<UInt32>()
    var pathsBySource: [UInt32: Int] = [:]
    var valuesBySource: [UInt32: Int] = [:]

    for entry in paths {
        byKind[describe(entry.kind), default: 0] += 1
        byNamespace[namespace(entry.path), default: 0] += 1
        switch try corpus.entry(for: entry) {
        case .strings(let table):
            values += table.count
            sourceIDs.insert(table.sourceID)
            pathsBySource[table.sourceID, default: 0] += 1
            valuesBySource[table.sourceID, default: 0] += table.count
        case .composite(let table):
            values += table.rowCount
            sourceIDs.insert(table.sourceID)
            pathsBySource[table.sourceID, default: 0] += 1
            valuesBySource[table.sourceID, default: 0] += table.rowCount
        case .explicitlyEmpty, .model:
            break
        }
    }

    print("file           : \(url.lastPathComponent)")
    print("corpus version : \(corpus.version)")
    print("paths          : \(paths.count)")
    print("values         : \(values)")
    print("distinct strings: \(corpus.stringCount)")
    print("kinds          : " + byKind.sorted { $0.key < $1.key }
        .map { "\($0.key) \($0.value)" }.joined(separator: ", "))

    print("\nnamespaces (\(byNamespace.count)):")
    for (name, count) in byNamespace.sorted(by: { $0.key < $1.key }) {
        print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(count) paths")
    }

    // Provenance is the point of recording sources at all; showing it here is what
    // makes "is any of this still faker-derived" a question you can answer per file.
    let sources = sourceIDs.sorted().compactMap { id -> (UInt32, Source)? in
        guard let source = try? corpus.source(id) else { return nil }
        return (id, source)
    }
    if !sources.isEmpty {
        print("\nsources (\(sources.count)):")
        // Sorted by how much each contributes, so "what is this corpus mostly made of"
        // is the first thing the eye lands on. During a migration that ordering is the
        // progress bar.
        for (id, source) in sources.sorted(by: { valuesBySource[$0.0, default: 0] > valuesBySource[$1.0, default: 0] }) {
            let pathCount = pathsBySource[id, default: 0]
            let valueCount = valuesBySource[id, default: 0]
            let share = values == 0 ? 0 : Int((Double(valueCount) / Double(values) * 100).rounded())
            let retrieved = source.retrieved.isEmpty ? "" : ", retrieved \(source.retrieved)"
            print("  \(source.id) — \(source.license), \(source.version)\(retrieved)")
            print("    \(pathCount) paths, \(valueCount) values (\(share)% of this corpus)")
            if !source.url.isEmpty { print("    \(source.url)") }
        }
    }
}

func list(_ url: URL, filter: String?) throws {
    let corpus = load(url)
    var shown = 0
    for entry in try corpus.paths {
        if let filter, !entry.path.contains(filter) { continue }
        let kind = describe(entry.kind).padding(toLength: 9, withPad: " ", startingAt: 0)
        let count = size(of: try corpus.entry(for: entry))
            .padding(toLength: 7, withPad: " ", startingAt: 0)
        print("\(kind) \(count) \(entry.path)")
        shown += 1
    }
    if shown == 0 {
        print("no paths\(filter.map { " matching '\($0)'" } ?? "")")
    } else {
        print("\n\(shown) paths")
    }
}

func values(_ url: URL, path: String) throws {
    let corpus = load(url)
    guard let entry = try corpus.lookup(path) else {
        // Suggest neighbours rather than just failing: a wrong path is far more often a
        // typo or a guess at the naming convention than a genuinely absent field.
        let near = try corpus.paths
            .filter { $0.path.contains(path) || path.contains(namespace($0.path)) }
            .prefix(10)
        if near.isEmpty {
            fail("no path '\(path)' in \(url.lastPathComponent)")
        }
        print("no path '\(path)'. did you mean:")
        for candidate in near { print("  \(candidate.path)") }
        exit(1)
    }

    switch entry {
    case .explicitlyEmpty:
        print("'\(path)' is explicitly empty — this locale defines it as having no value,")
        print("which blocks fallback to the locales behind it.")

    case .strings(let table):
        if let source = try corpus.source(table.sourceID) {
            print("source: \(source.id) (\(source.license))")
        }
        print("\(table.count) values\(table.hasWeights ? ", weighted" : "")\n")
        for i in 0..<table.count {
            if table.hasWeights {
                print("  \(try table.weight(at: i))\t\(try table.string(at: i))")
            } else {
                print("  \(try table.string(at: i))")
            }
        }

    case .composite(let table):
        if let source = try corpus.source(table.sourceID) {
            print("source: \(source.id) (\(source.license))")
        }
        let fields = try (0..<table.fieldCount).map { try table.fieldName($0) }
        print("\(table.rowCount) rows, fields: \(fields.joined(separator: ", "))\n")
        for row in 0..<table.rowCount {
            let cells = try (0..<table.fieldCount).map { try table.value(row: row, field: $0) }
            print("  " + cells.joined(separator: "\t"))
        }

    case .model(let id):
        print("'\(path)' is a generative model (id \(id)).")
    }
}

/// Reports what each locale defines *itself*, against a reference locale.
///
/// Native coverage rather than resolved coverage: a locale resolving `person.first_name`
/// only because English sits behind it in the chain is the failure this is meant to
/// surface, and resolved coverage would report it as 100%.
func coverage(_ directory: URL, against reference: String) throws {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                              includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "decoy" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    guard !files.isEmpty else { fail("no .decoy files in \(directory.path)") }

    let referenceURL = directory.appendingPathComponent("\(reference).decoy")
    guard FileManager.default.fileExists(atPath: referenceURL.path) else {
        fail("reference locale '\(reference)' not found in \(directory.path)")
    }
    let referencePaths = Set(try load(referenceURL).paths.map(\.path))
    let referenceNamespaces = Set(referencePaths.map(namespace)).sorted()

    print("native coverage against '\(reference)' (\(referencePaths.count) paths)")
    print("percentages are paths a locale defines ITSELF, not what it resolves via fallback.\n")

    let width = 14
    print("locale".padding(toLength: width, withPad: " ", startingAt: 0)
        + "  own%   own    " + referenceNamespaces.map { String($0.prefix(4)) }
        .joined(separator: " "))

    for file in files {
        let code = file.deletingPathExtension().lastPathComponent
        let paths = Set(try load(file).paths.map(\.path))
        let covered = paths.intersection(referencePaths).count
        let percent = referencePaths.isEmpty
            ? 0 : Int((Double(covered) / Double(referencePaths.count) * 100).rounded())

        // Intersected, not counted raw: a locale may define paths the reference lacks,
        // and counting those would report coverage above 100% — which reads as "more
        // than complete" exactly where the number is supposed to be trustworthy.
        let shared = paths.intersection(referencePaths)
        let cells = referenceNamespaces.map { namespaceName -> String in
            let total = referencePaths.filter { namespace($0) == namespaceName }.count
            let have = shared.filter { namespace($0) == namespaceName }.count
            guard total > 0 else { return "   ." }
            // A dot reads as "nothing here" far faster than a zero in a wide table.
            return have == 0 ? "   ." : String(
                format: "%4d", Int((Double(have) / Double(total) * 100).rounded()))
        }

        print(code.padding(toLength: width, withPad: " ", startingAt: 0)
            + String(format: "%5d%%", percent)
            + String(format: "%7d", paths.count)
            + "  " + cells.joined(separator: " "))
    }
}

// MARK: - Driver

switch parse() {
case .summary(let url): try summary(url)
case .paths(let url, let filter): try list(url, filter: filter)
case .values(let url, let path): try values(url, path: path)
case .coverage(let directory, let reference): try coverage(directory, against: reference)
}
