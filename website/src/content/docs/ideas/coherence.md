---
title: Coherent records
description: Why some values are drawn together and most are not.
---

Three independent draws produce a city, a state and a postcode that have never coexisted.
Where that matters, Decoy draws the row as a unit — the gazetteer supplies city and
subdivision together, and the postcode comes from inside that subdivision.

The same argument applies to names. Five locales carry their own surnames but no given
names, and composing across that boundary produced `ChengAaliyah`: a Han pattern,
correctly spaceless, filled from English. `fullName()` now takes the whole composition
from one corpus, so those locales return an obviously English name instead of a hybrid.
