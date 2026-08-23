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

## 1.0.0

The first release. The package version starts here and follows semantic versioning; the
corpus is already at 60.4.0 and keeps its own numbering, so the two are not going to line
up and are not meant to.

Undated until tagged — the tag is the release, and this heading is written before it so
the notes can be reviewed first.

### Fixed

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
