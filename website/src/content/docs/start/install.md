---
title: Install
description: Adding Decoy to a Swift package, and the one thing everybody gets wrong first.
---

Decoy is a Swift 6 package with no dependencies. Two edits to `Package.swift`:

```swift
// Package.swift
let package = Package(
    name: "MyApp",
    // 1. Where to fetch it from.
    dependencies: [
        .package(url: "https://github.com/nerdmenot-swift/decoy", from: "1.0.0"),
    ],
    targets: [
        // 2. Which of your targets uses it, and which products they use.
        .testTarget(name: "MyAppTests", dependencies: [
            .product(name: "Decoy", package: "decoy"),
            .product(name: "DecoyLocaleEN", package: "decoy"),
        ]),
    ]
)
```

Both are needed, and that is SwiftPM's design rather than anything Decoy asks for. The
top-level `dependencies` array only tells SwiftPM where to resolve the package from; it
does not put anything on any target's import path. Each target then names the products it
actually uses, which is what lets a test target depend on Decoy while your shipping target
does not — so fake-data generators and their corpora never end up linked into your app.

The second entry is a separate product on purpose. `Decoy` is the engine and
`DecoyLocaleEN` is the data; you pick the locales you want and pay for those only.

## Always pass a locale

`Faker` has no default one, and that is the point: the compiler asks you for it rather
than letting `Faker()` build and then trap on the second line. There *is* a built-in
corpus — `LocaleCorpus.builtIn` — but it defines ten paths against the hundred and
ninety-five the generators draw from, so almost everything would fail at run time. The
generators that need no corpus at all, like checksums and UUIDs, take it explicitly:

```swift
var faker = Faker(seed: 1337, locale: .builtIn)   // no corpus needed here
faker.crypto.ethereumAddress()
```

which reads as a decision rather than an accident.

```swift
import Decoy
import DecoyLocaleEN

// `faker` is a variable you create, not a global or a module. Name it what you like —
// every example on this site calls it `faker`, which is why the calls below read as
// `faker.something`.
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)

faker.person.fullName()   // "Riley Bonneau"
faker.company.name()      // "Foote COOP"
```

It must be a `var`. `Faker` is a struct that carries its own random state, so each draw
mutates it — that is what makes a run reproducible instead of depending on shared global
state. Hold one per test, or let a [forge](/guides/forges/) hold it for you.

Three locales ship as importable modules — `DecoyLocaleEN`, `DecoyLocaleDE` and
`DecoyLocaleJA`. The corpus holds sixty-five, and the other sixty-two are reached through
the `DecoyLocales` product, which carries every blob as a resource and loads one by code:

```swift
import DecoyLocales
let fr = try DecoyLocales.locale("fr")
```

See [Locales](/guides/locales/) for which to use when.

## Why a module rather than a resource file

A locale module compiles into your binary as ordinary Swift source — a base64
`StaticString` decoded once — so there is no resource loading at run time and nothing to
ship beside your executable. That avoids `Bundle.module`, which is the most
platform-fragile corner of SwiftPM.

`DecoyLocales` does use it, because sixty-five blobs cannot reasonably be sixty-five
modules. That is the trade: reach for a module when your locale has one, and the resource
product when it does not.

One module per locale means importing `DecoyLocaleDE` costs you `de`, `en` and `base`
and nothing else. SwiftPM compiles only the targets you actually depend on.

## Requirements

Swift 6.0 or later, in Swift 6 language mode. macOS 13+, iOS 16+, or Linux.

Everything that decides a *value* — the RNG, the corpus reader, the calendar maths —
imports nothing at all, so results are identical across platforms. Foundation appears
only at the edge: the `date` namespace returns `Foundation.Date` behind
`#if canImport(Foundation)`, and `Timestamp` gives you the same instants without it.
