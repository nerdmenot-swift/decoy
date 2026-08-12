---
title: Corpus format
description: One binary blob per locale — a string arena and an offset table.
---

Format v2: a deduplicated string arena, an offset table, and typed chunks for string
tables, composite records and n-gram models, plus a provenance chunk.

Lookups are a binary search over a sorted index, so nothing is parsed at load. One blob
per locale rather than one file for everything — 64 blobs, 13 MB in total — and you link
only the chain you use.
