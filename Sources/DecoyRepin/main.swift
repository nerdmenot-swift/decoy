import DecoyAdapterKit
import Foundation

/// Re-pins an upstream that moved, and records why that was alright.
///
/// Before this existed, a moved upstream meant an hour of archaeology: fetch the file by
/// hand, find the old one in a cache, unzip both, diff the parts, decide, then edit a
/// digest into a descriptor and hope the rest of the pipeline agreed. That work is
/// identical every time, which is what a tool is for — and doing it by hand is also how a
/// re-pin ends up undocumented, because the reasoning stayed in somebody's terminal.
///
/// What it will not do is decide. A content change is shown and must be accepted explicitly
/// with a reason; a data change is refused outright, because adopting one is a corpus
/// version decision made in the builder with `--write-baselines`, not here.
///
///     decoy-repin --bootstrap              record content digests for every pinned artifact
///     decoy-repin <source>…                fetch, classify, and show what moved
///     decoy-repin <source> --refresh       adopt bytes whose content is unchanged
///     decoy-repin <source> --accept --note "…"
///                                          adopt a content change, recorded
///     decoy-repin --defer <source> --reason "…" [--days 90] [--change "…"]…
///                                          record a data change as deliberately not adopted
///     decoy-repin --list                   what is recorded, and what is in date

let arguments = Array(CommandLine.arguments.dropFirst())

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

let bootstrap = arguments.contains("--bootstrap")
let refresh = arguments.contains("--refresh")
let accept = arguments.contains("--accept")
let listing = arguments.contains("--list")
let defer_ = arguments.contains("--defer")
let note_ = value(for: "--note")
let reason = value(for: "--reason")
let days = Int(value(for: "--days") ?? "90") ?? 90

/// Repeatable: the value-level lines the check reported, so the ledger says what is being
/// waited on rather than only that something is.
let changeLines: [String] = arguments.enumerated()
    .filter { $0.element == "--change" && $0.offset + 1 < arguments.count }
    .map { arguments[$0.offset + 1] }

let flags = Set([
    "--bootstrap", "--refresh", "--accept", "--list", "--defer", "--note", "--reason", "--days",
    "--change",
])
var consumed = Set<Int>()
for (index, argument) in arguments.enumerated() where flags.contains(argument) {
    consumed.insert(index)
    if ["--note", "--reason", "--days", "--defer", "--change"].contains(argument) {
        consumed.insert(index + 1)
    }
}
let named = arguments.enumerated().filter { !consumed.contains($0.offset) }.map(\.element)
let deferred = value(for: "--defer")

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tools")
    .appendingPathComponent("adapters")

func say(_ line: String) { print(line) }
func fail(_ line: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + line + "\n").utf8))
    exit(1)
}

func today() -> String { stamp(Date()) }
func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}

var lock: UpstreamLock
do { lock = try UpstreamLock.load(from: root) } catch {
    fail("could not read \(UpstreamLock.filename): \(error)")
}

func descriptor(_ id: String) throws -> SourceDescriptor {
    try JSONDecoder().decode(
        SourceDescriptor.self,
        from: Data(contentsOf: root.appendingPathComponent("sources/\(id).json")))
}

func allSources() -> [String] {
    let files =
        (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("sources"), includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }
        .map { $0.deletingPathExtension().lastPathComponent }.sorted()
}

/// Rewrites one digest in a descriptor as text, never by re-serialising the JSON.
///
/// These files are written and read by people: `iana-tld` is indented with one space, every
/// other descriptor with two, and each carries paragraphs of prose about why its licence
/// says what it says. Round-tripping them through a JSON encoder would reformat all of that
/// to make a 88-character change.
func replace(in id: String, _ old: String, _ new: String) throws {
    let file = root.appendingPathComponent("sources/\(id).json")
    let text = try String(contentsOf: file, encoding: .utf8)
    guard text.contains(old) else {
        throw Failure.notFound("\(old) is not in sources/\(id).json")
    }
    try text.replacingOccurrences(of: old, with: new).write(
        to: file, atomically: true, encoding: .utf8)
}

enum Failure: Error, CustomStringConvertible {
    case notFound(String)
    var description: String {
        switch self {
        case .notFound(let what): return what
        }
    }
}

let store = ArtifactStore(root: root)

/// The bytes an upstream serves now, with no pin applied.
func current(_ artifact: SourceDescriptor.Artifact, source: String) async throws -> (
    bytes: [UInt8], file: URL
) {
    let bytes = try await store.fetch(artifact.url)
    let scratch = store.cacheDirectory.appendingPathComponent(
        "\(source)-\(artifact.cacheSuffix).repin")
    try FileManager.default.createDirectory(
        at: store.cacheDirectory, withIntermediateDirectories: true)
    try Data(bytes).write(to: scratch)
    return (bytes, scratch)
}

func digest(_ bytes: [UInt8], _ artifact: SourceDescriptor.Artifact) -> String {
    Integrity.digest(Integrity.normalised(bytes, ignoringLinesMatching: artifact.ignoreLinesMatching))
}

// MARK: - --list

if listing {
    let sources = allSources()
    var recorded = 0
    for id in sources {
        guard let source = try? descriptor(id) else { continue }
        for artifact in source.artifacts ?? [] {
            let key = UpstreamLock.key(source: id, artifact: artifact.name)
            if let entry = lock.entries[key] {
                recorded += 1
                say(
                    "  \(key): \(entry.view) recorded \(entry.reviewedAt ?? "—")"
                        + (entry.note.map { " — \($0)" } ?? ""))
            } else if let kind = ContentView.kind(for: artifact) {
                say("  \(key): \(kind.rawValue) available, NOT recorded")
            } else {
                say("  \(key): no content view — a byte change will be fatal")
            }
        }
    }
    say("")
    say("\(recorded) artifacts carry a content digest.")
    if lock.deferrals.isEmpty {
        say("no deferred data changes.")
    } else {
        for (source, record) in lock.deferrals.sorted(by: { $0.key < $1.key }) {
            let state = today() > record.expires ? "EXPIRED" : "in date"
            say(
                "deferred \(source): \(state), seen \(record.firstSeen), adopt by "
                    + "\(record.expires) — \(record.reason)")
            for line in record.change.prefix(6) { say("    \(line)") }
        }
    }
    exit(0)
}

// MARK: - --defer

if defer_ {
    guard let source = deferred else { fail("--defer needs a source id") }
    guard let reason, !reason.isEmpty else {
        fail("--defer needs --reason: a deferral nobody explained is a deferral nobody revisits")
    }
    guard (try? descriptor(source)) != nil else { fail("no such source: \(source)") }

    let expires = stamp(Date().addingTimeInterval(Double(days) * 86_400))
    let existing = lock.deferrals[source]
    lock.deferrals[source] = UpstreamLock.Deferral(
        source: source, firstSeen: existing?.firstSeen ?? today(), expires: expires,
        reason: reason, change: changeLines.isEmpty ? (existing?.change ?? []) : changeLines)
    do { try lock.write(to: root) } catch { fail("could not write the lock: \(error)") }
    say("deferred \(source) until \(expires).")
    say("")
    say(
        "The upstream check will report it as known until then, and fail after. Adopting it "
            + "later means re-pinning, re-running the builder with --write-baselines, and "
            + "bumping the corpus version the diff names.")
    exit(0)
}

// MARK: - --bootstrap

if bootstrap {
    var recorded = 0
    var skipped: [String] = []
    for id in allSources() {
        guard let source = try? descriptor(id) else { continue }
        for artifact in source.artifacts ?? [] {
            let key = UpstreamLock.key(source: id, artifact: artifact.name)
            guard ContentView.kind(for: artifact) != nil else {
                skipped.append("\(key): no view for its format")
                continue
            }
            // Only ever recorded from bytes that satisfy the pin. Bootstrapping from
            // whatever an upstream happens to serve today would record the unreviewed
            // present as the reviewed past.
            let file: URL
            do {
                file = try await store.acquire(artifact, source: id, log: { _ in }).file
            } catch {
                skipped.append("\(key): \(error)")
                continue
            }
            do {
                let rendering = try ContentView.render(file, artifact: artifact, source: id)
                let bytes = digest([UInt8](try Data(contentsOf: file)), artifact)
                lock.entries[key] = UpstreamLock.Entry(
                    content: rendering.digest, view: rendering.kind.rawValue, bytes: bytes,
                    reviewedAt: today(),
                    note: "recorded from the pinned bytes (\(rendering.shape))")
                recorded += 1
                say("  \(key): \(rendering.kind.rawValue), \(rendering.shape)")
            } catch {
                skipped.append("\(key): \(error)")
            }
        }
    }
    do { try lock.write(to: root) } catch { fail("could not write the lock: \(error)") }
    say("")
    say("recorded \(recorded) content digests.")
    for line in skipped { say("  skipped \(line)") }
    say("")
    say("Artifacts with no content view keep the old behaviour: a byte change is fatal.")
    exit(0)
}

// MARK: - Re-pinning named sources

guard !named.isEmpty else {
    say("usage: decoy-repin <source>… [--refresh | --accept --note \"…\"]")
    say("       decoy-repin --bootstrap | --list | --defer <source> --reason \"…\" [--days 90]")
    exit(2)
}

var changed = false
for id in named {
    let source: SourceDescriptor
    do { source = try descriptor(id) } catch { fail("no such source: \(id) (\(error))") }

    for artifact in source.artifacts ?? [] {
        let key = UpstreamLock.key(source: id, artifact: artifact.name)
        say("\(key)")
        say("  \(artifact.url)")

        let fetched: (bytes: [UInt8], file: URL)
        do { fetched = try await current(artifact, source: id) } catch {
            say("  unreachable: \(error)")
            continue
        }
        defer { try? FileManager.default.removeItem(at: fetched.file) }

        let pinned = (try? Integrity.Expectation(artifact.integrity))?.expected ?? ""
        let actual = digest(fetched.bytes, artifact)
        if actual == pinned {
            say("  unchanged: the pinned bytes are what it serves.")
            continue
        }

        guard let kind = ContentView.kind(for: artifact) else {
            say("  bytes moved, and there is no content view for this format.")
            say("    pinned sha512-\(pinned)")
            say("    actual sha512-\(actual)")
            guard accept, let note_, !note_.isEmpty else {
                say("  nothing recorded. Review it by hand, then --accept --note \"…\".")
                continue
            }
            try? replace(in: id, "sha512-\(pinned)", "sha512-\(actual)")
            lock.entries[key] = UpstreamLock.Entry(
                content: "", view: "none", bytes: actual, reviewedAt: today(), note: note_)
            changed = true
            say("  accepted on your word, with no content check: \(note_)")
            continue
        }

        let rendering: ContentView.Rendering
        do {
            rendering = try ContentView.render(fetched.file, artifact: artifact, source: id)
        } catch {
            say("  bytes moved, and the file will not render as \(kind.rawValue): \(error)")
            say("  refusing to re-pin something this cannot read.")
            continue
        }

        let entry = lock.entries[key]
        if let entry, entry.content == rendering.digest, entry.view == rendering.kind.rawValue {
            say("  content unchanged (\(rendering.kind.rawValue), \(rendering.shape)).")
            say("  only the container's own metadata moved; the pin is stale.")
            guard refresh else {
                say("  re-run with --refresh to adopt the new bytes.")
                continue
            }
            try? replace(in: id, "sha512-\(pinned)", "sha512-\(actual)")
            lock.entries[key] = UpstreamLock.Entry(
                content: entry.content, view: entry.view, bytes: actual,
                reviewedAt: entry.reviewedAt, note: entry.note)
            changed = true
            say("  pin refreshed. No value changes, so nothing else needs regenerating.")
            continue
        }

        say("  content changed (\(rendering.kind.rawValue), now \(rendering.shape)).")
        // The previous rendering is kept beside the cache by a build, so a local re-pin can
        // diff two documents. CI has no cache on the weekly run and sees digests only.
        let previous = store.cacheDirectory.appendingPathComponent(
            "\(id)-\(artifact.cacheSuffix).view")
        if let before = try? String(contentsOf: previous, encoding: .utf8) {
            let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let new = rendering.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let removed = Set(old).subtracting(new).sorted()
            let added = Set(new).subtracting(old).sorted()
            say("  \(old.count) → \(new.count) lines of canonical content")
            for line in removed.prefix(10) { say("    - \(line.prefix(160))") }
            if removed.count > 10 { say("    - … \(removed.count - 10) more removed") }
            for line in added.prefix(10) { say("    + \(line.prefix(160))") }
            if added.count > 10 { say("    + … \(added.count - 10) more added") }
        } else {
            say("  no previous rendering cached, so this can only compare digests:")
            say("    recorded sha512-\(entry?.content ?? "—")")
            say("    now      sha512-\(rendering.digest)")
            say("  run a build first to cache the old rendering if you want a line diff.")
        }

        guard accept, let note_, !note_.isEmpty else {
            say("")
            say(
                "  nothing recorded. If this change is legitimate, re-run with --accept "
                    + "--note \"what moved\".")
            continue
        }

        try? replace(in: id, "sha512-\(pinned)", "sha512-\(actual)")
        lock.entries[key] = UpstreamLock.Entry(
            content: rendering.digest, view: rendering.kind.rawValue, bytes: actual,
            reviewedAt: today(), note: note_)
        changed = true
        say("  accepted and recorded: \(note_)")
        say(
            "  if this descriptor's version or retrieved date is transcribed from the "
                + "document, update it too — this tool does not guess at provenance.")
    }
}

if changed {
    do { try lock.write(to: root) } catch { fail("could not write the lock: \(error)") }
    say("")
    say("Lock updated. Re-run the builder: if the extracted values moved it will refuse, and")
    say("that refusal is the corpus version decision, not this.")
}
