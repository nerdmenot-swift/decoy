# Changelog

Decoy has two version numbers, and the one that matters to you depends on what you are
worried about.

**The corpus version** is the fixture-stability contract. `generate(seed:)` is reproducible
*with respect to a particular corpus*, so a change to the data is a change to everybody's
fixtures. Adding data is a minor bump; changing or removing an existing value is a major
one, because somebody has already generated rows from it.

**The package version** covers the library. Generated output can move without the corpus
moving — a change to how a name is composed does it — so a release note saying "corpus
unchanged" is not the same as saying "your fixtures are unchanged". Both are recorded
below, and anything that alters drawn values says so in bold.

Entries are grouped by the corpus version in force when they landed.

## 1.0.0 — 2026-09-06

The first release. A `v1.0.0` tag existed briefly before this and was withdrawn while
nothing depended on it, so that the shape of the release could be settled first — the
window in which breaking changes cost nothing closes at the moment somebody adopts it, and
it was worth spending.

The package version starts here and follows semantic versioning; the corpus is already at
64.0.0 and keeps its own numbering, so the two are not going to line up and are not meant to —
the corpus counts changes to the *data*, and there have been sixty-four of those before the
library ever had a version at all.

Which of the two you need depends on what you are protecting. Pin the package for the API;
pin the corpus if you are keeping generated fixtures, because that is the number a seed's
output moves with.

### Added since the withdrawn tag

The work the tag was withdrawn for. Each of these was free to do only because nothing
depended on 1.0.0 yet.

- **Vocabulary in thirty-three languages, up from fourteen.** Not more wordnets: the
  fourteen already wired up are exactly the permissively licensed ones, and every remaining
  Open Multilingual Wordnet language is CC BY-SA or CeCILL-C — established by reading the
  licence each archive declares rather than a table describing them. Wikidata *lexemes* are
  a different part of Wikidata from the items the name adapters read, CC0, with no new
  licence to clear.

- **Geography in the script the country writes in.** Sixteen locales were generating their
  people in one alphabet and their cities in another — a Japanese row read 神戸あんじゅ
  living in `Abashiri`. Cities and their subdivisions now come from Wikidata as a pair, so
  焼津市 sits in 静岡県. **Replaces values in sixteen locales, so the corpus takes a major
  bump.** Armenian and Macedonian keep the romanised gazetteer deliberately: Wikidata has
  six populated Armenian cities in Armenian script, and six is worse than several hundred
  in the wrong alphabet.

- **`en_IN` stopped putting English names on Indian addresses.** It carried no names of its
  own, so an Indian city and postcode arrived with "Jennifer Williams". It now draws 989
  romanised Indian names from the same Wikidata items that give `hi_IN` its Devanagari ones.

- **Postcodes for Armenia and Nigeria**, which the register always had. The mask reader
  treated a pattern that is entirely one optional group — Nigeria's `(\d{6})?` — as a
  trailing extension and stripped it to nothing, dropping four countries.

- **Company forms for Norway.** GLEIF files them under `no`, the macrolanguage; the roster
  says `nb`. Seventeen abbreviations sat unused behind two letters.

- **Nepali colours**, and `lv` explained rather than silently absent — see below.

- **Per-locale corpus versions.** Adding Hindi no longer renumbers English. Each locale
  carries its own version and content fingerprint; `faker.locale.version` reads it, and the
  release number becomes a manifest of them.

- **Coverage is answerable from the library**, not only from a table:
  `locale.supplies(.streets)`, `locale.nativeFields`, `locale.tier`.

### Removed since the withdrawn tag

- **`lastName(gender:)`.** It had been a no-op for the library's entire life:
  `person.last_name` is `.generic` in all sixty-six locales, so a caller passing `.female`
  got the same pool as one passing `.male`, in every language. Removing it changes no
  output. Languages that inflect surnames — Nováková, Иванова — want a rule per language
  for deriving the feminine form, which is a grammar problem rather than a list to source;
  adding the argument back when there is data behind it costs no caller anything.

- **`location.county` in sixteen locales**, rather than replaced. What the gazetteer
  supplied for Russian was `Abakan Urban District` — not romanised Russian but an English
  description of the administrative type.

### Changed since the withdrawn tag

- **Every filter that drops data now records what it dropped**, into `filters.json` and,
  for the fetch stage, into the snapshot itself. Every serious bug this pipeline has had was
  a silent discard, and three of them shipped. Two were found by this within a day: a
  Norwegian company-forms gap, and `lv` being in the colour table and absent from the
  snapshot — which turns out to be correct (five of Latvian's seven colour labels are
  two-word noun phrases, and one is "colour film") and looked exactly like a bug.

- **Hand-written numbers in `docs/corpus-strategy.md` are asserted by tests.** That table
  was wrong in twelve places and omitted eleven adapters.

- **Language QIDs are checked against the ISO code they are filed under** before any fetch
  runs. One was wrong — `Q33298` is Filipino, sitting where Kannada should have been — and
  it did not fail loudly: it returned several hundred perfectly valid Filipino names for an
  Indian locale.

### Fixed
- **No locale wears an English honorific it never chose.** `pa_IN` was producing
  `Dr. ਆਰਿਫ ਜਫਰ` and `ਸਾਹਿਲ ਸ਼੍ਰੀਕਾਂਤ Sr.` — a Latin title bolted to a Gurmukhi name.

  `person.prefix` was the smaller half: four locales inherited English titles because
  they were in neither the list that carries honorifics nor the list that declares none.
  `person.suffix` was the larger by far — **fifty-four locales** inherited `Jr.`, `Sr.` and
  `III`, because only English ever declared its own. Around three per cent of every
  non-English name carried one, which is rare enough to survive every sample anybody took.

  Both are now declared absent wherever a locale has none, which is the mechanism that
  already existed and simply had not been applied. `de` keeps `Dr.` and `Prof.`, which are
  German; `en` keeps its own.

  **Removes values, so the corpus takes a major bump.** Sixty-six locales also lose a name
  *shape*: CLDR gives several locales a pattern ending in `{{person.suffix}}`, and the
  compiler prunes a shape whose token can no longer produce anything. Fewer patterns is the
  point rather than a regression — and the coverage gate reported all sixty-two as
  regressions, correctly, before the baseline was refreshed.


- **Nine locales stopped answering in English.** `cy`, `bn_BD`, `hr`, `fa`, `id_ID`,
  `ka_GE`, `yo_NG`, `zh_TW` and `ko` now draw their own full names — Peredur Sinnott,
  শামীম সেন, Ratko Šeks, مهران کمالی, ნიკოლოზ ჭიაურელი, 游霖任. Not one new source or
  licence was involved. Three mechanisms had been discarding data the build was already
  fetching:

  - a minimum list length of 40, which threw away thirteen Welsh surnames, thirty-one
    Macedonian and twenty-one Bengali. It is ten now, the same reasoning that already put
    the colour floor at twelve. What forty actually chose, in those locales, was
    `Riley Bonneau` over `Bevan`;
  - a retry policy that read throttling as a dead endpoint. Three queries for one language
    went out 1.2 seconds apart and the third came back truncated, which surfaces as
    malformed JSON rather than as rate limiting; four retries inside a minute all landed in
    the same window. Spanish surnames had **never once** been fetched successfully, so the
    pipeline had recorded "Wikidata has no Spanish surnames" and carried on;
  - and, in the release before this one, a minimum length of two UTF-16 units that deleted
    almost every CJK surname there is.

  **Changes generated output for all nine.** `es` is unaffected: its 3,815 newly-arrived
  Wikidata surnames collided with INE's 27,661 weighted ones, the build refused the
  conflict rather than picking a winner, and Wikidata now yields that path to the census.

- **Nepal ships, as `ne_NP`** — Prakash Tharu, Siddhartha Pokharel, Sunita Chhetri.
  Twenty given names and twenty-four surnames from *Popular Names by Country* (CC0), the
  one candidate of five that is aggregate popularity rather than a roster of people. The
  others were built from a leaked Facebook dump, from "public records", from unnamed
  datasets, and scraped from Wiktionary.

  Romanised, deliberately. The file's Nepali surnames carry Devanagari and its given names
  do not, and Devanagari surnames beside Latin given names is a chimera inside one name.
  All-Latin is coherent, and romanised Nepali names are what passports and English-language
  records hold. Wikidata's twelve Devanagari Nepali surnames yield to it for that reason
  rather than for size.

  Ten given names a gender is thin, and it is the whole of what anybody publishes. Nepal
  has no equivalent of INSEE or the US Census surname file, and neither does India,
  Pakistan, Sri Lanka or Bangladesh — India's Census runs to some two hundred tables under
  GODL and not one counts names. That absence is in the world's open data, not in the
  search.

  **Sri Lanka was looked at and refused.** Fifty surnames, no given names; Wikidata's only
  Sinhala given names are six, in Sinhala script, and pairing those with Latin surnames is
  the mixture this corpus exists to refuse. `si_LK` would answer entirely in English, which
  is why Telugu, Marathi and Odia have no locale either.

- **Hindi ships, as `hi_IN`.** 211 given names and nine surnames in Devanagari, from
  Wikidata. The data was already being fetched; Hindi had been cut in the twelve-locale
  removal for supplying no names of its own, which was true when the floor was forty and
  stopped being true at five.

  Nine South Asian languages joined the query table at the same time — Punjabi, Gujarati,
  Marathi, Telugu, Kannada, Malayalam, Sinhala, Odia and Assamese — because none had ever
  been asked about. Wikidata's answer is thin: Telugu, Marathi and Odia have surnames and
  no given names, so a locale for them would answer entirely in English, which is what the
  original cut removed. Gujarati has three surnames and nothing else. Being in the table
  means the next refresh picks up whatever has been catalogued since.

  `pa_IN` was built and then dropped. Five Punjabi given names produced `ਹਮਜ਼ਾ` three times
  in eight draws, and the smoke test that watches for a generator collapsing to a handful
  of values caught it independently: *5 distinct values over 200 seeds from a pool of
  18,392*.

- **Wikidata labels are not always in the language they claim.** A `hi` label held Bengali
  and a `pa` label Urdu — one or two per list, contributed by hand and never checked
  against the characters. They compose, so `hi_IN` produced `स्वप्निल চৌধুরী`: a Devanagari
  given name beside a Bengali surname, a chimera inside a single name rather than across a
  fallback. Fifteen languages with one settled script now filter to it.

- **`fullName(gender:)` honours its argument.** It never had, in any locale.
  `fullName(.female)` and `fullName(.male)` returned character-for-character the same
  name, because a name's shape is data — `{{person.firstName}} {{person.lastName}}` — and
  the tokens in it take no arguments, so the gender only reached a fallback branch that
  runs when a locale has no pattern, which is almost never. It was a public parameter that
  did nothing.

  Nothing caught it because every test exercising `fullName` called it without a gender,
  and every test exercising gender called `firstName`. Honorifics come along for the ride:
  German now gives `Frau Luise Barmettler` beside `Herr Marc Barmettler` rather than the
  same name twice.

  **Changes generated output only for calls that pass a gender** — which were returning the
  wrong answer. `fullName()` with no argument is byte-identical, and the corpus does not
  move.

- **No locale answers in English any more.** `mk` was the last, on a margin of three
  names: thirty-one Macedonian surnames, forty-seven male given names, seven female. Two
  changes reached it. The floor came down from ten to five, which admitted the seven. And
  `fullName()` will now compose from a single gender where that is all a locale has, rather
  than requiring both and falling through — which fixed `mk` on its own, before the seven
  arrived.

  That relaxation is only safe because of a second fix underneath it. With no gender asked
  for and no ungendered pool, the library chose female or male on a coin toss and drew; a
  locale holding only male given names lost half its draws to English, so `mk.firstName()`
  had been returning `Gabriella` beside Macedonian surnames. It now chooses among the
  genders the locale actually supplies. Locales carrying both are untouched — the coin is
  still fair, and no existing stream moves.

  `NameCoherenceTests` asserts this rather than trusting it: fifty locales supply their own
  full name, none fall back. Its two categories used to be hand-written lists naming `ko`,
  `es`, `bn_BD`, `cy` and `mk` as locales that *should* answer in English. Every one has
  since been filled, so the test was pinning a corpus that no longer existed. Derived now.

  **Changes generated output for `mk` and `vi`.** Vietnamese given names moved to the name
  database, which carries 3,141 against Wikidata's 57 — they only collided once the floor
  came down far enough to admit 57 at all.

- **Korean names work.** `ko` had no surnames of its own, so `fullName()` returned
  `Albert Seaman`. The cause was not a missing source: `Endpoint.usable` required a label
  to be at least two UTF-16 code units, which is right for Latin script and wrong for Han
  and Hangul, where one character *is* a whole surname. Wikidata returns 143 Korean
  surnames and five survived the filter — 김, 이, 박 among those discarded. The floor is now
  script-aware, and `ko` draws 천혁진 rather than an English name.
  **Changes generated output for `ko` and `ja`.**

  Nothing could have caught this from the corpus: a filter that drops values leaves no
  record of what it dropped, and the survivors read as a small language rather than a
  broken rule. `zh_CN` and `zh_TW` are unaffected — both already draw surnames from
  dedicated sources that outrank Wikidata.

### Removed

- **The Korean surname integration**, which shipped as a source, an adapter and a
  `decoy-fetch` subcommand that between them produced nothing. KOSIS answers only to a
  registered API key, so the adapter contributed an empty table on every build while the
  source still counted toward the totals the documentation quotes. Half a feature is worse
  than a documented gap: the gap is now only in [the locale matrix](docs/locale-support.md),
  where it can be read. `ko` keeps its own given names and falls through to English for
  surnames. The code is in the history if a key turns up.

### Added

- **`es` has Spanish surnames** — 27,661 from INE, weighted by how many people carry them,
  so a Spanish name is `Maria Carmen Sandalinas` rather than a fully English fallback.
  `es_MX` inherits them. **Changes generated output for `es` and `es_MX`.**

### Changed

- **NOTICE names only sources whose data ships.** A descriptor can now exist for a source
  the corpus does not yet contain — `kosis-surnames` waits on a snapshot only an API key
  can fetch — and crediting it would assert a provenance that is not there.
- **Full names no longer mix two languages.** `ko` generated `Rivard혁진`, a US Census
  surname on a Korean given name; `es`, `bn_BD`, `cy` and `mk` did the same. A composed
  name now comes entirely from one language, so those five fall back to English rather
  than producing something subtly wrong. `en_GB` is unaffected and keeps its own given
  names, because borrowing English surnames is not a chimera when the locale is English.
  The individual generators are unchanged — `ko.firstName()` is still Hangul.
  **Changes generated output for five locales. Corpus unchanged.**
- **`Faker` requires a locale.** It used to default to a stub defining eleven paths against
  the hundred and eighty-four the generators draw from, so `Faker()` compiled and then
  trapped. Pass `.builtIn` explicitly for the generators that need no corpus — checksums,
  UUIDs, `int(in:)`.

### Added

- **`DecoyLocales`**, a product carrying all sixty-four locales as resources. Three ship as
  compiled-in modules; the rest were unreachable without forking the package.

  ```swift
  import DecoyLocales
  let fr = try DecoyLocales.locale("fr")
  ```

  Prefer a module where one exists: it costs nothing at run time and cannot fail.

- The compiled corpus is committed under `Corpus/binary/`. Rebuilding needs fifty-one
  upstreams to answer and two already do not, so the data no longer depends on every one of
  them still being there.

## Corpus 60.1.0

- Provenance only. `iana-tld` recorded a serial that IANA bumps whenever the root zone is
  regenerated, so the corpus changed daily for data that had not moved. No drawn value
  differs from 60.0.0.

## Corpus 60.0.0

- **`zh_CN` has Chinese names.** 131 given names carrying real population weights, and 742
  surnames replacing 41 Wikidata entries that were mostly rare compounds and romanisations.
  **Major, because the surnames are replaced rather than added.**
- Chinese surnames ship unweighted. 王, 李 and 张 cover about a fifth of China and here they
  are as likely as any other; no frequency table exists under a licence that composes.

## Corpus 59.3.0

- **`vi` has Vietnamese given names** — 1,571 female and 1,570 male, from an MIT
  compilation. `vi` previously drew Vietnamese surnames with English given names. Ships
  unweighted: a compilation records which names exist, not how many people hold them.

## Earlier

The corpus pipeline was rewritten from JavaScript to Swift and verified byte-identical
across all sixty-four locale binaries. That work changed no data and is not itemised here.
