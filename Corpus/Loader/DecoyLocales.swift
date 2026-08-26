import Decoy
import Foundation

/// Every locale, loaded from the compiled corpus at run time.
///
/// Three locales ship as compiled-in Swift modules — `DecoyLocaleEN`, `DecoyLocaleDE`,
/// `DecoyLocaleJA` — because those are the ones worth paying for statically. The corpus
/// holds sixty-four. This is how you reach the other sixty-one:
///
/// ```swift
/// import DecoyLocales
///
/// let fr = try DecoyLocales.locale("fr")
/// var faker = Faker(seed: 1337, locale: fr)
/// faker.person.fullName()   // "Étienne Lacombe"
/// ```
///
/// ## Which one to use
///
/// Prefer the module when your locale has one. `import DecoyLocaleDE` costs nothing at run
/// time — the blob is a base64 `StaticString` decoded once — and it cannot fail, so there
/// is no `try` and no error to handle.
///
/// This target carries every blob as a resource instead, which is about 13 MB, and reads
/// them from the bundle on demand. That is the right trade when the locale is chosen at
/// run time, or when you want several, or when yours is simply not one of the three. It is
/// a separate product precisely so nobody pays 13 MB for wanting German.
///
/// ## The chain is resolved for you
///
/// A locale is not one corpus but a chain of them: `de_AT` falls back to `de`, then `en`,
/// then `base`, and a value missing from the first is looked for in the next. Getting that
/// order wrong is silent — you get English where you expected Austrian German — so it is
/// derived here from the same rule the corpus was built with rather than left to the
/// caller.
public enum DecoyLocales {

    public enum Failure: Error, CustomStringConvertible {
        case unknown(code: String, available: [String])
        case unreadable(code: String, detail: String)

        public var description: String {
            switch self {
            case .unknown(let code, let available):
                // The whole list, not a count. Somebody who typed `pt` wants to be told
                // that `pt_BR` and `pt_PT` exist, and a message saying "64 available" makes
                // them go and find the list themselves.
                return
                    "no locale '\(code)' in the corpus. Available: "
                    + available.joined(separator: ", ")
            case .unreadable(let code, let detail):
                return "the corpus for '\(code)' could not be read: \(detail)"
            }
        }
    }

    /// Every locale code the bundled corpus carries, sorted.
    public static let available: [String] = {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("binary"),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".decoy") }
            .map { String($0.dropLast(".decoy".count)) }
            .sorted()
    }()

    /// The fallback chain for a code: itself, its shorter prefixes, then English, then base.
    ///
    /// The same rule the corpus is built with. `base` is the root and inherits from
    /// nothing — giving it an English fallback would quietly pull English into every locale
    /// on earth. Filtered against what is actually present at the end rather than while
    /// building, which matters for a code whose middle segment is not itself a locale:
    /// `sr_RS_latin` drops both `sr_RS` and `sr` because neither is present, while a code
    /// whose middle segment *is* present keeps it.
    public static func chain(for code: String, available: [String] = available) -> [String] {
        if code == "base" { return ["base"] }

        let parts = code.split(separator: "_").map(String.init)
        var chain: [String] = []
        for count in stride(from: parts.count, through: 1, by: -1) {
            chain.append(parts.prefix(count).joined(separator: "_"))
        }
        if !chain.contains("en") { chain.append("en") }
        chain.append("base")

        let present = Set(available)
        var seen = Set<String>()
        return chain.filter { present.contains($0) && seen.insert($0).inserted }
    }

    /// One locale, chain resolved and every blob in it loaded.
    ///
    /// An unrecognised code throws rather than resolving. It would otherwise *work* —
    /// `chain(for: "pt")` is `["en", "base"]` once the missing `pt` is filtered out — and
    /// hand back a perfectly functional English locale under a Portuguese name. That is the
    /// silent fallback this library exists to make visible, and asking for a locale that
    /// does not exist is a typo, not a preference.
    public static func locale(_ code: String) throws -> LocaleCorpus {
        guard available.contains(code) else {
            throw Failure.unknown(code: code, available: available)
        }
        let codes = chain(for: code)
        guard !codes.isEmpty else {
            throw Failure.unknown(code: code, available: available)
        }

        var corpora: [Corpus] = []
        for step in codes {
            guard let url = url(for: step) else {
                throw Failure.unknown(code: step, available: available)
            }
            do {
                corpora.append(try Corpus(bytes: [UInt8](try Data(contentsOf: url))))
            } catch {
                throw Failure.unreadable(code: step, detail: "\(error)")
            }
        }
        return LocaleCorpus(code: code, chain: corpora)
    }

    /// Where a single locale's blob sits in the bundle.
    public static func url(for code: String) -> URL? {
        Bundle.module.url(forResource: "binary/\(code)", withExtension: "decoy")
            ?? Bundle.module.resourceURL?
                .appendingPathComponent("binary")
                .appendingPathComponent("\(code).decoy")
    }
}
