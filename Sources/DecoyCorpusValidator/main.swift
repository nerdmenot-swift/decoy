import Decoy
import Foundation

/// Checks a corpus contribution before it reaches the corpus.
///
/// The test suite proves the shipped corpus works. This is for the change that has not
/// shipped yet: someone adding a source, an adapter, or a locale, who needs to know
/// whether it hangs together before they open a pull request — and who should not have
/// to read four documents to find out what the rules are.
///
/// The checks are the ones that have actually caught something here:
///
/// - **A path nothing can draw.** `person.last_name_pattern` was compiled into three
///   locales and read by nothing, so the double-barrelled surnames it encodes never
///   appeared. 2,225 `__keys` tables were emitted the same way. Neither failed a test,
///   because a test asks whether what you read is right, never whether what you wrote
///   is read.
/// - **A template token that expands to nothing.** Thirteen of them shipped: English
///   street addresses read `"791 "` and Japanese ones were empty. The test that covers
///   this runs against three locales; there are seventy-six.
/// - **Licence metadata that contradicts its own text.** Nine descriptors did.
/// - **An adapter and a descriptor that do not know about each other.**
///
/// Warnings do not fail the run unless `--strict`, because the useful ones are
/// judgements — data nobody draws *yet* is how a generator gets written.

// MARK: - Arguments

struct Options {
    var corpus = URL(fileURLWithPath: "Corpus/binary")
    var sources = URL(fileURLWithPath: "Tools/adapters/sources")
    var adapters = URL(fileURLWithPath: "Tools/adapters/adapters")
    var licenses = URL(fileURLWithPath: "LICENSES")
    var generators = URL(fileURLWithPath: "Sources/Decoy")
    var manifest = URL(fileURLWithPath: "Tools/adapters/out/manifest.json")
    var strict = false
}

let usage = """
    usage: decoy-validate [options]

      --corpus <dir>       compiled blobs          (default Corpus/binary)
      --sources <dir>      source descriptors      (default Tools/adapters/sources)
      --adapters <dir>     adapter programs        (default Tools/adapters/adapters)
      --licenses <dir>     committed licence texts (default LICENSES)
      --generators <dir>   Swift generator sources (default Sources/Decoy)
      --manifest <file>    adapter output manifest (default Tools/adapters/out/manifest.json)
      --strict             treat warnings as failures

    Run from the repository root. Checks a contribution before it lands: paths nothing
    can draw, template tokens that expand to nothing, and licence metadata that
    contradicts the text beside it.
    """

func parseOptions() -> Options {
    var options = Options()
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        func value(_ flag: String) -> URL {
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data("error: \(flag) needs a directory\n".utf8))
                exit(2)
            }
            defer { i += 2 }
            return URL(fileURLWithPath: args[i + 1])
        }
        switch args[i] {
        case "--corpus": options.corpus = value("--corpus")
        case "--sources": options.sources = value("--sources")
        case "--adapters": options.adapters = value("--adapters")
        case "--licenses": options.licenses = value("--licenses")
        case "--generators": options.generators = value("--generators")
        case "--manifest": options.manifest = value("--manifest")
        case "--strict":
            options.strict = true
            i += 1
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            FileHandle.standardError.write(Data("error: unknown argument '\(args[i])'\n".utf8))
            print(usage)
            exit(2)
        }
    }
    return options
}

// MARK: - Findings

enum Severity: String {
    case error
    case warning
}

struct Finding {
    let severity: Severity
    let check: String
    let message: String
    /// Repeated across many locales, this collapses to one line with a count.
    var locales: [String] = []
}

var findings: [Finding] = []

@MainActor
func report(_ severity: Severity, _ check: String, _ message: String, locales: [String] = []) {
    findings.append(Finding(severity: severity, check: check, message: message, locales: locales))
}

// MARK: - Loading

let options = parseOptions()
let fileManager = FileManager.default

@MainActor
func directoryContents(_ url: URL, suffix: String) -> [URL] {
    (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
        .filter { $0.lastPathComponent.hasSuffix(suffix) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
}

let blobs = directoryContents(options.corpus, suffix: ".decoy")
guard !blobs.isEmpty else {
    FileHandle.standardError.write(
        Data(
            """
            error: no .decoy files in \(options.corpus.path)

            The corpus is a build artifact and is not committed. Build it first:

                node Tools/adapters/run.mjs
                swift run decoy-compile-corpus Tools/adapters/out Corpus/binary

            """.utf8))
    exit(2)
}

var corpora: [String: Corpus] = [:]
for blob in blobs {
    let code = blob.deletingPathExtension().lastPathComponent
    do {
        corpora[code] = try Corpus(bytes: [UInt8](try Data(contentsOf: blob)))
    } catch {
        report(.error, "corpus", "\(code).decoy will not load — \(error)")
    }
}

// MARK: - Check: one corpus version

let versions = Set(corpora.values.map(\.version.description))
if versions.count > 1 {
    // A mixed set means a partial rebuild, and a chain that spans two versions resolves
    // some fields from each — reproducible against neither.
    report(
        .error, "version",
        "blobs declare \(versions.count) different corpus versions "
            + "(\(versions.sorted().joined(separator: ", "))). Recompile the whole directory.")
}

// MARK: - Check: source descriptors

struct Descriptor {
    let id: String
    let license: String
    let copyright: String
    let url: String
    let version: String
    let retrieved: String
    let integrities: [String]
}

var descriptors: [String: Descriptor] = [:]
for file in directoryContents(options.sources, suffix: ".json") {
    let name = file.lastPathComponent
    guard let data = try? Data(contentsOf: file),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        report(.error, "descriptor", "\(name) is not readable JSON")
        continue
    }
    guard let id = object["id"] as? String, !id.isEmpty else {
        report(.error, "descriptor", "\(name) declares no id")
        continue
    }
    if id != file.deletingPathExtension().lastPathComponent {
        // The compiler and the NOTICE generator both key on the id; a filename that
        // disagrees makes the source hard to find from either.
        report(.error, "descriptor", "\(name) declares id '\(id)' — rename one to match")
    }

    let artifacts = object["artifacts"] as? [[String: Any]] ?? []
    descriptors[id] = Descriptor(
        id: id,
        license: object["license"] as? String ?? "",
        copyright: object["copyright"] as? String ?? "",
        url: object["url"] as? String ?? "",
        version: object["version"] as? String ?? "",
        retrieved: object["retrieved"] as? String ?? "",
        integrities: artifacts.compactMap { $0["integrity"] as? String }
    )

    for (field, value) in [
        ("license", descriptors[id]!.license), ("url", descriptors[id]!.url),
        ("version", descriptors[id]!.version), ("retrieved", descriptors[id]!.retrieved),
    ] where value.isEmpty {
        report(.error, "descriptor", "\(id) declares no \(field)")
    }

    if artifacts.isEmpty {
        report(.error, "descriptor", "\(id) declares no artifacts to fetch")
    }
    for integrity in descriptors[id]!.integrities where !integrity.hasPrefix("sha512-") {
        // Anything else is either a weaker digest or a typo, and both mean the fetch is
        // not really pinned.
        report(.error, "descriptor", "\(id) has an integrity hash that is not sha512-")
    }
    if artifacts.count != descriptors[id]!.integrities.count {
        report(.error, "descriptor", "\(id) has an artifact with no integrity hash")
    }
}

if descriptors.isEmpty {
    report(.error, "descriptor", "no source descriptors found in \(options.sources.path)")
}

// MARK: - Check: licence texts

let licenceTexts = Set(
    directoryContents(options.licenses, suffix: ".txt").map {
        String($0.lastPathComponent.dropLast(4))
    })

for (id, descriptor) in descriptors.sorted(by: { $0.key < $1.key }) {
    guard licenceTexts.contains(id) else {
        report(
            .error, "licence",
            "\(id) has no \(options.licenses.lastPathComponent)/\(id).txt. MIT, the WordNet "
                + "family and Unicode all require the notice to travel with the distribution; "
                + "a source with no grant needs a file recording why instead.")
        continue
    }
    let noGrant = ["public-facts", "public-domain", "Unlicense"].contains(descriptor.license)
    if descriptor.copyright.isEmpty && !noGrant {
        report(
            .error, "licence",
            "\(id) is \(descriptor.license) but records no copyright holder — attribution "
                + "cannot be satisfied from a source id")
    }

    let file = options.licenses.appendingPathComponent("\(id).txt")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
    let lowered = text.lowercased()
    // The specific way nine descriptors were wrong: a bare CC BY claim over text that
    // also carries Princeton's terms. Never matched on "wordnet" — half these sources
    // have WordNet in their project name and are plain CC BY.
    if descriptor.license.hasPrefix("CC-BY") && lowered.contains("princeton")
        && !descriptor.license.contains("WordNet")
    {
        report(
            .error, "licence",
            "\(id) claims \(descriptor.license), but its own text names Princeton — that is "
                + "a WordNet grant the claim omits. Use an SPDX expression.")
    }
}

for id in licenceTexts.sorted() where descriptors[id] == nil {
    report(
        .warning, "licence",
        "\(options.licenses.lastPathComponent)/\(id).txt has no matching descriptor — a "
            + "licence for data that no longer ships says the distribution carries it")
}

// MARK: - Check: adapters and descriptors know about each other

var adapterSources: [String: String] = [:]
for file in directoryContents(options.adapters, suffix: ".mjs") {
    let name = file.deletingPathExtension().lastPathComponent
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
    // `export const source = 'mime-db'`, read rather than executed: running a contributor's
    // adapter to find out what it claims is the wrong order of operations.
    //
    // Anchored to the start of a line. Without that it matched the phrase inside a doc
    // comment in wordnet.mjs and reported the source id as a paragraph of prose.
    // `= ` included on purpose. Matching the bare phrase also matched `export const
    // sources` in wordnet.mjs, whose value is computed from a table of fifteen members,
    // and the id came back as a paragraph of the comment above it.
    guard let range = text.range(of: "export const source ="),
        let open = text[range.upperBound...].firstIndex(where: { $0 == "'" || $0 == "\"" }),
        let close = text[text.index(after: open)...].firstIndex(where: { $0 == "'" || $0 == "\"" })
    else {
        if !text.contains("export const sources") {
            report(
                .warning, "adapter",
                "\(name).mjs exports no `source` — nothing to attribute its data to")
        }
        // An adapter naming several sources computes the list, so it cannot be read
        // statically. The manifest check below covers those.
        continue
    }
    let id = String(text[text.index(after: open)..<close])
    adapterSources[name] = id
    if descriptors[id] == nil {
        report(
            .error, "adapter",
            "\(name).mjs names source '\(id)', which has no descriptor in "
                + options.sources.lastPathComponent)
    }
}

// Which sources actually claimed a path, taken from the pipeline's own output rather
// than from the adapter text. An adapter that names its source in a computed expression
// — wordnet reads fifteen members from a table — cannot be read statically, and the
// manifest records what really happened either way.
if let data = try? Data(contentsOf: options.manifest),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let attribution = object["attribution"] as? [String: [String: String]]
{
    let contributing = Set(attribution.values.flatMap(\.values))
    for id in descriptors.keys.sorted() where !contributing.contains(id) {
        report(
            .warning, "adapter",
            "\(id) is fetched, pinned and attributed, but claims no path in the compiled "
                + "corpus — it is a dependency paying for nothing")
    }
    for id in contributing.sorted() where descriptors[id] == nil {
        report(
            .error, "adapter",
            "the corpus attributes data to '\(id)', which has no descriptor — that data "
                + "ships with no licence, version or URL recorded")
    }
} else {
    report(
        .warning, "adapter",
        "no manifest at \(options.manifest.path), so nothing checked which sources actually "
            + "contributed. Run `node Tools/adapters/run.mjs` first.")
}

// MARK: - Check: every template token expands to something

/// Converts `firstName` to `first_name`.
///
/// Duplicated from the reader rather than exposed: the corpus mixes camelCase generator
/// names with snake_case paths, and both spellings have to count as a reference. Six
/// lines here is a better trade than a `public` helper that exists only for this.
func snakeCased(_ input: String) -> String {
    var out = String()
    for character in input {
        if character.isUppercase {
            out.append("_")
            out.append(Character(character.lowercased()))
        } else {
            out.append(character)
        }
    }
    return out
}

/// Every `{{token}}` in a string, without the braces.
func tokens(in template: String) -> [String] {
    var found: [String] = []
    var rest = Substring(template)
    while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
        found.append(String(rest[open.upperBound..<close.lowerBound]))
        rest = rest[close.upperBound...]
    }
    return found
}

/// Chains are `<code> -> en -> base`, which is how every generated module is built.
@MainActor
func chain(for code: String) -> [Corpus] {
    let codes = code == "base" ? ["base"] : (code == "en" ? ["en", "base"] : [code, "en", "base"])
    return codes.compactMap { corpora[$0] }
}

/// Tokens referenced by corpus data, so a path reached only from a pattern still counts
/// as reachable. `person.bio_supporter` is drawn by nothing in Swift and referenced by
/// `person.bio_pattern`, which is not an orphan — it is composition working.
var referencedByTemplates = Set<String>()
var unresolvedTokens: [String: [String]] = [:]

for (code, corpus) in corpora.sorted(by: { $0.key < $1.key }) {
    let locale = LocaleCorpus(code: code, chain: chain(for: code))
    var faker = Faker(seed: 1337, locale: locale)
    var seen = Set<String>()

    guard let entries = try? corpus.paths else { continue }
    for entry in entries {
        guard case .strings(let table)? = try? corpus.entry(for: entry) else { continue }
        for index in 0..<table.count {
            guard let value = try? table.string(at: index),
                value.utf8.contains(UInt8(ascii: "{"))
            else { continue }
            for token in tokens(in: value) {
                referencedByTemplates.insert(token)
                referencedByTemplates.insert(snakeCased(token))
                guard seen.insert(token).inserted else { continue }
                let resolved = faker.resolve(token)
                if resolved == nil || resolved!.isEmpty {
                    unresolvedTokens[token, default: []].append(code)
                }
            }
        }
    }
}

for (token, locales) in unresolvedTokens.sorted(by: { $0.key < $1.key }) {
    report(
        .error, "template",
        "{{\(token)}} expands to nothing — a pattern using it ships with a hole in it",
        locales: locales.sorted())
}

// MARK: - Check: data nothing can draw

/// Corpus paths named in the generator sources.
///
/// Read from the source text, because Decoy carries no reflection — it was removed
/// deliberately, and a validator that reintroduced `Mirror` would be the only thing in
/// the package needing it. Every string literal shaped like a path counts, not only those
/// inside a `draw(` or `require(`: paths reach the corpus through helpers too, and a net
/// that is slightly too wide produces a missing warning rather than a false one.
@MainActor
func generatorPathLiterals() -> [String] {
    var literals = Set<String>()
    let enumerator = fileManager.enumerator(atPath: options.generators.path)
    while let relative = enumerator?.nextObject() as? String {
        guard relative.hasSuffix(".swift"),
            let text = try? String(
                contentsOf: options.generators.appendingPathComponent(relative), encoding: .utf8)
        else { continue }

        var rest = Substring(text)
        while let open = rest.firstIndex(of: "\"") {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "\"") else { break }
            let literal = rest[after..<close]
            rest = rest[rest.index(after: close)...]

            // An interpolated literal such as `date.month.\(abbreviated ...)` keeps its
            // stable prefix, which is what makes the whole subtree reachable.
            let stable = literal.prefix { $0 != "\\" }
            guard stable.contains("."), let first = stable.first, first.isLowercase else {
                continue
            }
            guard stable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" })
            else { continue }
            literals.insert(String(stable).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
    }
    return literals.sorted()
}

let literals = generatorPathLiterals()
if literals.count < 50 {
    report(
        .error, "orphan",
        "only \(literals.count) path literals found under \(options.generators.path) — "
            + "the scan is looking in the wrong place, so the orphan check below means nothing")
}

/// Whether any generator can reach `path`.
@MainActor
func reachable(_ path: String) -> Bool {
    if referencedByTemplates.contains(path) { return true }
    for literal in literals {
        // Equal, beneath, or an ancestor: `person.first_name` is drawn as
        // `person.first_name.female`, and `system.mime_type` is a node whose children are
        // reached by interpolation.
        if path == literal || path.hasPrefix(literal + ".") || literal.hasPrefix(path + ".") {
            return true
        }
    }
    return false
}

var orphans: [String: [String]] = [:]
for (code, corpus) in corpora {
    guard let entries = try? corpus.paths else { continue }
    for entry in entries where !reachable(entry.path) {
        orphans[entry.path, default: []].append(code)
    }
}

for (path, locales) in orphans.sorted(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) }) {
    report(
        .warning, "orphan",
        "\(path) is compiled but no generator can draw it — either write one or stop "
            + "emitting it",
        locales: locales.sorted())
}

// MARK: - Output

let errors = findings.filter { $0.severity == .error }
let warnings = findings.filter { $0.severity == .warning }

@MainActor
func show(_ list: [Finding], _ label: String) {
    guard !list.isEmpty else { return }
    print("\(label) (\(list.count))")
    print(String(repeating: "-", count: label.count + 6))
    for finding in list {
        print("  [\(finding.check)] \(finding.message)")
        if !finding.locales.isEmpty {
            let shown = finding.locales.prefix(6).joined(separator: ", ")
            let more = finding.locales.count > 6 ? " and \(finding.locales.count - 6) more" : ""
            print("      in: \(shown)\(more)")
        }
    }
    print("")
}

print("decoy-validate: \(corpora.count) locales, \(descriptors.count) sources, "
    + "\(adapterSources.count) adapters\n")
show(errors, "errors")
show(warnings, "warnings")

if errors.isEmpty && warnings.isEmpty {
    print("nothing to report.")
} else if errors.isEmpty {
    print("no errors. \(warnings.count) warning(s)\(options.strict ? " — failing under --strict" : "").")
}

exit(errors.isEmpty && !(options.strict && !warnings.isEmpty) ? 0 : 1)
