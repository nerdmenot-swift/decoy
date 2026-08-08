import Decoy
import DecoyCorpusKit
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
///   decoy-inspect <file.decoy> --paths [substr] every path, with kind and size
///                                              (a plain substring match, not a glob)
///   decoy-inspect <file.decoy> --path <path>   the values at one path
///   decoy-inspect --coverage <dir> [--against <code>]
///                                              native coverage across a directory

// MARK: - Arguments

enum Command {
    case summary(URL)
    case paths(URL, filter: String?)
    case values(URL, path: String)
    case coverage(URL, against: String, gate: URL?, writeGate: URL?)
    case notice(URL, licenses: URL?)
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
      decoy-inspect --coverage <dir> --gate <file>    fail if coverage regressed
      decoy-inspect --coverage <dir> --write-gate <f>  record the current state as baseline
      decoy-inspect --notice <dir> [--licenses LICENSES]
                                                      attribution for every source shipped
    """

func parse() -> Command {
    var positional: [String] = []
    var pathsFilter: String??
    var singlePath: String?
    var coverageDirectory: URL?
    var noticeDirectory: URL?
    var licensesDirectory: URL?
    var gate: URL?
    var writeGate: URL?
    var against = "en"
    var againstWasGiven = false

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
        case "--notice":
            guard i + 1 < args.count else { fail("--notice needs a directory") }
            noticeDirectory = URL(fileURLWithPath: args[i + 1])
            i += 2
        case "--licenses":
            guard i + 1 < args.count else { fail("--licenses needs a directory") }
            licensesDirectory = URL(fileURLWithPath: args[i + 1])
            i += 2
        case "--gate":
            guard i + 1 < args.count else { fail("--gate needs a baseline file") }
            gate = URL(fileURLWithPath: args[i + 1])
            i += 2
        case "--write-gate":
            guard i + 1 < args.count else { fail("--write-gate needs a file") }
            writeGate = URL(fileURLWithPath: args[i + 1])
            i += 2
        case "--against":
            guard i + 1 < args.count else { fail("--against needs a locale code") }
            against = args[i + 1]
            againstWasGiven = true
            i += 2
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            positional.append(args[i])
            i += 1
        }
    }

    // Every combination that cannot be honoured is refused here rather than silently
    // resolved by the order of these `if`s. `--notice` used to win over `--coverage`,
    // `--write-gate` over `--gate`, and `--against` was accepted and ignored under both
    // gate modes — so a run could report success having done something other than what
    // was asked, which is the worst thing a tool whose whole job is auditing can do.
    if noticeDirectory != nil && coverageDirectory != nil {
        fail("--notice and --coverage do different jobs; run them separately")
    }
    if gate != nil && writeGate != nil {
        fail("--gate checks the baseline and --write-gate replaces it; pick one")
    }
    if againstWasGiven && (gate != nil || writeGate != nil) {
        fail("--against applies to the coverage report, not to the gate, which compares "
            + "each locale against its own recorded counts")
    }
    if !positional.isEmpty && (noticeDirectory != nil || coverageDirectory != nil) {
        fail("unexpected argument '\(positional[0])': --notice and --coverage take a "
            + "directory, not a file")
    }

    if let directory = noticeDirectory { return .notice(directory, licenses: licensesDirectory) }
    if let directory = coverageDirectory {
        return .coverage(directory, against: against, gate: gate, writeGate: writeGate)
    }
    if licensesDirectory != nil { fail("--licenses only applies to --notice") }
    if gate != nil || writeGate != nil { fail("--gate and --write-gate need --coverage") }

    guard positional.count == 1 else { fail(usage) }
    let file = URL(fileURLWithPath: positional[0])

    if singlePath != nil && pathsFilter != nil {
        fail("--path shows one path's values and --paths lists them; pick one")
    }
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
    // Contexts rather than values: a model has no row count, and the number of contexts
    // is the thing that says how much of the training data it actually kept.
    case .model(let model): "\(model.contextCount)ctx"
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
        case .model(let model):
            sourceIDs.insert(model.sourceID)
            pathsBySource[model.sourceID, default: 0] += 1
        case .explicitlyEmpty:
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

    case .model(let model):
        // A model has no values to list, which is the whole point of it, so this reports
        // its shape and then draws some — the only honest way to show what it holds.
        if let source = try corpus.source(model.sourceID) {
            print("source: \(source.id) (\(source.license)) — training data")
        }
        print("order \(model.order), \(model.alphabetCount - 1) characters, "
            + "\(model.contextCount) contexts")
        print("Bloom filter: \(model.filterByteCount) bytes, \(model.filterHashCount) hashes")
        print("")
        print("a model stores no values; these are drawn from it:")
        var faker = Faker(seed: 1337, locale: LocaleCorpus(code: "?", chain: [corpus]))
        for _ in 0..<20 {
            print("  " + (faker.draw(fromModel: model) ?? "<empty>"))
        }

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
    }
}

/// Reports what each locale defines *itself*, against a reference locale.
///
/// Native coverage rather than resolved coverage: a locale resolving `person.first_name`
/// only because English sits behind it in the chain is the failure this is meant to
/// surface, and resolved coverage would report it as 100%.
func coverage(_ directory: URL, against reference: String, gate: URL?, writeGate: URL?) throws {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                              includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "decoy" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    guard !files.isEmpty else { fail("no .decoy files in \(directory.path)") }

    if let baselineURL = writeGate {
        try writeBaseline(baselineURL, over: files)
        return
    }
    if let gate {
        try enforce(gate, over: files)
        return
    }

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

/// Counts what a locale carries: its own paths, and the values reachable through them.
///
/// Values are counted rather than inferred from path count because the two fail
/// independently. `us-surnames` supplies one path and 24,889 values; an adapter silently
/// returning three would keep the path and lose the data, which is precisely the
/// regression the gate is described as catching and could not.
func coverage(of corpus: Corpus) throws -> LocaleCoverage {
    var values = 0
    let entries = try corpus.paths
    for entry in entries {
        switch try corpus.entry(for: entry) {
        case .strings(let table): values += table.count
        case .composite(let table): values += table.rowCount
        case .model(let model): values += model.contextCount
        case .explicitlyEmpty: break
        }
    }
    return LocaleCoverage(paths: entries.count, values: values)
}

/// Fails when any locale carries less of its own data than the baseline records.
///
/// A regression gate, not a quality bar. Median native coverage is 26% and most locales
/// sit under 30%, so an absolute threshold would fail everything on the first run and be
/// switched off within a week. What is actually worth catching is a locale going
/// *backwards* — an adapter that stops emitting, a source that silently returns less
/// after a re-pin — which is invisible in a passing test suite because the corpus is a
/// build artifact nobody diffs.
///
/// Growth is not a failure and does not require a baseline update to pass; the message
/// says when the file is worth refreshing.
func enforce(_ baselineURL: URL, over files: [URL]) throws {
    guard let data = try? Data(contentsOf: baselineURL) else {
        fail(
            "cannot read \(baselineURL.path) — regenerate it with:\n"
                + "  decoy-inspect --coverage <dir> --write-gate \(baselineURL.path)"
        )
    }
    let baseline = try JSONDecoder().decode(CoverageBaseline.self, from: data)

    var measured: [String: LocaleCoverage] = [:]
    for file in files {
        measured[file.deletingPathExtension().lastPathComponent] = try coverage(of: try load(file))
    }

    let result = compareCoverage(measured: measured, against: baseline)

    for regression in result.regressions {
        let message =
            "regression: \(regression.locale) has \(regression.actual) "
            + "\(regression.dimension.rawValue), baseline expects \(regression.expected)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
    for locale in result.missing {
        FileHandle.standardError.write(Data(
            "missing: \(locale) is in the baseline but not in the corpus\n".utf8))
    }
    if !result.unlisted.isEmpty {
        print("new locales, not yet in the baseline: \(result.unlisted.joined(separator: ", "))")
    }
    if !result.improved.isEmpty {
        print(
            "\(result.improved.count) locale(s) gained paths or values "
                + "— refresh the baseline to lock that in")
    }

    guard result.passes else {
        fail("coverage regressed in \(result.regressions.count + result.missing.count) locale(s)")
    }
    print("coverage gate: \(files.count) locales, none below baseline")
}

/// Writes the current state as the new baseline.
func writeBaseline(_ baselineURL: URL, over files: [URL]) throws {
    var locales: [String: LocaleCoverage] = [:]
    for file in files {
        locales[file.deletingPathExtension().lastPathComponent] = try coverage(of: try load(file))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(CoverageBaseline(locales: locales)).write(to: baselineURL)
    print("wrote \(locales.count) locales to \(baselineURL.lastPathComponent)")
}

// MARK: - Attribution

/// Emits the NOTICE text for every source represented in a compiled corpus.
///
/// Derived from the provenance records embedded in the blobs rather than maintained by
/// hand, so attribution cannot drift from what actually shipped. That is not a
/// convenience: several of these licences are conditions of distribution, and a
/// hand-written list silently stops being true the next time an adapter changes.
///
/// CC BY 4.0 §3(a)(1) wants the title, the creator, a copyright notice, a link to the
/// licence, **and an indication that the material was modified**. Decoy's corpus is
/// unambiguously modified — filtered, re-encoded into a binary format and deduplicated
/// across locales — so that statement is stated once, prominently, rather than implied.
func notice(_ directory: URL, licenses licensesDirectory: URL?) throws {
    // Which sources have their full text committed. MIT, the WordNet family and Unicode
    // all require the text itself to travel with the distribution, so a link is not
    // enough — but the text is per *source*, not per licence family: `omw-da` and
    // `omw-nb` carry bespoke licences and `omw-fi` is dual, so a shared WordNet-3.0 file
    // would be wrong for three of the eight sources filed under it.
    let licenseTexts: Set<String> = {
        guard let directory = licensesDirectory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return Set(names.filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) })
    }()

    let files = (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "decoy" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    guard !files.isEmpty else { fail("no .decoy files in \(directory.path)") }

    // Read from each corpus's provenance chunk rather than by walking its tables.
    // A table merged from several upstreams is credited to one of them, so walking
    // tables omits the others: the ISO 4217 registry supplies every numeric currency
    // code and would have been missing from this file entirely.
    //
    // Deduplicated by id, because the same source appears in all seventy-six locales and
    // a NOTICE that repeated CLDR seventy-six times would be complete and unreadable.
    var sources: [String: Source] = [:]
    for file in files {
        for source in try load(file).sources where sources[source.id] == nil {
            // `CorpusBuilder` reserves source 0 so every table can reference something
            // when provenance is unknown. Nothing is ever attributed to it, but printing
            // it produced an empty licence heading over `unattributed — version ` in the
            // one document whose whole job is saying where the data came from.
            guard !source.license.isEmpty else { continue }
            sources[source.id] = source
        }
    }

    // A source named here without its text is the failure this whole file exists to
    // prevent: MIT, the WordNet family and Unicode all require the notice itself to
    // travel with the distribution, and the four public-domain sources need a recorded
    // reason rather than silence. Both live in `LICENSES/<id>.txt`, so one check covers
    // them, and it fails the build rather than printing an incomplete NOTICE.
    if licensesDirectory != nil {
        let uncovered = sources.keys.filter { !licenseTexts.contains($0) }.sorted()
        if !uncovered.isEmpty {
            fail(
                "no licence text or recorded reason for: \(uncovered.joined(separator: ", ")). "
                    + "Add LICENSES/<id>.txt for each."
            )
        }
    }

    print(
        """
        Decoy
        Copyright 2026 Srinivas Iyer

        This product includes software developed at NerdMeNot, licensed under the Apache
        License, Version 2.0.

        ------------------------------------------------------------------------------
        Corpus data
        ------------------------------------------------------------------------------

        Decoy's data corpus is derived from the sources below. The data has been MODIFIED:
        entries were filtered and selected, re-encoded into Decoy's binary corpus format,
        and deduplicated across locales. None of the sources listed endorse Decoy or its
        use of their material.

        This file is generated from the provenance records embedded in the compiled
        corpus, so it describes exactly what ships:

            swift run decoy-inspect --notice Corpus/binary --licenses LICENSES > NOTICE

        Each source's full licence text is committed at `LICENSES/<source-id>.txt`. Where
        a source carries no grant at all — a registry of facts, or a work of the US
        government — that file records why, rather than leaving the absence unexplained.

        """
    )

    // Grouped by licence rather than by source, because the reader of a NOTICE is
    // usually answering "what obligations does this impose on me", not "what is in it".
    let grouped = Dictionary(grouping: sources.values, by: \.license)
    for license in grouped.keys.sorted() {
        print("\(license)")
        print(String(repeating: "-", count: license.count))
        for source in grouped[license]!.sorted(by: { $0.id < $1.id }) {
            let retrieved = source.retrieved.isEmpty ? "" : ", retrieved \(source.retrieved)"
            print("  \(source.id) — version \(source.version)\(retrieved)")
            // The holder is most of what MIT and CC BY actually ask for, and naming a
            // licence without saying whose work it covers satisfies neither.
            if !source.copyright.isEmpty { print("    \(source.copyright)") }
            if !source.url.isEmpty { print("    \(source.url)") }
            if licenseTexts.contains(source.id) { print("    Full licence: LICENSES/\(source.id).txt") }
        }
        if let uri = licenseURI(license) { print("    Licence: \(uri)") }
        print("")
    }
}

/// The canonical URI for a licence, which CC BY requires be conveyed alongside the work.
///
/// Kept as a table rather than derived from the identifier: several of these are not
/// SPDX identifiers at all — `public-facts` and `public-domain` record *reasoning* about
/// data that carries no grant, and inventing a URL for them would assert a licence that
/// does not exist.
func licenseURI(_ license: String) -> String? {
    switch license {
    case "CC-BY-4.0": "https://creativecommons.org/licenses/by/4.0/"
    case "CC-BY-3.0": "https://creativecommons.org/licenses/by/3.0/"
    case "Apache-2.0": "https://www.apache.org/licenses/LICENSE-2.0"
    case "MIT": "https://opensource.org/licenses/MIT"
    case "Unicode-3.0": "https://www.unicode.org/license.txt"
    case "WordNet-3.0": "https://wordnet.princeton.edu/license-and-commercial-use"
    case "Unlicense": "https://unlicense.org/"
    // Two members are dual-licensed, so the expression gets its own entry rather than
    // being filed under either half. The six `LicenseRef-` members deliberately get
    // none: a bespoke licence has no canonical URI, and pointing at a project homepage
    // would suggest terms live there that do not. `LICENSES/<id>.txt` is their pointer.
    case "WordNet-3.0 AND CC-BY-3.0": "https://wordnet.princeton.edu/license-and-commercial-use"
    // WordNet-SALDO's only rights statement reads `CC-BY attribution` with no version,
    // so the reader is sent to the licence family rather than to a version nobody chose.
    case "CC-BY": "https://creativecommons.org/licenses/"
    default: nil
    }
}

// MARK: - Driver

switch parse() {
case .summary(let url): try summary(url)
case .paths(let url, let filter): try list(url, filter: filter)
case .values(let url, let path): try values(url, path: path)
case .coverage(let directory, let reference, let gate, let writeGate):
    try coverage(directory, against: reference, gate: gate, writeGate: writeGate)
case .notice(let directory, let licenses): try notice(directory, licenses: licenses)
}
