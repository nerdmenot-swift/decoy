/**
 * Commercial vocabulary for the major European languages, written for this project.
 *
 * Fills, for `de`, `nl`, `fr`, `es`, `it` and `pt`:
 *   commerce.product_name.{product,adjective,material,pattern}
 *   commerce.department
 *   finance.account_type
 *   vehicle.type
 *
 * A deliberate widening of `authored.mjs`'s "English only" rule, made with the project
 * owner's explicit agreement after the cost was set out. Everything below is the kind of
 * vocabulary no registry publishes in any language, so the choice was English everywhere or
 * this.
 *
 * ## Why this is grammar, not a word list
 *
 * The English composition is `{adjective} {material} {product}` — "Rustic Granite Chair" —
 * and translating its three lists word for word produces broken output in every language
 * here. German declines the attributive adjective by the noun's gender: *ergonomischer*
 * Stuhl, *ergonomische* Lampe, *ergonomisches* Sofa. French and the other Romance languages
 * put the adjective after the noun, agree it for gender, and join the material with a
 * preposition. Dutch inflects by de-word versus het-word.
 *
 * So each language gets its own pattern, and two constructions remove the agreement problem
 * rather than hiding it:
 *
 *   - **German and Dutch use the plural.** The plural nominative attributive adjective ends
 *     in `-e` for every gender in both languages, so `Ergonomische Stühle` and
 *     `Ergonomische stoelen` are correct whatever the noun is. Singular would require
 *     knowing each noun's gender and declining to match.
 *   - **The Romance languages use only gender-invariant adjectives.** Mostly the ones ending
 *     in `-e` or `-l` — `rustique`, `elegante`, `artesanal` — though not by that rule alone:
 *     Portuguese `simples` ends in `-s` and is invariant, and Spanish `duradero` ends in `-o`
 *     and is not. Each entry was chosen for the property rather than matched by shape, and a
 *     first draft that filtered on the ending would have quietly dropped `simples` and
 *     quietly kept nothing wrong only by luck. Anything that inflects — `petit/petite`,
 *     `rústico/rústica` — is absent, so the noun's gender never has to be known.
 *
 * The material is joined with each language's own preposition (`aus`, `van`, `en`, `de`,
 * `in`) rather than compounded. German would more often compound — `Granitstuhl` — but that
 * requires the product noun in lower case to sit inside the compound, which would make
 * `commerce.product()` return an uncapitalised German noun when called on its own.
 *
 * ## What is deliberately still English
 *
 * `company.buzz_*` and `person.job_*` stay English in every locale. Corporate buzzwords are
 * deliberate nonsense — "de-engineered", "holisticly" — and have no meaning to translate;
 * job titles in German and Dutch industry are frequently English in real life, so
 * translating them would be less accurate rather than more. `commerce.product_description`
 * stays English for the same reason as the buzzwords: it is marketing register rather than
 * vocabulary.
 *
 * ## Departments, accounts and vehicles are not translations
 *
 * These three are localised rather than translated, which is a different job. A French
 * supermarket has a `Bricolage` aisle that English retail has no word for; `Checking` is a
 * United States banking product that does not exist in Germany, where the equivalent is a
 * `Girokonto`; and a `Saloon` is a `Limousine` in German and a `Berlina` in Italian. Each
 * list is what that market actually calls its own categories.
 */

export const id = 'authored-commerce'
export const source = 'decoy-authored'

/**
 * Per language: the pattern, and the three lists it composes.
 *
 * `plural` marks the two languages whose nouns are listed in the plural, which is recorded
 * because it is the reason their adjectives need no gender.
 */
const LANGUAGES = {
  de: {
    plural: true,
    pattern: '{{commerce.productAdjective}} {{commerce.product}} aus {{commerce.productMaterial}}',
    adjective: [
      'Ergonomische', 'Elegante', 'Handgefertigte', 'Robuste', 'Moderne', 'Klassische',
      'Praktische', 'Nachhaltige', 'Hochwertige', 'Rustikale', 'Leichte', 'Kompakte',
    ],
    material: [
      'Granit', 'Leder', 'Holz', 'Stahl', 'Baumwolle', 'Bronze', 'Keramik', 'Beton',
      'Bambus', 'Glas', 'Kunststoff', 'Seide', 'Wolle', 'Kupfer', 'Marmor',
    ],
    product: [
      'Stühle', 'Tische', 'Lampen', 'Sofas', 'Bänke', 'Regale', 'Uhren', 'Taschen',
      'Hemden', 'Hosen', 'Jacken', 'Teller', 'Messer', 'Töpfe', 'Becher', 'Fahrräder',
      'Bälle', 'Handschuhe', 'Mützen', 'Kissen', 'Decken', 'Spiegel', 'Vasen', 'Körbe',
    ],
    department: [
      'Elektronik', 'Bekleidung', 'Bücher', 'Haushalt', 'Garten', 'Spielwaren',
      'Lebensmittel', 'Sport', 'Schuhe', 'Möbel', 'Baumarkt', 'Drogerie', 'Schmuck',
      'Musik', 'Auto', 'Baby',
    ],
    accountType: [
      'Girokonto', 'Sparkonto', 'Tagesgeldkonto', 'Festgeldkonto', 'Depot',
      'Kreditkartenkonto', 'Baufinanzierung', 'Ratenkredit',
    ],
    vehicleType: [
      'Limousine', 'Kombi', 'Kleinwagen', 'Kompaktwagen', 'Cabrio', 'Coupé', 'SUV',
      'Geländewagen', 'Van', 'Kleintransporter', 'Pick-up', 'Sportwagen',
    ],
    transactionType: ['Einzahlung', 'Rechnung', 'Zahlung', 'Abhebung'],
    bicycleType: [
      'BMX-Rad', 'Lastenrad', 'Cityrad', 'Cruiser', 'Cyclocrossrad', 'E-Bike',
      'Faltrad', 'Gravelbike', 'Trekkingrad', 'Mountainbike', 'Liegerad', 'Rennrad',
      'Tandem', 'Tourenrad', 'Bahnrad',
    ],
    gender: [
      'Agender', 'Bigender', 'Weiblich', 'Genderfluid', 'Genderqueer', 'Männlich',
      'Nicht-binär', 'Transgender',
    ],
    preposition: [
      'an', 'auf', 'aus', 'bei', 'durch', 'für', 'gegen', 'hinter', 'in', 'mit', 'nach',
      'neben', 'ohne', 'seit', 'über', 'um', 'unter', 'von', 'vor', 'während', 'wegen',
      'zu', 'zwischen',
    ],
    conjunction: [
      'aber', 'als', 'bevor', 'damit', 'dass', 'denn', 'doch', 'falls', 'nachdem',
      'obwohl', 'oder', 'sobald', 'sondern', 'sowie', 'und', 'weil', 'wenn', 'während',
    ],
    interjection: [
      'ach', 'aha', 'au', 'bravo', 'hm', 'hoppla', 'huch', 'igitt', 'juhu', 'na',
      'nanu', 'oh', 'oje', 'pst', 'puh', 'tja', 'uff', 'wow',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} und {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'O', 'S', 'W'],
    ordinalAbbr: ['NO', 'NW', 'SO', 'SW'],
    prefixFemale: ['Frau', 'Dr.', 'Prof.'],
    prefixMale: ['Herr', 'Dr.', 'Prof.'],
  },
  nl: {
    plural: true,
    pattern: '{{commerce.productAdjective}} {{commerce.product}} van {{commerce.productMaterial}}',
    adjective: [
      'ergonomische', 'elegante', 'handgemaakte', 'robuuste', 'moderne', 'klassieke',
      'praktische', 'duurzame', 'hoogwaardige', 'rustieke', 'lichte', 'compacte',
    ],
    material: [
      'graniet', 'leer', 'hout', 'staal', 'katoen', 'brons', 'keramiek', 'beton',
      'bamboe', 'glas', 'kunststof', 'zijde', 'wol', 'koper', 'marmer',
    ],
    product: [
      'stoelen', 'tafels', 'lampen', 'banken', 'kasten', 'klokken', 'tassen', 'hemden',
      'broeken', 'jassen', 'borden', 'messen', 'pannen', 'bekers', 'fietsen', 'ballen',
      'handschoenen', 'mutsen', 'kussens', 'dekens', 'spiegels', 'vazen', 'manden',
    ],
    department: [
      'Elektronica', 'Kleding', 'Boeken', 'Huishouden', 'Tuin', 'Speelgoed',
      'Levensmiddelen', 'Sport', 'Schoenen', 'Meubels', 'Doe-het-zelf', 'Drogisterij',
      'Sieraden', 'Muziek', 'Auto', 'Baby',
    ],
    accountType: [
      'Betaalrekening', 'Spaarrekening', 'Depositorekening', 'Beleggingsrekening',
      'Creditcardrekening', 'Hypotheek', 'Persoonlijke lening',
    ],
    vehicleType: [
      'Sedan', 'Stationwagen', 'Hatchback', 'Cabriolet', 'Coupé', 'SUV', 'Terreinwagen',
      'Bestelwagen', 'Pick-up', 'Sportwagen', 'Stadsauto',
    ],
    transactionType: ['Storting', 'Factuur', 'Betaling', 'Opname'],
    bicycleType: [
      'BMX-fiets', 'Bakfiets', 'Stadsfiets', 'Cruiser', 'Cyclocrossfiets',
      'Elektrische fiets', 'Vouwfiets', 'Gravelbike', 'Hybride fiets', 'Mountainbike',
      'Ligfiets', 'Racefiets', 'Tandem', 'Toerfiets', 'Baanfiets',
    ],
    gender: [
      'Agender', 'Bigender', 'Vrouw', 'Genderfluïde', 'Genderqueer', 'Man',
      'Non-binair', 'Transgender',
    ],
    preposition: [
      'aan', 'achter', 'bij', 'door', 'in', 'met', 'na', 'naar', 'naast', 'om', 'onder',
      'op', 'over', 'sinds', 'tegen', 'tijdens', 'tot', 'tussen', 'uit', 'van', 'voor',
      'zonder',
    ],
    conjunction: [
      'als', 'dat', 'dus', 'en', 'hoewel', 'maar', 'nadat', 'of', 'omdat', 'terwijl',
      'toen', 'totdat', 'voordat', 'want', 'zodat', 'zodra',
    ],
    interjection: [
      'aha', 'au', 'bah', 'foei', 'hoera', 'hm', 'jee', 'nou', 'oeps', 'oh', 'pff',
      'sst', 'tja', 'wauw', 'zeg',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} en {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'O', 'Z', 'W'],
    ordinalAbbr: ['NO', 'NW', 'ZO', 'ZW'],
    prefixFemale: ['Mevr.', 'Dr.'],
    prefixMale: ['Dhr.', 'Dr.'],
  },
  fr: {
    pattern: '{{commerce.product}} {{commerce.productAdjective}} en {{commerce.productMaterial}}',
    adjective: [
      'rustique', 'moderne', 'classique', 'robuste', 'pratique', 'durable',
      'authentique', 'écologique', 'magnifique', 'souple', 'solide', 'unique',
    ],
    material: [
      'granit', 'cuir', 'bois', 'acier', 'coton', 'bronze', 'céramique', 'béton',
      'bambou', 'verre', 'plastique', 'soie', 'laine', 'cuivre', 'marbre',
    ],
    product: [
      'Chaise', 'Table', 'Lampe', 'Canapé', 'Banc', 'Étagère', 'Horloge', 'Sac',
      'Chemise', 'Pantalon', 'Veste', 'Assiette', 'Couteau', 'Casserole', 'Tasse',
      'Vélo', 'Ballon', 'Gant', 'Bonnet', 'Coussin', 'Couverture', 'Miroir', 'Vase',
      'Panier',
    ],
    department: [
      'Électronique', 'Vêtements', 'Livres', 'Maison', 'Jardin', 'Jouets',
      'Alimentation', 'Sport', 'Chaussures', 'Meubles', 'Bricolage', 'Beauté',
      'Bijoux', 'Musique', 'Auto', 'Bébé',
    ],
    accountType: [
      'Compte courant', 'Livret A', "Compte d'épargne", 'Compte à terme',
      'Compte-titres', 'Crédit immobilier', 'Prêt personnel',
    ],
    vehicleType: [
      'Berline', 'Break', 'Citadine', 'Compacte', 'Cabriolet', 'Coupé', 'SUV',
      'Monospace', 'Utilitaire', 'Pick-up', 'Voiture de sport',
    ],
    transactionType: ['Dépôt', 'Facture', 'Paiement', 'Retrait'],
    bicycleType: [
      'BMX', 'Vélo cargo', 'Vélo de ville', 'Cruiser', 'Vélo de cyclo-cross',
      'Vélo électrique', 'Vélo pliant', 'Gravel', 'Vélo hybride', 'VTT', 'Vélo couché',
      'Vélo de route', 'Tandem', 'Vélo de randonnée', 'Vélo de piste',
    ],
    gender: [
      'Agenre', 'Bigenre', 'Femme', 'Genre fluide', 'Genderqueer', 'Homme',
      'Non-binaire', 'Transgenre',
    ],
    preposition: [
      'à', 'après', 'avant', 'avec', 'chez', 'contre', 'dans', 'depuis', 'derrière',
      'devant', 'entre', 'malgré', 'par', 'parmi', 'pendant', 'pour', 'sans', 'sous',
      'sur', 'vers',
    ],
    conjunction: [
      'ainsi', 'alors', 'car', 'cependant', 'donc', 'et', 'lorsque', 'mais', 'ni',
      'or', 'ou', 'pourtant', 'puisque', 'quand', 'quoique', 'si',
    ],
    interjection: [
      'aïe', 'ah', 'bah', 'bravo', 'chut', 'eh', 'hélas', 'hourra', 'hum', 'oh',
      'ouf', 'oups', 'pff', 'tiens', 'waouh', 'zut',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} et {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'E', 'S', 'O'],
    ordinalAbbr: ['NE', 'NO', 'SE', 'SO'],
    prefixFemale: ['Mme', 'Mlle', 'Dr'],
    prefixMale: ['M.', 'Dr'],
  },
  es: {
    pattern: '{{commerce.product}} {{commerce.productAdjective}} de {{commerce.productMaterial}}',
    adjective: [
      'elegante', 'resistente', 'artesanal', 'natural', 'versátil', 'flexible',
      'funcional', 'sostenible', 'suave', 'grande', 'portátil', 'confortable',
    ],
    material: [
      'granito', 'cuero', 'madera', 'acero', 'algodón', 'bronce', 'cerámica', 'hormigón',
      'bambú', 'vidrio', 'plástico', 'seda', 'lana', 'cobre', 'mármol',
    ],
    product: [
      'Silla', 'Mesa', 'Lámpara', 'Sofá', 'Banco', 'Estantería', 'Reloj', 'Bolso',
      'Camisa', 'Pantalón', 'Chaqueta', 'Plato', 'Cuchillo', 'Olla', 'Taza',
      'Bicicleta', 'Balón', 'Guante', 'Gorro', 'Cojín', 'Manta', 'Espejo', 'Jarrón',
      'Cesta',
    ],
    department: [
      'Electrónica', 'Ropa', 'Libros', 'Hogar', 'Jardín', 'Juguetes', 'Alimentación',
      'Deportes', 'Calzado', 'Muebles', 'Bricolaje', 'Belleza', 'Joyería', 'Música',
      'Automoción', 'Bebé',
    ],
    accountType: [
      'Cuenta corriente', 'Cuenta de ahorro', 'Depósito a plazo', 'Cuenta de valores',
      'Tarjeta de crédito', 'Préstamo hipotecario', 'Préstamo personal',
    ],
    vehicleType: [
      'Berlina', 'Familiar', 'Utilitario', 'Compacto', 'Descapotable', 'Cupé', 'SUV',
      'Todoterreno', 'Monovolumen', 'Furgoneta', 'Pick-up', 'Deportivo',
    ],
    transactionType: ['Depósito', 'Factura', 'Pago', 'Retirada'],
    bicycleType: [
      'BMX', 'Bicicleta de carga', 'Bicicleta urbana', 'Cruiser',
      'Bicicleta de ciclocrós', 'Bicicleta eléctrica', 'Bicicleta plegable',
      'Bicicleta gravel', 'Bicicleta híbrida', 'Bicicleta de montaña',
      'Bicicleta reclinada', 'Bicicleta de carretera', 'Tándem',
      'Bicicleta de turismo', 'Bicicleta de pista',
    ],
    gender: [
      'Agénero', 'Bigénero', 'Mujer', 'Género fluido', 'Genderqueer', 'Hombre',
      'No binario', 'Transgénero',
    ],
    preposition: [
      'a', 'ante', 'bajo', 'con', 'contra', 'de', 'desde', 'durante', 'en', 'entre',
      'hacia', 'hasta', 'mediante', 'para', 'por', 'según', 'sin', 'sobre', 'tras',
    ],
    conjunction: [
      'aunque', 'como', 'cuando', 'mientras', 'ni', 'o', 'pero', 'porque', 'pues',
      'que', 'si', 'sino', 'y',
    ],
    interjection: [
      'ah', 'anda', 'ay', 'bah', 'bravo', 'caramba', 'eh', 'hala', 'hombre', 'hurra',
      'oh', 'ojalá', 'ostras', 'uf', 'uy', 'vaya',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} y {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'E', 'S', 'O'],
    ordinalAbbr: ['NE', 'NO', 'SE', 'SO'],
    prefixFemale: ['Sra.', 'Srta.', 'Dra.'],
    prefixMale: ['Sr.', 'Dr.'],
  },
  it: {
    pattern: '{{commerce.product}} {{commerce.productAdjective}} in {{commerce.productMaterial}}',
    adjective: [
      'elegante', 'resistente', 'versatile', 'naturale', 'artigianale', 'funzionale',
      'sostenibile', 'semplice', 'grande', 'pieghevole', 'confortevole', 'affidabile',
    ],
    material: [
      'granito', 'pelle', 'legno', 'acciaio', 'cotone', 'bronzo', 'ceramica',
      'cemento', 'bambù', 'vetro', 'plastica', 'seta', 'lana', 'rame', 'marmo',
    ],
    product: [
      'Sedia', 'Tavolo', 'Lampada', 'Divano', 'Panca', 'Scaffale', 'Orologio', 'Borsa',
      'Camicia', 'Pantalone', 'Giacca', 'Piatto', 'Coltello', 'Pentola', 'Tazza',
      'Bicicletta', 'Pallone', 'Guanto', 'Cappello', 'Cuscino', 'Coperta', 'Specchio',
      'Vaso', 'Cesto',
    ],
    department: [
      'Elettronica', 'Abbigliamento', 'Libri', 'Casa', 'Giardino', 'Giocattoli',
      'Alimentari', 'Sport', 'Calzature', 'Mobili', 'Fai da te', 'Bellezza',
      'Gioielli', 'Musica', 'Auto', 'Bambini',
    ],
    accountType: [
      'Conto corrente', 'Conto di risparmio', 'Conto deposito', 'Conto titoli',
      'Carta di credito', 'Mutuo', 'Prestito personale',
    ],
    vehicleType: [
      'Berlina', 'Station wagon', 'Utilitaria', 'Compatta', 'Cabriolet', 'Coupé',
      'SUV', 'Fuoristrada', 'Monovolume', 'Furgone', 'Pick-up', 'Sportiva',
    ],
    transactionType: ['Deposito', 'Fattura', 'Pagamento', 'Prelievo'],
    bicycleType: [
      'BMX', 'Bici da carico', 'Bici da città', 'Cruiser', 'Bici da ciclocross',
      'Bici elettrica', 'Bici pieghevole', 'Gravel', 'Bici ibrida', 'Mountain bike',
      'Bici reclinata', 'Bici da corsa', 'Tandem', 'Bici da turismo', 'Bici da pista',
    ],
    gender: [
      'Agender', 'Bigender', 'Donna', 'Genere fluido', 'Genderqueer', 'Uomo',
      'Non binario', 'Transgender',
    ],
    preposition: [
      'a', 'con', 'contro', 'da', 'di', 'dopo', 'durante', 'fra', 'in', 'oltre', 'per',
      'presso', 'secondo', 'senza', 'sopra', 'sotto', 'su', 'tra', 'verso',
    ],
    conjunction: [
      'anche', 'anzi', 'benché', 'come', 'dunque', 'e', 'invece', 'ma', 'mentre', 'né',
      'o', 'oppure', 'perché', 'però', 'poiché', 'quando', 'se', 'sebbene',
    ],
    interjection: [
      'ah', 'ahi', 'beh', 'bravo', 'ehi', 'evviva', 'macché', 'mah', 'oh', 'ohi',
      'ops', 'puah', 'uffa', 'urrà', 'uh', 'wow',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} e {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'E', 'S', 'O'],
    ordinalAbbr: ['NE', 'NO', 'SE', 'SO'],
    prefixFemale: ['Sig.ra', 'Sig.na'],
    prefixMale: ['Sig.'],
  },
  pt: {
    pattern: '{{commerce.product}} {{commerce.productAdjective}} de {{commerce.productMaterial}}',
    adjective: [
      'elegante', 'resistente', 'artesanal', 'natural', 'versátil', 'sustentável',
      'funcional', 'durável', 'simples', 'grande', 'portátil', 'flexível',
    ],
    material: [
      'granito', 'couro', 'madeira', 'aço', 'algodão', 'bronze', 'cerâmica', 'betão',
      'bambu', 'vidro', 'plástico', 'seda', 'lã', 'cobre', 'mármore',
    ],
    product: [
      'Cadeira', 'Mesa', 'Candeeiro', 'Sofá', 'Banco', 'Estante', 'Relógio', 'Bolsa',
      'Camisa', 'Calça', 'Casaco', 'Prato', 'Faca', 'Panela', 'Caneca', 'Bicicleta',
      'Bola', 'Luva', 'Gorro', 'Almofada', 'Manta', 'Espelho', 'Vaso', 'Cesto',
    ],
    department: [
      'Eletrónica', 'Vestuário', 'Livros', 'Casa', 'Jardim', 'Brinquedos',
      'Alimentação', 'Desporto', 'Calçado', 'Móveis', 'Bricolage', 'Beleza',
      'Joalharia', 'Música', 'Automóvel', 'Bebé',
    ],
    accountType: [
      'Conta à ordem', 'Conta poupança', 'Depósito a prazo', 'Conta de títulos',
      'Cartão de crédito', 'Crédito habitação', 'Crédito pessoal',
    ],
    vehicleType: [
      'Sedan', 'Carrinha', 'Utilitário', 'Compacto', 'Descapotável', 'Cupé', 'SUV',
      'Todo-o-terreno', 'Monovolume', 'Furgão', 'Pick-up', 'Desportivo',
    ],
    transactionType: ['Depósito', 'Fatura', 'Pagamento', 'Levantamento'],
    bicycleType: [
      'BMX', 'Bicicleta de carga', 'Bicicleta urbana', 'Cruiser',
      'Bicicleta de ciclocrosse', 'Bicicleta elétrica', 'Bicicleta dobrável', 'Gravel',
      'Bicicleta híbrida', 'Bicicleta de montanha', 'Bicicleta reclinada',
      'Bicicleta de estrada', 'Tandem', 'Bicicleta de cicloturismo',
      'Bicicleta de pista',
    ],
    gender: [
      'Agénero', 'Bigénero', 'Mulher', 'Género fluido', 'Genderqueer', 'Homem',
      'Não binário', 'Transgénero',
    ],
    preposition: [
      'a', 'ante', 'após', 'até', 'com', 'contra', 'de', 'desde', 'durante', 'em',
      'entre', 'para', 'perante', 'por', 'sem', 'sob', 'sobre',
    ],
    conjunction: [
      'contudo', 'e', 'embora', 'enquanto', 'logo', 'mas', 'nem', 'ou', 'porém',
      'porque', 'pois', 'quando', 'que', 'se', 'todavia',
    ],
    interjection: [
      'ah', 'ai', 'arre', 'bah', 'bravo', 'caramba', 'eh', 'oh', 'olá', 'opa', 'ora',
      'ufa', 'uh', 'upa', 'viva',
    ],
    companyNamePattern: [
      { value: '{{person.lastName}} {{company.legal_entity_type}}', weight: 5 },
      { value: '{{person.lastName}}-{{person.lastName}}', weight: 3 },
      {
        value:
          '{{person.lastName}}, {{person.lastName}} e {{person.lastName}}',
        weight: 2,
      },
    ],
    cardinalAbbr: ['N', 'E', 'S', 'O'],
    ordinalAbbr: ['NE', 'NO', 'SE', 'SO'],
    prefixFemale: ['Sra.', 'Dna.'],
    prefixMale: ['Sr.'],
  },
}

/**
 * Which locales take which language's vocabulary.
 *
 * Regional variants are included where the vocabulary genuinely carries: Austrian and Swiss
 * German shop in the same words, and `fr_BE` and `fr_CH` likewise. `pt_BR` is deliberately
 * absent — Brazilian Portuguese differs here in ways this list does not capture, from
 * `Comboio`/`Trem` to `Telemóvel`/`Celular`, and the European vocabulary would be wrong
 * rather than merely unlocalised.
 */
const LOCALES = {
  de: ['de', 'de_AT', 'de_CH'],
  nl: ['nl', 'nl_BE'],
  fr: ['fr', 'fr_BE', 'fr_CH', 'fr_LU'],
  es: ['es'],
  it: ['it'],
  pt: ['pt_PT'],
}

export async function run({ locales }) {
  const contributions = {}
  const taken = []

  for (const [language, spec] of Object.entries(LANGUAGES)) {
    for (const code of LOCALES[language]) {
      if (!locales.includes(code)) continue
      contributions[code] = {
        'commerce.product_name.pattern': [spec.pattern],
        'commerce.product_name.adjective': spec.adjective,
        'commerce.product_name.material': spec.material,
        'commerce.product_name.product': spec.product,
        'commerce.department': spec.department,
        'finance.account_type': spec.accountType,
        'finance.transaction_type': spec.transactionType,
        'vehicle.type': spec.vehicleType,
        'vehicle.bicycle_type': spec.bicycleType,
        'person.gender': spec.gender,
        'word.preposition': spec.preposition,
        'word.conjunction': spec.conjunction,
        'word.interjection': spec.interjection,
        // The English company pattern joins three surnames with the English word `and`,
        // and every locale inherited it once faker's own patterns went — a German firm
        // came out as `Biber, Gumbel and Happe`. A conjunction is the smallest possible
        // piece of grammar and the most visible when it is the wrong language.
        'company.name_pattern': spec.companyNamePattern,
        // English `N, E, S, W` is not merely unlocalised here, it is wrong: German and
        // Dutch abbreviate Ost/Oost to `O`, and the Romance languages abbreviate
        // Oeste/Ouest/Ovest to `O` where English has `W`. Every one of these locales was
        // inheriting an abbreviation that names the wrong direction.
        'location.direction.cardinal_abbr': spec.cardinalAbbr,
        'location.direction.ordinal_abbr': spec.ordinalAbbr,
        ...(spec.prefixFemale
          ? {
              // Honorifics came from faker for every one of these, so deleting it left
              // German addressing people as `Mrs.` and French as `Dr.` — English titles on
              // names that are otherwise entirely local. Italian had shipped an empty node
              // and Portuguese none at all even before that.
              'person.prefix.female': spec.prefixFemale,
              'person.prefix.male': spec.prefixMale,
            }
          : {}),
      }
      taken.push(code)
    }
  }

  if (taken.length === 0) throw new Error('authored-commerce matched no locales')
  return { contributions, stats: { locales: taken.length, taken } }
}
