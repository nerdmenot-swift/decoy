/**
 * Country subdivisions — states, provinces, prefectures, départements — from CLDR's
 * ISO 3166-2 data.
 *
 * Each locale gets *its own country's* subdivisions rather than everyone getting
 * American states. `de` yields the sixteen Bundesländer, `ja` the forty-seven
 * prefectures, `en_IN` the Indian states and union territories. faker put fifty US
 * states in `en` and nothing anywhere else, so a German address came out with a
 * Californian state attached.
 *
 * Fills:
 *   <each>  location.state       composite (name, abbr) -- that locale's subdivisions
 *   <each>  location.state_abbr  the same codes as a flat list
 *
 * KNOWN GAP, and a worse one than it first appears: CLDR translates subdivision names
 * into English only. Every other locale file carries three entries (England, Scotland,
 * Wales) and nothing more, so these names are English everywhere.
 *
 * How much that costs depends entirely on the language. Japanese prefectures, Brazilian
 * states and Indian states come through as endonyms — Hokkaidō, Acre, Assam — and read
 * correctly. German does not: eight of the sixteen Bundesländer have English exonyms in
 * CLDR, so a German corpus yields Bavaria, Saxony, Lower Saxony, Rhineland-Palatinate,
 * North Rhine-Westphalia, Thuringia, Hesse and Saxony-Anhalt where the German forms
 * belong. That is half the list, not a handful.
 *
 * It is still a large improvement on what it replaces — faker had fifty US states in
 * `en` and nothing for any other country, so every German address carried a Californian
 * state. But this field is not finished, and closing it needs a source CLDR does not
 * provide.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iso-3166-2'
export const source = 'cldr-48'

/**
 * Finds the country a locale belongs to.
 *
 * An explicit region subtag wins: `de_AT` is Austria, not Germany, and `en_IN` is India.
 * Otherwise CLDR's likely-subtags table supplies the language's default region, which is
 * how `ja` resolves to Japan and `en` to the United States.
 */
function regionFor(code, likelySubtags) {
  for (const segment of code.split('_').slice(1)) {
    if (/^[A-Z]{2}$/.test(segment)) return segment
  }
  const language = code.split('_')[0]
  const likely = likelySubtags[language] ?? likelySubtags[code.replaceAll('_', '-')]
  const region = likely?.split('-').at(-1)
  return /^[A-Z]{2}$/.test(region ?? '') ? region : null
}

export async function run({ artifacts, locales }) {
  const likelySubtags = JSON.parse(
    await readFile(
      join(artifacts.core, 'package', 'supplemental', 'likelySubtags.json'),
      'utf8',
    ),
  ).supplemental.likelySubtags

  // English only, per the note above. Reading one file rather than one per locale is a
  // consequence of that, not an optimisation.
  const subdivisions = JSON.parse(
    await readFile(
      join(artifacts.subdivisions, 'package', 'subdivisions', 'en', 'en.json'),
      'utf8',
    ),
  ).subdivisions.localeDisplayNames.subdivisions

  // Group by country once: `usca` -> US, `debw` -> DE.
  const byRegion = {}
  for (const [key, name] of Object.entries(subdivisions)) {
    const match = key.match(/^([a-z]{2})([a-z0-9]+)$/)
    if (!match) continue
    const [, country, suffix] = match
    ;(byRegion[country.toUpperCase()] ??= []).push({ name, code: suffix.toUpperCase() })
  }
  for (const rows of Object.values(byRegion)) rows.sort((a, b) => (a.name < b.name ? -1 : 1))

  const contributions = {}
  const withoutSubdivisions = []

  for (const code of locales) {
    if (code === 'base') continue

    const region = regionFor(code, likelySubtags)
    const rows = region ? byRegion[region] : null
    if (!rows || rows.length === 0) {
      if (region) withoutSubdivisions.push(`${code}(${region})`)
      continue
    }

    // A composite, so a row that needs both gets them from the same subdivision.
    // Parallel lists would pair Bavaria with Hamburg's code and pass most validators.
    contributions[code] = {
      'location.state': rows.map((r) => ({ name: r.name, abbr: r.code })),
      // The flat list too, because `stateAbbreviation()` fills a column of its own and
      // should not have to draw a whole row to do it. Same values as the composite's
      // `abbr`, from the same rows, so the two cannot disagree — which is the failure a
      // separate source for this would reintroduce.
      'location.state_abbr': rows.map((r) => r.code),
    }
  }

  return {
    contributions,
    stats: {
      countries: Object.keys(byRegion).length,
      subdivisions: Object.keys(subdivisions).length,
      locales: Object.keys(contributions).length,
      withoutSubdivisions,
    },
  }
}
