/**
 * HTTP status codes and JOSE algorithms, from the IANA registries that define them.
 *
 * Fills:
 *   base    internet.http_status_code.<class>   informational … serverError
 *   base    internet.jwt_algorithm              JWS/JWE algorithm names
 *
 * These are the clearest kind of fact in the whole corpus. A status code is 404 because
 * IANA's registry says so, and there is no locale, no opinion and no editorial judgement
 * anywhere in it — which is exactly the sort of thing this project holds should come from
 * the registry rather than from a copy of a copy.
 *
 * The registries are also *current* in a way a vendored list is not. faker carried 63
 * status codes; IANA has every one assigned to date, including the ones added since
 * whichever version of the list faker copied.
 */

import { readFile } from 'node:fs/promises'

export const id = 'iana-web'
export const sources = ['iana-http-status', 'iana-jose']
export const attributeTo = 'iana-http-status'

/**
 * Reads a CSV where a field may be quoted and contain commas.
 *
 * A three-line parser rather than a dependency, and sufficient because IANA's registry
 * exports are machine-generated with a fixed dialect: comma-separated, double-quoted
 * where needed, doubled quotes to escape.
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
    } else if (character === '"') {
      quoted = true
    } else if (character === ',') {
      row.push(field)
      field = ''
    } else if (character === '\n') {
      row.push(field.replace(/\r$/, ''))
      if (row.some((cell) => cell !== '')) rows.push(row)
      row = []
      field = ''
    } else {
      field += character
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field)
    if (row.some((cell) => cell !== '')) rows.push(row)
  }
  return rows
}

/** The five classes an HTTP status code falls into, by its leading digit. */
const STATUS_CLASSES = {
  1: 'informational',
  2: 'success',
  3: 'redirection',
  4: 'clientError',
  5: 'serverError',
}

export async function run({ artifacts }) {
  const statusRows = parseCSV(await readFile(artifacts.status, 'utf8'))
  const [statusHeader, ...statuses] = statusRows
  if (statusHeader[0] !== 'Value' || statusHeader[1] !== 'Description') {
    throw new Error(`IANA status header is ${statusHeader.join(',')} — the schema has changed`)
  }

  const byClass = {}
  for (const [value, description] of statuses) {
    // The registry carries reserved and unassigned ranges as rows too. Those are not
    // status codes anybody returns, and the description says so.
    if (!/^\d{3}$/.test(value)) continue
    if (/^unassigned$|^\(unused\)$|^reserved/i.test(description.trim())) continue
    const klass = STATUS_CLASSES[value[0]]
    if (!klass) continue
    byClass[klass] ??= []
    byClass[klass].push(Number(value))
  }

  const total = Object.values(byClass).reduce((n, codes) => n + codes.length, 0)
  if (total < 40) {
    throw new Error(`IANA yielded ${total} status codes — verify before re-pinning`)
  }

  const joseRows = parseCSV(await readFile(artifacts.jose, 'utf8'))
  const [joseHeader, ...algorithms] = joseRows
  if (joseHeader[0] !== 'Algorithm Name') {
    throw new Error(`IANA JOSE header is ${joseHeader[0]} — the schema has changed`)
  }

  // `alg` usage only. The registry also lists `enc` algorithms, which name a content
  // encryption method rather than a signature algorithm, and a JWT header's `alg` field
  // never carries one.
  const jwt = [
    ...new Set(
      algorithms
        .filter(([name, , usage]) => /\balg\b/.test(usage ?? '') && /^[A-Za-z0-9+-]+$/.test(name))
        .map(([name]) => name),
    ),
  ].sort()

  if (jwt.length < 10) {
    throw new Error(`IANA yielded ${jwt.length} JOSE algorithms — verify before re-pinning`)
  }

  const statusPaths = {}
  for (const [klass, codes] of Object.entries(byClass)) {
    statusPaths[`internet.http_status_code.${klass}`] = codes.sort((a, b) => a - b)
  }

  return {
    // `base`: a status code is the same in every language.
    contributions: { base: { ...statusPaths, 'internet.jwt_algorithm': jwt } },
    stats: { statusCodes: total, jwtAlgorithms: jwt.length },
  }
}
