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

    /// The version of *this locale's* data — the number to pin if you are keeping fixtures.
    ///
    /// Not the corpus release number. Those diverged on purpose: the release counts every
    /// change to every locale, so adding Hindi moved it for somebody using only English and
    /// told them their fixtures were at risk when nothing they drew from had changed. This
    /// moves when this locale's own data moves, and not otherwise.
    ///
    /// Read from the head of the chain, which is the locale itself. The corpora behind it
    /// carry their own versions and are reachable through `chain` for anyone who needs the
    /// whole picture — a locale that inherits half its data does depend on them, and saying
    /// so is more honest than folding four versions into one number.
    public var version: CorpusVersion? { chain.first?.version }

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

    /// Whether the chain declares `path` deliberately empty.
    ///
    /// ``resolve(_:)`` flattens "this locale says there is nothing here" and "nobody has
    /// this at all" into the same `nil`, which is right for drawing a value and wrong for
    /// deciding what to do about it. The first is a fact about the language and should
    /// yield an empty string; the second is a build error and should fail loudly.
    ///
    /// Six locales declare `person.suffix` empty and four declare the city affixes empty,
    /// so without this distinction `person.suffix()` traps on ordinary Russian or Italian
    /// records.
    public func declaresEmpty(_ path: String) -> Bool {
        for corpus in chain {
            guard let entry = try? corpus.lookup(path) else { continue }
            if case .explicitlyEmpty = entry { return true }
            return false
        }
        return false
    }

    /// The string table at `path`, if the chain has one.
    public func strings(_ path: String) -> StringTable? {
        guard case .strings(let table)? = resolve(path) else { return nil }
        return table
    }

    /// The narrowed chain starting at the first corpus carrying all of `requires`.
    ///
    /// Exists because a pattern and the parts it interpolates can come from different
    /// languages, and the result is not a degraded record but an incoherent one.
    ///
    /// Five locales — `zh_CN`, `zh_TW`, `vi`, `id_ID`, `yo_NG` — supply their own
    /// surnames and their own name pattern but no given names. Resolving each path on
    /// its own merits gave `zh_CN` the Han pattern `{{lastName}}{{firstName}}`, correct
    /// in having no separator, and then filled the second half from English: `ChengAaliyah`.
    /// Two scripts, no space, and nothing at the call site to suggest anything was wrong.
    ///
    /// Composing the whole name from wherever the parts come from yields `Aaliyah
    /// Bradley` — entirely English, a visible and honest fallback rather than a chimera.
    /// Narrowing only the *pattern* is not enough: that produced `Brenda 安期`, which
    /// fixed the spacing and left both languages exactly where they were.
    /// `lastName()` still returns 鄭, because a caller asking only for a surname is not
    /// building anything self-contradictory; it is the *composition* that has to agree
    /// with itself.
    public func agreeing(on requires: [String]) -> LocaleCorpus {
        agreeing(onAnyOf: [requires])
    }

    /// The same, where a locale can satisfy the requirement in more than one way.
    ///
    /// A locale supplies its own given names either by carrying `person.first_name.female`
    /// *and* `.male`, or by carrying `.generic` — Chinese does the second, because the
    /// source that made `zh_CN` possible counts how many people hold a name and not who
    /// they are. Asking only for the gendered pair sent `zh_CN` to English while its own
    /// 131 given names sat one path away, unreachable through `fullName` and reachable
    /// through `firstName`, which is the kind of inconsistency nothing would have reported.
    public func agreeing(onAnyOf groups: [[String]]) -> LocaleCorpus {
        for index in chain.indices {
            let corpus = chain[index]
            let satisfies = groups.contains { group in
                !group.isEmpty
                    && group.allSatisfy { required in
                        guard let entry = try? corpus.lookup(required) else { return false }
                        if case .explicitlyEmpty = entry { return false }
                        return true
                    }
            }
            if satisfies { return LocaleCorpus(code: code, chain: Array(chain[index...])) }
        }
        return self
    }

    /// Which gendered sub-lists are supplied by the first corpus in the chain that has
    /// either of them.
    ///
    /// Not "does the chain have `.female`" — the chain always does, because it ends at
    /// English. The question is which genders the locale supplies *itself*, at the point
    /// where it starts supplying any, so that a caller who did not ask for a gender can be
    /// given one the locale can actually answer for.
    ///
    /// `mk` is the case. It carries forty-seven Macedonian male given names and no female
    /// ones, so choosing a gender by coin toss sent half the draws to `.female`, found
    /// nothing in Macedonian, walked to English, and returned `Gabriella` beside a
    /// Macedonian surname. The coin was fair; the pool it was choosing between was not.
    public func gendersSupplied(at path: String) -> (female: Bool, male: Bool) {
        for corpus in chain {
            let female = supplies(corpus, "\(path).female")
            let male = supplies(corpus, "\(path).male")
            if female || male { return (female, male) }
        }
        return (false, false)
    }

    /// Present, and not a declaration that the locale deliberately has none.
    private func supplies(_ corpus: Corpus, _ path: String) -> Bool {
        guard let entry = try? corpus.lookup(path) else { return false }
        if case .explicitlyEmpty = entry { return false }
        return true
    }

    // MARK: - Coverage

    /// Whether this locale answers for `field` in its own language.
    ///
    /// `false` does not mean the field is unavailable — every field generates for every
    /// locale, because the chain ends at English. It means the values will be another
    /// language's. That distinction is the whole point of asking:
    ///
    /// ```swift
    /// let locale = try DecoyLocales.locale("hi_IN")
    /// locale.supplies(.givenNames)   // true  — Devanagari names
    /// locale.supplies(.streets)      // false — street names would come out English
    /// ```
    ///
    /// Asked of the locale itself, not the chain. `de_AT` inherits German names and reports
    /// `false` here, which is honest about where they come from — the chain is public for
    /// anyone who wants to ask what the ancestors carry.
    public func supplies(_ field: LocaleField) -> Bool {
        guard let corpus = chain.first else { return false }
        return field.requirements.contains { alternative in
            !alternative.isEmpty && alternative.allSatisfy { supplies(corpus, $0) }
        }
    }

    /// Every field this locale answers for itself, in declaration order.
    public var nativeFields: [LocaleField] {
        LocaleField.allCases.filter(supplies)
    }

    /// How much of its own data this locale carries.
    ///
    /// Measured against what a locale *can* have rather than against every field, because
    /// three of them are English-only by policy and counting those would put the top of the
    /// scale out of reach for everybody. See ``LocaleField/englishOnly``.
    public var tier: LocaleTier {
        let achievable = LocaleField.achievable
        let own = achievable.filter(supplies).count
        if own >= achievable.count - 1 { return .complete }
        // Above the universal set — names, cities, addresses, phones, subdivisions,
        // countries and compass — but not near the top.
        if own >= 9 { return .extended }
        return .core
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
        // A model always has something to say — that is the point of it.
        case .model: return true
        case .explicitlyEmpty, nil: return false
        }
    }

    // MARK: - Coverage

    /// The paths in this chain that a locale could meaningfully define for itself.
    ///
    /// Everything the chain resolves *except* what comes from its last corpus, which is
    /// language-neutral by construction: `base` carries media types, country codes, time
    /// zones and emoji, and there is no Japanese answer to `image/png`. Counting those
    /// as fields Japanese has failed to supply put its coverage at 5% — of 1,145 paths,
    /// 1,016 of them media types — which is not a fact about Japanese.
    ///
    /// A single-corpus chain has no language-neutral tail to exclude, so it is all of it.
    var languageBearingPaths: [String] {
        get throws {
            guard chain.count > 1 else { return try paths.map(\.path).filter(Self.bearsLanguage) }
            var seen = Set<String>()
            for corpus in chain.dropLast() {
                for entry in try corpus.paths where Self.bearsLanguage(entry.path) {
                    seen.insert(entry.path)
                }
            }
            return seen.sorted()
        }
    }

    /// Whether a path is a field a locale could translate, rather than a key in a table.
    ///
    /// `location.postcode_by_state` holds one entry per subdivision — fifty-one for the
    /// United States alone — and every one is a digit mask rather than a word. Counting
    /// them as fifty-one fields a locale has failed to translate put English 51 paths ahead
    /// of everybody and pushed every other locale's coverage down by a sixth, for a feature
    /// no other country even has.
    ///
    /// The same correction the `__keys` tables needed, and it moves the number the same
    /// way: down for English, up for everyone else, and closer to what the reader thinks it
    /// means. The postcode feature is still measured — `location.postcode` is one path, and
    /// a locale either has its own mask or does not.
    ///
    /// ## The invented namespaces, and a reversal
    ///
    /// `whimsy`, `sport` and `beverage` were deliberately *left in* this count when they
    /// landed, on the reasoning that a Japanese caller reaching for a pub name really does
    /// get English, so it should show up as a gap. The threshold moved down twice to
    /// accommodate that, and when `system.error_*` and `commerce.review_*` arrived it would
    /// have moved a third time — Japanese fell to 28% having lost nothing.
    ///
    /// That reasoning contradicted this function's own contract, which is *a field a locale
    /// could translate*. An invented pub name is not a field anybody translates; it is
    /// content this library authors, in English, and no registry will ever publish a
    /// Japanese equivalent because there is nothing to publish. Counting it meant every
    /// whimsical addition silently downgraded all sixty-three other locales, so the number
    /// measured how much invention had been added rather than how local a locale was.
    ///
    /// A locale that reaches for these still gets English, and that is worth knowing — but
    /// it belongs in the matrix, which has an `Invented names` column showing exactly one
    /// native locale, rather than in a ratio it distorts. `decoy-inspect --coverage` prints
    /// the excluded count so the exclusion is visible rather than silent.
    public static func bearsLanguage(_ path: String) -> Bool {
        if path.hasPrefix("location.postcode_by_state.") { return false }
        return !isEnglishOnlyByPolicy(path)
    }

    /// Namespaces Decoy has committed never to localise.
    ///
    /// Two groups, and they are excluded for **different** reasons — worth keeping
    /// straight, because collapsing them is how this exclusion would become the tuning it
    /// is meant not to be.
    ///
    /// `whimsy`, `sport`, `beverage`, `system.error_` and `commerce.review_` are
    /// *invented*. There is no Japanese equivalent of an invented pub name because there
    /// is nothing to equate it to; no registry can ever publish one.
    ///
    /// `animal`, `food`, `nature`, `media`, `notable`, `brand` and `institution` are
    /// different: an otter plainly has a Japanese name, so these are translatable in a way
    /// the first group is not. They are excluded because Decoy has stated it will not
    /// translate them — writing a Japanese animal list would mean producing an
    /// unverifiable foreign-language fact list, and the `common-knowledge` descriptor
    /// already concedes that the English one is unverified. Doing it seven times over in
    /// languages the author cannot check would be inventing, not sourcing.
    ///
    /// What is *not* excluded is the case these are often confused with: `person.job_title`
    /// and `commerce.department` are English-only today and still count, because a French
    /// occupational registry exists and could replace them. Those are gaps. These are
    /// decisions.
    ///
    /// The justification for excluding at all is what the warning claims — *"records will
    /// be largely another language's data"*. Before this, `ja` read 28% while being 100%
    /// native for colours and dates, 80% for location and 60% for person, which is to say
    /// the warning would have been false about every field a Japanese caller actually
    /// generates. The matrix carries `Invented names` and `Real-world lists` columns so the
    /// English-only reality of both groups stays visible where it is true.
    public static func isEnglishOnlyByPolicy(_ path: String) -> Bool {
        let invented = ["whimsy.", "sport.", "beverage.", "system.error_", "commerce.review_"]
        let untranslated = [
            "animal.", "food.", "nature.", "media.", "notable.", "brand.", "institution.",
        ]
        for prefix in invented + untranslated where path.hasPrefix(prefix) { return true }
        return false
    }

    /// How many paths a locale in this chain could meaningfully define. The
    /// denominator behind ``nativeCoverage``, exposed so the compiler can print the
    /// fraction rather than only the percentage.
    public var languageBearingPathCount: Int {
        get throws { try languageBearingPaths.count }
    }

    /// What share of the language-bearing paths in this chain the locale supplies
    /// itself, 0 to 1.
    ///
    /// `ta_IN` reads about 0.11: eleven paths of its own, and everything else — names,
    /// company names, most vocabulary — arriving from English through the chain. A
    /// fixture set built from it is largely English wearing a Tamil label, and nothing
    /// about the call site says so.
    ///
    /// Walks the chain's path lists, so it is a setup-time question rather than
    /// something to ask per row.
    public var nativeCoverage: Double {
        get throws {
            let denominator = try languageBearingPaths.count
            guard denominator > 0 else { return 0 }
            let own = Set(try nativePaths.map(\.path))
            let covered = try languageBearingPaths.filter { own.contains($0) }.count
            return Double(covered) / Double(denominator)
        }
    }

    /// Language-bearing paths the locale inherits rather than defines, sorted.
    ///
    /// The actionable half of ``nativeCoverage``: a number says a locale is thin, and
    /// this says which fields to go and find data for.
    public var inheritedPaths: [String] {
        get throws {
            let own = Set(try nativePaths.map(\.path))
            return try languageBearingPaths.filter { !own.contains($0) }
        }
    }

    /// A description of how much of this locale is really a fallback, or `nil` when
    /// `threshold` is met.
    ///
    /// Deliberately a returned value rather than something printed.
    ///
    /// A library that writes to stderr is a library you have to work out how to silence,
    /// and doing it here would mean Decoy's first piece of global mutable state — a
    /// process-wide "have I already warned about this locale" set — introduced to
    /// deduplicate a message nobody asked for. It would also have to be computed
    /// somewhere, and `Faker.init` runs once per row.
    ///
    /// The failure this guards against is caught in review or in a test, not at three in
    /// the morning in production, so it is shaped as something a test can assert on:
    ///
    /// ```swift
    /// #expect(DecoyLocaleDE.locale.fallbackWarning() == nil)
    /// ```
    public func fallbackWarning(threshold: Double = 0.3) -> String? {
        guard let coverage = try? nativeCoverage, coverage < threshold else { return nil }
        let percent = Int((coverage * 100).rounded())
        let inherited = (try? inheritedPaths.count) ?? 0
        return """
            locale '\(code)' defines \(percent)% of its fields itself; the other \
            \(inherited) resolve through the fallback chain \
            (\(chain.count) corpora). Records generated from it will be largely \
            \(chain.count > 1 ? "another language's data" : "unavailable") wearing a \
            '\(code)' label. Inspect with: decoy-inspect --coverage Corpus/binary
            """
    }
}

// MARK: - Built-in corpus

extension LocaleCorpus {

    /// A deliberately tiny English corpus, compiled in memory at first use.
    ///
    /// **This is a smoke-test stub, not a working corpus.** It defines ten paths — first
    /// and last names, a few domain suffixes, month and weekday names, time zones — and
    /// nothing else. Every other generator traps against it, so `company.name()`,
    /// `lorem.word()`, `location.city()` and most of the API need a real locale:
    ///
    /// ```swift
    /// import DecoyLocaleEN
    /// Forge<User>("user") { User() }.locale(DecoyLocaleEN.locale)
    /// ```
    ///
    /// It exists so the library has no hard dependency on a blob being present, and it
    /// uses the same paths as the compiled locales, so swapping in a real one changes
    /// nothing but the data.
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
        // `location.time_zone`, not `date.time_zone`: both `date.timeZone()` and
        // `location.timeZone()` read this one path, so the corpus carries it once.
        add(
            "location.time_zone",
            ["UTC", "Europe/London", "America/New_York", "Asia/Kolkata"]
        )

        // A corpus that cannot be read is a programming error here, not a user error.
        let corpus = try! Corpus(bytes: builder.build())
        return LocaleCorpus(code: "built-in", chain: [corpus])
    }()
}
