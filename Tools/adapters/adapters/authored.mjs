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
 * 2. **English only.** These are not translations. A locale without its own data falls
 *    through to English, which is what already happens for wordnet vocabulary and job
 *    titles. Inventing a German list would be inventing German.
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
 * English toponymic elements — the pieces place names are built from.
 *
 * `city()` draws a real GeoNames city now, so these no longer compose one; they remain
 * because `cityPrefix()` and `citySuffix()` are public generators and a feature should
 * not vanish because its data moved. Real elements rather than invented ones: every
 * suffix here is a live English place-name ending with an etymology behind it.
 */
const CITY_PREFIXES = [
  'East', 'Fort', 'Great', 'Lake', 'Little', 'Lower', 'Mount', 'New', 'North', 'Old',
  'Port', 'Saint', 'South', 'Upper', 'West',
]
const CITY_SUFFIXES = [
  'borough', 'bury', 'burgh', 'cester', 'chester', 'dale', 'field', 'ford', 'ham',
  'haven', 'land', 'mouth', 'port', 'shire', 'side', 'stead', 'ton', 'view', 'ville',
  'worth',
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
const PRODUCT_MATERIALS = [
  'Bamboo', 'Bronze', 'Ceramic', 'Concrete', 'Cotton', 'Frozen', 'Granite', 'Leather',
  'Linen', 'Marble', 'Metal', 'Plastic', 'Rubber', 'Silk', 'Soft', 'Steel', 'Wooden',
]

export async function run() {
  return {
    contributions: {
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
      en: {
        'color.human': COLOURS,
        'vehicle.type': VEHICLE_TYPES,
        'vehicle.bicycle_type': BICYCLE_TYPES,
        'airline.airplane': AIRPLANES,
        'airline.airline': AIRLINES,
        'location.city_prefix': CITY_PREFIXES,
        'location.city_suffix': CITY_SUFFIXES,
        'location.direction.cardinal': CARDINAL,
        'location.direction.cardinal_abbr': CARDINAL_ABBR,
        'location.direction.ordinal': ORDINAL,
        'location.direction.ordinal_abbr': ORDINAL_ABBR,
        'person.western_zodiac_sign': ZODIAC,
        'person.sex': SEX,
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
        'commerce.department': DEPARTMENTS,
        'commerce.product_name.product': PRODUCTS,
        'commerce.product_name.adjective': PRODUCT_ADJECTIVES,
        'commerce.product_name.material': PRODUCT_MATERIALS,
      },
    },
    stats: { lists: 38 },
  }
}
