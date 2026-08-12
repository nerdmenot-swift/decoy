---
title: Install
description: Adding Decoy to a Swift package, and the one thing people get wrong first.
---

Decoy is a Swift 6 package with no dependencies. Add it, then add a locale.

```swift
.package(url: "https://github.com/NerdMeNot/decoy", from: "1.0.0")
```

```swift
.target(name: "MyTests", dependencies: [
    .product(name: "Decoy", package: "decoy"),
    .product(name: "DecoyLocaleEN", package: "decoy"),
])
```

## Always import a locale

This is the one that catches people. `Faker`'s default corpus is a ten-path smoke-test
stub — enough to prove the wiring, not enough to generate anybody.

```swift
import Decoy
import DecoyLocaleEN

var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
faker.person.fullName()   // "Kathrine Meyers"
```

Locales compile into the binary as ordinary Swift source, so there is no resource
loading at runtime and nothing to ship beside your executable. One module per locale
means importing `DecoyLocaleDE` costs you `de`, `en` and `base` — not all sixty-four.
