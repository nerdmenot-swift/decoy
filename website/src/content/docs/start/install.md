---
title: Install
description: Adding Decoy to a Swift package, and the one thing everybody gets wrong first.
---

Decoy is a Swift 6 package with no dependencies. Add it, then add a locale.

```swift
// Package.swift
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
stub — enough to prove the wiring, not enough to generate anybody. Ask it for a company
name and it traps with a message telling you exactly this.

```swift
import Decoy
import DecoyLocaleEN

var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
faker.person.fullName()   // "Riley Bonneau"
```

Three locales ship as importable modules today — `DecoyLocaleEN`, `DecoyLocaleDE` and
`DecoyLocaleJA`. Sixty-four compile; the rest are emitted on request, which is two
commands and a line in `Package.swift`. See [Locales and fallback](/ideas/locales/).

## Why a module and not a resource file

Locales compile into your binary as ordinary Swift source — a base64 `StaticString`
decoded once — so there is no resource loading at runtime and nothing to ship beside
your executable. That deliberately avoids `Bundle.module`, which is the most
platform-fragile corner of SwiftPM.

One module per locale means importing `DecoyLocaleDE` costs you `de`, `en` and `base`
and nothing else. SwiftPM compiles only the targets you actually depend on.

## Requirements

Swift 6.0 or later, in Swift 6 language mode. macOS 13+, iOS 16+, or Linux.

Everything that decides a *value* — the RNG, the corpus reader, the calendar maths —
imports nothing at all, so results are identical across platforms. Foundation appears
only at the edge: the `date` namespace returns `Foundation.Date` behind
`#if canImport(Foundation)`, and `Timestamp` gives you the same instants without it.
