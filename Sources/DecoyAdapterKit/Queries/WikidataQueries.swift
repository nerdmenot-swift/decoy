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
        // South Asia, which this table had almost entirely missed: Telugu, Marathi and
        // Tamil have seventy-five to eighty-five million speakers each and had never been
        // asked about. Wikidata's answer is thin today — Gujarati has three surnames and
        // no given names at all — and that is worth recording rather than assuming. Being
        // in the table means the next refresh picks up whatever has been catalogued since;
        // a language absent from it stays absent however much it grows.
        ("pa", "Q58635"), ("gu", "Q5137"), ("mr", "Q1571"), ("te", "Q8097"),
        ("kn", "Q33673"), ("ml", "Q36236"), ("si", "Q13267"), ("or", "Q33810"),
        ("as", "Q29401"),
    ]

    /// Below this a category is not written, and the locale keeps whatever it had.
    ///
    /// The floor exists so a query that half-worked cannot ship three names as though they
    /// were a language. It was forty, which is a reasonable guess and was wrong: Wikidata
    /// catalogues thirteen Welsh surnames, thirty-one Macedonian and twenty-one Bengali,
    /// all real, all CC0, all already fetched — and forty threw every one of them away.
    ///
    /// What the floor actually chose, in those locales, was `Riley Bonneau` over `Bevan`.
    /// A small list of the right language beats a large list of the wrong one, because the
    /// point of a locale is that it is that locale. Thirteen surnames against Welsh's 230
    /// given names is some three thousand distinct full names, which is not a repetition
    /// problem.
    ///
    /// Ten was the next guess and it was still one too many, by three names.
    ///
    /// `mk` has thirty-one Macedonian surnames and forty-seven male given names, and seven
    /// female ones — so it was the last locale in the corpus answering in a language that
    /// was not its own, on a margin of three. Five, then, which is the point where a list
    /// stops being a list: below it a "language" is one or two names repeated, and that is
    /// worse than an honest fallback because it looks deliberate.
    ///
    /// The reasoning is the same one that put `minimumColours` at twelve. A language with
    /// few catalogued names is not a language with few names; it is one Wikidata has not
    /// finished. The [locale matrix](../../../docs/locale-support.md) publishes what each
    /// locale actually carries, so a thin list is visible rather than implied.
    public static let minimumNames = 5

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

    // MARK: - Romanised names

    /// Locales whose names are another language's, written in Latin script.
    ///
    /// `en_IN` is the case this exists for. It carried no names of its own, so it inherited
    /// `en`'s — which meant an Indian city, an Indian postcode and "Jennifer Williams" on
    /// the same row. India's English-language records are full of Indian names in Latin
    /// script, and that is the one thing the corpus could not produce.
    ///
    /// The names are already here: the same Wikidata items that supply `hi_IN` its
    /// Devanagari names carry an English label too, which is the romanised form. So this is
    /// the existing name query with the label filter moved to `en` — no new source, no new
    /// licence, and the pool spans the nine languages rather than one, which is right for a
    /// pan-Indian locale.
    ///
    /// Not a transliteration. Deriving `Anjali` from `अंजली` mechanically means a rule per
    /// script and a choice between competing romanisations, and Wikidata already holds the
    /// spelling people actually use.
    public static let romanisedNameLocales: [(code: String, languages: [String])] = [
        (
            "en_IN",
            [
                "Q1568",  // Hindi
                "Q9610",  // Bengali
                "Q5885",  // Tamil
                "Q8097",  // Telugu
                "Q1571",  // Marathi
                "Q5137",  // Gujarati
                "Q58635",  // Punjabi
                "Q33673",  // Kannada
                "Q36236",  // Malayalam
            ]
        )
    ]

    /// The language codes `romanisedNameLocales` spans, in the order its QIDs are listed.
    ///
    /// Kept beside the QIDs so `verifyLanguageQIDs` can check one against the other. This
    /// list existed only as a trailing comment on each QID, and a comment cannot be wrong
    /// in a way anything notices: `Q33298` sat behind `// Kannada` and is Filipino.
    public static let romanisedLanguageCodes = [
        "hi", "bn", "ta", "te", "mr", "gu", "pa", "kn", "ml",
    ]

    public static func romanisedNameQuery(class classID: String, languages: [String]) -> String {
        """
        SELECT DISTINCT ?l WHERE {
          VALUES ?lang { \(languages.map { "wd:\($0)" }.joined(separator: " ")) }
          ?i wdt:P407 ?lang ;
             wdt:P31 wd:\(classID) ;
             rdfs:label ?l .
          FILTER(LANG(?l) = "en")
        } LIMIT 4000
        """
    }

    // MARK: - Lexemes

    /// Everyday vocabulary, from Wikidata's lexeme entities.
    ///
    /// Vocabulary was the widest remaining gap after streets — fourteen roots of forty-five
    /// — and the Open Multilingual Wordnet cannot close it. The fourteen already wired up
    /// are precisely the permissively-licensed ones; every remaining OMW language is CC
    /// BY-SA or CeCILL-C, checked by reading the licence each archive declares rather than
    /// a table about them. Share-alike would put the whole corpus's Apache-2.0
    /// redistribution in question for the sake of one field.
    ///
    /// Lexemes are a different part of Wikidata from the items the name and colour queries
    /// read: `L`-entities carrying a lemma, a language and a lexical category, contributed
    /// for dictionary purposes. Same project, same CC0, same query endpoint — no new
    /// licence to clear and no new fetch machinery.
    ///
    /// Coverage is very uneven and the floor is what handles that: German, French and
    /// Russian return thousands, Ukrainian hundreds, and Macedonian five. A language below
    /// the floor keeps the English it already had.
    public static let noun = "Q1084"

    /// Below this a locale keeps what it had.
    ///
    /// Higher than the name floor, because these words are not composed with anything. A
    /// name draws from two lists and multiplies; a noun is drawn alone, so fifty of them is
    /// the point where a sentence stops obviously reusing the same handful.
    public static let minimumLexemes = 50

    /// Locale to the Wikidata item for its language.
    ///
    /// Only locales that do not already have vocabulary from a wordnet. Where both exist the
    /// wordnet wins: it is curated for sense rather than contributed for the dictionary, and
    /// two adapters claiming `word.noun` is refused by the orchestrator anyway.
    public static let lexemeLanguages: [(code: String, id: String)] = [
        ("ar", "Q13955"), ("az", "Q9292"), ("bn_BD", "Q9610"), ("cs_CZ", "Q9056"),
        ("cy", "Q9309"), ("de", "Q188"), ("fa", "Q9168"), ("fr", "Q150"),
        ("hi_IN", "Q1568"), ("hu", "Q9067"), ("hy", "Q8785"), ("ka_GE", "Q8108"),
        ("kn_IN", "Q33673"), ("ko", "Q9176"), ("lv", "Q9078"), ("mk", "Q9296"),
        ("nl", "Q7411"), ("pa_IN", "Q58635"), ("pt_BR", "Q5146"), ("pt_PT", "Q5146"),
        ("ro", "Q7913"), ("ru", "Q7737"), ("sk", "Q9058"), ("sl_SI", "Q9063"),
        ("tr", "Q256"), ("uk", "Q8798"), ("vi", "Q9199"), ("zh_TW", "Q7850"),
    ]

    /// Every noun lemma recorded for one language.
    ///
    /// `LIMIT 5000` because the largest languages exceed it and a truncated list of common
    /// nouns is still a list of common nouns — unlike a name list, where truncation would
    /// bias toward whatever the endpoint happened to order first. Nothing here is weighted,
    /// so the cut costs variety rather than correctness.
    /// The ten roots this cannot reach, and why looking again is not worth it.
    ///
    /// `az, cy, hi, hy, kn, mk, ne, sr, vi, yo` have no vocabulary of their own. Measured
    /// against the endpoint on 2026-08-31: Welsh, Armenian, Kannada, Macedonian,
    /// Vietnamese, Nepali and Serbian have **zero** noun lexemes, and Hindi has three
    /// lexemes in total across every category. Azerbaijani is different — it has 138, but
    /// only 36 are Latin, which is under the floor, and `filters.json` says so.
    ///
    /// Two other routes were tried and rejected rather than left as open questions:
    ///
    /// - **Wikidata items instead of lexemes**, the trick the colour adapter uses. It does
    ///   not transfer. Six everyday classes returned 60 single-word Hindi labels of which a
    ///   good half were transliterated foreign dishes — tzatziki, cassata, rødgrød — plus
    ///   the biscuit brand पार्ले-जी and an untranslated `blueberry`. Items are encyclopedic
    ///   entities; a lexeme is curated as a word. For a closed set like colours that
    ///   distinction does not bite, and for open vocabulary it decides the whole result.
    /// - **Hugging Face.** The Hindi sets are `cc-by-nc-sa` or carry no licence tag at all,
    ///   and a tag describes the uploader's upload rather than their right to license what
    ///   they collected.
    ///
    /// So these ten inherit their vocabulary, which the matrix records honestly. Closing
    /// them wants somebody to contribute lexemes upstream, not a different query here.
    public static func lexemeQuery(language id: String) -> String {
        """
        SELECT DISTINCT ?lemma WHERE {
          ?l dct:language wd:\(id) ;
             wikibase:lexicalCategory wd:\(noun) ;
             wikibase:lemma ?lemma .
        } LIMIT 5000
        """
    }

    // MARK: - Colours

    /// Wikidata's item for the concept "colour". Everything wanted is an instance of it.
    public static let colour = "Q1075"

    /// Below this a locale keeps what it had.
    ///
    /// Colour vocabularies are small by nature — English ships forty-five — so the floor is
    /// lower than the one for names. That sentence was written when the names floor was
    /// forty; it is five now, and twelve stopped being "lower" some time ago without anyone
    /// noticing, because a constant does not announce that the thing it was set relative to
    /// has moved.
    ///
    /// Five, then, and for the same reason: below that a list is one or two words repeated,
    /// which is worse than an honest fallback because it looks deliberate. Above it, a
    /// Slovak or Vietnamese fixture says its colours in Slovak or Vietnamese.
    public static let minimumColours = 5

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
        // Nepali, checked before adding rather than added hopefully: six single-word
        // Devanagari terms — सेतो, गुलाबी, मरून, बैजनी, कागती, जैतुन — which clears the
        // floor of five with one to spare. Latvian is the counter-example and is why the
        // checking happens first: it is in this table, returns seven labels, and five of
        // them are two-word noun phrases that the single-word rule drops.
        ("ne_NP", "Q33823"),
        // The seventeen roots this table had simply never been extended to. Colours were
        // the widest gap after names -- twenty-four of forty-five roots -- and closing it
        // costs one query each against a source already in use, under a licence already
        // cleared. Every one of these locales gains a field it was answering for in
        // English.
        ("bn_BD", "Q9610"), ("cs_CZ", "Q9056"), ("da", "Q9035"), ("fi", "Q1412"),
        ("hi_IN", "Q1568"), ("hr", "Q6654"), ("it", "Q652"), ("ka_GE", "Q8108"),
        ("kn_IN", "Q33673"), ("mk", "Q9296"), ("pa_IN", "Q58635"), ("ro", "Q7913"),
        ("sk", "Q9058"), ("sl_SI", "Q9063"), ("uk", "Q8798"), ("vi", "Q9199"),
        ("yo_NG", "Q34311"),
        // Two roots are deliberately absent, both for script rather than availability.
        //
        // `sr_RS_latin` is written in Latin here and Wikidata labels Serbian in Cyrillic;
        // the names adapter transliterates for exactly this reason and the colour adapter
        // does not, so adding it would put Cyrillic colours beside Latin names.
        //
        // `ne_NP` is romanised, because the only Nepali given names anybody publishes are.
        // Devanagari colours would sit beside Latin names in the same fixture. English
        // colours are at least the same script, which makes the fallback the coherent
        // answer rather than the lazy one.
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
    ///
    /// Four language roots fail it and are worth naming, because the matrix shows them as
    /// gaps and the obvious next move is to go looking for a source that does not exist.
    /// Measured against the live endpoint on 2026-08-30: Bengali has eleven of the twelve,
    /// Armenian nine, and Kannada and Yoruba none at all. There is nothing to fetch — the
    /// translations have not been made — so those four inherit the zodiac from their
    /// fallback chain, and the honest fix is upstream in Wikidata rather than here.
    ///
    /// Do not lower this to a threshold to close them. Bengali at eleven of twelve is the
    /// exact case the rule is for: it would ship as a complete-looking set missing one sign.
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
