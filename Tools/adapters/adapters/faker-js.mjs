/**
 * The bootstrap corpus, read directly from a pinned @faker-js/faker tarball.
 *
 * Deliberately a reader of faker's own compiled objects rather than a parser of its
 * TypeScript source: importing the built package is robust against upstream refactors in
 * a way that parsing `.ts` never is. faker-js has zero runtime dependencies, so the
 * extracted tarball imports with nothing to resolve -- no npm, no `node_modules`, and
 * nothing about faker-js committed to this repository.
 *
 * Declared `fallback`, so every other adapter overrides it wherever they overlap. A
 * field stops being faker-derived the moment something else covers it, and no other file
 * changes. When coverage is complete, deleting this file and its descriptor removes the
 * dependency entirely.
 *
 * Contributes each locale's top-level categories rather than individual paths. The merge
 * is by subtree, so `system.mime_type` from the mime-db adapter replaces faker's whole
 * `system.mime_type` node while faker's `system.directory_path` survives beside it.
 * Flattening to dotted paths would break here anyway: media types contain dots, and
 * `system.mime_type.application/vnd.ms-excel.extensions` cannot be split back apart.
 */

import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

export const id = 'faker-js'
export const source = 'faker-js'

/** Lowest precedence: contributes only where nothing else has. */
export const fallback = true

/**
 * Categories deliberately outside Decoy's scope.
 *
 * Decoy seeds databases. These are domain vocabularies that exist in every faker because
 * contributors added what amused them, not because anyone seeding a schema needs them --
 * the same reasoning that excluded gofakeit's Minecraft and jaswdr's Pokémon, applied
 * consistently rather than only to the obvious cases.
 *
 * Dropping them is not cosmetic. Each is a curated word list with no registry behind it,
 * in 76 languages, and every one would have to be re-sourced before faker-js can be
 * deleted. Several are also lists of real trademarked entities -- actual recording
 * artists, airlines and book titles -- which is exposure taken on for data nobody asked
 * for.
 *
 * `airline` was here and is not any more. Airports carry IATA and ICAO codes -- real
 * published identifiers rather than a curated word list -- so the namespace is back, with
 * airports sourced from the registry and airline and aircraft names left to this adapter,
 * since those are trademarks nobody publishes permissively.
 *
 * `cell_phone` is here for a different reason: no generator has ever read it.
 *
 * `science` is deliberately NOT here despite being small and obscure. Chemical elements
 * are IUPAC-published and SI units are standardised, so it is a fact table with a real
 * registry -- exactly what corpus-strategy.md says to keep and source rather than drop.
 */
const OUT_OF_SCOPE = new Set([
  'animal',
  'app',
  'book',
  'cell_phone',
  'food',
  'hacker',
  'music',
  'team',
])

/**
 * Checks Decoy's derived fallback chains against faker's own resolution.
 *
 * Decoy derives chains from the locale roster rather than storing them, and faker is the
 * only source that can confirm the rule is right. Asserting it here means a divergence
 * fails the build loudly instead of silently producing a corpus with the wrong
 * inheritance -- which surfaces as a locale quietly serving another language's data.
 *
 * This check disappears with faker-js. That is a real cost of the migration and worth
 * stating plainly: afterwards the chain rule is asserted by nothing but its own tests.
 */
function verifyChains(faker, chains, locales) {
  const mismatches = []

  // Order-insensitive on purpose. Key order carries no meaning here, and comparing
  // serialised forms would report a mismatch every time faker reordered a declaration.
  function deepEqual(a, b) {
    if (a === b) return true
    if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false
    if (Array.isArray(a) !== Array.isArray(b)) return false
    const aKeys = Object.keys(a)
    if (aKeys.length !== Object.keys(b).length) return false
    return aKeys.every((k) => deepEqual(a[k], b[k]))
  }

  for (const code of locales) {
    const expected = faker.allFakers[code]?.rawDefinitions
    const chain = chains[code]
    if (!expected || !chain) continue

    const merged = {}
    for (const link of chain) {
      const locale = faker.allLocales[link]
      if (!locale) continue
      for (const [category, entries] of Object.entries(locale)) {
        if (entries === null || typeof entries !== 'object') continue
        merged[category] ??= {}
        for (const [key, value] of Object.entries(entries)) {
          // Presence, not nullishness. An explicit `null` means "this locale has no such
          // concept" -- Azerbaijani has no name prefixes -- and must block the fallback
          // rather than invite English to fill the gap.
          if (!(key in merged[category])) merged[category][key] = value
        }
      }
    }

    for (const category of Object.keys(expected)) {
      if (OUT_OF_SCOPE.has(category) || category === 'metadata') continue
      if (!deepEqual(merged[category], expected[category])) {
        mismatches.push(`${code}.${category}`)
      }
    }
  }

  return mismatches
}

/**
 * Tokens no generator can ever resolve, because the data behind them was cut from scope.
 *
 * The scope cut removed `animal`, `food` and the rest but left faker's patterns that
 * reference them, so `commerce.product_description` shipped with holes in it.
 *
 * A pattern is data, and a pattern referencing data that does not exist is broken data.
 * Dropping it here is better than expanding it to a hole at runtime.
 *
 * `company.category` used to be listed here on the grounds that "no locale defines it at
 * all, in faker or here". That was simply wrong — `ja`, `ko`, `uk` and `zh_CN` all define
 * it, and all four use it in their company name patterns. Dropping those patterns left
 * the data orphaned and the names missing the industry that identifies them. Found by
 * `decoy-validate`, which reported the data as unreachable.
 */
const UNRESOLVABLE_TOKEN = /\{\{\s*(animal|food)\./

/**
 * Paths another adapter has superseded, dropped as whole `category.key` pairs.
 *
 * Distinct from a *claim*, which is how a real adapter takes a path over: a claim needs
 * the claiming adapter to supply the path, and here nothing does. `date.time_zone` used
 * to be written twice by the tzdb adapter, byte-identical to `location.time_zone`, so
 * `date.timeZone()` now reads the one canonical path -- which left faker's own 419-entry
 * `date.time_zone` unclaimed and free to fill a path nothing reads.
 */
const SUPERSEDED = new Set([
  'date.time_zone',
  // Nobiliary particles — "von", "zu". Carried by `de` and `de_AT`, referenced by no
  // pattern in faker either, so it is dead upstream as well as here. A generator for a
  // fragment of a surname in two locales is not worth writing to make a warning go away.
  'person.nobility_title_prefix',
  // Welsh-only, and CLDR supplies continents for every locale that has territory names.
  // Keeping faker's would mean `continent()` working in one locale out of seventy-six.
  'location.continents',
  // Open Multilingual Wordnet supplies these in fifteen locales under licences that
  // compose; the eight faker also covered are ones OMW cannot reach. Dropping them lets
  // those eight fall through to English, which is what the other fifty-three already do.
  // A German noun from faker is better than an English one, and neither is worth keeping
  // a dependency for once the rest of the namespace has moved.
  'word.noun',
  'word.verb',
  'word.adjective',
  'word.adverb',
  // No wordnet carries closed-class function words -- OMW is nouns, verbs, adjectives and
  // adverbs only -- and no registry publishes them. `word.preposition()`,
  // `word.conjunction()` and `word.interjection()` are dropped with the data rather than
  // left to trap: they existed because faker had the lists, not because anybody needs a
  // generated preposition.
  'word.preposition',
  'word.conjunction',
  'word.interjection',
])

/** Removes superseded keys from one category's tree. */
function withoutSuperseded(category, value) {
  const out = {}
  for (const [key, inner] of Object.entries(value)) {
    if (SUPERSEDED.has(`${category}.${key}`)) continue
    out[key] = inner
  }
  return Object.keys(out).length > 0 ? out : undefined
}

/** Recursively drops pattern strings whose tokens cannot be satisfied. */
function withoutBrokenPatterns(value, dropped) {
  if (typeof value === 'string') {
    return UNRESOLVABLE_TOKEN.test(value) ? undefined : value
  }
  if (Array.isArray(value)) {
    const kept = value
      .map((item) => withoutBrokenPatterns(item, dropped))
      .filter((item) => item !== undefined)
    dropped.count += value.length - kept.length
    // An emptied list is worse than an absent one: `require` would trap on it.
    return kept.length > 0 ? kept : undefined
  }
  if (value !== null && typeof value === 'object') {
    const out = {}
    for (const [key, inner] of Object.entries(value)) {
      const next = withoutBrokenPatterns(inner, dropped)
      if (next !== undefined) out[key] = next
    }
    return Object.keys(out).length > 0 ? out : undefined
  }
  return value
}

export async function run({ artifacts, locales, chains }) {
  const entry = pathToFileURL(join(artifacts.faker, 'package', 'dist', 'index.js'))
  const faker = await import(entry.href)

  const mismatches = verifyChains(faker, chains, locales)
  if (mismatches.length > 0) {
    throw new Error(
      `fallback chain mismatch in ${mismatches.length} locale/category pairs ` +
        `(first: ${mismatches.slice(0, 5).join(', ')}). Decoy's derived chains no longer ` +
        `match faker's own resolution; fix fallbackChain() in run.mjs.`,
    )
  }

  const contributions = {}
  const dropped = { count: 0 }
  let categories = 0
  let outOfScope = 0

  for (const code of locales) {
    const definitions = faker.allLocales[code]
    if (!definitions) continue

    const perLocale = {}
    for (const [category, value] of Object.entries(definitions)) {
      // `metadata` describes the locale rather than supplying drawable values, and
      // compiling it would put paths like `metadata.title` in the corpus.
      if (category === 'metadata') continue
      if (OUT_OF_SCOPE.has(category)) {
        outOfScope += 1
        continue
      }
      if (value === null || typeof value !== 'object') continue
      const kept = withoutSuperseded(category, value)
      if (kept === undefined) continue
      const cleaned = withoutBrokenPatterns(kept, dropped)
      if (cleaned === undefined) continue
      perLocale[category] = cleaned
      categories += 1
    }

    if (Object.keys(perLocale).length > 0) contributions[code] = perLocale
  }

  return {
    contributions,
    stats: {
      locales: Object.keys(contributions).length,
      categories,
      outOfScopeDropped: outOfScope,
      brokenPatternsDropped: dropped.count,
      chainsVerified: locales.length,
    },
  }
}
