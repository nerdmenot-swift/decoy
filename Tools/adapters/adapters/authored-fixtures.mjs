/**
 * Invented content for the columns a survey of other faker libraries showed nobody fills
 * well, and Decoy did not fill at all.
 *
 * Fills:
 *   en  system.error_database, system.error_http, system.error_runtime,
 *       system.error_validation, system.error_component, system.error_constraint
 *   en  commerce.review_pattern, commerce.review_aspect, commerce.review_praise,
 *       commerce.review_complaint, commerce.review_title_pattern
 *   en  whimsy.restaurant_pattern, whimsy.cuisine, whimsy.dish_pattern,
 *       whimsy.school_pattern, whimsy.school_kind, whimsy.faculty
 *   en  whimsy.superhero_pattern, whimsy.power, whimsy.peak_pattern, whimsy.star_pattern
 *   en  whimsy.technobabble_pattern, whimsy.tech_noun, whimsy.tech_verb,
 *       whimsy.tech_gerund, whimsy.tech_adjective
 *   en  beverage.coffee_pattern, beverage.roast, beverage.tea_pattern, beverage.tea_base
 *
 * ## Why these and not the rest
 *
 * gofakeit, Ruby's faker, Bogus and datafaker between them ship animals, celebrities,
 * Minecraft blocks, DC characters, camera models and real book titles. Every one of those
 * fails the test in `authored-whimsy.mjs`: a list of real animals has a fact of the matter
 * and wants a source, a list of real characters wants a lawyer. What survived the filter is
 * the part those libraries compose rather than list — and, in the case of error messages
 * and product reviews, the part they mostly do not have.
 *
 * ## The two that are not jokes
 *
 * `system.error_*` and `commerce.review_*` are here for use rather than amusement. Every
 * application has an error column and every storefront has a review column, and both are
 * usually seeded with lorem, which tells you nothing about how the real thing will wrap,
 * truncate or overflow. An error message is long, has punctuation and quotes an identifier;
 * a review has a sentiment and an aspect. Lorem has none of that shape.
 *
 * ## Collision, again
 *
 * `Bramblewood Academy` may well be a real school and `The Copper Kettle` is certainly a
 * real café. The mitigation is the one the whimsy adapter already argues: the space is
 * large, nothing here was curated to be recognisable, and none of it is a claim that the
 * named thing exists.
 */

export const id = 'authored-fixtures'
export const source = 'decoy-authored'

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/**
 * The subsystem an error names, which is what makes a fake error legible as one.
 *
 * Deliberately generic: `payments` and `search-indexer` are the shape of a service name
 * anywhere, not a real product's module list.
 */
const COMPONENTS = [
  'auth-service', 'billing', 'search-indexer', 'payments', 'notification-worker',
  'session-store', 'media-pipeline', 'reporting', 'sync-agent', 'gateway',
  'user-directory', 'audit-log', 'scheduler', 'export-worker', 'webhook-dispatcher',
]

/** Constraint and index names, in the shapes a real schema produces them. */
const CONSTRAINTS = [
  'users_email_key', 'orders_pkey', 'accounts_tenant_id_fkey', 'sessions_token_key',
  'invoices_number_key', 'idx_events_created_at', 'projects_slug_key',
  'memberships_user_id_org_id_key', 'documents_owner_id_fkey', 'subscriptions_pkey',
]

/**
 * Database errors, phrased the way Postgres and MySQL actually phrase them.
 *
 * The wording is the point. A fixture that reads `error 42` tells you nothing about how the
 * column behaves when something 120 characters long with an embedded quoted identifier
 * lands in it.
 */
const DATABASE_ERRORS = [
  'duplicate key value violates unique constraint "{{system.error_constraint}}"',
  'deadlock detected while waiting for ShareLock on transaction 4####',
  'could not serialize access due to concurrent update',
  'relation "{{system.error_component}}" does not exist',
  'null value in column "tenant_id" violates not-null constraint',
  'insert or update on table "sessions" violates foreign key constraint '
    + '"{{system.error_constraint}}"',
  'canceling statement due to statement timeout',
  'value too long for type character varying(255)',
  'connection to server was lost during query execution',
  'too many connections for role "{{system.error_component}}"',
]

/** HTTP-layer failures, from the client's side of the wire. */
const HTTP_ERRORS = [
  'upstream {{system.error_component}} returned 503 after 3 attempts',
  'request to {{system.error_component}} timed out after 3#00ms',
  'TLS handshake failed: certificate has expired',
  'unexpected content-type "text/html" from {{system.error_component}}, expected JSON',
  'connection reset by peer while reading response body',
  'too many redirects following {{system.error_component}} callback',
  'rate limit exceeded: retry after 6# seconds',
  'malformed chunked encoding in response from {{system.error_component}}',
]

/** Runtime failures, in the register a stack trace summary uses. */
const RUNTIME_ERRORS = [
  'nil dereference in {{system.error_component}} while handling a queued job',
  'index out of range: 1# with length 8',
  'context deadline exceeded',
  'out of memory: cannot allocate 512MiB for {{system.error_component}}',
  'panic recovered in {{system.error_component}}: send on closed channel',
  'goroutine leak detected: 4## routines blocked on the same mutex',
  'unmarshalling failed: unexpected token at position 2##',
  'circular dependency detected while initialising {{system.error_component}}',
]

/** Validation failures, in the register a form or an API returns to a caller. */
const VALIDATION_ERRORS = [
  'email must be a valid address',
  'password must be at least 12 characters',
  'value must be one of: draft, review, published',
  'start date must fall before end date',
  'quantity must be a positive integer',
  'this field is required',
  'postcode does not match the format for the selected country',
  'a project with this slug already exists',
  'file exceeds the 25MB limit',
  'currency must match the account currency',
]

// ---------------------------------------------------------------------------
// Product reviews
// ---------------------------------------------------------------------------

/**
 * What a review is actually about, which is never the product as a whole.
 *
 * Reviews praise or complain about one aspect at a time, and it is that specificity that
 * makes the text look real rather than generated.
 */
const REVIEW_ASPECTS = [
  'the build quality', 'the packaging', 'the finish', 'the weight', 'the instructions',
  'the battery life', 'the fit', 'the colour', 'the price', 'the delivery',
  'the stitching', 'the grip', 'the noise', 'the size', 'the materials',
]

const REVIEW_PRAISE = [
  'better than I expected', 'exactly as described', 'worth every penny',
  'well thought through', 'sturdier than it looks', 'genuinely excellent',
  'a noticeable step up', 'hard to fault',
]

const REVIEW_COMPLAINTS = [
  'not what the photos suggest', 'a let-down for the money', 'flimsier than it looks',
  'awkward to use', 'noticeably worse than the previous version',
  'fine until it broke', 'the weak point', 'not as described',
]

/**
 * Reviews as sentiment plus aspect, weighted the way real ratings distribute.
 *
 * Real review corpora are J-shaped — mostly five stars, a tail of one star, very little in
 * between — so praise outweighs complaint here rather than splitting evenly. A fixture that
 * splits 50/50 makes any dashboard built on it look wrong.
 */
/*
 * Every aspect is stored lowercase and lands mid-sentence, never after a full stop.
 *
 * The first draft put one at the start of a clause and produced `Really pleased with
 * this. the delivery is a noticeable step up.` Capitalising at expansion time would need
 * the generator to know where in the sentence a token sits, which no other pattern here
 * requires — so the patterns are shaped to avoid the position instead. Dashes and commas
 * where a full stop would otherwise fall.
 */
const REVIEW_PATTERNS = [
  { value: 'Really pleased with this — {{commerce.review_aspect}} is '
      + '{{commerce.review_praise}}.', weight: 5 },
  { value: 'Arrived early and {{commerce.review_aspect}} is '
      + '{{commerce.review_praise}}.', weight: 4 },
  { value: 'Second one I have bought, because {{commerce.review_aspect}} is '
      + '{{commerce.review_praise}}.', weight: 3 },
  { value: 'Does the job — {{commerce.review_aspect}} is {{commerce.review_praise}}, '
      + 'though {{commerce.review_aspect}} could be better.', weight: 3 },
  { value: 'Mixed: {{commerce.review_aspect}} is {{commerce.review_praise}} but '
      + '{{commerce.review_aspect}} is {{commerce.review_complaint}}.', weight: 2 },
  { value: 'Disappointed — {{commerce.review_aspect}} is '
      + '{{commerce.review_complaint}}.', weight: 2 },
  { value: 'Returned it. Frankly {{commerce.review_aspect}} was '
      + '{{commerce.review_complaint}}, and support took a week to reply.', weight: 1 },
]

const REVIEW_TITLE_PATTERNS = [
  { value: 'Exactly what I wanted', weight: 3 },
  { value: 'Would buy again', weight: 3 },
  { value: 'Good, with one caveat', weight: 2 },
  { value: 'Does what it says', weight: 2 },
  { value: 'Not for me', weight: 1 },
  { value: 'Save your money', weight: 1 },
]

// ---------------------------------------------------------------------------
// Institutions
// ---------------------------------------------------------------------------

/**
 * Cuisines, which are categories rather than claims — `Lebanese` is a kind of restaurant
 * the way `IPA` is a kind of beer, and the same argument that admits `beverage.beer_style`
 * admits this.
 */
const CUISINES = [
  'Italian', 'Lebanese', 'Vietnamese', 'Georgian', 'Peruvian', 'Ethiopian', 'Basque',
  'Sichuan', 'Portuguese', 'Korean', 'Turkish', 'Nordic', 'Creole', 'Gujarati',
  'Sicilian', 'Yucatecan',
]

const RESTAURANT_PATTERNS = [
  { value: 'The {{whimsy.adjective}} {{whimsy.object}}', weight: 4 },
  { value: 'The {{whimsy.adjective}} {{whimsy.creature}}', weight: 4 },
  { value: '{{whimsy.place}} & {{whimsy.object}}', weight: 3 },
  { value: 'The {{whimsy.place}} Kitchen', weight: 3 },
  { value: '{{whimsy.creature}} & Sons', weight: 2 },
  { value: 'The Old {{whimsy.place}}', weight: 2 },
]

/**
 * Dishes as a menu writes them: a treatment, a thing, and something it sits on.
 *
 * The components are cooking words rather than named dishes, so nothing here asserts that
 * a recipe exists — `Charred Thicket Ragout` is a menu line, not a claim about food.
 */
const DISH_PATTERNS = [
  '{{whimsy.dish_treatment}} {{whimsy.dish_base}} with {{whimsy.dish_side}}',
  '{{whimsy.dish_treatment}} {{whimsy.dish_base}}, {{whimsy.dish_side}}',
  '{{whimsy.dish_base}} {{whimsy.dish_form}} with {{whimsy.dish_side}}',
]

const DISH_TREATMENTS = [
  'Charred', 'Slow-Roasted', 'Cured', 'Smoked', 'Braised', 'Confit', 'Pickled',
  'Blackened', 'Poached', 'Griddled', 'Salt-Baked', 'Twice-Cooked',
]

const DISH_BASES = [
  'Celeriac', 'Barley', 'Squash', 'Fennel', 'Chard', 'Artichoke', 'Aubergine',
  'Pumpkin', 'Leek', 'Beetroot', 'Cauliflower', 'Parsnip', 'Chickpea', 'Lentil',
]

const DISH_FORMS = ['Ragout', 'Terrine', 'Broth', 'Gratin', 'Velouté', 'Tartare', 'Galette']

const DISH_SIDES = [
  'burnt butter', 'wild garlic', 'preserved lemon', 'brown crab', 'toasted hazelnut',
  'smoked yoghurt', 'pickled walnut', 'charred spring onion', 'black garlic',
  'sea buckthorn', 'horseradish cream', 'green peppercorn',
]

/** What kind of institution, which changes the register of the whole name. */
const SCHOOL_KINDS = [
  'Academy', 'Grammar School', 'High School', 'Preparatory School', 'College',
  'Community School', 'Free School', 'Comprehensive',
]

const FACULTIES = [
  'Engineering', 'Applied Mathematics', 'Comparative Literature', 'Marine Biology',
  'Public Health', 'Archaeology', 'Music', 'Political Economy', 'Veterinary Medicine',
  'Earth Sciences', 'Linguistics', 'Architecture',
]

const SCHOOL_PATTERNS = [
  { value: '{{whimsy.place}} {{whimsy.school_kind}}', weight: 4 },
  { value: '{{whimsy.adjective}} {{whimsy.place}} {{whimsy.school_kind}}', weight: 2 },
  { value: 'The {{whimsy.place}} {{whimsy.school_kind}}', weight: 2 },
  { value: '{{whimsy.object}} {{whimsy.school_kind}}', weight: 1 },
]

// ---------------------------------------------------------------------------
// Invented geography and people
// ---------------------------------------------------------------------------

/**
 * Superheroes, which Ruby's faker composes rather than lists, and rightly: a list of real
 * ones is a list of trademarks belonging to two companies.
 */
const POWERS = [
  'Flight', 'Invisibility', 'Telekinesis', 'Regeneration', 'Super Speed', 'Shapeshifting',
  'Precognition', 'Phasing', 'Elasticity', 'Magnetism', 'Sonic Scream', 'Duplication',
  'Illusion', 'Density Control', 'Weather Control', 'Technopathy',
]

const SUPERHERO_PATTERNS = [
  { value: 'The {{whimsy.adjective}} {{whimsy.creature}}', weight: 3 },
  { value: 'Captain {{whimsy.object}}', weight: 3 },
  { value: 'The {{whimsy.object}} of {{whimsy.place}}', weight: 2 },
  { value: '{{whimsy.adjective}} {{whimsy.object}}', weight: 2 },
  { value: 'Doctor {{whimsy.place}}', weight: 1 },
]

/** Peaks, named the way a survey names them rather than the way a myth does. */
const PEAK_PATTERNS = [
  'Mount {{whimsy.object}}',
  '{{whimsy.adjective}} {{whimsy.place}}',
  'The {{whimsy.creature}}s Tooth',
  '{{whimsy.object}} Pike',
  '{{whimsy.adjective}} Crag',
]

/**
 * Stars and their planets, in the two registers astronomy actually uses: a catalogue
 * designation for the star and a Bayer-style letter for the planet.
 */
const STAR_PATTERNS = [
  '{{whimsy.object}} Majoris',
  '{{whimsy.adjective}} {{whimsy.creature}}i',
  'HD 1#####',
  '{{whimsy.place}} Borealis',
]

// ---------------------------------------------------------------------------
// Technobabble
// ---------------------------------------------------------------------------

/**
 * The one that came back from the scope cut.
 *
 * `hacker phrases` were on the list of namespaces deliberately absent, because faker's were
 * a word list nobody could account for. Composed from this project's own vocabulary they
 * pass the same test everything else here passes: there is no fact of the matter about
 * whether you can bypass a redundant SSL matrix, because the sentence does not mean
 * anything. The vocabulary is ordinary technical English a dictionary carries.
 */
const TECH_NOUNS = [
  'protocol', 'bus', 'matrix', 'firewall', 'bandwidth', 'array', 'interface', 'circuit',
  'driver', 'monitor', 'card', 'sensor', 'feed', 'panel', 'port', 'transmitter',
]

const TECH_VERBS = [
  'bypass', 'quantify', 'index', 'transmit', 'synthesize', 'compress', 'override',
  'reboot', 'calculate', 'parse', 'navigate', 'connect', 'generate', 'copy',
]

/**
 * The same verbs as gerunds, stored rather than derived.
 *
 * The first draft appended a bare `ing` to `tech_verb` and produced `overrideing`,
 * `navigateing` and `transmiting` — eight of the fourteen were wrong, because English
 * gerunds drop a final `e` and double a final consonant after a short vowel. That is
 * morphology, and the project already refused to fake morphology once, when Slavic street
 * names were excluded for inflecting the stem. gofakeit reached the same conclusion and
 * ships a separate `HackeringVerb` list.
 */
const TECH_GERUNDS = [
  'bypassing', 'quantifying', 'indexing', 'transmitting', 'synthesizing', 'compressing',
  'overriding', 'rebooting', 'calculating', 'parsing', 'navigating', 'connecting',
  'generating', 'copying',
]

const TECH_ADJECTIVES = [
  'redundant', 'auxiliary', 'digital', 'solid-state', 'multi-byte', 'primary',
  'back-end', 'cross-platform', 'virtual', 'optical', 'neural', 'wireless',
  'open-source', 'mobile', 'haptic', 'bluetooth',
]

const TECHNOBABBLE_PATTERNS = [
  'If we {{whimsy.tech_verb}} the {{whimsy.tech_noun}}, we can get to the '
    + '{{whimsy.tech_adjective}} {{whimsy.tech_noun}} through the '
    + '{{whimsy.tech_adjective}} {{whimsy.tech_noun}}',
  'We need to {{whimsy.tech_verb}} the {{whimsy.tech_adjective}} {{whimsy.tech_noun}}',
  'Try to {{whimsy.tech_verb}} the {{whimsy.tech_noun}}, maybe it will '
    + '{{whimsy.tech_verb}} the {{whimsy.tech_adjective}} {{whimsy.tech_noun}}',
  'You cannot {{whimsy.tech_verb}} the {{whimsy.tech_noun}} without '
    + '{{whimsy.tech_gerund}} the {{whimsy.tech_adjective}} {{whimsy.tech_noun}}',
]

// ---------------------------------------------------------------------------
// Coffee and tea
// ---------------------------------------------------------------------------

/** Roast levels and processes — terms of art, checkable, and nobody's property. */
const ROASTS = [
  'Light Roast', 'Medium Roast', 'Dark Roast', 'Filter Roast', 'Espresso Roast',
  'Washed', 'Natural', 'Honey Process', 'Anaerobic', 'Decaf',
]

const COFFEE_PATTERNS = [
  '{{whimsy.adjective}} {{whimsy.place}} {{beverage.roast}}',
  '{{whimsy.object}} {{beverage.roast}}',
  'The {{whimsy.adjective}} {{whimsy.creature}} {{beverage.roast}}',
  '{{whimsy.place}} Reserve {{beverage.roast}}',
]

const TEA_BASES = [
  'Black Tea', 'Green Tea', 'White Tea', 'Oolong', 'Rooibos', 'Chai', 'Herbal Infusion',
  'Pu-erh', 'Matcha', 'Yerba Mate',
]

const TEA_PATTERNS = [
  '{{whimsy.adjective}} {{whimsy.place}} {{beverage.tea_base}}',
  '{{whimsy.object}} {{beverage.tea_base}}',
  '{{whimsy.place}} Morning {{beverage.tea_base}}',
  '{{whimsy.adjective}} {{whimsy.creature}} {{beverage.tea_base}}',
]

export async function run({ locales }) {
  if (!locales.includes('en')) throw new Error('authored-fixtures needs the `en` locale')
  return {
    contributions: {
      en: {
        'system.error_component': COMPONENTS,
        'system.error_constraint': CONSTRAINTS,
        'system.error_database': DATABASE_ERRORS,
        'system.error_http': HTTP_ERRORS,
        'system.error_runtime': RUNTIME_ERRORS,
        'system.error_validation': VALIDATION_ERRORS,

        'commerce.review_aspect': REVIEW_ASPECTS,
        'commerce.review_praise': REVIEW_PRAISE,
        'commerce.review_complaint': REVIEW_COMPLAINTS,
        'commerce.review_pattern': REVIEW_PATTERNS,
        'commerce.review_title_pattern': REVIEW_TITLE_PATTERNS,

        'whimsy.cuisine': CUISINES,
        'whimsy.restaurant_pattern': RESTAURANT_PATTERNS,
        'whimsy.dish_pattern': DISH_PATTERNS,
        'whimsy.dish_treatment': DISH_TREATMENTS,
        'whimsy.dish_base': DISH_BASES,
        'whimsy.dish_form': DISH_FORMS,
        'whimsy.dish_side': DISH_SIDES,
        'whimsy.school_kind': SCHOOL_KINDS,
        'whimsy.school_pattern': SCHOOL_PATTERNS,
        'whimsy.faculty': FACULTIES,
        'whimsy.power': POWERS,
        'whimsy.superhero_pattern': SUPERHERO_PATTERNS,
        'whimsy.peak_pattern': PEAK_PATTERNS,
        'whimsy.star_pattern': STAR_PATTERNS,
        'whimsy.tech_noun': TECH_NOUNS,
        'whimsy.tech_verb': TECH_VERBS,
        'whimsy.tech_gerund': TECH_GERUNDS,
        'whimsy.tech_adjective': TECH_ADJECTIVES,
        'whimsy.technobabble_pattern': TECHNOBABBLE_PATTERNS,

        'beverage.roast': ROASTS,
        'beverage.coffee_pattern': COFFEE_PATTERNS,
        'beverage.tea_base': TEA_BASES,
        'beverage.tea_pattern': TEA_PATTERNS,
      },
    },
    stats: {
      errors: DATABASE_ERRORS.length + HTTP_ERRORS.length + RUNTIME_ERRORS.length
        + VALIDATION_ERRORS.length,
      reviewPatterns: REVIEW_PATTERNS.length,
      words: CUISINES.length + DISH_TREATMENTS.length + DISH_BASES.length
        + DISH_SIDES.length + POWERS.length + TECH_NOUNS.length + TECH_VERBS.length
        + TECH_ADJECTIVES.length,
    },
  }
}
