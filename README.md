# Decoy

A seeded fake-data generator for Swift — for seeding databases and building test
fixtures.

Reproducible by construction, portable across macOS, Linux, and Windows.

> **Status: 1.0 in progress.** Nothing is tagged. The `v1.0.0` tag that briefly existed
> has been withdrawn, deliberately and while nobody depended on it, so that the shape of
> the release can be settled before anyone has to live with it. `from: "1.0.0"` will not
> resolve until it is cut again.
>
> If you resolved that tag in the window it existed, SwiftPM has pinned it to a commit that
> no longer exists and will refuse the new one with *"does not match previously recorded
> value"*. Clearing the package caches does not help; delete
> `~/Library/org.swift.swiftpm/security/fingerprints/decoy-*.json`.
>
> The corpus versions *separately*, and it will keep moving — it is at 62.0.0, and adding
> data to a locale bumps it. A corpus bump changes what a given seed draws, so pin the
> corpus version, not just the package version, if you are keeping generated fixtures.
> [CHANGELOG.md](CHANGELOG.md) explains which of the two numbers answers which worry.
>
> Every locale composes a full name in its own language — fifty-four of them, with none falling
> through to English. That is asserted rather than claimed: `NameCoherenceTests` derives the
> two categories from the corpus and fails if any locale answers in a language that is not
> its own. Individual fields still vary, and the
> [locale support matrix](docs/locale-support.md) publishes exactly which.

## Why

Fixtures are only useful if they hold still, and only trustworthy if you can say where
they came from. Decoy is built on three commitments:

- **Reproducible by construction.** The RNG is a value type you supply and thread
  through. Seed 1337 gives the same rows on every machine, every run, until the corpus
  version changes — which it does loudly.
- **Sourced, not invented.** Every string is derived from a citable primary source by a
  reproducible pipeline and carries its origin with it. Where no source exists, the
  corpus records that rather than guessing.
- **Deep outside English.** Sixty-five locales, each measured for how much of its own
  language it actually supplies, with the gaps published rather than hidden.

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
  different fixtures tomorrow than today, which is a reproducibility hole.
- **No runtime JSON parsing.** The corpus compiles to a compact binary format (string
  arena + offset table) loaded once and sliced. Notably this avoids `Bundle.module`,
  the most platform-fragile part of SPM.
- **Every string carries its origin.** The corpus records which source and licence each
  path came from, so `decoy-inspect` can answer "where did this come from" and generate
  attribution from what actually shipped — which is what makes the corpus auditable
  and licensable with confidence.
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
locale means importing `DecoyLocaleDE` costs you `de`, `en` and `base` — not all 64.

**Always import a locale.** `Faker`'s default corpus is a ten-path smoke-test stub, so
most generators trap against it; `base` is language-neutral data every chain ends at and
is not importable on its own for the same reason.

Referential integrity falls out of closures capturing already-generated arrays. No
"World" abstraction, no inheritance gymnastics.

Large seed jobs split across tasks and reassemble into exactly the sequential result,
because each row's values are derived from `(seed, rowIndex)` alone:

```swift
let events = Forge<Event>("event") { Event() }
    .rule(\.id)   { $0.uuidV7Value() }
    .rule(\.kind) { $0.pick(["click", "view", "purchase"]) }

let chunks = await withTaskGroup(of: (Int, [Event]).self) { group in
    for start in stride(from: 0, to: 1_000_000, by: 50_000) {
        group.addTask { (start, events.generate(rows: start..<start + 50_000, seed: 1337)) }
    }
    return await group.reduce(into: [Int: [Event]]()) { $0[$1.0] = $1.1 }
}
let all = chunks.keys.sorted().flatMap { chunks[$0]! }
```

Note the forge here has no `unique` rule. Chunks cannot see each other's values, so
`generate(rows:seed:)` refuses a forge that has one rather than emitting duplicates —
uniqueness and independent chunks cannot both hold.

## What changed, and whether it moves your fixtures

[CHANGELOG.md](CHANGELOG.md). Decoy carries two version numbers — the corpus version is the
fixture-stability contract, the package version covers the library — and generated output
can move without the corpus moving. Anything that alters drawn values is marked.

## Platforms

macOS, Linux, and Windows are all first-class targets; iOS/tvOS/watchOS/visionOS are
supported for app developers. Each of the three builds, compiles a corpus and runs the
full suite in its own CI job — Linux natively in a `swift:6.3` container rather than by
cross-compiling. Windows is best-effort: a failure there should prompt a portability fix
rather than block a release.

Running on three platforms catches a divergence once it reaches a test. Some do not:
`URLSession` lives in `FoundationNetworking` off Apple platforms, and forgetting the
conditional import compiles cleanly on a Mac. So `PortabilityLintTests` scans the sources
for the calls that are known to mean something else elsewhere — Foundation's newline
search, which splits a CRLF file differently on Linux; `isExecutableFile` and `PATH`,
which read wrong on Windows; raw `Process`; Apple-only imports. Each rule carries what
actually goes wrong and what to use instead, and each has a per-file allowlist so a
deliberate use is recorded with its reason rather than argued with twice.

The shipped library sidesteps the question entirely: nothing under `Sources/Decoy`
imports Foundation, and code that stays in the standard library is portable by
construction. Every portability bug this project has had was in the build tooling.

## The corpus is derived, not written

No data is hand-edited. `Tools/adapters/` holds *programs* that derive the corpus from
fifty-four sources — forty-nine pinned upstreams fetched by URL and verified against an
integrity hash, three queried and their answers committed, and two written here — each
recorded in the corpus with its licence:

```
Tools/adapters/
  sources/<id>.json     pinned descriptor: URL, integrity hash, licence, version
  locales.json          the locale roster
  corpus-version.json   the corpus version, declared once
  data/*.json           snapshots of the sources that answer a query, not a URL
  parity/<id>.json      what each adapter last emitted, diffed on every run

Sources/DecoyAdapterKit/
  Adapters/<Name>.swift the transform, one per upstream
  ArtifactStore.swift   fetch, verify, cache, extract
  Queries/              the fetchers behind `decoy-fetch`, run by hand
```

The compiled result **is** committed, under `Corpus/binary/` — see the note there. It was
not, on the grounds that it is reproducible from the adapters, which was true and stopped
being enough: reproducing it needs fifty-one upstreams to answer and two already do not.
Rebuild it with `swift run decoy-build-corpus`, then `swift run decoy-compile-corpus`.

The package has no dependencies — no `.package(…)` entries, and the hashing, the archive
readers, the n-gram trainer and the rest are written out rather than pulled in, because a
toolchain whose job is to keep shipped data accountable should not itself depend on a
package it cannot audit. The build does shell out to `tar`, `unzip` and `gzip`, which macOS
has already and Debian needs `xz-utils` and `unzip` for; hand-rolling zip and DEFLATE is a
great deal of risk for a build step.

Countries, languages, currencies, time zones, media types, subdivisions, cities,
programming languages, elements, units and English surnames come from registries — CLDR,
IANA, the ISO 4217 registry, GeoNames, Linguist, PubChem, the US Census. Personal names come
from twelve national civil registries; streets are composed from each language's own
vocabulary; the rest is either authored here or recorded as unavailable.

`decoy-inspect` audits any of it — every path, what a locale defines itself, and which
source and licence covers each field:

```
swift run decoy-inspect Corpus/binary/en.decoy            # summary and provenance
swift run decoy-inspect Corpus/binary/en.decoy --paths    # every path
swift run decoy-inspect --coverage Corpus/binary          # native coverage per locale
swift run decoy-validate                                 # check a contribution
swift run decoy-inspect --notice Corpus/binary \
  --licenses LICENSES                                     # attribution, generated
```

See [docs/corpus-strategy.md](docs/corpus-strategy.md) for why, and
[docs/corpus-format.md](docs/corpus-format.md) for the binary layout.

## Releases

Tagging is the release — SwiftPM resolves `.package(url:from:)` straight from a git tag —
so a tag is never moved once it exists. Cutting one is a single manual workflow, and the
package version and the corpus version mean different things:
[docs/releasing.md](docs/releasing.md).

## v1 scope

- [x] Multi-platform package skeleton, Foundation-free core, `swiftLanguageMode(.v6)`
- [x] Seeded RNG (`Xoshiro256**` behind `RandomNumberGenerator`)
- [x] `Forge<T>` with rules, traits, streaming, child fan-out and unique constraints
- [x] Adapter pipeline: 54 sources — 49 integrity-verified, 3 queried, 2 authored — provenance per path
- [x] [Locale support matrix](docs/locale-support.md) — which fields each of the 65 locales
      supplies itself, and which fall through to English. Generated from the corpus and
      checked in CI, so it cannot describe a corpus that is no longer shipping.
- [x] JSON → binary corpus format + Swift reader
- [x] 319 generators across 29 namespaces, including dates, seeded UUIDs and checksummed crypto addresses
- [x] All 66 locales compile; `en`, `de`, `ja` ship as importable Swift modules
- [x] `decoy-inspect`: enumeration, coverage, generated attribution
- [x] CI run on every push — macOS, Linux and Windows each build, compile a corpus and
      run the full suite; `PortabilityLintTests` fails the build on the calls known to
      mean something else on another platform

Deferred: strict-mode rule checking (needs a macro, and macro plugins are
host-executed and historically awkward under cross-compilation) and rule sets.

## Embedding another locale

All 64 compile to `.decoy`; four ship as Swift modules. The rest are emitted on request,
in two steps and in this order:

```
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary \
  --emit-swift Sources --locales de_AT
```

It writes `Sources/DecoyLocaleDE_AT/` and then prints the exact line to add to the
`locales` array in `Package.swift`:

```
    ("DE_AT", ["DE", "EN", "Base"]),
```

Add it, and `import DecoyLocaleDE_AT` works.

**Emit before declaring, not the other way round.** SwiftPM will not build anything —
including the compiler that writes the directory — while a declared target has no sources,
so adding the line first leaves you unable to run the command that would fix it.

The array order is the fallback chain, most specific first. `LocaleModuleTests` checks it
against the locale roster, because getting it wrong is silent: a module with a short chain
resolves fewer paths and reads as missing data rather than as a manifest error.

**Why not embed all 64?** Not build time — measured, and SwiftPM compiles only the locale
targets a consumer actually depends on: an app importing `DecoyLocaleDE` builds `DE`, `EN`
and `Base` and never touches the other 61. The cost is the checkout. SwiftPM clones the
whole repository, so ~14 MB of base64 string literals would land in every consumer's
`.build/checkouts` whether or not a single one is compiled, and in every CI cache that
carries it.

Known gaps, blocked rather than unscheduled: given-name frequencies (ssa.gov refuses
non-interactive requests), vocabulary for German, French, Dutch, Portuguese and five
others (their wordnets are CC BY-SA or CeCILL, and share-alike does not compose with
Apache-2.0), national postcode formats outside the US and Canada, vehicle makes (no
pinnable source), and streets and non-English person names, which need the generative
layer described in the strategy doc.

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
