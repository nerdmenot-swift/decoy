---
title: Corpus format
description: One binary blob per locale — a string arena, an offset table, and typed chunks.
---

Format v2. One blob per locale rather than one file for everything: 64 blobs, 13 MB in
total, and you link only the chain you use.

## Why not JSON

A fixture library that parses JSON at startup pays for every string it will never draw,
and does it on the main thread of somebody's test suite. The binary format is read by
slicing: the file is loaded once, the index is binary-searched, and a value is a range
into a byte buffer.

It also avoids `Bundle.module` entirely, which is the most platform-fragile corner of
SwiftPM and a large share of what makes resource-loading libraries fail off macOS.

## Layout

```
header          magic, version, chunk offsets
string arena    every distinct string, once, back to back
offset table    (start, length) per string
path index      sorted path → entry, binary-searched at lookup
chunks          typed: string tables, composites, n-gram models
provenance      source id, licence, version, retrieval date, per table
```

**The arena is deduplicated across the whole blob.** Cross-locale duplication is
substantial — a regional variant repeats most of its parent's data — and deduplicating
strings is worth roughly a fifth of the total size.

**Weights and composites live in the data, not in the reader.** A weighted list carries
its weights; an ISO 3166 triple is one composite row with three fields. That is what lets
`countryCode()` return a country that exists rather than three independent draws that
never coexisted.

## Entry kinds

| Kind | Holds |
|---|---|
| `strings` | a list, optionally weighted |
| `composite` | rows of named fields, drawn together |
| `model` | a character-level n-gram model |
| `explicitlyEmpty` | "this locale has no such thing" |

`explicitlyEmpty` is the one that carries meaning rather than data. Azerbaijani declares
`person.prefix` empty, and the chain walk **stops** there instead of continuing to
English — because continuing would put "Dr." on Azeri records. Missing and empty are
different states and the format keeps them apart.

## Models

`novelSurname()` draws from a character-level n-gram model trained on the same register
lists the plain generator uses. The model ships in the blob; training happens in the
pipeline, not at runtime.

It is off by default. The registers carry real population frequencies, and swapping them
for a model silently would throw away the realism they were sourced for — so you ask for
it explicitly with `Forge.novelNames()` or `Faker(novelNames: true)`.

## Provenance

Each table references a source record: id, licence, version, retrieval date. That is what
`decoy-inspect --path` reads, and what `--notice` assembles attribution from — so the
`NOTICE` file describes exactly what shipped rather than what someone believed shipped.

## Versioning

The corpus version is declared once, in `Tools/adapters/corpus-version.json`, and read by
the pipeline, the compiler and the tests. Before it existed the number lived in a
compiler default, whichever flag you happened to type, and two test files — so CI built
1.0.0 while the tests asserted 11.0.0.

Adding data is a minor bump. Changing or removing an existing value is a **major** bump,
because it silently changes every fixture anyone has already generated.
