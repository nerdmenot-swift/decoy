---
title: Command-line tools
description: Inspecting, validating and compiling the corpus.
---

Three executables ship with the package. They exist because "what data do we actually
have" stopped being answerable by reading somebody else's repository.

## decoy-inspect

Reads compiled corpora.

```
decoy-inspect <file.decoy>                      summary
decoy-inspect <file.decoy> --paths [substring]  list paths, with kind and size
decoy-inspect <file.decoy> --path <path>        the values at one path
decoy-inspect --coverage <dir> [--against en]   native coverage per locale
decoy-inspect --coverage <dir> --gate <file>    fail if coverage regressed
decoy-inspect --coverage <dir> --write-gate <f> record the current state as baseline
decoy-inspect --matrix <dir>                    locale × data type support, as Markdown
decoy-inspect --notice <dir> --licenses <dir>   attribution for everything shipped
```

A summary tells you what is in a blob:

```
$ swift run decoy-inspect Corpus/binary/en.decoy

file           : en.decoy
corpus version : 58.0.0
paths          : 270
values         : 117217
distinct strings: 88323
kinds          : composite 7, model 3, strings 260
```

One path tells you where it came from:

```
$ swift run decoy-inspect Corpus/binary/en.decoy --path person.last_name.generic

source: us-census-surnames (public-domain)
24889 values, weighted
```

Every combination that cannot be honoured is refused rather than silently resolved by
argument order. `--notice` with `--coverage`, `--gate` with `--write-gate`, `--against`
under either gate mode — all fail with an explanation. A tool whose whole job is auditing
should never report success having done something other than what was asked.

## decoy-validate

Checks a contribution before it lands.

```
decoy-validate [--strict]

  --corpus <dir>       compiled blobs          (default Corpus/binary)
  --sources <dir>      source descriptors      (default Tools/adapters/sources)
  --adapters <dir>     adapter programs        (default Tools/adapters/adapters)
  --licenses <dir>     committed licence texts (default LICENSES)
  --generators <dir>   Swift generator sources (default Sources/Decoy)
  --manifest <file>    adapter output manifest (default Tools/adapters/out/manifest.json)
```

It finds paths nothing can draw, template tokens that expand to nothing, generators
calling paths no locale answers, licence metadata that contradicts the text beside it, and
sources about to ship without attribution.

`--strict` treats warnings as failures, and CI uses it, because the report is clean. A
check that always prints ten warnings has no signal in it — the eleventh, the one somebody
just introduced, is invisible in the noise.

```
$ swift run decoy-validate --strict
decoy-validate: 64 locales, 49 sources, 24 adapters

nothing to report.
```

## decoy-compile-corpus

Turns the adapter output into binary blobs, and optionally into Swift modules.

```
decoy-compile-corpus <in> <out> [--emit-swift <dir> --locales de,ja]
```

```
$ swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
corpus version  : 58.0.0
locales compiled: 64
binary out      : 13099 KB
```

`--emit-swift` writes a `DecoyLocale<CODE>` module: the blob as a base64 `StaticString`
decoded once at first access. Committed source, reviewable in a diff.

## Rebuilding from scratch

```
node Tools/adapters/run.mjs                                   # sources → JSON
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
```

The first step fetches every pinned artifact, verifies each against its SRI hash and
caches it. A cached copy is re-verified rather than trusted on later runs.
