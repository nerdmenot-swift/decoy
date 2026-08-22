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
corpus is already at 60.2.0 and keeps its own numbering, so the two are not going to line
up and are not meant to.

Undated until tagged — the tag is the release, and this heading is written before it so
the notes can be reviewed first.

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
