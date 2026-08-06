/**
 * Units of measurement as coherent `(name, symbol)` rows, from Unicode CLDR.
 *
 * Localized, unlike the periodic table: CLDR carries unit display names in every locale,
 * so a German corpus yields `Kilogramm / kg` rather than `kilograms / kg`.
 *
 * Fills:
 *   <each>  science.unit   composite (name, symbol)
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'si-units'
export const source = 'cldr-48'

function cldrCodeFor(code, overrides) {
  if (Object.hasOwn(overrides, code)) return overrides[code]
  return code.replaceAll('_', '-')
}

/**
 * CLDR's unit identifiers are prefixed by quantity (`length-meter`, `mass-kilogram`).
 *
 * A few families are excluded because they are not units anyone measures with: `10p-*`
 * are SI power-of-ten prefixes, `power-*` and `per-*` are compounding rules for building
 * derived units rather than units themselves.
 */
function isMeasurableUnit(key) {
  return (
    key.includes('-') &&
    !key.startsWith('10p') &&
    !key.startsWith('power') &&
    !key.startsWith('per')
  )
}

/**
 * Extracts the symbol from CLDR's narrow unit pattern.
 *
 * The narrow `displayName` is often still a word (`joule`, `watt`); the symbol lives in
 * the pattern that formats a value, as `{0}J` or `{0}W`. Stripping the placeholder is
 * what yields `J` and `W` rather than the spelled-out name.
 */
function symbolFrom(narrow) {
  const pattern = narrow?.['unitPattern-count-other'] ?? narrow?.['unitPattern-count-one']
  if (typeof pattern !== 'string') return null
  const symbol = pattern.replace('{0}', '').trim()
  return symbol === '' ? null : symbol
}

async function loadUnits(cldrCode, root) {
  const parts = cldrCode.split('-')
  for (let i = parts.length; i > 0; i--) {
    const candidate = parts.slice(0, i).join('-')
    try {
      const raw = await readFile(join(root, 'package', 'main', candidate, 'units.json'), 'utf8')
      return JSON.parse(raw).main[candidate].units
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
  return null
}

export async function run({ artifacts, locales, overrides }) {
  const contributions = {}
  const unmapped = []
  let unitCount = 0

  for (const code of locales) {
    const cldrCode = cldrCodeFor(code, overrides)
    if (cldrCode === null) continue

    const units = await loadUnits(cldrCode, artifacts.units)
    if (units === null) {
      unmapped.push(code)
      continue
    }

    const rows = []
    for (const key of Object.keys(units.long ?? {}).sort()) {
      if (!isMeasurableUnit(key)) continue
      const name = units.long[key]?.displayName
      const symbol = symbolFrom(units.narrow?.[key])
      // Both columns or neither, so `unit()["symbol"]` is never empty for some draws
      // and populated for others.
      if (!name || !symbol) continue
      rows.push({ name, symbol })
    }

    if (rows.length > 0) {
      contributions[code] = { 'science.unit': rows }
      unitCount = Math.max(unitCount, rows.length)
    }
  }

  return {
    contributions,
    stats: { units: unitCount, locales: Object.keys(contributions).length, unmapped },
  }
}
