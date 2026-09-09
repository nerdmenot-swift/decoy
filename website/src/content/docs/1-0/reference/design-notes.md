---
title: Design notes
description: The decisions behind the corpus, for anyone who wants them.
---

Short version, for people who care. Nothing here is needed to use the library.

## Every value knows where it came from

The corpus is a build artifact. Nothing is hand-edited: each string is derived from a
citable source by a reproducible pipeline and carries its origin inside the compiled
blob.

```
swift run decoy-inspect Corpus/binary/en.decoy --path person.last_name.generic
# source: us-census-surnames (public-domain), 24889 values, weighted
```

`NOTICE` is generated from those records, so it credits what actually shipped. CI
regenerates it and fails on a diff.

## Sources are pinned and re-verified

Every artifact has an SRI hash. A cached copy is re-verified rather than trusted — a
tampered cache would otherwise produce a corpus that passes every check on the machine
that built it and nowhere else.

## Some data is invented, and it is labelled

Three namespaces compose values rather than sourcing them, allowed by one test: *is there
a fact of the matter that could be wrong?* There is none for an invented pub name, so
composing one is not a claim. Those pages carry a note.

Seven more namespaces carry real things — animals, cheeses, mountains, composers —
written from general knowledge because no suitably licensed list exists. They are pinned
to nothing and hash-verified against nothing, and their pages say so. What they get
instead is a duplicate guard, a near-duplicate scan and a read-through.

## What was declined

Rosters of real people: election registers and director filings are open and full of
names, and every one identifies a private individual. A register counts how many people
hold a name; a roster names them.

Corpora that arrive with a permissive licence file but no provenance. Of those surveyed,
one Apache-2.0 name set was built from a 533-million-account breach, and one CC0 dataset
was Wikipedia-derived, which is share-alike laundering.

Share-alike data of any kind, since the package must stay Apache-2.0.

Twelve locales were removed rather than shipped nameless — each carried no personal names
of its own, so every person it generated was English wearing its postcode. The criterion
is names, not volume: one of them shipped 15,612 native values and still could not name a
person.

## Why the corpus is binary

One blob per locale: a deduplicated string arena, an offset table and a sorted index that
lookups binary-search. Nothing is parsed at load, and it avoids `Bundle.module`, the most
platform-fragile corner of SwiftPM.

Weights and composite rows live in the data rather than the reader, which is what lets a
country code return a triple that actually exists.
