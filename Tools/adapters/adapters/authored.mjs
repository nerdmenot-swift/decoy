/**
 * Decoy's own data, for the fields no registry publishes.
 *
 * Every other adapter here reads somebody else's file. This one does not, and that is a
 * deliberate exception to the rule the strategy doc opens with — *no data is
 * hand-edited* — so it is worth being precise about why the exception is safe.
 *
 * That rule exists to stop an unaudited list being pasted into the repository and
 * acquiring authority it never earned: a thousand surnames from nowhere, unverifiable,
 * unattributable, quietly wrong. The lists below are the opposite case. They are short,
 * closed, checkable by anyone reading them, and — critically — **there is nothing to cite
 * because nobody publishes a registry of them**. No standards body maintains the list of
 * car manufacturers, or bicycle types, or the words people use for colours. Searching
 * harder does not produce one.
 *
 * Given that, there were two options: delete the generators, or write the data. Deleting
 * `vehicle.manufacturer()` because no institution has blessed a list of car makes is the
 * wrong trade for a fixture library, so this file exists. It is original content, owned by
 * this project, distributed under the same Apache-2.0 licence as the code — which means it
 * adds no dependency and no obligation.
 *
 * ## Rules for anything added here
 *
 * 1. **Try to cite first.** Most things have a source; four rounds of searching moved
 *    counties, subdivisions, phone formats, name patterns, status codes, JOSE algorithms,
 *    Latin vocabulary and job titles out of this category. Only add here after looking.
 * 2. **English only, with one narrow exception.** These are not translations. A locale
 *    without its own data falls through to English, which is what already happens for
 *    wordnet vocabulary, commerce words and job titles. Inventing a German list of *content*
 *    would be inventing German.
 *
 *    The exception is a closed set of ordinary words whose members are not in doubt --
 *    the compass points, and the street types below. `straße` means street and `platz`
 *    means square; writing them down is translating a short list, not authoring one, and
 *    a speaker can check every entry at a glance. The test is whether being wrong would
 *    be *visible*: a wrong street type is obvious to anyone who reads the language, where
 *    a wrong surname or a wrong colour name is not.
 *
 *    It applies to vocabulary and never to stems. Inventing German street *names* would be
 *    inventing German, which is why streets are composed from real surnames rather than
 *    listed, and why the languages that inflect the stem are left out entirely.
 * 3. **Facts where possible.** `color.human` is the CSS/X11 named-colour set, which is at
 *    least a de-facto standard rather than a preference; `vehicle.fuel` is what fuels
 *    exist. Prefer the enumerable over the imagined.
 * 4. **Short enough to read.** If a list needs hundreds of entries to be plausible, that
 *    is a sign it wants a source, not an author.
 */

export const id = 'authored'
export const source = 'decoy-authored'

/**
 * Colour names, from the CSS Color Module's named-colour set.
 *
 * These began as X11's `rgb.txt` and became a web standard by being implemented
 * everywhere, so the *names* are a de-facto registry even though no localized one exists.
 * CLDR carries no colour names in any locale, which was checked, so the other
 * thirty-three locales that had faker's translations fall through to English.
 */
const COLOURS = [
  'aqua', 'azure', 'beige', 'black', 'blue', 'brown', 'chartreuse', 'chocolate', 'coral',
  'crimson', 'cyan', 'fuchsia', 'gold', 'gray', 'green', 'indigo', 'ivory', 'khaki',
  'lavender', 'lime', 'magenta', 'maroon', 'mint green', 'navy', 'olive', 'orange',
  'orchid', 'pink', 'plum', 'purple', 'red', 'salmon', 'sea green', 'sienna', 'silver',
  'sky blue', 'tan', 'teal', 'thistle', 'tomato', 'turquoise', 'violet', 'wheat', 'white',
  'yellow',
]

/** Colour models, which are named by the specifications that define them. */
const COLOUR_SPACES = [
  'CMY', 'CMYK', 'HSB', 'HSI', 'HSL', 'HSLA', 'HSV', 'HWB', 'LCH', 'LAB', 'RGB', 'RGBA',
  'XYZ', 'YCbCr', 'YIQ', 'YUV',
]

/**
 * Vehicles. No standards body maintains a list of car makes — the closest is NHTSA's
 * vehicle API, which is live and unversioned and therefore unpinnable, which is recorded
 * in the strategy doc as a known gap.
 */
const VEHICLE_MANUFACTURERS = [
  'Alfa Romeo', 'Aston Martin', 'Audi', 'BMW', 'Bentley', 'Bugatti', 'Buick', 'Cadillac',
  'Chevrolet', 'Chrysler', 'Citroën', 'Dacia', 'Dodge', 'Ferrari', 'Fiat', 'Ford',
  'Genesis', 'Honda', 'Hyundai', 'Infiniti', 'Jaguar', 'Jeep', 'Kia', 'Lamborghini',
  'Land Rover', 'Lexus', 'Lotus', 'Maserati', 'Mazda', 'McLaren', 'Mercedes-Benz', 'Mini',
  'Mitsubishi', 'Nissan', 'Opel', 'Peugeot', 'Polestar', 'Porsche', 'Renault',
  'Rolls-Royce', 'Rivian', 'Saab', 'Seat', 'Škoda', 'Subaru', 'Suzuki', 'Tesla', 'Toyota',
  'Vauxhall', 'Volkswagen', 'Volvo',
]

const VEHICLE_MODELS = [
  'Alpina', 'Aventador', 'Beetle', 'Camry', 'Ceed', 'Charger', 'Civic', 'Clio', 'Corolla',
  'Corsa', 'Cybertruck', 'Defender', 'Discovery', 'Duster', 'Escape', 'Explorer', 'Fiesta',
  'Focus', 'Golf', 'Impreza', 'Ioniq', 'Jetta', 'Land Cruiser', 'Leaf', 'Malibu',
  'Mustang', 'Navara', 'Outback', 'Panda', 'Passat', 'Prius', 'Q5', 'Ranger', 'Rio',
  'Sportage', 'Tucson', 'Wrangler', 'XC40', 'Yaris', 'Zoe',
]

const VEHICLE_TYPES = [
  'Cargo Van', 'Convertible', 'Coupe', 'Crossover', 'Estate', 'Hatchback', 'Minivan',
  'Passenger Van', 'Pickup Truck', 'SUV', 'Saloon', 'Sedan', 'Sports Car', 'Wagon',
]

/** What actually goes in the tank, which is enumerable rather than invented. */
const VEHICLE_FUELS = [
  'Biodiesel', 'Compressed Natural Gas', 'Diesel', 'Electric', 'Ethanol', 'Gasoline',
  'Hybrid', 'Hydrogen', 'Liquefied Petroleum Gas', 'Plug-in Hybrid',
]

const BICYCLE_TYPES = [
  'BMX Bike', 'Cargo Bike', 'City Bike', 'Cruiser Bicycle', 'Cyclocross Bicycle',
  'Electric Bike', 'Folding Bike', 'Gravel Bicycle', 'Hybrid Bicycle', 'Mountain Bicycle',
  'Recumbent Bicycle', 'Road Bicycle', 'Tandem Bicycle', 'Touring Bicycle', 'Track Bicycle',
]

/**
 * Aircraft and airlines.
 *
 * The airport list comes from OpenFlights via `airport-data`, which ships airports and
 * nothing else; OpenFlights publishes `airlines.dat` separately and unversioned.
 */
/**
 * Both are **composite** rows rather than lists, and finding that out cost a test
 * failure: `airline()` and `airplane()` call `drawRow`, so a flat list of names leaves
 * them returning an empty dictionary. The codes are the reason the composite exists — a
 * row that pairs an airline with somebody else's designator is worse than no row.
 *
 * The names and codes are facts. IATA assigns them, and while IATA sells the complete
 * register, the designators of well-known carriers and aircraft are published everywhere
 * and checkable by anyone. A short list of verifiable pairs is the honest form this can
 * take without buying a licence to the whole thing.
 */
const AIRPLANES = [
  { name: 'Airbus A220', iataTypeCode: '223' },
  { name: 'Airbus A319', iataTypeCode: '319' },
  { name: 'Airbus A320', iataTypeCode: '320' },
  { name: 'Airbus A321', iataTypeCode: '321' },
  { name: 'Airbus A330', iataTypeCode: '330' },
  { name: 'Airbus A350', iataTypeCode: '350' },
  { name: 'Airbus A380', iataTypeCode: '380' },
  { name: 'ATR 42', iataTypeCode: 'AT4' },
  { name: 'ATR 72', iataTypeCode: 'AT7' },
  { name: 'Boeing 737', iataTypeCode: '737' },
  { name: 'Boeing 747', iataTypeCode: '747' },
  { name: 'Boeing 757', iataTypeCode: '757' },
  { name: 'Boeing 767', iataTypeCode: '767' },
  { name: 'Boeing 777', iataTypeCode: '777' },
  { name: 'Boeing 787', iataTypeCode: '787' },
  { name: 'Bombardier CRJ700', iataTypeCode: 'CR7' },
  { name: 'Bombardier CRJ900', iataTypeCode: 'CR9' },
  { name: 'De Havilland Dash 8', iataTypeCode: 'DH8' },
  { name: 'Embraer E175', iataTypeCode: 'E75' },
  { name: 'Embraer E190', iataTypeCode: 'E90' },
]

const AIRLINES = [
  { name: 'Aer Lingus', iataCode: 'EI' },
  { name: 'Aeroflot', iataCode: 'SU' },
  { name: 'Air Canada', iataCode: 'AC' },
  { name: 'Air France', iataCode: 'AF' },
  { name: 'Air India', iataCode: 'AI' },
  { name: 'Air New Zealand', iataCode: 'NZ' },
  { name: 'Alaska Airlines', iataCode: 'AS' },
  { name: 'American Airlines', iataCode: 'AA' },
  { name: 'Austrian Airlines', iataCode: 'OS' },
  { name: 'British Airways', iataCode: 'BA' },
  { name: 'Cathay Pacific', iataCode: 'CX' },
  { name: 'Delta Air Lines', iataCode: 'DL' },
  { name: 'Emirates', iataCode: 'EK' },
  { name: 'Finnair', iataCode: 'AY' },
  { name: 'Iberia', iataCode: 'IB' },
  { name: 'Japan Airlines', iataCode: 'JL' },
  { name: 'KLM', iataCode: 'KL' },
  { name: 'Korean Air', iataCode: 'KE' },
  { name: 'LATAM Airlines', iataCode: 'LA' },
  { name: 'Lufthansa', iataCode: 'LH' },
  { name: 'Norwegian', iataCode: 'DY' },
  { name: 'Qantas', iataCode: 'QF' },
  { name: 'Qatar Airways', iataCode: 'QR' },
  { name: 'Ryanair', iataCode: 'FR' },
  { name: 'SAS', iataCode: 'SK' },
  { name: 'Singapore Airlines', iataCode: 'SQ' },
  { name: 'Southwest Airlines', iataCode: 'WN' },
  { name: 'Swiss', iataCode: 'LX' },
  { name: 'TAP Air Portugal', iataCode: 'TP' },
  { name: 'Turkish Airlines', iataCode: 'TK' },
  { name: 'United Airlines', iataCode: 'UA' },
  { name: 'Vietnam Airlines', iataCode: 'VN' },
  { name: 'Virgin Atlantic', iataCode: 'VS' },
]

/** Free-mail hosts, which are facts about which services exist. */
const FREE_EMAIL = ['gmail.com', 'hotmail.com', 'icloud.com', 'outlook.com', 'proton.me', 'yahoo.com']

/**
 * Reserved for documentation and examples by RFC 2606, so an address at one can never
 * reach a real mailbox. The one entry here that genuinely is a citation.
 */
const EXAMPLE_EMAIL = ['example.com', 'example.net', 'example.org']

/**
 * Street suffixes, and the pattern that composes a street name from one.
 *
 * The hardest call in this file, and the one to reopen first if a source ever appears.
 *
 * There is no gazetteer of streets that can be used. OpenStreetMap has every street in
 * the world under ODbL, which is share-alike and therefore unusable in an Apache-2.0
 * distribution. Nothing else is comprehensive.
 *
 * So a faker-free corpus composes streets rather than listing them, and composes them
 * with *English* suffixes in every locale, because writing German and Japanese street
 * vocabulary would be inventing German and Japanese. `Schäfer Street` in a German fixture
 * is worse than `Bohnenkampsweg`, and that is the measured cost of the independence —
 * stated here rather than discovered by somebody looking at their test data.
 *
 * The suffixes themselves are the USPS standard set, which is a published fact about
 * American addressing rather than a preference. The pattern draws on surnames and given
 * names, which is how English street names are actually formed.
 */
const STREET_SUFFIXES = [
  'Alley', 'Avenue', 'Boulevard', 'Bridge', 'Brook', 'Burg', 'Bypass', 'Canyon', 'Cape',
  'Causeway', 'Center', 'Circle', 'Cliff', 'Common', 'Corner', 'Court', 'Cove', 'Creek',
  'Crescent', 'Crest', 'Crossing', 'Dale', 'Dam', 'Divide', 'Drive', 'Estate', 'Expressway',
  'Extension', 'Fall', 'Ferry', 'Field', 'Flat', 'Ford', 'Forest', 'Forge', 'Fork', 'Fort',
  'Freeway', 'Garden', 'Gateway', 'Glen', 'Green', 'Grove', 'Harbor', 'Haven', 'Heights',
  'Highway', 'Hill', 'Hollow', 'Island', 'Junction', 'Key', 'Knoll', 'Lake', 'Landing',
  'Lane', 'Light', 'Loaf', 'Lock', 'Lodge', 'Manor', 'Meadow', 'Mews', 'Mill', 'Mission',
  'Motorway', 'Mount', 'Mountain', 'Neck', 'Orchard', 'Oval', 'Overpass', 'Park', 'Parkway',
  'Pass', 'Passage', 'Path', 'Pike', 'Pine', 'Place', 'Plain', 'Plaza', 'Point', 'Port',
  'Prairie', 'Radial', 'Ramp', 'Ranch', 'Rapid', 'Rest', 'Ridge', 'River', 'Road', 'Route',
  'Row', 'Rue', 'Run', 'Shoal', 'Shore', 'Skyway', 'Spring', 'Spur', 'Square', 'Station',
  'Stravenue', 'Stream', 'Street', 'Summit', 'Terrace', 'Throughway', 'Trace', 'Track',
  'Trafficway', 'Trail', 'Tunnel', 'Turnpike', 'Underpass', 'Union', 'Valley', 'Viaduct',
  'View', 'Village', 'Ville', 'Vista', 'Walk', 'Wall', 'Way', 'Well', 'Wharf',
]

/**
 * The rest of an address: the number on the door, the flat within it, and how a street
 * address is assembled from them.
 *
 * libaddressinput gives the *layout* of an address and the postcode shape, but says
 * nothing about house numbering, because there is nothing to say — no country publishes a
 * rule for it. `####` is a four-digit number, which is what the masks elsewhere mean.
 */
const BUILDING_NUMBER = ['%##', '%###', '%####', '%#']

/**
 * How other languages build a street name, for the languages where that is settled.
 *
 * The note above says writing German street vocabulary would be inventing German. On
 * reflection that is too broad, and the distinction worth drawing is between the *stem* of
 * a street name and its *type*. Inventing stems would indeed be inventing German -- there
 * is no way to know that Bohnenkamp is a real Hamburg street rather than a plausible
 * string. But `straße`, `weg` and `platz` are ordinary nouns meaning street, way and
 * square, and writing them down is translation of a closed set, the same thing already
 * done for the compass points a few lines above.
 *
 * Wikidata was tried for the vocabulary first and is not usable here. Its "street" item is
 * a formal concept -- "public thoroughfare in a built environment" -- and the label a
 * language attaches to it is often the technical register rather than the everyday word:
 * German returns `Innerortsstraße` and Italian `strada urbana`, while `Straße` and `strada`
 * come back under "road". The same shape of mismatch that made CLDR's coordinate labels
 * unusable for the compass.
 *
 * Two families, because they compose differently and the difference is orthography rather
 * than preference:
 *
 *   - Germanic languages compound, with no space: Schillerstraße, Kalverstraat,
 *     Drottninggatan. The type is written lower case and joined to the stem.
 *   - Romance languages put the type first as a separate word: Rue Lafayette, Calle
 *     Serrano, Via Garibaldi, Rua Augusta.
 *
 * Turkish is neither, and puts the type last as its own word: Atatürk Caddesi.
 *
 * ## What is deliberately not here
 *
 * Only languages whose street formation can be stated without qualification. Polish,
 * Czech and Russian inflect the stem -- a street named for Piłsudski is `ulica
 * Piłsudskiego`, not `ulica Piłsudski` -- and generating the genitive correctly is
 * grammar, not a list. Getting it wrong produces something that reads as broken to a
 * speaker and fine to everybody else, which is the worst failure available. Those locales
 * keep the English fallback until somebody who reads the language writes the rule.
 *
 * Japanese, Korean and Chinese are absent for a different reason: their addresses number
 * blocks rather than naming streets, and `location.postal_address` already renders them
 * that way.
 */
const STREET_TYPES = {
  // Germanic: compounded onto the surname, lower case.
  de: ['straße', 'weg', 'gasse', 'platz', 'allee', 'ring', 'damm', 'ufer', 'steig', 'hof'],
  nl: ['straat', 'weg', 'laan', 'plein', 'gracht', 'kade', 'dijk', 'singel', 'hof'],
  sv: ['gatan', 'vägen', 'torget', 'gränden', 'backen', 'stigen'],
  da: ['gade', 'vej', 'allé', 'plads', 'stræde', 'have'],
  nb: ['gate', 'veien', 'plassen', 'stien', 'bakken'],
  // Romance: the type leads, as its own word.
  fr: ['Rue', 'Avenue', 'Boulevard', 'Place', 'Impasse', 'Allée', 'Chemin', 'Quai'],
  es: ['Calle', 'Avenida', 'Plaza', 'Paseo', 'Camino', 'Ronda', 'Travesía'],
  it: ['Via', 'Viale', 'Piazza', 'Corso', 'Vicolo', 'Largo', 'Lungomare'],
  pt: ['Rua', 'Avenida', 'Travessa', 'Praça', 'Largo', 'Alameda', 'Estrada'],
  // Turkish: the type trails, as its own word.
  tr: ['Sokak', 'Caddesi', 'Bulvarı', 'Meydanı', 'Yolu'],
  // British English, which trails its type the same way and draws on a different set from
  // American English. The USPS list `en` uses is a postal standard with `Stravenue`,
  // `Trafficway` and `Turnpike` in it; none of those is a British street type, and Britain
  // has `Close`, `Crescent`, `Mews` and `Gardens`, which the USPS set lacks.
  en_GB: [
    'Road', 'Street', 'Lane', 'Avenue', 'Close', 'Drive', 'Way', 'Crescent', 'Gardens',
    'Grove', 'Place', 'Court', 'Terrace', 'Rise', 'View', 'Walk', 'Hill', 'Park', 'Row',
    'Mews', 'Square', 'Green',
  ],
}

/** Which locales take which language's street formation. */
const STREET_LOCALES = {
  de: ['de', 'de_AT', 'de_CH'],
  nl: ['nl', 'nl_BE'],
  sv: ['sv'],
  da: ['da'],
  nb: ['nb_NO'],
  fr: ['fr', 'fr_BE', 'fr_CA', 'fr_CH', 'fr_LU', 'fr_SN'],
  es: ['es', 'es_MX'],
  it: ['it'],
  pt: ['pt_BR', 'pt_PT'],
  tr: ['tr'],
  en_GB: ['en_GB'],
}

const COMPOUNDING = new Set(['de', 'nl', 'sv', 'da', 'nb'])
// English and Turkish both put the type last as a separate word: `Yıldırım Bulvarı`,
// `Bramson Road`.
const TYPE_TRAILS = new Set(['tr', 'en_GB'])

/**
 * The pattern that composes a street name in one language.
 *
 * Surnames dominate over given names in every one of these languages, which is why the
 * weights match the English pattern's: streets are named after people by surname, and
 * `Rue Marie` is far rarer than `Rue Lafayette`.
 */
function streetPatternFor(language) {
  if (COMPOUNDING.has(language)) {
    // No space, and the surname keeps its capital: Schillerstraße.
    return [
      { value: '{{person.lastName}}{{location.street_suffix}}', weight: 8 },
      { value: '{{person.firstName}}{{location.street_suffix}}', weight: 2 },
    ]
  }
  if (TYPE_TRAILS.has(language)) {
    return [
      { value: '{{person.lastName}} {{location.street_suffix}}', weight: 8 },
      { value: '{{person.firstName}} {{location.street_suffix}}', weight: 2 },
    ]
  }
  return [
    { value: '{{location.street_suffix}} {{person.lastName}}', weight: 8 },
    { value: '{{location.street_suffix}} {{person.firstName}}', weight: 2 },
  ]
}

/**
 * Where the house number goes, and how big it gets.
 *
 * English-speaking countries lead with the number -- 46 Crosslin Turnpike -- and almost
 * nowhere else does. German is `Hauptstraße 5`, Italian `Via Roma 12`, Swedish
 * `Drottninggatan 5`, Turkish `Atatürk Caddesi 5`. French is the exception among these and
 * keeps the English order: `12 Rue de Rivoli`.
 *
 * The size matters too and is easy to miss. The English set runs to five digits because US
 * addresses really do -- 38722 is an ordinary number on a long road -- and applying it
 * elsewhere produced `Simonring 38722`, which is not a German address. European numbering
 * restarts per street, so one to three digits is the range.
 */
const NUMBER_LEADS = new Set(['fr', 'en_GB'])
const EUROPEAN_BUILDING_NUMBER = ['%', '%#', '%##']

function streetAddressFor(language) {
  if (NUMBER_LEADS.has(language)) {
    return {
      normal: ['{{location.buildingNumber}} {{location.street}}'],
      full: ['{{location.buildingNumber}} {{location.street}} {{location.secondaryAddress}}'],
    }
  }
  return {
    normal: ['{{location.street}} {{location.buildingNumber}}'],
    full: ['{{location.street}} {{location.buildingNumber}} {{location.secondaryAddress}}'],
  }
}

/**
 * The locales whose street names this file composes.
 *
 * Kept as an export after faker-js went, because it was the load-bearing half of removing
 * faker's street lists: where a pattern here composes a street from a surname, faker's list
 * of real streets for that locale was compiled and never read, and this was how the other
 * adapter knew which ones to drop.
 */
export const STREET_COMPOSED_LOCALES = new Set(Object.values(STREET_LOCALES).flat())

/** Builds the per-locale street contributions from the tables above. */
function streetContributions() {
  const out = {}
  for (const [language, locales] of Object.entries(STREET_LOCALES)) {
    for (const code of locales) {
      out[code] = {
        'location.street_suffix': STREET_TYPES[language],
        'location.street_pattern': streetPatternFor(language),
        'location.street_address': streetAddressFor(language),
        'location.building_number': EUROPEAN_BUILDING_NUMBER,
      }
    }
  }
  return out
}
const SECONDARY_ADDRESS = ['Apt. ###', 'Suite ###', 'Unit ###', 'Flat #', 'Floor #']
const STREET_ADDRESS = {
  normal: ['{{location.buildingNumber}} {{location.street}}'],
  full: ['{{location.buildingNumber}} {{location.street}} {{location.secondaryAddress}}'],
}

const STREET_PATTERN = [
  { value: '{{person.lastName}} {{location.street_suffix}}', weight: 6 },
  { value: '{{person.firstName}} {{location.street_suffix}}', weight: 3 },
  { value: '{{location.direction.cardinal}} {{person.lastName}} {{location.street_suffix}}', weight: 1 },
]

/** Compass points. Closed, ancient, and not published by anybody as a registry. */
const CARDINAL = ['North', 'East', 'South', 'West']
const CARDINAL_ABBR = ['N', 'E', 'S', 'W']
const ORDINAL = ['Northeast', 'Northwest', 'Southeast', 'Southwest']
const ORDINAL_ABBR = ['NE', 'NW', 'SE', 'SW']

/** The twelve western zodiac signs, which is a closed set of long standing. */
const ZODIAC = [
  'Aquarius', 'Aries', 'Cancer', 'Capricorn', 'Gemini', 'Leo', 'Libra', 'Pisces',
  'Sagittarius', 'Scorpio', 'Taurus', 'Virgo',
]

/**
 * Sex and gender.
 *
 * `person.sex` is the two values a birth register records, because that is what the field
 * means and what the gendered name lists are keyed by. `person.gender` is broader by
 * design, since the thing it models is broader. Neither list claims to be exhaustive and
 * both are here rather than cited because no registry of gender identities exists.
 */
const SEX = ['female', 'male']
const GENDER = [
  'Agender', 'Bigender', 'Female', 'Genderfluid', 'Genderqueer', 'Male', 'Non-binary',
  'Transgender',
]

/**
 * Profile bios, of the kind a social account carries.
 *
 * Composed from a role and an enthusiasm because that is how they read in life:
 * "developer", "coffee enthusiast", "dog lover". faker built these from a pattern with
 * four component lists and an emoji; this is the same idea with the pieces written here.
 */
const BIO_PARTS = [
  'accountant', 'adventurer', 'amateur baker', 'aspiring novelist', 'baker',
  'beer enthusiast', 'bookworm', 'cat lover', 'certified nerd', 'chef', 'chocolate lover',
  'coffee enthusiast', 'creator', 'cyclist', 'designer', 'developer', 'dog lover',
  'dreamer', 'engineer', 'entrepreneur', 'explorer', 'film buff', 'foodie', 'gamer',
  'gardener', 'guitarist', 'hiker', 'introvert', 'investor', 'journalist', 'keen runner',
  'knitter', 'lifelong learner', 'maker', 'musician', 'nature lover', 'optimist',
  'organiser', 'painter', 'photographer', 'plant parent', 'podcaster', 'problem solver',
  'reader', 'researcher', 'runner', 'scientist', 'storyteller', 'tea drinker', 'teacher',
  'tinkerer', 'traveller', 'volunteer', 'writer',
]

/** Post-nominals. English only; a locale with its own honorifics shadows these. */
const NAME_SUFFIXES = ['Jr.', 'Sr.', 'I', 'II', 'III', 'IV', 'V', 'MD', 'DDS', 'PhD', 'DVM']

/**
 * Unix directory paths, which exist rather than being invented — these are the
 * Filesystem Hierarchy Standard's, plus the ones macOS adds.
 */
const DIRECTORY_PATHS = [
  '/bin', '/boot', '/dev', '/etc', '/etc/defaults', '/home', '/home/user',
  '/home/user/dir', '/lib', '/media', '/mnt', '/opt', '/private', '/proc', '/root',
  '/sbin', '/srv', '/sys', '/tmp', '/usr', '/usr/bin', '/usr/lib', '/usr/local',
  '/usr/local/bin', '/usr/local/src', '/usr/sbin', '/usr/share', '/usr/src', '/var',
  '/var/log', '/var/mail', '/var/spool', '/var/tmp',
]

/**
 * Browser user-agent strings, as a pattern.
 *
 * The version numbers are masked rather than fixed, so a fixture set does not look like
 * it was captured on one machine on one afternoon. The shapes are the real ones the four
 * major engines emit.
 */
const USER_AGENT_PATTERN = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    + 'Chrome/1##.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like '
    + 'Gecko) Version/1#.# Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:1##.0) Gecko/20100101 Firefox/1##.0',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    + 'Chrome/1##.0.0.0 Safari/537.36',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 1#_# like Mac OS X) AppleWebKit/605.1.15 (KHTML, '
    + 'like Gecko) Version/1#.# Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (Linux; Android 1#; SM-G99#B) AppleWebKit/537.36 (KHTML, like Gecko) '
    + 'Chrome/1##.0.0.0 Mobile Safari/537.36',
]

/**
 * Federal Reserve routing symbols — the first four digits of a US routing number.
 *
 * The Fed publishes the full directory, behind a form and without a stable URL, so these
 * are the district and processing-centre prefixes rather than the whole register. The
 * check digit `routingNumber()` appends is computed, so the result validates.
 */
const ROUTING_SYMBOLS = [
  '0110', '0111', '0112', '0113', '0210', '0211', '0212', '0213', '0219', '0260', '0280',
  '0310', '0311', '0312', '0313', '0410', '0412', '0420', '0430', '0440', '0510', '0514',
  '0519', '0520', '0530', '0540', '0550', '0560', '0610', '0611', '0613', '0620', '0630',
  '0640', '0650', '0670', '0710', '0711', '0712', '0719', '0720', '0724', '0730', '0739',
  '0740', '0749', '0750', '0810', '0812', '0819', '0820', '0829', '0830', '0839', '0840',
  '0910', '0912', '0918', '0919', '0920', '0929', '0960', '1010', '1011', '1019', '1020',
  '1030', '1040', '1110', '1111', '1119', '1120', '1130', '1140', '1210', '1211', '1220',
  '1230', '1240', '1250', '1260', '1270', '1280', '1290', '3210', '3220',
]

/** Database vocabulary: what column names, types, engines and collations look like. */
const DB_COLUMNS = [
  'created_at', 'deleted_at', 'description', 'email', 'first_name', 'group_id', 'id',
  'last_name', 'name', 'password', 'phone', 'slug', 'status', 'title', 'token',
  'updated_at', 'user_id', 'uuid',
]
const DB_TYPES = [
  'bigint', 'blob', 'boolean', 'date', 'datetime', 'decimal', 'double', 'float', 'int',
  'json', 'numeric', 'real', 'smallint', 'text', 'time', 'timestamp', 'uuid', 'varchar',
]
const DB_ENGINES = ['ARCHIVE', 'BLACKHOLE', 'CSV', 'InnoDB', 'MEMORY', 'MyISAM']
const DB_COLLATIONS = [
  'ascii_bin', 'cp1250_general_ci', 'latin1_general_ci', 'utf8mb4_bin',
  'utf8mb4_general_ci', 'utf8mb4_unicode_ci',
]

/** Banking vocabulary. */
const ACCOUNT_TYPES = [
  'Auto Loan', 'Checking', 'Credit Card', 'Home Loan', 'Investment', 'Money Market',
  'Personal Loan', 'Savings',
]
const TRANSACTION_TYPES = ['deposit', 'invoice', 'payment', 'withdrawal']

/**
 * Closed-class function words, restored.
 *
 * These were dropped when their faker data went, on the grounds that nobody needs a
 * generated preposition. That was the wrong call under the rule this file follows: a
 * feature should not disappear because no institution publishes a list of English
 * prepositions. They are a closed class, so the list is very nearly complete rather than
 * a sample.
 */
const PREPOSITIONS = [
  'about', 'above', 'across', 'after', 'against', 'along', 'among', 'around', 'at',
  'before', 'behind', 'below', 'beneath', 'beside', 'between', 'beyond', 'by', 'despite',
  'down', 'during', 'except', 'for', 'from', 'in', 'inside', 'into', 'near', 'of', 'off',
  'on', 'onto', 'outside', 'over', 'past', 'since', 'through', 'throughout', 'to',
  'toward', 'under', 'underneath', 'until', 'up', 'upon', 'with', 'within', 'without',
]
const CONJUNCTIONS = [
  'after', 'although', 'and', 'as', 'because', 'before', 'but', 'either', 'for', 'however',
  'if', 'neither', 'nor', 'once', 'or', 'since', 'so', 'than', 'that', 'though', 'unless',
  'until', 'when', 'whenever', 'where', 'whereas', 'whether', 'while', 'yet',
]
const INTERJECTIONS = [
  'aha', 'alas', 'aw', 'bah', 'bravo', 'eh', 'gosh', 'ha', 'hey', 'hmm', 'hooray', 'huh',
  'hurrah', 'oh', 'ouch', 'oops', 'phew', 'shh', 'ugh', 'well', 'whoa', 'wow', 'yikes',
  'yippee',
]

/**
 * Company and product vocabulary.
 *
 * The most obviously invented data in the corpus, and the least apologetic: a company
 * catchphrase is invented by definition, and a registry of buzzwords would be a strange
 * thing for anybody to maintain.
 */
const COMPANY_ADJECTIVES = [
  'Adaptive', 'Advanced', 'Ameliorated', 'Assimilated', 'Automated', 'Balanced',
  'Business-focused', 'Centralized', 'Cloned', 'Compatible', 'Configurable',
  'Cross-platform', 'Customer-focused', 'Decentralized', 'De-engineered', 'Devolved',
  'Digitized', 'Distributed', 'Diverse', 'Down-sized', 'Enhanced', 'Enterprise-wide',
  'Ergonomic', 'Exclusive', 'Expanded', 'Extended', 'Focused', 'Front-line',
  'Fully-configurable', 'Fundamental', 'Future-proofed', 'Grass-roots', 'Horizontal',
  'Implemented', 'Innovative', 'Integrated', 'Intuitive', 'Inverse', 'Managed',
  'Mandatory', 'Monitored', 'Multi-channelled', 'Multi-layered', 'Networked',
  'Object-based', 'Open-architected', 'Open-source', 'Operative', 'Optimized', 'Optional',
  'Organic', 'Organized', 'Persevering', 'Persistent', 'Phased', 'Polarized',
  'Pre-emptive', 'Proactive', 'Profit-focused', 'Profound', 'Programmable', 'Progressive',
  'Public-key', 'Quality-focused', 'Reactive', 'Realigned', 'Re-contextualized',
  'Re-engineered', 'Reduced', 'Reverse-engineered', 'Right-sized', 'Robust', 'Seamless',
  'Secured', 'Self-enabling', 'Sharable', 'Stand-alone', 'Streamlined', 'Switchable',
  'Synchronized', 'Synergistic', 'Synergized', 'Team-oriented', 'Total', 'Triple-buffered',
  'Universal', 'Up-sized', 'Upgradable', 'User-centric', 'User-friendly', 'Versatile',
  'Virtual', 'Visionary', 'Vision-oriented',
]

const COMPANY_DESCRIPTORS = [
  '24hour', '24/7', '3rdgeneration', '4thgeneration', '5thgeneration', '6thgeneration',
  'actuating', 'analyzing', 'assymetric', 'asynchronous', 'attitude-oriented', 'background',
  'bandwidth-monitored', 'bi-directional', 'bifurcated', 'bottom-line', 'clear-thinking',
  'client-driven', 'client-server', 'coherent', 'cohesive', 'composite', 'context-sensitive',
  'contextually-based', 'content-based', 'dedicated', 'demand-driven', 'didactic',
  'directional', 'discrete', 'disintermediate', 'dynamic', 'eco-centric', 'empowering',
  'encompassing', 'even-keeled', 'executive', 'explicit', 'exuding', 'fault-tolerant',
  'foreground', 'fresh-thinking', 'full-range', 'global', 'grid-enabled', 'heuristic',
  'high-level', 'holistic', 'homogeneous', 'human-resource', 'hybrid', 'impactful',
  'incremental', 'intangible', 'interactive', 'intermediate', 'leading edge', 'local',
  'logistical', 'maximized', 'methodical', 'mission-critical', 'mobile', 'modular',
  'motivating', 'multimedia', 'multi-state', 'multi-tasking', 'national', 'needs-based',
  'neutral', 'next generation', 'non-volatile', 'object-oriented', 'optimal', 'optimizing',
  'radical', 'real-time', 'reciprocal', 'regional', 'responsive', 'scalable', 'secondary',
  'solution-oriented', 'stable', 'static', 'systematic', 'systemic', 'system-worthy',
  'tangible', 'tertiary', 'transitional', 'uniform', 'upward-trending', 'user-facing',
  'value-added', 'web-enabled', 'well-modulated', 'zero administration', 'zero defect',
  'zero tolerance',
]

const COMPANY_NOUNS = [
  'ability', 'access', 'adapter', 'algorithm', 'alliance', 'analyzer', 'application',
  'approach', 'architecture', 'archive', 'artificial intelligence', 'array', 'attitude',
  'benchmark', 'budgetary management', 'capability', 'capacity', 'challenge', 'circuit',
  'collaboration', 'complexity', 'concept', 'conglomeration', 'contingency', 'core',
  'customer loyalty', 'database', 'data-warehouse', 'definition', 'emulation', 'encoding',
  'encryption', 'extranet', 'firmware', 'flexibility', 'focus group', 'forecast',
  'frame', 'framework', 'function', 'functionalities', 'Graphic Interface', 'groupware',
  'Graphical User Interface', 'hardware', 'help-desk', 'hierarchy', 'hub', 'implementation',
  'info-mediaries', 'infrastructure', 'initiative', 'installation', 'instruction set',
  'interface', 'internet solution', 'intranet', 'knowledge user', 'knowledge base',
  'local area network', 'leverage', 'matrices', 'matrix', 'methodology', 'middleware',
  'migration', 'model', 'moderator', 'monitoring', 'moratorium', 'neural-net',
  'open architecture', 'open system', 'orchestration', 'paradigm', 'parallelism', 'policy',
  'portal', 'pricing structure', 'process improvement', 'product', 'productivity',
  'project', 'projection', 'protocol', 'secured line', 'service-desk', 'software',
  'solution', 'standardization', 'strategy', 'structure', 'success', 'superstructure',
  'support', 'synergy', 'system engine', 'task-force', 'throughput', 'time-frame',
  'toolset', 'utilisation', 'website', 'workforce',
]

const BUZZ_VERBS = [
  'aggregate', 'architect', 'benchmark', 'brand', 'cultivate', 'deliver', 'deploy',
  'disintermediate', 'drive', 'e-enable', 'embrace', 'empower', 'enable', 'engage',
  'engineer', 'enhance', 'envisioneer', 'evolve', 'expedite', 'exploit', 'extend',
  'facilitate', 'generate', 'grow', 'harness', 'implement', 'incentivize', 'incubate',
  'innovate', 'integrate', 'iterate', 'leverage', 'matrix', 'maximize', 'mesh',
  'monetize', 'morph', 'optimize', 'orchestrate', 'productize', 'recontextualize',
  'redefine', 'reintermediate', 'reinvent', 'repurpose', 'revolutionize', 'scale',
  'seize', 'strategize', 'streamline', 'syndicate', 'synergize', 'synthesize', 'target',
  'transform', 'transition', 'unleash', 'utilize', 'visualize', 'whiteboard',
]

const BUZZ_ADJECTIVES = [
  '24/365', '24/7', 'B2B', 'B2C', 'back-end', 'best-of-breed', 'bleeding-edge',
  'bricks-and-clicks', 'clicks-and-mortar', 'collaborative', 'compelling', 'cross-media',
  'cross-platform', 'customized', 'cutting-edge', 'distributed', 'dot-com', 'dynamic',
  'e-business', 'efficient', 'end-to-end', 'enterprise', 'extensible', 'frictionless',
  'front-end', 'global', 'granular', 'holistic', 'impactful', 'innovative', 'integrated',
  'interactive', 'intuitive', 'killer', 'leading-edge', 'magnetic', 'mission-critical',
  'next-generation', 'one-to-one', 'open-source', 'out-of-the-box', 'plug-and-play',
  'proactive', 'real-time', 'revolutionary', 'rich', 'robust', 'scalable', 'seamless',
  'sexy', 'sticky', 'strategic', 'synergistic', 'transparent', 'turn-key', 'ubiquitous',
  'user-centric', 'value-added', 'vertical', 'viral', 'virtual', 'visionary', 'web-enabled',
  'wireless', 'world-class',
]

const BUZZ_NOUNS = [
  'action-items', 'applications', 'architectures', 'bandwidth', 'channels', 'communities',
  'content', 'convergence', 'deliverables', 'e-business', 'e-commerce', 'e-markets',
  'e-services', 'e-tailers', 'experiences', 'eyeballs', 'functionalities', 'infomediaries',
  'infrastructures', 'initiatives', 'interfaces', 'markets', 'methodologies', 'metrics',
  'mindshare', 'models', 'networks', 'niches', 'paradigms', 'partnerships', 'platforms',
  'portals', 'relationships', 'ROI', 'schemas', 'services', 'solutions', 'supply-chains',
  'synergies', 'systems', 'technologies', 'users', 'vortals', 'web services', 'web-readiness',
]

/**
 * The role half of a job title, for locales with no flat list of occupations.
 *
 * `en` gets O*NET's 941 real occupations and `jobTitle()` prefers a flat list where one
 * exists, so these compose only where it does not.
 */
const JOB_TYPES = [
  'Administrator', 'Agent', 'Analyst', 'Architect', 'Assistant', 'Associate', 'Consultant',
  'Coordinator', 'Designer', 'Developer', 'Director', 'Engineer', 'Executive',
  'Facilitator', 'Manager', 'Officer', 'Orchestrator', 'Planner', 'Producer',
  'Representative', 'Specialist', 'Strategist', 'Supervisor', 'Technician',
]

/**
 * Japanese addresses and company names, which have no European shape at all.
 *
 * Japan does not name its streets. An address narrows by nested area — prefecture, city,
 * district — and then gives a block, a lot and a building: `9丁目5番7号` is chōme 9, ban 5,
 * gō 7. There is no street to put a number on, so the English composition of a house
 * number beside a street name has nothing to attach to, and `ja` addresses came out as
 * `94 あつこ Well` once faker's patterns went — a Japanese given name with an English
 * street type.
 *
 * `location.postal_address` was already right, because libaddressinput knows the layout
 * (`〒{{zipCode}}` first, name last). What was missing is the block itself, which faker had
 * supplied and nothing replaced.
 *
 * Company names run the other way from English too: the legal form trails the name rather
 * than being joined to it, and 株式会社 is written out where English abbreviates to Ltd.
 */
const JAPANESE = {
  // `#` is filled by the same substitution that turns `###` into a house number.
  'location.building_number': ['%丁目%番%号', '%#丁目%番%号', '%丁目%#番%号'],
  'location.street_address': {
    normal: ['{{location.buildingNumber}}'],
    full: ['{{location.buildingNumber}} {{location.secondaryAddress}}'],
  },
  // `streetName()` requires a pattern, and for Japanese the honest answer to "what is the
  // street called" is the block designation, which is what an address actually carries.
  'location.street_pattern': ['{{location.buildingNumber}}'],
  'company.name_pattern': [
    { value: '{{person.lastName}}{{company.legal_entity_type}}', weight: 6 },
    { value: '{{person.lastName}}{{company.category}}{{company.legal_entity_type}}', weight: 4 },
  ],
  // The pattern above puts a sector between the surname and the legal form, so an English
  // sector list produced 谷田部Telecommunications合同会社 — a company name that is Japanese
  // at both ends and English in the middle. The trade names of Japanese firms carry these
  // words, which is why the pattern wants one.
  // Japanese has no prefixed honorific — さん and 様 follow the name — so the field is
  // declared empty rather than left to inherit `Dr.` from English. `null` is how a locale
  // says the concept does not exist here, and it blocks the fallback.
  'person.prefix': null,
  'company.category': [
    '情報', '保険', '建設', '商事', '運輸', '電機', '化学', '製薬', '食品', '銀行',
    '証券', '不動産', '印刷', '鉄鋼', '物流', '電力', '通信', '出版', '観光', '倉庫',
  ],
}

/**
 * English honorifics, which nothing supplied once faker went.
 *
 * The gap that `person.prefix()` fell into: English had no prefix of its own, every chain
 * ends at English, and `require` traps rather than returning empty. Azerbaijani found it
 * first, which is fitting — `az` declares the field explicitly empty because Azerbaijani
 * has no honorifics, and that declaration is the reason the mechanism exists at all. With
 * faker gone the declaration went too, so `az` walked the chain and found nothing to walk
 * to.
 *
 * No `generic` list, deliberately. `gendered()` prefers `generic` over the gendered lists,
 * so an English one was inherited by every locale that has honorifics of its own but no
 * generic — German has `Herr` and `Frau` and produced `Dr.` every single time, and so did
 * French, Spanish and Italian. The ungendered call now picks a sex and draws, which is what
 * it does for given names and for the same reason. `Dr.` and `Prof.` sit in both lists, so
 * nothing is lost by having no third one.
 */
const NAME_PREFIXES = {
  female: ['Miss', 'Mrs.', 'Ms.', 'Dr.', 'Prof.'],
  male: ['Mr.', 'Dr.', 'Prof.'],
}

/**
 * Issuer prefixes for `creditCardNumber()`, from ISO/IEC 7812.
 *
 * The leading digits that identify a card scheme, and the total length each scheme uses,
 * are published facts: every payment integration guide and the standard itself carry them.
 * `4` is Visa and always sixteen digits; American Express is `34` or `37` and fifteen.
 *
 * A trailing `L` means "append a Luhn check digit", which the generator computes, so each
 * pattern is one digit shorter than the number it produces. Getting that arithmetic wrong
 * yields cards of the wrong length that still pass Luhn — valid-looking and rejected by
 * every real validator, which is exactly the failure a fixture library must not have.
 */
const CREDIT_CARDS = {
  visa: ['4##############L'],
  mastercard: ['5[1-5]#############L', '2[2-7]#############L'],
  american_express: ['34############L', '37############L'],
  discover: ['6011###########L', '65#############L'],
  diners_club: ['30[0-5]#########L', '36#########L'],
  jcb: ['35#############L'],
}

/**
 * US ZIP ranges by state, and Canadian postcode letters by province.
 *
 * `postcode(state:)` exists so an address can be internally coherent rather than pairing
 * Alaska with a Florida ZIP, and it went dead when faker did.
 *
 * The ranges are USPS assignments, which are geographic and published. Patterns are
 * *derived* from them rather than written out, and only three-digit prefixes wholly inside
 * the range are kept -- so Alaska yields `996##` to `998##` and not `995##`, whose `##` can
 * reach 99500 where the state begins at 99501. A prefix only mostly inside would produce a
 * valid-looking ZIP belonging to no state, which is the failure this generator exists to
 * prevent.
 *
 * Written with `#` rather than as a regex range: `bothify` fills `#` and `?` and knows
 * nothing about `[0-6]`, so a first attempt shipped a literal bracket into the postcode.
 *
 * Canada needs a different care. Its postcodes never use D, F, I, O, Q or U, because those
 * read as digits -- and `?` draws from the whole alphabet, so the letters are fixed per
 * pattern rather than substituted. Each province gets one pattern per allowed letter,
 * trading some variety for every value being real.
 */
const US_ZIP_RANGES = {
  AL: [35004, 36925], AK: [99501, 99950], AZ: [85001, 86556], AR: [71601, 72959],
  CA: [90001, 96162], CO: [80001, 81658], CT: [6001, 6928], DE: [19701, 19980],
  DC: [20001, 20799], FL: [32003, 34997], GA: [30002, 31999], HI: [96701, 96898],
  ID: [83201, 83876], IL: [60001, 62999], IN: [46001, 47997], IA: [50001, 52809],
  KS: [66002, 67954], KY: [40003, 42788], LA: [70001, 71497], ME: [3901, 4992],
  MD: [20601, 21930], MA: [1001, 2791], MI: [48001, 49971], MN: [55001, 56763],
  MS: [38601, 39776], MO: [63001, 65899], MT: [59001, 59937], NE: [68001, 69367],
  NV: [88901, 89883], NH: [3031, 3897], NJ: [7001, 8989], NM: [87001, 88439],
  NY: [10001, 14975], NC: [27006, 28909], ND: [58001, 58856], OH: [43001, 45999],
  OK: [73001, 74966], OR: [97001, 97920], PA: [15001, 19640], RI: [2801, 2940],
  SC: [29001, 29948], SD: [57001, 57799], TN: [37010, 38589], TX: [75001, 79999],
  UT: [84001, 84791], VT: [5001, 5907], VA: [20101, 24658], WA: [98001, 99403],
  WV: [24701, 26886], WI: [53001, 54990], WY: [82001, 83128],
}

/**
 * Every prefix whose whole block falls inside the range, at the coarsest width that fits.
 *
 * Three digits first, because a wider block gives more variety. Some states are too narrow
 * for any hundred-block to sit entirely inside them -- Hawaii runs 96701 to 96898, so
 * `967##` starts one below and `968##` ends one above -- and those fall to four digits and
 * ten-blocks. Rhode Island is the same shape.
 *
 * Returning nothing rather than something slightly outside was the first behaviour, and it
 * made `postcode(state:)` return nil for two states while claiming to cover all fifty. A
 * narrower block is the right answer; no block is not.
 */
function zipPatternsFor([low, high]) {
  for (const width of [3, 4]) {
    const block = 10 ** (5 - width)
    const patterns = []
    for (let prefix = Math.ceil(low / block); (prefix + 1) * block - 1 <= high; prefix++) {
      patterns.push(String(prefix).padStart(width, '0') + '#'.repeat(5 - width))
    }
    if (patterns.length > 0) return patterns
  }
  throw new Error(`no ZIP prefix fits the range ${low}-${high}`)
}

const US_POSTCODE_BY_STATE = Object.fromEntries(
  Object.entries(US_ZIP_RANGES).map(([state, range]) => [state, zipPatternsFor(range)]),
)

/** The letters each province's postcodes begin with. */
const CANADIAN_PREFIXES = {
  NL: ['A'], NS: ['B'], PE: ['C'], NB: ['E'], QC: ['G', 'H', 'J'],
  ON: ['K', 'L', 'M', 'N', 'P'], MB: ['R'], SK: ['S'], AB: ['T'], BC: ['V'],
  NT: ['X'], NU: ['X'], YT: ['Y'],
}

const CANADIAN_LETTERS = [...'ABCEGHJKLMNPRSTVWXYZ']

const CANADIAN_POSTCODE_BY_STATE = Object.fromEntries(
  Object.entries(CANADIAN_PREFIXES).map(([province, firsts]) => [
    province,
    firsts.flatMap((first) =>
      CANADIAN_LETTERS.map(
        (letter, index) =>
          `${first}#${letter} #${CANADIAN_LETTERS[(index + 7) % CANADIAN_LETTERS.length]}#`,
      ),
    ),
  ]),
)

/**
 * A sample of real North American area codes and exchange prefixes.
 *
 * `areaCode()` documents itself as returning nil rather than a digit-shaped guess, because
 * "I do not know" and "here is a plausible fiction" are different answers. That reasoning
 * argues for a short list of codes that are genuinely assigned over a long list padded to
 * look thorough — every one of these is a real NANP area code, and anybody can check it.
 *
 * Exchange prefixes exclude `555`, which is reserved for fiction and would make every
 * generated number obviously fake, and `911`, `411` and `0`/`1` leading digits, which NANP
 * does not assign.
 */
const NANP_AREA_CODES = [
  '202', '212', '213', '215', '216', '303', '305', '312', '313', '404', '415', '416',
  '503', '504', '512', '514', '602', '604', '612', '617', '702', '713', '714', '804',
  '808', '813', '901', '902', '904', '917',
]
const NANP_EXCHANGE_CODES = [
  '201', '234', '246', '267', '281', '312', '347', '386', '407', '425', '456', '478',
  '512', '567', '602', '628', '646', '689', '712', '734', '786', '812', '862', '901',
]

/**
 * Industry sectors, for `company.category()`.
 *
 * English had none of its own: the path existed only in `ja`, `ko`, `uk` and `zh_CN`,
 * which use it in their company name patterns — 保険 for insurance, 물산 for trading. So a
 * public generator was reachable in four locales and trapped in the other seventy-two, and
 * would have trapped everywhere once faker went.
 *
 * Sectors rather than adjectives: what an industry is called is closer to a fact than to a
 * preference, and these are the divisions a stock index or a statistical classification
 * uses.
 */
const COMPANY_CATEGORIES = [
  'Aerospace', 'Agriculture', 'Automotive', 'Banking', 'Biotechnology', 'Chemicals',
  'Construction', 'Consulting', 'Defence', 'Education', 'Energy', 'Engineering',
  'Entertainment', 'Finance', 'Healthcare', 'Hospitality', 'Insurance', 'Logistics',
  'Manufacturing', 'Media', 'Mining', 'Pharmaceuticals', 'Publishing', 'Retail',
  'Shipping', 'Software', 'Telecommunications', 'Textiles', 'Transport', 'Utilities',
]

/**
 * How a company name is assembled, and the remaining patterns nothing else supplies.
 *
 * `company.name_pattern` composes from surnames and legal forms, which is how firms are
 * actually named — Dittmer-Kick, Grasse und Menga. The legal form comes from the ISO 20275
 * register; a locale without one gets the bare surname form.
 *
 * The list of English forms that used to live here has gone with it. It read
 * `Inc, LLC, Ltd, Group, Holdings, Partners`, and the last three are not legal entity
 * types at all — they are words that appear in company names. The register knows the
 * difference, and knows it per jurisdiction.
 */
const COMPANY_NAME_PATTERN = [
  { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
  { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
  { value: '{{person.lastName}}, {{person.lastName}} and {{person.lastName}}', weight: 2 },
]

/** The remaining composition rules, each naming only paths this file also supplies. */
const PRODUCT_NAME_PATTERN = [
  '{{commerce.productAdjective}} {{commerce.productMaterial}} {{commerce.product}}',
]
const JOB_TITLE_PATTERN = [
  '{{person.job_descriptor}} {{person.job_area}} {{person.job_type}}',
]
const BIO_PATTERN = [
  '{{person.bio_part}}',
  '{{person.bio_part}}, {{person.bio_part}}',
  '{{person.bio_part}} {{internet.emoji}}',
]
const TRANSACTION_DESCRIPTION_PATTERN = [
  '{{finance.transaction_type}} transaction at {{company.name}} using card ending with '
    + '{{string.numeric(4)}} for {{finance.amount}}',
]

/** Retail vocabulary, for product names and departments. */
const DEPARTMENTS = [
  'Automotive', 'Baby', 'Beauty', 'Books', 'Clothing', 'Computers', 'Electronics',
  'Games', 'Garden', 'Grocery', 'Health', 'Home', 'Industrial', 'Jewelery', 'Kids',
  'Movies', 'Music', 'Outdoors', 'Pet Supplies', 'Shoes', 'Sports', 'Tools', 'Toys',
]
const PRODUCTS = [
  'Bacon', 'Ball', 'Bench', 'Bike', 'Chair', 'Cheese', 'Chicken', 'Chips', 'Computer',
  'Fish', 'Gloves', 'Hat', 'Keyboard', 'Knife', 'Lamp', 'Mouse', 'Pants', 'Pizza',
  'Salad', 'Sausages', 'Shirt', 'Shoes', 'Soap', 'Table', 'Towels', 'Tuna',
]
const PRODUCT_ADJECTIVES = [
  'Awesome', 'Bespoke', 'Electronic', 'Elegant', 'Ergonomic', 'Fantastic', 'Generic',
  'Gorgeous', 'Handcrafted', 'Handmade', 'Incredible', 'Intelligent', 'Licensed',
  'Luxurious', 'Modern', 'Oriental', 'Practical', 'Recycled', 'Refined', 'Rustic',
  'Sleek', 'Small', 'Tasty', 'Unbranded',
]
const PRODUCT_DESCRIPTIONS = [
  'Boston\'s most advanced compression wear technology increases muscle oxygenation and '
    + 'stabilizes active muscles',
  'Carbonite web goalkeeper gloves are ergonomically designed to give easy fit',
  'Ergonomic executive chair upholstered in bonded black leather and PVC padded seat',
  'New range of formal shirts are designed keeping you in mind',
  'New ABC 13 9370, 13.3, 5th Gen CoreA5-8250U, 8GB RAM, 256GB SSD, power UHD Graphics',
  'The Football Is Good For Training And Recreational Purposes',
  'The Great Granite Chair has a comfortable seat and a sturdy frame',
  'The automobile layout consists of a front-engine design, with transaxle-type '
    + 'transmissions mounted at the rear of the engine',
  'The beautiful range of Apple Natural is a distinctive coffee blend',
  'The slim and elegant design combines with a powerful battery',
  'Andy shoes are designed to keeping in mind durability as well as trends',
]

const PRODUCT_MATERIALS = [
  'Bamboo', 'Bronze', 'Ceramic', 'Concrete', 'Cotton', 'Frozen', 'Granite', 'Leather',
  'Linen', 'Marble', 'Metal', 'Plastic', 'Rubber', 'Silk', 'Soft', 'Steel', 'Wooden',
]

/**
 * Locales that block English honorifics rather than inherit them.
 *
 * Every chain ends at English, and English carries `person.prefix`. So a locale that says
 * nothing about honorifics does not get none — it gets *Mr.*, *Dr.* and *Prof.*, in a
 * language that may have no prefixed honorific at all. Azerbaijani full names were coming
 * out as "Dr. Nazir Novruzəliyev", at the 7-in-100 weight the prefix variant carries.
 *
 * The mechanism to stop this already existed and worked: `null` means the concept does
 * not exist here, and it blocks the fallback. Japanese uses it, which is why Japanese was
 * never affected. The declarations for everywhere else lived in faker-js, and when faker
 * was removed they went with it — only Japanese was restored. The comment in
 * `lib/patterns.mjs` claiming this was fixed reads true because the *resolver* honours
 * nulls correctly; there were simply no nulls left for it to honour.
 *
 * Blocking is the safe default rather than the finished answer. A missing honorific is
 * never wrong; a wrong-language one always is. Several of these languages do have prefixed
 * honorifics — German Herr/Frau, French M./Mme, Spanish Sr./Sra. are already supplied by
 * their own locales and are absent from this list — and the ones below should get real
 * data source by source rather than a guess. Turkish belongs here permanently: Bey and
 * Hanım follow the name, so a prefix is wrong in the same way it is for Japanese.
 *
 * Locales inheriting from a same-language ancestor are deliberately absent: es_MX takes
 * Spanish honorifics from `es`, fr_CA and fr_SN take French from `fr`, and the en_*
 * family takes English from `en`, all of which is correct.
 */
const NO_PREFIXED_HONORIFIC = [
  'ar', 'az', 'bn_BD', 'cs_CZ', 'cy', 'da', 'el', 'fa', 'fi', 'he', 'hr', 'hu', 'hy',
  'id_ID', 'ka_GE', 'ko', 'lv', 'mk', 'nb_NO', 'pl', 'pt_BR', 'ro', 'ro_MD', 'ru', 'sk',
  'sl_SI', 'sr_RS_latin', 'sv', 'tr', 'uk', 'vi', 'yo_NG', 'zh_CN', 'zh_TW',
]

/**
 * Adds the block without disturbing anything a locale already contributes.
 *
 * Merged rather than spread: object spread replaces a key outright, and five of the
 * locales above (da, nb_NO, pt_BR, sv, tr) already receive street data from
 * `streetContributions()`. A second spread would have silently discarded it.
 */
function withBlockedHonorifics(contributions) {
  for (const code of NO_PREFIXED_HONORIFIC) {
    contributions[code] = { ...contributions[code], 'person.prefix': null }
  }
  return contributions
}

export async function run() {
  return {
    contributions: withBlockedHonorifics({
      ...streetContributions(),
      // `base` for anything language-neutral enough that falling through to it is right,
      // `en` for anything that is plainly English and should be shadowed by a locale that
      // knows better.
      base: {
        'color.space': COLOUR_SPACES,
        'internet.free_email': FREE_EMAIL,
        'internet.example_email': EXAMPLE_EMAIL,
        'vehicle.manufacturer': VEHICLE_MANUFACTURERS,
        'vehicle.model': VEHICLE_MODELS,
        'vehicle.fuel': VEHICLE_FUELS,
        'database.column': DB_COLUMNS,
        'database.type': DB_TYPES,
        'database.engine': DB_ENGINES,
        'database.collation': DB_COLLATIONS,
      },
      ja: JAPANESE,
      // Canada's postcodes are letters and its own province set, so they belong to the
      // Canadian locales rather than to `en`, which carries the US ranges.
      en_CA: { 'location.postcode_by_state': CANADIAN_POSTCODE_BY_STATE },
      fr_CA: { 'location.postcode_by_state': CANADIAN_POSTCODE_BY_STATE },
      en: {
        'color.human': COLOURS,
        'vehicle.type': VEHICLE_TYPES,
        'vehicle.bicycle_type': BICYCLE_TYPES,
        'airline.airplane': AIRPLANES,
        'airline.airline': AIRLINES,
        'company.category': COMPANY_CATEGORIES,
        'person.prefix': NAME_PREFIXES,
        'finance.credit_card': CREDIT_CARDS,
        'location.postcode_by_state': US_POSTCODE_BY_STATE,
        'phone_number.area_code': NANP_AREA_CODES,
        'phone_number.exchange_code': NANP_EXCHANGE_CODES,
        'location.street_suffix': STREET_SUFFIXES,
        'location.building_number': BUILDING_NUMBER,
        'location.secondary_address': SECONDARY_ADDRESS,
        'location.street_address': STREET_ADDRESS,
        'location.street_pattern': STREET_PATTERN,
        'location.direction.cardinal': CARDINAL,
        'location.direction.cardinal_abbr': CARDINAL_ABBR,
        'location.direction.ordinal': ORDINAL,
        'location.direction.ordinal_abbr': ORDINAL_ABBR,
        'person.western_zodiac_sign': ZODIAC,
        'person.sex': SEX,
        'person.bio_part': BIO_PARTS,
        'person.suffix': NAME_SUFFIXES,
        'system.directory_path': DIRECTORY_PATHS,
        'internet.user_agent_pattern': USER_AGENT_PATTERN,
        'finance.federal_reserve_routing_symbol': ROUTING_SYMBOLS,
        'person.gender': GENDER,
        'person.job_descriptor': COMPANY_ADJECTIVES.slice(0, 40),
        'person.job_area': COMPANY_NOUNS.slice(0, 40),
        'person.job_type': JOB_TYPES,
        'finance.account_type': ACCOUNT_TYPES,
        'finance.transaction_type': TRANSACTION_TYPES,
        'word.preposition': PREPOSITIONS,
        'word.conjunction': CONJUNCTIONS,
        'word.interjection': INTERJECTIONS,
        'company.adjective': COMPANY_ADJECTIVES,
        'company.descriptor': COMPANY_DESCRIPTORS,
        'company.noun': COMPANY_NOUNS,
        'company.buzz_verb': BUZZ_VERBS,
        'company.buzz_adjective': BUZZ_ADJECTIVES,
        'company.buzz_noun': BUZZ_NOUNS,
        'company.name_pattern': COMPANY_NAME_PATTERN,
        'commerce.product_name.pattern': PRODUCT_NAME_PATTERN,
        'person.job_title_pattern': JOB_TITLE_PATTERN,
        'person.bio_pattern': BIO_PATTERN,
        'finance.transaction_description_pattern': TRANSACTION_DESCRIPTION_PATTERN,
        'commerce.department': DEPARTMENTS,
        'commerce.product_description': PRODUCT_DESCRIPTIONS,
        'commerce.product_name.product': PRODUCTS,
        'commerce.product_name.adjective': PRODUCT_ADJECTIVES,
        'commerce.product_name.material': PRODUCT_MATERIALS,
      },
    }),
    stats: { lists: 38 },
  }
}
