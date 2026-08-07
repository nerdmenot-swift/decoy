# Decoy binary corpus format v2

The on-disk format for compiled locale data. Read by `Decoy`'s Foundation-free
reader; written by `decoy-compile-corpus`.

## Goals

- **No runtime JSON parsing.** Parsing 2.7 MB of JSON at first use is Fakery's
  performance problem; this format is loaded once and sliced.
- **No `Bundle.module` in the hot path.** Resource-bundle lookup is the most
  platform-fragile part of SPM and a large share of Fakery's trouble off macOS.
- **Byte-identical across platforms.** All integers are little-endian and read
  byte-wise, so there are no alignment or endianness assumptions to get wrong. Verified
  on arm64 macOS, x86-64 Linux and x86-64 Windows, which CI covers. A big-endian host
  should follow from the byte-wise reads, but no such target has ever run this — that is
  a property of the design rather than a tested result.
- **Extensible without re-cutting.** Unknown chunk kinds are skipped, so a reader
  built today tolerates a corpus containing chunks it does not understand.

All offsets are absolute byte positions from the start of the file unless stated
otherwise. All integers are unsigned little-endian.

---

## Header — 32 bytes at offset 0

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 8 | `magic` | ASCII `DECOYBIN` |
| 8 | 2 | `formatVersion` | Bumped only for reader-incompatible changes |
| 10 | 2 | `flags` | Reserved, must be 0 — rejected on load if not |
| 12 | 2 | `corpusMajor` | Changing an existing value bumps this |
| 14 | 2 | `corpusMinor` | Adding data bumps this |
| 16 | 2 | `corpusPatch` | |
| 18 | 2 | — | Reserved, must be 0 — rejected on load if not |
| 20 | 4 | `chunkCount` | |
| 24 | 8 | — | Reserved, must be 0 — rejected on load if not |

The corpus version is separate from the library version on purpose: `generate(seed:)`
is only reproducible with respect to a specific corpus, so users must be able to pin
it. See `corpus-strategy.md`.

A reader must reject a file whose `magic` does not match or whose `formatVersion` is
anything other than the one it implements — **including an older one**, since a v1
blob's chunks parse as plausible garbage under the v2 layout, and silently serving
wrong data is worse than refusing to load. Backward compatibility becomes worth
building once a version has actually shipped. A reader must **not** reject unknown
chunk kinds.

## Chunk directory — `chunkCount` entries of 24 bytes, at offset 32

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `kind` |
| 4 | 4 | `id` |
| 8 | 8 | `offset` |
| 16 | 8 | `length` |

### Chunk kinds

| Kind | Name | Status |
|---|---|---|
| 1 | String arena | required |
| 2 | String tables | required |
| 3 | Composite tables | required |
| 4 | Provenance | required |
| 5 | Index | required |
| 6 | Models | reserved — generative n-gram models |

Kind 6 is unimplemented but allocated. A reader skipping it today will not need a
format bump when models arrive; only a `corpusMinor` bump.

---

## Chunk 1 — String arena

Every distinct string in the corpus, stored once. Measured 21.2% redundancy across
the 76 faker-js locales, so deduplication here is worth roughly 40,000 strings.

```
u32                  count
u32                  checkpointInterval    // 16
u32                  checkpointCount       // ceil(count / checkpointInterval)
u32[checkpointCount] checkpoints           // byte offset, relative to `bytes`, of
                                           // the string at index i * interval
u8[]                 bytes                 // sequence of length-prefixed UTF-8
```

Each string is a length prefix followed by its UTF-8 bytes. A prefix below `0xFF` is
a single byte holding the length; `0xFF` escapes to a following `u32`.

Corpus strings average 10.6 bytes, so v1's fixed `u32` offset per string cost **38%
of the text it pointed at**. A one-byte length plus a checkpoint every 16 strings
costs about 1.25 bytes instead, at the price of a forward scan of at most 15 length
prefixes per lookup — cheap next to constructing the `String`.

To read string *i*: seek to `checkpoints[i / interval]`, skip `i % interval` strings
by their prefixes, then read the length and slice.

## Chunk 2 — String tables

```
u32                 tableCount
u64[tableCount + 1] tableOffsets   // relative to chunk data start

per table:
  u32 entryCount
  u32 flags        // bit 0: weights present
                   // bit 1: contiguous layout
                   // bit 2: run layout
  u32 sourceID     // index into the provenance chunk
  u32 extra        // contiguous: first arena index
                   // runs:       run count
                   // explicit:   unused

  then, by layout:
    contiguous  (nothing)
    runs        { u32 logicalStart; u32 arenaStart; u32 length } × extra
    explicit    u32[entryCount] arenaIndex

  u32[entryCount] weight    // present only if bit 0 is set
```

The builder interns in insertion order, so a table's strings occupy consecutive arena
slots wherever they were new. **Run encoding rather than a single contiguous flag is
load-bearing**: only ~6% of entries in `en` are repeats, but an all-or-nothing scheme
lets one repeat in a 2,240-entry table force all 2,240 indices to be written. Runs
took this chunk from 86 KB to 23 KB for `en`.

A reader binary-searches the runs on `logicalStart`; runs are written in ascending
logical order. The `explicit` layout is kept for tables so fragmented that runs would
cost more than one index per entry.

Weights are stored as raw integers exactly as the source provides them; the reader
normalises. faker-js already ships non-uniform weights (95, 99, 50, 49, 25, …) across
136 arrays, so this column is populated from day one, and it is the same column real
frequency data fills: `person.last_name.generic` in `en` carries US Census surname
counts, so a weighted draw reproduces the real Zipf distribution rather than a uniform
one.

## Chunk 3 — Composite tables

Rows of correlated fields, drawn together. A country is `(alpha2, alpha3, numeric)`;
storing three parallel lists and drawing independently generates countries that do not
exist. faker-js has 36 such arrays in 7 shapes.

```
u32                 tableCount
u64[tableCount + 1] tableOffsets

per table:
  u32                        fieldCount
  u32                        rowCount
  u32                        sourceID
  u32                        —              // reserved
  u32[fieldCount]            fieldNameArenaIndex
  u32[rowCount * fieldCount] arenaIndex     // row-major
```

## Chunk 4 — Provenance

Where each table's data came from. No other faker records this, and without it the
corpus cannot be audited, selectively excluded by license, or checked for staleness.

```
u32 sourceCount

per source:
  u32 idArenaIndex          // e.g. "faker-js"
  u32 licenseArenaIndex     // SPDX identifier, e.g. "MIT"
  u32 urlArenaIndex
  u32 versionArenaIndex     // upstream version, e.g. "10.5.0"
  u32 retrievedArenaIndex   // ISO 8601 date
  u32 —                     // reserved
```

Source 0 is reserved to mean "unattributed" so a table can always reference something.

## Chunk 5 — Index

Maps a dotted path — `person.first_name.female` — to the table holding it.

```
u32 entryCount

per entry, sorted ascending by keyHash:
  u64 keyHash        // FNV-1a over the UTF-8 path
  u32 keyArenaIndex
  u32 kind           // 0 = null, 1 = string table, 2 = composite, 3 = model
  u32 tableID
  u32 —              // reserved
```

Lookup binary-searches on `keyHash`, then confirms with a string comparison against
the arena, so a hash collision degrades to a miss rather than to wrong data. FNV-1a
rather than `Hasher` because Swift's is randomly seeded per process and would produce
a different ordering on every run.

`kind == 0` records a key the locale explicitly defines as null — Azerbaijani has no
name prefixes — which must block fallback to a parent locale rather than invite
English to fill the gap. Distinguishing "explicitly none" from "absent" is why this is
a stored kind rather than an omitted entry.

---

## Locale files and fallback

One blob per locale, compiled from the unmerged definitions. Fallback is resolved at
*lookup* time by walking the chain (`de_AT → de → en → base`) rather than at compile
time, so a locale's blob stays small and shared data is not duplicated 76 times.

A `kind == 0` entry stops the walk. A missing entry continues it.

---

## Validation on load

The reader checks, once, on construction:

- `magic` matches and `formatVersion` is exactly the implemented one
- every chunk's `offset + length` lies within the file
- the arena's `checkpointCount` agrees with `count` and `checkpointInterval`, and the
  checkpoints strictly increase — a non-increasing checkpoint could send a lookup
  scanning backwards indefinitely
- the index is sorted by `keyHash`, which `lookup` binary-searches: an unsorted index
  does not fail, it reports "no such path" for data that is present and lets the locale
  fall through to its parent, which is a silently wrong *value*

Anything else — an arena index out of range, a malformed table — is caught at access
time by bounds-checked reads rather than by a full upfront scan, so start-up cost stays
proportional to the header rather than to the corpus.
