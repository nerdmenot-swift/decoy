---
title: Locales
description: Picking one, knowing what it actually covers, and adding more.
---

```swift
import DecoyLocaleDE

var faker = Faker(seed: 2024, locale: DecoyLocaleDE.locale)
faker.person.fullName()         // "Benning Blaha"
faker.location.streetAddress()  // "Grubergasse 17"
faker.commerce.productName()    // "Praktische Sofas aus Leder"
```

Three ship as modules today — `DecoyLocaleEN`, `DecoyLocaleDE`, `DecoyLocaleJA`. Sixty-four
compile, and more are added over time.

## Check coverage before you commit

A locale is a chain: `de_AT → de → en → base`. Anything it does not carry itself, it
inherits — which usually means English.

```
swift run decoy-inspect --coverage Corpus/binary
```

```
locale          own%   own
de               62%     58
ja               46%     44
```

`own%` is the share of language-bearing fields the locale defines **itself**. The
[locale matrix](/reference/locale-matrix/) breaks the same figure down per data type, and
is the thing to read before picking a locale for a demo.

Assert on it in your own suite if a language matters to your product:

```swift
#expect(try DecoyLocaleJA.locale.nativeCoverage > 0.3)

if let warning = locale.fallbackWarning() {
    print(warning)   // names the locale, the percentage, and where to look
}
```

## What falls back, and how you can tell

Three locales carry their own surnames and no given names — `zh_TW`, `id_ID` and `yo_NG`.
Rather than pair a Han surname with an English given name, `fullName()` composes the whole
name from one language:

```swift
var f = Faker(seed: 11, locale: taiwaneseLocale)
f.person.fullName()   // "Brenda Beil"  — obviously a fallback
f.person.lastName()   // "黃"            — still native
```

A caller asking only for a surname is not building anything self-contradictory, so it keeps
the native one. It is the *composition* that has to agree with itself.

Some fields are English everywhere by design: invented pub names, marketing adjectives,
job descriptors. No registry publishes them in any language.

## Empty is not missing

A locale that declares a field empty **stops** the fallback walk. Azerbaijani has no name
prefixes, so `person.prefix()` returns `""` rather than "Dr." — a fact about the language,
not a gap.

Missing is different and traps with the path named, because that is a build error.

## Adding one to your build

```
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary \
  --emit-swift Sources --locales pt_BR
```

Then add the target and product to `Package.swift`. The generated module is committed
Swift source, reviewable in a diff.
