/**
 * Media types and their file extensions, from mime-db.
 *
 * Language-neutral, so it lives in `base`.
 *
 * Fills:
 *   base    system.mime_type   object keyed by media type, each with `extensions`
 *
 * The shape is unusual and deliberate: the media types themselves are the *keys*, which
 * is what lets the compiler emit a `__keys` table so `mimeType()` can draw a type, and
 * `system.mime_type.<type>.extensions` so `fileExtension()` can draw one that actually
 * belongs to it. Parallel lists would pair `image/png` with `.docx`.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'mime-types'
export const source = 'mime-db'

/**
 * Object nodes whose *keys* are data and must be drawable.
 *
 * The compiler used to emit a `__keys` table under every object node it walked, which
 * came to 2,225 tables of which exactly one is ever read -- this one. In `base` alone
 * that was 1,027 of 2,072 paths and about 90 KB, and 1,015 of them held the single
 * string `"extensions"`, base64-inflated into every binary that links the module.
 *
 * Declared rather than inferred because only the adapter knows: `system.mime_type` is a
 * map from media type to its extensions, so the types are the keys, while
 * `person.first_name` is an object whose keys are `generic`/`female`/`male` and drawing
 * from those would produce the string "female".
 */
export const keyTables = ['system.mime_type']

export async function run({ artifacts }) {
  const db = JSON.parse(
    await readFile(join(artifacts.db, 'package', 'db.json'), 'utf8'),
  )

  const types = {}
  let skipped = 0

  for (const [type, entry] of Object.entries(db).sort(([a], [b]) => (a < b ? -1 : 1))) {
    // Most of mime-db has no extension mapping -- it exists to answer "is this type
    // compressible", not "what file is it". Without extensions a drawn type would send
    // fileExtension() to its "bin" fallback, so those entries would degrade the output
    // rather than broaden it.
    if (!Array.isArray(entry.extensions) || entry.extensions.length === 0) {
      skipped += 1
      continue
    }
    types[type] = { extensions: [...entry.extensions].sort() }
  }

  if (Object.keys(types).length === 0) {
    throw new Error('mime-db yielded no types with extensions — the schema has changed')
  }

  return {
    // Handed over nested rather than as dotted paths: media types contain dots
    // (`application/vnd.ms-excel`), and flattening would split one type into several
    // levels of nesting that nothing could look up again.
    contributions: {
      base: { 'system.mime_type': types },
    },
    stats: {
      types: Object.keys(types).length,
      withoutExtensions: skipped,
    },
  }
}
