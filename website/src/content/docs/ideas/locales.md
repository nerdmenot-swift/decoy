---
title: Locales and fallback
description: Sixty-four locales, what each supplies itself, and how to find out before you commit.
---

A locale is a chain, not a file. `de_AT` resolves through `de`, then `en`, then `base`,
and the walk happens at *lookup* time rather than being merged at compile time — so
`de_AT` need not carry a copy of everything `de` already has.

```
de_AT → de → en → base
```

`base` is the language-neutral tail: country codes, time zones, media types, emoji.
Things with no Japanese answer to `image/png`.

## The failure this is all guarding against

A locale that supplies none of its own names still *resolves* them, through the chain,
from English. You get Tamil postcodes attached to people called Jennifer Williams — and
nothing at the call site says so. You find out from a screenshot.

Twelve locales were removed rather than shipped in that state. Tamil carried 15,612
native values — month names, cities, postcodes, phone formats — and still could not name
a person. The criterion is names, not volume, and it is enforced by a test rather than
remembered.

## Find out before you commit

```
swift run decoy-inspect --coverage Corpus/binary
```

```
locale          own%   own    anim bran colo comm comp date fina food loca medi natu pers phon
de               62%     58      .  100   83   22  100   27    .   90   60  100   43  100  100
ja               46%     44      .  100    .   33  100    9    .   80   30    .   57   60  100
```

`own%` is the share of language-bearing paths the locale defines **itself**, not what it
can resolve. Median across non-English locales is 37%; thirteen sit below 30%.

The [locale matrix](/reference/locale-matrix/) is the same information per data type, and
is the thing to read before picking a locale for a demo.

## Assert on it in your own tests

If your product ships Tamil, you probably want to know the day its coverage drops:

```swift
#expect(try DecoyLocaleJA.locale.nativeCoverage > 0.3)

if let warning = locale.fallbackWarning() {
    print(warning)   // names the locale, the percentage, and where to look
}
```

## Deliberately empty is not missing

A locale that declares a field empty **stops the walk**. Azerbaijani has no name
prefixes; continuing to English would put "Dr." on Azeri records. That is a fact about
the language, not a gap, so it yields an empty string rather than trapping or falling
through.

Missing is different, and traps with a message naming the path — because that is a build
error somebody can fix.

## What is English by design

A growing share of the corpus is English-only and always will be: invented pub names,
marketing adjectives, job descriptors, department names. No registry publishes them in
any language, and writing them in a language the author cannot check would be inventing
rather than sourcing.

Those 125 paths are excluded from the coverage percentage. Counting them would measure
how much invention has been added rather than how local a locale is — Japanese once read
28% while being 100% native for colours and dates, 80% for location and 60% for person,
which made the warning false about every field a Japanese caller actually generates.

They still appear in the matrix, in the `Invented names` and `Real-world lists` columns,
because a caller reaching for an animal name really does get English.

## Adding a locale to your build

Sixty-four compile. Three ship as modules. To get another:

```
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary \
  --emit-swift Sources --locales pt_BR
```

Then add the target and product to `Package.swift`. The generated module is committed
Swift source, so it is reviewable in a diff like anything else.
