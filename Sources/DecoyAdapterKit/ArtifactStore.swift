import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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

        public var description: String {
            switch self {
            case .unreachable(let url, let attempts, let last):
                return "\(url) failed after \(attempts) attempts — \(last)"
            case .vendoredMismatch(let path):
                return
                    "integrity mismatch for vendored \(path)\n"
                    + "Re-vendor from the pinned URL, or delete the file to fetch it."
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

    public let root: URL
    public var cacheDirectory: URL { root.appendingPathComponent(".cache") }
    public var vendorDirectory: URL { root.appendingPathComponent("vendor") }

    public init(root: URL) { self.root = root }

    /// A file path holding verified bytes for `artifact`.
    public func acquire(
        _ artifact: SourceDescriptor.Artifact,
        source: String,
        log: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async throws -> URL {
        let expectation = try Integrity.Expectation(artifact.integrity)
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
        let cached = cacheDirectory.appendingPathComponent("\(source)-\(artifact.cacheSuffix)")

        let matches = { (bytes: [UInt8]) in
            Integrity.digest(
                Integrity.normalised(bytes, ignoringLinesMatching: artifact.ignoreLinesMatching))
                == expectation.expected
        }

        if let data = try? Data(contentsOf: cached) {
            if matches([UInt8](data)) { return cached }
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
            return cached
        }

        log("  fetching \(artifact.url)")
        let bytes = try await fetch(artifact.url)
        try Integrity.verify(
            bytes, against: expectation, source: source, url: artifact.url,
            ignoringLinesMatching: artifact.ignoreLinesMatching)
        try Data(bytes).write(to: cached)
        return cached
    }

    /// Fetches, retrying the failures that are the network rather than the server.
    ///
    /// A 4xx is not retried: that is the server saying the request is wrong — a moved file,
    /// a revoked dataset — and asking again does not change the answer. 5xx and transport
    /// failures are, because those come right on their own. The integrity hash
    /// still decides whether what arrives is correct; this only decides how often to ask.
    func fetch(_ url: String, attempts: Int = 6) async throws -> [UInt8] {
        guard let target = URL(string: url) else {
            throw Failure.unreachable(url: url, attempts: 0, last: "not a URL")
        }
        var last = "no response"
        for attempt in 0..<attempts {
            do {
                var request = URLRequest(url: target)
                request.setValue(
                    "DecoyCorpusBuild/1.0 (https://github.com/nerdmenot-swift/decoy)",
                    forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) { return [UInt8](data) }
                last = "\(url) returned HTTP \(status)"
                if (400..<500).contains(status) {
                    throw Failure.unreachable(url: url, attempts: attempt + 1, last: last)
                }
            } catch let failure as Failure {
                throw failure
            } catch {
                last = error.localizedDescription
            }
            if attempt < attempts - 1 {
                // Six attempts over about two minutes rather than four over eighteen
                // seconds. PubChem answered 503 to all four and failed a build for a
                // service that was back within the minute — and a fetch is the cheapest
                // part of a job that takes ten, so patience costs nothing and impatience
                // costs a red build somebody has to read and dismiss.
                try await Task.sleep(nanoseconds: UInt64(5_000_000_000 * (attempt + 1)))
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
