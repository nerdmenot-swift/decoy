---
title: Seeds and reproducibility
description: What the same seed guarantees, and the two things that change the answer.
---

A **seed** is a number you choose. Decoy's randomness is deterministic, so the same
number always makes the same choices — which is what turns generated data into something
you can rely on twice.

Precisely: the same seed, the same corpus version and the same call order produce the
same values, on every machine and every platform.

```swift
var a = Faker(seed: 42, locale: DecoyLocaleEN.locale)
var b = Faker(seed: 42, locale: DecoyLocaleEN.locale)

a.person.fullName()   // "Penny Syverson"
b.person.fullName()   // "Penny Syverson"
```

## A faker is a stream

Each draw advances state. Adding a call in the middle shifts everything after it:

```swift
var f = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
f.person.fullName()        // "Riley Bonneau"
f.location.city()          // depends on the draw above having happened
```

If you need a value that survives reordering, derive it from the row index instead:

```swift
.rule(\.email) { "user\($0.index)@example.com" }
```

## Rows are independent

Row 400 is a function of `(seed, 400)`, not of rows 0–399 having been generated first:

```swift
let whole = users.generate(500, seed: 1337)
let slice = users.generate(rows: 400..<403, seed: 1337)

whole[400].name == slice[0].name   // true
```

That is what makes a large job splittable across tasks, or resumable after a failure at
row 700,000.

## Dates do not drift

`past()` and `future()` are relative to a fixed reference instant, not to `now`.
Anchoring to the clock would mean seed 1337 giving different fixtures tomorrow than
today. Supply your own anchor when you want dates around a particular moment:

```swift
Faker(seed: 1337, reference: myInstant)
Forge<User>("User") { User() }.reference(myInstant)
```

## The corpus version

Reproducibility is guaranteed *with respect to a corpus*, and the corpus is a build
artifact.

**Adding data is a minor bump. Changing or removing a value is a major one**, because it
changes every fixture anyone has already generated. Removing a single mis-typed name took
the corpus from 57.2.0 to 58.0.0 — a typo, and still a breaking change.

Record the corpus version alongside your seed. When rows differ, that is the first thing
to check.
