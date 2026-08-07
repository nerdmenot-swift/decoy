/**
 * Airports as coherent `(name, iataCode)` rows.
 *
 * Language-neutral — airport names are proper nouns and IATA codes are identifiers — so
 * this lives in `base`.
 *
 * Fills:
 *   base    airline.airport   composite (name, iataCode)
 *
 * A composite for the usual reason: drawn apart you get Heathrow labelled `JFK`. Only
 * airports are sourced here. `airline.airline` and `airline.airplane` stay faker-derived
 * because airline and aircraft names are trademarks with no permissive registry behind
 * them, which is also why this namespace was cut from v1 in the first place.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'airports'
export const source = 'airport-data'

export async function run({ artifacts }) {
  const raw = JSON.parse(
    await readFile(join(artifacts.airports, 'package', 'airports.json'), 'utf8'),
  )
  const entries = Array.isArray(raw) ? raw : Object.values(raw)

  const rows = []
  let withoutCode = 0

  for (const airport of entries) {
    // OpenFlights records airports with no IATA assignment as `\N` or an empty string.
    // A three-letter code is the whole point of the field, so those are dropped rather
    // than emitted with a blank that no validator would accept.
    if (!airport.name || !/^[A-Z]{3}$/.test(airport.iata ?? '')) {
      withoutCode += 1
      continue
    }
    rows.push({ name: String(airport.name), iataCode: airport.iata })
  }

  rows.sort((a, b) => (a.iataCode < b.iataCode ? -1 : 1))

  if (rows.length < 3000) {
    throw new Error(`airport-data yielded only ${rows.length} coded airports — schema changed`)
  }

  return {
    contributions: {
      base: { 'airline.airport': rows },
    },
    stats: { airports: rows.length, withoutIataCode: withoutCode },
  }
}
