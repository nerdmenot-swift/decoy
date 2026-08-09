/**
 * Month and weekday names, from Unicode CLDR.
 *
 * Localized across every locale CLDR covers, which is what a date name has to be —
 * `Januar`, `Mittwoch`, `1月`, `水曜日`.
 *
 * Fills:
 *   <each>  date.month.wide     January … December
 *   <each>  date.month.abbr     Jan … Dec
 *   <each>  date.weekday.wide   Sunday … Saturday
 *   <each>  date.weekday.abbr   Sun … Sat
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'cldr-dates'
export const source = 'cldr-48'

/**
 * Sunday first, matching ``Timestamp/weekday`` so an index into one lines up with the
 * other. CLDR uses these keys in this order; naming them explicitly means a change
 * upstream surfaces as a missing key rather than a silently rotated week.
 */
const WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']

/** CLDR keys months by number as strings. */
const MONTH_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']

function cldrCodeFor(code, overrides) {
  if (Object.hasOwn(overrides, code)) return overrides[code]
  return code.replaceAll('_', '-')
}

async function loadGregorian(cldrCode, root) {
  const parts = cldrCode.split('-')
  for (let i = parts.length; i > 0; i--) {
    const candidate = parts.slice(0, i).join('-')
    try {
      const raw = await readFile(
        join(root, 'package', 'main', candidate, 'ca-gregorian.json'),
        'utf8',
      )
      return JSON.parse(raw).main[candidate].dates.calendars.gregorian
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
  return null
}

/** Reads a name set in a fixed key order, or null if any key is missing. */
function ordered(source, keys) {
  if (!source) return null
  const values = keys.map((key) => source[key])
  return values.every((v) => typeof v === 'string' && v !== '') ? values : null
}

export async function run({ artifacts, locales, overrides }) {
  const contributions = {}
  const unmapped = []

  for (const code of locales) {
    const cldrCode = cldrCodeFor(code, overrides)
    if (cldrCode === null) continue

    const gregorian = await loadGregorian(cldrCode, artifacts.dates)
    if (gregorian === null) {
      unmapped.push(code)
      continue
    }

    // `format` rather than `stand-alone`: these appear inside a formatted date, which is
    // the context a fixture's month name is used in. Slavic languages inflect the two
    // differently and the stand-alone form would read as a heading, not a date.
    const monthsWide = ordered(gregorian.months?.format?.wide, MONTH_KEYS)
    const monthsAbbr = ordered(gregorian.months?.format?.abbreviated, MONTH_KEYS)
    const daysWide = ordered(gregorian.days?.format?.wide, WEEKDAY_KEYS)
    const daysAbbr = ordered(gregorian.days?.format?.abbreviated, WEEKDAY_KEYS)

    // The stand-alone forms, which faker called `_context`. CLDR keeps both because they
    // genuinely differ: a Slavic month name inside a date is genitive — "5 stycznia" —
    // and the same month named on its own is nominative, "styczeń". German has one form
    // for both, which is why the distinction looks redundant until it is not.
    const monthsWideStandalone = ordered(gregorian.months?.['stand-alone']?.wide, MONTH_KEYS)
    const monthsAbbrStandalone = ordered(
      gregorian.months?.['stand-alone']?.abbreviated, MONTH_KEYS)
    const daysWideStandalone = ordered(gregorian.days?.['stand-alone']?.wide, WEEKDAY_KEYS)
    const daysAbbrStandalone = ordered(
      gregorian.days?.['stand-alone']?.abbreviated, WEEKDAY_KEYS)

    if (!monthsWide || !monthsAbbr || !daysWide || !daysAbbr) {
      unmapped.push(code)
      continue
    }

    contributions[code] = {
      // Calendar order, unlike the bootstrap corpus, which stores both alphabetically --
      // invisible while every draw is random, and wrong the moment anything indexes them.
      'date.month.wide': monthsWide,
      'date.month.abbr': monthsAbbr,
      'date.weekday.wide': daysWide,
      'date.weekday.abbr': daysAbbr,
      ...(monthsWideStandalone ? { 'date.month.wide_context': monthsWideStandalone } : {}),
      ...(monthsAbbrStandalone ? { 'date.month.abbr_context': monthsAbbrStandalone } : {}),
      ...(daysWideStandalone ? { 'date.weekday.wide_context': daysWideStandalone } : {}),
      ...(daysAbbrStandalone ? { 'date.weekday.abbr_context': daysAbbrStandalone } : {}),
    }
  }

  return {
    contributions,
    stats: { locales: Object.keys(contributions).length, unmapped },
  }
}
