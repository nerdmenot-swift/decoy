---
title: Provenance
description: Every value can name the source it came from, the licence, and the day.
---

Most fake-data libraries are two decades of contributor goodwill: lists typed into files
by people who are long gone, with no record of where anything came from. That is not a
criticism of the people involved. It is an accurate description of a model that cannot
be audited, cannot be licensed with confidence, and cannot be improved systematically.

Decoy inverts it:

> **The corpus is a build artifact.** No one hand-edits data. Every string is derived
> from a citable primary source by a reproducible pipeline, and carries its origin with
> it.

Everything else here follows from that sentence.

## Ask any value where it came from

```
swift run decoy-inspect Corpus/binary/en.decoy --path person.last_name.generic
```

```
source: us-census-surnames (public-domain)
24889 values, weighted
```

The provenance travels *inside* the compiled corpus, in its own chunk, keyed per path.
It is not a README that has to be kept in step by hand — it is read out of the same bytes
your fixtures are drawn from.

## Adapters, not data files

`Tools/adapters/` holds programs, not strings:

```
sources/<id>.json      pinned descriptor: URL, integrity hash, licence, version
adapters/<id>.mjs      the transform
lib/sources.mjs        fetch, verify, cache, extract
locales.json           the locale roster
run.mjs                orchestrator → out/locales/*.json + manifest.json
```

Every artifact is pinned to an SRI integrity hash. A cached copy is **re-verified rather
than trusted**, because a tampered cache would otherwise produce a corpus that passes
every check on the machine that built it and nowhere else. A mismatch aborts with the
expected and actual digests and instructions to re-pin.

There is no package manifest and nothing to install — plain `.mjs` files run by Node.
A toolchain whose job is keeping shipped data accountable should not itself depend on a
tree of packages it cannot audit.

## Attribution generated from what shipped

```
swift run decoy-inspect --notice Corpus/binary --licenses LICENSES > NOTICE
```

`NOTICE` is produced from the provenance records in the blobs, so it credits exactly what
is in them — not what someone believed was in them. CI regenerates it and fails on a
diff.

Sources whose licence requires the notice to travel also ship the text in `LICENSES/`,
and the generator refuses to name a source that has neither a licence text nor a recorded
reason for not having one.

## What "public-facts" means

Two licence values in the [sources table](/reference/sources/) are not SPDX identifiers,
and both record a conclusion rather than a grant.

**`public-facts`** means the extracted content is facts nobody authored. That Antigua and
Barbuda has the ISO code `AG`; that a German *Gesellschaft mit beschränkter Haftung* is
abbreviated GmbH because the statute says so. There is no creative expression in
recording that and no authorship for anyone to license. What is deliberately *not* used
in those cases is the publisher's own selection and arrangement.

**`public-domain`** is a positive statement by the publisher, not an inference.

Being exact about this matters. One registry grants CC0 in two nearby places and neither
one covers the file actually consumed — reading either as covering it would have been
convenient and wrong.

## The check that runs every time

```
swift run decoy-validate --strict
```

It reports paths nothing can draw, template tokens that expand to nothing, licence
metadata that contradicts the text sitting beside it, and any source about to be shipped
without attribution. `--strict` because the report is clean: a check that always prints
ten warnings has no signal in it, and the eleventh — the one somebody just introduced —
is invisible in the noise.
