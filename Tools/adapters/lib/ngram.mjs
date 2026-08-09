/**
 * Fits a character-level n-gram model to a word list.
 *
 * Shared rather than living in one adapter, because every generative field wants the same
 * machinery on a different list: surnames today, given names and street names once
 * permissively licensed seed lists exist for them.
 *
 * ## Two decisions worth stating
 *
 * **Types, not tokens.** Each distinct name contributes once, regardless of how many
 * people bear it. Training weighted by the Census counts would mean Smith contributing
 * 2.4 million times, and the model would learn to produce near-misses of the twenty
 * commonest surnames rather than the shape of English surnames generally. Frequency
 * realism is not lost by this — the real weighted list is still in the corpus and is
 * still what `lastName()` draws. The model's job is novelty; the list's job is
 * distribution. Conflating them would do both badly.
 *
 * **Every suffix of every context is recorded**, not just the longest. The sampler backs
 * off a symbol at a time when it meets a context it has not seen, so a model holding only
 * order-1 contexts would back straight off and generate noise. This is what makes the
 * model larger than a naive count suggests, and it is not optional.
 *
 * **Contexts are left-padded with the sentinel**, so word-initial position is part of the
 * context rather than a special case. Without it the shortest context is the empty one,
 * which is the *marginal* distribution over every character in the training set and not
 * the start-of-word distribution at all — so the walk began mid-word and produced `ster`,
 * `rda`, `uck`. With padding, `[0,0,0]` means "nothing yet" and is a real, distinct
 * context, and backing off from `[0,0,S]` to `[0,S]` to `[S]` keeps that information.
 */

/** The end-of-word sentinel. Alphabet index 0, and never a real character. */
export const END = 0

/**
 * Below this many distinct values, a model is not worth building.
 *
 * At 50 values an order-3 model reproduces its input a third of the time and an order-2
 * one — novel but with a single character of context — generates noise. There is no
 * setting at which 50 names teach a machine what a name looks like, and shipping a model
 * that mostly echoes its training data is worse than shipping the list: same values, more
 * bytes, and a false claim of novelty attached.
 */
export const MINIMUM_TRAINING_VALUES = 100

/**
 * Picks the n-gram order from how much there is to learn from.
 *
 * A fixed order was the first mistake here, and it was invisible: order 4 on the 24,889
 * Census surnames gives 73% novel output, and the same order on a 200-name list gives
 * 33%. Two thirds of what a small-locale model produced would have been its own training
 * data handed back, rejected by the Bloom filter, and redrawn — so the model would have
 * looked like it worked while quietly having nothing to say.
 *
 * The rule is the highest order that still clears roughly 70% novel output, because
 * higher order means closer fidelity to the language and lower order means more
 * invention. Measured over the Census list subsampled from 50 to 24,889:
 *
 * ```
 * size    order 2   order 3   order 4   order 5
 *   50      100%       67%       17%        0%
 *  200      100%       89%       33%        4%
 *  800       99%       95%       57%       13%
 * 3200       96%       93%       67%       27%
 * 6400       94%       91%       74%       31%
 * 24889      85%       83%       73%       45%
 * ```
 *
 * Order 2 clears the bar everywhere and is never chosen: one character of context is not
 * a language model, it is a letter-frequency table, and its output reads like one.
 */
export function orderFor(count, typicalLength = Infinity) {
  if (count < MINIMUM_TRAINING_VALUES) return null

  // The context has to be a *fragment* of a word, not the whole of one. Japanese given
  // names are two characters; at order 3 the two-character context spans the entire name,
  // so the model can only reproduce pairs it has already seen, every candidate is a
  // training-set member, the Bloom filter rejects all of them and the generator returns
  // nothing at all. That is exactly what it did.
  //
  // Order n means a context of n-1, so capping the order at the typical word length
  // leaves at least one character for the model to decide.
  const byLength = Math.max(2, Math.floor(typicalLength))
  const bySize = count > 5000 ? 4 : 3
  return Math.min(bySize, byLength, 4)
}

/** The median length of `words`, which is what `orderFor` needs and the mean is not. */
export function typicalLength(words) {
  if (words.length === 0) return 0
  const lengths = words.map((w) => [...w].length).sort((a, b) => a - b)
  return lengths[Math.floor(lengths.length / 2)]
}

/**
 * Draws from a trained model, mirroring `Faker.draw(fromModel:)`.
 *
 * Here so the trainer can check its own work before shipping it — see `isViable`. It is a
 * second implementation of the sampler and therefore a place the two can drift, which is
 * why `NGramSamplerParityTests` trains a model here and compares draws against Swift.
 */
export function sample(model, next32, { maxLength = 64 } = {}) {
  const byKey = new Map(model.contexts.map((c) => [c.key, c.transitions]))
  const keyOf = (symbols) => {
    let packed = BigInt(symbols.length) << 56n
    symbols.forEach((symbol, offset) => {
      packed |= BigInt(symbol) << BigInt(offset * 16)
    })
    return packed.toString()
  }

  const history = new Array(model.order - 1).fill(END)
  let word = ''
  for (let step = 0; step < maxLength; step++) {
    let transitions = null
    for (let length = model.order - 1; length >= 1 && !transitions; length--) {
      transitions = byKey.get(keyOf(history.slice(history.length - length)))
    }
    if (!transitions) break
    const total = transitions.reduce((sum, t) => sum + t.weight, 0)
    let roll = next32() % total
    let picked = transitions[transitions.length - 1]
    for (const transition of transitions) {
      if (roll < transition.weight) {
        picked = transition
        break
      }
      roll -= transition.weight
    }
    if (picked.symbol === END) break
    word += model.alphabet[picked.symbol]
    history.push(picked.symbol)
  }
  return word
}

/**
 * Whether a trained model can actually generate, rather than only recite.
 *
 * The backstop, and the reason it exists is that I cannot reason about every script. The
 * order rules above are derived from English surnames; Japanese broke them in a way no
 * amount of staring at the rule would have predicted, and something else will break them
 * again. So the trainer draws from its own model and refuses to ship one that cannot
 * produce novel output — a model whose every candidate is rejected by the Bloom filter is
 * not a conservative model, it is a generator that returns nothing.
 */
export function isViable(model, words, { draws = 400, minimumNovel = 0.5 } = {}) {
  const known = new Set(words)
  const lengths = words.map((w) => [...w].length)
  const min = Math.min(...lengths)
  const max = Math.max(...lengths)

  let state = 20260809n
  const MASK = (1n << 64n) - 1n
  const next32 = () => {
    state = (state * 6364136223846793005n + 1442695040888963407n) & MASK
    return Number((state >> 32n) & 0xffffffffn)
  }

  let usable = 0
  for (let i = 0; i < draws; i++) {
    const word = sample(model, next32)
    const length = [...word].length
    if (word && length >= min && length <= max && !known.has(word)) usable += 1
  }
  return { novel: usable / draws, viable: usable / draws >= minimumNovel }
}

/**
 * Pruning threshold, likewise from size.
 *
 * Dropping transitions seen once halves a large model and guts a small one — at 200
 * values almost every transition is a singleton, and pruning them leaves a model that
 * can only produce the handful of sequences it saw twice.
 */
export function minCountFor(count) {
  return count > 5000 ? 2 : 1
}

/**
 * Counts every (context, next-symbol) pair in `words`.
 *
 * @param {string[]} words       distinct training words
 * @param {number}   order       context length is order - 1
 * @param {number}   minCount    transitions seen fewer times than this are dropped
 */
export function train(words, options = {}) {
  const distinct = [...new Set(words)]
  const order = options.order ?? orderFor(distinct.length, typicalLength(distinct))
  const minCount = options.minCount ?? minCountFor(distinct.length)
  if (order === null) {
    throw new Error(
      `${distinct.length} values is below MINIMUM_TRAINING_VALUES (${MINIMUM_TRAINING_VALUES})`,
    )
  }
  // Three 16-bit symbols and a length byte are what a u64 context key holds.
  if (order < 2 || order > 4) throw new Error(`order must be 2...4, got ${order}`)
  words = distinct

  // Alphabet in first-appearance order, so a re-run over the same list is byte-identical.
  const symbolOf = new Map()
  const alphabet = ['']
  for (const word of words) {
    for (const character of word) {
      if (!symbolOf.has(character)) {
        symbolOf.set(character, alphabet.length)
        alphabet.push(character)
      }
    }
  }
  if (alphabet.length > 65535) {
    throw new Error(
      `${alphabet.length} distinct characters exceeds the 65,535 a packed context key allows`,
    )
  }

  // context key (a string of comma-joined symbols) -> next symbol -> count
  const counts = new Map()
  const record = (context, next) => {
    const key = context.join(',')
    let row = counts.get(key)
    if (row === undefined) {
      row = new Map()
      counts.set(key, row)
    }
    row.set(next, (row.get(next) ?? 0) + 1)
  }

  const padding = new Array(order - 1).fill(END)
  for (const word of words) {
    const symbols = [...padding, ...[...word].map((c) => symbolOf.get(c))]
    // One extra step past the end so the model learns where words stop. Without it every
    // walk runs to the length cap and every name comes out 32 characters long.
    for (let i = order - 1; i <= symbols.length; i++) {
      const next = i === symbols.length ? END : symbols[i]
      // Every suffix of the padded window, longest first. Length 0 is deliberately absent:
      // with padding the window is always full, so there is always a length-1 context to
      // back off to, and an empty context could only mean the marginal distribution.
      for (let length = 1; length <= order - 1; length++) {
        record(symbols.slice(i - length, i), next)
      }
    }
  }

  // Pack each context into the u64 key the format uses: length in the top byte, symbols
  // below it, most-recent last. BigInt because a u64 does not fit a JS number.
  const contexts = []
  for (const [key, row] of counts) {
    const symbols = key === '' ? [] : key.split(',').map(Number)
    let packed = BigInt(symbols.length) << 56n
    symbols.forEach((symbol, offset) => {
      packed |= BigInt(symbol) << BigInt(offset * 16)
    })

    const transitions = [...row.entries()]
      .filter(([, count]) => count >= minCount)
      // Sorted by symbol so the encoding is stable across runs.
      .sort(([a], [b]) => a - b)
      .map(([symbol, count]) => ({ symbol, weight: count }))

    // Pruning can empty a context. A context with no transitions is a dead end the
    // sampler would have to back out of, so it is dropped rather than shipped empty.
    if (transitions.length > 0) {
      contexts.push({ key: packed.toString(), transitions })
    }
  }
  contexts.sort((a, b) => (BigInt(a.key) < BigInt(b.key) ? -1 : 1))

  // The observed length range travels with the model so the sampler can reject outside
  // it. An n-gram has no notion of total length — it only ever decides what comes next —
  // so nothing stops a run of plausible bigrams adding up to a 28-character surname when
  // the longest real one is 15. Measured at 0.8% of draws, which is rare enough to miss
  // in a sample and common enough to notice in a fixture set.
  let minLength = Infinity
  let maxLength = 0
  for (const word of words) {
    const length = [...word].length
    if (length < minLength) minLength = length
    if (length > maxLength) maxLength = length
  }

  return { order, alphabet, contexts, minLength, maxLength }
}

/**
 * Builds a Bloom filter over the training set.
 *
 * Sized from the target false-positive rate rather than a round number of bytes, because
 * the rate is what has a meaning: it is the share of novel names the sampler will throw
 * away for looking like real ones. 1% costs about 1.2 bytes per name and is invisible in
 * practice.
 *
 * The hash must match `NGramModel.wasTrainedOn` exactly — FNV-1a, then the same mix per
 * probe. A mismatch would not fail loudly; it would silently stop rejecting real names,
 * which is the one failure this filter exists to prevent, so it is asserted by a test
 * that trains here and checks in Swift.
 */
export function bloomFilter(words, { falsePositiveRate = 0.01 } = {}) {
  return buildFilter(words, falsePositiveRate)
}

/**
 * A filter over blocked substrings, for screening generated words.
 *
 * Only the hashes ship. Nothing in the blocklist reaches the binary as text, which keeps
 * a list of slurs out of something people grep and security scanners read, and keeps one
 * out of the string arena where a bug in path resolution could surface it as a value.
 *
 * Terms shorter than `minLength` are dropped. Two- and three-letter entries appear inside
 * ordinary surnames constantly, and blocking on them would reject a large share of
 * perfectly good output while catching nothing a longer term does not.
 *
 * **The false-positive rate is budgeted per word, not per lookup**, which is why it looks
 * absurdly tight. Screening a 15-character name means about 78 substring queries, so a
 * per-query rate of 0.1% gives `1 - 0.999^78`, about 7.5% per word — and it showed up
 * exactly there: 1.4% of real Census surnames were being rejected by a filter configured
 * for 0.1%. At 1e-6 per query the per-word rate is under 0.01% and the filter still costs
 * under a kilobyte, because a Bloom filter's size grows with the log of the rate.
 */
export function blocklistFilter(terms, { falsePositiveRate = 1e-6, minLength = 4 } = {}) {
  const kept = [
    ...new Set(
      terms
        .map((term) => term.trim().toLowerCase())
        // Multi-word entries cannot appear inside a single generated token.
        .filter((term) => term.length >= minLength && !term.includes(' ')),
    ),
  ].sort()
  return { minLength, dropped: terms.length - kept.length, ...buildFilter(kept, falsePositiveRate) }
}

function buildFilter(words, falsePositiveRate) {
  const n = Math.max(words.length, 1)
  const bits = Math.ceil((-n * Math.log(falsePositiveRate)) / Math.LN2 ** 2)
  const byteCount = Math.ceil(bits / 8)
  const hashCount = Math.max(1, Math.round((bits / n) * Math.LN2))
  const filter = new Uint8Array(byteCount)

  const MASK = (1n << 64n) - 1n
  const MIX = 0x9e3779b97f4a7c15n

  for (const word of words) {
    // FNV-1a over UTF-8, matching SeedDerivation.fnv1a.
    let hash = 0xcbf29ce484222325n
    for (const byte of new TextEncoder().encode(word)) {
      hash = ((hash ^ BigInt(byte)) * 0x100000001b3n) & MASK
    }
    for (let i = 0; i < hashCount; i++) {
      const bit = Number(hash % BigInt(byteCount * 8))
      filter[bit >> 3] |= 1 << bit % 8
      hash = (hash * MIX) & MASK
      hash ^= hash >> 29n
    }
  }

  return { hashCount, bits: [...filter] }
}
