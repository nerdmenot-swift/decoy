import Foundation

/// Given names and surnames for eight Indian languages that had none.
///
/// Fills `person.first_name.generic` and `person.last_name.generic` for `gu_IN`, `kn_IN`,
/// `ml_IN`, `mr_IN`, `or_IN`, `pa_IN`, `ta_IN` and `te_IN`.
///
/// ## Why this source and not a register
///
/// There is no register. India's Census runs to some two hundred tables under GODL and not
/// one of them counts names; neither Pakistan, Sri Lanka, Nepal nor Bangladesh publishes
/// anything comparable. Wikidata, which carries thousands of names for European languages,
/// has *nothing* usable for Tamil, Telugu, Kannada, Malayalam or Gujarati — under five
/// each. Five hundred million people, and the corpus answered for all of them in English.
///
/// `naamapadam` is a named-entity dataset: five and three quarter million sentences of
/// Indian-language text with person, place and organisation spans marked. It is CC0, which
/// is the only reason it is usable here.
///
/// ## What is taken, and what that avoids
///
/// **Single tokens, never a pair.** A person span is read for its parts and the parts are
/// counted separately; the given name and the surname that stood beside it are never stored
/// together. What ships is a vocabulary of name-words with frequencies, which is a register
/// in shape if not in origin. It is emphatically not the list of people the sentences were
/// about, and this project has turned down three such lists already.
///
/// ## Four filters, and what each is for
///
/// The tags were projected automatically from English word alignments rather than read by
/// anybody, so the raw output is roughly a third wrong. In order:
///
/// 1. **Script.** Every letter must belong to the language's own block. Indian news is full
///    of foreign names, and `ரூசோ` — Rousseau — is not a Tamil surname.
/// 2. **Length.** Three characters or more. Below that the tokens are initials: `கே`, `ஆர்`,
///    `எஸ்` are K, R and S, which is how Indian names are abbreviated in print.
/// 3. **Frequency band.** Between eight and two hundred occurrences. The floor removes
///    one-off alignment errors. The *ceiling* is the interesting one: the most frequent
///    "people" in Indian news are Modi, Gandhi — and `இயேசு`, `யெகோவா`, `அல்லாஹ்`,
///    `கடவுள்`, which are Jesus, Jehovah, Allah and God. A ceiling drops the celebrities
///    and the deities together, and leaves the ordinary names underneath.
/// 4. **Person ratio.** The token must be tagged as a person in at least four fifths of its
///    appearances. Without this the lists carry `ஒரு`, `மத்திய` and `உன்` — "a", "central"
///    and "your" — which appear thousands of times as ordinary words and a few times inside
///    a mis-projected span.
///
/// ## The fifth filter: case endings, learned rather than declared
///
/// These languages are agglutinative, so a name appears inflected — `பன்சாலியின்` is
/// *Bhansali's*, `ટ્રમ્પનું` is *Trump's*, `நயன்தாராவுடன்` is *with Nayanthara*. Roughly one
/// in three survivors carried an ending, which is not "slightly wrong data": it is a
/// possessive shipped as a surname, visible to any speaker.
///
/// Stripping them would normally need a morphological analyser per language — seven sets of
/// rules nobody here can verify, which is the same reason `decoy-authored` is English only.
/// So they are not declared. They are *learned from the file*: for every pair of candidates
/// where one is the other plus two to six characters, the difference is recorded, and an
/// ending seen on eight or more distinct stems is grammar rather than coincidence.
///
/// What that finds is exactly the case system — Tamil `வின்` and `வை`, Telugu `కి` and
/// `కు`, Marathi `ला`, `ने`, `चा`, `ची`, Gujarati `ની` and `ના`, Malayalam `റെ` and `യെ`.
/// Nothing about them was typed here.
///
/// Two details earn their place. Single characters are excluded, because a lone vowel sign
/// is ordinary spelling and dropping it would gut the lists. And the ending is matched
/// against the *word*, not against a stem that also had to survive filtering — `ટ્રમ્પનું`
/// stayed until that changed, because `ટ્રમ્પ` itself never qualified.
///
/// ## What is still wrong, and knowingly
///
/// About one name in five is a foreign name in local script: `டயானா` is Diana, `ਰਿਚਰਡ` is
/// Richard. Indian news is full of them and no filter here can tell them from native names,
/// because in this script they *are* names. Unlike an inflected form they are not
/// ungrammatical, only unlocalised, so they stay.
public struct IndicNamesAdapter: Adapter {
    public static let id = "indic-names"
    public static let sources = ["naamapadam"]

    public init() {}

    /// Locale, artifact, and the Unicode block its script occupies.
    static let languages: [(locale: String, artifact: String, script: ClosedRange<UInt32>)] = [
        ("kn_IN", "kannada", 0x0C80...0x0CFF),
        // Tamil is absent for the same reason Gujarati is, found the same way. Twenty
        // sampled surnames held six inflected — `யாதவும்` and `கோலியும்` are *and Yadav*
        // and *and Kohli*, `அலிக்கு` is *to Ali*, `ஷாவின்` is *Shah's*. Tamil's accusative
        // is a single grapheme, and single graphemes cannot be learned as endings without
        // also deleting ordinary spellings. Two thousand names, refused for one letter --
        // and refused after being built, which is the only way the rate was measurable.
        //
        // Telugu, Malayalam and Marathi are absent, and they are the three whose case
        // systems the learned endings could not clear. Marathi surnames came out half
        // inflected — `नेहवालची`, `सेंगरला`, `पांड्याने`, `धोनीने` are Nehwal's, to Sengar,
        // by Pandya, by Dhoni — and Telugu shipped `దోచుకుందువటే`, which is a verb. Their
        // markers attach where the learned set could not reach them without also deleting
        // ordinary spellings, and guessing at the difference would be inventing Marathi.
        //
        // Gujarati is absent, and it is the one language whose inflection could not be
        // filtered. Its ergative is a *single* vowel sign, and single characters are
        // excluded from the learned endings because in every one of these scripts a lone
        // vowel sign is ordinary spelling — admitting them would gut the lists. So
        // `પ્લેસિસે`, `ઈનાયતે` and `જફરે` survived every pass, which are du Plessis, Inayat
        // and Jafar with "-e" on the end. Two thousand names, refused for one vowel.
        //
        // Odia is absent, and it is the one language here the filters could not carry.
        // 196,793 sentences -- the smallest file but not by an order of magnitude -- yielded
        // six given names and seven surnames, against two thousand-odd for its neighbours.
        // Whatever the cause, six is not a language, so `or_IN` is not a locale.
        ("pa_IN", "punjabi", 0x0A00...0x0A7F),
    ]

    static let minimumLength = 3
    static let floor = 8
    static let ceiling = 200
    static let personRatio = 0.8
    /// Distinct stems an ending must attach to before it counts as grammar rather than a
    /// name that happens to end that way — `Mohandas` is not `Mohan` inflected.
    static let inflectionStems = 4

    /// Below this a language is not thin, the file is broken.
    static let minimumNames = 100

    public func run(_ input: AdapterInput) throws -> AdapterOutput {
        var contributions: [String: [String: Definition]] = [:]
        var stats: [(String, String)] = []

        for (locale, artifact, script) in Self.languages {
            guard input.locales.contains(locale) else { continue }

            let counts = try tally(input, artifact)
            var given = keep(counts.given, counts.other, script)
            var surnames = keep(counts.surname, counts.other, script)

            // Learned from every person token seen, not from the survivors. An ending is
            // only discoverable where both the bare name and the inflected form are in the
            // sample, and filtering removes most of both — Malayalam's `യുടെ` and `ുമായി`
            // went unlearned that way, so `ഗോപിയുടെ` and `പുടിനുമായി`, Gopi's and with
            // Putin, shipped as surnames.
            let vocabulary = Set(counts.given.keys).union(counts.surname.keys)
                .filter { $0.count >= 2 && $0.count <= 20 && inScript($0, script) }
            let endings = inflections(in: Set(vocabulary))
            given = given.filter { !isInflected($0, endings) }
            surnames = surnames.filter { !isInflected($0, endings) }

            guard given.count >= Self.minimumNames, surnames.count >= Self.minimumNames else {
                throw AdapterFailure.shapeChanged(
                    adapter: Self.id,
                    detail:
                        "\(locale): \(given.count) given and \(surnames.count) surnames survived "
                        + "filtering — verify the file before re-pinning")
            }

            contributions[locale] = [
                "person.first_name.generic": .list(given.map(Definition.string)),
                "person.last_name.generic": .list(surnames.map(Definition.string)),
            ]
            stats.append((locale, "\(given.count)+\(surnames.count)"))
        }

        guard !contributions.isEmpty else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "the roster carries none of this adapter's locales")
        }
        return AdapterOutput(contributions: contributions, stats: stats)
    }

    /// How often each token is the head of a person span, inside one, or neither.
    ///
    /// Streamed a line at a time. The training files run to 180 MB and holding one in memory
    /// as a single `String` — then again as parsed JSON — is most of a gigabyte for a file
    /// that is read once, forwards.
    private func tally(_ input: AdapterInput, _ artifact: String)
        throws -> (given: [String: Int], surname: [String: Int], other: [String: Int])
    {
        let directory = try input.artifact(artifact, for: Self.id)
        let training = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasSuffix("_train.json") }
        guard let training else {
            throw AdapterFailure.shapeChanged(
                adapter: Self.id, detail: "\(artifact): no *_train.json in the archive")
        }

        var given: [String: Int] = [:], surname: [String: Int] = [:], other: [String: Int] = [:]
        for line in Lines.split(String(decoding: try Data(contentsOf: training), as: UTF8.self)) {
            guard !line.isEmpty,
                let row = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                let words = row["words"] as? [String],
                let tags = row["ner"] as? [String],
                words.count == tags.count
            else { continue }

            for (word, tag) in zip(words, tags) {
                switch tag {
                case "B-PER": given[word, default: 0] += 1
                case "I-PER": surname[word, default: 0] += 1
                default: other[word, default: 0] += 1
                }
            }
        }
        return (given, surname, other)
    }

    /// The four filters, in the order that makes each cheap.
    private func keep(
        _ counts: [String: Int], _ other: [String: Int], _ script: ClosedRange<UInt32>
    ) -> [String] {
        var kept: [String] = []
        for (word, count) in counts {
            guard count >= Self.floor, count <= Self.ceiling else { continue }
            guard word.count >= Self.minimumLength, word.count <= 18 else { continue }
            guard Double(count) / Double(count + (other[word] ?? 0)) >= Self.personRatio
            else { continue }
            guard inScript(word, script) else { continue }
            kept.append(word)
        }
        return CodeUnitOrder.sorted(kept)
    }

    /// Endings that attach to many different stems, which makes them grammar.
    ///
    /// Compared on characters rather than scalars: a Devanagari or Tamil syllable is a
    /// consonant plus one or more combining marks, and splitting between them would produce
    /// endings that are half a letter.
    private func inflections(in pool: Set<String>) -> Set<String> {
        // Each word's own prefixes are looked up, rather than every pair being compared.
        // The vocabulary runs to tens of thousands of tokens per language and the pairwise
        // form is quadratic — it ran for ten minutes on one language and was still going.
        // This is five hash lookups a word.
        var stems: [String: Set<String>] = [:]
        for word in pool {
            let characters = Array(word)
            guard characters.count > 3 else { continue }
            for cut in 2...6 where characters.count - cut >= 3 {
                let stem = String(characters[..<(characters.count - cut)])
                guard pool.contains(stem) else { continue }
                stems[String(characters[(characters.count - cut)...]), default: []].insert(stem)
            }
        }
        return Set(stems.filter { $0.value.count >= Self.inflectionStems }.keys)
    }

    /// Ends in a learned case marker, with enough left over to have been a name.
    private func isInflected(_ word: String, _ endings: Set<String>) -> Bool {
        endings.contains { word.hasSuffix($0) && word.count - $0.count >= 3 }
    }

    /// Every letter belongs to the language's own block. Marks and punctuation pass.
    private func inScript(_ value: String, _ range: ClosedRange<UInt32>) -> Bool {
        var sawLetter = false
        for scalar in value.unicodeScalars where scalar.properties.isAlphabetic {
            sawLetter = true
            if !range.contains(scalar.value) { return false }
        }
        return sawLetter
    }
}
