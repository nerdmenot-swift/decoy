---
title: Invented things
description: Pubs, beers, board games, superheroes, technobabble — and the one rule that lets them exist.
---

Most of the corpus is sourced. Three namespaces are not, and the permission slip is a
single question:

> **Is there a fact of the matter that could be wrong?**

A list of real animals can be wrong, so it wants a source. A list of real bands is
somebody's trademark, so it wants a lawyer. But there is no fact of the matter about what
a fictional brewery is called — *The Nimble Jackal* is neither correct nor incorrect —
so composing one is not a claim about the world and cannot be in error.

```swift
var f = Faker(seed: 99, locale: DecoyLocaleEN.locale)

f.whimsy.pubName()        // "The Nimble Jackal"
f.beverage.beer()         // "Reef Lager"
f.sport.club()            // "Cairn Casuals"
f.whimsy.codename()       // "Project Signal"
f.whimsy.technobabble()   // "If we index the matrix, we can get to the back-end
                          //  driver through the solid-state port"
```

## What is in here

**`whimsy`** — pub names, band names, board games, project codenames, ship names, horse
names, paint colours, meeting rooms, Wi-Fi networks, conference talk titles, incident
excuses, superheroes, restaurants, invented dishes, invented peaks and stars, and
technobabble.

**`beverage`** — beers, wines, whiskies, cocktails, breweries, coffees, teas.

**`sport`** — clubs, venues, trophies; plus real disciplines, which are a category rather
than a claim.

## Two of them are not jokes

`system.error*` and `commerce.review*` are here to be used.

```swift
f.system.databaseError()
// "deadlock detected while waiting for ShareLock on transaction 47428"

f.commerce.review()
// "Does the job — the stitching is better than I expected, though the
//  instructions could be better."
```

Every application has an error column and every storefront has a review column. Both
normally get seeded with lorem, which tells you nothing about how the column behaves when
something 120 characters long carrying punctuation and a quoted identifier actually lands
in it. That shape is the whole value.

Reviews are weighted the way real ratings distribute — J-shaped, mostly positive with a
tail of very negative — because a fixture that splits evenly makes any dashboard built on
it look wrong.

## How big the space is

337 authored words and 73 patterns yield **257,484** distinct values across seventeen
generators.

| Generator | Distinct outputs |
|---|---|
| `whimsy.talkTitle()` | 69,833 |
| `beverage.beer()` | 63,880 |
| `whimsy.boardGame()` | 46,951 |
| `beverage.wine()` | 31,752 |
| `whimsy.codename()` | 6,526 |
| `whimsy.bandName()` | 6,084 |
| `sport.club()` | 3,974 |

Those are measured, not estimated: each generator was drawn five million times and the
distinct results counted, which for a space that size exhausts it rather than samples it.
An earlier arithmetic estimate was wrong for two of them, because multiplying pattern
slots double-counts collisions.

## The vocabulary is deliberately plain

Every adjective and noun is an ordinary English word a dictionary would carry. The
invention is in the assembly, not the vocabulary — which keeps the pools free of anything
to verify, and keeps the output printable, since a curated pool cannot produce a
combination a profanity filter would have to catch.

## It can still land on something real

`whimsy.horseName()` can produce *Northern Dancer*, which was a very famous racehorse.
Composition from ordinary English words will occasionally coincide with something that
exists.

That is a collision, not a claim — nothing in the corpus asserts the horse existed. It is
the same trade `location.city()` has always made, and the reason these generators are for
fixtures rather than for anything that must be provably fictional.
