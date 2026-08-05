# Corpus strategy

How Decoy's data is sourced, built, and improved — and how it stops depending on
`@faker-js/faker`.

> **Status:** partly implemented, and this document says which parts. The adapter
> pipeline, provenance, and coverage reporting exist. The generative layer and
> frequency weighting do not. Written down so the reasoning survives outside the
> conversations that produced it — and kept current, because a design record that has
> quietly stopped being true is worse than none.
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
binary. Nothing else writes data. `Tools/adapters` has **no npm dependencies**,
deliberately: the mechanism for removing a dependency on someone else's package should
not accumulate its own.

**Built so far** — five adapters, four sources, ~104k strings:

| Adapter | Source | Licence | Fills |
|---|---|---|---|
| `iso-3166` | CLDR 48.2.0 | Unicode-3.0 | `location.country_code` (composite), `location.country` in 73 locales |
| `iso-639` | CLDR 48.2.0 | Unicode-3.0 | `location.language` (composite) in 73 locales |
| `iso-4217` | CLDR + SIX Group | Unicode-3.0 / facts | `finance.currency` (composite) in 72 locales |
| `iana-tzdb` | tzdata 2026b | public domain | `location.time_zone`, `date.time_zone` |
| `mime-types` | mime-db 1.54.0 | MIT | `system.mime_type` — 1,015 types with extensions |

**faker-js is one producer among two, not yet an adapter.** `Tools/extractor` still
writes the same intermediate shape, and the compiler reads either — manifest fields for
the extractor are optional, with a synthesised faker-js source record as fallback. That
is what lets faker be replaced one field at a time rather than in a single commit. It
has not been converted into an adapter proper because there is no point: it is being
deleted, not maintained.

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

Measured against the faker-derived corpus, this gave the first real size of the problem:

| | |
|---|---|
| Median native coverage | 26% |
| Locales under 30% native | 48 of 77 |
| `ta_IN` | 7% (15 paths against `en`'s 190) |
| `yo_NG` | 8% (17 paths) |

**Roughly three quarters of what a non-English locale produces is English falling
through the chain.** This is the "Tamil records named Jennifer Williams" failure, and it
is much larger than the locale count suggests.

Caveat on the denominator: 36 of `en`'s 190 paths are synthetic `__keys` tables the
compiler emits so object keys are drawable, so the real denominator is ~154 and the
percentages are slightly pessimistic. The ranking is unaffected.

Still **planned**: CI that fails when a locale drops below a declared threshold, and a
runtime warning when a locale falls back to English for most fields. The measurement
exists; the gate does not.

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

## Statistical fidelity is the quality bar — **Planned**

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

The extractor is re-runnable and verifies faker's fallback chains against faker's own
resolution, so a scheduled job could diff a fresh extract and open a PR — inheriting
upstream contributions free, for as long as faker remains a producer. Adapter sources
are pinned by integrity hash, so their equivalent is deliberate: bump the version in the
descriptor, re-pin, and read the diff.

---

## What this requires of the binary format

These are format requirements rather than later additions. The format need not
*implement* the generative layer now, but if it cannot represent a model chunk, adding
one later means re-cutting every blob and breaking every pinned corpus version.

All six are representable in format v2. Four are in use.

| Requirement | Consequence | State |
|---|---|---|
| Weights | A weight column alongside string tables | Representable; used by faker-derived patterns, not yet by frequency data |
| Composite records | Heterogeneous field tuples, not parallel lists | **In use** — countries, languages, currencies |
| Provenance | A source/license table, referenced by ID | **In use** — four sources, attributed by nearest claimed ancestor |
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

**Emit fewer values when the extra ones are wrong.** Time zones went from 419 to 312 by
reading `zone1970.tab` and ignoring `backward`: the surplus were deprecated aliases like
`US/Eastern`, fine to parse but wrong to generate. Currencies are restricted to current
legal tender, or fixtures would contain Deutsche Marks. MIME types without a file
extension are dropped, since a drawn type with no extension falls through to `"bin"`.
Counts are not the quality bar.

---

## Sequencing

1. ~~Binary format with all six requirements representable~~ — **done** (format v2)
2. ~~Core generators against the faker-derived corpus~~ — **done** (208 methods, 22 namespaces)
3. ~~Corpus discoverability and coverage measurement~~ — **done** (`Corpus.paths`, `decoy-inspect`)
4. Authoritative reference adapters replacing factual fields — **substantially done**;
   ISO 3166/639/4217, IANA tzdb and media types are migrated. GeoNames and NHTSA are not.
5. Frequency data (Census, SSA) populating the weight column — **not started**
6. Generative models for names, with the safety filters above — **not started**
7. Coverage gate in CI, and `decoy-validate` for contributions — **not started**
8. Coverage gates reach threshold → delete `Tools/extractor`

Steps 4–6 are independent and can proceed in any order. Step 8 is a consequence, not a
task.

**The honest remaining cost.** Everything migrated so far is from the factual bucket,
where a published registry settles the answer. What is left — names, streets, cities,
companies — is the expensive bucket, and it is most of the corpus by volume. Five
adapters replaced roughly 2,000 of `base`'s paths and four of `en`'s 190. A faker-free
v1 means re-sourcing the rest, which is why steps 5 and 6 matter more than another
registry adapter would.

---

## Attribution

Every corpus carries its own source records, so the authoritative answer is
`decoy-inspect <locale>.decoy` rather than this list. As shipped today:

| Source | Licence | Obligation |
|---|---|---|
| [@faker-js/faker](https://github.com/faker-js/faker) | MIT | Retain notice. Ends when `Tools/extractor` is deleted. |
| [Unicode CLDR](https://github.com/unicode-org/cldr-json) | Unicode-3.0 | Retain notice. |
| [mime-db](https://github.com/jshttp/mime-db) | MIT | Retain notice. |
| [IANA tzdb](https://www.iana.org/time-zones) | public domain | None. |
| ISO 4217 registry (SIX Group) | facts | None asserted; see Decisions. |

The faker-js obligation is the only temporary one, and it ends only when `Tools/extractor`
is deleted *and* no derived data remains — the second condition being the one that is
easy to forget. The upstream copyright notice is retained alongside the extracted data
until then.
