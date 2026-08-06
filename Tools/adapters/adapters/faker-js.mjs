/**
 * The bootstrap corpus, read from whatever `Tools/extractor` last wrote.
 *
 * Declared `fallback`, so every other adapter overrides it wherever they overlap. A
 * field stops being faker-derived the moment something else covers it, and no other file
 * changes. That is the whole migration mechanism: when coverage is complete, deleting
 * this file and `Tools/extractor` removes the dependency in one commit rather than
 * requiring a coordinated rewrite.
 *
 * Contributes each locale's top-level categories rather than individual paths. The
 * merge is by subtree, so `system.mime_type` from the mime-db adapter replaces faker's
 * whole `system.mime_type` node while faker's `system.directory_path` survives beside
 * it. Flattening to dotted paths would break here anyway: media types contain dots, and
 * `system.mime_type.application/vnd.ms-excel.extensions` cannot be split back apart.
 */

import { readFile, readdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const extractorOut = join(here, '..', '..', 'extractor', 'out')

export const id = 'faker-js'
export const source = 'faker-js'

/**
 * Categories deliberately outside Decoy's scope.
 *
 * Decoy seeds databases. These are domain vocabularies that exist in every faker because
 * contributors added what amused them, not because anyone seeding a schema needs them —
 * the same reasoning that excluded gofakeit's Minecraft and jaswdr's Pokémon, applied
 * consistently rather than only to the obvious cases.
 *
 * Dropping them is not cosmetic. Each one is a curated word list with no registry behind
 * it, in 76 languages, and every one would have to be re-sourced before faker-js can be
 * deleted. Together they were 44% of `en`'s values. Several are also lists of real
 * trademarked entities — actual recording artists, airlines and book titles — which is
 * exposure taken on for data nobody asked for.
 *
 * `cell_phone` is here for a different reason: no generator has ever read it.
 *
 * `science` is deliberately NOT here despite being small and obscure. Chemical elements
 * are IUPAC-published and SI units are standardised, so it is a fact table with a real
 * registry -- exactly what corpus-strategy.md says to keep and source rather than drop.
 */
const OUT_OF_SCOPE = new Set([
  'airline',
  'animal',
  'app',
  'book',
  'cell_phone',
  'food',
  'hacker',
  'music',
  'team',
])

/// Lowest precedence: contributes only where nothing else has.
export const fallback = true

export async function run({ locales }) {
  let available
  try {
    available = new Set(await readdir(join(extractorOut, 'locales')))
  } catch (error) {
    if (error.code !== 'ENOENT') throw error
    // Not an error. Once the extractor is gone this adapter contributes nothing and the
    // build proceeds on adapter data alone -- which is exactly the end state.
    return { contributions: {}, stats: { note: 'no extractor output; skipped' } }
  }

  const contributions = {}
  let categories = 0
  let dropped = 0

  for (const code of locales) {
    if (!available.has(`${code}.json`)) continue

    const definitions = JSON.parse(
      await readFile(join(extractorOut, 'locales', `${code}.json`), 'utf8'),
    )

    const perLocale = {}
    for (const [category, value] of Object.entries(definitions)) {
      // `metadata` describes the locale rather than supplying drawable values, and
      // compiling it would put paths like `metadata.title` in the corpus.
      if (category === 'metadata') continue
      if (OUT_OF_SCOPE.has(category)) {
        dropped += 1
        continue
      }
      if (value === null || typeof value !== 'object') continue
      perLocale[category] = value
      categories += 1
    }

    if (Object.keys(perLocale).length > 0) contributions[code] = perLocale
  }

  return {
    contributions,
    stats: {
      locales: Object.keys(contributions).length,
      categories,
      outOfScopeDropped: dropped,
    },
  }
}
