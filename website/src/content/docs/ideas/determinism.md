---
title: Determinism
description: What "the same seed" actually promises, and the two ways it can be broken.
---

Fixtures are only useful if they hold still. A test that passes today and fails tomorrow
because the data moved underneath it is worse than no test, and a screenshot diff against
regenerated data is noise.

Decoy's promise is narrow and worth stating exactly: **the same seed, the same corpus
version and the same call order produce the same values, on every machine and every
platform.**

## How it holds

**The RNG is a value type you own.** `Xoshiro256StarStar` is threaded through as `inout`
rather than reached for globally. There is no ambient seed to be set by one test and
observed by another, which also means the whole thing is `Sendable` under Swift 6 strict
concurrency without a lock.

**Nothing consults the clock.** `past()` and `future()` are relative to a fixed reference
instant, not to `now`. Anchoring to the system clock would mean seed 1337 producing
different fixtures tomorrow than today — reproducibility with an expiry date. Pass your
own anchor with `Faker(seed:reference:)` or `Forge.reference(_:)` when you want dates
around a particular moment.

**Nothing floats.** Every decision that picks a *value* — the generator, the weighted
draw, the calendar arithmetic — is integer work in a module that imports nothing. There
is no platform-dependent `Double` rounding anywhere in the path from seed to string.

**Rows are independent.** Row 400 is a function of `(seed, 400)`, not of rows 0 through
399 having been generated first.

```swift
let whole = users.generate(500, seed: 1337)
let slice = users.generate(rows: 400..<403, seed: 1337)
whole[400].name == slice[0].name   // true
```

That is what lets a large job split across tasks or resume after a failure — and it is
tested rather than asserted.

## The two ways it breaks

**You changed the call order.** A faker is a stream. Adding a draw in the middle shifts
everything after it. This is not a bug and cannot be designed away without making every
generator carry its own RNG, which costs more than it buys. If you need a value that
survives reordering, derive it from `faker.index` rather than drawing it.

**The corpus version changed.** Reproducibility is guaranteed *with respect to a corpus*,
and the corpus is a build artifact that gets rebuilt when its sources do.

The version lives in one place and everything reads it:

```
Tools/adapters/corpus-version.json
```

The rule is simple and enforced by review rather than by a tool: **adding data is a minor
bump; changing or removing an existing value is a major one.** A major bump means every
fixture anyone has already generated will differ. That is why the removal of a single
mis-transcribed athlete's name — one entry, in one list — took the corpus from 57.2.0 to
58.0.0. It was a typo, and fixing it was still a breaking change.

## What this is not

It is not a guarantee across library versions independent of the corpus. A change to how
`fullName()` composes is a behavioural change even if the data is identical; those are
called out in the release notes.

If you need fixtures pinned beyond any of this, serialise the generated rows and commit
them. Decoy makes regenerating cheap; it does not make regeneration free of consequence.
