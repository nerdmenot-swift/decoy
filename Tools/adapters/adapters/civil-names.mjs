/**
 * Given names from national civil registries, with real population frequencies.
 *
 * Fills:
 *   <each>  person.first_name.female   weighted by how many people bear each
 *   <each>  person.first_name.male     likewise
 *
 * The one adapter that has to scale by country rather than by locale. Every other source
 * here is one dataset covering the world — CLDR, IANA, GeoNames — because the thing it
 * describes is global. Given names are not: they are recorded by whoever registers births
 * in a jurisdiction, published under that jurisdiction's open-data terms, in that
 * jurisdiction's file format. There is no world registry of names and there is not going
 * to be one.
 *
 * So this is a table of countries and a parser per format, and adding a country is a
 * descriptor plus an entry below. That is the honest cost of replacing faker's names, and
 * writing the mechanism once is the only part of it that gets cheaper.
 *
 * ## What is deliberately not done
 *
 * **Surnames, almost never.** France publishes given names openly and surnames only
 * commercially, and that pattern repeats: birth registers are public record, family-name
 * frequencies usually are not. Sweden is the one exception found — SCB publishes 411,802
 * family names with counts — so the adapter handles them where a register has them and
 * expects not to find them.
 *
 * **Never a list of identifiable people.** A register counts how many people hold a name;
 * a roster names them. The distinction matters more here than almost anywhere, because
 * `lastName()` exists alongside a generator whose entire purpose is returning surnames no
 * real person is recorded as having — a fixture set that escapes onto a screenshot or a
 * support ticket should not be naming somebody.
 *
 * It has to be said explicitly because the tempting sources are exactly the wrong ones.
 * Election candidate registers, company director filings and academic author lists are
 * open, machine-readable, often CC BY, and full of names — and every one of them is a list
 * of real people, usually public figures, frequently attached to a political affiliation.
 * Pakistan's Gallup election database was offered for `ur` on precisely those grounds and
 * refused on this one. What is wanted is the count without the roster.
 *
 * **Never a transliteration where the locale expects its own script.** `ur` writes
 * `اقدس`, not `Aqdas`. Serbian is converted because Serbia is officially digraphic and the
 * alphabets are a bijection; Urdu, Russian and Bulgarian romanisations are one convention
 * among several, and picking one is authoring rather than reading.
 *
 * **Year is discarded.** The files carry a name's count per birth year, which would give
 * `firstName(bornIn: 1950)` — a genuinely better generator and a different feature. The
 * counts are summed across every year instead.
 *
 * **What the weights describe differs by country, and cannot be made uniform.** Spain,
 * Poland, Finland and Sweden count the living population; the UK counts babies named over
 * thirty years, because that is what the ONS publishes. So British weights describe who is
 * under thirty and Spanish ones describe everybody. Both are the best available for their
 * country, and pretending otherwise would mean discarding one.
 */

import { readFile, readdir } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

import { readWorkbook } from '../lib/xlsx.mjs'

export const id = 'civil-names'
export const sources = [
  'insee-prenoms',
  'gender-by-name',
  'pesel-imiona',
  'ine-nombres',
  'dvv-etunimet',
  'scb-namn',
  'ons-baby-names',
  'ssb-fornavn',
  'surs-imena',
  'az-adlar',
  'moi-surnames',
  'cbs-shemot',
]

/**
 * Names borne by fewer than this many people since 1900 are dropped.
 *
 * The same reasoning as the Census surname threshold, and a different number because the
 * populations differ. INSEE publishes down to three bearers; keeping that tail would be
 * 39,331 names, most of them a spelling somebody's registrar accepted once, and a
 * weighted draw would reach them about never. At 200 it keeps 9,243 names — twenty times
 * what faker had for French — and the weights among them are exactly INSEE's.
 */
const MINIMUM_BEARERS = 200

/**
 * One entry per country: which locales it serves, and how to read its file.
 *
 * `parse` returns `[{ name, sex, count }]`. Keeping the format knowledge next to the
 * country rather than in a shared CSV reader is deliberate — the next registry will
 * delimit differently, spell its columns differently and mark its residual bucket
 * differently, and a general reader would grow a flag for each.
 */
const REGISTRIES = [
  {
    country: 'EN',
    locales: ['en'],
    source: 'gender-by-name',
    // Not `names`: two sources cannot both name an artifact the same thing, since an
    // adapter receives them in one flat map.
    artifact: 'english',
    /**
     * `Name,Gender,Count,Probability`, one row per name, already aggregated across the
     * four countries and every year. `M` and `F`.
     *
     * The header carries a UTF-8 byte order mark, which turns the first column name into
     * something that does not compare equal to `Name` — a classic way to read a CSV as
     * empty and conclude the schema changed.
     */
    parse(text) {
      const lines = text.replace(/^\uFEFF/, '').split('\n')
      const header = lines[0]?.trim()
      if (header !== 'Name,Gender,Count,Probability') {
        throw new Error(`Gender-by-Name header is '${header}' — the schema has changed`)
      }
      const rows = []
      for (const line of lines.slice(1)) {
        const [name, gender, count] = line.split(',')
        if (!name) continue
        const bearers = Number(count)
        if (!Number.isFinite(bearers) || bearers <= 0) continue
        const sex = gender === 'M' ? 'male' : gender === 'F' ? 'female' : null
        if (sex) rows.push({ name, sex, count: bearers })
      }
      return rows
    },
  },
  {
    country: 'AZ',
    locales: ['az'],
    source: 'az-adlar',
    files: ['azerbaijani-names'],
    format: 'json',
    // A register of permitted names, not a count of bearers. See `applyRegistry`.
    weighted: false,
    minimumRows: 2000,
    /**
     * The Ministry of Justice's list of names that may be registered, each with an
     * etymology. `kişi` is male and `qadın` female.
     *
     * Given names and surnames share the file and are told apart by the etymology, which
     * opens `familiya,` for a family name. That is a prose field being used as a flag,
     * which is fragile -- so the count of each is asserted below rather than trusted, and a
     * change in how the Ministry writes its descriptions fails the build instead of
     * silently reclassifying 1,385 surnames as given names.
     *
     * Two spellings of one name are written `Abbas // Abas`, and feminine surname forms as
     * `Abbasov (a)`. The first variant is taken and the suffix marker dropped; keeping
     * either would put punctuation in a fixture.
     */
    parse(text) {
      const records = JSON.parse(text)
      if (!Array.isArray(records)) throw new Error('AZ register is not a JSON array')
      const rows = []
      let surnames = 0
      for (const record of records) {
        const raw = record.personName ?? ''
        const name = raw.split('//')[0].replace(/\(.*?\)/g, '').trim()
        if (!name) continue
        const isSurname = /familiya/i.test(record.meaningOfName ?? '')
        if (isSurname) surnames += 1
        const sex = isSurname
          ? 'surname'
          : record.gender === 'kişi'
            ? 'male'
            : record.gender === 'qadın'
              ? 'female'
              : null
        if (sex) rows.push({ name, sex, count: 1 })
      }
      if (surnames < 500) {
        throw new Error(
          `AZ register flagged only ${surnames} rows as 'familiya' — the description ` +
            `wording has changed and surnames are being read as given names`,
        )
      }
      return rows
    },
  },
  {
    country: 'TW',
    locales: ['zh_TW'],
    source: 'moi-surnames',
    files: ['taiwanese-surnames'],
    // 441 surnames clear the threshold, and that is the whole truth rather than a
    // truncation: Chinese surnames are a closed set of a few hundred covering nearly
    // everybody. 陳 alone is held by 2.6 million people.
    minimumRows: 300,
    /**
     * `年度,ranking,lastname,age,人口數` -- one row per surname per age bracket, so the
     * brackets are summed to get the population holding each name.
     *
     * Surnames only. Taiwan publishes given-name statistics as a 376-page PDF whose fonts
     * carry no usable ToUnicode mapping, so it extracts as mojibake; `zh_TW` given names
     * stay where they were.
     */
    parse(text) {
      const lines = text.replace(/^\uFEFF/, '').split('\n')
      const header = lines[0]?.trim()
      if (!header?.includes('lastname') || !header.includes('人口數')) {
        throw new Error(`MOI header is '${header}' — the schema has changed`)
      }
      const totals = new Map()
      for (const line of lines.slice(1)) {
        const parts = line.split(',')
        if (parts.length < 5) continue
        const name = parts[2]?.trim()
        const people = Number(parts[4])
        if (!name || !Number.isFinite(people) || people <= 0) continue
        totals.set(name, (totals.get(name) ?? 0) + people)
      }
      return [...totals].map(([name, count]) => ({ name, sex: 'surname', count }))
    },
  },
  {
    country: 'IL',
    locales: ['he'],
    source: 'cbs-shemot',
    files: ['israeli-names'],
    format: 'xlsx',
    /**
     * Eight sheets, one per sex and population group, each `given name | total | <year>...`
     * for births from 1949 to 2024. Only the total is read.
     *
     * All four population groups are merged rather than only the largest. The locale is the
     * Hebrew language, and a Hebrew-language database in Israel holds the names of everyone
     * in Israel -- so merging is what makes the distribution true, and taking one group
     * would be a choice about who counts.
     *
     * `..` marks a value the CBS withholds, and parses to NaN, which the numeric guard
     * drops.
     */
    parse(bytes) {
      const sheets = readWorkbook(bytes)
      const rows = []
      let seen = 0
      for (const [sheet, table] of Object.entries(sheets)) {
        // Sheet names are Hebrew and carry the sex: בנות is girls, בנים boys.
        const sex = sheet.startsWith('בנות') ? 'female' : sheet.startsWith('בנים') ? 'male' : null
        if (!sex) continue
        const header = table.findIndex((row) => row[0] === 'prati1')
        if (header < 0) continue
        seen += 1
        for (const row of table.slice(header + 1)) {
          const name = row[0]?.trim()
          const total = Number(row[1])
          if (!name || !Number.isFinite(total) || total <= 0) continue
          rows.push({ name, sex, count: total })
        }
      }
      if (seen !== 8) {
        throw new Error(`CBS workbook had ${seen} name sheets, expected 8 — the shape has changed`)
      }
      return rows
    },
  },
  {
    country: 'NO',
    locales: ['nb_NO'],
    source: 'ssb-fornavn',
    // Neither an artifact nor a file: PxWeb answers a POST, so there is nothing to pin.
    // `fetch-statistics-names.mjs` runs by hand and its output is committed.
    committed: 'NO',
  },
  {
    country: 'SI',
    locales: ['sl_SI'],
    source: 'surs-imena',
    committed: 'SI',
  },
  {
    country: 'FI',
    locales: ['fi'],
    source: 'dvv-etunimet',
    files: ['finnish-names'],
    format: 'xlsx',
    /**
     * Six sheets: `kaikki` is every given name a person holds, `ens` only those held as
     * the *first* given name, `muut` the rest. `Etunimi | Lukumäärä`.
     *
     * `ens` is the one that matches what `firstName()` means. Finns commonly carry several
     * given names and go by one of them, so the two sheets disagree sharply: `Juhani` tops
     * `kaikki` with 270,972 and does not top `ens` at all, because it is overwhelmingly a
     * second name. Taking `kaikki` would make Juhani the most common Finnish first name,
     * which it is not.
     */
    parse(bytes) {
      const sheets = readWorkbook(bytes)
      const rows = []
      for (const [sheet, sex] of [['Miehet ens', 'male'], ['Naiset ens', 'female']]) {
        const table = sheets[sheet]
        if (!table) throw new Error(`DVV workbook has no '${sheet}' sheet — the shape has changed`)
        const header = table.findIndex((row) => row[0] === 'Etunimi')
        if (header < 0) throw new Error(`DVV '${sheet}' has no 'Etunimi' header row`)
        for (const row of table.slice(header + 1)) {
          const name = row[0]?.trim()
          const bearers = Number(row[1])
          if (!name || !Number.isFinite(bearers) || bearers <= 0) continue
          rows.push({ name, sex, count: bearers })
        }
      }
      return rows
    },
  },
  {
    country: 'SE',
    locales: ['sv'],
    source: 'scb-namn',
    files: ['swedish-names'],
    format: 'xlsx',
    /**
     * The only register here that publishes family names, and the reason this adapter
     * handles surnames at all: `Efternamn` carries 411,802 of them with counts.
     *
     * Given names come from `Tilltalsnamn` rather than `Förnamn` for the same reason
     * Finland uses `ens`. A *tilltalsnamn* is the given name a person is actually
     * addressed by, where `Förnamn` counts every given name they hold.
     */
    parse(bytes) {
      const sheets = readWorkbook(bytes)
      const rows = []
      const sources = [
        ['Tilltalsnamn män', 'male', 'Tilltalsnamn'],
        ['Tilltalsnamn kvinnor', 'female', 'Tilltalsnamn'],
        ['Efternamn', 'surname', 'Efternamn'],
      ]
      for (const [sheet, sex, headerCell] of sources) {
        const table = sheets[sheet]
        if (!table) throw new Error(`SCB workbook has no '${sheet}' sheet — the shape has changed`)
        const header = table.findIndex((row) => row[0] === headerCell)
        if (header < 0) throw new Error(`SCB '${sheet}' has no '${headerCell}' header row`)
        for (const row of table.slice(header + 1)) {
          const name = row[0]?.trim()
          const bearers = Number(row[1])
          if (!name || !Number.isFinite(bearers) || bearers <= 0) continue
          rows.push({ name, sex, count: bearers })
        }
      }
      return rows
    },
  },
  {
    country: 'GB',
    locales: ['en_GB'],
    source: 'ons-baby-names',
    files: ['uk-names'],
    format: 'xlsx',
    /**
     * `Table_1` girls and `Table_2` boys, each `Name` followed by a rank and a count per
     * year from 2025 back to 1996. Counts are summed across every year.
     *
     * A birth cohort rather than a living population, and worth stating because the other
     * registers here are not. These are the babies named in England and Wales over thirty
     * years, so the weights describe who is under thirty rather than who is alive — which
     * is the right shape for most fixtures and the wrong one for a pensions dataset.
     *
     * Counts of one or two are redacted as `[x]` under the FOI personal-information
     * exemption, and parse to `NaN`, which the numeric guard drops.
     */
    parse(bytes) {
      const sheets = readWorkbook(bytes)
      const rows = []
      for (const [sheet, sex] of [['Table_1', 'female'], ['Table_2', 'male']]) {
        const table = sheets[sheet]
        if (!table) throw new Error(`ONS workbook has no '${sheet}' sheet — the shape has changed`)
        const header = table.findIndex((row) => row[0] === 'Name')
        if (header < 0) throw new Error(`ONS '${sheet}' has no 'Name' header row`)
        // Every column headed `<year> Count`. Found by name rather than by taking every
        // other column, so a future edition inserting one does not silently sum ranks.
        const columns = table[header]
          .map((label, index) => (/^\d{4} Count$/.test(label ?? '') ? index : -1))
          .filter((index) => index >= 0)
        if (columns.length === 0) throw new Error(`ONS '${sheet}' has no '<year> Count' columns`)

        for (const row of table.slice(header + 1)) {
          const name = row[0]?.trim()
          if (!name) continue
          let total = 0
          for (const index of columns) {
            const count = Number(row[index])
            if (Number.isFinite(count)) total += count
          }
          if (total > 0) rows.push({ name, sex, count: total })
        }
      }
      return rows
    },
  },
  {
    country: 'ES',
    locales: ['es'],
    source: 'ine-nombres',
    files: ['spanish-names'],
    format: 'xlsx',
    /**
     * Two sheets, `Hombres` and `Mujeres`, each `Orden | Nombre | Frecuencia | Edad Media`
     * over the population census. Names borne by fewer than twenty people nationally are
     * already excluded upstream.
     *
     * The header row is found rather than assumed, because it is not in the same place in
     * both sheets -- row seven in `Hombres` and row six in `Mujeres`, the men's sheet
     * carrying one extra line of preamble. Counting to a fixed row reads a title as a
     * column heading and then silently drops the first name.
     *
     * `Edad Media` is the mean age of everyone with the name, and is ignored here for the
     * same reason INSEE's year column is: it would give `firstName(bornIn:)`, which is a
     * different feature.
     */
    parse(bytes) {
      const sheets = readWorkbook(bytes)
      const rows = []
      for (const [sheet, sex] of [['Hombres', 'male'], ['Mujeres', 'female']]) {
        const table = sheets[sheet]
        if (!table) throw new Error(`INE workbook has no '${sheet}' sheet — the shape has changed`)
        const header = table.findIndex((row) => row[0] === 'Orden' && row[1] === 'Nombre')
        if (header < 0) throw new Error(`INE '${sheet}' has no 'Orden | Nombre' header row`)
        for (const row of table.slice(header + 1)) {
          const name = row[1]?.trim()
          const bearers = Number(row[2])
          if (!name || !Number.isFinite(bearers) || bearers <= 0) continue
          rows.push({ name, sex, count: bearers })
        }
      }
      return rows
    },
  },
  {
    country: 'PL',
    locales: ['pl'],
    source: 'pesel-imiona',
    // Plain CSVs rather than a zip, and one per sex, so `files` instead of `artifact`.
    files: ['polish-male', 'polish-female'],
    /**
     * `IMIĘ_PIERWSZE,PŁEĆ,LICZBA_WYSTĄPIEŃ`, already aggregated: one row per name, with
     * how many people in the PESEL register bear it. `MĘŻCZYZNA` is male and `KOBIETA`
     * female.
     *
     * The sex is taken from the column rather than from which file the row came in.
     * The two are consistent today, and reading the column means they cannot silently
     * stop being consistent -- the register publishes the split for convenience, not as
     * the authoritative statement.
     */
    parse(text) {
      const lines = text.replace(/^﻿/, '').split('\n')
      const header = lines[0]?.trim()
      if (header !== 'IMIĘ_PIERWSZE,PŁEĆ,LICZBA_WYSTĄPIEŃ') {
        throw new Error(`PESEL header is '${header}' — the schema has changed`)
      }
      const rows = []
      for (const line of lines.slice(1)) {
        const [name, plec, count] = line.trim().split(',')
        if (!name) continue
        const bearers = Number(count)
        if (!Number.isFinite(bearers) || bearers <= 0) continue
        const sex = plec === 'MĘŻCZYZNA' ? 'male' : plec === 'KOBIETA' ? 'female' : null
        if (sex) rows.push({ name, sex, count: bearers })
      }
      return rows
    },
  },
  {
    country: 'FR',
    locales: ['fr'],
    source: 'insee-prenoms',
    artifact: 'names',
    /**
     * `sexe;preusuel;annais;nombre`, semicolon-delimited, one row per name per year.
     * `1` is male and `2` is female. Rows whose name begins with `_` are INSEE's
     * residual buckets — `_PRENOMS_RARES` is "every rare name", not a name.
     */
    parse(text) {
      const totals = new Map()
      const lines = text.split('\n')
      const header = lines[0]?.trim()
      if (header !== 'sexe;preusuel;annais;nombre') {
        throw new Error(`INSEE header is '${header}' — the schema has changed`)
      }
      for (const line of lines.slice(1)) {
        const [sexe, name, , count] = line.split(';')
        if (!name || name.startsWith('_')) continue
        const bearers = Number(count)
        if (!Number.isFinite(bearers) || bearers <= 0) continue
        const sex = sexe === '1' ? 'male' : sexe === '2' ? 'female' : null
        if (!sex) continue
        const key = `${sex} ${name}`
        totals.set(key, (totals.get(key) ?? 0) + bearers)
      }
      return [...totals].map(([key, count]) => {
        const [sex, name] = key.split(' ')
        return { name, sex, count }
      })
    },
  },
]

/**
 * Registries publish names in upper case; nobody stores them that way.
 *
 * Capitalises after each hyphen, apostrophe and space, so `JEAN-PIERRE` and `MARIE
 * THÉRÈSE` come back right rather than as `Jean-pierre`. Locale-aware lower-casing is
 * used because `İ` exists and `String.toLowerCase()` alone gets Turkish wrong — not a
 * problem for France, and one that would be waiting for whoever adds Turkey.
 */
/**
 * A Decoy locale code as a language tag `toLocaleLowerCase` will accept.
 *
 * Decoy separates subtags with underscores and BCP 47 with hyphens, so `en_GB` throws
 * `RangeError: Invalid language tag` -- which nothing noticed until the UK became the
 * first registry to serve a locale with a region in its name. Decoy also carries subtags
 * BCP 47 has no idea about, `en_AU_ocker` and `uz_UZ_latin` among them, so an invalid tag
 * falls back to the bare language rather than failing: casing rules are per language, and
 * Turkish `İ` is the reason this is locale-aware at all.
 */
function languageTag(code) {
  const tag = code.replaceAll('_', '-')
  try {
    ''.toLocaleLowerCase(tag)
    return tag
  } catch {
    return code.split('_')[0]
  }
}

function titleCase(name, locale) {
  const tag = languageTag(locale)
  let out = ''
  let atBoundary = true
  for (const character of name.toLocaleLowerCase(tag)) {
    out += atBoundary ? character.toLocaleUpperCase(tag) : character
    atBoundary = character === '-' || character === "'" || character === ' '
  }
  return out
}

export async function run({ artifacts, locales }) {
  const contributions = {}
  const stats = {}
  // Per-locale, because this adapter reads several registries and none is "the primary".
  // English names come from Gender-by-Name and French from INSEE, and crediting both to
  // whichever happens to be first in `sources` would put a French statistics office's
  // name on a list of American given names.
  const sourceByLocale = {}

  // Loaded once and only if something needs it, so a checkout without the committed query
  // results still builds every registry that ships a file.
  let committedRows = null
  async function committed() {
    if (committedRows === null) {
      const raw = await readFile(join(here, '..', 'data', 'statistics-names.json'), 'utf8')
      committedRows = JSON.parse(raw).countries
    }
    return committedRows
  }

  /**
   * Thresholds a registry's rows and writes them to every locale it serves.
   *
   * Two registries do not fit the default and say so rather than being special-cased here.
   *
   * `weighted: false` is for a register that lists which names exist without counting
   * bearers -- Azerbaijan publishes the names the Ministry of Justice permits, which is a
   * different kind of fact from how many people hold one. Thresholding it would compare
   * against a count it does not have, so the threshold is skipped and the values ship
   * unweighted, which is what the data actually says.
   *
   * `minimumRows` is for a register that is legitimately small. The default guard exists to
   * catch a re-pin that silently yields almost nothing, and 1,000 suits a European given-name
   * register. Chinese surnames are a closed set of a few hundred covering almost everybody --
   * Taiwan has 441 above the threshold and that is the whole truth of it, not a truncation.
   */
  function applyRegistry(registry, rows) {
    const kept =
      registry.weighted === false ? rows : rows.filter((row) => row.count >= MINIMUM_BEARERS)
    const floor = registry.minimumRows ?? 1000
    if (kept.length < floor) {
      throw new Error(
        `${registry.source} yielded only ${kept.length} names — verify before re-pinning`,
      )
    }

    for (const code of registry.locales) {
      if (!locales.includes(code)) continue
      const contribution = {}
      // `surname` alongside the two sexes, because one register publishes them. The note
      // at the top of this file said surnames were not here, and that was true of France
      // and stayed true through Poland and Spain — Sweden is the exception that made it
      // false, publishing 411,802 family names with counts beside its given names.
      for (const kind of ['female', 'male', 'surname']) {
        const path =
          kind === 'surname' ? 'person.last_name.generic' : `person.first_name.${kind}`
        const matching = kept.filter((row) => row.sex === kind)
        if (matching.length === 0) continue
        // An unweighted register ships a plain list. Giving every entry the same weight
        // would encode a uniform draw as though it had been measured, and the corpus would
        // carry a number that means nothing.
        contribution[path] =
          registry.weighted === false
            ? [...new Set(matching.map((row) => titleCase(row.name, code)))].sort()
            : matching
                .sort((a, b) => b.count - a.count || (a.name < b.name ? -1 : 1))
                .map((row) => ({ value: titleCase(row.name, code), weight: row.count }))
      }
      contributions[code] = contribution
      sourceByLocale[code] = registry.source
      stats[code] = Object.entries(contribution)
        .map(([path, values]) => `${path.split('.').at(-1)}=${values.length}`)
        .join(' ')
    }
  }

  for (const registry of REGISTRIES) {
    // A committed query result rather than a fetched file. Norway and Slovenia publish
    // through PxWeb, which answers a POST — there is no file to hash and no version to
    // pin, so the query is run by hand and its output committed beside it. Same reasoning
    // as the Wikidata data files, and the same trade: re-runnable and diffable instead of
    // hashed.
    if (registry.committed) {
      const rows = (await committed())[registry.committed]
      if (!rows) {
        throw new Error(
          `${registry.source}: no '${registry.committed}' in data/statistics-names.json — ` +
            `run Tools/adapters/fetch-statistics-names.mjs`,
        )
      }
      applyRegistry(registry, rows)
      continue
    }

    // Two shapes, because registries publish in two shapes. Most ship a zip holding one
    // CSV whose filename carries the edition year, so the name is read rather than
    // hard-coded and re-pinning to a newer edition does not silently stop finding the
    // data. Poland publishes a plain CSV per sex, so there is nothing to look inside.
    let paths
    if (registry.artifact) {
      const directory = artifacts[registry.artifact]
      const [file] = (await readdir(directory)).filter((name) => name.endsWith('.csv'))
      if (!file) throw new Error(`${registry.source}: no CSV in the artifact`)
      paths = [join(directory, file)]
    } else {
      paths = registry.files.map((name) => artifacts[name])
    }

    // Parsed per file and concatenated, so a registry that splits its publication across
    // several files needs no special case in the parser it shares with the others.
    //
    // Concatenated rather than spread into `push`: Poland's male file alone is 46,000
    // rows, and `push(...rows)` passes every one as an argument, which overflows the call
    // stack. A failure that only appears once a registry is large enough.
    let rows = []
    for (const path of paths) {
      // A workbook is handed to its parser as bytes; everything else as text. Statistical
      // offices publish in `.xlsx` more often than in anything else, so this is the common
      // case rather than the exotic one — see `lib/xlsx.mjs`.
      const contents =
        registry.format === 'xlsx' ? await readFile(path) : await readFile(path, 'utf8')
      rows = rows.concat(registry.parse(contents))
    }
    applyRegistry(registry, rows)
  }

  return { contributions, sourceByLocale, stats }
}
