---
title: Determinism
description: What "the same seed" actually guarantees, and when it stops.
---

Decoy uses Xoshiro256\*\* seeded per faker. Rows are independent: row 400 does not depend
on rows 1 through 399 having been generated, which is what allows parallel generation.

Reproducibility is guaranteed with respect to **a corpus version**. Adding data is a
minor bump; changing or removing an existing value is a major one, because it silently
changes every fixture anyone has already generated. The version is declared in one place
and read by everything.
