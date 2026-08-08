# Corpus strategy

How Decoy's data is sourced, built, and improved — and how it stops depending on
`@faker-js/faker`.

> **Status:** partly implemented, and this document says which parts. The adapter
> pipeline, provenance, coverage reporting and the coverage gate exist, and frequency
> weighting is done for English surnames. The generative layer does not exist. Written
> down so the reasoning survives outside the conversations that produced it — and kept
> current, because a design record that has quietly stopped being true is worse than
> none.
>
> Sections are marked **Built**, **Partly built**, or **Planned**.

---

## The problem with inherited corpora

Decoy bootstraps from faker-js. That was the right call — it has the deepest
non-English data of the major fakers and models names as `{ generic, female, male }`
rather than flat lists. But it is a bootstrap, not a foundation, for two reasons.

**The major fakers are one family tree, not independent sources.** Faker was written
in Perl in 2004 (`Data::Faker`, Jason Kohles). Ruby's faker is a port of it. faker.js
was created by Matthew Bergman and Marak Squires, heavily inspired by the Ruby gem and
Perl's original, and `@faker-js/faker` is the community fork of that after January
2022. Ruby faker and faker-js are therefore cousins sharing a common ancestor.

The practical consequence: mining another faker for strings adds far less than the raw
counts suggest, because much of the core overlaps by descent. Ruby's larger English
number is additionally inflated by fandom content that carries trademark exposure we
do not want to ship.

**The provenance is undocumented.** Neither faker-js's localization guide nor Ruby's
locale files say where any of the data came from, who verified it, or against what
standard. It is two decades of contributor goodwill. That is not a criticism of the
people involved — it is an accurate description of a model that cannot be audited,
cannot be licensed with confidence, and cannot be improved systematically.

### What was measured

Against `@faker-js/faker` 10.5.0, extracted 2026-07-27:

| | |
|---|---|
| Locales | 76 |
| String occurrences (unmerged) | 187,112 |
| Distinct strings | 147,470 (21.2% redundant across locales) |
| Unique string bytes | 1.56 MB |
| Weighted arrays | 136, with real non-uniform weights (95, 99, 50, 49, 25, …) |
| Composite record arrays | 36, in 7 distinct shapes |

Two findings drive the format design. Weights and composite records are **already in
the data** — `country_code` is `(alpha2, alpha3, numeric)`, and splitting that into
three parallel lists would generate countries that do not exist. And the 21.2%
cross-locale duplication (`de_AT` duplicates all 1,145 of `de`'s first names) makes a
shared, deduplicated string arena worth real space.

---

## The model: a derived corpus

Every faker's data model is *humans type lists into files*. Decoy's is different:

> **The corpus is a build artifact.** No one hand-edits data. Every string is derived
> from a citable primary source by a reproducible pipeline, and carries its origin
> with it.

This is the whole strategy. Everything below follows from it.

### Adapters, not data files — **Built**

`Tools/adapters/` holds *programs*, not strings:

```
sources/<id>.json      pinned descriptor: URL, integrity hash, licence, version
adapters/<id>.mjs      the transform
lib/sources.mjs        fetch, verify, cache, extract
locales.json           the locale roster Decoy targets
run.mjs                orchestrator → out/locales/*.json + manifest.json
```

Each adapter declares one or more sources; each source pins every artifact to an SRI
integrity hash. A cached artifact is **re-verified rather than trusted**, because a
tampered cache would otherwise produce a corpus that passes every check on the machine
that built it and nowhere else. A hash mismatch aborts with the expected and actual
digests and instructions to verify and re-pin.

`node run.mjs` produces the intermediate JSON; `decoy-compile-corpus` produces the
binary. Nothing else writes data. There is **no package manifest and no dependency
install** anywhere in the toolchain — every source, faker-js included, is a pinned
tarball fetched into the gitignored cache. The mechanism for removing a dependency on
someone else's package should not itself require a package manager.

**Built so far** — seventeen adapters plus the faker-js bootstrap, twenty-eight sources:

| Adapter | Source | Licence | Fills |
|---|---|---|---|
| `iso-3166` | CLDR 48.2.0 | Unicode-3.0 | `location.country_code` (composite), `location.country` in 73 locales |
| `iso-639` | CLDR 48.2.0 | Unicode-3.0 | `location.language` (composite) in 73 locales |
| `iso-4217` | CLDR + SIX Group | Unicode-3.0 / facts | `finance.currency` (composite) in 72 locales |
| `iana-tzdb` | tzdata 2026b | public domain | `location.time_zone`, `date.time_zone` |
| `mime-types` | mime-db 1.54.0 | MIT | `system.mime_type` — 1,015 types with extensions |
| `programming-languages` | Linguist 9.4.0 | MIT | `system.programming_language` — 533 languages |
| `iana-tld` | IANA root zone 2026080700 | facts | `internet.domain_suffix` — 1,438 TLDs |
| `periodic-table` | PubChem (NIH) | public domain | `science.chemical_element` (composite) |
| `si-units` | CLDR 48.2.0 | Unicode-3.0 | `science.unit` (composite) in 74 locales |
| `iso-3166-2` | CLDR 48.2.0 | Unicode-3.0 | `location.state` (composite) — 3,341 subdivisions across 73 locales, each getting its own country's (upstream carries 5,395 across 200) |
| `cldr-dates` | CLDR 48.2.0 | Unicode-3.0 | `date.month.*`, `date.weekday.*` in 74 locales |
| `cities` | cities.json 1.1.61 (GeoNames) | CC BY 4.0 | `location.city_name`, `location.place` (composite) in 74 locales |
| `us-surnames` | US Census 2010 | public domain | `person.last_name.generic` in `en` — 24,889 names, **weighted** |
| `wordnet` | Open Multilingual Wordnet 2.0 | per language (see below) | `word.noun/verb/adjective/adverb` in 15 locales |
| `persian-words` | Lilak 3.3 | Apache-2.0 | `lorem.word` in `fa` |
| `emoji` | Unicode Emoji 16.0 | Unicode-3.0 | `internet.emoji.*` — 3,780 sequences across 10 categories |
| `airports` | airport-data 1.0.1 (OpenFlights) | Unlicense | `airline.airport` (composite) — 5,614 IATA-coded airports |
| `faker-js` | @faker-js/faker 10.5.0 | MIT | everything not yet covered, at lowest precedence |

**faker-js is an adapter like any other, and the lowest-precedence one.** It is fetched
as a pinned npm tarball into the gitignored cache and read by importing its ESM entry
point directly — faker-js has zero runtime dependencies, so there is nothing to resolve.
Nothing about faker-js is committed here, and no package manager is involved: the whole
toolchain is plain `.mjs` files run by `node run.mjs`, with no package manifest at all.

Because it declares `fallback`, every other adapter overrides it wherever they overlap.
A field stops being faker-derived the moment something else covers it, with no
coordinating change anywhere. The migration ends as `rm adapters/faker-js.mjs
sources/faker-js.json`, and the adapter already handles its own absence.

It also carries the one check that cannot outlive it: Decoy derives fallback chains from
the locale roster rather than storing them, and the faker adapter asserts those derived
chains against faker's own resolution for all 76 locales. When faker goes, the chain rule
is asserted by nothing but its own tests. That is a real, and easily forgotten, cost.

### Provenance is per path — **Built**

The compiler registers every source the manifest declares and attributes each table to
the source that supplied it, resolving by **nearest claimed ancestor**. That rule is not
cosmetic: an adapter claims `system.mime_type` and the compiler then emits thousands of
paths beneath it, none matching exactly. Exact matching credited all of them to
whichever source happened to be registered first, silently mislabelling 2,036 paths in
`base` — the kind of error nobody notices until a licence audit.

**Known limitation.** The binary format stores one source ID per table, so a table merged
from several sources is credited to the one its adapter names as primary. `iso-4217`
takes names and symbols from CLDR and numeric codes from the ISO 4217 registry, and is
attributed to CLDR. Every source is still registered in the corpus and listed in the
manifest, so nothing is lost — the attribution is coarser than per-field. Making it
exact is a format change and has not been judged worth one.

### Coverage gates decide when deletion is safe — **Partly built**

`decoy-inspect --coverage <dir>` reports **native** coverage per locale: what a locale
defines itself, not what it resolves through the chain. The distinction is the whole
point — a locale that resolves `person.first_name` only because English sits behind it
would report as fully covered otherwise.

Measured against the current corpus, over the 74 locales that are neither `en` nor the
language-neutral `base`:

| | |
|---|---|
| Median native coverage | 35% |
| Locales under 30% native | 26 of 74 |
| `ta_IN` | 11% (11 paths against `en`'s 99) |
| `yo_NG` | 16% (16 paths) |

**Around a third of what the median non-English locale produces is its own**, and the
rest is English falling through the chain. That is the "Tamil records named Jennifer
Williams" failure, and at the bottom of the table it is still most of the output.

These numbers have moved twice, and both reasons are worth recording because both look
like progress or regress and are neither.

The first measurement put the median at 26% with 48 locales under 30%. Most of that gap
was a shadowing bug — a source claiming a path in `en` suppressed every other locale's
data beneath it, so locales were credited with nothing for fields they defined perfectly
well. Fixing it took the median to 40%.

It then fell to 35% when the compiler stopped emitting a `__keys` table under every
object node. Those were synthetic paths, and a locale carrying faker's objects was
credited with one per node — coverage it had not earned, on data nothing could draw. The
denominator fell too, from 126 to 99. **No locale lost a single drawable value**; the
measurement stopped counting things that were not data. These figures are lower and more
honest, which is the direction a coverage number should move when it is corrected.

**Built**: `decoy-inspect --coverage --gate Corpus/coverage-baseline.json` fails when a
locale carries less of its own data than the committed baseline, and CI runs it on every
build. It is a regression gate rather than a quality bar — it catches an adapter silently
dropping coverage, which is what the failure actually looks like, rather than asserting a
threshold nobody has justified.

Still **planned**: a runtime warning when a locale falls back to English for most fields.

---

## The generative layer — **Planned**

Strings are the wrong primitive for most categories. This is where Decoy stops needing
anyone else's corpus at all.

| Category | Better primitive |
|---|---|
| Phone numbers | Numbering plan (ITU E.164 allocations) + format |
| Postcodes | Per-country format specification |
| Street addresses | Pattern over component lists |
| Person / street / company names | Per-language phonotactic n-gram model |

The last row is the real lever. A character-level n-gram model trained on a real name
list generates *plausible new* names indefinitely, in the correct language and
orthography. It gives:

- **Infinite non-repeating values**, which dissolves `unique` rule exhaustion entirely
- A **smaller** binary footprint than the list it was trained on
- **Licensing independence** — a model is not its training data, and outputs are novel
- Coverage for any language with one obtainable seed list

**The honest risk:** an n-gram model will occasionally emit a real person's name by
coincidence, or an offensive string. This needs a blocklist filter and a known-real-name
exclusion pass, and it must be a stated guarantee rather than an afterthought. Fake data
that turns out to be real PII is a serious failure for a library like this.

The split, therefore:

- **Curated lists for what must be true** — ISO 3166/4217/639, IANA timezones and MIME
  types, currencies. These are facts; generating them is wrong. *All of these are now
  built; see the adapter table above.*
- **Generative models for what need only be plausible** — people, streets, companies.
  *None of these are built. This is the whole remaining cost of a faker-free v1.*

---

## Statistical fidelity is the quality bar — **Partly built**

Replace "how many strings do we have" with "does our output match the real
distribution".

Every faker draws names uniformly. Real populations are Zipf-distributed — a handful of
surnames cover a large share of the population, and most are vanishingly rare. Uniform
sampling produces data that is wrong in ways that matter specifically for backend work:
deduplication and fuzzy-matching logic look flawless because real collision rates never
occur, index behaviour under load does not resemble production, and analytics built on
it have suspiciously flat histograms.

Public-domain frequency data exists (US Census surname files, SSA given names). Feeding
real frequencies into the weight column the format already needs turns a uniform draw
into a realistic one with **no API change** — `Faker.weighted(_:)` already exists.

**Done for English surnames.** `person.last_name.generic` in `en` is 24,889 Census names
carrying their real counts, against faker's 473 drawn uniformly. Measured over 100,000
draws: Smith 1.11%, Johnson 0.83%, Williams 0.68%, and 17,178 distinct surnames in the
tail. That is the first field in the corpus whose output distribution matches reality.

**Not done for given names**, and blocked rather than unscheduled: ssa.gov returns 403 to
every non-interactive request regardless of user agent, so the SSA baby-name data — which
would supply first names with frequencies *and* by birth year, giving
`firstName(bornIn: 1950)` — cannot be fetched by an adapter. It needs a fetchable mirror
that is versioned enough to pin; a manual download would not do, because then the corpus
could only be rebuilt on one machine.

SSA data is also per birth year, which yields something no other library has:
`firstName(bornIn: 1950)` returns an era-appropriate name rather than a contemporary one.

Testable quality gates, run in CI against the built corpus:

- Chi-square / KS tests against reference frequency distributions
- Postcode outputs match national format regexes
- IBANs checksum; card numbers pass Luhn
- Generated strings in a locale use that locale's script

### Coherent records

`city: "Boston", state: "CA", postcode: "10001"` passes most validators and is
nonsense. Fields are drawn independently, so correlated ones disagree.

Once composite records exist in the format, a whole row is drawn from a source like
GeoNames — city, state, postcode, timezone, coordinates together. For a library aimed
at database seeding this is arguably a bigger differentiator than referential
integrity, and it reuses the same mechanism.

---

## Corpus version is part of the reproducibility contract

Easy to miss, expensive to retrofit, and nobody else does it.

`generate(seed: 1337)` is meaningless without knowing *which corpus*. Any change to the
data changes everyone's fixtures. Therefore:

- The corpus version is **pinnable and versioned separately** from the library
- Adding fields is a minor bump
- **Changing an existing value is a major bump**, because it breaks reproducibility for
  every existing user
- Multiple corpus versions must be able to coexist

A library whose entire promise is determinism cannot treat its data as an
implementation detail.

---

## Adding to the corpus

Three different questions hide inside "how do I add data", and they have different
answers.

**1. Data for your own project — Built.** Build a corpus at runtime and put it in front
of the chain. No fork, no PR, no rebuild:

```swift
var b = CorpusBuilder(version: CorpusVersion(major: 1, minor: 0, patch: 0))
let src = b.addSource(id: "my-skus", license: "proprietary", url: "",
                      version: "1", retrieved: "2026-08-06")
b.index("commerce.sku", stringTable: b.addStringTable(["A-100", "B-200"], source: src))
let locale = DecoyLocaleEN.locale.overlaid(by: try Corpus(bytes: b.build()))
```

`overlaid(by:)` pushes it to the front, so it wins for the paths it defines and falls
through for everything else. `CorpusBuilder` lives in the Foundation-free module rather
than in the compiler precisely so this needs no Node and no fork.

**2. A locale Decoy does not ship — Built.** Add the code to `Tools/adapters/locales.json`,
run the adapters, then add a `Package.swift` entry. Chains are derived from the roster,
not stored, so they cannot drift.

**3. Contributing data back — Planned, and nothing exists yet.** There is no contribution
format, no validation, and no documented path. While faker is still a producer this is
survivable, because the corpus is regenerated wholesale. It stops being survivable the
moment faker is deleted, because contribution then becomes the *only* way the corpus
grows — with 48 locales under 30% native coverage.

The intended shape, unchanged from the original design:

- **Contributions must cite a source.** A contribution is an adapter plus a source
  descriptor, never a raw list pasted into a file. This is the single rule that prevents
  Decoy's corpus from decaying into the thing it replaced.
- **Automated plausibility checks** — script matches the locale, no ASCII-only entries in
  a Cyrillic locale, no duplicates against existing data, descriptor complete, checksum
  verifies. A `decoy-validate` running in CI on every PR.

`decoy-inspect` already provides the front half of that workflow: `--coverage` to find
the holes, `--paths` to learn the naming convention, `--path` to see what shape existing
data takes.

### Discoverability — **Built**

`Corpus.paths` enumerates every path a corpus defines, and `LocaleCorpus.nativePaths`
distinguishes what a locale defines from what it inherits. Before this, `lookup(_:)`
could retrieve a path only if the caller already knew it existed — the set of valid
paths lived nowhere but in the generators' source, and coverage was unanswerable.

It cost no format change: the index already interns each path string to confirm hash
matches during lookup, so enumeration is a sequential walk of data that was there for
other reasons.

### Keeping upstream current

Every source is pinned by integrity hash, so refreshing one is deliberate rather than
automatic: bump the version in the descriptor, re-pin, and read the diff. That is the
intended workflow, not a limitation — an upstream that changed under a pinned hash is
exactly the event worth a human look.

The faker-js adapter additionally verifies Decoy's derived fallback chains against
faker's own resolution on every run, across all 76 locales. **That check does not
outlive faker-js.** Chains are derived from the locale roster rather than stored, and
faker is the only source that can independently confirm the rule; once its adapter is
deleted the rule is asserted by nothing but its own tests. Easy to forget, and worth
replacing before that day rather than after.

---

## What this requires of the binary format

These are format requirements rather than later additions. The format need not
*implement* the generative layer now, but if it cannot represent a model chunk, adding
one later means re-cutting every blob and breaking every pinned corpus version.

All six are representable in format v2. Four are in use.

| Requirement | Consequence | State |
|---|---|---|
| Weights | A weight column alongside string tables | **In use** — faker-derived patterns, and real Census frequencies for English surnames |
| Composite records | Heterogeneous field tuples, not parallel lists | **In use** — countries, languages, currencies |
| Provenance | A source/license table, referenced by ID | **In use** — 28 sources, attributed by nearest claimed ancestor, and the origin of `NOTICE` |
| Generative models | A model chunk type, not only string tables | Chunk kind reserved; nothing emits one |
| Corpus version + compatibility | Header fields, checked on load | **In use** |
| Cross-locale dedup | A shared string arena (21.2% redundancy measured) | **In use** |

---

## Decisions on record

Kept here because each was reasoned through once and would otherwise be re-litigated.

**gofakeit is not a data source.** Its ~339 functions across 38 categories look like
breadth, but the addressable surface is ~237: roughly 40 functions are trademark-exposed
fandom (18 Minecraft, plus Celebrity/Movie/Book/Song/Beer), 57 are English grammar
taxonomy that does not localize (`NounCollectivePeople`, `AdverbFrequencyIndefinite`),
and 5 are reflection-based generation that Decoy rejects by design. Its localization is
thin, so it adds nothing where Decoy's coverage is actually weak. **It is useful as a
breadth spec** — read its function list to decide which namespaces to cover, then source
each from a citable primary. Vendoring its data would just create a second corpus to
delete.

**Prefer the registry over a package, even when the package is easier to pin.** ISO 4217
numeric codes were available from Debian `iso-codes` (LGPL-2.1) and from MIT npm mirrors.
Both are copies of the SIX Group registry, and a copy adds a licence to comply with
without adding authority. The registry publishes at an unversioned URL, which was the
argument for a package — handled instead by pinning the integrity hash *and* asserting
the document's self-declared `Pblshd` date, so a republication fails twice over.

*Corollary:* extracting data from a copyleft source and omitting the reference is not a
workaround. Obligations follow the distributed copy, not the build script, and it would
defeat the provenance chunk's entire purpose. Where the underlying values are pure facts
the right move is a source that grants permission openly, not a concealed one. Note the
EU database right is a separate and more protective regime than US copyright.

**One layer removed is acceptable when the primary cannot be verified.** `mime-db` was
taken over IANA's media types registry because IANA publishes at unversioned URLs that
change in place — an adapter reading it directly could not distinguish a legitimate
update from a compromised response. One intermediary, in exchange for a supply chain that
can actually be verified. Revisit if IANA ever publishes versioned snapshots.

**`airline` was cut and then restored.** It went out with the domain vocabularies on the
trademark argument — airline and aircraft names are real marks. But airports carry IATA
and ICAO codes, which are published identifiers rather than a curated word list, so the
"no registry, can never be re-sourced" test that killed `animal` and `food` did not apply.
It is back with airports sourced from the registry and the trademark-bearing halves left
to the bootstrap. The lesson is that the scope test has two independent clauses — *is it
schema material* and *is it re-sourceable* — and a namespace can fail one while passing
the other.

**Emit fewer values when the extra ones are wrong.** Time zones went from 419 to 312 by
reading `zone1970.tab` and ignoring `backward`: the surplus were deprecated aliases like
`US/Eastern`, fine to parse but wrong to generate. Currencies are restricted to current
legal tender, or fixtures would contain Deutsche Marks. MIME types without a file
extension are dropped, since a drawn type with no extension falls through to `"bin"`.
Counts are not the quality bar.

---

## Sequencing

1. ~~Binary format with all six requirements representable~~ — **done** (format v2)
2. ~~Core generators against the faker-derived corpus~~ — **done** (192 methods across 18
   namespaces; 174 across 17 without Foundation, which gates the `date` namespace)
3. ~~Corpus discoverability and coverage measurement~~ — **done** (`Corpus.paths`, `decoy-inspect`)
4. Authoritative reference adapters replacing factual fields — **done for everything
   with a pinnable registry**. Migrated: ISO 3166-1 and 3166-2, ISO 639, ISO 4217, IANA
   tzdb, the IANA root zone, media types, Linguist, the periodic table, CLDR units and
   CLDR date names.

   What remains has no pinnable source and needs a different mechanism rather than
   another adapter: NHTSA publishes vehicle makes only as a live unversioned API, and
   postcodes have ~200 national publishers rather than one.
5. Frequency data (Census, SSA) populating the weight column — **done for English
   surnames** (24,889 Census names with real counts), blocked for given names: ssa.gov
   returns 403 to every non-interactive request. See "Frequency" above.
6. Generative models for names, with the safety filters above — **not started**
7. ~~Coverage gate in CI~~ — **done** (`decoy-inspect --gate`, run against a committed
   baseline on every build). `decoy-validate` for contributions — **not started**
8. Coverage gates reach threshold → `rm adapters/faker-js.mjs sources/faker-js.json`

Steps 4–6 are independent and can proceed in any order. Step 8 is a consequence, not a
task.

**The honest remaining cost.** Everything migrated so far is from the factual bucket,
where a published registry settles the answer. What is left — names, streets, cities,
companies — is the expensive bucket, and it is most of the corpus by volume. Sixteen
adapters now cover `base` almost entirely and roughly a third of `en`. A faker-free
v1 means re-sourcing the rest, which is why steps 5 and 6 matter more than another
registry adapter would.

---

## Attribution

Every corpus carries its own source records, so the authoritative answer is
`decoy-inspect <locale>.decoy` rather than this list. As shipped today:

All twenty-eight, because a table that omits seven of them is the same failure as a
NOTICE that does:

| Source | Licence | Obligation |
|---|---|---|
| [@faker-js/faker](https://github.com/faker-js/faker) | MIT | Retain notice. Ends when the faker-js adapter is deleted. |
| [Unicode CLDR](https://github.com/unicode-org/cldr-json) | Unicode-3.0 | Retain notice. |
| [Unicode Emoji](https://www.unicode.org/Public/emoji/16.0/) | Unicode-3.0 | Retain notice. |
| [mime-db](https://github.com/jshttp/mime-db) | MIT | Retain notice. |
| [Linguist](https://github.com/github-linguist/linguist) | MIT | Retain notice. |
| [Lilak](https://github.com/b00f/lilak) | Apache-2.0 | Retain notice; state changes. |
| [airport-data](https://www.npmjs.com/package/airport-data) (OpenFlights) | Unlicense | None. |
| [IANA tzdb](https://www.iana.org/time-zones) | public domain | None. |
| [IANA root zone](https://data.iana.org/TLD/) | facts | None asserted; see Decisions. |
| [US Census 2010 surnames](https://www.census.gov/topics/population/genealogy/data/2010_surnames.html) | public domain (17 U.S.C. 105) | None. |
| [PubChem](https://pubchem.ncbi.nlm.nih.gov/) (NIH) | public domain (17 U.S.C. 105) | None. |
| [GeoNames](https://www.geonames.org/), via cities.json | CC BY 4.0 | **Attribution required wherever the corpus is distributed.** |
| [Open Multilingual Wordnet](https://omwn.org/) — 15 members | eight distinct licences, listed below | Attribution required. Each language pinned separately. |
| ISO 4217 registry (SIX Group) | facts | None asserted; see Decisions. |

The OMW members do not share a licence, and treating them as one family was wrong for
six of the fifteen. `omw-el` is Apache-2.0, `omw-id` is MIT, `omw-hr` and `omw-it` are
CC BY 3.0, `omw-sv` is CC BY with no version stated, `omw-en` and `omw-pl` are
Princeton's WordNet 3.0, and `omw-es` and `omw-fi` are dual `WordNet-3.0 AND CC-BY-3.0`.
The remaining six — `omw-cmn`, `omw-da`, `omw-he`, `omw-ja`, `omw-nb` and `omw-th` —
carry bespoke licences from NICT, the University of Haifa, the University of Copenhagen,
the Norwegian Language Bank and Francis Bond. Several are Princeton's licence *text*
re-issued by a different licensor, which is a different licence with the same wording.

Every one of these ships its full text at `LICENSES/<source-id>.txt`, copied verbatim
from the upstream artifact. Where a source carries no grant at all, that file records
why rather than leaving the absence to be read as an oversight.

The faker-js obligation is the only temporary one, and it ends only when the adapter is
deleted *and* no derived data remains — the second condition being the one that is easy
to forget.
