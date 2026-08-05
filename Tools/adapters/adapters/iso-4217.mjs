/**
 * Currencies as coherent `(code, name, symbol)` rows, from Unicode CLDR.
 *
 * Restricted to currencies that are *currently legal tender*. CLDR carries the full
 * historical set, so an unfiltered pass would seed databases with Deutsche Marks and
 * Zimbabwean dollars -- plausible-looking data that no live system should ever contain.
 *
 * Fills:
 *   <each>  finance.currency   composite (code, name, symbol)
 *
 * KNOWN GAP: no `numericCode`. CLDR does not carry ISO 4217 numeric codes, and the
 * faker-derived corpus did. Nothing in Decoy reads the field -- `currency()` exposes
 * name, code and symbol -- but a caller reading the raw row will now get nothing for it.
 * Restoring it means a second source; see docs/corpus-strategy.md.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iso-4217'
export const source = 'cldr-48'

function cldrCodeFor(code, overrides) {
  if (Object.hasOwn(overrides, code)) return overrides[code]
  return code.replaceAll('_', '-')
}

/**
 * The currencies some region still uses as tender.
 *
 * CLDR models this as a per-region history of currency periods. A period with no `_to`
 * date has not ended, and `_tender: "false"` marks accounting-only units such as the
 * IMF's XDR, which are not money anyone can hold.
 */
function currentTender(currencyData) {
  const current = new Set()
  for (const periods of Object.values(currencyData.region)) {
    for (const period of periods) {
      for (const [code, info] of Object.entries(period)) {
        if (info._to === undefined && info._tender !== 'false') current.add(code)
      }
    }
  }
  return current
}

async function loadCurrencyNames(cldrCode, root) {
  const parts = cldrCode.split('-')
  for (let i = parts.length; i > 0; i--) {
    const candidate = parts.slice(0, i).join('-')
    try {
      const raw = await readFile(
        join(root, 'package', 'main', candidate, 'currencies.json'),
        'utf8',
      )
      return JSON.parse(raw).main[candidate].numbers.currencies
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
  return null
}

export async function run({ artifacts, locales, overrides }) {
  const currencyData = JSON.parse(
    await readFile(
      join(artifacts.core, 'package', 'supplemental', 'currencyData.json'),
      'utf8',
    ),
  ).supplemental.currencyData

  const tender = currentTender(currencyData)

  const contributions = {}
  const unmapped = []

  for (const code of locales) {
    const cldrCode = cldrCodeFor(code, overrides)
    if (cldrCode === null) continue

    const currencies = await loadCurrencyNames(cldrCode, artifacts.numbers)
    if (currencies === null) {
      unmapped.push(code)
      continue
    }

    const rows = [...tender]
      .filter((currency) => currencies[currency]?.displayName)
      .sort()
      .map((currency) => ({
        code: currency,
        name: currencies[currency].displayName,
        // Not every currency has a distinct symbol; CLDR falls back to the code itself,
        // which is what a user interface would show anyway.
        symbol: currencies[currency].symbol ?? currency,
      }))

    if (rows.length > 0) {
      contributions[code] = { 'finance.currency': rows }
    }
  }

  return {
    contributions,
    stats: {
      currencies: tender.size,
      locales: Object.keys(contributions).length,
      unmapped,
    },
  }
}
