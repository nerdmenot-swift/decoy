---
title: Command-line tools
description: Inspecting, validating and compiling the corpus.
---

```
decoy-inspect <file.decoy>                    summary
decoy-inspect <file.decoy> --paths [substr]   every path, with kind and size
decoy-inspect --coverage <dir>                native coverage per locale
decoy-inspect --matrix <dir>                  locale × data type support, as Markdown
decoy-inspect --notice <dir> --licenses <dir> attribution for every source shipped
decoy-validate --strict                       paths nothing can draw, dead tokens, licences
decoy-compile-corpus <in> <out>               JSON → binary
```
