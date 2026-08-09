/**
 * Phone number formats, from libphonenumber's metadata.
 *
 * The formats are facts about a country's numbering plan, published and maintained by the
 * people who maintain the canonical implementation of them. Apache-2.0, which is the
 * closest licence match any source in this corpus has.
 *
 * Fills:
 *   <each>  phone_number.format.national       that country's national formats
 *   <each>  phone_number.format.international   the same, with the country code
 *   <each>  phone_number.format.human           an alias for national; see below
 *
 * `mobile` is deliberately not filled. libphonenumber describes mobile numbers with a
 * *pattern* rather than a distinct format — which formats apply is decided by leading
 * digits at call time — and inventing a mobile mask from the national one would state
 * something the source does not. That path stays on faker until it is dropped or answered
 * properly.
 *
 * ## Reading the metadata
 *
 * Each format is a capture pattern and a template:
 *
 *     <numberFormat pattern="(\d{3})(\d{3})(\d{4})">
 *       <format>($1) $2-$3</format>
 *     </numberFormat>
 *
 * Group lengths come out of the pattern and substitute into the template, so `($1) $2-$3`
 * becomes `(###) ###-####`. No example numbers and no formatting engine needed — the mask
 * is already there, spelled differently.
 *
 * Parsed with regular expressions rather than an XML parser, which is normally a mistake.
 * It is defensible here for one reason: the alternative is a dependency, and this pipeline
 * has none by design. The file is machine-maintained with a fixed shape, every extraction
 * is anchored to a named element, and the adapter throws if the shape stops matching
 * rather than silently yielding fewer formats.
 */

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export const id = 'phone-formats'
export const sources = ['libphonenumber', 'cldr-48']

/** libphonenumber supplies every format; CLDR only resolves a locale to its country. */
export const attributeTo = 'libphonenumber'

/**
 * Countries where a leading digit cannot be 0 or 1.
 *
 * The North American Numbering Plan forbids both as the first digit of an area code and
 * of an exchange, so `###` there generates numbers no switch would route. The corpus mask
 * language has `!` for "2 through 9" precisely for this, and faker used it in the same
 * place. Applied only where the rule is a documented property of the plan rather than
 * inferred from `leadingDigits`, which encodes far more than a mask can carry.
 */
const NANP_COUNTRY_CODE = '1'

function regionFor(code, likelySubtags) {
  for (const segment of code.split('_').slice(1)) {
    if (/^[A-Z]{2}$/.test(segment)) return segment
  }
  const language = code.split('_')[0]
  const region = likelySubtags[language]?.split('-').at(-1)
  return /^[A-Z]{2}$/.test(region ?? '') ? region : null
}

/**
 * Group bounds from a capture pattern: `(\d{3})(\d{2,7})` -> [[3,3], [2,7]].
 *
 * Ranges are the whole difficulty. Germany writes `(\d{2})(\d{3,13})`, and collapsing
 * that to its minimum produced `## ###` — a five-digit German phone number. The bounds
 * are kept and resolved against the country's real number lengths in `resolveLengths`.
 */
function groupBounds(pattern) {
  const groups = pattern.match(/\((?:\\d|\[[^\]]*\])(?:\{\d+(?:,\d+)?\})?\)/g)
  if (!groups) return null
  return groups.map((group) => {
    const range = group.match(/\{(\d+)(?:,(\d+))?\}/)
    if (!range) return [1, 1]
    return [Number(range[1]), Number(range[2] ?? range[1])]
  })
}

/** Parses a `possibleLengths` spec: `9`, `10,11` and `[5-15]` all appear. */
function parseLengths(declared) {
  if (!declared) return null
  const lengths = new Set()
  for (const part of declared.split(',')) {
    const range = part.match(/^\[(\d+)-(\d+)\]$/)
    if (range) {
      for (let n = Number(range[1]); n <= Number(range[2]); n++) lengths.add(n)
    } else if (/^\d+$/.test(part)) {
      lengths.add(Number(part))
    }
  }
  return lengths.size > 0 ? lengths : null
}

function lengthsIn(territory, element) {
  const section = territory.match(new RegExp(`<${element}>[\\s\\S]*?</${element}>`))?.[0]
  return parseLengths(section?.match(/<possibleLengths[^>]*\bnational="([^"]+)"/)?.[1])
}

/**
 * The digit count to build a mask at.
 *
 * A mask is one shape, so it has to be the *typical* number rather than an extreme, and
 * the narrower of the two published specs is the one that says what typical is. German
 * landlines genuinely run 5 to 15 digits — area codes vary that much — so the widest
 * reading is not wrong, it is just useless: taking it produced `## #############`. German
 * mobiles are 10 or 11, and that is a number somebody recognises.
 *
 * `generalDesc` is never used. It spans short codes, premium rate and everything else a
 * country issues, which is the widest range of all.
 */
function targetLengths(territory) {
  const fixedLine = lengthsIn(territory, 'fixedLine')
  const mobile = lengthsIn(territory, 'mobile')
  if (!fixedLine) return mobile
  if (!mobile) return fixedLine
  return mobile.size <= fixedLine.size ? mobile : fixedLine
}

/**
 * Fixes each group to a concrete length, or `null` if the format cannot produce a real
 * number.
 *
 * A format whose groups are all fixed is kept only when its total is a length the country
 * issues — that is what filters France's four- and six-digit service formats out of a
 * plan whose subscriber numbers are nine. Where one group is a range, it absorbs whatever
 * the largest achievable real length needs, because the short end of these ranges is
 * service numbers and the long end is what a person's phone actually is.
 */
function resolveLengths(bounds, lengths) {
  const fixed = bounds.reduce((sum, [low, high]) => sum + (low === high ? low : 0), 0)
  const variable = bounds.filter(([low, high]) => low !== high)
  if (variable.length === 0) return lengths.has(fixed) ? bounds.map(([n]) => n) : null
  if (variable.length > 1) return null

  const [low, high] = variable[0]
  const achievable = [...lengths]
    .filter((total) => total - fixed >= low && total - fixed <= high)
    .sort((a, b) => b - a)
  if (achievable.length === 0) return null

  const share = achievable[0] - fixed
  return bounds.map(([a, b]) => (a === b ? a : share))
}

/** Substitutes `$1`, `$2` … in a template with runs of mask characters. */
function maskFrom(template, lengths, nanp) {
  let out = ''
  let index = 0
  while (index < template.length) {
    const marker = template.indexOf('$', index)
    if (marker < 0) {
      out += template.slice(index)
      break
    }
    out += template.slice(index, marker)
    const group = Number(template[marker + 1])
    if (!Number.isInteger(group) || group < 1 || group > lengths.length) return null
    const length = lengths[group - 1]
    // Only the first digit of the first two groups is constrained, which is the area code
    // and the exchange. The subscriber number may begin with anything.
    const leading = nanp && group <= 2 ? '!' : '#'
    out += leading + '#'.repeat(length - 1)
    index = marker + 2
  }
  return out
}

export async function run({ artifacts, locales }) {
  const likelySubtags = JSON.parse(
    await readFile(
      join(artifacts.core, 'package', 'supplemental', 'likelySubtags.json'),
      'utf8',
    ),
  ).supplemental.likelySubtags

  const xml = await readFile(artifacts.metadata, 'utf8')

  const byRegion = new Map()
  const territories = xml.match(/<territory\s[^>]*>[\s\S]*?<\/territory>/g) ?? []
  if (territories.length < 200) {
    throw new Error(
      `libphonenumber metadata yielded ${territories.length} territories — the shape has changed`,
    )
  }

  for (const territory of territories) {
    const id = territory.match(/\bid="([A-Z]{2})"/)?.[1]
    const countryCode = territory.match(/\bcountryCode="(\d+)"/)?.[1]
    if (!id || !countryCode) continue

    const nanp = countryCode === NANP_COUNTRY_CODE
    const nationalPrefix = territory.match(/\bnationalPrefix="([^"]+)"/)?.[1] ?? null
    const allowed = targetLengths(territory)
    const national = []
    // Kept apart because they differ by exactly the trunk prefix, and deriving one from
    // the other by stripping a leading zero guesses at what the source states.
    const international = []
    for (const format of territory.match(/<numberFormat[\s\S]*?<\/numberFormat>/g) ?? []) {
      const pattern = format.match(/\bpattern="([^"]+)"/)?.[1]
      const template = format.match(/<format>([^<]+)<\/format>/)?.[1]
      if (!pattern || !template || !allowed) continue
      const bounds = groupBounds(pattern)
      if (!bounds) continue
      const lengths = resolveLengths(bounds, allowed)
      if (!lengths) continue
      const mask = maskFrom(template, lengths, nanp)
      if (!mask) continue

      // The trunk prefix, where the country uses one. `$NP$FG` means "national prefix
      // then the formatted number" — the leading 0 a French or German number is written
      // with domestically and dropped from internationally. Without it the national form
      // was one digit short of what anybody writes down.
      const rule = format.match(/\bnationalPrefixFormattingRule="([^"]*)"/)?.[1]
      const domestic =
        rule && nationalPrefix ? rule.replace('$NP', nationalPrefix).replace('$FG', mask) : mask

      if (!national.includes(domestic)) national.push(domestic)
      if (!international.includes(mask)) international.push(mask)
    }
    const main = /\bmainCountryForCode="true"/.test(territory)
    if (national.length > 0) byRegion.set(id, { countryCode, national, international, main })
  }

  // A country sharing a calling code with another carries no formats of its own — Canada
  // has none because the United States is the main country for code 1, and the two write
  // numbers identically. Inheriting from the main country is what libphonenumber itself
  // does at format time; without it Canada came back with nothing and stayed on faker.
  const mainByCode = new Map()
  for (const entry of byRegion.values()) {
    if (entry.main) mainByCode.set(entry.countryCode, entry)
  }
  for (const territory of territories) {
    const id = territory.match(/\bid="([A-Z]{2})"/)?.[1]
    const countryCode = territory.match(/\bcountryCode="(\d+)"/)?.[1]
    if (!id || !countryCode || byRegion.has(id)) continue
    const inherited = mainByCode.get(countryCode)
    if (inherited) byRegion.set(id, { ...inherited, inherited: true })
  }

  const contributions = {}
  const withoutFormats = []

  for (const code of locales) {
    if (code === 'base') continue
    const region = regionFor(code, likelySubtags)
    const entry = region ? byRegion.get(region) : null
    if (!entry) {
      if (region) withoutFormats.push(`${code}(${region})`)
      continue
    }

    contributions[code] = {
      'phone_number.format.national': entry.national,
      // `human` is what `phone.number()` draws by default, and a national-format number
      // is what a person writes down. faker distinguished the two and then used the same
      // shapes for both.
      'phone_number.format.human': entry.national,
      // The international form is the national one with the country code and without the
      // national trunk prefix — the leading `0` most plans use domestically. Stripping it
      // is the one transformation applied here rather than read.
      'phone_number.format.international': entry.international.map(
        (mask) => `+${entry.countryCode} ${mask}`,
      ),
    }
  }

  return {
    contributions,
    stats: {
      territories: byRegion.size,
      locales: Object.keys(contributions).length,
      withoutFormats,
    },
  }
}
