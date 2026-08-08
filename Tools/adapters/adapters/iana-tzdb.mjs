/**
 * IANA time zone identifiers, from the tz database itself.
 *
 * Zone IDs are language-neutral, so they live in `base` where every locale reaches them.
 *
 * Fills:
 *   base    location.time_zone   -- `date.timeZone()` reads this path too
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iana-tzdb'
export const source = 'iana-tzdb'

/**
 * Parses the canonical zone list out of `zone1970.tab`.
 *
 * `zone1970.tab` rather than `zone.tab`: the latter retains zones kept only for
 * backward compatibility, and `backward` holds outright deprecated aliases such as
 * `US/Eastern` and `Asia/Calcutta`. Emitting those would produce fixtures naming zones
 * that the tz maintainers consider obsolete -- fine for parsing, wrong for generating.
 *
 * Format is tab-separated: country codes, coordinates, zone name, then optional
 * comments. Comment lines start with `#`.
 */
function parseZones(table) {
  const zones = new Set()
  for (const line of table.split('\n')) {
    if (line.startsWith('#') || line.trim() === '') continue
    const fields = line.split('\t')
    if (fields.length < 3) continue
    const name = fields[2].trim()
    if (name !== '') zones.add(name)
  }
  return [...zones].sort()
}

export async function run({ artifacts }) {
  const table = await readFile(join(artifacts.tzdata, 'zone1970.tab'), 'utf8')
  const zones = parseZones(table)

  if (zones.length === 0) {
    throw new Error('zone1970.tab parsed to zero zones — the format has changed')
  }

  return {
    // Both paths, because the corpus has carried them separately since faker and the
    // date and location namespaces each expose a timeZone(). Same data, one source.
    contributions: {
      base: {
        'location.time_zone': zones,
      },
    },
    stats: { zones: zones.length },
  }
}
