---
title: Seeding a database
description: Ten thousand coherent rows, and keeping them stable across runs.
---

Generating a million rows is the easy part. Keeping them stable, unique where they must
be, and coherent where they must agree is the rest of it.

```swift
let users = Forge<User>()
    .rule(\.email) { "user\($0.index)@example.com" }   // unique by construction
    .unique(\.username)                                 // unique by constraint

for batch in users.stream(rows: 1_000_000, seed: 1337, batchSize: 5_000) {
    try await db.insert(batch)
}
```
