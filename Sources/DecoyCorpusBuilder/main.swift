import Decoy
import DecoyAdapterKit
import Foundation

/// Builds the intermediate corpus JSON from the adapters.
///
/// Every source is a pinned artifact fetched by URL and verified against an integrity hash.
/// Nothing is installed and nothing is vendored except the two upstreams no build machine
/// can reach, and those are hashed like everything else.
///
/// Output (regenerable, none of it committed):
///   out/locales/<code>.json  nested definitions for one locale
///   out/manifest.json        chains, source records, and per-path attribution
///
/// ## Why this is a Swift executable and not a Node script
///
/// It was a Node script, and the corpus it produced is what every adapter here is checked
/// against. The reason to move was not that JavaScript was doing it badly: it was that a
/// Swift package whose data pipeline needs a second language runtime asks every contributor
/// to install one, and asks CI to keep two toolchains working. The corpus is Decoy's
/// substance, so the tool that builds it belongs in the same language as the thing it
/// builds.

// MARK: - Arguments

let arguments = CommandLine.arguments
var excluded = Set<String>()
for (index, argument) in arguments.enumerated() where argument == "--without" {
    // `--without <id>` drops an adapter from the run.
    //
    // Built for one question — does the corpus still work with faker-js gone? — which is
    // now answered permanently. It stays because the question generalises: any adapter can
    // be pulled and the result measured rather than argued about, which is how the street
    // and vocabulary decisions were settled.
    if index + 1 < arguments.count { excluded.insert(arguments[index + 1]) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tools")
    .appendingPathComponent("adapters")

let outDirectory = root.appendingPathComponent("out")

/// `--write-baselines` re-records each adapter's contribution under `parity/`.
///
/// These began as the port's scaffolding: every adapter's output was frozen from the
/// JavaScript before any of it was rewritten, so a ported adapter could be checked against
/// what its predecessor actually produced rather than against a re-description of what it
/// was supposed to produce. With the JavaScript gone they would have become unregenerable
/// fixtures, correct today and impossible to update the first time an upstream is
/// legitimately re-pinned — the kind of check people delete rather than fix.
///
/// So they are regenerable from here instead, and what they are for has changed with them:
/// not "does Swift match JavaScript" but "did this adapter's output move". A re-pin
/// regenerates them and the diff is reviewed like any other.
let writeBaselines = arguments.contains("--write-baselines")
let baselineDirectory = root.appendingPathComponent("parity")

func note(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func fail(_ line: String) -> Never {
    note("error: \(line)")
    exit(1)
}

// MARK: - The adapters

// Named explicitly rather than discovered, and named in one place — see `Adapters.all`,
// which the builder, the validator and the parity suite all read.
let allAdapters = Adapters.all
let keyTables = Adapters.keyTables

let adapters = allAdapters.filter { !excluded.contains($0.adapterID) }
if !excluded.isEmpty {
    note("excluded        : \(excluded.sorted().joined(separator: ", "))")
}

// MARK: - Roster and version

/// Declared in one file so the compiler, the tests and CI cannot disagree about it.
let corpusVersion: String = {
    guard
        let data = try? Data(
            contentsOf: root.appendingPathComponent("corpus-version.json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let version = object["version"] as? String
    else { fail("corpus-version.json is unreadable") }

    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    else { fail("corpus-version.json holds '\(version)', which is not X.Y.Z") }
    return version
}()

/// Per locale: the version it declares, and the fingerprint of the data that version was
/// recorded against.
///
/// The release number above is one figure for the whole build, which is too blunt to act
/// on — adding Hindi bumped it for somebody using only English, so their fixtures read as
/// at-risk when nothing they used had moved. A locale's own version changes only when its
/// own data does, and the fingerprint is what makes that a check rather than a promise.
let declaredLocaleVersions: [String: (version: String, fingerprint: String)] = {
    guard
        let data = try? Data(
            contentsOf: root.appendingPathComponent("corpus-version.json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { fail("corpus-version.json is unreadable") }

    guard let table = object["locales"] as? [String: [String: String]] else {
        fail("corpus-version.json declares no `locales` table")
    }
    var out: [String: (version: String, fingerprint: String)] = [:]
    for (code, entry) in table {
        guard let version = entry["version"] else {
            fail("corpus-version.json: \(code) declares no version")
        }
        out[code] = (version, entry["fingerprint"] ?? "")
    }
    return out
}()

/// What each locale's data hashed to this run, filled as locales are compiled.
var localeFingerprints: [String: String] = [:]

let (locales, cldrOverrides): ([String], [String: String?]) = {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("locales.json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let codes = object["locales"] as? [String]
    else { fail("locales.json is unreadable") }

    var overrides: [String: String?] = [:]
    for (key, value) in (object["cldr"] as? [String: Any]) ?? [:] {
        overrides[key] = value as? String
    }
    return (codes, overrides)
}()

let roster = Set(locales)
// Chains are derived once and handed to the adapters that need them.
let chains = Dictionary(
    uniqueKeysWithValues: locales.map { ($0, Orchestrator.fallbackChain($0, roster: roster)) })

// MARK: - Sources

let store = ArtifactStore(root: root)
var sourceRecords: [String: SourceDescriptor.Provenance] = [:]
/// The order sources were first loaded, which is adapter order.
///
/// Not sorted, and not incidental: the compiler numbers sources by their position in this
/// array and stores that number against every table. Emitting them alphabetically produced
/// an intermediate that compared equal field by field and compiled to 64 different binaries,
/// because every table pointed at a different source record.
var sourceOrder: [String] = []

@MainActor func descriptor(_ id: String) throws -> SourceDescriptor {
    try JSONDecoder().decode(
        SourceDescriptor.self,
        from: Data(contentsOf: root.appendingPathComponent("sources/\(id).json")))
}

/// Acquires, verifies and unpacks every artifact a source declares, and registers its
/// provenance.
@MainActor func load(_ id: String) async throws -> [String: URL] {
    let source = try descriptor(id)

    var artifacts: [String: URL] = [:]
    for artifact in source.artifacts ?? [] {
        let path = try await store.acquire(artifact, source: id, log: note)
        artifacts[artifact.name] = try store.materialise(artifact, at: path, source: id)
    }

    // A version is transcribed, never read back out of the data.
    //
    // Reading it was tried, for `iana-tld`, on the reasoning that a stale transcribed
    // version is provenance naming something that never shipped. It is — and the cure was
    // worse. IANA republishes the root zone with a fresh serial whenever the zone is
    // regenerated, all 1,438 entries identical, which is exactly why that descriptor's
    // digest ignores the serial line. Adopting the same number as the version put a
    // daily-changing value in the provenance chunk, inside the committed blob, so every
    // rebuild on a new day produced different locale modules for data that had not moved.
    //
    // A number that changes when the data does not is not a version of the data.

    // Held, not registered. A source is credited once its adapter has actually
    // contributed something — see `credit`. Registering here instead put Statistics Korea
    // in NOTICE for a snapshot that does not exist yet, which is the `common-knowledge`
    // failure inverted: crediting data that does not ship rather than failing to credit
    // data that does.
    provenance[source.id] = source.provenance
    return artifacts
}

/// Every descriptor that has been read, whether or not its data reached the corpus.
var provenance: [String: SourceDescriptor.Provenance] = [:]

/// Records a source as one the corpus was built from.
@MainActor func credit(_ id: String) {
    guard let record = provenance[id] else { return }
    if sourceRecords[id] == nil { sourceOrder.append(id) }
    sourceRecords[id] = record
}

// MARK: - Run the adapters

if writeBaselines {
    try? FileManager.default.createDirectory(
        at: baselineDirectory, withIntermediateDirectories: true)
}

var contributions: [Orchestrator.Contribution] = []

for adapter in adapters {
    let id = adapter.adapterID
    let sources = adapter.adapterSources
    note("adapter \(id) (\(sources.joined(separator: " + ")))")

    var artifacts: [String: URL] = [:]
    for sourceID in sources {
        let loaded: [String: URL]
        do { loaded = try await load(sourceID) } catch {
            fail("\(id): \(error)")
        }
        for (name, path) in loaded {
            guard artifacts[name] == nil else {
                fail("\(id): two of its sources both name an artifact '\(name)'")
            }
            artifacts[name] = path
        }
    }

    let output: AdapterOutput
    do {
        output = try adapter.run(
            AdapterInput(
                artifacts: artifacts, locales: locales, chains: chains,
                cldrOverrides: cldrOverrides,
                dataDirectory: root.appendingPathComponent("data")))
    } catch {
        fail("\(error)")
    }

    let summary = output.stats.filter { !$0.1.isEmpty }
        .map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    if !summary.isEmpty { note("  \(summary)") }

    // An adapter that produced nothing is not a source the corpus was built from. Every
    // source it names is credited when it produced anything at all, because the format
    // records one source per table and an adapter combining several cannot split them.
    if !output.contributions.isEmpty { for sourceID in sources { credit(sourceID) } }

    if writeBaselines {
        let record: [String: Any] = [
            "id": id,
            "sources": sources,
            // The source the tables are credited to, which is the first one unless
            // the adapter names another.
            "attributeTo": type(of: adapter).attributeTo ?? sources[0],
            "fallback": false,
            "contributions": output.contributions.mapValues { $0.mapValues(\.json) },
            "sourceByLocale": output.sourceByLocale as Any? ?? NSNull(),
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: baselineDirectory.appendingPathComponent("\(id).json"))
        } catch {
            fail("could not write the \(id) baseline: \(error)")
        }
    }

    contributions.append(
        Orchestrator.Contribution(
            id: id,
            // The format stores one source per table, so a table merged from several
            // sources is credited to the one the adapter names as primary. Every source it
            // used is still registered in the corpus, so nothing is lost — the attribution
            // is just coarser than per-field.
            attributeTo: type(of: adapter).attributeTo ?? sources[0],
            isFallback: false,
            contributions: output.contributions,
            sourceByLocale: output.sourceByLocale))
}

let merged: Orchestrator.Result
do {
    merged = try Orchestrator(roster: roster).merge(contributions)
} catch {
    fail("\(error)")
}

// MARK: - Pipeline stages
//
// Loaded before the manifest is built, not after, because the source list is snapshotted
// into it. Loading them afterwards left LDNOOBW out of the manifest and therefore out of
// NOTICE — an attribution failure for a CC BY 4.0 source, produced by a line ordering.
//
// The blocklist is loaded here rather than by an adapter because no adapter uses it: it
// screens what models produce, and models are trained at this level. Registered in
// `sourceRecords` all the same, so it reaches the manifest and NOTICE like everything else.
let blocklists: [String: [String]]
do {
    let screen = try await load("ldnoobw")
    guard let words = screen["words"] else { fail("ldnoobw has no 'words' artifact") }
    blocklists = try Models.loadBlocklists(at: words)
    // Credited unconditionally: the screen is compiled into every model that ships.
    credit("ldnoobw")
} catch {
    fail("\(error)")
}

// Name order and separator, from the CLDR release the corpus already pins. A pattern is a
// composition rule rather than data, and this is the published authority for the one part
// of it that varies by language.
let nameFormats: NamePatterns.Formats
do {
    let cldr = try await load("cldr-48")
    guard let core = cldr["core"], let personNames = cldr["personnames"] else {
        fail("cldr-48 is missing core or personnames")
    }
    nameFormats = try NamePatterns.loadFormats(
        coreDirectory: core, personNamesDirectory: personNames)
    // Likewise: `person.name` is CLDR's, in every locale that has one.
    credit("cldr-48")
} catch {
    fail("\(error)")
}

// MARK: - Per locale

func countStrings(_ value: Definition) -> Int {
    switch value {
    case .string: return 1
    case .list(let items): return items.reduce(0) { $0 + countStrings($1) }
    case .object(let members): return members.values.reduce(0) { $0 + countStrings($1) }
    case .number, .bool, .null: return 0
    }
}

var attribution = merged.attribution
var localeSummaries: [String: [String: Any]] = [:]
var namePatternCount = 0
var totalStrings = 0
var modelLocales = 0
var modelCount = 0
var unscreened: [String] = []
var tooSmall = 0
var notViable: [String] = []

/// Each locale's intermediate JSON, held until every check has passed.
///
/// Written at the end rather than as they are produced, because the output directory is
/// wiped first and a check that fails midway would leave `out/` holding locale files and no
/// manifest — which the compiler will happily read past, and which is exactly how a stale
/// intermediate once got compiled and reported as a fresh corpus. A failed build now leaves
/// the previous one intact.
var pendingLocaleFiles: [String: Data] = [:]


for code in locales {
    var definitions = merged.definitions[code] ?? [:]
    let parents = (chains[code] ?? []).dropFirst().map { merged.definitions[$0] ?? [:] }

    if NamePatterns.apply(code, to: &definitions, formats: nameFormats, parents: parents) {
        namePatternCount += 1
        attribution[code, default: [:]]["person.name"] = "cldr-48"
    }

    // Models are trained here rather than in an adapter because a model has to learn from
    // what a locale *ends up with* after the merge, not from one adapter's contribution.
    let outcome = Models.trainLocale(code, &definitions, blocklists: blocklists)
    for reason in outcome.skipped {
        if reason.contains("novel") { notViable.append("\(code) \(reason)") } else { tooSmall += 1 }
    }
    if !outcome.trained.isEmpty {
        modelLocales += 1
        modelCount += outcome.trained.count
        if outcome.trained.contains(where: { !$0.screened }) { unscreened.append(code) }
        for model in outcome.trained {
            // A model is attributed to whatever supplied the values it learned from,
            // because that is what it is derived from. Training does not launder
            // provenance.
            guard let from = Models.modelledFields.first(where: { $0.to == model.path })?.from
            else { continue }
            let inherited = (attribution[code] ?? [:])
                .filter { from == $0.key || from.hasPrefix("\($0.key).") }
                .sorted { $0.key.count > $1.key.count }
                .first
            if let inherited { attribution[code, default: [:]][model.path] = inherited.value }
        }
    }

    let json = Definition.object(definitions).json
    guard
        let encoded = try? JSONSerialization.data(
            withJSONObject: json, options: [.withoutEscapingSlashes])
    else { fail("could not encode \(code).json") }
    pendingLocaleFiles[code] = encoded

    let ownStrings = countStrings(.object(definitions))
    totalStrings += ownStrings

    // Hashed from the bytes actually written, so the fingerprint cannot disagree with what
    // the compiler will read. Sorted keys, because a dictionary's order is not data and a
    // fingerprint that moves without the content moving is worse than none.
    let fingerprint: String = {
        guard
            let stable = try? JSONSerialization.data(
                withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
        else { fail("could not fingerprint \(code)") }
        return SHA512.hash([UInt8](stable)).prefix(16).map { String(format: "%02x", $0) }
            .joined()
    }()
    localeFingerprints[code] = fingerprint

    guard let declared = declaredLocaleVersions[code] else {
        fail(
            "\(code) has no entry in corpus-version.json. Add one at 1.0.0, then re-run "
                + "with --write-baselines to record its fingerprint.")
    }
    localeSummaries[code] = [
        "chain": chains[code] ?? [], "ownStrings": ownStrings, "version": declared.version,
    ]
}

// MARK: - Per-locale versions

// A locale whose data moved while its version stayed put, which is the case the per-locale
// contract exists to catch. Reported all at once rather than one per run, because a data
// refresh usually moves several and finding out about the second one after fixing the
// first is how a two-minute edit becomes six builds.
//
// `--write-baselines` records instead of refusing: by then the bump is deliberate and the
// fingerprints are the record of what it was deliberate about.
let moved = localeFingerprints
    .filter { code, hash in
        guard let declared = declaredLocaleVersions[code] else { return false }
        return !declared.fingerprint.isEmpty && declared.fingerprint != hash
    }
    .keys.sorted()

if writeBaselines {
    let versionFile = root.appendingPathComponent("corpus-version.json")
    guard
        let data = try? Data(contentsOf: versionFile),
        var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        var table = object["locales"] as? [String: [String: String]]
    else { fail("corpus-version.json is unreadable") }

    for (code, hash) in localeFingerprints {
        table[code] = [
            "version": declaredLocaleVersions[code]?.version ?? "1.0.0", "fingerprint": hash,
        ]
    }
    object["locales"] = table
    do {
        let out = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: versionFile)
    } catch {
        fail("could not record locale fingerprints: \(error)")
    }
    if !moved.isEmpty {
        print("  recorded new fingerprints for: \(moved.joined(separator: ", "))")
    }
} else if !moved.isEmpty {
    fail(
        "\(moved.count) locale(s) changed without a version bump: \(moved.joined(separator: ", "))"
            + "\n\nEach one's data moved while its entry in corpus-version.json stayed put. Bump"
            + " the version for the locales whose values actually changed -- adding data is a"
            + " minor bump, changing or removing an existing value is a major one -- then re-run"
            + " with --write-baselines to record the new fingerprints.")
}

// MARK: - Writing

// Only now, with every locale compiled and every version check passed, is the previous
// build replaced. Up to this point a failure leaves `out/` exactly as it was.
try? FileManager.default.removeItem(at: outDirectory)
do {
    try FileManager.default.createDirectory(
        at: outDirectory.appendingPathComponent("locales"), withIntermediateDirectories: true)
} catch {
    fail("could not create \(outDirectory.path): \(error)")
}
for (code, data) in pendingLocaleFiles {
    do {
        try data.write(to: outDirectory.appendingPathComponent("locales/\(code).json"))
    } catch {
        fail("could not write \(code).json: \(error)")
    }
}

// MARK: - Manifest

let manifest: [String: Any] = [
    "generator": "decoy adapters",
    "corpusVersion": corpusVersion,
    "sources": sourceOrder.compactMap { id -> [String: Any]? in
        guard let record = sourceRecords[id] else { return nil }
        return [
            "id": record.id, "license": record.license, "copyright": record.copyright,
            "url": record.url, "version": record.version, "retrieved": record.retrieved,
        ]
    },
    "keyTables": keyTables.sorted(),
    "locales": localeSummaries,
    "attribution": attribution,
    "localeCount": locales.count,
]

do {
    let data = try JSONSerialization.data(
        withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: outDirectory.appendingPathComponent("manifest.json"))
} catch {
    fail("could not write manifest.json: \(error)")
}

// MARK: - Report

let covered = locales.filter { (localeSummaries[$0]?["ownStrings"] as? Int ?? 0) > 0 }
print("corpus version  : \(corpusVersion)")
print("adapters run    : \(adapters.count)")
print("sources         : \(sourceOrder.joined(separator: ", "))")
print("locales in out  : \(locales.count)")
print("  with own data : \(covered.count)")
print("  empty         : \(locales.count - covered.count)")
print("strings written : \(totalStrings)")
print("name patterns   : \(namePatternCount) locales, from CLDR")
print("models trained  : \(modelCount) across \(modelLocales) locales")
print(
    "  refused       : \(tooSmall) below the training floor, "
        + "\(notViable.count) could not generate")
for reason in notViable.prefix(6) { print("      \(reason)") }
if notViable.count > 6 { print("      … \(notViable.count - 6) more") }
if !unscreened.isEmpty {
    let named = unscreened.prefix(8).joined(separator: ", ")
    print(
        "  no blocklist  : \(unscreened.count) locales "
            + "(\(named)\(unscreened.count > 8 ? ", …" : ""))")
}
