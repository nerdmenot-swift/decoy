# Corpus strategy

How Decoy's data is sourced, built, and improved — and how it stops depending on
`@faker-js/faker`.

> **Status:** design record, not yet implemented. The extractor exists; everything
> from "Adapters" onward is planned. Written down so the reasoning survives outside
> the conversation that produced it.

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

### Adapters, not data files

The repository holds *programs*, not strings. Each adapter:

1. Pins a source URL and version
2. Verifies a checksum, so a silently-changed upstream fails the build
3. Transforms to the canonical intermediate form
4. Emits provenance: source ID, license, retrieval date, transformation applied

`make corpus` produces the binary blob from adapters. Nothing else writes data.

**faker-js becomes one adapter among many** — the bootstrap one. It is not ripped out
at release; it is deleted once other adapters cover the same fields. A frightening
migration becomes `rm adapters/faker-js.js`.

### Coverage gates decide when that deletion is safe

A coverage matrix of locale × category × field, with CI that fails if dropping the
faker-js adapter would take any locale below a declared threshold. "Can we drop
faker-js yet?" stops being a judgement call and becomes a green check.

The same matrix tells contributors exactly where the holes are, and lets Decoy warn
users when a locale silently falls back to English for most fields.

---

## The generative layer

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
  types, currencies. These are facts; generating them is wrong.
- **Generative models for what need only be plausible** — people, streets, companies.

---

## Statistical fidelity is the quality bar

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

## Keeping it current

- **Automated upstream sync.** The extractor is re-runnable and verifies faker's
  fallback chains against faker's own resolution. A scheduled CI job can diff a fresh
  extract against the committed corpus and open a PR — inheriting upstream
  contributions for free, for as long as the faker-js adapter exists.
- **Contributions must cite a source.** A contribution is an adapter or a sourced
  dataset, never a raw list pasted into a file. This is the single rule that prevents
  Decoy's corpus from decaying into the thing it replaced.
- **Automated plausibility checks** on contributions: script matches the locale, no
  ASCII-only entries in a Cyrillic locale, no duplicates against existing data.
- **User-supplied corpora** through the same binary format, registered at runtime, so
  domain-specific data (medical codes, tickers, SKUs) needs no fork.

---

## What this requires of the binary format

These are format requirements rather than later additions. The format need not
*implement* the generative layer now, but if it cannot represent a model chunk, adding
one later means re-cutting every blob and breaking every pinned corpus version.

| Requirement | Consequence |
|---|---|
| Weights | A weight column alongside string tables |
| Composite records | Heterogeneous field tuples, not parallel lists |
| Provenance | A source/license table, referenced by ID |
| Generative models | A model chunk type, not only string tables |
| Corpus version + compatibility | Header fields, checked on load |
| Cross-locale dedup | A shared string arena (21.2% redundancy measured) |

---

## Sequencing

1. Binary format with all six requirements representable — **next**
2. Core generators against the faker-js-derived corpus
3. Authoritative reference adapters (ISO, IANA, GeoNames, NHTSA) replacing curated
   fields where the data is factual
4. Frequency data (Census, SSA) populating the weight column
5. Generative models for names, with the safety filters above
6. Coverage gates reach threshold → delete the faker-js adapter

Steps 3–5 are independent and can proceed in any order. Step 6 is a consequence, not a
task.

---

## Attribution while the bootstrap lasts

The corpus is currently derived from [@faker-js/faker](https://github.com/faker-js/faker),
MIT licensed. The upstream copyright notice is retained alongside the extracted data.
That obligation ends only when the faker-js adapter is deleted and no derived data
remains.
