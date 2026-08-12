---
title: Locales and fallback
description: Sixty-four locales, what each supplies itself, and what it borrows.
---

Locales resolve through a chain — `de_AT → de → en → base` — at lookup time rather than
compile time, so a locale's blob stays small.

A locale that declares a field *empty* stops the walk. Azerbaijani has no name prefixes,
and continuing to English would put "Dr." on Azeri records.

Coverage is measurable and worth measuring before you pick a locale:

```
decoy-inspect --coverage Corpus/binary
```

See the [locale matrix](/reference/locale-matrix/) for what each one supplies itself.
