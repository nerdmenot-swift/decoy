---
title: Seeding a database
description: A million coherent rows, kept stable across runs and split across tasks.
---

Generating a million rows is the easy part. Keeping them stable, unique where they must
be, and coherent where they must agree is the rest of it.

## Start with the shape

```swift
struct User {
    var id = 0
    var username = ""
    var email = ""
    var name = ""
    var city = ""
    var region = ""
    var postcode = ""
    var createdAt = Date()
}

let users = Forge<User>("User") { User() }
    .locale(DecoyLocaleEN.locale)
    .rule(\.id) { $0.index + 1 }
    .rule(\.email) { "user\($0.index)@example.com" }
    .rule(\.name) { $0.person.fullName() }
    .rule(\.createdAt) { $0.date.past(years: 3) }
    .finish { faker, user in
        let place = faker.location.placeAndPostcode()
        user.city = place.city
        user.region = place.state
        user.postcode = place.postcode
    }
```

Two things worth copying from that.

**Derive from `index` where you can.** `id` and `email` cannot collide because arithmetic
says so, not because a constraint retried until it got lucky. That is cheaper and it
survives chunking.

**Use `finish` for fields that must agree.** Drawing the city, region and postcode as one
row is what stops you inserting a Boston address in California.

## Uniqueness that actually needs the constraint

```swift
    .rule(unique: \.username, label: "username") { $0.internet.username() }
```

Use it when the value genuinely cannot be derived. It retries until it finds one no
earlier row used, and throws `ForgeError.uniqueConstraintExhausted` — naming the property,
the attempts and any active traits — rather than looping forever or silently repeating.

```swift
do {
    let rows = try users.tryGenerate(1_000_000, seed: 1337)
} catch let error as ForgeError {
    print(error)
}
```

## Runs too large to hold

```swift
for user in users.stream(seed: 1337).prefix(1_000_000) {
    try await db.insert(user)
}
```

`stream` is a lazy `Sequence`, so nothing accumulates. Use it when the run does not fit
in memory or when you want to start inserting before generation finishes.

## Runs too large to wait for

Rows are independent, so a slice is exactly what those indices of the whole run would
have been:

```swift
await withTaskGroup(of: [User].self) { group in
    for chunk in stride(from: 0, to: 1_000_000, by: 50_000) {
        group.addTask { users.generate(rows: chunk..<chunk + 50_000, seed: 1337) }
    }
    for await batch in group { try await db.insert(batch) }
}
```

The same property makes a failed job resumable: if it died at row 700,000, generate
`700_000..<1_000_000` and the rows match what the first attempt would have produced.

**This does not work with `unique` rules, and traps rather than pretending.** Chunks
cannot see each other's values, so uniqueness could not be honoured — and allowing it
silently would produce duplicates that surface as a constraint violation at insert time,
long after the run looked successful. Derive from `index` instead, or generate the whole
run in one call.

## Referential integrity

```swift
let posts = Forge<Post>("Post") { Post() }
    .rule(\.title) { $0.lorem.sentence() }
    .rule(\.body) { $0.lorem.paragraphs(3) }

let users = users.each(\.posts, 0...12, of: posts)
```

Children get a seed derived from the parent's stream, so the whole tree is reproducible
from the one seed at the top.

## Keeping the seed somewhere

Put it in the fixture script, not in an environment variable that varies by machine. The
guarantee is only worth having if everyone runs the same number.

And record the corpus version alongside it. Reproducibility is *with respect to a corpus*,
and the version is the thing that tells you why last month's rows differ.
