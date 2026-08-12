---
title: Fixtures in tests
description: Using generated data in a test suite without making it flaky.
---

The point of a seeded generator in a test suite is that failures are reproducible. Two
habits get you that.

## Seed per test, not per suite

```swift
@Test("a user with no posts shows the empty state")
func emptyState() {
    var faker = Faker(seed: 1, locale: DecoyLocaleEN.locale)
    let user = User(name: faker.person.fullName(), posts: [])
    #expect(render(user).contains("Nothing here yet"))
}
```

A faker shared across tests couples them: adding a draw in one changes the data in
another, and the order tests run in starts to matter. Make one per test and the failure
you see is the failure anyone else sees.

## Do not assert on generated values

```swift
// Fragile — breaks on any corpus update
#expect(user.name == "Riley Bonneau")

// Durable — asserts the thing you actually care about
#expect(!user.name.isEmpty)
#expect(user.email.contains("@"))
```

Generated data is for *filling* records, not for pinning them. If a test genuinely needs
an exact string, write it literally — that is clearer than deriving it from a seed and
hoping the corpus never moves.

## When you do want exact values

Golden-file tests are the exception, and they need a pinned corpus version:

```swift
// Regenerate deliberately when the corpus major version changes.
let rows = users.generate(20, seed: 1337)
assertSnapshot(of: rows, as: .json)
```

Record the corpus version next to the snapshot. When it changes, the diff tells you why.

## Realistic volume, cheaply

```swift
let rows = users.generate(10_000, seed: 1337)
```

Rows are independent, so this parallelises and there is no accumulating state to reset
between tests.

## A locale you can rely on

Pick a locale that actually carries the fields you are testing. If your test asserts on
address formatting, check the [locale matrix](/reference/locale-matrix/) first — a locale
that inherits addresses from English will not exercise what you think it does.

```swift
#expect(try DecoyLocaleJA.locale.nativeCoverage > 0.3)
```

## What not to use it for

Not for security tests. Passwords, tokens and keys from a seeded generator are
predictable by construction — that is the whole point — so never let one reach anything
that treats it as a secret.
