# Vendored upstreams

Pinned artifacts that a build machine cannot fetch, committed so a cold clone can still
build the corpus. Everything else is downloaded on demand into `../.cache/`.

`lib/sources.mjs` looks here **after** the cache and **before** the network, and verifies
the file against the same integrity hash it would apply to a download. Vendoring changes
where the bytes come from, not whether they are checked: a tampered vendored file fails
exactly as a tampered cache does.

Files are named `<source-id>-<filename>`, matching the cache's naming, and every one is
redistributable under its recorded licence.

| File | Source | Licence | Why |
|---|---|---|---|
| `dvv-etunimet-etunimitilasto.xlsx` | `dvv-etunimet` | CC-BY-4.0 | `avoindata.suomi.fi` answers 403 from its load balancer to clients it does not recognise — GitHub's runners among them — regardless of user agent. One of 51 pinned artifacts, and the only one affected, but without it no platform could build the corpus from a fresh clone. CC BY 4.0 permits redistribution; the copyright line, source URL and full licence text ship in `NOTICE` and `LICENSES/dvv-etunimet.txt`. |

To re-vendor after re-pinning a version, download the new URL and drop it in here under the
same name. If the upstream becomes reachable again, deleting the file is enough — the
fetch path takes over with no other change.
