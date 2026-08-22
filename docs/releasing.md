# Releasing Decoy

## The short version

```
Actions → Prepare release → run with "1.1.0"
```

That is the whole procedure. It sets `Decoy.version`, runs the suite, commits, and pushes
`v1.1.0`, which triggers everything else. Do not tag by hand — the workflow exists because
the version lives in two places and hand-tagging is how they come to disagree.

**The tag is `v1.1.0`, with the `v`.** `Release` triggers on `v*.*.*`, so a tag named
`1.1.0` builds nothing and publishes nothing, silently. SwiftPM resolves either form, so
the mistake does not show up on the consuming side — only the release does not exist.

## Two version numbers, and why

Most packages have one. Decoy has two because it ships code *and* data, and they fail
differently.

| | What it promises | What breaks it |
|---|---|---|
| **Package** `1.1.0` | The API | A renamed method, a changed signature |
| **Corpus** `60.2.0` | What a seed draws | Adding names to a locale; changing an existing value |

`generate(seed:)` is only reproducible *with respect to a corpus*. Somebody who committed
generated fixtures is exposed to the corpus version, not the package version — so a
release note saying "no API changes" tells them nothing about whether their test data
still matches.

Which is why both appear in every release note, and why one rule is enforced rather than
documented:

> **A corpus change cannot ship in a patch release.**

`from: "1.0.0"` resolves patch upgrades automatically. Moving the data in a patch would
rewrite somebody's fixtures during a `swift package update` they did not think about. A
minor is the smallest release a person actually chooses. `Release` fails the build if a
patch bump moves the corpus version.

Within the corpus itself: **adding** data is a minor bump, **changing or removing an
existing value** is a major one. See [corpus-strategy.md](corpus-strategy.md).

## What happens when you run it

```
Prepare release  ──►  pushes tag v1.1.0  ──►  Release  ──►  Docs
  set version                                  verify        deploy site
  build + test                                 build ×3
  commit + tag                                 publish
```

**Prepare release** (`prepare-release.yml`, manual). Refuses a non-semver version and
refuses a tag that already exists — a released version is never re-cut. Has a dry-run mode
that shows the diff without committing.

**Release** (`release.yml`, on `v*.*.*`). Four gates before anything is built:

1. the tag matches `Decoy.version` — binaries that report a different version than the tag
   that produced them are wrong in a way nobody notices until they are debugging something
   else;
2. a corpus version is declared;
3. the corpus did not move in a patch release;
4. the corpus builds and the full suite passes *against it* — roughly thirty suites skip
   rather than fail when `Corpus/binary` is absent, so testing without building the corpus
   first would gate a release on almost nothing.

Then it publishes the GitHub release. Nothing is built and nothing is attached: the tag is
what people install.

It used to also build the three corpus tools for macOS, Linux and Windows. That was
dropped — the [CLI reference](/reference/cli/) says plainly that none of them is needed to
*use* Decoy, they cost three platform builds on every tag, the Linux archive was 76 MB
because it links the Swift runtime statically, and the Windows one was not self-contained
anyway. `swift run decoy-inspect` is the supported route for reading a corpus.

**Docs** (`docs.yml`). Deploys `website/` to Cloudflare Pages on a push to `main` that
touches it, and on every published release, so the site is never describing the previous
version.

## The library needs no publishing step

SwiftPM has no registry in practice: `.package(url:from:)` resolves a git tag directly.
**The tag is the release.** This has one consequence worth internalising — a tag can never
be moved or deleted once anyone has resolved it, because their `Package.resolved` pins a
commit hash. `Prepare release` refuses to re-cut an existing version for that reason.

The binaries are a convenience for people who want to inspect a `.decoy` file without a
Swift toolchain. Nobody needs them to use the library.

## What CI enforces so a release does not have to

The release is boring because `main` is always releasable. On every push, three platforms
build, compile a corpus and run the full suite, and these gates run:

- `NOTICE`, the locale support matrix and the locale modules are regenerated and diffed —
  a stale generated file fails the build;
- the generated website content is regenerated and diffed, for the same reason;
- `decoy-validate --strict`, with a clean report, so the eleventh warning is visible;
- coverage has not regressed against a committed baseline;
- `PortabilityLintTests` fails on calls known to mean something else on another platform.

## How this compares to the rest of the ecosystem

The shape here — a manual *prepare* that tags, and an automated *release* that reacts to
the tag — is the same one used by `cargo-release`, `goreleaser`, changesets and
release-please. The split matters: deciding a version number is a judgement about what a
change does to somebody else's work, and nothing in a workflow can make that call.
Everything *after* the decision is mechanical, and mechanical things should not be done by
hand at 11pm.

Where Decoy deliberately differs from its closest neighbour: faker-js documents that
seeded output may change between minor versions, and leaves it there. Decoy versions the
data separately so it can be pinned, and refuses to move it in a patch.

Practices adopted from elsewhere:

- **Keep a Changelog** — `## Unreleased` accumulating during development, promoted to a
  version heading at release, rather than release notes generated from commit subjects.
- **Never re-cut a tag** — universal, and load-bearing for SwiftPM specifically.
- **Release candidates for majors** — `1.0.0-rc.1` is accepted by `Prepare release`, and
  SwiftPM treats a pre-release as opt-in, so `from: "1.0.0"` will not resolve to it.

Deliberately not adopted: automated version bumps from commit messages
(`feat:`/`fix:` → semver). Whether a corpus change is breaking depends on whether it alters
values somebody has already generated, which is not visible in a commit subject.

## Checklist for a major

1. Is anything in `CHANGELOG.md` under `## Unreleased` marked as changing drawn values?
2. Does the corpus major differ from the last release's?
3. Are the locale gaps in `README.md` still accurate — has anything been filled or lost?
4. Cut `2.0.0-rc.1` first and leave it out for a week.
