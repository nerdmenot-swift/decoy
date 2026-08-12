---
title: Quick start
description: Generating values, and why the same seed gives you the same people forever.
---

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
anyone has already generated. See [Determinism](/ideas/determinism/).

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
pairing them would halve the variety for no benefit. [Coherent
records](/ideas/coherence/) explains where the line is.

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
