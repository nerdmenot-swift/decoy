---
title: Provenance
description: Every value knows which source it came from, under which licence.
---

The corpus is a build artifact. Nobody hand-edits data: every string is derived from a
citable primary source by a reproducible pipeline, and carries its origin with it.

```
decoy-inspect --notice Corpus/binary --licenses LICENSES
```

Each source is pinned to a URL and an SRI integrity hash. A cached artifact is
re-verified rather than trusted, because a tampered cache would otherwise produce a
corpus that passes every check on the machine that built it and nowhere else.
