import Foundation

/// The authored lists that are simply lists: no upstream, no composition, one locale.
///
/// Three adapters share this shape — whimsy vocabulary, fixture text, and common knowledge
/// — and between them they were 2,000 lines of literals inside JavaScript modules. The
/// values now live in `data/authored/*.json` and this reads them.
///
/// ## Why freezing is right here and was not for commerce
///
/// `authored-commerce` maps one language's vocabulary onto several locales, so its
/// language-to-locale rule had to stay as code or the corpus would stop adapting when a
/// locale is added. These three have no such rule: every path is stated explicitly against
/// a single locale, so the data file *is* the adapter. Turning it into code would be
/// writing a program to hold a constant.
///
/// The lists are `en` because that is where invented English vocabulary belongs, not
/// because English is a default — `LocaleCorpus` still has to be asked for them, and the
/// matrix marks them English-only rather than pretending every locale has its own.
public struct AuthoredListsAdapter: Adapter {
    public static let id = "authored-lists"
    public static let sources = ["decoy-authored"]

    /// The adapter this instance stands in for, the source it credits, and the file holding
    /// its values.
    private let identifier: String
    private let source: String
    private let file: String

    public init(id: String, source: String, file: String) {
        self.identifier = id
        self.source = source
        self.file = file
    }

    public static func whimsy() -> AuthoredListsAdapter {
        AuthoredListsAdapter(
            id: "authored-whimsy", source: "decoy-authored", file: "whimsy.json")
    }
    public static func fixtures() -> AuthoredListsAdapter {
        AuthoredListsAdapter(
            id: "authored-fixtures", source: "decoy-authored", file: "fixtures.json")
    }
    /// Its own descriptor, not `decoy-authored`. The other two are invented vocabulary;
    /// this one records facts nobody publishes a register of, and says so under its own
    /// licence and URL.
    public static func commonKnowledge() -> AuthoredListsAdapter {
        AuthoredListsAdapter(
            id: "common-knowledge", source: "common-knowledge",
            file: "common-knowledge.json")
    }

    public var adapterID: String { identifier }
    public var adapterSources: [String] { [source] }


    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        let path = input.dataDirectory.appendingPathComponent("authored/\(file)")
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: path))
                as? [String: [String: Any]]
        else {
            throw AdapterFailure.shapeChanged(
                adapter: identifier, detail: "data/authored/\(file) is not locale -> path -> values")
        }

        let roster = Set(input.locales)
        var contributions: [String: [String: Definition]] = [:]
        var pathCount = 0

        for (locale, paths) in root {
            // Stated rather than assumed: these lists name their locale, and a roster that
            // no longer carries it is a change worth failing on rather than dropping the
            // whole contribution silently.
            guard roster.contains(locale) else {
                throw AdapterFailure.shapeChanged(
                    adapter: identifier,
                    detail: "\(identifier) needs the `\(locale)` locale")
            }
            contributions[locale] = paths.mapValues(Definition.init(json:))
            pathCount += paths.count
        }

        return AdapterOutput(
            contributions: contributions, stats: [("paths", String(pathCount))])
    }
}
