---
title: Command-line tools
description: Inspecting, validating and compiling the corpus.
---

Six executables ship with the package. Three read and check a corpus, which exist because
"what data do we actually have" stopped being answerable by reading somebody else's
repository; three build one.

| | |
|---|---|
| `decoy-inspect` | read a compiled corpus: paths, coverage, provenance, NOTICE |
| `decoy-validate` | check a contribution before it lands |
| `decoy-compile-corpus` | intermediate JSON → binary blobs, and optionally Swift modules |
| `decoy-build-corpus` | pinned sources → intermediate JSON |
| `decoy-fetch` | refresh the snapshots of sources that answer a query |
| `decoy-assets` | redraw the brand assets from computed geometry |

None of them is needed to *use* Decoy — a locale module is committed Swift source. They are
here because the corpus is a build artifact and the tools that produce it should be as
inspectable as the data.

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
decoy-validate: 64 locales, 53 sources, 36 adapters

nothing to report.
```

## decoy-compile-corpus

Turns the adapter output into binary blobs, and optionally into Swift modules.

```
decoy-compile-corpus <in> <out> [--emit-swift <dir> --locales de,ja]
```

```
$ swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
corpus version  : 59.2.0
locales compiled: 64
binary out      : 13098 KB
```

`--emit-swift` writes a `DecoyLocale<CODE>` module: the blob as a base64 `StaticString`
decoded once at first access. Committed source, reviewable in a diff.

## Rebuilding from scratch

You do not have to. `Corpus/binary/` is committed — all 64 locales, about 5.5 MB — so a
checkout has the corpus already and `decoy-inspect` works immediately. Rebuilding is for
re-pinning a source, not for obtaining the data.

That changed deliberately. Reproducing the corpus needs fifty-one upstreams to answer, and
two of them already do not; a corpus that is perfectly good data should not become
unbuildable because a ministry reorganised its website.

When you do want to rebuild:

```
swift run decoy-build-corpus                                  # sources → JSON
swift run decoy-compile-corpus Tools/adapters/out Corpus/binary
```

The first step fetches every pinned artifact, verifies each against its SRI hash and
caches it. A cached copy is re-verified rather than trusted on later runs.

Three sources answer a query rather than publishing a file — Wikidata over SPARQL, and the
Norwegian and Slovenian statistics offices over PxWeb — so there is nothing to hash. They
are refreshed deliberately, as four snapshots, and their results committed:

```
swift run decoy-fetch all            # or: wikidata-names, wikidata-colours,
                                     #     wikidata-terms, statistics-names
```

`all` runs the ones that need nothing but a network. `korean-surnames` is named explicitly
because KOSIS answers only to a registered key, so it takes one along with the table
identifier from the table's own page URL:

```
KOSIS_API_KEY=… swift run decoy-fetch korean-surnames --table DT_XXXXXXX
```

Re-running and diffing is the check that replaces the hash, which is why the snapshots are
committed rather than regenerated by the build. The two Wikidata crawls resume from what is
already on disk; delete the file to force a full refresh.
