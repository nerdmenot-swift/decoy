/**
 * Decoy's own invented things, for the fields a schema has and no registry describes.
 *
 * Fills:
 *   en  whimsy.adjective, whimsy.creature, whimsy.object, whimsy.place
 *   en  whimsy.codename_pattern, whimsy.band_pattern, whimsy.room, whimsy.ssid
 *   en  whimsy.excuse, whimsy.talk_pattern, whimsy.buzz_topic
 *   en  sport.club_pattern, sport.venue_pattern, sport.trophy_pattern, sport.discipline
 *   en  beverage.beer_pattern, beverage.whisky_pattern, beverage.wine_pattern, ...
 *
 * The word pools are shared across all three namespaces rather than duplicated. They are
 * this project's stock of ordinary evocative English, and a football club, a brewery and a
 * project codename all want the same thing from them.
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
/**
 * Talk titles, which needed a second variable slot.
 *
 * The first draft was seven patterns over eighteen topics: 126 possible titles, which fails
 * the standard the name floor sets elsewhere in this project — a two-hundred-row fixture
 * would repeat every one of them. Composition only pays when more than one thing varies,
 * and a template with a single slot is a list wearing a pattern's clothes.
 */
const TALK_PATTERNS = [
  '{{whimsy.buzz_topic}} at Scale',
  'Considered Harmful: Rethinking {{whimsy.buzz_topic}}',
  'What I Learned Migrating {{whimsy.buzz_topic}}',
  '{{whimsy.buzz_topic}}: A Postmortem',
  'Stop Doing {{whimsy.buzz_topic}}',
  'The Hidden Cost of {{whimsy.buzz_topic}}',
  '{{whimsy.buzz_topic}} Without the Tears',
  '{{whimsy.buzz_topic}}: Lessons from {{whimsy.place}}',
  'From {{whimsy.object}} to {{whimsy.buzz_topic}}',
  '{{whimsy.buzz_topic}} and the {{whimsy.adjective}} {{whimsy.object}}',
  'Why We Rewrote {{whimsy.buzz_topic}} in {{whimsy.place}}',
  'Ten Years of {{whimsy.buzz_topic}}: A {{whimsy.adjective}} Retrospective',
]

const BUZZ_TOPICS = [
  'Event Sourcing', 'Service Meshes', 'Monorepos', 'Feature Flags', 'Observability',
  'Schema Migrations', 'Caching', 'Retries', 'Idempotency', 'Blue-Green Deploys',
  'Distributed Tracing', 'Rate Limiting', 'Eventual Consistency', 'Circuit Breakers',
  'Immutable Infrastructure', 'Chaos Testing', 'Zero-Downtime Cutovers', 'Backpressure',
  'Sharding', 'Message Queues', 'Config Management', 'Dependency Pinning', 'Type Safety',
  'Code Review', 'Incident Response', 'On-Call Rotations', 'Load Shedding', 'Batch Jobs',
  'Data Lineage', 'Access Control', 'Secret Rotation', 'Cold Starts', 'Connection Pooling',
  'Log Aggregation', 'Canary Releases', 'Rollback Strategy', 'Test Fixtures', 'Seed Data',
]

/**
 * Football club naming, which is a small and very well-defined grammar.
 *
 * British clubs are `{place} {suffix}` almost without exception, and the suffix set is
 * closed enough that a supporter could recite it. The places come from the invented
 * landscape pool rather than from real towns, which is what keeps `Fjord Rovers` from
 * colliding with anybody's actual club — the pattern is authentic and the input is not.
 */
const CLUB_SUFFIXES = [
  'United', 'City', 'Rovers', 'Wanderers', 'Athletic', 'Albion', 'Town', 'County',
  'Rangers', 'Thistle', 'Harriers', 'Casuals', 'Academicals', 'Victoria',
]

const CLUB_PATTERNS = [
  { value: '{{whimsy.place}} {{sport.club_suffix}}', weight: 5 },
  { value: '{{whimsy.creature}} {{sport.club_suffix}}', weight: 3 },
  { value: '{{whimsy.adjective}} {{whimsy.place}} FC', weight: 2 },
  { value: '{{whimsy.place}} {{whimsy.creature}}s', weight: 2 },
]

const VENUE_PATTERNS = [
  'The {{whimsy.object}} Ground',
  '{{whimsy.place}} Park',
  '{{whimsy.adjective}} {{whimsy.place}} Stadium',
  'The {{whimsy.place}} Arena',
]

const TROPHY_PATTERNS = [
  'The {{whimsy.object}} Cup',
  'The {{whimsy.adjective}} {{whimsy.object}} Trophy',
  'The {{whimsy.place}} Shield',
]

/**
 * Sports themselves, which are a factual list rather than an invented one.
 *
 * The same category as `vehicle.type` and `finance.transaction_type`: short, closed, and
 * checkable by anybody reading it. Football is a sport in the way a saloon is a body style,
 * and neither is a trademark.
 */
const DISCIPLINES = [
  'Football', 'Cricket', 'Rugby Union', 'Rugby League', 'Basketball', 'Ice Hockey',
  'Field Hockey', 'Athletics', 'Cycling', 'Rowing', 'Netball', 'Handball', 'Volleyball',
  'Sailing', 'Fencing', 'Archery', 'Judo', 'Swimming', 'Badminton', 'Squash',
]

/**
 * Drinks, split the same way everything else here is: the *style* is a fact and the
 * *name* is an invention.
 *
 * An IPA is a style of beer and a Merlot is a grape, in the way that a saloon is a body
 * style — generic terms anybody can check, carried for the same reason `vehicle.type` is.
 * What is composed is the brand on the label, because a list of real breweries is a list of
 * real trademarks and that is precisely what got `music` and `book` cut from this project.
 */
const BEER_STYLES = [
  'IPA', 'Pale Ale', 'Stout', 'Porter', 'Lager', 'Pilsner', 'Saison', 'Gose', 'Bitter',
  'Wheat Beer', 'Amber Ale', 'Barleywine', 'Dubbel', 'Tripel', 'Sour', 'Helles', 'Bock',
  'Brown Ale', 'Kölsch', 'Mild',
]

const BEER_PATTERNS = [
  { value: '{{whimsy.adjective}} {{whimsy.creature}} {{beverage.beer_style}}', weight: 5 },
  { value: '{{whimsy.creature}} {{beverage.beer_style}}', weight: 2 },
  { value: '{{whimsy.place}} {{beverage.beer_style}}', weight: 2 },
]

const BREWERY_PATTERNS = [
  '{{whimsy.place}} Brewing Co.',
  '{{whimsy.creature}} & Sons',
  'The {{whimsy.adjective}} {{whimsy.object}} Brewery',
]

/**
 * Whisky, where the naming convention is itself the joke — `Glen` is simply Gaelic for
 * valley, and half of Speyside is named that way.
 */
const AGE_STATEMENTS = [
  '10 Year Old', '12 Year Old', '15 Year Old', '18 Year Old', '21 Year Old',
  '25 Year Old', 'Small Batch', 'Cask Strength', 'Single Cask', 'Sherry Finish',
]

const WHISKY_PATTERNS = [
  { value: 'Glen {{whimsy.place}} {{beverage.age_statement}}', weight: 4 },
  { value: '{{whimsy.place}} {{beverage.age_statement}}', weight: 3 },
  // `Reserve` rather than `Cask`, because two of the age statements are `Cask Strength`
  // and `Single Cask` and the pair produced `Bittern's Cask Single Cask`.
  { value: '{{whimsy.creature}}\'s Reserve {{beverage.age_statement}}', weight: 2 },
]

/** Grape varieties, a factual list for the same reason the beer styles are. */
const GRAPES = [
  'Merlot', 'Syrah', 'Riesling', 'Chardonnay', 'Pinot Noir', 'Sauvignon Blanc',
  'Cabernet Sauvignon', 'Grenache', 'Tempranillo', 'Nebbiolo', 'Sangiovese', 'Malbec',
  'Viognier', 'Gewürztraminer', 'Chenin Blanc', 'Barbera', 'Carménère', 'Albariño',
]

const WINE_PATTERNS = [
  '{{whimsy.adjective}} {{whimsy.place}} {{beverage.grape}}',
  '{{whimsy.place}} Estate {{beverage.grape}}',
  '{{whimsy.creature}} Ridge {{beverage.grape}}',
]

const COCKTAIL_PATTERNS = [
  'The {{whimsy.adjective}} {{whimsy.object}}',
  'The {{whimsy.creature}}',
  '{{whimsy.adjective}} {{whimsy.place}}',
  'The {{whimsy.object}} Sour',
]

/**
 * Pubs, which have the richest naming grammar in this file and one of the oldest.
 *
 * A British pub is `The {noun} & {noun}` or `The {adjective} {creature}`, and the form
 * predates literacy — the sign had to be describable by someone who could not read it.
 * That is why the compositions here are concrete: a crimson heron can be painted, and
 * `The Abstract Synergy` cannot.
 */
const PUB_PATTERNS = [
  { value: 'The {{whimsy.creature}} & {{whimsy.object}}', weight: 4 },
  { value: 'The {{whimsy.adjective}} {{whimsy.creature}}', weight: 4 },
  { value: 'The {{whimsy.object}} & Crown', weight: 2 },
  { value: 'The Old {{whimsy.object}}', weight: 2 },
  { value: 'The {{whimsy.creature}}s Arms', weight: 2 },
]

/**
 * Board games: an invented title and a factual mechanic.
 *
 * `Worker Placement` is a category of game the way `IPA` is a category of beer — a term of
 * art anybody can check, and not anybody's property. The titles compose, because a list of
 * real board games is a list of trademarks.
 */
const GAME_MECHANICS = [
  'Deck-Building', 'Worker Placement', 'Area Control', 'Tile Placement', 'Roll and Write',
  'Set Collection', 'Push Your Luck', 'Hidden Role', 'Engine Building', 'Drafting',
  'Cooperative', 'Legacy', 'Trick-Taking', 'Auction', 'Route Building', 'Deduction',
]

const BOARD_GAME_PATTERNS = [
  { value: 'The {{whimsy.place}} Expedition', weight: 3 },
  { value: '{{whimsy.adjective}} {{whimsy.object}}', weight: 3 },
  { value: '{{whimsy.creature}} & {{whimsy.object}}', weight: 2 },
  { value: 'Rise of the {{whimsy.creature}}s', weight: 2 },
  { value: '{{whimsy.place}}: {{whimsy.adjective}} {{whimsy.object}}', weight: 1 },
]

/**
 * Racehorses, which are named under a real constraint worth honouring: eighteen characters
 * and no duplicates of a horse still competing. Short evocative pairs are what the rule
 * produces, and it is why the naming reads the way it does.
 */
const HORSE_PATTERNS = [
  '{{whimsy.adjective}} {{whimsy.object}}',
  '{{whimsy.adjective}} {{whimsy.place}}',
  '{{whimsy.creature}} Song',
  '{{whimsy.adjective}} Dancer',
]

/**
 * Paint and nail-varnish colours, a genre built on the joke that the name says nothing
 * about the colour. `Restless Tundra` could be any shade at all, which is the point.
 */
const PAINT_PATTERNS = [
  '{{whimsy.adjective}} {{whimsy.place}}',
  '{{whimsy.adjective}} {{whimsy.object}}',
  '{{whimsy.creature}} Feather',
  '{{whimsy.adjective}} Morning',
]

/** Ships, in the naval register and the merchant one. */
const SHIP_PATTERNS = [
  'HMS {{whimsy.object}}',
  'The {{whimsy.adjective}} {{whimsy.creature}}',
  'The {{whimsy.object}} of {{whimsy.place}}',
  'The {{whimsy.adjective}} {{whimsy.place}}',
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
        'whimsy.pub_pattern': PUB_PATTERNS,
        'whimsy.board_game_pattern': BOARD_GAME_PATTERNS,
        'whimsy.game_mechanic': GAME_MECHANICS,
        'whimsy.horse_pattern': HORSE_PATTERNS,
        'whimsy.paint_pattern': PAINT_PATTERNS,
        'whimsy.ship_pattern': SHIP_PATTERNS,

        'sport.club_suffix': CLUB_SUFFIXES,
        'sport.club_pattern': CLUB_PATTERNS,
        'sport.venue_pattern': VENUE_PATTERNS,
        'sport.trophy_pattern': TROPHY_PATTERNS,
        'sport.discipline': DISCIPLINES,

        'beverage.beer_style': BEER_STYLES,
        'beverage.beer_pattern': BEER_PATTERNS,
        'beverage.brewery_pattern': BREWERY_PATTERNS,
        'beverage.age_statement': AGE_STATEMENTS,
        'beverage.whisky_pattern': WHISKY_PATTERNS,
        'beverage.grape': GRAPES,
        'beverage.wine_pattern': WINE_PATTERNS,
        'beverage.cocktail_pattern': COCKTAIL_PATTERNS,
      },
    },
    stats: {
      adjectives: ADJECTIVES.length,
      creatures: CREATURES.length,
      patterns: ROOM_PATTERNS.length + CODENAME_PATTERNS.length + BAND_PATTERNS.length,
    },
  }
}
