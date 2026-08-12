---
title: Forges
description: Describing a type once and generating as many of them as you need.
---

A `Forge` maps generated values onto your own types, with rules, traits and
relationships.

```swift
let users = Forge<User>()
    .rule(\.name) { $0.person.fullName() }
    .rule(\.email) { "user\($0.index)@example.com" }
    .trait("admin") { $0.rule(\.role) { _ in .admin } }

let rows = users.generate(rows: 1_000, seed: 1337)
```

`index` is the zero-based row number, which is what makes collision-free derived values
cheap without a uniqueness constraint.
