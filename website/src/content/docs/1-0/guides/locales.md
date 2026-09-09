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

Three ship as modules today — `DecoyLocaleEN`, `DecoyLocaleDE`, `DecoyLocaleJA`. Sixty-five
compile, and more are added over time.

## Check coverage before you commit

A locale is a chain: `de_AT → de → en → base`. Anything it does not carry itself, it
inherits — which usually means English.

```
swift run decoy-inspect --coverage Corpus/binary
```

```
locale          own%   own
de               64%     60
ja               47%     45
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

One locale has half a name of its own: `en_GB` carries given names from the ONS and no
surnames. Every other locale that supplies names supplies both halves — `ko`, `es`,
`zh_TW`, `bn_BD`, `cy`, `mk`, `id_ID` and `yo_NG` each had only one half at various points
and now have both, so a composed name in those languages is entirely that language.

Where a locale does have only half, `fullName()` composes the whole name from one language
rather than pairing a native surname with an English given name. `en_GB` is the deliberate
exception: borrowing English surnames is not a chimera when the locale is English, so it
keeps them, and only locales whose language differs from the fallback's are narrowed.

A caller asking only for a surname is not building anything self-contradictory, so it keeps
the native one. It is the *composition* that has to agree with itself.

That rule is why the list above shrank to one: the fix for a half-named locale was always
surname data rather than a cleverer rule, and `es` now has 27,661 surnames from the INE
census, `ko` its own, and so on down the list.

Some fields are English everywhere by design: invented pub names, marketing adjectives,
job descriptors. No registry publishes them in any language.

## Empty is not missing

A locale that declares a field empty **stops** the fallback walk. Azerbaijani has no name
prefixes, so `person.prefix()` returns `""` rather than "Dr." — a fact about the language,
not a gap.

Missing is different and traps with the path named, because that is a build error.

## Using a locale that has no module

Three ship as compiled-in Swift modules — `DecoyLocaleEN`, `DecoyLocaleDE`, `DecoyLocaleJA`.
The corpus holds sixty-five. For the rest, add the `DecoyLocales` product and ask for one by
code:

```swift
import Decoy
import DecoyLocales

let fr = try DecoyLocales.locale("fr")
var faker = Faker(seed: 1337, locale: fr)
faker.person.fullName()   // "Félix Tillet"
```

`DecoyLocales.available` lists all sixty-five, plus `base`, and the fallback chain is resolved for you
from the same rule the corpus was built with — `de_AT` through `de` through `en` to `base`.
An unknown code throws rather than resolving: `"pt"` is not a locale here, and letting it
quietly become English under a Portuguese name is the failure this library exists to make
visible.

Prefer a module when your locale has one. It costs nothing at run time, cannot fail, and
needs no `try`. `DecoyLocales` carries every blob as a resource — about 14 MB — which is why
it is a separate product rather than part of `Decoy`: nobody should pay for sixty-five
locales to get German.

## Compiling one into your own build

If you want a locale as a module rather than a resource:

```
swift run decoy-compile-corpus Corpus/binary Corpus/binary \
  --emit-swift Sources --locales pt_BR
```

Then add the target and product to `Package.swift`. The generated module is committed
Swift source, reviewable in a diff. This is a change to *Decoy's* manifest, so it suits a
fork or a vendored copy; `DecoyLocales` is the answer when you are consuming the package
normally.
