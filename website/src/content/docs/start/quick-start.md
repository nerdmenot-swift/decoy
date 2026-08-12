---
title: Quick start
description: Generating values, and why the same seed gives you the same people forever.
---

## If you do not care about seeds

Then do not pass one.

```swift
var faker = Faker(locale: DecoyLocaleEN.locale)

faker.person.fullName()   // a different name every run
```

You get plausible data and nothing to think about. The same works for forges —
`users.generate(100)`.

One thing worth knowing: the seed still exists, it was just chosen for you, and you can
read it back.

```swift
print(faker.seed)   // 14086741927554889
```

That matters the first time generated data turns up something surprising — a name that
breaks a layout, a row that trips a validator. Print the seed, pass it to
`Faker(seed:)`, and you have the exact run again to show somebody.

## What a seed is

A **seed** is just a number you choose.

Decoy's randomness is deterministic: the same number always makes the same choices. Seed
1337 gives you the same names, the same addresses and the same companies today, next
year, on your laptop and in CI. Change the number and you get an entirely different set —
equally repeatable.

That is the whole point. Fixtures you can regenerate exactly are fixtures you can rely on
in a test, a screenshot diff or a demo database.

```swift
Faker(seed: 1337, locale: DecoyLocaleEN.locale)   // these people
Faker(seed: 42, locale: DecoyLocaleEN.locale)     // different people, just as repeatable
```

Any `UInt64` works. Pick one, write it down, and keep it in the code rather than in an
environment variable that varies by machine.

## A faker is a stream

A `Faker` is a value type carrying a seed, a locale and a row index. Every draw advances
its state, so a faker is a stream rather than a bag — which is why it is `inout`
everywhere and why `var` matters.

```swift
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)

faker.person.fullName()         // "Riley Bonneau"
faker.location.streetAddress()  // "12289 Seaman Divide"
faker.company.name()            // "Crosslin inc."
faker.internet.email()          // "david.paul@example.net"
faker.person.jobTitle()         // "Implemented frame Designer"
```

Run that on any machine, on any day, on any platform, and you get those five strings in
that order. Draw them in a different order and you get different values — the stream
advances, it does not memoise per generator.

## The same seed, twice

```swift
var a = Faker(seed: 42, locale: DecoyLocaleEN.locale)
var b = Faker(seed: 42, locale: DecoyLocaleEN.locale)

a.person.fullName()   // "Penny Syverson"
b.person.fullName()   // "Penny Syverson"
```

That guarantee holds against **a corpus version**. Adding data is a minor bump; changing
or removing an existing value is a major one, because it silently changes every fixture
anyone has already generated. See [the corpus version](/guides/seeds/#the-corpus-version).

## Rows that agree with themselves

Independent draws produce records that have never existed. `city: "Boston"` beside
`state: "CA"` passes most validators and is nonsense, and it is what you get from any
generator that treats the two as unrelated.

Where the parts of a record must agree, draw them as a unit:

```swift
let place = faker.location.placeAndPostcode()
// (city: "Paducah", state: "Kentucky", stateCode: "KY", postcode: "42279")

let country = faker.location.countryCode()
// ["alpha2": "CK", "alpha3": "COK", "numeric": "184"]

let state = faker.location.stateRow()
// ["name": "North Dakota", "abbr": "ND"]
```

`city()` and `state()` stay independent, because most rows want one or the other and
pairing them would halve the variety for no benefit. [Forges](/guides/forges/) is where you compose a row that has to agree with itself.

## Another language

Pass a different locale and the shape of the data changes, not just the words. German
addresses put the number after the street; Japanese names have no space.

```swift
var de = Faker(seed: 2024, locale: DecoyLocaleDE.locale)
de.person.fullName()          // "Benning Blaha"
de.location.streetAddress()   // "Grubergasse 17"
de.commerce.productName()     // "Praktische Sofas aus Leder"
de.finance.accountType()      // "Baufinanzierung"

var ja = Faker(seed: 2024, locale: DecoyLocaleJA.locale)
ja.person.fullName()          // "竹川しゅうこ"
ja.company.name()             // "小笠原合名会社"
```

Not everything is localised, and the library tells you which parts. Check the [locale
matrix](/reference/locale-matrix/) before you pick one.

## Patterns and masks

Two helpers for the formats you already have a shape for:

```swift
faker.numerify("+1 (###) ###-####")   // "+1 (339) 237-5868"
faker.bothify("??-####-%#")           // "HP-6857-58"
```

`#` is any digit, `%` is 1–9, `!` is 2–9, `?` is a letter and `*` is either. `%` exists
because `###` yields a leading zero about one time in a thousand, which is how house
number `0` reaches production.
