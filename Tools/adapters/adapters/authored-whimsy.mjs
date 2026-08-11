/**
 * Decoy's own invented things, for the fields a schema has and no registry describes.
 *
 * Fills:
 *   en  whimsy.adjective, whimsy.creature, whimsy.object, whimsy.place
 *   en  whimsy.codename_pattern, whimsy.band_pattern, whimsy.room, whimsy.ssid
 *   en  whimsy.excuse, whimsy.talk_pattern, whimsy.buzz_topic
 *
 * ## Why this is allowed where an animal list was not
 *
 * The other adapters answer to something. A German street type is right or wrong; a Polish
 * given-name frequency is right or wrong; whether Antigua and Barbuda has the ISO code `AG`
 * is right or wrong. Everything in this project is built so those can be checked, and the
 * cost of that discipline is that data nobody publishes cannot be shipped.
 *
 * This file is the one category where the discipline has nothing to bite on, because
 * **there is no fact of the matter**. `The Amber Cartographers` is not a correct or an
 * incorrect band name. `Operation Silent Meridian` is not a mis-transcription of anything.
 * No speaker can find an error in them, no registry can contradict them, and no upstream
 * can silently change underneath them — so the entire apparatus of sources, hashes and
 * verification has nothing to do here, and its absence costs nothing.
 *
 * That is a narrower licence than "amusing content is fine". Real animals are a factual
 * list and real book titles are somebody's trademark; the first wants a source and the
 * second wants a lawyer. What is safe is *composition*: ordinary English words, owned by
 * this project, assembled by a pattern into something that did not exist before.
 *
 * ## The word pools are deliberately plain
 *
 * Every adjective and noun below is an ordinary English word a dictionary would carry. The
 * invention is in the assembly, not the vocabulary, which is what keeps the pools free of
 * anything to verify — and keeps the output printable, since a curated pool cannot produce
 * a combination the profanity blocklist would have to catch.
 *
 * ## Collision with something real
 *
 * A generator that composes two common words will occasionally name a real band, and that
 * is the same exposure `lastName()` has always had — which is why `novelSurname()` exists.
 * The mitigation here is the size of the space rather than a check: several thousand
 * combinations per pattern, none of them a list anybody curated to be recognisable.
 */

export const id = 'authored-whimsy'
export const source = 'decoy-authored'

/**
 * Evocative but ordinary. Grouped by initial letter, because `releaseName()` alliterates
 * and needs to find an adjective matching the creature it drew.
 */
const ADJECTIVES = [
  'Amber', 'Ancient', 'Auburn', 'Bitter', 'Brazen', 'Brittle', 'Copper', 'Crimson',
  'Cursive', 'Dappled', 'Distant', 'Drifting', 'Eager', 'Earnest', 'Endless', 'Feral',
  'Fleeting', 'Frosted', 'Gilded', 'Glacial', 'Grateful', 'Hollow', 'Humming', 'Hushed',
  'Idle', 'Immense', 'Iron', 'Jagged', 'Jovial', 'Keen', 'Kindred', 'Lucid', 'Luminous',
  'Molten', 'Mottled', 'Muted', 'Nimble', 'Northern', 'Noble', 'Opaline', 'Orbital',
  'Patient', 'Pewter', 'Prudent', 'Quiet', 'Quilted', 'Restless', 'Roaming', 'Rugged',
  'Sable', 'Silent', 'Solemn', 'Tidal', 'Tireless', 'Twilight', 'Umbral', 'Upright',
  'Vagrant', 'Velvet', 'Vivid', 'Wandering', 'Weathered', 'Willing', 'Zealous', 'Zesty',
]

/**
 * Creatures, which is where this brushes closest to the factual list that was refused.
 *
 * The difference is what the value is *for*. `animal.type()` would assert that these are
 * the animals; here a creature is one half of an invented compound, and `Feral Falcon` is
 * a release name rather than a claim about falcons. They are common nouns chosen for
 * sound, and no entry is load-bearing.
 *
 * Every one pluralises with a bare `-s`, which is a constraint rather than a coincidence:
 * the band pattern appends one, and the first draft produced `The Lucid Caribous`. Out went
 * albatross, ibis, walrus, lynx, dormouse, caribou and dingo — anything taking `-es`, an
 * irregular plural, or none at all — replaced by a bird or a mammal starting with the same
 * letter, because `releaseName()` alliterates and a missing letter costs more than a
 * missing species.
 */
const CREATURES = [
  'Antelope', 'Adder', 'Badger', 'Bittern', 'Curlew', 'Cormorant', 'Dunlin', 'Dipper',
  'Egret', 'Ermine', 'Falcon', 'Ferret', 'Gannet', 'Gecko', 'Heron', 'Hedgehog', 'Iguana',
  'Impala', 'Jackal', 'Jerboa', 'Kestrel', 'Kingfisher', 'Lemur', 'Lapwing', 'Magpie',
  'Marmot', 'Narwhal', 'Nightjar', 'Ocelot', 'Osprey', 'Panther', 'Pelican', 'Quail',
  'Quokka', 'Raven', 'Roebuck', 'Stoat', 'Sturgeon', 'Tapir', 'Tern', 'Urchin', 'Umbrette',
  'Viper', 'Vole', 'Warbler', 'Wombat', 'Yak', 'Zebu',
]

/** Objects with some weight to them, for codenames and room names. */
const OBJECTS = [
  'Anvil', 'Atlas', 'Beacon', 'Bellows', 'Cipher', 'Compass', 'Crucible', 'Dial',
  'Ledger', 'Lantern', 'Lattice', 'Meridian', 'Mortar', 'Obelisk', 'Pennant', 'Prism',
  'Quiver', 'Rampart', 'Sextant', 'Signal', 'Spindle', 'Tessera', 'Thimble', 'Turnstile',
  'Vessel', 'Weathervane',
]

/** Landscape words, which read well as meeting rooms and as the back half of a codename. */
const PLACES = [
  'Basin', 'Cairn', 'Causeway', 'Cove', 'Delta', 'Escarpment', 'Estuary', 'Fjord',
  'Foothill', 'Harbour', 'Headland', 'Hollow', 'Isthmus', 'Lagoon', 'Marsh', 'Moor',
  'Narrows', 'Plateau', 'Quarry', 'Ravine', 'Reef', 'Ridge', 'Shoal', 'Steppe',
  'Thicket', 'Tundra',
]

/**
 * Wi-Fi network names, which are the one place in this file where the joke is the point.
 *
 * Left as whole strings rather than composed, because the humour is in the specific pun
 * and a generator would produce the shape without the joke.
 */
const SSIDS = [
  'Pretty Fly for a WiFi', 'Bill Wi the Science Fi', 'The LAN Before Time',
  'Drop It Like Its Hotspot', 'Wu-Tang LAN', 'Silence of the LANs', 'Nacho WiFi',
  'Panic at the Cisco', 'Get Off My LAN', 'It Burns When IP', 'LAN Solo',
  'The Promised LAN', 'Abraham Linksys', 'Router? I Hardly Know Her',
  'Winternet Is Coming', 'No More Mister WiFi', 'Hide Yo Kids Hide Yo WiFi',
  'Tell My WiFi Love Her', 'Untrusted Network', 'FBI Surveillance Van',
]

/**
 * Incident excuses, for the ticket and postmortem columns every internal tool has.
 *
 * Plausible rather than absurd, because a fixture that reads as obviously fake stops being
 * useful for judging how a column looks when it is full.
 */
const EXCUSES = [
  'the certificate expired again',
  'someone rotated the key without telling anyone',
  'a migration ran twice',
  'the cron job and the deploy landed in the same minute',
  'DNS',
  'the retry storm made it worse',
  'a config flag was set in staging and not in production',
  'the disk filled with logs about the disk filling',
  'the load balancer health check was checking itself',
  'an upstream changed a field type without a version bump',
  'the clock on one node drifted',
  'a dependency published a patch release',
  'the feature flag defaulted to on',
  'the backup restore had never been tested',
  'a regex was greedy',
  'someone force-pushed to main',
]

/** Meeting rooms, the way offices actually name them. */
const ROOM_PATTERNS = [
  'The {{whimsy.object}}',
  'The {{whimsy.place}}',
  '{{whimsy.adjective}} {{whimsy.place}}',
  'The {{whimsy.creature}}',
]

/**
 * Codenames, in the two registers a real project uses: the military one and the shy one.
 */
const CODENAME_PATTERNS = [
  'Operation {{whimsy.adjective}} {{whimsy.object}}',
  'Operation {{whimsy.adjective}} {{whimsy.creature}}',
  'Project {{whimsy.object}}',
  'Project {{whimsy.adjective}} {{whimsy.place}}',
]

/** Band names, weighted towards the definite-article form because that is how they run. */
const BAND_PATTERNS = [
  { value: 'The {{whimsy.adjective}} {{whimsy.creature}}s', weight: 4 },
  { value: 'The {{whimsy.object}}s', weight: 2 },
  { value: '{{whimsy.adjective}} {{whimsy.place}}', weight: 2 },
  { value: '{{whimsy.creature}} {{whimsy.object}}', weight: 1 },
]

/** Conference talks, in the shapes a real programme is full of. */
const TALK_PATTERNS = [
  '{{whimsy.buzz_topic}} at Scale',
  'Considered Harmful: Rethinking {{whimsy.buzz_topic}}',
  'What I Learned Migrating {{whimsy.buzz_topic}}',
  '{{whimsy.buzz_topic}}: A Postmortem',
  'Stop Doing {{whimsy.buzz_topic}}',
  'The Hidden Cost of {{whimsy.buzz_topic}}',
  '{{whimsy.buzz_topic}} Without the Tears',
]

const BUZZ_TOPICS = [
  'Event Sourcing', 'Service Meshes', 'Monorepos', 'Feature Flags', 'Observability',
  'Schema Migrations', 'Caching', 'Retries', 'Idempotency', 'Blue-Green Deploys',
  'Distributed Tracing', 'Rate Limiting', 'Eventual Consistency', 'Circuit Breakers',
  'Immutable Infrastructure', 'Chaos Testing', 'Zero-Downtime Cutovers', 'Backpressure',
]

export async function run({ locales }) {
  if (!locales.includes('en')) throw new Error('authored-whimsy needs the `en` locale')
  return {
    contributions: {
      en: {
        'whimsy.adjective': ADJECTIVES,
        'whimsy.creature': CREATURES,
        'whimsy.object': OBJECTS,
        'whimsy.place': PLACES,
        'whimsy.room_pattern': ROOM_PATTERNS,
        'whimsy.codename_pattern': CODENAME_PATTERNS,
        'whimsy.band_pattern': BAND_PATTERNS,
        'whimsy.talk_pattern': TALK_PATTERNS,
        'whimsy.buzz_topic': BUZZ_TOPICS,
        'whimsy.ssid': SSIDS,
        'whimsy.excuse': EXCUSES,
      },
    },
    stats: {
      adjectives: ADJECTIVES.length,
      creatures: CREATURES.length,
      patterns: ROOM_PATTERNS.length + CODENAME_PATTERNS.length + BAND_PATTERNS.length,
    },
  }
}
