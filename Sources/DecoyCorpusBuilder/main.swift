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

/// `--check-upstreams` asks only "have our upstreams moved", and writes nothing.
///
/// The weekly job used to answer that question by rebuilding the corpus, which conflated it
/// with "does this repository still work" and put a moved upstream on the CI badge. They are
/// different questions with different audiences: one is answered by the committed corpus on
/// every push, the other by fifty-four third parties on their own schedule.
///
/// In this mode every artifact is still fetched and verified, every adapter still runs, and
/// the extracted data is still compared against `parity/` — so the report is as precise as a
/// build's. What it does not do is produce a corpus, which is what let the two apart.
let checkUpstreams = arguments.contains("--check-upstreams")

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
let declaredLocaleVersions: [String: (version: String, fingerprint: String, at: String)] = {
    guard
        let data = try? Data(
            contentsOf: root.appendingPathComponent("corpus-version.json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { fail("corpus-version.json is unreadable") }

    guard let table = object["locales"] as? [String: [String: String]] else {
        fail("corpus-version.json declares no `locales` table")
    }
    var out: [String: (version: String, fingerprint: String, at: String)] = [:]
    for (code, entry) in table {
        guard let version = entry["version"] else {
            fail("corpus-version.json: \(code) declares no version")
        }
        // `at` is the version the fingerprint was recorded against, which is what makes
        // "the data moved and nobody bumped" distinguishable from "the data moved and
        // somebody did". Defaults to the declared version so a file written before this
        // existed reads as already-in-agreement.
        out[code] = (version, entry["fingerprint"] ?? "", entry["fingerprintAt"] ?? version)
    }
    return out
}()

/// What each locale's data hashed to this run, filled as locales are compiled.
var localeFingerprints: [String: String] = [:]

/// What every adapter's filters discarded, collected for `Tools/adapters/filters.json`.
var discardsByAdapter: [String: [DiscardRecord]] = [:]

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

/// Content digests and recorded decisions. See `UpstreamLock`.
let lock: UpstreamLock
do { lock = try UpstreamLock.load(from: root) } catch {
    fail("could not read \(UpstreamLock.filename): \(error)")
}

/// Upstreams whose bytes moved while everything the document states stayed put.
var acceptedDrift: [ArtifactStore.Drift] = []
/// Set while the check mode is measuring what a refused upstream would do to the data.
///
/// Scoped to the one phase that needs it: the preflight verifies for real, and only the
/// adapter pass that follows it in `--check-upstreams` analyses. A normal build never sets
/// it, so unverified bytes cannot reach a corpus.
var analysing = false

/// Upstreams that did not verify, collected rather than fatal on the first one.
///
/// Three Mondays in a row failed on three different sources, one per week, because the
/// build stopped at the first. Collecting them means one run says everything it knows.
var upstreamFailures: [(source: String, error: any Error)] = []

func today() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: Date())
}

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

/// Sources already resolved this run, so that nothing is fetched or unpacked twice.
///
/// Both the preflight and the adapters ask for the same sources, and before this a check
/// run fetched all fifty-four of them twice — once to verify, once to use. The second pass
/// also re-read the cache, which in check mode is deliberately bypassed, so it would have
/// measured the data against whatever was already on disk rather than against what the
/// upstream now serves.
var resolvedSources: [String: [String: URL]] = [:]
var refusedSources: [String: any Error] = [:]

/// Acquires, verifies and unpacks every artifact a source declares, and registers its
/// provenance.
@MainActor func load(_ id: String) async throws -> [String: URL] {
    if let resolved = resolvedSources[id] { return resolved }
    if let refused = refusedSources[id] { throw refused }
    let source = try descriptor(id)

    var artifacts: [String: URL] = [:]
    for artifact in source.artifacts ?? [] {
        let acquired = try await store.acquire(
            artifact, source: id, lock: lock, allowingUnverified: analysing,
            // Checking means asking the upstream, not the cache. A build reads the cache,
            // because a cached copy that satisfies the pin is the pinned file.
            ignoringCache: checkUpstreams, attempts: checkUpstreams ? 3 : 6,
            deadline: 180, log: note)
        if acquired.unverified {
            note("  \(artifact.name): unverified bytes, for measurement only")
        }
        if let drift = acquired.drift {
            acceptedDrift.append(drift)
            note(
                "  \(drift.artifact): bytes moved, content unchanged (\(drift.view), "
                    + "\(drift.shape))")
        }
        artifacts[artifact.name] = try store.materialise(
            artifact, at: acquired.file, source: id)
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
    resolvedSources[id] = artifacts
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

// MARK: - Preflight
//
// Every artifact is acquired and verified before any adapter runs, so that a run reports
// every upstream that moved instead of the first one. In check mode the net is wider: every
// descriptor on disk, whether or not an enabled adapter names it, because "is this upstream
// still published" is a question about all of them.
let preflightSources: [String] = {
    if checkUpstreams {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("sources"), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }
    var seen = Set<String>()
    return adapters.flatMap(\.adapterSources).filter { seen.insert($0).inserted }
}()

for sourceID in preflightSources {
    do { _ = try await load(sourceID) } catch {
        upstreamFailures.append((sourceID, error))
        // Remembered so the adapter pass neither re-fetches it nor reports it twice. In
        // check mode the adapters run anyway, against the unverified bytes, which is what
        // turns "SIX republished" into "two entries gained an attribute nobody reads".
        refusedSources[sourceID] = error
    }
}

// The refusals above were verdicts on verified bytes. Measuring what they would do to the
// data means asking again, this time accepting what arrives — so the memo is cleared for
// exactly those sources and exactly that purpose.
if checkUpstreams { refusedSources.removeAll() }

if !upstreamFailures.isEmpty, !checkUpstreams {
    note("")
    for failure in upstreamFailures { note("error: \(failure.error)") }
    fail(
        "\(upstreamFailures.count) upstream\(upstreamFailures.count == 1 ? "" : "s") did not "
            + "verify. Nothing was built.")
}

// The preflight has already reported what failed. From here the check mode measures rather
// than verifies, so that a refused upstream still yields "and this is what it would change".
if checkUpstreams { analysing = true }

var contributions: [Orchestrator.Contribution] = []

/// Extracted data that no longer matches what `parity/` recorded.
///
/// Tier one, and the only one of the three that is a decision about the corpus: a value
/// added, removed or changed moves every fixture drawn from it.
var dataChanges: [(adapter: String, sources: [String], lines: [String])] = []

/// What `parity/<id>.json` recorded for an adapter, as definitions.
@MainActor func baseline(_ id: String) -> [String: [String: Definition]]? {
    let url = baselineDirectory.appendingPathComponent("\(id).json")
    guard let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let raw = object["contributions"] as? [String: [String: Any]]
    else { return nil }
    return raw.mapValues { $0.mapValues(Definition.init(json:)) }
}

/// The value-level difference between an adapter's output and its baseline.
///
/// Phrased as gains and losses rather than as "first divergence", because the question a
/// reader has is which values moved: `-JUNIPER` is the whole story of a retired TLD, and an
/// index into two lists is not.
func dataDifference(
    _ now: [String: [String: Definition]], _ before: [String: [String: Definition]]
) -> [String] {
    var lines: [String] = []
    for locale in Set(now.keys).union(before.keys).sorted() {
        let mine = now[locale] ?? [:]
        let theirs = before[locale] ?? [:]
        for path in Set(mine.keys).union(theirs.keys).sorted() {
            guard let a = mine[path] else {
                lines.append("\(locale).\(path): gone")
                continue
            }
            guard let b = theirs[path] else {
                lines.append("\(locale).\(path): new")
                continue
            }
            guard a != b else { continue }
            if case .list(let now) = a, case .list(let before) = b {
                let added = now.filter { !before.contains($0) }
                let removed = before.filter { !now.contains($0) }
                let summary =
                    (removed.prefix(5).map { "-\(compactValue($0))" }
                        + added.prefix(5).map { "+\(compactValue($0))" })
                    .joined(separator: " ")
                let more = (added.count + removed.count) > 10 ? " …" : ""
                lines.append(
                    "\(locale).\(path): \(before.count) → \(now.count) entries"
                        + (summary.isEmpty ? "" : " (\(summary)\(more))"))
            } else {
                lines.append("\(locale).\(path): changed")
            }
        }
    }
    return lines
}

/// A value in a few characters, for a report line.
func compactValue(_ value: Definition) -> String {
    switch value {
    case .string(let text): return text.count > 40 ? String(text.prefix(40)) + "…" : text
    case .number(let number): return String(number)
    case .bool(let flag): return String(flag)
    case .null: return "null"
    case .list(let items): return "[\(items.count)]"
    case .object(let fields):
        return "{" + fields.keys.sorted().prefix(3).joined(separator: ",") + "}"
    }
}

for adapter in adapters {
    let id = adapter.adapterID
    let sources = adapter.adapterSources
    note("adapter \(id) (\(sources.joined(separator: " + ")))")

    var artifacts: [String: URL] = [:]
    var unverified = false
    for sourceID in sources {
        let loaded: [String: URL]
        do { loaded = try await load(sourceID) } catch {
            // In check mode a source that cannot be read at all — unreachable, or bytes
            // that will not parse — is the finding, not a crash: the other fifty-three
            // still have to be reported.
            guard !checkUpstreams else {
                note("  skipped: \(sourceID) could not be read")
                refusedSources[sourceID] = error
                unverified = true
                continue
            }
            fail("\(id): \(error)")
        }
        for (name, path) in loaded {
            guard artifacts[name] == nil else {
                fail("\(id): two of its sources both name an artifact '\(name)'")
            }
            artifacts[name] = path
        }
    }
    if unverified { continue }

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

    // Tier one. The baseline is what this adapter last emitted; a difference here is data,
    // and data is a corpus decision rather than a re-pin.
    if !writeBaselines, let before = baseline(id) {
        let lines = dataDifference(output.contributions.mapValues { $0 }, before)
        if !lines.isEmpty {
            dataChanges.append((adapter: id, sources: sources, lines: lines))
            for line in lines.prefix(8) { note("  data: \(line)") }
            if lines.count > 8 { note("  data: … \(lines.count - 8) more") }
        }
    }

    // What this adapter's filters threw away, kept for `filters.json`. The heaviest losses
    // go to the log as well: a filter keeping a tenth of what it saw is either doing its
    // job on a dirty source or has stopped understanding the data, and those two look
    // identical in a total.
    for record in output.discarded {
        discardsByAdapter[id, default: []].append(record)
        if record.seen >= 20, record.kept * 4 < record.seen {
            note("  \(record.scope) \(record.filter): kept \(record.kept) of \(record.seen)")
        }
    }

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

// MARK: - The upstream verdict
//
// Three tiers, reported together. Only the first is a decision about the corpus; the second
// needs a human to look once; the third is noise that has been proven to be noise.

/// A deferral that covers `sources`, if one is on record and still in date.
func deferral(for sources: [String]) -> UpstreamLock.Deferral? {
    sources.compactMap { lock.deferrals[$0] }.first
}

if checkUpstreams {
    note("")
    note("upstream check: \(preflightSources.count) descriptors")

    var verdict = 0

    for drift in acceptedDrift {
        note(
            "  stale pin  \(drift.source)/\(drift.artifact): content unchanged "
                + "(\(drift.view), \(drift.shape)) — refresh with `decoy-repin "
                + "\(drift.source) --refresh`")
    }

    for failure in upstreamFailures {
        if let record = lock.deferrals[failure.source] {
            if today() > record.expires {
                note(
                    "  EXPIRED    \(failure.source): deferred on \(record.firstSeen) until "
                        + "\(record.expires), which has passed — \(record.reason)")
                verdict = 1
            } else {
                note(
                    "  deferred   \(failure.source): known change, adopt by \(record.expires) "
                        + "— \(record.reason)")
            }
            continue
        }
        // "Did not answer" and "answered with something else" are different findings with
        // different remedies, and reading the first as the second is how a flaky server
        // comes to look like a republication.
        let unreachable: Bool = {
            guard let failure = failure.error as? ArtifactStore.Failure else { return false }
            if case .unreachable = failure { return true }
            return false
        }()
        note("  \(unreachable ? "UNREACHABLE" : "CHANGED    ") \(failure.source)")
        for line in "\(failure.error)".split(separator: "\n") { note("             \(line)") }
        verdict = 1
    }

    for change in dataChanges {
        if let record = deferral(for: change.sources), today() <= record.expires {
            note(
                "  deferred   \(change.adapter): data change recorded, adopt by "
                    + "\(record.expires)")
            continue
        }
        note("  DATA       \(change.adapter): the extracted values moved")
        for line in change.lines.prefix(12) { note("             \(line)") }
        if change.lines.count > 12 { note("             … \(change.lines.count - 12) more") }
        verdict = 1
    }

    // An expired deferral fails even when its upstream verified this week, because the thing
    // that expired is the promise to come back to it.
    for (source, record) in lock.deferrals.sorted(by: { $0.key < $1.key })
    where today() > record.expires && !upstreamFailures.contains(where: { $0.source == source })
        && !dataChanges.contains(where: { $0.sources.contains(source) })
    {
        note(
            "  EXPIRED    \(source): deferred until \(record.expires), which has passed — "
                + "\(record.reason)")
        verdict = 1
    }

    if verdict == 0 {
        note("")
        note(
            "nothing to report: every upstream matches what was recorded, or differs only in "
                + "container metadata.")
    }
    exit(Int32(verdict))
}

if !dataChanges.isEmpty {
    note("")
    for change in dataChanges {
        note("error: \(change.adapter): extracted values moved against parity/\(change.adapter).json")
        for line in change.lines.prefix(12) { note("  \(line)") }
        if change.lines.count > 12 { note("  … \(change.lines.count - 12) more") }
    }
    fail(
        "the corpus data would change. That is a corpus version decision, not a re-pin: read "
            + "the diff, then re-run with --write-baselines and bump the versions it names.")
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
    // Recording is not a way around the check. `--write-baselines` exists to accept a
    // change once it is deliberate, and the evidence that it is deliberate is a version
    // bump — so a locale whose data moved while its version stayed put is refused here
    // exactly as it is on a plain build.
    //
    // Without this the gate is a formality: run with `--write-baselines`, the new
    // fingerprints are recorded, the versions stay at whatever they were, and every
    // subsequent build agrees that nothing is wrong. Which is what happened the first time
    // this feature was used, an hour after it was written, by its author.
    let unbumped = moved.filter { code in
        guard let declared = declaredLocaleVersions[code] else { return false }
        return declared.version == declared.at
    }
    if !unbumped.isEmpty {
        fail(
            "\(unbumped.count) locale(s) changed but still declare their old version: "
                + unbumped.joined(separator: ", ")
                + "\n\nBump each one in corpus-version.json first -- adding data is a minor bump,"
                + " changing or removing an existing value is a major one -- then re-run with"
                + " --write-baselines to record the fingerprints against the new versions.")
    }

    let versionFile = root.appendingPathComponent("corpus-version.json")
    guard
        let data = try? Data(contentsOf: versionFile),
        var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        var table = object["locales"] as? [String: [String: String]]
    else { fail("corpus-version.json is unreadable") }

    for (code, hash) in localeFingerprints {
        let version = declaredLocaleVersions[code]?.version ?? "1.0.0"
        table[code] = ["version": version, "fingerprint": hash, "fingerprintAt": version]
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

// MARK: - What the filters threw away

// Committed, and therefore diffable. A filter that begins rejecting far more than it used
// to shows up here as a changed number in review, which is the only mechanism that would
// have caught any of the three that shipped: a length floor deleting 138 of 143 Korean
// surnames, a count floor discarding 13 Welsh ones, and a retry recording Spanish surnames
// as absent because the query never once succeeded.
//
// Sorted, and holding only counts, so the file is a record of behaviour rather than a
// second copy of the corpus. It is regenerated on every build like the parity dumps, and
// CI diffs it for the same reason.
do {
    var report: [String: Any] = [:]
    for (adapter, records) in discardsByAdapter {
        var byScope: [String: [String: Any]] = [:]
        for record in records.sorted(by: { ($0.scope, $0.filter) < ($1.scope, $1.filter) }) {
            byScope[record.scope, default: [:]][record.filter] = [
                "kept": record.kept, "seen": record.seen,
            ]
        }
        report[adapter] = byScope
    }
    let data = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: root.appendingPathComponent("filters.json"))
} catch {
    fail("could not write filters.json: \(error)")
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
