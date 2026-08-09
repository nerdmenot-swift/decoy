/**
 * Company legal forms per jurisdiction, from the ISO 20275 register.
 *
 * Fills:
 *   <each>  company.legal_entity_type   GmbH, AG, SARL, Pty Ltd, ...
 *
 * The list is keyed by country *and* language, which is what makes it better than the
 * hand-curated one it replaces rather than merely differently licensed. Austrian company
 * law is not German company law: `de_AT` gets `OG` and `GesbR`, `de_CH` gets the Swiss
 * forms, and `de` gets `GmbH` and `OHG`. No curated list had drawn that distinction, and
 * every German-speaking locale previously shared one set.
 *
 * ## Abbreviations only, and short ones
 *
 * The register carries both `Gesellschaft mit beschraenkter Haftung` and `GmbH`. The
 * abbreviation is what belongs in a generated company name -- `Fischer GmbH` is what a
 * German company is called, and `Fischer Gesellschaft mit beschraenkter Haftung` is what
 * its articles of association say.
 *
 * So a form with no abbreviation is skipped rather than falling back to its full name, and
 * anything long is dropped. Both rules follow from what this path is for. It is the suffix
 * in `{{person.lastName}} {{company.legal_entity_type}}`, and a suffix that does not fit
 * on a letterhead is not one: `Cantonal administration` and `A Benefit Corporation` are
 * real entries and neither is how a company signs its name.
 *
 * ## A caveat the register does not let us fix
 *
 * ISO 20275 records legal forms, and for some jurisdictions those include bodies of public
 * law. Switzerland lists `Canton`, `Commune` and `Bund` alongside `AG` and `GmbH`, and
 * there is no column distinguishing them -- the file carries no category, only the form,
 * its language and its status. So a Swiss fixture can occasionally read `Meier Bezirk`.
 * Left alone deliberately: separating them would mean hand-maintaining a list of which
 * entries are really companies, which is the curation this source exists to stop doing.
 *
 * ## Why inactive forms are dropped
 *
 * The register marks each form ACTV or INAC, the latter being forms that no longer exist --
 * abolished by a reform, or superseded. A fixture naming a company as a legal form its
 * jurisdiction has retired is the kind of wrongness nobody notices until a lawyer reads it.
 */

import { readFile } from 'node:fs/promises'

export const id = 'legal-entities'
export const sources = ['gleif-elf', 'cldr-48']
export const attributeTo = 'gleif-elf'

/**
 * A minimal RFC 4180 reader.
 *
 * The register quotes fields containing commas and semicolons, and doubles interior
 * quotes, so a `split(',')` would tear rows apart at the first legal form with a comma in
 * its name. Written here rather than taken as a dependency for the same reason the rest of
 * this directory has none.
 */
function parseCSV(text) {
  const rows = []
  let row = []
  let field = ''
  let quoted = false

  for (let i = 0; i < text.length; i++) {
    const character = text[i]
    if (quoted) {
      if (character === '"') {
        if (text[i + 1] === '"') {
          field += '"'
          i += 1
        } else {
          quoted = false
        }
      } else {
        field += character
      }
      continue
    }
    if (character === '"') quoted = true
    else if (character === ',') {
      row.push(field)
      field = ''
    } else if (character === '\n') {
      row.push(field)
      rows.push(row)
      row = []
      field = ''
    } else if (character !== '\r') field += character
  }
  if (field !== '' || row.length > 0) {
    row.push(field)
    rows.push(row)
  }
  return rows
}

function regionFor(code, likelySubtags) {
  for (const segment of code.split('_').slice(1)) {
    if (/^[A-Z]{2}$/.test(segment)) return segment
  }
  const language = code.split('_')[0]
  const region = likelySubtags[language]?.split('-').at(-1)
  return /^[A-Z]{2}$/.test(region ?? '') ? region : null
}

/**
 * Below this a locale keeps what it had.
 *
 * A jurisdiction with one legal form would put the same suffix on every company in a
 * fixture set. Two is enough to vary; below that the register has recorded a country
 * thinly rather than described one.
 */
const MINIMUM_FORMS = 2

/**
 * Longer than this is a description rather than a suffix.
 *
 * Twelve characters keeps `Ges.m.b.H.`, `FlexKapG` and `Pty Ltd`, and drops
 * `Limited Liability Partnership` -- which is a real English legal form whose suffix is
 * `LLP`, already in the list beside it.
 */
const MAXIMUM_LENGTH = 12

/** An initial run of two to six capitals, used only where the abbreviation column is empty. */
const LEADING_ABBREVIATION = /^([\p{Lu}][\p{Lu}.]{1,5})(?=\s|$)/u

export async function run({ artifacts, locales }) {
  const likelySubtags = JSON.parse(
    await readFile(
      new URL('file://' + artifacts.core + '/package/supplemental/likelySubtags.json'),
      'utf8',
    ),
  ).supplemental.likelySubtags

  const rows = parseCSV(await readFile(artifacts.list, 'utf8'))
  const header = rows[0]
  const column = (name) => {
    const index = header.findIndex((h) => h === name || h.startsWith(name))
    if (index < 0) throw new Error(`gleif-elf: no '${name}' column — the schema has changed`)
    return index
  }
  const COUNTRY = column('Country Code (ISO 3166-1)')
  const LANGUAGE = column('Language Code (ISO 639-1)')
  const NAME = column('Entity Legal Form name Local name')
  const ABBREVIATIONS = column('Abbreviations Local language')
  const STATUS = column('ELF Status')

  // (country, language) -> the forms recorded for it.
  const byJurisdiction = new Map()
  for (const row of rows.slice(1)) {
    if (row[STATUS] !== 'ACTV') continue
    const country = row[COUNTRY]?.trim()
    const language = row[LANGUAGE]?.trim().toLowerCase()
    if (!country || !language) continue

    // Several abbreviations per form, separated by semicolons, and each is a real way of
    // writing it -- `KG`, `GmbH & Co. KG` and `Stiftung & Co. KG` are all Kommanditgesell-
    // schaften. Interior quotes survive the register's own quoting and are stripped.
    const declared = (row[ABBREVIATIONS] ?? '')
      .split(';')
      .map((value) => value.replaceAll('"', '').trim())
      .filter(Boolean)
    let forms = declared.filter(
      (value) => value.length >= 2 && value.length <= MAXIMUM_LENGTH,
    )

    // A one-character abbreviation is registry shorthand, not a suffix. Japan records 株
    // for 株式会社 and 有 for 有限会社, which is how a form is marked in the commercial
    // register; a Japanese company is 丸野情報株式会社 and never 丸野情報株. So where the
    // register offers only that, the full name is what goes on the sign.
    //
    // Keyed on a short abbreviation *being present*, not on the column being empty, and
    // the difference matters. An empty column means the form has no suffix at all, and
    // falling back to the name there fills French with `Congrégation`, `Ministére` and
    // `Métropole` -- entity categories that no company appends to itself. Reaching for the
    // name only when the register has shown its shorthand keeps Japan and leaves France
    // with the seven real abbreviations it had.
    if (forms.length === 0 && declared.some((value) => value.length === 1)) {
      const name = (row[NAME] ?? '').trim()
      if (name.length >= 2 && name.length <= MAXIMUM_LENGTH) forms = [name]
    }

    // France leaves the abbreviation column empty on almost all of its 255 forms and puts
    // the abbreviation at the front of the name instead -- `SARL d'attribution`,
    // `SA nationale à conseil d'administration`. Without this, France ships five forms and
    // not one of them is SARL, which is the form most French companies actually take.
    //
    // Deliberately narrow: an initial run of capitals, two to six of them. It recovers
    // `SA`, `SARL` and `SCP`, and leaves `Syndicat de salariés` and `Autre société civile`
    // alone because those lead with a word rather than an abbreviation. Checked against
    // Spain, Italy, Portugal and the Netherlands, where it fires on nothing at all -- they
    // populate the column properly, so there is nothing for it to find.
    if (forms.length === 0) {
      const leading = LEADING_ABBREVIATION.exec((row[NAME] ?? '').trim())
      if (leading) forms = [leading[1]]
    }
    if (forms.length === 0) continue

    const key = `${country} ${language}`
    if (!byJurisdiction.has(key)) byJurisdiction.set(key, new Set())
    for (const form of forms) byJurisdiction.get(key).add(form)
  }

  if (byJurisdiction.size < 50) {
    throw new Error(
      `gleif-elf yielded ${byJurisdiction.size} jurisdictions — verify before re-pinning`,
    )
  }

  const contributions = {}
  const taken = []
  const unmatched = []

  for (const code of locales) {
    if (code === 'base') continue
    const region = regionFor(code, likelySubtags)
    const language = code.split('_')[0]
    if (!region) continue

    const forms = byJurisdiction.get(`${region} ${language}`)
    if (!forms || forms.size < MINIMUM_FORMS) {
      unmatched.push(`${code}(${region})`)
      continue
    }
    contributions[code] = { 'company.legal_entity_type': [...forms].sort() }
    taken.push(`${code}(${forms.size})`)
  }

  return {
    contributions,
    stats: { jurisdictions: byJurisdiction.size, locales: taken.length, taken, unmatched },
  }
}
