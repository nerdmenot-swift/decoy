import Foundation

/// Trains a generative model for every name field a locale has enough data for.
///
/// A pipeline stage rather than an adapter, and that placement is the whole design. An
/// adapter sees only its own contribution; a model has to be trained on what a locale
/// *ends up with*, which is whatever won the merge — the Census surnames in `en`, the
/// registry's in `fr`, and a future replacement in either without this code changing.
///
/// Nothing here replaces anything. Each model is written to a parallel path and the list
/// it was trained on stays exactly where it was, because the two answer different
/// questions: the list carries real frequencies and real names, the model carries neither
/// and is the only one of the two that never names a real person.
public enum Models {

    /// Fields worth generating, and where the model goes.
    ///
    /// Names only, deliberately. A generated city is a place that does not exist, which
    /// breaks anything validating fixtures against a gazetteer, and a generated company
    /// name is not anybody's personal data. The argument for generating rather than listing
    /// is at its strongest for names and gets weaker with every step away from them.
    public static let modelledFields: [(from: String, to: String)] = [
        ("person.first_name.female", "person.first_name_model.female"),
        ("person.first_name.male", "person.first_name_model.male"),
        ("person.first_name.generic", "person.first_name_model.generic"),
        ("person.last_name.generic", "person.last_name_model.generic"),
        ("person.last_name.female", "person.last_name_model.female"),
        ("person.last_name.male", "person.last_name_model.male"),
        ("person.middle_name.generic", "person.middle_name_model.generic"),
    ]

    public struct Trained: Sendable {
        public let path: String
        public let values: Int
        public let order: Int
        public let novel: Double
        public let screened: Bool
    }

    public struct Outcome: Sendable {
        public let trained: [Trained]
        /// Why a field was passed over, in a line the run can print.
        public let skipped: [String]
    }

    public enum Failure: Error, CustomStringConvertible {
        case blocklistsUnreadable(String)
        case tooFewBlocklists(Int)

        public var description: String {
            switch self {
            case .blocklistsUnreadable(let detail): return "blocklists: \(detail)"
            case .tooFewBlocklists(let found):
                return "only \(found) blocklists found — verify before re-pinning"
            }
        }
    }

    // MARK: - Reading and writing a nested tree

    /// Reads a dotted path out of a nested definition tree.
    static func at(_ root: [String: Definition], _ path: String) -> Definition? {
        var cursor = Definition.object(root)
        for part in path.split(separator: ".") {
            guard let object = cursor.asObject, let next = object[String(part)] else {
                return nil
            }
            cursor = next
        }
        return cursor
    }

    /// Writes a dotted path into a nested definition tree, creating what it needs.
    static func put(_ root: inout [String: Definition], _ path: String, _ value: Definition) {
        let parts = path.split(separator: ".").map(String.init)
        func insert(_ node: inout [String: Definition], _ remaining: ArraySlice<String>) {
            guard let head = remaining.first else { return }
            if remaining.count == 1 {
                node[head] = value
                return
            }
            // A non-object sitting in the way is replaced, matching the JavaScript's
            // `typeof cursor[part] !== 'object'` check.
            var child = node[head]?.asObject ?? [:]
            insert(&child, remaining.dropFirst())
            node[head] = .object(child)
        }
        insert(&root, parts[...])
    }

    /// The strings in a field, whether it is a plain list or a weighted one.
    ///
    /// Weights are read and discarded on purpose: the model is trained on each name once
    /// regardless of how many people bear it. Training on the counts would make it produce
    /// near-misses of the twenty commonest names rather than the shape of the language.
    static func valuesOf(_ field: Definition?) -> [String]? {
        guard case .list(let items)? = field else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(items.count)
        for item in items {
            if case .string(let text) = item {
                strings.append(text)
            } else if case .object(let fields) = item,
                case .string(let text)? = fields["value"]
            {
                strings.append(text)
            } else {
                // All or nothing: a table this cannot read whole is not one to train on
                // half of.
                return nil
            }
        }
        return strings
    }

    // MARK: - Blocklists

    /// A blocklist filename: a two- or three-letter language code, optionally with more
    /// after a hyphen. Replaces `/^[a-z]{2,3}(-|$)/`.
    static func isLanguageFile(_ name: String) -> Bool {
        let characters = Array(name)
        var length = 0
        while length < characters.count, characters[length].isASCII,
            characters[length].isLowercase
        {
            length += 1
        }
        guard (2...3).contains(length) else { return false }
        return length == characters.count || characters[length] == "-"
    }

    /// Loads the blocklists, keyed by the language code they screen.
    ///
    /// One file per language upstream, twenty-eight of them, and a locale with no matching
    /// file gets no screen. That is stated rather than papered over with the English list:
    /// English profanity cannot appear in a model trained on Japanese, so an English screen
    /// on `ja` would cost lookups and catch nothing, while implying a protection that is
    /// not there. `decoy-validate` reports which locales ship a model without one.
    public static func loadBlocklists(at directory: URL) throws -> [String: [String]] {
        let manager = FileManager.default

        // The archive unpacks to a single top-level directory whose name carries the
        // release. Found by being a directory rather than by being first in the listing:
        // the JavaScript took `readdir`'s first entry, which on a macOS checkout is
        // whichever of `.DS_Store` and the real directory the filesystem happens to
        // return first.
        let entries = try manager.contentsOfDirectory(atPath: directory.path).sorted()
        guard
            let root = entries.first(where: { name in
                var isDirectory: ObjCBool = false
                let path = directory.appendingPathComponent(name).path
                return manager.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            })
        else { throw Failure.blocklistsUnreadable("no directory inside \(directory.path)") }

        let base = directory.appendingPathComponent(root)
        var lists: [String: [String]] = [:]
        for file in try manager.contentsOfDirectory(atPath: base.path).sorted()
        where isLanguageFile(file) {
            let terms = String(
                decoding: try Data(contentsOf: base.appendingPathComponent(file)),
                as: UTF8.self
            ).components(separatedBy: "\n").filter { !$0.isEmpty }
            if !terms.isEmpty { lists[file] = terms }
        }

        guard lists.count >= 20 else { throw Failure.tooFewBlocklists(lists.count) }
        return lists
    }

    /// The blocklist covering a locale, by language, ignoring the region.
    static func screen(for code: String, in lists: [String: [String]]) -> [String]? {
        let language = (code.split(separator: "_").first.map(String.init) ?? code)
            .lowercased()
        return lists[language]
    }

    // MARK: - Training

    /// Trains every viable model for one locale, writing them into `definitions`.
    public static func trainLocale(
        _ code: String, _ definitions: inout [String: Definition],
        blocklists: [String: [String]]
    ) -> Outcome {
        let screenTerms = screen(for: code, in: blocklists)
        let screen = screenTerms.map { BloomFilter.overBlocklist($0) }
        var trained: [Trained] = []
        var skipped: [String] = []

        for (from, to) in modelledFields {
            guard let values = valuesOf(at(definitions, from)) else { continue }

            let unique = NGram.distinct(values)
            let distinct = unique.count
            guard NGram.orderFor(count: distinct, typicalLength: NGram.typicalLength(unique))
                != nil
            else {
                // Not a failure. Most locales carry a few dozen names and no order of
                // n-gram turns those into a language model.
                skipped.append("\(from)(\(distinct))")
                continue
            }

            // Trained on this sub-list, screened against every sibling of it.
            //
            // `person.first_name` splits into `generic`, `female` and `male`, and those
            // lists overlap without being equal. A model trained on the 2,240 generic names
            // and screened only against them will happily emit a name that sits in the
            // 473-name female list — novel for the list it learned from, and a real given
            // name in this locale, which is the thing a caller actually asked not to get.
            let parent = from.split(separator: ".").dropLast().joined(separator: ".")
            let siblings = (at(definitions, parent)?.asObject ?? [:]).values
                .flatMap { valuesOf($0) ?? [] }

            // Deduplicated on code units rather than on the string, so the count that sizes
            // the filter is the one JavaScript's Set produced. See `CodeUnitOrder.key`.
            var seen = Set<[UInt16]>()
            var guardedAgainst: [String] = []
            for word in unique + siblings where seen.insert(CodeUnitOrder.key(word)).inserted {
                guardedAgainst.append(word)
            }

            guard let model = try? NGram.train(values) else {
                skipped.append("\(from)(\(distinct), would not train)")
                continue
            }

            // Trained, then made to prove it can generate. A model that only recites is
            // worse than no model: the Bloom filter rejects every candidate, the sampler
            // exhausts its attempts and returns nothing, and the caller gets an empty
            // string from a generator that reported success.
            let check = NGram.viability(model, words: guardedAgainst)
            guard check.viable else {
                let percent = Int((check.novel * 100).rounded())
                skipped.append("\(from)(\(distinct), \(percent)% novel)")
                continue
            }

            let filter = BloomFilter.overTrainingSet(guardedAgainst)
            var fields: [String: Definition] = [
                "order": .number(Double(model.order)),
                "alphabet": .list(model.alphabet.map(Definition.string)),
                "contexts": .list(
                    model.contexts.map { context in
                        // The key is a string because a u64 context key does not survive a
                        // JSON number: JavaScript would round it and the context would land
                        // in the wrong place in a sorted index.
                        .object([
                            "key": .string(String(context.key)),
                            "transitions": .list(
                                context.transitions.map {
                                    .object([
                                        "symbol": .number(Double($0.symbol)),
                                        "weight": .number(Double($0.weight)),
                                    ])
                                }),
                        ])
                    }),
                "minLength": .number(Double(model.minLength)),
                "maxLength": .number(Double(model.maxLength)),
                "filterHashCount": .number(Double(filter.hashCount)),
                // Base64 rather than an array of numbers: the filter for English surnames
                // is 29 KB, which is 100 KB of decimal digits and commas in the
                // intermediate.
                "filterBits": .string(Data(filter.bits).base64EncodedString()),
            ]
            if let screen {
                fields["blockHashCount"] = .number(Double(screen.hashCount))
                fields["blockMinLength"] = .number(Double(screen.minLength))
                fields["blockBits"] = .string(Data(screen.bits).base64EncodedString())
            }

            put(&definitions, to, .object(["__model": .object(fields)]))
            trained.append(
                Trained(
                    path: to, values: distinct, order: model.order, novel: check.novel,
                    screened: screen != nil))
        }

        return Outcome(trained: trained, skipped: skipped)
    }
}
