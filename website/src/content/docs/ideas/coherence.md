---
title: Coherent records
description: Which values are drawn together, which are not, and why the line falls there.
---

Three independent draws give you a city, a subdivision and a postcode that have never
coexisted:

```
city: "Boston", state: "CA", postcode: "10001"
```

That passes most validators. It is also nonsense, and it is what you get from any
generator that treats those three fields as unrelated — which is nearly all of them,
because storing them as one table is more work than storing three.

## Drawn together

Where a record would otherwise contradict itself, Decoy stores a composite and draws the
row as a unit.

```swift
faker.location.placeAndPostcode()
// (city: "Paducah", state: "Kentucky", stateCode: "KY", postcode: "42279")

faker.location.stateRow()      // ["name": "North Dakota", "abbr": "ND"]
faker.location.countryCode()   // ["alpha2": "CK", "alpha3": "COK", "numeric": "184"]
faker.location.language()      // ["name": …, "alpha2": …, "alpha3": …]
faker.science.chemicalElement()
```

The city and subdivision come from one gazetteer row, so they cannot disagree. The
postcode is drawn from inside that subdivision's own range where the locale has one — the
United States and Canada — and falls back to the national mask elsewhere, because
gazetteers code subdivisions their own way and only the US codes happen to coincide with
the ISO ones the postcode ranges are keyed by.

An ISO 3166 triple drawn as three independent values would produce countries that do not
exist. So it is one row, always.

## Deliberately not drawn together

`city()` and `state()` stay independent. Most rows want one or the other, and pairing
them would halve the variety for no benefit — a fixture with a city column and no state
column gains nothing from the pairing and loses half its distinct values.

The rule is: **couple where a mismatch would be a defect, not merely a coincidence.**

`media.book()` returns a title, an author and a genre drawn independently, and that is
deliberate too. An author paired with a title they did not write is obviously fake data
and harms nothing; correlating them would need a real bibliography, which is exactly the
sourcing problem that namespace exists to sidestep.

## Names, which are the hard case

Five locales — `zh_CN`, `zh_TW`, `vi`, `id_ID`, `yo_NG` — carry their own surnames and
their own name pattern, but no given names.

Resolving each path on its own merits handed `zh_CN` the Han pattern
`{{lastName}}{{firstName}}` — correct in having no separator — and then filled the second
half from English. The result was `ChengAaliyah`: two scripts, no space, and nothing at
the call site to suggest anything was wrong.

`fullName()` now composes from the first corpus in the chain that carries the parts, so
those locales return an entirely English name. It is obviously a fallback, and a caller
notices it immediately rather than shipping it.

```swift
var f = Faker(seed: 11, locale: chineseLocale)
f.person.fullName()   // "Aaliyah Bradley"  — English, and visibly so
f.person.lastName()   // "蒲察"              — still native
```

`lastName()` is untouched, because a caller asking only for a surname is not building
anything self-contradictory. It is the *composition* that has to agree with itself.

An earlier attempt narrowed only the pattern and produced `Brenda 安期` — which fixed the
spacing and left both languages exactly where they were. The parts have to come from the
same corpus as the pattern, not just the pattern.
