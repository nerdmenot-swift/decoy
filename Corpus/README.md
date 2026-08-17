# The compiled corpus

`binary/<code>.decoy` is the corpus, one blob per locale, all 64 of them. It is committed.

That is a change. It was ignored for a long time as *"a build artifact, reproducible from
the adapters"*, which was true and stopped being enough.

## Why it is committed now

Reproducing it needs forty-nine upstreams to answer. Two already do not — `vendor/` exists
because one returns 403 to every non-interactive request and another answers HTTP 200 with
a rejection page — and that number only goes one way. A statistics office reorganises its
site, a GitHub repository is deleted, a ministry moves to a new open-data platform, and the
corpus becomes unbuildable from a clean checkout while remaining perfectly good data.

Committing it costs about 5.5 MB in the repository, because git stores it compressed and
the format is already dense. That is cheap for making the data permanent.

The build pipeline is now *optional* rather than load-bearing. It is how the corpus is
regenerated when a source is re-pinned; it is no longer how the corpus is obtained.

## What this does not change

Nothing about how the library is consumed. `DecoyLocaleEN` and its siblings are committed
Swift source with the blob embedded as base64, so an app that imports Decoy has never
touched the network and still does not. These files are for rebuilding, for the locales
that have no Swift module, and for anyone who wants to inspect the corpus with
`decoy-inspect` without building it first.

## Why not Parquet, or JSON, or a database

The format is a string arena, an offset table and typed chunks, described in
`docs/corpus-format.md`. It is built for one access pattern: resolve a dotted path, draw a
value, in constant time, with the whole thing memory-mappable and no allocation on the
draw. Parquet is columnar and built for analytical scans, and reading it would mean a
dependency — the first in a package whose argument is that a toolchain for keeping data
accountable should not depend on a package it cannot audit.

JSON was measured: the same data is 32 MB as the intermediate the compiler reads, against
13 MB here, and it has to be parsed into objects before anything can be drawn from it.

## Regenerating

```
swift run decoy-build-corpus
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
```

Then the derived files, all of which CI checks are current:

```
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary --emit-swift Sources --locales de,ja
swift run decoy-inspect --notice Corpus/binary --licenses LICENSES > NOTICE
swift run decoy-inspect --matrix Corpus/binary > docs/locale-support.md
swift run decoy-inspect --coverage Corpus/binary --write-gate Corpus/coverage-baseline.json
```

`coverage-baseline.json` is the gate: it records what each locale supplies itself, and a
build that drops below it fails. Regenerate it deliberately, and expect the diff to be
reviewed — a shrinking number there is a locale quietly losing its own data.
