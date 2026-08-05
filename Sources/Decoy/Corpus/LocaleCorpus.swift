/// A locale and the chain it falls back through.
///
/// `de_AT` resolves through `de`, then `en`, then `base`. Resolving at *lookup* time
/// rather than merging at compile time keeps each blob small — `de_AT` need not carry
/// a copy of everything `de` already has.
///
/// The chain is also the extension point: a user-supplied corpus placed at the front
/// overrides anything behind it, so adding your own data needs no separate overlay
/// mechanism. See ``overlaid(by:)``.
public struct LocaleCorpus: Sendable {

    /// The locale this represents, e.g. `de_AT`.
    public let code: String

    /// Most specific first. Lookups walk this in order.
    public let chain: [Corpus]

    public init(code: String, chain: [Corpus]) {
        self.code = code
        self.chain = chain
    }

    /// Returns a copy with `corpus` consulted before everything else.
    ///
    /// ```swift
    /// let mine = try Corpus(bytes: builder.build())
    /// let locale = LocaleCorpus.builtIn.overlaid(by: mine)
    /// ```
    public func overlaid(by corpus: Corpus) -> LocaleCorpus {
        LocaleCorpus(code: code, chain: [corpus] + chain)
    }

    /// Walks the chain for `path`.
    ///
    /// Stops at the first locale that mentions the key. A locale that explicitly
    /// defines it as empty ends the walk and yields nothing — Azerbaijani has no name
    /// prefixes, and continuing to English would put English honorifics on Azeri
    /// records. A locale that simply lacks the key continues to the next.
    public func resolve(_ path: String) -> Entry? {
        for corpus in chain {
            guard let entry = try? corpus.lookup(path) else { continue }
            if case .explicitlyEmpty = entry { return nil }
            return entry
        }
        return nil
    }

    /// The string table at `path`, if the chain has one.
    public func strings(_ path: String) -> StringTable? {
        guard case .strings(let table)? = resolve(path) else { return nil }
        return table
    }

    /// The composite table at `path`, if the chain has one.
    public func composite(_ path: String) -> CompositeTable? {
        guard case .composite(let table)? = resolve(path) else { return nil }
        return table
    }

    /// Every path the chain can resolve, sorted, with the same precedence as
    /// ``resolve(_:)`` — the most specific locale to mention a path wins.
    ///
    /// A path the front of the chain defines as explicitly empty is *included*: it is
    /// something this locale has an opinion about. Use ``has(_:)`` to distinguish
    /// "defined" from "yields a value".
    public var paths: [PathEntry] {
        get throws {
            var seen = Set<String>()
            var result = [PathEntry]()
            for corpus in chain {
                for entry in try corpus.paths where seen.insert(entry.path).inserted {
                    result.append(entry)
                }
            }
            result.sort { $0.path < $1.path }
            return result
        }
    }

    /// The paths `code`'s own corpus defines, ignoring everything it inherits.
    ///
    /// This is the coverage signal: a locale resolving `person.first_name` only because
    /// English sits behind it is exactly the failure that leaves Tamil records named
    /// "Jennifer Williams", and the chain-wide ``paths`` cannot show it.
    public var nativePaths: [PathEntry] {
        get throws { try chain.first?.paths ?? [] }
    }

    /// Whether the chain can supply a non-empty value for `path`.
    ///
    /// Useful for coverage reporting: a locale silently falling back to English for
    /// most fields is the failure that leaves Tamil records named "Jennifer Williams".
    public func has(_ path: String) -> Bool {
        switch resolve(path) {
        case .strings(let table): return !table.isEmpty
        case .composite(let table): return !table.isEmpty
        case .model: return true
        case .explicitlyEmpty, nil: return false
        }
    }
}

// MARK: - Built-in corpus

extension LocaleCorpus {

    /// A deliberately tiny English corpus, compiled in memory at first use.
    ///
    /// Exists so `Forge` works with no setup and so the library has no hard dependency
    /// on a blob being present. It is **not** the real corpus — a few dozen names
    /// against `en`'s 21,629 strings — and it uses the same paths as the compiled
    /// locales, so swapping in a real one changes nothing but the data.
    public static let builtIn: LocaleCorpus = {
        var builder = CorpusBuilder(version: CorpusVersion(major: 0, minor: 0, patch: 1))
        let source = builder.addSource(
            id: "decoy-builtin",
            license: "Apache-2.0",
            url: "https://github.com/NerdMeNot/decoy",
            version: Decoy.version,
            retrieved: ""
        )

        func add(_ path: String, _ values: [String]) {
            builder.index(path, stringTable: builder.addStringTable(values, source: source))
        }

        add(
            "person.first_name.female",
            [
                "Ada", "Beatriz", "Chiara", "Daniela", "Elif", "Fatima", "Greta", "Hana",
                "Ingrid", "Júlia", "Keiko", "Lucia", "Maya", "Nadia", "Olga", "Priya",
            ]
        )
        add(
            "person.first_name.male",
            [
                "Arda", "Bruno", "Caleb", "Dmitri", "Emeka", "Farid", "Gustav", "Hugo",
                "Ivan", "Jamie", "Kenji", "Lars", "Mateo", "Niko", "Omar", "Pavel",
            ]
        )
        add(
            "person.last_name.generic",
            [
                "Almeida", "Bergström", "Chen", "Dubois", "Eriksen", "Fischer", "Gallo",
                "Haddad", "Ibrahim", "Jensen", "Kowalski", "Lindqvist", "Moreau",
                "Nakamura", "Oyelaran", "Petrov", "Quintana", "Rossi", "Silva",
                "Takahashi",
            ]
        )
        add("internet.domain_suffix", ["com", "net", "org", "io", "dev"])
        add("internet.example_email", ["example.com", "example.org", "example.net"])
        add(
            "date.month.wide",
            [
                "January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December",
            ]
        )
        add(
            "date.month.abbr",
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        )
        add(
            "date.weekday.wide",
            ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        )
        add("date.weekday.abbr", ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        add("date.time_zone", ["UTC", "Europe/London", "America/New_York", "Asia/Kolkata"])

        // A corpus that cannot be read is a programming error here, not a user error.
        let corpus = try! Corpus(bytes: builder.build())
        return LocaleCorpus(code: "en", chain: [corpus])
    }()
}
