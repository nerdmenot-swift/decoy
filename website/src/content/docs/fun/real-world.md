---
title: Real-world lists
description: Animals, food, mountains, books, composers — and why these took longest to allow.
---

Seven namespaces name real things.

```swift
var f = Faker(seed: 99, locale: DecoyLocaleEN.locale)

f.animal.animal()             // "Skunk"
f.animal.dogBreed()           // "Setter"
f.food.cheese()               // "Brie"
f.food.dish()                 // "Coq au Vin"
f.nature.mountain()           // "Everest"
f.nature.gemstone()           // "Imperial Topaz"
f.notable.scientist()         // "Charles Babbage"
f.institution.university()    // "University of Barcelona"
f.media.bookTitle()           // "The Count of Monte Cristo"
```

**`animal`** — animals, birds, reptiles, fish, insects, farm animals, dog / cat / horse
breeds, pet names.
**`food`** — fruit, vegetables, herbs and spices, cheeses, dishes, desserts, grains,
nuts, seafood, breads.
**`nature`** — mountains, rivers, lakes, islands, deserts, trees, flowers, gemstones,
weather.
**`media`** — book titles and authors, film and song titles, genres, instruments, art
movements.
**`notable`** — philosophers, scientists, mathematicians, inventors, composers, artists,
architects, explorers, and a short list of living public figures.
**`brand`** — cameras, phones, watches, fashion, sportswear, motorcycles, appliances.
**`institution`** — universities, football clubs, museums, newspapers, orchestras.

## Why these were refused for months

The rule that admits the [invented namespaces](/fun/invented/) is *is there a fact of the
matter that could be wrong?* For animals the answer is plainly yes. So they wanted a
citable source — and no suitable one exists. Wikidata's taxonomy is not a colloquial
animal list, Wikipedia's categories are share-alike and unusable, and the open food
databases are product catalogues rather than ingredient lists.

The reasoning was sound and the conclusion was wrong. It treated *cannot be mechanically
verified* as *cannot be shipped*, and a fixture library that will not tell you an otter is
an animal is not being rigorous — it is being useless.

## What replaces the hash

These live under their own source, `common-knowledge`, whose descriptor states plainly
that accuracy is **high and unverified**: written from general knowledge, with no upstream
to pin and nothing for the pipeline to re-check. Every other source in the corpus is
fetched from a pinned URL and verified against an integrity hash. This one cannot be.

What it gets instead is scrutiny of a different kind.

A duplicate guard runs at build time — and was itself wrong on the first attempt, because
`Set.add` returns the Set and is always truthy, so the check could never fire. It now
carries a self-test. Rewritten, it found no exact duplicates.

But a typo makes a *distinct* string and slips straight past an equality check, so a
Levenshtein scan over the proper-noun lists went next. It surfaced six candidates, five of
them genuinely distinct things — Afrobeat and Afrobeats, Internazionale and Internacional,
*Die Zeit* and *Die Welt* — and one real typo: `Jesse Ownes` sitting beside `Jesse Owens`.

Reading found three more no scanner would catch: `Rudolf Hertz` for Heinrich Hertz, the
same film listed as both *Bicycle Thieves* and *The Bicycle Thief*, and mathematicians
mixing `Blaise Pascal` with a bare `Pascal`.

That is the standard on offer: **not verified, but looked at.** An error here is an error
rather than a licence problem, and it is fixable in a diff.

## Trademarks and living people

Camera makers, universities, football clubs and museums appear by name. Naming a trademark
to refer to the thing it names is nominative use, and is not what trademark law restricts —
the restriction is on using a mark to suggest endorsement or cause confusion in trade.
Decoy is not affiliated with any organisation named.

`notable.actor()`, `notable.musician()` and `notable.athlete()` name people who are alive.
The project refuses rosters of real people, so the distinction is worth stating: those
rosters identify private individuals, listed with a constituency or an employer. These
name people already universally known and pair them with nothing — no address, no date of
birth — so no generated record resembles a record *about* the person named. The lists are
short for that reason; the volume is in the historical figures.

Anyone named who would rather not be may have the entry removed on request.
