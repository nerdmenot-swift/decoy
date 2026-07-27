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
- **Foundation-free arithmetic.** Everything that decides a *value* — the RNG, the
  corpus reader, calendar maths — imports nothing, so results are identical across
  platforms. Foundation appears only at the edge: the `date` namespace returns
  `Foundation.Date` behind `#if canImport`, and `Timestamp` provides the same dates
  without it. On Linux this resolves to the lean `FoundationEssentials` rather than
  the full corelibs implementation.
- **Dates are anchored, not "now".** `past()` is relative to a fixed reference
  instant, because anchoring to the system clock would mean seed 1337 producing
  different fixtures tomorrow than today — a reproducibility hole every other faker
  has.
- **No runtime JSON parsing.** The corpus compiles to a compact binary format (string
  arena + offset table) loaded once and sliced. Notably this avoids `Bundle.module`,
  the most platform-fragile part of SPM and a large share of Fakery's trouble off
  macOS.
- **Typed key paths, no reflection anywhere.** Rules are `WritableKeyPath`s, so the
  value type of every rule is checked at compile time. Nothing in the library reflects
  on a type — which is why a `Forge` is named explicitly: deriving the seed from
  `String(reflecting: T.self)` would mean renaming `User` to `Account`, or moving it
  to another module, silently changing every fixture it generates.
- **Rows are independent.** Each row is seeded from `(seed, rowIndex)` rather than
  continuing one long stream, so row 500 is the same value whether you generated
  1,000 rows or asked for rows `500..<600`. Generation is therefore parallelisable
  and resumable, and `Forge` is `Sendable`.

```swift
import Decoy
import DecoyLocaleDE

let users = Forge<User>("user") { User() }
    .locale(DecoyLocaleDE.locale)
    .rule(\.id)        { _ in UUID() }
    .rule(\.gender)    { $0.pick(Gender.allCases) }
    .rule(\.firstName) { f, u in f.person.firstName(u.gender) }  // agrees with gender
    .rule(unique: \.email) { $0.internet.email() }               // unique-constraint safe
    .rule(\.deletedAt) { $0.maybe(chance: 0.1) { $0.date.past() } }
    .generate(1_000, seed: 1337)

let orders = Forge<Order>("order") { Order() }
    .rule(\.userId) { f in f.pick(users).id }    // referential integrity
    .rule(\.total)  { $0.commerce.price() }
    .generate(5_000, seed: 1337)
```

Locales are compiled into the binary as ordinary Swift source, so there is no resource
loading at runtime and nothing to ship alongside your executable. One module per
locale means importing `DecoyLocaleDE` costs you `de`, `en` and `base` — not all 76.

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
- [x] Seeded RNG (`Xoshiro256**` behind `RandomNumberGenerator`)
- [x] `Forge<T>` with rules, traits, streaming, child fan-out and unique constraints
- [x] Node extractor: `@faker-js/faker` → JSON, with verified fallback chains
- [x] JSON → binary corpus format + Swift reader
- [x] 204 generators across 22 namespaces, including dates
- [x] `base`, `en`, `de`, `ja` compiled in as per-locale modules
- [ ] CI actually run (the workflow exists but has never executed)

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
