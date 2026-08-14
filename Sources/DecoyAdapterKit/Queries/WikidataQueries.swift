import Foundation

/// The three Wikidata snapshots: given names and surnames, colour vocabulary, and a handful
/// of small closed concept sets.
///
/// ## Why Wikidata rather than scraping
///
/// Wikidata is CC0: no attribution required, no share-alike, nothing to reconcile with
/// Apache-2.0. It is also a database with a query interface rather than pages to scrape,
/// which matters beyond politeness — scraped content carries whatever licence the page had,
/// usually all-rights-reserved or CC BY-SA, and a corpus that cannot say where a value came
/// from is the thing this project exists to replace.
public enum WikidataQueries {

    // MARK: - Names

    /// Wikidata classes for the three things wanted.
    public static let nameClasses: [(kind: String, id: String)] = [
        ("female", "Q11879590"),
        ("male", "Q12308941"),
        ("surname", "Q101352"),
    ]

    /// Locale to the Wikidata item for its language.
    ///
    /// `P407` — "language of work or name" — is what ties a name to a language, and it is
    /// the property that makes this usable at all: without it a query returns every name
    /// that happens to have a German *label*, which is every name in the world.
    ///
    /// Every QID here was checked against Wikidata's own label rather than typed from
    /// memory: a wrong one returns nothing, which reads as "Wikidata has no Zulu names"
    /// instead of "that is not Zulu".
    public static let nameLanguages: [(code: String, id: String)] = [
        ("de", "Q188"), ("es", "Q1321"), ("it", "Q652"), ("pt", "Q5146"), ("nl", "Q7411"),
        ("pl", "Q809"), ("sv", "Q9027"), ("da", "Q9035"), ("nb", "Q9043"), ("fi", "Q1412"),
        ("cs", "Q9056"), ("sk", "Q9058"), ("tr", "Q256"), ("ru", "Q7737"), ("uk", "Q8798"),
        ("el", "Q9129"), ("hu", "Q9067"), ("ro", "Q7913"), ("hr", "Q6654"), ("sl", "Q9063"),
        ("lv", "Q9078"), ("lt", "Q9083"), ("et", "Q9072"), ("id", "Q9240"), ("vi", "Q9199"),
        ("th", "Q9217"), ("fa", "Q9168"), ("he", "Q9288"), ("ar", "Q13955"), ("ja", "Q5287"),
        ("ko", "Q9176"), ("zh", "Q7850"), ("hi", "Q1568"), ("fr", "Q150"), ("en", "Q1860"),
        ("af", "Q14196"), ("az", "Q9292"), ("bn", "Q9610"), ("cy", "Q9309"), ("dv", "Q32656"),
        ("eo", "Q143"), ("hy", "Q8785"), ("ka", "Q8108"), ("ku", "Q36368"), ("mk", "Q9296"),
        ("mn", "Q9246"), ("ne", "Q33823"), ("sr", "Q9299"), ("ta", "Q5885"), ("ur", "Q1617"),
        ("uz", "Q9264"), ("yo", "Q34311"), ("zu", "Q10179"),
    ]

    /// Below this a locale keeps whatever it had.
    public static let minimumNames = 40

    /// The triple order matters and is not stylistic.
    ///
    /// Putting `wdt:P407` first narrows to one language before touching the label index;
    /// putting `wdt:P31` first makes the engine consider every family name in Wikidata —
    /// about a million of them — and the query times out. That is the difference between
    /// this working and not.
    public static func nameQuery(class classID: String, language languageID: String, code: String)
        -> String
    {
        """
        SELECT DISTINCT ?l WHERE {
          ?i wdt:P407 wd:\(languageID) ;
             wdt:P31 wd:\(classID) ;
             rdfs:label ?l .
          FILTER(LANG(?l) = "\(code)")
        } LIMIT 4000
        """
    }

    // MARK: - Colours

    /// Wikidata's item for the concept "colour". Everything wanted is an instance of it.
    public static let colour = "Q1075"

    /// Below this a locale keeps what it had.
    ///
    /// Colour vocabularies are small by nature — English ships forty-five — so the floor is
    /// lower than the one for names. Twelve is about where a fixture set stops repeating the
    /// same three words on every row.
    public static let minimumColours = 12

    /// Locale to the Wikidata item for its language.
    ///
    /// The set is the locales that carried colour names before this existed, so the change
    /// is a replacement rather than an expansion. Several are locale codes rather than bare
    /// languages: they map to the same language item as their parent, because Wikidata
    /// labels are per language and not per region — the regional split lives in Decoy's
    /// chain, not here.
    public static let colourLanguages: [(code: String, id: String)] = [
        ("ar", "Q13955"), ("az", "Q9292"), ("cy", "Q9309"), ("de", "Q188"), ("el", "Q9129"),
        ("eo", "Q143"), ("es", "Q1321"), ("es_MX", "Q1321"), ("fa", "Q9168"), ("fr", "Q150"),
        ("he", "Q9288"), ("hu", "Q9067"), ("hy", "Q8785"), ("id_ID", "Q9240"),
        ("ja", "Q5287"), ("ko", "Q9176"), ("lv", "Q9078"), ("nb_NO", "Q9043"),
        ("nl", "Q7411"), ("pl", "Q809"), ("pt_BR", "Q5146"), ("pt_PT", "Q5146"),
        ("ru", "Q7737"), ("sv", "Q9027"), ("th", "Q9217"), ("tr", "Q256"), ("ur", "Q1617"),
        ("zh_CN", "Q7850"), ("zh_TW", "Q7850"), ("dv", "Q32656"), ("ku_kmr_latin", "Q36368"),
        ("mn_MN_cyrl", "Q9246"), ("uz_UZ_latin", "Q9264"),
    ]

    /// The English label comes back alongside the target one, and it is what makes this
    /// usable.
    ///
    /// A Wikidata label tagged `fr` is not necessarily French. Where nobody has translated
    /// an item, contributors routinely paste the English string in and tag it anyway, so the
    /// first run put `Fallow`, `Flax` and `Alvon` in the French colour list.
    public static func colourQuery(language tag: String) -> String {
        """
        SELECT DISTINCT ?l ?en WHERE {
          ?i wdt:P31 wd:\(colour) ;
             rdfs:label ?l .
          FILTER(LANG(?l) = "\(tag)")
          OPTIONAL { ?i rdfs:label ?en FILTER(LANG(?en) = "en") }
        } LIMIT 1000
        """
    }

    /// Whether two labels are the same word entered by two different people.
    ///
    /// Compared case-insensitively, because the two labels agree on the word without
    /// agreeing on the capital. `Fallow`, `Flax` and `Isabelle` all survived an exact
    /// comparison against an English `fallow`, `flax` and `isabelle`, which is the whole
    /// failure this check exists to prevent.
    public static func sameWord(_ left: String, _ right: String) -> Bool {
        left.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == right.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The language subtag Wikidata labels are tagged with, which is not the locale code.
    public static func subtag(of code: String) -> String {
        String(code.split(separator: "_")[0])
    }

    // MARK: - Terms

    /// The concept sets, each an explicit member list in its conventional order.
    ///
    /// Every identifier here was looked up, not recalled, and that matters more than it
    /// sounds. The first attempt at the intercardinals guessed `Q1704632` for northeast; it
    /// is a man called Josef Gabriel, and `Q1704634` is a wolf spider. A wrong identifier
    /// does not fail loudly — it returns a plausible label in the right language and quietly
    /// puts a spider in the compass.
    ///
    /// The cardinals came from CLDR's `coordinateUnit` first, on the grounds that it gives
    /// the compass form — German `Nord` rather than `Norden`. Checking more than two locales
    /// killed that: `coordinateUnit` labels a *latitude or longitude*, not a bearing.
    /// Japanese returns 北緯, "north latitude"; Welsh returns `i'r gogledd`, "to the north".
    /// The cost is that German gets the noun `Norden`, which is a real if small imprecision
    /// taken knowingly — the alternative was a source correct for German and wrong for
    /// Japanese.
    ///
    /// The zodiac is named explicitly rather than enumerated. Enumerating the class returned
    /// thirteen: Ophiuchus is a real instance of "occidental astrological sign" and belongs
    /// to the thirteen-sign zodiac rather than to the twelve that `western_zodiac_sign`
    /// means.
    public static let termSets: [(name: String, members: [String])] = [
        ("direction_cardinal", ["Q659", "Q684", "Q667", "Q679"]),
        ("direction_ordinal", ["Q6497686", "Q5491373", "Q6452640", "Q2381698"]),
        (
            "western_zodiac_sign",
            [
                "Q32067", "Q164016", "Q129214", "Q161701", "Q159816", "Q134061", "Q134394",
                "Q134398", "Q2194186", "Q164272", "Q162119", "Q1254190",
            ]
        ),
        ("sex", ["Q6581097", "Q6581072"]),
    ]

    public static func termQuery(members: [String]) -> String {
        """
        SELECT ?i ?l WHERE {
          VALUES ?i { \(members.map { "wd:\($0)" }.joined(separator: " ")) }
          ?i rdfs:label ?l .
        }
        """
    }

    /// Every member in the language, or nothing.
    ///
    /// The untranslated-label check the colours need would be actively wrong here: Spanish
    /// for Aries is `Aries`, and dropping a label for matching English would delete a
    /// correct translation from half the zodiac.
    ///
    /// A closed set admits a better check anyway. If a language has labels for all twelve
    /// signs it has been translated; if it has nine, somebody is part-way through and the
    /// gaps would ship as a set that silently lacks Capricorn. So it is all or nothing,
    /// which is exact and needs no guessing about what a word looks like.
    public static func completeSetsOnly(_ bindings: [[String: Any]], order: [String])
        -> [(key: String, value: OrderedJSON)]
    {
        // Languages in the order the endpoint first mentions them, because a dictionary
        // would reorder the file on every run for no reason anybody could read.
        var languages: [String] = []
        var found: [String: [String: String]] = [:]

        for binding in bindings {
            guard let uri = Endpoint.value(binding, "i"),
                let label = Endpoint.value(binding, "l"),
                let language = Endpoint.language(binding, "l")
            else { continue }
            if found[language] == nil { languages.append(language) }
            found[language, default: [:]][Endpoint.qid(uri)] = label
        }

        var out: [(key: String, value: OrderedJSON)] = []
        for language in languages {
            let values = order.compactMap { found[language]?[$0] }
            guard values.count == order.count else { continue }
            // Deduplicated because a language can give two members the same word, and a set
            // that reads ["north-east", "north-east", …] is worse than one simply absent.
            guard Set(values.map(CodeUnitOrder.key)).count == values.count else { continue }
            out.append((language, .array(values.map(OrderedJSON.string))))
        }
        return out
    }
}
