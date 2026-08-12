---
title: Your first fixtures
description: Generating rows, and why the same seed gives the same people forever.
---

A `Faker` is a value type carrying a seed and a locale. Draws advance its state, so a
faker is a stream rather than a bag.

```swift
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)

faker.person.fullName()        // "Kathrine Meyers"
faker.location.streetAddress() // "7913 Kuhic Ridge"
faker.company.name()           // "Boyle, Kunde and Hessel"
```

Run that on any machine, on any day, and you get the same three strings. That is the
whole contract, and it holds until the corpus version changes — which it does loudly.

## Coherent rows

Independent draws produce records that do not exist. `city: "Boston", state: "CA"` passes
most validators and is nonsense. Where the parts of a record must agree, draw them
together:

```swift
let place = faker.location.placeAndPostcode()
// (city: "Boston", state: "Massachusetts", stateCode: "MA", postcode: "02108")
```
