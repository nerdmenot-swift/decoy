/**
 * Country codes and localized country names, from Unicode CLDR.
 *
 * The first adapter, and deliberately the easiest case: countries are *facts*. There is
 * a correct answer, it is published, and generating one instead would be a bug. That
 * makes this the field to prove the pipeline on before touching anything where the
 * right answer is a judgement call.
 *
 * Fills:
 *   base    location.country_code   composite (alpha2, alpha3, numeric)
 *   <each>  location.country, location.continent        names in that locale's own language
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iso-3166'
export const source = 'cldr-48'

/**
 * ISO 3166-1 reserves numeric codes 900-999 for user assignment, and CLDR carries those
 * alongside the real ones (`AA`/`AAA`/`958`, the `XA`-`XZ` range, `ZZ`). Emitting them
 * would produce fixtures containing countries that do not exist, which is precisely the
 * failure a factual field is supposed to be immune to.
 */
const USER_ASSIGNED_FLOOR = 900

/** Maps a Decoy locale code to CLDR's, honouring the roster's explicit overrides. */
function cldrCodeFor(code, overrides) {
  if (Object.hasOwn(overrides, code)) return overrides[code]
  return code.replaceAll('_', '-')
}

/**
 * Loads the closest CLDR territory list at or above a locale.
 *
 * `fr_LU` has no CLDR territory names of its own but `fr` does, and Luxembourgish French
 * does not rename countries. Falling back one segment at a time yields correct data;
 * refusing to fall back would leave the locale empty and hand it to English instead.
 *
 * Probes the file rather than the directory: CLDR ships locale directories that carry
 * some data but not territories -- `dv` is one -- so a directory listing reports
 * coverage the locale does not actually have.
 */
async function loadTerritories(cldrCode, root) {
  const parts = cldrCode.split('-')
  for (let i = parts.length; i > 0; i--) {
    const candidate = parts.slice(0, i).join('-')
    try {
      const raw = await readFile(
        join(root, 'package', 'main', candidate, 'territories.json'),
        'utf8',
      )
      return JSON.parse(raw).main[candidate].localeDisplayNames.territories
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
  return null
}

/** UN M49 macro-region codes: Africa, Americas, Asia, Europe, Oceania, Antarctica. */
const CONTINENT_CODES = ['002', '019', '142', '150', '009', 'AQ']

export async function run({ artifacts, locales, overrides }) {
  const codeMappings = JSON.parse(
    await readFile(
      join(artifacts.core, 'package', 'supplemental', 'codeMappings.json'),
      'utf8',
    ),
  ).supplemental.codeMappings

  // Officially assigned entries only: a real two-letter code carrying both an alpha-3
  // and a numeric outside the user-assigned range.
  const assigned = Object.entries(codeMappings)
    .filter(
      ([code, mapping]) =>
        /^[A-Z]{2}$/.test(code) &&
        mapping._alpha3 &&
        mapping._numeric &&
        Number(mapping._numeric) < USER_ASSIGNED_FLOOR,
    )
    .sort(([a], [b]) => (a < b ? -1 : 1))

  const known = new Set(assigned.map(([code]) => code))

  const contributions = {}
  const unmapped = []

  // The code triple is language-neutral, so it belongs in `base` where every locale
  // reaches it. Splitting it into three parallel lists would generate countries that do
  // not exist, which is why the format carries composite records at all.
  contributions.base = {
    'location.country_code': assigned.map(([alpha2, mapping]) => ({
      alpha2,
      alpha3: mapping._alpha3,
      numeric: mapping._numeric,
    })),
  }

  for (const code of locales) {
    const cldrCode = cldrCodeFor(code, overrides)
    if (cldrCode === null) continue

    const territories = await loadTerritories(cldrCode, artifacts.localenames)
    if (territories === null) {
      unmapped.push(code)
      continue
    }

    // CLDR carries alternates such as `CD-alt-variant` and `HK-alt-short`. The plain key
    // is the standard form; the alternates are editorial choices we have no basis to make.
    const names = Object.entries(territories)
      .filter(([key]) => !key.includes('-alt-') && known.has(key))
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([, name]) => name)

    // Continents come from the same file, under the UN M49 codes CLDR uses for macro
    // regions. Worth taking because they are otherwise a one-locale curiosity: faker
    // carries `location.continents` for Welsh and nothing else, so a continent generator
    // built on it would work in one locale out of seventy-six. From CLDR it works
    // wherever territory names do.
    //
    // Six rather than seven: CLDR models the Americas as one region (019), because M49
    // does. A library that split it would be asserting a schoolroom convention that a
    // good half the world does not use.
    const continents = CONTINENT_CODES.map((m49) => territories[m49]).filter(Boolean)

    if (names.length > 0 || continents.length > 0) {
      contributions[code] = {}
      if (names.length > 0) contributions[code]['location.country'] = names
      if (continents.length > 0) contributions[code]['location.continent'] = continents
    }
  }

  return {
    contributions,
    stats: {
      countries: assigned.length,
      locales: Object.keys(contributions).length - 1,
      unmapped,
    },
  }
}
