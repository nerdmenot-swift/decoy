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
        'vehicle.type': spec.vehicleType,
      }
      taken.push(code)
    }
  }

  if (taken.length === 0) throw new Error('authored-commerce matched no locales')
  return { contributions, stats: { locales: taken.length, taken } }
}
