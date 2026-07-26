# Decoy

A seeded fake-data generator for Swift — for seeding databases and building test
fixtures.

Reproducible by construction, portable across macOS, Linux, and Windows.

> **Status: pre-alpha.** Nothing here is usable yet. See the v1 scope below.

## Why

[Fakery](https://github.com/vadymmarkov/Fakery) is the only established Swift option,
and it has three problems Decoy exists to fix:

- **No seed injection.** You cannot supply a `RandomNumberGenerator`, so runs are not
  reproducible — fatal for fixtures and database seeding.
- **Effectively unmaintained.** Last PR merged ~2 years ago.
- **Shallow non-English data.** It vendors Ruby faker's corpus, the weakest of the
  major fakers outside English.

## Design

- **Local seeding only.** The RNG is a value type threaded through as `inout`. No
  global mutable seed — it is fragile under code changes and a `Sendable` violation
  under Swift 6 strict concurrency.
- **Foundation-free core.** The `Decoy` target imports no Foundation, so behaviour is
  identical across platforms. Foundation interop (`UUID`, `Date`) sits behind
  `#if canImport` shims — a convenience, never a requirement.
- **No runtime JSON parsing.** The corpus compiles to a compact binary format (string
  arena + offset table) loaded once and sliced. Notably this avoids `Bundle.module`,
  the most platform-fragile part of SPM and a large share of Fakery's trouble off
  macOS.
- **Typed key paths, no reflection.** Rules are `WritableKeyPath`s, so the value type
  of every rule is checked at compile time.
- **Rows are independent.** Each row is seeded from `(seed, rowIndex)` rather than
  continuing one long stream, so row 500 is the same value whether you generated
  1,000 rows or asked for rows `500..<600`. Generation is therefore parallelisable
  and resumable, and `Forge` is `Sendable`.

```swift
let users = Forge<User> { User() }
    .rule(\.id)        { _ in UUID() }
    .rule(\.firstName) { $0.name.firstName() }
    .rule(\.email)     { $0.internet.email() }
    .rule(\.deletedAt) { $0.maybe(0.9) { $0.date.past() } }
    .generate(1_000, seed: 1337)

let orders = Forge<Order> { Order() }
    .rule(\.userId) { f in f.pick(users).id }    // referential integrity
    .rule(\.total)  { $0.commerce.price() }
    .generate(5_000, seed: 1337)
```

Referential integrity falls out of closures capturing already-generated arrays. No
"World" abstraction, no inheritance gymnastics.

Large seed jobs split across tasks and reassemble into exactly the sequential result:

```swift
await withTaskGroup { group in
    for start in stride(from: 0, to: 1_000_000, by: 50_000) {
        group.addTask { users.generate(rows: start..<start + 50_000, seed: 1337) }
    }
}
```

## Platforms

macOS, Linux, and Windows are all first-class targets; iOS/tvOS/watchOS/visionOS are
supported for app developers. Linux is verified both natively in CI and by
cross-compiling against the Swift Static Linux SDK. Windows is best-effort.

## v1 scope

- [x] Multi-platform package skeleton, verified cross-compiling to Linux
- [ ] Seeded RNG (`Xoshiro256**` behind `RandomNumberGenerator`)
- [ ] `Forge<T>` with `.rule(_:_:)`, `.generate(_:seed:)`, `.maybe(_:_:)`, `.pick(_:)`
- [ ] Node extractor: `@faker-js/faker` → JSON
- [ ] JSON → binary corpus format + Swift reader
- [ ] Core generators: name, address, internet, company, phone, commerce, date
- [ ] `en` + 2–3 locales, per-locale targets

Deferred: strict-mode rule checking (needs a macro, and macro plugins are
host-executed and historically awkward under cross-compilation), rule sets, the other
70+ locales.

## Attribution

The data corpus is derived from [@faker-js/faker](https://github.com/faker-js/faker),
MIT licensed, and the upstream copyright notice is retained in the vendored data
directory. faker-js was chosen for the depth of its non-English data and because it
models names as `{ generic, female, male }` rather than flat lists, which lets Decoy
generate a coherent `(firstName, gender)` pair instead of contradicting itself.

## License

Apache 2.0. © NerdMeNot.
