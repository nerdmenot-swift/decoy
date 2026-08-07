# Decoy

A seeded fake-data generator for Swift — for seeding databases and building test
fixtures.

Reproducible by construction, portable across macOS, Linux, and Windows.

> **Status: pre-alpha.** The API and the corpus are both still moving, and the corpus
> version will keep bumping — which changes the data a given seed produces. Usable, but
> do not pin fixtures you cannot regenerate. See the v1 scope below.

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
- **Every string carries its origin.** The corpus records which source and licence each
  path came from, so `decoy-inspect` can answer "where did this come from" and generate
  attribution from what actually shipped. No other faker records this, which is why none
  of them can be audited or licensed with confidence.
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
    .rule(\.id)        { $0.uuidV7Value() }                      // seeded, and sorts by row
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

**Always import a locale.** `Faker`'s default corpus is a ten-path smoke-test stub, so
most generators trap against it; `base` is language-neutral data every chain ends at and
is not importable on its own for the same reason.

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

## The corpus is a build artifact

No data is hand-edited, and none is committed. `Tools/adapters/` holds *programs* that
derive the corpus from twenty-seven pinned upstreams — each fetched by URL, verified
against an integrity hash, and recorded in the corpus with its licence:

```
Tools/adapters/
  sources/<id>.json     pinned descriptor: URL, integrity hash, licence, version
  adapters/<id>.mjs     the transform
  locales.json          the locale roster
  corpus-version.json   the corpus version, declared once
  run.mjs               orchestrator
```

Rebuild it with `node Tools/adapters/run.mjs`, then `swift run decoy-compile-corpus`.
There is no package manifest and nothing to install: they are plain `.mjs` files, and a
toolchain built to remove a dependency should not need a package manager of its own.

Countries, languages, currencies, time zones, media types, subdivisions, cities,
programming languages, elements, units and English surnames come from registries — CLDR,
IANA, the ISO 4217 registry, GeoNames, Linguist, PubChem, the US Census. Person names,
streets and most vocabulary are still inherited from `@faker-js/faker`, which is the
lowest-precedence adapter and is deleted a field at a time as others cover its ground.

`decoy-inspect` audits any of it — every path, what a locale defines itself, and which
source and licence covers each field:

```
swift run decoy-inspect Corpus/binary/en.decoy            # summary and provenance
swift run decoy-inspect Corpus/binary/en.decoy --paths    # every path
swift run decoy-inspect --coverage Corpus/binary          # native coverage per locale
swift run decoy-inspect --notice Corpus/binary            # attribution, generated
```

See [docs/corpus-strategy.md](docs/corpus-strategy.md) for why, and
[docs/corpus-format.md](docs/corpus-format.md) for the binary layout.

## v1 scope

- [x] Multi-platform package skeleton, verified cross-compiling to Linux
- [x] Seeded RNG (`Xoshiro256**` behind `RandomNumberGenerator`)
- [x] `Forge<T>` with rules, traits, streaming, child fan-out and unique constraints
- [x] Adapter pipeline: 27 pinned sources, integrity-verified, provenance per path
- [x] JSON → binary corpus format + Swift reader
- [x] 191 generators across 18 namespaces, including dates, seeded UUIDs and checksummed crypto addresses
- [x] All 76 locales compile; `en`, `de`, `ja` ship as importable Swift modules
- [x] `decoy-inspect`: enumeration, coverage, generated attribution
- [ ] CI actually run — the workflow is correct but this repository has no remote

Deferred: strict-mode rule checking (needs a macro, and macro plugins are
host-executed and historically awkward under cross-compilation), rule sets, and Swift
modules for the other 72 locales — all 76 compile to `.decoy`, but only four are
embedded.

Known gaps, blocked rather than unscheduled: given-name frequencies (ssa.gov refuses
non-interactive requests), Dutch vocabulary (OpenTaal publishes no immutable artifact),
postcodes and vehicle makes (no pinnable source), and streets and non-English person
names, which need the generative layer described in the strategy doc.

## Attribution

The corpus embeds data under CC BY 4.0, CC BY 3.0, the Princeton WordNet licence, MIT,
Apache-2.0, the Unicode licence and the Unlicense. Several of those require attribution
wherever the work is distributed.

**[NOTICE](NOTICE) carries it**, and is generated from the provenance records embedded in
the compiled corpus rather than maintained by hand — so it describes exactly what ships
and cannot drift:

```
swift run decoy-inspect --notice Corpus/binary > NOTICE
```

## License

Apache 2.0. © NerdMeNot. The corpus data is under the licences listed in
[NOTICE](NOTICE).
