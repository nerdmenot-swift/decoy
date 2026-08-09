/**
 * Postcode shapes and address layouts, from Google's address metadata.
 *
 * Fills:
 *   <each>  location.postcode        a mask matching that country's postcode rule
 *   <each>  location.postal_address  the order and line breaks an address is written in
 *
 * The address format is the part with no other source anywhere. `%N%n%O%n%A%n%C %S %Z`
 * says a US address puts name, organisation and street on their own lines and then city,
 * state and ZIP together; `〒%Z%n%S%C%n%A%n%O%n%N` says a Japanese one runs the other way
 * entirely, postcode first and name last. faker carried twelve of these as hand-written
 * strings and every other locale fell through to an American layout.
 *
 * ## Turning a postcode regex into a mask
 *
 * `zip` is a validation pattern rather than a template — `\d{5}([ \-]\d{4})?` for the
 * United States. The conversion handles the constructs that actually appear: digit and
 * letter classes, explicit character sets, fixed and ranged repetition, literals, and
 * optional trailing groups.
 *
 * It refuses anything else. Britain's pattern is a 400-character alternation enumerating
 * every valid area code, and a mask cannot express it — so `GB` keeps whatever it had
 * rather than getting a plausible-looking postcode that no sorting office would accept.
 * Refusing loudly beats approximating quietly.
 */

import { readFile } from 'node:fs/promises'

export const id = 'postal'
export const sources = ['libaddressinput', 'cldr-48']
export const attributeTo = 'libaddressinput'

function regionFor(code, likelySubtags) {
  for (const segment of code.split('_').slice(1)) {
    if (/^[A-Z]{2}$/.test(segment)) return segment
  }
  const language = code.split('_')[0]
  const region = likelySubtags[language]?.split('-').at(-1)
  return /^[A-Z]{2}$/.test(region ?? '') ? region : null
}

/**
 * Converts a postcode pattern to a `#`/`?` mask, or `null` if it cannot be expressed.
 *
 * `#` is a digit and `?` an uppercase letter, matching what `bothify` substitutes. A
 * ranged repetition takes its maximum, because postcodes pad rather than truncate and the
 * long form is the canonical one.
 */
export function maskFor(pattern) {
  // An optional trailing group is a real alternative rather than an error — the US +4 is
  // written about as often as it is not — but a mask is one shape, so the shorter form is
  // taken and the extension dropped.
  let source = pattern.replace(/\((?:\?:)?[^()]*\)\?$/, '')
  if (/[|()]/.test(source)) return null

  let mask = ''
  let index = 0
  while (index < source.length) {
    let unit = null

    if (source.startsWith('\\d', index)) {
      unit = '#'
      index += 2
    } else if (source[index] === '[') {
      const close = source.indexOf(']', index)
      if (close < 0) return null
      const set = source.slice(index + 1, close)
      // `[0-9]` is a digit, `[A-Z]` a letter, `[ \-]` a literal separator. Anything
      // narrower — `[ABD-HJLNP-UW-Z]`, which is a real postcode constraint — cannot be a
      // mask, and pretending otherwise generates invalid codes.
      if (/^0-9$/.test(set)) unit = '#'
      else if (/^A-Z$/.test(set)) unit = '?'
      else if (/^[ \\-]+$/.test(set)) unit = set.replace(/\\/g, '')[0]
      else return null
      index = close + 1
    } else if (/[A-Za-z0-9 -]/.test(source[index])) {
      unit = source[index]
      index += 1
    } else if (source[index] === '\\') {
      unit = source[index + 1]
      index += 2
    } else {
      return null
    }

    let repeat = 1
    if (source[index] === '{') {
      const close = source.indexOf('}', index)
      if (close < 0) return null
      const bounds = source.slice(index + 1, close).split(',')
      repeat = Number(bounds[bounds.length - 1] || bounds[0])
      if (!Number.isFinite(repeat) || repeat < 1 || repeat > 12) return null
      index = close + 1
    } else if (source[index] === '?') {
      index += 1
      // An optional *separator* is kept, because it is what people write: a Japanese
      // postcode is `154-0023` and a Brazilian CEP `01310-100`, and both regexes mark the
      // hyphen optional because both are also valid without it. Dropping it gave
      // `#######`, which is correct and unrecognisable. Anything else optional is
      // dropped, so the mask stays the shorter valid form.
      if (!' -'.includes(unit)) continue
    }

    mask += unit.repeat(repeat)
  }
  return mask.length > 0 ? mask : null
}

/** libaddressinput's placeholders, mapped to the corpus's template tokens. */
const FIELDS = {
  N: '{{person.name}}',
  A: '{{location.streetAddress}}',
  C: '{{location.city}}',
  S: '{{location.state}}',
  Z: '{{location.zipCode}}',
}

/**
 * Converts an address format to a template.
 *
 * `%O` — organisation — is dropped rather than mapped to a company name: an address is
 * for a person here, and half of them would otherwise arrive care of a business. `%D`,
 * `%X` and the other sublocality fields are dropped for the same reason, since nothing in
 * the corpus supplies a district.
 */
export function templateFor(format) {
  let out = ''
  for (let i = 0; i < format.length; i++) {
    if (format[i] !== '%') {
      out += format[i]
      continue
    }
    const code = format[++i]
    if (code === 'n') out += '\n'
    else if (FIELDS[code]) out += FIELDS[code]
  }
  // Dropping fields leaves blank lines and doubled spaces behind.
  return out
    .split('\n')
    .map((line) => line.replace(/ {2,}/g, ' ').trim())
    .filter(Boolean)
    .join('\n')
}

export async function run({ artifacts, locales }) {
  const likelySubtags = JSON.parse(
    await readFile(
      new URL('file://' + artifacts.core + '/package/supplemental/likelySubtags.json'),
      'utf8',
    ),
  ).supplemental.likelySubtags

  const text = await readFile(artifacts.countryinfo, 'utf8')
  const byRegion = new Map()
  for (const line of text.split('\n')) {
    const match = line.match(/^data\/([A-Z]{2})=(\{.*\})$/)
    if (!match) continue
    try {
      byRegion.set(match[1], JSON.parse(match[2]))
    } catch {
      // A malformed row is skipped rather than fatal: the file carries subdivision rows
      // too, and only the country ones matter here.
    }
  }
  if (byRegion.size < 200) {
    throw new Error(`libaddressinput yielded ${byRegion.size} countries — the shape has changed`)
  }

  const contributions = {}
  let masks = 0
  let templates = 0
  const unmasked = []

  for (const code of locales) {
    if (code === 'base') continue
    const region = regionFor(code, likelySubtags)
    const entry = region ? byRegion.get(region) : null
    if (!entry) continue

    const contribution = {}
    if (entry.zip) {
      const mask = maskFor(entry.zip)
      if (mask) {
        contribution['location.postcode'] = [mask]
        masks += 1
      } else {
        unmasked.push(`${code}(${region})`)
      }
    }
    if (entry.fmt) {
      const template = templateFor(entry.fmt)
      if (template.includes('{{')) {
        contribution['location.postal_address'] = [template]
        templates += 1
      }
    }
    if (Object.keys(contribution).length > 0) contributions[code] = contribution
  }

  return {
    contributions,
    stats: { countries: byRegion.size, postcodes: masks, addresses: templates, unmasked },
  }
}
