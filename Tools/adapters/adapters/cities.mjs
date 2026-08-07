/**
 * Real cities, per locale, and as coherent place rows.
 *
 * Each locale gets its own country's cities: `de` yields German ones, `ja` Japanese,
 * `pt_BR` Brazilian. faker had 927 US cities in `en` and nothing for anywhere else, so
 * every German address was set in Ohio.
 *
 * Fills:
 *   <each>  location.city_name   that country's cities
 *   <each>  location.place       composite (city, state)
 *
 * KNOWN INCONSISTENCY: `location.state` comes from CLDR and `location.place`'s state
 * column from the gazetteer, and the two occasionally spell a subdivision differently --
 * German yields `Rheinland-Pfalz` here where CLDR says `Rhineland-Palatinate`. Most
 * entries agree (Bavaria, Saxony, Lower Saxony, North Rhine-Westphalia all match), and
 * the gazetteer is internally inconsistent for that one rather than systematically
 * different. Unifying them needs a GeoNames-admin1 to ISO 3166-2 mapping, which is a
 * per-country table nobody publishes.
 *
 * `location.place` is the point. `city: "Boston", state: "CA"` passes most validators
 * and is nonsense, and it is what every faker produces because the fields are drawn
 * independently. A whole row drawn at once cannot disagree with itself — the failure
 * corpus-strategy.md calls a bigger differentiator than referential integrity for a
 * library aimed at database seeding.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'cities'
export const sources = ['cities-json', 'cldr-48']

/** The gazetteer supplies every value; CLDR only resolves a locale to its country. */
export const attributeTo = 'cities-json'

function regionFor(code, likelySubtags) {
  for (const segment of code.split('_').slice(1)) {
    if (/^[A-Z]{2}$/.test(segment)) return segment
  }
  const language = code.split('_')[0]
  const region = likelySubtags[language]?.split('-').at(-1)
  return /^[A-Z]{2}$/.test(region ?? '') ? region : null
}

export async function run({ artifacts, locales }) {
  const likelySubtags = JSON.parse(
    await readFile(
      join(artifacts.core, 'package', 'supplemental', 'likelySubtags.json'),
      'utf8',
    ),
  ).supplemental.likelySubtags

  const root = join(artifacts.cities, 'package')

  const cities = JSON.parse(await readFile(join(root, 'cities.json'), 'utf8'))
  const admin1 = JSON.parse(await readFile(join(root, 'admin1.json'), 'utf8'))

  // admin1 codes are country-scoped (`US.CA`, `DE.02`), so the lookup has to be keyed by
  // the pair — `03` alone means a different subdivision in every country.
  const adminNames = new Map(admin1.map((entry) => [entry.code, entry.name]))

  const byCountry = new Map()
  for (const city of cities) {
    if (!city.name || !city.country) continue
    if (!byCountry.has(city.country)) byCountry.set(city.country, [])
    byCountry.get(city.country).push(city)
  }

  const contributions = {}
  const withoutCities = []

  for (const code of locales) {
    if (code === 'base') continue

    const region = regionFor(code, likelySubtags)
    const rows = region ? byCountry.get(region) : null
    if (!rows || rows.length === 0) {
      if (region) withoutCities.push(`${code}(${region})`)
      continue
    }

    const sorted = [...rows].sort((a, b) => (a.name < b.name ? -1 : 1))

    contributions[code] = {
      'location.city_name': [...new Set(sorted.map((c) => c.name))],
      // Coordinates are deliberately omitted. The gazetteer has them, and a coherent
      // place row arguably wants them, but they are single-use high-entropy strings that
      // never dedup in the arena: for `en` alone they were 17,019 distinct strings, about
      // a third of the locale's total, and they tripled the compiled module. `latitude()`
      // and `longitude()` already generate coordinates algorithmically. Re-adding them
      // should be a deliberate choice about geo fixtures, not a side effect of wanting
      // city and state to agree.
      'location.place': sorted.map((c) => ({
        city: c.name,
        // Empty rather than absent where the gazetteer has no subdivision, so the
        // composite keeps one shape across every row.
        state: adminNames.get(`${c.country}.${c.admin1}`) ?? '',
      })),
    }
  }

  return {
    contributions,
    stats: {
      cities: cities.length,
      countries: byCountry.size,
      locales: Object.keys(contributions).length,
      withoutCities,
    },
  }
}
