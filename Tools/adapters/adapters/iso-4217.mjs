/**
 * Currencies as coherent `(code, name, symbol, numericCode)` rows.
 *
 * Restricted to currencies that are *currently legal tender*. CLDR carries the full
 * historical set, so an unfiltered pass would seed databases with Deutsche Marks and
 * Zimbabwean dollars -- plausible-looking data that no live system should ever contain.
 *
 * Fills:
 *   <each>  finance.currency   composite (code, name, symbol, numericCode)
 *
 * Two sources: CLDR decides which currencies exist and supplies their localized names
 * and symbols; the ISO 4217 registry supplies the numeric codes, which CLDR does not
 * carry. The registry alone would give English names and no symbols, and CLDR alone
 * would give no numeric codes.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'iso-4217'
export const sources = ['cldr-48', 'iso-4217-six']

/** CLDR defines the currency set and every localized string, so it is credited. */
export const attributeTo = 'cldr-48'

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

/**
 * Reads `(alphabetic, numeric)` pairs out of the ISO 4217 registry XML.
 *
 * Matched with a regex rather than a parser: the document is a flat list of `CcyNtry`
 * elements with no attributes, nesting or namespaces on the fields being read, so a
 * parser would be a dependency bought for nothing. The structural assertions below are
 * what make that safe -- if SIX ever restructures the file, this fails loudly instead of
 * silently yielding an empty mapping.
 */
function parseRegistry(xml, expectedVersion) {
  const published = xml.match(/Pblshd="([^"]+)"/)?.[1]
  if (published !== expectedVersion) {
    throw new Error(
      `ISO 4217 registry declares Pblshd="${published}" but the source descriptor pins ` +
        `${expectedVersion}. Upstream republished; verify the change and re-pin.`,
    )
  }

  const numericFor = {}
  for (const entry of xml.split('<CcyNtry>').slice(1)) {
    const code = entry.match(/<Ccy>([A-Z]{3})<\/Ccy>/)?.[1]
    const numeric = entry.match(/<CcyNbr>(\d{1,3})<\/CcyNbr>/)?.[1]
    // Entries without a code are the "no universal currency" placeholders (Antarctica).
    if (!code || !numeric) continue
    numericFor[code] = numeric.padStart(3, '0')
  }

  if (Object.keys(numericFor).length < 100) {
    throw new Error(
      `ISO 4217 registry yielded only ${Object.keys(numericFor).length} codes — ` +
        `the document structure has changed`,
    )
  }
  return numericFor
}

export async function run({ artifacts, locales, overrides }) {
  const registryVersion = JSON.parse(
    await readFile(new URL('../sources/iso-4217-six.json', import.meta.url), 'utf8'),
  ).version
  const numericFor = parseRegistry(
    await readFile(artifacts.list, 'utf8'),
    registryVersion,
  )

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
        // Empty rather than omitted for the handful the registry has not assigned, so
        // the composite keeps one shape and callers do not get a column that exists on
        // some rows and not others.
        numericCode: numericFor[currency] ?? '',
      }))

    if (rows.length > 0) {
      contributions[code] = { 'finance.currency': rows }
    }
  }

  return {
    contributions,
    stats: {
      currencies: tender.size,
      withNumericCode: [...tender].filter((c) => numericFor[c]).length,
      locales: Object.keys(contributions).length,
      unmapped,
    },
  }
}
