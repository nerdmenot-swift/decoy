/**
 * Chemical elements as coherent `(atomicNumber, name, symbol)` rows.
 *
 * A composite for the usual reason: drawn independently you get atomic number 6 named
 * Helium with the symbol Fe. Elements are facts, so generating one would be a bug —
 * exactly the case corpus-strategy.md says to source rather than model.
 *
 * Element names do translate, and CLDR does not carry them. English names are used for
 * every locale, which is a real gap rather than a decision: `location.country` is
 * properly localized and this is not.
 *
 * Fills:
 *   base    science.chemical_element   composite (atomicNumber, name, symbol)
 */

import { readFile } from 'node:fs/promises'

export const id = 'periodic-table'
export const source = 'pubchem'

export async function run({ artifacts }) {
  const table = JSON.parse(await readFile(artifacts.table, 'utf8')).Table

  const columns = table.Columns.Column
  const index = (name) => {
    const position = columns.indexOf(name)
    if (position < 0) {
      throw new Error(`PubChem response has no '${name}' column — the schema has changed`)
    }
    return position
  }

  const atomicNumber = index('AtomicNumber')
  const symbol = index('Symbol')
  const name = index('Name')

  const rows = table.Row.map((row) => ({
    atomicNumber: String(row.Cell[atomicNumber]),
    name: String(row.Cell[name]),
    symbol: String(row.Cell[symbol]),
  })).sort((a, b) => Number(a.atomicNumber) - Number(b.atomicNumber))

  // 118 named elements as of IUPAC's 2016 additions. Fewer means a truncated response;
  // more means something was added and the corpus should be reviewed rather than
  // silently extended.
  if (rows.length !== 118) {
    throw new Error(`expected 118 elements, got ${rows.length} — verify before re-pinning`)
  }

  return {
    contributions: {
      base: { 'science.chemical_element': rows },
    },
    stats: { elements: rows.length },
  }
}
