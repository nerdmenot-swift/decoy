import Foundation

/// Running the two archive tools the pipeline needs, on the three platforms it builds on.
///
/// The pipeline shells out for extraction rather than decoding archives in-process: Swift
/// has no built-in zip, gzip or xz, and a hand-rolled archive reader is a great deal of
/// risk for a build step. That was fine while the pipeline was JavaScript and the corpus was
/// only ever built on Unix.
///
/// It is not fine now. `/usr/bin/env` is not a file on Windows, and the first Windows run of
/// the Swift pipeline failed on the first artifact with `The file doesn't exist` — the file
/// in question being `env`, which reads like a missing download. Windows also has no
/// `unzip`, so the tool table has to differ too.
///
/// Windows does ship bsdtar as `tar.exe`, which reads zip, gzip and xz alike and detects
/// which from the bytes. So the Windows branch is one tool for every format, and the Unix
/// branch keeps `unzip` explicitly, because GNU tar reads no zip at all.
public enum Shell {

    public enum Failure: Error, CustomStringConvertible {
        case toolMissing(String)

        public var description: String {
            switch self {
            case .toolMissing(let tool):
                return "`\(tool)` is not on PATH, and the corpus build needs it to unpack archives"
            }
        }
    }

    /// The directories to search, and the one Windows keeps its tools in.
    ///
    /// Windows environment variables are case-insensitive and Swift's dictionary lookup is
    /// not, so `environment["PATH"]` finds nothing on a runner that spells it `Path` — which
    /// GitHub's does. That produced "`tar` is not installed" on a machine that ships tar.
    static func searchDirectories() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let raw =
            environment["PATH"]
            ?? environment.first { $0.key.caseInsensitiveCompare("PATH") == .orderedSame }?
                .value ?? ""

        #if os(Windows)
            let separator: Character = ";"
            // Named explicitly as well as searched for. `tar.exe` has shipped in System32
            // since Windows 10 1803, and a PATH that somehow omits it should not turn into
            // a build failure that reads like a missing package.
            let system = environment["SystemRoot"] ?? environment["SYSTEMROOT"] ?? "C:\\Windows"
            let known = ["\(system)\\System32"]
        #else
            let separator: Character = ":"
            let known: [String] = ["/usr/bin", "/bin", "/usr/local/bin"]
        #endif

        return raw.split(separator: separator).map(String.init).filter { !$0.isEmpty } + known
    }

    /// Where a tool actually lives.
    ///
    /// Resolved against the search path rather than delegated to `/usr/bin/env`, which does
    /// not exist on Windows — and `Process` needs a real path either way, so nothing is lost
    /// by doing the lookup here on every platform.
    static func locate(_ tool: String) -> URL? {
        #if os(Windows)
            // A bare name is not a program on Windows; the extension is part of the file.
            let suffixes = ["", ".exe", ".cmd", ".bat"]
        #else
            let suffixes = [""]
        #endif

        for directory in searchDirectories() {
            for suffix in suffixes {
                let candidate = URL(fileURLWithPath: directory)
                    .appendingPathComponent(tool + suffix)
                #if os(Windows)
                    // `isExecutableFile` consults permissions that do not mean the same
                    // thing here; an `.exe` on the search path is the program.
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                #else
                    if FileManager.default.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                #endif
            }
        }
        return nil
    }

    /// The tool that unpacks an archive of this format, and the arguments it takes.
    public static func extraction(format: String, archive: String, into destination: String)
        -> (tool: String, arguments: [String])
    {
        #if os(Windows)
            // bsdtar detects the compression from the bytes, so one invocation covers zip,
            // tgz and tar.xz.
            return ("tar", ["-xf", archive, "-C", destination])
        #else
            // `tar` reads zip on macOS via libarchive but GNU tar does not, so zips go
            // through `unzip` explicitly rather than relying on which tar the host has.
            switch format {
            case "zip": return ("unzip", ["-q", "-o", archive, "-d", destination])
            case "tar.xz": return ("tar", ["xJf", archive, "-C", destination])
            default: return ("tar", ["xzf", archive, "-C", destination])
            }
        #endif
    }

    /// The tool that reads one member of a zip to standard output.
    public static func member(_ name: String, of archive: String)
        -> (tool: String, arguments: [String])
    {
        #if os(Windows)
            return ("tar", ["-xOf", archive, name])
        #else
            return ("unzip", ["-p", archive, name])
        #endif
    }

    /// Runs a tool, returning its exit status and what it wrote where.
    public static func run(
        _ tool: String, _ arguments: [String], captureOutput: Bool = false
    ) throws -> (status: Int32, output: Data, stderr: String) {
        guard let executable = locate(tool) else { throw Failure.toolMissing(tool) }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let out = Pipe()
        let errors = Pipe()
        process.standardOutput = out
        process.standardError = errors
        try process.run()

        // Read before waiting. A member of a workbook is megabytes, and a pipe that fills
        // while the parent waits deadlocks both sides.
        let output = captureOutput ? out.fileHandleForReading.readDataToEndOfFile() : Data()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, output, String(decoding: stderr, as: UTF8.self))
    }
}
