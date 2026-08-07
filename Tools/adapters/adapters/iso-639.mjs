/**
 * Languages as coherent `(alpha2, alpha3, name)` rows, from Unicode CLDR.
 *
 * A composite rather than three parallel lists, for the same reason countries are: a row
 * drawn field by field would pair `fr` with `deu` and call it Spanish.
 *
 * Fills:
 *   <each>  location.language   composite (alpha2, alpha3, name)
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iso-639'
export const source = 'cldr-48'

/** Maps a Decoy locale code to CLDR's, honouring the roster's explicit overrides. */
function cldrCodeFor(code, overrides) {
  if (Object.hasOwn(overrides, code)) return overrides[code]
  return code.replaceAll('_', '-')
}

/**
 * Builds the ISO 639-2/3 to 639-1 mapping from CLDR's alias table.
 *
 * CLDR records three-letter codes as "overlong" aliases of their two-letter equivalents
 * -- that is the same relationship ISO 639-1 has to 639-2, expressed for a different
 * purpose. Reading it here avoids taking on a second source for one column.
 */
function alphaMapping(aliases) {
  const alpha3For = {}
  for (const [code, alias] of Object.entries(aliases.languageAlias)) {
    if (!/^[a-z]{3}$/.test(code)) continue
    if (alias._reason !== 'overlong') continue
    const replacement = alias._replacement
    if (!/^[a-z]{2}$/.test(replacement)) continue
    // First alias wins; CLDR lists the bibliographic variant second where both exist.
    alpha3For[replacement] ??= code
  }
  return alpha3For
}

async function loadLanguageNames(cldrCode, root) {
  const parts = cldrCode.split('-')
  for (let i = parts.length; i > 0; i--) {
    const candidate = parts.slice(0, i).join('-')
    try {
      const raw = await readFile(
        join(root, 'package', 'main', candidate, 'languages.json'),
        'utf8',
      )
      return JSON.parse(raw).main[candidate].localeDisplayNames.languages
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
  return null
}

export async function run({ artifacts, locales, overrides }) {
  const aliases = JSON.parse(
    await readFile(join(artifacts.core, 'package', 'supplemental', 'aliases.json'), 'utf8'),
  ).supplemental.metadata.alias

  const alpha3For = alphaMapping(aliases)

  const contributions = {}
  const unmapped = []

  for (const code of locales) {
    const cldrCode = cldrCodeFor(code, overrides)
    if (cldrCode === null) continue

    const names = await loadLanguageNames(cldrCode, artifacts.localenames)
    if (names === null) {
      unmapped.push(code)
      continue
    }

    // Only languages that have all three columns. A row missing its alpha-3 would make
    // location.language().alpha3 empty for some draws and not others, which is a worse
    // failure than the language simply not appearing.
    const rows = Object.keys(names)
      .filter((key) => /^[a-z]{2}$/.test(key) && alpha3For[key] && names[key])
      .sort()
      .map((alpha2) => ({ alpha2, alpha3: alpha3For[alpha2], name: names[alpha2] }))

    if (rows.length > 0) {
      contributions[code] = { 'location.language': rows }
    }
  }

  return {
    contributions,
    stats: {
      languages: Object.values(contributions)[0]?.['location.language'].length ?? 0,
      locales: Object.keys(contributions).length,
      unmapped,
    },
  }
}
