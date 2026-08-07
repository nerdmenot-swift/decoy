/**
 * Top-level domains, from the IANA root zone database.
 *
 * TLDs are language-neutral, so this lives in `base`.
 *
 * Fills:
 *   base    internet.domain_suffix
 */

import { readFile } from 'node:fs/promises'

export const id = 'iana-tld'
export const source = 'iana-tld'

/**
 * Internationalised TLDs are published in Punycode (`XN--P1AI` for `рф`).
 *
 * Kept, and kept in that form. A domain name containing the Unicode label is not what
 * DNS resolves or what a database column stores -- the A-label is the real value, and
 * decoding it would produce addresses that fail a round trip through any resolver.
 */
const PUNYCODE_PREFIX = 'XN--'

export async function run({ artifacts }) {
  const text = await readFile(artifacts.tlds, 'utf8')

  const lines = text.split('\n')
  // Reported, not asserted. IANA bumps this serial on every regeneration whether or not
  // a TLD changed, so failing on it would fail the build daily; the descriptor's digest
  // ignores the serial line and covers the delegations instead, which is the real check.
  const serial = lines[0]?.match(/^# Version (\d+)/)?.[1] ?? 'unknown'

  const suffixes = []
  let internationalised = 0
  for (const line of lines.slice(1)) {
    const tld = line.trim()
    if (tld === '' || tld.startsWith('#')) continue
    if (tld.startsWith(PUNYCODE_PREFIX)) internationalised += 1
    // Lower-cased: IANA publishes upper-case, but a domain suffix appears in a hostname,
    // and hostnames are conventionally lower-case wherever anyone stores one.
    suffixes.push(tld.toLowerCase())
  }

  if (suffixes.length < 500) {
    throw new Error(`root zone parsed to only ${suffixes.length} TLDs — the format has changed`)
  }

  return {
    contributions: {
      base: { 'internet.domain_suffix': suffixes.sort() },
    },
    stats: { tlds: suffixes.length, internationalised, serial },
  }
}
