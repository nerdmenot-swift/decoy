import Foundation

/// Resolves a pinned artifact to a file on disk: cache, then vendor, then the network.
///
/// The order is deliberate. A cached copy is
/// re-verified rather than trusted — a corrupted or tampered cache would otherwise produce
/// a corpus that passes every check on the machine that built it and nowhere else.
public struct ArtifactStore: Sendable {

    public enum Failure: Error, CustomStringConvertible {
        case unreachable(url: String, attempts: Int, last: String)
        case vendoredMismatch(path: String)
        case extractionFailed(archive: String, format: String, tool: String?, detail: String)
        /// The bytes moved and so did what the document states.
        case contentChanged(
            source: String, artifact: String, url: String, view: String, shape: String,
            actualBytes: String, actualContent: String)
        /// The bytes moved and this pipeline cannot say whether it matters.
        case uncharacterised(
            source: String, artifact: String, url: String, actualBytes: String, reason: String)

        public var description: String {
            switch self {
            case .unreachable(let url, let attempts, let last):
                return "\(url) failed after \(attempts) attempts — \(last)"
            case .vendoredMismatch(let path):
                return
                    "integrity mismatch for vendored \(path)\n"
                    + "Re-vendor from the pinned URL, or delete the file to fetch it."
            case .contentChanged(
                let source, let artifact, let url, let view, let shape, let actualBytes,
                let actualContent):
                return """
                    \(source)/\(artifact): upstream content changed at \(url)
                      the bytes moved and so did what the document states (\(view), \(shape))
                      bytes   sha512-\(actualBytes)
                      content sha512-\(actualContent)
                    This is not a re-issue. Review it with `decoy-repin \(source)`, which shows \
                    what changed and records the decision.
                    """

            case .uncharacterised(
                let source, let artifact, let url, let actualBytes, let reason):
                return """
                    \(source)/\(artifact): upstream changed at \(url)
                      bytes sha512-\(actualBytes)
                      cannot tell whether the content moved: \(reason)
                    Refusing to guess. Review it with `decoy-repin \(source)`.
                    """

            case .extractionFailed(let archive, let format, let tool, let detail):
                guard let tool else {
                    return "could not unpack \(archive) (\(format))\n\(detail)"
                }
                let package = tool == "xz" ? "xz-utils" : tool
                return
                    "could not unpack \(archive) (\(format)): `\(tool)` is not installed.\n"
                    + "Install it (Debian/Ubuntu: apt-get install -y \(package); macOS: "
                    + "preinstalled) and re-run."
            }
        }
    }

    /// A non-2xx answer, carried out of the raced fetch so the retry rules still apply.
    struct Status: Error { let code: Int }

    public let root: URL
    public var cacheDirectory: URL { root.appendingPathComponent(".cache") }
    public var vendorDirectory: URL { root.appendingPathComponent("vendor") }

    public init(root: URL) { self.root = root }

    /// A byte pin held, or a content-only change accepted.
    ///
    /// `pinned` is the ordinary answer. `contentUnchanged` is the one deliberate loosening
    /// in this pipeline: the bytes are not the recorded ones, but the file was parsed and
    /// everything it states is identical to what was recorded, so the difference is the
    /// container's own metadata and cannot reach the corpus. It is reported, never silent.
    public enum Acceptance: Sendable {
        case pinned
        case contentUnchanged(Drift)
    }

    /// Where the bytes came from, and whether a content-only change was accepted.
    public struct Acquisition: Sendable {
        public let file: URL
        /// Non-nil when the pinned bytes were not what arrived, but the content was.
        public let drift: Drift?
        /// True only under `allowingUnverified`, where bytes that failed every check are
        /// handed over anyway so that their effect on the data can be measured.
        public let unverified: Bool

        public init(file: URL, drift: Drift?, unverified: Bool = false) {
            self.file = file
            self.drift = drift
            self.unverified = unverified
        }
    }

    public struct Drift: Sendable {
        public let source: String
        public let artifact: String
        public let url: String
        public let view: String
        public let pinnedBytes: String
        public let actualBytes: String
        public let shape: String
    }

    /// A file path holding verified bytes for `artifact`.
    ///
    /// `lock` supplies the content digests that make the middle verdict possible. Without
    /// one — an empty lock, or an artifact nobody has recorded — a byte mismatch is fatal,
    /// which is the behaviour this had before content views existed.
    /// `allowingUnverified` hands over bytes that failed verification, for analysis only.
    ///
    /// The upstream check needs to answer "and what would that do to the data" about a file
    /// it has just refused — which is the difference between "SIX republished" and "two
    /// entries gained an attribute nobody reads". Measuring that means running the adapter
    /// over bytes no pin covers, so this is deliberately awkward to reach: one caller passes
    /// it, in a mode that exits before anything is written, and the returned `Acquisition`
    /// says `unverified` so a caller cannot forget which it got.
    public func acquire(
        _ artifact: SourceDescriptor.Artifact,
        source: String,
        lock: UpstreamLock = UpstreamLock(),
        allowingUnverified: Bool = false,
        ignoringCache: Bool = false,
        /// Fewer when the answer is a report rather than a build: six attempts over two
        /// minutes is the right patience for a build that needs the bytes, and the wrong
        /// one for a check that only has to say "this did not answer" — fifty-four sources
        /// each waiting out a dead host would spend the job's whole budget on silence.
        attempts: Int = 6,
        /// The wall-clock cap on one attempt. Shorter for a check, for the same reason.
        deadline: Int = 180,
        log: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async throws -> Acquisition {
        let expectation = try Integrity.Expectation(artifact.integrity)
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
        let cached = cacheDirectory.appendingPathComponent("\(source)-\(artifact.cacheSuffix)")

        let matches = { (bytes: [UInt8]) in
            Integrity.digest(
                Integrity.normalised(bytes, ignoringLinesMatching: artifact.ignoreLinesMatching))
                == expectation.expected
        }

        // The upstream check asks what a publisher is serving now, so it passes
        // `ignoringCache`. Answering that question from a cache is how a check goes green on
        // a URL that 404'd a month ago — the scheduled CI job worked around it by throwing
        // its runner cache away, which only worked on CI and not for anybody running the
        // same command locally.
        if let data = try? Data(contentsOf: cached), !ignoringCache {
            if matches([UInt8](data)) { return Acquisition(file: cached, drift: nil) }
            // A cached copy that is not the pinned bytes gets the same three-way reading as
            // a fetched one, except that a verdict of "changed" falls through to the network
            // rather than failing: the cache is the more likely thing to be stale.
            if case .contentUnchanged(let drift) = (try? verdict(
                for: cached, artifact: artifact, source: source, lock: lock)) ?? .pinned
            {
                return Acquisition(file: cached, drift: drift)
            }
            try? FileManager.default.removeItem(at: cached)
        }

        // A vendored copy, for upstreams no build machine can reach. Two of the fifty-one
        // are in that state: one answers 403 from its load balancer, the other answers
        // HTTP 200 with a rejection page. The hash below still decides whether the bytes
        // are right, so this changes where a file comes from and not whether it is checked.
        let vendored = vendorDirectory.appendingPathComponent("\(source)-\(artifact.cacheSuffix)")
        if let data = try? Data(contentsOf: vendored) {
            guard matches([UInt8](data)) else {
                throw Failure.vendoredMismatch(path: vendored.path)
            }
            log("  vendored \(source)/\(artifact.name)")
            try data.write(to: cached)
            return Acquisition(file: cached, drift: nil)
        }

        log("  fetching \(artifact.url)")
        let bytes = try await fetch(artifact.url, attempts: attempts, deadline: deadline)
        if matches(bytes) {
            try Data(bytes).write(to: cached)
            return Acquisition(file: cached, drift: nil)
        }

        // Not the pinned bytes. Write them where a view can be rendered from them, then let
        // the content decide: unchanged content is accepted and reported, changed or
        // unreadable content is refused with what is known about it.
        let candidate = cacheDirectory.appendingPathComponent(
            "\(source)-\(artifact.cacheSuffix).candidate")
        try Data(bytes).write(to: candidate)
        defer { try? FileManager.default.removeItem(at: candidate) }

        let reading: Acceptance
        do {
            reading = try verdict(for: candidate, artifact: artifact, source: source, lock: lock)
        } catch {
            guard allowingUnverified else { throw error }
            // Kept apart from the cache, which only ever holds bytes that satisfied a pin.
            let unverified = cacheDirectory.appendingPathComponent(
                "\(source)-\(artifact.cacheSuffix).unverified")
            try Data(bytes).write(to: unverified)
            return Acquisition(file: unverified, drift: nil, unverified: true)
        }

        switch reading {
        case .pinned:
            // Only reachable if the pin itself matched, which `matches` just denied.
            try Data(bytes).write(to: cached)
            return Acquisition(file: cached, drift: nil)
        case .contentUnchanged(let drift):
            try Data(bytes).write(to: cached)
            return Acquisition(file: cached, drift: drift)
        }
    }

    /// The three-way reading of a file whose bytes are not the pinned ones.
    ///
    /// Throws for both refusing verdicts, so a caller cannot accidentally treat "changed"
    /// as a value it may ignore.
    func verdict(
        for file: URL, artifact: SourceDescriptor.Artifact, source: String, lock: UpstreamLock
    ) throws -> Acceptance {
        let bytes = (try? Data(contentsOf: file)).map { [UInt8]($0) } ?? []
        let actualBytes = Integrity.digest(
            Integrity.normalised(bytes, ignoringLinesMatching: artifact.ignoreLinesMatching))
        let pinned = (try? Integrity.Expectation(artifact.integrity))?.expected ?? ""
        if actualBytes == pinned { return .pinned }

        let key = UpstreamLock.key(source: source, artifact: artifact.name)
        guard let entry = lock.entries[key] else {
            throw Failure.uncharacterised(
                source: source, artifact: artifact.name, url: artifact.url,
                actualBytes: actualBytes,
                reason: "no content digest has ever been recorded for it")
        }

        let rendering: ContentView.Rendering
        do {
            rendering = try ContentView.render(file, artifact: artifact, source: source)
        } catch {
            throw Failure.uncharacterised(
                source: source, artifact: artifact.name, url: artifact.url,
                actualBytes: actualBytes, reason: "\(error)")
        }

        guard rendering.kind.rawValue == entry.view else {
            throw Failure.uncharacterised(
                source: source, artifact: artifact.name, url: artifact.url,
                actualBytes: actualBytes,
                reason: "recorded under \(entry.view), rendered as \(rendering.kind.rawValue) — "
                    + "re-record it")
        }

        // The canonical rendering is kept beside the cache, uncommitted, so that a local
        // re-pin can diff the document rather than only compare digests. CI's scheduled run
        // has no cache by design and gets the digest-level report instead; the value-level
        // one it needs comes from the parity baselines further down the build.
        try? Data(rendering.text.utf8).write(
            to: cacheDirectory.appendingPathComponent(
                "\(source)-\(artifact.cacheSuffix).view"))

        guard rendering.digest == entry.content else {
            throw Failure.contentChanged(
                source: source, artifact: artifact.name, url: artifact.url,
                view: rendering.kind.rawValue, shape: rendering.shape, actualBytes: actualBytes,
                actualContent: rendering.digest)
        }

        return .contentUnchanged(
            Drift(
                source: source, artifact: artifact.name, url: artifact.url,
                view: rendering.kind.rawValue, pinnedBytes: pinned, actualBytes: actualBytes,
                shape: rendering.shape))
    }

    /// Fetches, retrying the failures that are the network rather than the server.
    ///
    /// A 4xx is not retried: that is the server saying the request is wrong — a moved file,
    /// a revoked dataset — and asking again does not change the answer. 5xx and transport
    /// failures are, because those come right on their own. The integrity hash
    /// still decides whether what arrives is correct; this only decides how often to ask.
    /// Races `work` against the clock, so that a slow answer cannot become no answer.
    ///
    /// `URLRequest.timeoutInterval` bounds silence, not duration: a server that trickles
    /// bytes resets it indefinitely. The CBS held a check run for ten minutes that way,
    /// which on CI would have been the job timeout — an hour spent to report nothing. A
    /// deadline is the only thing that bounds the case where the upstream is answering,
    /// just not usefully.
    /// A deadline that expired. Its own type, because `Failure.unreachable` is the verdict
    /// after every attempt and this is the outcome of one: thrown as a `Failure` it skipped
    /// the retry ladder entirely, and eight large-but-healthy artifacts were reported as
    /// changed on the strength of a single slow minute.
    struct Timeout: Error { let seconds: Int }

    static func withDeadline(
        seconds: Int, url: String, _ work: @escaping @Sendable () async throws -> [UInt8]
    ) async throws -> [UInt8] {
        try await withThrowingTaskGroup(of: [UInt8].self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw Timeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw Failure.unreachable(url: url, attempts: 1, last: "no response")
            }
            return first
        }
    }

    public func fetch(_ url: String, attempts: Int = 6, deadline: Int = 180) async throws
        -> [UInt8]
    {
        guard let target = URL(string: url) else {
            throw Failure.unreachable(url: url, attempts: 0, last: "not a URL")
        }
        var last = "no response"
        for attempt in 0..<attempts {
            do {
                let response = try await Self.withDeadline(seconds: deadline, url: url) {
                    let answer = try await HTTP.send(
                        target,
                        headers: [
                            "User-Agent":
                                "DecoyCorpusBuild/1.0 (https://github.com/nerdmenot-swift/decoy)"
                        ],
                        timeout: TimeInterval(deadline))
                    // The status travels inside the raced value so that the deadline covers
                    // reading the body too, which is the part that trickles.
                    guard (200..<300).contains(answer.status) else {
                        throw Status(code: answer.status)
                    }
                    return [UInt8](answer.body)
                }
                return response
            } catch let timeout as Timeout {
                // Transient by nature: a statistics office serving 8 MB slowly on Monday is
                // not a statistics office that has withdrawn the file.
                last = "\(url) did not finish answering within \(timeout.seconds)s"
            } catch let status as Status {
                last = "\(url) returned HTTP \(status.code)"
                if (400..<500).contains(status.code) {
                    throw Failure.unreachable(url: url, attempts: attempt + 1, last: last)
                }
            } catch let failure as Failure {
                throw failure
            } catch let failure as HTTP.Failure {
                // Not a transient condition; retrying would only wait two minutes to say so.
                throw Failure.unreachable(url: url, attempts: attempt + 1, last: failure.description)
            } catch {
                last = error.localizedDescription
            }
            if attempt < attempts - 1 {
                // Six attempts over about two minutes rather than four over eighteen
                // seconds. PubChem answered 503 to all four and failed a build for a
                // service that was back within the minute — and a fetch is the cheapest
                // part of a job that takes ten, so patience costs nothing and impatience
                // costs a red build somebody has to read and dismiss.
                //
                // `Duration` rather than nanoseconds: the multiplication used to happen in
                // `Int`, which is 32 bits on watchOS, where five seconds of nanoseconds does
                // not fit and the literal failed to compile.
                try await Task.sleep(for: .seconds(5 * (attempt + 1)))
            }
        }
        throw Failure.unreachable(url: url, attempts: attempts, last: last)
    }

    /// Unpacks an archive, or returns the file as-is.
    ///
    /// Shelling out to `tar`/`unzip` rather than decoding in-process, which is what the
    /// JavaScript did too — Swift has no built-in zip or xz either, and a hand-rolled
    /// archive reader is a great deal of risk for a build step.
    public func materialise(
        _ artifact: SourceDescriptor.Artifact, at path: URL, source: String
    ) throws -> URL {
        guard artifact.isArchive else { return path }
        let destination = cacheDirectory.appendingPathComponent("\(source)-\(artifact.name)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)

        // Which tool, and how it is invoked, differs by platform — see `Shell`.
        let format = artifact.format ?? "tgz"
        let (tool, arguments) = Shell.extraction(
            format: format, archive: path.path, into: destination.path)

        let result: (status: Int32, output: Data, stderr: String)
        do {
            result = try Shell.run(tool, arguments)
        } catch Shell.Failure.toolMissing(let name) {
            // Reported as an extraction failure so it carries the install instructions
            // rather than only the fact that PATH does not have it.
            throw Failure.extractionFailed(
                archive: path.lastPathComponent, format: format, tool: name,
                detail: "`\(name)` is not on PATH")
        }

        guard result.status == 0 else {
            // GNU tar shells out to a separate `xz` binary and the Swift Linux image has
            // none, which surfaced as "xz: Cannot exec" nested in a child's stderr and read
            // like a corrupt archive rather than a missing package.
            let missing = result.stderr.contains("Cannot exec")
                || result.stderr.contains("not found")
                || result.stderr.contains("No such file")
            throw Failure.extractionFailed(
                archive: path.lastPathComponent, format: format,
                tool: missing ? (format == "zip" ? "unzip" : format == "tar.xz" ? "xz" : "tar")
                    : nil,
                detail: result.stderr)
        }
        return destination
    }

}
