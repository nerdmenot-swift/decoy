import Foundation

/// Composition rules, derived from CLDR rather than inherited from anywhere.
///
/// A pattern is not data in the way a name list is. `{{person.firstName}}
/// {{person.lastName}}` contains no names — it says how a locale assembles one, which is a
/// fact about the language with a published authority behind it.
///
/// A pipeline stage rather than an adapter, for the same reason the model trainer is one:
/// whether a locale gets a prefix variant depends on whether it *has* prefixes, and that is
/// only knowable after the merge.
public enum NamePatterns {

    public struct Formats: Sendable {
        public let surnameFirst: Set<String>
        public let separators: [String: String]

        public init(surnameFirst: Set<String>, separators: [String: String]) {
            self.surnameFirst = surnameFirst
            self.separators = separators
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case implausible(surnameFirst: Int, separators: Int)

        public var description: String {
            switch self {
            case .implausible(let first, let separators):
                return
                    "CLDR name formats look wrong: \(first) surname-first, "
                    + "\(separators) separators — verify before re-pinning"
            }
        }
    }

    /// What CLDR knows that a pattern encodes implicitly: the order a locale writes names
    /// in, and what goes between the parts.
    ///
    /// The separator is not always a space. `nativeSpaceReplacement` is empty for Japanese,
    /// Korean and Chinese, because 山田太郎 is how a Japanese name is written and 山田 太郎
    /// is a concession to Latin typesetting.
    public static func loadFormats(coreDirectory: URL, personNamesDirectory: URL) throws -> Formats
    {
        let defaultsPath = coreDirectory
            .appendingPathComponent("package/supplemental/personNamesDefaults.json")
        let defaults =
            try JSONSerialization.jsonObject(with: Data(contentsOf: defaultsPath))
            as? [String: Any]
        let supplemental = defaults?["supplemental"] as? [String: Any]
        let personNames = supplemental?["personNamesDefaults"] as? [String: Any]
        let surnameFirst = Set(
            ((personNames?["surnameFirst"] as? String) ?? "")
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .map(String.init))

        var separators: [String: String] = [:]
        let base = personNamesDirectory.appendingPathComponent("package/main")
        let locales =
            (try? FileManager.default.contentsOfDirectory(atPath: base.path))?.sorted() ?? []
        for locale in locales {
            let path = base.appendingPathComponent("\(locale)/personNames.json")
            guard let data = try? Data(contentsOf: path),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let main = root["main"] as? [String: Any],
                let entry = main[locale] as? [String: Any],
                let names = entry["personNames"] as? [String: Any],
                let replacement = names["nativeSpaceReplacement"] as? String
            else { continue }
            separators[locale] = replacement
        }

        guard !surnameFirst.isEmpty, separators.count >= 50 else {
            throw Failure.implausible(
                surnameFirst: surnameFirst.count, separators: separators.count)
        }
        return Formats(surnameFirst: surnameFirst, separators: separators)
    }

    /// CLDR keys on language, so `de_AT` and `pt_BR` resolve through theirs.
    static func format(_ formats: Formats, for code: String)
        -> (surnameFirst: Bool, separator: String)
    {
        let language = String(code.split(separator: "_")[0])
        let separator =
            formats.separators[code.replacingOccurrences(of: "_", with: "-")]
            ?? formats.separators[language] ?? " "
        return (formats.surnameFirst.contains(language), separator)
    }

    /// What a locale says about a path.
    ///
    /// The three-way answer is the point. `empty` means the locale declares the path
    /// deliberately empty, which *blocks* inheritance — Azerbaijani has no honorifics, and
    /// the whole reason the corpus format carries explicit nulls is to stop it borrowing
    /// English ones. Collapsing `empty` into `absent` walks a chain past a stop sign.
    public enum State: Sendable { case filled, empty, absent }

    public static func state(of definitions: Any?, at path: String) -> State {
        var cursor: Any? = definitions
        for part in path.split(separator: ".") {
            guard let node = cursor as? [String: Any], node.keys.contains(String(part)) else {
                return .absent
            }
            cursor = node[String(part)]
            // A JSON null decodes to NSNull, which is how "deliberately empty" survives.
            if cursor is NSNull { cursor = nil }
        }
        if cursor == nil { return .empty }
        if let list = cursor as? [Any] { return list.isEmpty ? .empty : .filled }
        return cursor is [String: Any] ? .filled : .absent
    }

    public struct Variant: Sendable, Equatable {
        public let value: String
        public let weight: Int
    }

    /// Builds `person.name` for one locale.
    ///
    /// Weighted so the plain form dominates, because it does in life: a fixture set where
    /// one row in eight carries a title looks generated.
    ///
    /// Prefix and suffix variants only where the locale has that data *and* writes names
    /// with a space. Attaching a title in a script that joins its name parts is a question
    /// about that language which CLDR's defaults do not answer, and guessing would put さん
    /// in the wrong place rather than leave it out.
    public static func namePattern(
        resolves: (String) -> Bool, surnameFirst: Bool, separator: String
    ) -> [Variant] {
        let given = "{{person.firstName}}"
        let surname = "{{person.lastName}}"
        let (first, second) = surnameFirst ? (surname, given) : (given, surname)
        let plain = "\(first)\(separator)\(second)"

        var variants = [Variant(value: plain, weight: 90)]
        if separator == " " {
            if resolves("person.prefix") {
                variants.append(Variant(value: "{{person.prefix}} \(plain)", weight: 7))
            }
            if resolves("person.suffix") {
                variants.append(Variant(value: "\(plain) {{person.suffix}}", weight: 3))
            }
        }
        return variants
    }

    /// Resolves a path through the chain, stopping where the chain says to stop.
    ///
    /// Two failures shaped this, both found by the validator rather than by reading.
    /// Checking only a locale's own data left `en_GB` and `en_HK` on a stale pattern,
    /// because both define surnames and inherit given names. And walking the chain *without*
    /// honouring explicit nulls gave Azerbaijani a `{{person.prefix}}` variant on the
    /// strength of English honorifics it deliberately blocks — a token expanding to nothing
    /// in the one locale the blocking mechanism exists for.
    public static func resolver(definitions: Any?, chain: [Any?]) -> (String) -> Bool {
        { path in
            for level in [definitions] + chain {
                switch state(of: level, at: path) {
                case .filled: return true
                case .empty: return false
                case .absent: continue
                }
            }
            return false
        }
    }
}
