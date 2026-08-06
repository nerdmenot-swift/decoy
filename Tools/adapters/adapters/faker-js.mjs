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
    },
  }
}
