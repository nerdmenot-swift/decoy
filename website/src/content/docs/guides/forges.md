---
title: Forges
description: Describing a type once, then generating as many of them as you need.
---

A `Forge<T>` maps generated values onto your own type. It is a value type: every method
returns a new forge, so they compose and nothing mutates under you.

```swift
struct User {
    var name = ""
    var email = ""
    var role = Role.member
    var posts: [Post] = []
}

let users = Forge<User>("User") { User() }
    .rule(\.name) { $0.person.fullName() }
    .rule(\.email) { "user\($0.index)@example.com" }
    .locale(DecoyLocaleEN.locale)

users.generate(3, seed: 1337)
// User(name: "James Grow",       email: "user0@example.com", …)
// User(name: "Dr. Linda Vereen", email: "user1@example.com", …)
// User(name: "Phillis Madden",   email: "user2@example.com", …)
```

The name — `Forge<User>("User")` — is given explicitly rather than derived. Nothing in
the library reflects on a type, so there is nothing to read it from, and a mis-typed
label is a worse failure than a redundant one.

## Rules

`rule` takes a writable key path and a closure. Two shapes: one that sees only the
faker, and one that also sees the row built so far.

```swift
.rule(\.name) { faker in faker.person.fullName() }
.rule(\.slug) { faker, user in user.name.lowercased().replacingOccurrences(of: " ", with: "-") }
```

`faker.index` is the zero-based row number. It is the cheapest way to get values that
cannot collide, without paying for a uniqueness constraint:

```swift
.rule(\.email) { "user\($0.index)@example.com" }
```

## Uniqueness, when you actually need it

`rule(unique:)` retries until it finds a value no earlier row in the same run used.

```swift
let users = Forge<User>("User") { User() }
    .rule(unique: \.username, label: "username") { $0.internet.username() }
```

If the pool is too small it throws `ForgeError.uniqueConstraintExhausted` naming the
property, the attempt count and any traits in play, rather than looping forever or
quietly repeating. Use `tryGenerate` to catch it:

```swift
do {
    let rows = try users.tryGenerate(50_000, seed: 1337)
} catch let error as ForgeError {
    print(error)   // names the property and how many attempts it made
}
```

Prefer `index`-derived values where you can. Uniqueness needs every row to see every
other row, and that has consequences below.

## Cycling and children

```swift
let posts = Forge<Post>("Post") { Post() }
    .rule(\.title) { $0.lorem.sentence() }

let users = Forge<User>("User") { User() }
    .rule(\.name) { $0.person.fullName() }
    .cycle(\.role, through: [.member, .editor, .admin])
    .each(\.posts, 0...5, of: posts)
```

`cycle` assigns by row index, so a run of 300 gets exactly 100 of each — useful when you
need coverage of every case rather than a random spread. `each` generates a nested forge
with a seed derived from the parent's stream, so children are reproducible too. Pass a
plain number for a fixed fan-out: `.each(\.posts, 3, of: posts)`.

The child inherits the parent's locale, reference instant and `novelNames` setting, so
you configure them once on the parent. A child that sets its own keeps it.

## Traits

A trait is a named transformation, applied at generation time.

```swift
let admin = Trait<User>("admin") { $0.rule(\.role) { _ in .admin } }
let banned = Trait<User>("banned") { $0.rule(\.status) { _ in .banned } }

users.generate(10, seed: 1337, applying: admin, banned)
```

Traits appear in `ForgeError` messages, which is why they are named: a uniqueness
failure that only happens under one combination of traits is otherwise very hard to
reproduce.

Extending `Trait` with static members reads better at the call site:

```swift
extension Trait where T == User {
    static var admin: Trait { Trait("admin") { $0.rule(\.role) { _ in .admin } } }
}

users.generate(10, seed: 1337, applying: .admin)
```

swift-testing exports a protocol also called `Trait`, so in a test file you need one
selective import to say which you mean:

```swift
import Testing
import struct Decoy.Trait
import Decoy
```

Only the `extension` needs it — `applying: .admin` never names the type.

## Finishing a row

`finish` runs last and sees the whole row, for the invariants that need everything else
decided first.

```swift
.finish { faker, user in
    user.displayName = user.name.isEmpty ? user.email : user.name
}
```

## Generating

| Call | Use |
|---|---|
| `generate(_:seed:)` | the whole run, traps on error |
| `tryGenerate(_:seed:)` | the same, throwing |
| `one(seed:)` | a single row |
| `generate(rows:seed:)` | a slice, for parallel or resumed runs |
| `stream(seed:)` | a lazy sequence, for runs too large to hold |

Rows are independent, so a slice is exactly what the same indices of the whole run would
have been:

```swift
let whole = users.generate(500, seed: 1337)
let slice = users.generate(rows: 400..<403, seed: 1337)

whole[400].name == slice[0].name   // true — "Mark Reddick IV"
```

That is what makes a million-row job splittable across tasks, or resumable after a
failure at row 700,000.

**`generate(rows:seed:)` refuses a forge with `unique` rules,** and traps saying so.
Separate chunks cannot see each other's values, so uniqueness could not be honoured —
and allowing it silently would produce duplicates that only surface as a constraint
violation at insert time. Use `generate(_:seed:)` for the whole run instead.

## Other knobs

```swift
users
    .locale(DecoyLocaleDE.locale)   // which language this forge speaks
    .reference(myInstant)           // the anchor `past()` and `future()` work from
    .novelNames()                   // surnames no real person is recorded as having
```

`novelNames()` swaps the weighted register lists for character-level models trained on
them. Off by default, because the registers carry real frequency data and turning that
off silently would throw away the realism it was built for. See [what was declined](/reference/design-notes/#what-was-declined).
