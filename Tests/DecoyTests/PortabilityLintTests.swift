import DecoyAdapterKit
import Foundation
import Testing

/// A lint over the source tree for the calls that behave differently on another platform.
///
/// Every portability bug in this project has been in the build tooling, never in the
/// shipped library — `Sources/Decoy` imports Foundation in none of its files, and code that
/// only uses the standard library is portable by construction. The tooling does not have
/// that protection, so it gets this instead.
///
/// ## Why a lint and not a comment
///
/// The `FoundationNetworking` import was forgotten twice. The second time there was already
/// a shell one-liner checking for it, written after the first time — and it was not re-run,
/// because a check you have to remember to run is a check you forget. This one runs on
/// every `swift test`, on all three platforms, whether anybody remembers it or not.
///
/// ## What it is *not*
///
/// Not a ban on Foundation. Most of `components(separatedBy:)` is fine: the divergence is
/// in how the *search* matches, so it bites only when the needle could fall inside a
/// grapheme cluster. `,` and `\t` cannot. `\n` can, because CRLF is one cluster. The rules
/// below are narrow on purpose — a lint that cries wolf is one people silence.
@Suite("Portability lint")
struct PortabilityLintTests {

    /// One thing that differs across platforms, and where it is knowingly allowed.
    struct Rule {
        let pattern: String
        /// What actually goes wrong, so a failure explains rather than forbids.
        let because: String
        let instead: String
        /// Files where the use is deliberate, each with the reason it is safe there.
        var allowed: [String: String] = [:]
    }

    static let rules: [Rule] = [
        Rule(
            pattern: #"separatedBy: "\n""#,
            because: """
                Foundation searches by UTF-16 code unit on Darwin and through a \
                grapheme-aware path in swift-corelibs-foundation. CRLF is a single extended \
                grapheme cluster, so a CRLF file splits into one line on Linux and into \
                thousands on macOS — silently, with a header check reporting that the \
                upstream schema changed
                """,
            instead: "Lines.split, which walks unicode scalars and means the same everywhere"
        ),
        Rule(
            pattern: #"range(of: "\n"#,
            because: """
                the same grapheme-versus-code-unit search, in its single-match form: a \
                needle beginning with a newline can match across a CRLF cluster on one \
                platform and not the other
                """,
            instead: "Lines.split, or a scalar-level scan",
            allowed: [
                // Both search LF-only files, and both are proved on Linux by something
                // stronger than reading: the adapter's output is compared against its
                // committed baseline on every CI run, and the compiler re-emits the locale
                // modules and diffs them.
                "ProgrammingLanguagesAdapter.swift":
                    "linguist's YAML is LF; the parity baseline compares its output on Linux",
                "DecoyCorpusCompiler/main.swift":
                    "reads a file this repo generates, and the module-drift gate diffs it on Linux",
            ]
        ),
        Rule(
            pattern: "isExecutableFile",
            because: """
                it consults permissions that do not mean the same thing on Windows, where \
                an .exe on the search path reads as not executable
                """,
            instead: "Shell.locate, which checks existence on Windows and permissions elsewhere",
            allowed: ["Shell.swift": "the one place that knows the difference, inside #if"]
        ),
        Rule(
            pattern: #"environment["PATH"]"#,
            because: """
                Windows environment variables are case-insensitive and Swift's dictionary \
                lookup is not, so this finds nothing on a runner that spells it `Path` — \
                which GitHub's does
                """,
            instead: "Shell.searchDirectories, which looks it up case-insensitively",
            allowed: ["Shell.swift": "where the case-insensitive lookup lives"]
        ),
        Rule(
            pattern: "Process(",
            because: """
                launching a program needs a real path, and `/usr/bin/env` is not a file on \
                Windows — the first Windows corpus build died on it, reporting that a \
                downloaded artifact did not exist
                """,
            instead: "Shell.run, which resolves the tool per platform",
            allowed: ["Shell.swift": "the one place that launches anything"]
        ),
        Rule(
            pattern: #""/usr/bin"#,
            because: "there is no /usr/bin on Windows",
            instead: "Shell.run, which resolves against the search path",
            allowed: ["Shell.swift": "the fallback directory list, which is per-platform"]
        ),
        Rule(
            pattern: "CFGetTypeID",
            because: """
                CoreFoundation is Apple-only. Telling a boolean from a 0 or 1 inside an \
                NSNumber this way broke the Linux build outright
                """,
            instead: "a type test that does not leave the standard library"
        ),
        Rule(
            pattern: "import Darwin",
            because: "Darwin is Apple's libc module and does not exist elsewhere",
            instead: "the standard library, or #if os(...) around a platform module"
        ),
    ]

    /// `URLSession` and friends live in a separate module off Apple platforms.
    ///
    /// This is the one that was missed twice, so it is checked by whether the file carries
    /// the import rather than by where the call is — the failure is per-file.
    static let networking = ["URLSession", "URLRequest", "HTTPURLResponse"]

    /// Every Swift file this repository writes.
    ///
    /// Both roots, because `DecoyLocales` is a shipped product that does not live under
    /// `Sources` — it sits beside the corpus blobs it loads.
    private static var sources: [URL] {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ["Sources", "Corpus/Loader"]
            .map(repository.appendingPathComponent)
            .flatMap { root -> [URL] in
                let walker = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: nil)
                return walker?.compactMap { $0 as? URL } ?? []
            }
            .filter { $0.pathExtension == "swift" }
            // The generated locale modules are one base64 literal each: nothing to lint, and
            // a megabyte of string to scan per file. Matched on the directory rather than the
            // filename, which would also skip the hand-written `DecoyLocales.swift`.
            .filter { !$0.deletingLastPathComponent().lastPathComponent.hasPrefix("DecoyLocale") }
            .sorted { $0.path < $1.path }
    }

    /// The lint finds the code it claims to be linting.
    ///
    /// A scan that resolves to nothing passes every rule and prints nothing to say so. That
    /// is not hypothetical here: `decoy-validate` used to check adapters by reading their
    /// files, and when those files moved it went quietly to zero adapters while still
    /// reporting success. A lint that cannot fail is worse than no lint, because it is
    /// believed.
    @Test("the scan reaches the source tree")
    func scanIsNotEmpty() throws {
        let found = Self.sources
        // Loose on purpose: this catches a scan that has collapsed, not one that has drifted
        // by a file. Pinning the count would make every new file a failing test.
        #expect(
            found.count > 50,
            "the source scan found \(found.count) Swift files, so it is looking in the wrong place")
        #expect(
            found.contains { $0.lastPathComponent == "DecoyLocales.swift" },
            "the scan missed Corpus/Loader, which ships")
        #expect(
            found.contains { $0.lastPathComponent == "Shell.swift" },
            "the scan missed Sources, which is most of the code")
    }

    /// A line of code rather than a line about code.
    ///
    /// Documentation naming these calls is how they get explained, and half the reasons in
    /// this file mention them. Comment lines are skipped so the explanation does not trip
    /// the rule it explains.
    static func isCode(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.isEmpty
    }

    @Test("no source uses a call that means something else on another platform")
    func noDivergentCalls() throws {
        for file in Self.sources {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let name = file.lastPathComponent
            let scoped = "\(file.deletingLastPathComponent().lastPathComponent)/\(name)"

            for (offset, line) in Lines.split(text).enumerated()
            where Self.isCode(line) {
                for rule in Self.rules where line.contains(rule.pattern) {
                    if rule.allowed[name] != nil || rule.allowed[scoped] != nil { continue }
                    Issue.record(
                        """
                        \(scoped):\(offset + 1) uses `\(rule.pattern)`, which \(rule.because).
                        Use \(rule.instead) — or, if it is right here, add the file to that \
                        rule's `allowed` with the reason it is safe.
                        """)
                }
            }
        }
    }

    @Test("every file touching URLSession carries the conditional import")
    func networkingImport() throws {
        for file in Self.sources {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let code = Lines.split(text).filter(Self.isCode).joined(separator: "\n")
            guard Self.networking.contains(where: code.contains) else { continue }
            // Recorded rather than `#expect`ed on the condition: the macro quotes the
            // expression it evaluated, and that expression is the entire file.
            guard !text.contains("canImport(FoundationNetworking)") else { continue }
            Issue.record(
                """
                \(file.lastPathComponent) uses URLSession without

                    #if canImport(FoundationNetworking)
                        import FoundationNetworking
                    #endif

                It compiles on macOS, where URLSession is in Foundation, and fails on Linux \
                and Windows, where it is not. That has happened twice. Prefer routing the \
                request through `Endpoint`, which already carries the import — then no new \
                file has to remember.
                """)
        }
    }
}
