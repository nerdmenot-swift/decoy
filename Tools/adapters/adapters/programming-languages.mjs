/**
 * Programming languages as coherent `(name, extension, color)` rows, from Linguist.
 *
 * A composite rather than three lists, for the same reason countries are: drawn
 * independently you get Haskell with a `.rs` extension in Go's blue.
 *
 * Language names are proper nouns and do not translate, so this lives in `base` where
 * every locale reaches it.
 *
 * Fills:
 *   base    system.programming_language   composite (name, extension, color)
 */

import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

export const id = 'programming-languages'
export const source = 'linguist'

export async function run({ artifacts }) {
  // The package is plain ES modules, one per language, re-exported from index.js by
  // display name. Importing it is both simpler and more robust than parsing: node does
  // the work, and a change to the file layout fails loudly at import rather than
  // silently matching nothing.
  const entry = pathToFileURL(join(artifacts.languages, 'package', 'index.js'))
  const languages = await import(entry.href)

  const rows = []
  let withoutExtension = 0
  let nonProgramming = 0

  for (const name of Object.keys(languages).sort()) {
    const language = languages[name]
    if (!language || typeof language !== 'object') continue

    // Linguist classifies markup, data and prose alongside programming languages. JSON
    // and Markdown are not what anyone means by "programming language", and a fixture
    // offering them as one is wrong in a way that is hard to notice.
    if (language.type !== 'programming') {
      nonProgramming += 1
      continue
    }

    const extensions = language.extensions ?? []
    if (extensions.length === 0) {
      withoutExtension += 1
      continue
    }

    rows.push({
      name: language.name,
      // The first extension is Linguist's primary; the rest are alternates.
      extension: extensions[0],
      // Not every language has an assigned colour, and an empty column keeps the
      // composite one shape rather than existing on some rows and not others.
      color: language.color ?? '',
    })
  }

  if (rows.length < 100) {
    throw new Error(
      `linguist yielded only ${rows.length} programming languages — the data shape has changed`,
    )
  }

  return {
    contributions: {
      base: { 'system.programming_language': rows },
    },
    stats: {
      languages: rows.length,
      withoutExtension,
      nonProgramming,
    },
  }
}
