/**
 * The categories every other faker library ships and this one refused until now.
 *
 * Fills seven new namespaces: `animal`, `food`, `nature`, `media`, `notable`, `brand`
 * and `institution`.
 *
 * ## What changed
 *
 * These were refused on a rule that turned out to be stricter than its own reasoning.
 * The rule is *is there a fact of the matter that could be wrong?* — and for a list of
 * animals the answer is yes, so it wanted a citable source, and no suitable one exists.
 * Wikidata's taxonomy is not a colloquial animal list; Wikipedia's categories are
 * CC BY-SA and unusable here; the open food databases are either share-alike or product
 * catalogues rather than ingredient lists.
 *
 * The reasoning was sound and the conclusion was wrong, because it treated "cannot be
 * mechanically verified" as "cannot be shipped". A fixture library that will not tell you
 * an otter is an animal is not being rigorous, it is being useless. What the discipline
 * actually buys is knowing *which* data is checked, and that is preserved by putting these
 * under their own source (`common-knowledge`) rather than smuggling them in beside the
 * pinned registries. `decoy-inspect --notice` names it; the descriptor says plainly that
 * the accuracy is unverified.
 *
 * ## What is still refused
 *
 * Nothing here is a joke at a named person's expense. `ChuckNorris` is a persona with
 * merchandising behind it rather than a public figure being named, and the quotes are a
 * curated comedic corpus somebody wrote — that is authorship, not fact, and it belongs to
 * whoever wrote it.
 *
 * ## Accuracy
 *
 * Written from general knowledge and not verified against a registry, which is a weaker
 * guarantee than anything else in this pipeline offers. Errors are expected to be rare,
 * cosmetic, and fixable in a diff. Where a fact is contested or a detail uncertain the
 * entry was dropped rather than guessed — a list forty items long that is right is worth
 * more than one sixty long that is half-remembered.
 */

export const id = 'common-knowledge'
export const source = 'common-knowledge'

// ---------------------------------------------------------------------------
// Animals
// ---------------------------------------------------------------------------

const ANIMALS = [
  'Otter', 'Badger', 'Fox', 'Wolf', 'Bear', 'Lynx', 'Hare', 'Hedgehog', 'Squirrel',
  'Deer', 'Elk', 'Bison', 'Moose', 'Beaver', 'Raccoon', 'Skunk', 'Porcupine', 'Marmot',
  'Lion', 'Tiger', 'Leopard', 'Cheetah', 'Jaguar', 'Panther', 'Hyena', 'Jackal',
  'Elephant', 'Rhinoceros', 'Hippopotamus', 'Giraffe', 'Zebra', 'Antelope', 'Gazelle',
  'Wildebeest', 'Warthog', 'Meerkat', 'Aardvark', 'Pangolin', 'Armadillo', 'Sloth',
  'Kangaroo', 'Koala', 'Wombat', 'Platypus', 'Echidna', 'Tasmanian Devil',
  'Chimpanzee', 'Gorilla', 'Orangutan', 'Baboon', 'Lemur', 'Gibbon',
  'Walrus', 'Seal', 'Sea Lion', 'Whale', 'Dolphin', 'Porpoise', 'Manatee',
  'Camel', 'Llama', 'Alpaca', 'Yak', 'Ibex', 'Chamois', 'Mongoose', 'Weasel', 'Stoat',
]

const BIRDS = [
  'Robin', 'Sparrow', 'Blackbird', 'Starling', 'Wren', 'Finch', 'Thrush', 'Nightingale',
  'Swallow', 'Swift', 'Martin', 'Lark', 'Magpie', 'Jackdaw', 'Rook', 'Crow', 'Raven',
  'Jay', 'Woodpecker', 'Kingfisher', 'Cuckoo', 'Owl', 'Kestrel', 'Falcon', 'Hawk',
  'Buzzard', 'Eagle', 'Osprey', 'Harrier', 'Kite', 'Heron', 'Egret', 'Stork', 'Crane',
  'Swan', 'Goose', 'Duck', 'Teal', 'Mallard', 'Grebe', 'Coot', 'Moorhen', 'Curlew',
  'Lapwing', 'Oystercatcher', 'Puffin', 'Gannet', 'Cormorant', 'Albatross', 'Petrel',
  'Pelican', 'Flamingo', 'Ibis', 'Peacock', 'Pheasant', 'Partridge', 'Quail', 'Grouse',
  'Toucan', 'Parrot', 'Macaw', 'Cockatoo', 'Penguin', 'Ostrich', 'Emu', 'Kiwi',
]

const DOG_BREEDS = [
  'Labrador Retriever', 'Golden Retriever', 'German Shepherd', 'Border Collie', 'Beagle',
  'Poodle', 'Bulldog', 'Boxer', 'Dachshund', 'Rottweiler', 'Doberman Pinscher',
  'Great Dane', 'Saint Bernard', 'Bernese Mountain Dog', 'Newfoundland', 'Husky',
  'Alaskan Malamute', 'Samoyed', 'Akita', 'Shiba Inu', 'Chow Chow', 'Shar Pei',
  'Jack Russell Terrier', 'Yorkshire Terrier', 'Scottish Terrier', 'Airedale Terrier',
  'Staffordshire Bull Terrier', 'West Highland White Terrier', 'Cairn Terrier',
  'Cocker Spaniel', 'Springer Spaniel', 'Cavalier King Charles Spaniel', 'Pointer',
  'Weimaraner', 'Vizsla', 'Greyhound', 'Whippet', 'Irish Wolfhound', 'Afghan Hound',
  'Basset Hound', 'Bloodhound', 'Dalmatian', 'Pug', 'Chihuahua', 'Pomeranian',
  'Shih Tzu', 'Maltese', 'Bichon Frise', 'Papillon', 'Corgi',
]

const CAT_BREEDS = [
  'Siamese', 'Persian', 'Maine Coon', 'Ragdoll', 'British Shorthair', 'Bengal',
  'Abyssinian', 'Birman', 'Burmese', 'Russian Blue', 'Sphynx', 'Devon Rex', 'Cornish Rex',
  'Scottish Fold', 'Norwegian Forest Cat', 'Siberian', 'Turkish Angora', 'Turkish Van',
  'Manx', 'Somali', 'Tonkinese', 'Ocicat', 'Savannah', 'Chartreux', 'Korat',
  'Egyptian Mau', 'Singapura', 'Balinese', 'Himalayan', 'American Shorthair',
  'Exotic Shorthair', 'Oriental Shorthair', 'Selkirk Rex', 'Bombay', 'Nebelung',
]

const FISH = [
  'Salmon', 'Trout', 'Cod', 'Haddock', 'Halibut', 'Plaice', 'Sole', 'Turbot', 'Bass',
  'Bream', 'Mackerel', 'Herring', 'Sardine', 'Anchovy', 'Tuna', 'Swordfish', 'Marlin',
  'Snapper', 'Grouper', 'Mullet', 'Pike', 'Perch', 'Carp', 'Tench', 'Roach', 'Barbel',
  'Eel', 'Catfish', 'Sturgeon', 'Shark', 'Ray', 'Skate', 'Angelfish', 'Clownfish',
  'Guppy', 'Koi', 'Goldfish', 'Piranha', 'Barracuda', 'Tilapia',
]

const INSECTS = [
  'Ant', 'Bee', 'Bumblebee', 'Wasp', 'Hornet', 'Beetle', 'Ladybird', 'Weevil',
  'Butterfly', 'Moth', 'Dragonfly', 'Damselfly', 'Mayfly', 'Cricket', 'Grasshopper',
  'Locust', 'Cicada', 'Mantis', 'Stick Insect', 'Cockroach', 'Termite', 'Earwig',
  'Firefly', 'Aphid', 'Midge', 'Mosquito', 'Housefly', 'Hoverfly', 'Horsefly', 'Flea',
]

const FARM_ANIMALS = [
  'Cow', 'Bull', 'Calf', 'Sheep', 'Lamb', 'Ram', 'Goat', 'Kid', 'Pig', 'Piglet', 'Sow',
  'Horse', 'Foal', 'Donkey', 'Mule', 'Chicken', 'Hen', 'Rooster', 'Duck', 'Goose',
  'Turkey', 'Guinea Fowl', 'Rabbit', 'Alpaca',
]

const PET_NAMES = [
  'Bella', 'Luna', 'Charlie', 'Lucy', 'Max', 'Daisy', 'Milo', 'Molly', 'Buddy', 'Bailey',
  'Rosie', 'Teddy', 'Poppy', 'Ollie', 'Ruby', 'Alfie', 'Coco', 'Toby', 'Millie', 'Oscar',
  'Nala', 'Simba', 'Jasper', 'Willow', 'Hugo', 'Bonnie', 'Rocky', 'Pepper', 'Ziggy',
  'Mango', 'Biscuit', 'Marmalade', 'Pickle', 'Waffles', 'Noodle', 'Peanut', 'Mochi',
  'Gizmo', 'Tilly', 'Barnaby',
]

// ---------------------------------------------------------------------------
// Food
// ---------------------------------------------------------------------------

const FRUITS = [
  'Apple', 'Pear', 'Quince', 'Plum', 'Damson', 'Greengage', 'Cherry', 'Peach',
  'Nectarine', 'Apricot', 'Orange', 'Lemon', 'Lime', 'Grapefruit', 'Mandarin',
  'Clementine', 'Kumquat', 'Banana', 'Plantain', 'Mango', 'Papaya', 'Guava', 'Lychee',
  'Rambutan', 'Passion Fruit', 'Pineapple', 'Melon', 'Watermelon', 'Cantaloupe',
  'Strawberry', 'Raspberry', 'Blackberry', 'Blueberry', 'Redcurrant', 'Blackcurrant',
  'Gooseberry', 'Cranberry', 'Elderberry', 'Fig', 'Date', 'Pomegranate', 'Persimmon',
  'Kiwi Fruit', 'Dragon Fruit', 'Starfruit', 'Grape', 'Rhubarb', 'Avocado',
]

const VEGETABLES = [
  'Potato', 'Sweet Potato', 'Carrot', 'Parsnip', 'Turnip', 'Swede', 'Beetroot',
  'Celeriac', 'Radish', 'Onion', 'Shallot', 'Leek', 'Garlic', 'Spring Onion',
  'Cabbage', 'Kale', 'Savoy', 'Brussels Sprout', 'Cauliflower', 'Broccoli', 'Romanesco',
  'Pak Choi', 'Spinach', 'Chard', 'Watercress', 'Rocket', 'Lettuce', 'Endive', 'Chicory',
  'Celery', 'Fennel', 'Asparagus', 'Artichoke', 'Courgette', 'Marrow', 'Cucumber',
  'Pumpkin', 'Butternut Squash', 'Aubergine', 'Pepper', 'Chilli', 'Tomato',
  'Pea', 'Broad Bean', 'Green Bean', 'Runner Bean', 'Sweetcorn', 'Okra',
]

const HERBS_AND_SPICES = [
  'Basil', 'Oregano', 'Thyme', 'Rosemary', 'Sage', 'Marjoram', 'Tarragon', 'Dill',
  'Parsley', 'Coriander', 'Chives', 'Mint', 'Bay Leaf', 'Lemongrass', 'Chervil',
  'Black Pepper', 'White Pepper', 'Cinnamon', 'Cassia', 'Nutmeg', 'Mace', 'Clove',
  'Cardamom', 'Cumin', 'Caraway', 'Fennel Seed', 'Coriander Seed', 'Mustard Seed',
  'Turmeric', 'Ginger', 'Galangal', 'Saffron', 'Paprika', 'Sumac', 'Star Anise',
  'Fenugreek', 'Asafoetida', 'Juniper', 'Allspice', 'Vanilla',
]

const CHEESES = [
  'Cheddar', 'Stilton', 'Wensleydale', 'Red Leicester', 'Double Gloucester', 'Caerphilly',
  'Lancashire', 'Cheshire', 'Brie', 'Camembert', 'Roquefort', 'Comté', 'Gruyère',
  'Emmental', 'Raclette', 'Reblochon', 'Munster', 'Époisses', 'Chèvre', 'Parmesan',
  'Pecorino', 'Gorgonzola', 'Taleggio', 'Mozzarella', 'Burrata', 'Ricotta', 'Provolone',
  'Manchego', 'Idiazábal', 'Cabrales', 'Gouda', 'Edam', 'Leyden', 'Feta', 'Halloumi',
  'Havarti', 'Jarlsberg', 'Gubbeen', 'Mascarpone', 'Quark',
]

const DISHES = [
  'Risotto', 'Paella', 'Ratatouille', 'Cassoulet', 'Bouillabaisse', 'Coq au Vin',
  'Beef Bourguignon', 'Moussaka', 'Lasagne', 'Carbonara', 'Puttanesca', 'Osso Buco',
  'Gnocchi', 'Minestrone', 'Gazpacho', 'Tortilla Española', 'Goulash', 'Schnitzel',
  'Sauerbraten', 'Pierogi', 'Borscht', 'Stroganoff', 'Shakshuka', 'Falafel', 'Hummus',
  'Tabbouleh', 'Kofta', 'Shawarma', 'Tagine', 'Couscous', 'Jollof Rice', 'Injera',
  'Biryani', 'Rogan Josh', 'Dhansak', 'Dosa', 'Pad Thai', 'Tom Yum', 'Laksa', 'Rendang',
  'Pho', 'Banh Mi', 'Ramen', 'Katsu Curry', 'Bibimbap', 'Bulgogi', 'Kimchi Jjigae',
  'Mapo Tofu', 'Dim Sum', 'Ceviche', 'Empanada', 'Feijoada', 'Mole', 'Tamale',
]

const DESSERTS = [
  'Tiramisu', 'Panna Cotta', 'Cannoli', 'Zabaglione', 'Crème Brûlée', 'Tarte Tatin',
  'Profiterole', 'Éclair', 'Madeleine', 'Macaron', 'Clafoutis', 'Mille-feuille',
  'Sachertorte', 'Black Forest Gateau', 'Strudel', 'Stollen', 'Baklava', 'Kunafa',
  'Halva', 'Churros', 'Flan', 'Sticky Toffee Pudding', 'Eton Mess', 'Trifle',
  'Bakewell Tart', 'Treacle Tart', 'Bread and Butter Pudding', 'Spotted Dick',
  'Banoffee Pie', 'Pavlova', 'Cheesecake', 'Brownie', 'Blondie', 'Cobbler', 'Crumble',
  'Sorbet', 'Gelato', 'Affogato', 'Mochi', 'Mango Sticky Rice',
]

// ---------------------------------------------------------------------------
// Nature
// ---------------------------------------------------------------------------

const MOUNTAINS = [
  'Everest', 'K2', 'Kangchenjunga', 'Lhotse', 'Makalu', 'Cho Oyu', 'Dhaulagiri',
  'Manaslu', 'Nanga Parbat', 'Annapurna', 'Denali', 'Aconcagua', 'Kilimanjaro',
  'Mount Elbrus', 'Vinson Massif', 'Puncak Jaya', 'Mont Blanc', 'Matterhorn',
  'Monte Rosa', 'Eiger', 'Jungfrau', 'Grossglockner', 'Zugspitze', 'Mount Olympus',
  'Mount Etna', 'Vesuvius', 'Mount Fuji', 'Mount Kita', 'Mount Cook', 'Mount Kosciuszko',
  'Table Mountain', 'Mount Kenya', 'Atlas', 'Ben Nevis', 'Snowdon', 'Scafell Pike',
  'Carrauntoohil', 'Mount Rainier', 'Mount Whitney', 'Mount Shasta', 'Pikes Peak',
  'Half Dome', 'Mount Hood', 'Popocatépetl', 'Chimborazo', 'Cotopaxi', 'Fitz Roy',
  'Torres del Paine', 'Mount Ararat', 'Mount Sinai',
]

const RIVERS = [
  'Nile', 'Amazon', 'Yangtze', 'Mississippi', 'Missouri', 'Yenisei', 'Ob', 'Yellow River',
  'Congo', 'Amur', 'Lena', 'Mekong', 'Mackenzie', 'Niger', 'Brahmaputra', 'Ganges',
  'Indus', 'Danube', 'Volga', 'Rhine', 'Elbe', 'Loire', 'Rhône', 'Seine', 'Tagus',
  'Ebro', 'Po', 'Tiber', 'Vistula', 'Oder', 'Dnieper', 'Don', 'Thames', 'Severn',
  'Trent', 'Shannon', 'Clyde', 'Tyne', 'Colorado', 'Columbia', 'Rio Grande', 'Hudson',
  'St Lawrence', 'Paraná', 'Orinoco', 'Zambezi', 'Orange', 'Limpopo', 'Murray', 'Darling',
]

const TREES = [
  'Oak', 'Ash', 'Beech', 'Birch', 'Elm', 'Alder', 'Hazel', 'Hornbeam', 'Sycamore',
  'Maple', 'Lime', 'Poplar', 'Aspen', 'Willow', 'Rowan', 'Hawthorn', 'Blackthorn',
  'Holly', 'Yew', 'Juniper', 'Scots Pine', 'Douglas Fir', 'Spruce', 'Larch', 'Cedar',
  'Cypress', 'Redwood', 'Sequoia', 'Chestnut', 'Walnut', 'Hickory', 'Magnolia',
  'Eucalyptus', 'Baobab', 'Acacia', 'Olive', 'Cork Oak', 'Plane', 'Ginkgo', 'Mulberry',
]

const FLOWERS = [
  'Rose', 'Tulip', 'Daffodil', 'Narcissus', 'Hyacinth', 'Crocus', 'Snowdrop', 'Bluebell',
  'Lily', 'Iris', 'Peony', 'Poppy', 'Cornflower', 'Foxglove', 'Delphinium', 'Lupin',
  'Hollyhock', 'Sunflower', 'Dahlia', 'Chrysanthemum', 'Aster', 'Marigold', 'Zinnia',
  'Cosmos', 'Sweet Pea', 'Wisteria', 'Clematis', 'Honeysuckle', 'Jasmine', 'Camellia',
  'Rhododendron', 'Azalea', 'Hydrangea', 'Lavender', 'Geranium', 'Petunia', 'Pansy',
  'Violet', 'Primrose', 'Orchid', 'Freesia', 'Anemone', 'Buttercup', 'Daisy',
]

const GEMSTONES = [
  'Diamond', 'Ruby', 'Sapphire', 'Emerald', 'Topaz', 'Amethyst', 'Aquamarine', 'Garnet',
  'Peridot', 'Opal', 'Tourmaline', 'Tanzanite', 'Zircon', 'Spinel', 'Alexandrite',
  'Moonstone', 'Sunstone', 'Labradorite', 'Lapis Lazuli', 'Turquoise', 'Malachite',
  'Jade', 'Onyx', 'Agate', 'Carnelian', 'Jasper', 'Obsidian', 'Amber', 'Pearl', 'Coral',
  'Citrine', 'Morganite', 'Kunzite', 'Iolite', 'Chrysoprase',
]

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

/**
 * Books, weighted toward the long-out-of-copyright, which is a deliberate bias rather
 * than an accident of taste.
 *
 * A title is not itself copyrightable, so a modern title would be legal to list — but
 * the classics are more useful as fixtures anyway: they are recognisable everywhere,
 * they do not date, and nobody has to wonder whether the library is endorsing them.
 */
const BOOK_TITLES = [
  'Pride and Prejudice', 'Jane Eyre', 'Wuthering Heights', 'Middlemarch', 'Bleak House',
  'Great Expectations', 'David Copperfield', 'Vanity Fair', 'Tess of the d’Urbervilles',
  'Far from the Madding Crowd', 'Moby-Dick', 'The Scarlet Letter',
  'The Adventures of Huckleberry Finn', 'Little Women', 'Walden', 'Leaves of Grass',
  'War and Peace', 'Anna Karenina', 'Crime and Punishment', 'The Brothers Karamazov',
  'Fathers and Sons', 'Dead Souls', 'Madame Bovary', 'Les Misérables',
  'The Count of Monte Cristo', 'Germinal', 'Don Quixote', 'The Divine Comedy',
  'Faust', 'The Metamorphosis', 'The Trial', 'Buddenbrooks', 'Ulysses', 'Dubliners',
  'Heart of Darkness', 'The Picture of Dorian Gray', 'Dracula', 'Frankenstein',
  'Treasure Island', 'The Time Machine', 'The War of the Worlds', 'Robinson Crusoe',
  'Gulliver’s Travels', 'The Odyssey', 'The Iliad', 'The Aeneid', 'Beowulf',
  'The Canterbury Tales', 'Paradise Lost', 'The Tale of Genji',
]

const BOOK_AUTHORS = [
  'Jane Austen', 'Charlotte Brontë', 'Emily Brontë', 'George Eliot', 'Charles Dickens',
  'William Thackeray', 'Thomas Hardy', 'Herman Melville', 'Nathaniel Hawthorne',
  'Mark Twain', 'Louisa May Alcott', 'Henry David Thoreau', 'Walt Whitman',
  'Leo Tolstoy', 'Fyodor Dostoevsky', 'Ivan Turgenev', 'Nikolai Gogol', 'Anton Chekhov',
  'Gustave Flaubert', 'Victor Hugo', 'Alexandre Dumas', 'Émile Zola', 'Marcel Proust',
  'Miguel de Cervantes', 'Dante Alighieri', 'Johann Wolfgang von Goethe', 'Franz Kafka',
  'Thomas Mann', 'James Joyce', 'Joseph Conrad', 'Oscar Wilde', 'Bram Stoker',
  'Mary Shelley', 'Robert Louis Stevenson', 'H. G. Wells', 'Daniel Defoe',
  'Jonathan Swift', 'Homer', 'Virgil', 'Geoffrey Chaucer', 'John Milton',
  'Virginia Woolf', 'Edith Wharton', 'Willa Cather', 'Henry James',
]

const BOOK_GENRES = [
  'Literary Fiction', 'Historical Fiction', 'Science Fiction', 'Fantasy', 'Mystery',
  'Crime', 'Thriller', 'Horror', 'Romance', 'Adventure', 'Satire', 'Gothic',
  'Bildungsroman', 'Epistolary', 'Dystopian', 'Magical Realism', 'Biography', 'Memoir',
  'Travel Writing', 'Essay', 'Poetry', 'Drama', 'Popular Science', 'History',
]

const FILM_GENRES = [
  'Drama', 'Comedy', 'Thriller', 'Horror', 'Science Fiction', 'Fantasy', 'Western',
  'Film Noir', 'Documentary', 'Animation', 'Musical', 'Romance', 'War', 'Crime',
  'Mystery', 'Adventure', 'Biopic', 'Historical Epic', 'Road Movie', 'Heist',
]

const MUSIC_GENRES = [
  'Jazz', 'Blues', 'Bebop', 'Swing', 'Soul', 'Funk', 'Motown', 'Disco', 'Reggae', 'Ska',
  'Dub', 'Rock', 'Blues Rock', 'Psychedelic Rock', 'Progressive Rock', 'Punk',
  'Post-Punk', 'New Wave', 'Grunge', 'Indie Rock', 'Shoegaze', 'Britpop', 'Metal',
  'Thrash Metal', 'Doom Metal', 'Hip Hop', 'Trip Hop', 'Grime', 'House', 'Techno',
  'Trance', 'Drum and Bass', 'Garage', 'Ambient', 'Downtempo', 'Folk', 'Bluegrass',
  'Country', 'Americana', 'Gospel', 'Classical', 'Baroque', 'Romantic', 'Opera',
  'Chamber Music', 'Minimalism', 'Flamenco', 'Fado', 'Bossa Nova', 'Samba', 'Salsa',
  'Afrobeat', 'Highlife', 'Klezmer', 'Qawwali',
]

const INSTRUMENTS = [
  'Piano', 'Violin', 'Viola', 'Cello', 'Double Bass', 'Harp', 'Guitar', 'Banjo',
  'Mandolin', 'Ukulele', 'Lute', 'Sitar', 'Flute', 'Piccolo', 'Oboe', 'Clarinet',
  'Bassoon', 'Saxophone', 'Trumpet', 'Cornet', 'Trombone', 'French Horn', 'Tuba',
  'Accordion', 'Harmonica', 'Bagpipes', 'Organ', 'Harpsichord', 'Drum Kit', 'Timpani',
  'Marimba', 'Xylophone', 'Vibraphone', 'Tabla', 'Djembe', 'Bodhrán', 'Theremin',
]

// ---------------------------------------------------------------------------
// Notable people
// ---------------------------------------------------------------------------

const PHILOSOPHERS = [
  'Socrates', 'Plato', 'Aristotle', 'Heraclitus', 'Parmenides', 'Democritus', 'Epicurus',
  'Zeno of Citium', 'Diogenes', 'Pythagoras', 'Seneca', 'Epictetus', 'Marcus Aurelius',
  'Plotinus', 'Augustine of Hippo', 'Boethius', 'Avicenna', 'Averroes', 'Maimonides',
  'Thomas Aquinas', 'William of Ockham', 'Machiavelli', 'Montaigne', 'Francis Bacon',
  'René Descartes', 'Blaise Pascal', 'Baruch Spinoza', 'Gottfried Leibniz', 'John Locke',
  'George Berkeley', 'David Hume', 'Jean-Jacques Rousseau', 'Immanuel Kant',
  'Georg Wilhelm Friedrich Hegel', 'Arthur Schopenhauer', 'Søren Kierkegaard',
  'Karl Marx', 'John Stuart Mill', 'Friedrich Nietzsche', 'William James',
  'Bertrand Russell', 'Ludwig Wittgenstein', 'Martin Heidegger', 'Jean-Paul Sartre',
  'Simone de Beauvoir', 'Hannah Arendt', 'Simone Weil', 'Michel Foucault',
]

const SCIENTISTS = [
  'Archimedes', 'Euclid', 'Hipparchus', 'Ptolemy', 'Al-Khwarizmi', 'Alhazen',
  'Nicolaus Copernicus', 'Tycho Brahe', 'Johannes Kepler', 'Galileo Galilei',
  'Isaac Newton', 'Robert Hooke', 'Christiaan Huygens', 'Edmond Halley',
  'Carl Linnaeus', 'Antoine Lavoisier', 'Alessandro Volta', 'John Dalton',
  'Michael Faraday', 'James Clerk Maxwell', 'Charles Darwin', 'Alfred Russel Wallace',
  'Gregor Mendel', 'Louis Pasteur', 'Dmitri Mendeleev', 'Lord Kelvin',
  'Ludwig Boltzmann', 'Henri Poincaré', 'Marie Curie', 'Pierre Curie',
  'Ernest Rutherford', 'Max Planck', 'Albert Einstein', 'Niels Bohr',
  'Erwin Schrödinger', 'Werner Heisenberg', 'Paul Dirac', 'Emmy Noether',
  'Lise Meitner', 'Enrico Fermi', 'Richard Feynman', 'Rosalind Franklin',
  'Barbara McClintock', 'Dorothy Hodgkin', 'Alan Turing', 'Ada Lovelace',
  'Charles Babbage', 'Grace Hopper', 'Edwin Hubble', 'Subrahmanyan Chandrasekhar',
]

const COMPOSERS = [
  'Hildegard of Bingen', 'Guillaume de Machaut', 'Josquin des Prez',
  'Giovanni Pierluigi da Palestrina', 'Claudio Monteverdi', 'Henry Purcell',
  'Antonio Vivaldi', 'Johann Sebastian Bach', 'George Frideric Handel',
  'Domenico Scarlatti', 'Joseph Haydn', 'Wolfgang Amadeus Mozart',
  'Ludwig van Beethoven', 'Franz Schubert', 'Hector Berlioz', 'Felix Mendelssohn',
  'Frédéric Chopin', 'Robert Schumann', 'Clara Schumann', 'Franz Liszt',
  'Richard Wagner', 'Giuseppe Verdi', 'Johannes Brahms', 'Anton Bruckner',
  'Pyotr Ilyich Tchaikovsky', 'Antonín Dvořák', 'Edvard Grieg', 'Jean Sibelius',
  'Gustav Mahler', 'Richard Strauss', 'Claude Debussy', 'Maurice Ravel', 'Erik Satie',
  'Igor Stravinsky', 'Béla Bartók', 'Sergei Prokofiev', 'Dmitri Shostakovich',
  'Sergei Rachmaninoff', 'Arnold Schoenberg', 'Alban Berg', 'Ralph Vaughan Williams',
  'Gustav Holst', 'Benjamin Britten', 'Aaron Copland', 'George Gershwin',
]

const ARTISTS = [
  'Giotto', 'Fra Angelico', 'Sandro Botticelli', 'Leonardo da Vinci', 'Michelangelo',
  'Raphael', 'Titian', 'Tintoretto', 'Caravaggio', 'Artemisia Gentileschi',
  'El Greco', 'Diego Velázquez', 'Francisco Goya', 'Peter Paul Rubens',
  'Anthony van Dyck', 'Rembrandt', 'Johannes Vermeer', 'Frans Hals',
  'Jean-Antoine Watteau', 'Jacques-Louis David', 'J. M. W. Turner', 'John Constable',
  'Eugène Delacroix', 'Gustave Courbet', 'Édouard Manet', 'Claude Monet',
  'Pierre-Auguste Renoir', 'Edgar Degas', 'Mary Cassatt', 'Berthe Morisot',
  'Camille Pissarro', 'Paul Cézanne', 'Vincent van Gogh', 'Paul Gauguin',
  'Georges Seurat', 'Henri de Toulouse-Lautrec', 'Gustav Klimt', 'Egon Schiele',
  'Edvard Munch', 'Henri Matisse', 'Pablo Picasso', 'Georges Braque', 'Marc Chagall',
  'Wassily Kandinsky', 'Paul Klee', 'Piet Mondrian', 'Salvador Dalí', 'René Magritte',
  'Frida Kahlo', 'Georgia O’Keeffe', 'Edward Hopper', 'Jackson Pollock',
  'Mark Rothko', 'Katsushika Hokusai', 'Utagawa Hiroshige',
]

const EXPLORERS = [
  'Zheng He', 'Ibn Battuta', 'Marco Polo', 'Christopher Columbus', 'Vasco da Gama',
  'Ferdinand Magellan', 'Hernán Cortés', 'Francisco Pizarro', 'Jacques Cartier',
  'Francis Drake', 'Walter Raleigh', 'Henry Hudson', 'Abel Tasman', 'James Cook',
  'Alexander von Humboldt', 'Meriwether Lewis', 'William Clark', 'David Livingstone',
  'Henry Morton Stanley', 'Richard Burton', 'John Hanning Speke', 'Mary Kingsley',
  'Fridtjof Nansen', 'Roald Amundsen', 'Robert Falcon Scott', 'Ernest Shackleton',
  'Matthew Henson', 'Edmund Hillary', 'Tenzing Norgay', 'Jacques Cousteau',
  'Yuri Gagarin', 'Valentina Tereshkova', 'Neil Armstrong', 'Buzz Aldrin',
]

/**
 * Living public figures, which is the one list here worth pausing over.
 *
 * The project refuses rosters of real people. The line being drawn is between
 * identifying private individuals — which is what an election-candidate database does,
 * and why that one was declined — and naming people whose names are already universally
 * known. Nothing here is private, and nothing here is paired with an address, a
 * date of birth or anything else that would make a fixture look like a record about them.
 *
 * Kept small and uncontroversial for that reason. The historical lists above carry no
 * such question and are where the volume is.
 */
const ACTORS = [
  'Meryl Streep', 'Denzel Washington', 'Cate Blanchett', 'Anthony Hopkins',
  'Viola Davis', 'Daniel Day-Lewis', 'Judi Dench', 'Morgan Freeman', 'Helen Mirren',
  'Tom Hanks', 'Frances McDormand', 'Ian McKellen', 'Michelle Yeoh', 'Idris Elba',
  'Tilda Swinton', 'Mahershala Ali', 'Olivia Colman', 'Gary Oldman', 'Lupita Nyong’o',
  'Riz Ahmed', 'Toni Collette', 'Ke Huy Quan', 'Sally Hawkins', 'Chiwetel Ejiofor',
]

const MUSICIANS = [
  'Aretha Franklin', 'Stevie Wonder', 'Nina Simone', 'Miles Davis', 'John Coltrane',
  'Ella Fitzgerald', 'Billie Holiday', 'Ray Charles', 'Bob Dylan', 'Joni Mitchell',
  'Paul McCartney', 'David Bowie', 'Prince', 'Kate Bush', 'Peter Gabriel',
  'Björk', 'Yo-Yo Ma', 'Jacqueline du Pré', 'Ravi Shankar', 'Fela Kuti',
  'Bob Marley', 'Celia Cruz', 'Cesária Évora', 'Youssou N’Dour',
]

const ATHLETES = [
  'Jesse Owens', 'Muhammad Ali', 'Pelé', 'Diego Maradona', 'Michael Jordan',
  'Serena Williams', 'Roger Federer', 'Rafael Nadal', 'Billie Jean King',
  'Martina Navratilova', 'Usain Bolt', 'Carl Lewis', 'Jackie Joyner-Kersee',
  'Nadia Comăneci', 'Simone Biles', 'Michael Phelps', 'Katie Ledecky',
  'Eddy Merckx', 'Ayrton Senna', 'Jack Nicklaus', 'Babe Ruth', 'Wayne Gretzky',
  'Sachin Tendulkar', 'Don Bradman', 'Jonah Lomu', 'Marta Vieira da Silva',
]

// ---------------------------------------------------------------------------
// Brands and institutions
// ---------------------------------------------------------------------------

const CAMERA_MAKERS = [
  'Canon', 'Nikon', 'Sony', 'Fujifilm', 'Olympus', 'Panasonic', 'Leica', 'Pentax',
  'Hasselblad', 'Phase One', 'Sigma', 'Ricoh', 'Kodak', 'Polaroid', 'GoPro',
]

const PHONE_MAKERS = [
  'Apple', 'Samsung', 'Google', 'Xiaomi', 'Huawei', 'Oppo', 'Vivo', 'OnePlus',
  'Motorola', 'Nokia', 'Sony', 'Asus', 'Realme', 'Honor', 'Nothing',
]

const APPLIANCE_BRANDS = [
  'Bosch', 'Siemens', 'Miele', 'AEG', 'Zanussi', 'Electrolux', 'Whirlpool', 'Indesit',
  'Hotpoint', 'Beko', 'Hoover', 'Dyson', 'Smeg', 'Neff', 'LG', 'Samsung', 'Panasonic',
  'Sharp', 'Haier', 'Candy',
]

const UNIVERSITIES = [
  'University of Oxford', 'University of Cambridge', 'Imperial College London',
  'University College London', 'University of Edinburgh', 'University of Manchester',
  'University of Glasgow', 'Trinity College Dublin', 'Harvard University',
  'Massachusetts Institute of Technology', 'Stanford University', 'Yale University',
  'Princeton University', 'Columbia University', 'University of Chicago',
  'California Institute of Technology', 'University of California, Berkeley',
  'Cornell University', 'Johns Hopkins University', 'University of Michigan',
  'University of Toronto', 'McGill University', 'University of British Columbia',
  'ETH Zurich', 'EPFL', 'Sorbonne University', 'Université PSL', 'Heidelberg University',
  'Technical University of Munich', 'Ludwig Maximilian University of Munich',
  'Delft University of Technology', 'Leiden University', 'Utrecht University',
  'KU Leuven', 'Uppsala University', 'Lund University', 'University of Copenhagen',
  'University of Helsinki', 'University of Vienna', 'Charles University',
  'University of Bologna', 'Sapienza University of Rome', 'Complutense University',
  'University of Barcelona', 'University of Tokyo', 'Kyoto University',
  'Peking University', 'Tsinghua University', 'National University of Singapore',
  'Seoul National University', 'Indian Institute of Science',
  'University of Melbourne', 'Australian National University', 'University of Cape Town',
]

const FOOTBALL_CLUBS = [
  'Arsenal', 'Aston Villa', 'Chelsea', 'Everton', 'Liverpool', 'Manchester City',
  'Manchester United', 'Newcastle United', 'Tottenham Hotspur', 'West Ham United',
  'Celtic', 'Rangers', 'Real Madrid', 'Barcelona', 'Atlético Madrid', 'Sevilla',
  'Valencia', 'Athletic Bilbao', 'Real Sociedad', 'Juventus', 'AC Milan',
  'Internazionale', 'Napoli', 'Roma', 'Lazio', 'Fiorentina', 'Bayern Munich',
  'Borussia Dortmund', 'RB Leipzig', 'Bayer Leverkusen', 'Schalke 04', 'Hamburger SV',
  'Paris Saint-Germain', 'Olympique de Marseille', 'Olympique Lyonnais', 'Monaco',
  'Ajax', 'PSV Eindhoven', 'Feyenoord', 'Benfica', 'Porto', 'Sporting CP',
  'Galatasaray', 'Fenerbahçe', 'Beşiktaş', 'Shakhtar Donetsk', 'Dynamo Kyiv',
  'Red Star Belgrade', 'Olympiacos', 'Panathinaikos', 'Boca Juniors', 'River Plate',
  'Flamengo', 'Palmeiras', 'Santos', 'Corinthians', 'Club América', 'LA Galaxy',
]

const MUSEUMS = [
  'The Louvre', 'Musée d’Orsay', 'Centre Pompidou', 'The British Museum',
  'National Gallery', 'Tate Modern', 'Tate Britain', 'Victoria and Albert Museum',
  'Natural History Museum', 'Science Museum', 'The Metropolitan Museum of Art',
  'Museum of Modern Art', 'Guggenheim Museum', 'Whitney Museum of American Art',
  'Art Institute of Chicago', 'Smithsonian Institution', 'Getty Center',
  'Rijksmuseum', 'Van Gogh Museum', 'Mauritshuis', 'Prado Museum', 'Reina Sofía',
  'Guggenheim Bilbao', 'Uffizi Gallery', 'Galleria Borghese', 'Vatican Museums',
  'Pergamon Museum', 'Alte Nationalgalerie', 'Kunsthistorisches Museum',
  'Hermitage Museum', 'Tretyakov Gallery', 'Acropolis Museum', 'Egyptian Museum',
  'National Palace Museum', 'Tokyo National Museum', 'Museum of Islamic Art',
]

export async function run({ locales }) {
  if (!locales.includes('en')) throw new Error('common-knowledge needs the `en` locale')
  return {
    contributions: {
      en: {
        'animal.animal': ANIMALS,
        'animal.bird': BIRDS,
        'animal.dog_breed': DOG_BREEDS,
        'animal.cat_breed': CAT_BREEDS,
        'animal.fish': FISH,
        'animal.insect': INSECTS,
        'animal.farm_animal': FARM_ANIMALS,
        'animal.pet_name': PET_NAMES,

        'food.fruit': FRUITS,
        'food.vegetable': VEGETABLES,
        'food.herb_or_spice': HERBS_AND_SPICES,
        'food.cheese': CHEESES,
        'food.dish': DISHES,
        'food.dessert': DESSERTS,

        'nature.mountain': MOUNTAINS,
        'nature.river': RIVERS,
        'nature.tree': TREES,
        'nature.flower': FLOWERS,
        'nature.gemstone': GEMSTONES,

        'media.book_title': BOOK_TITLES,
        'media.book_author': BOOK_AUTHORS,
        'media.book_genre': BOOK_GENRES,
        'media.film_genre': FILM_GENRES,
        'media.music_genre': MUSIC_GENRES,
        'media.instrument': INSTRUMENTS,

        'notable.philosopher': PHILOSOPHERS,
        'notable.scientist': SCIENTISTS,
        'notable.composer': COMPOSERS,
        'notable.artist': ARTISTS,
        'notable.explorer': EXPLORERS,
        'notable.actor': ACTORS,
        'notable.musician': MUSICIANS,
        'notable.athlete': ATHLETES,

        'brand.camera': CAMERA_MAKERS,
        'brand.phone': PHONE_MAKERS,
        'brand.appliance': APPLIANCE_BRANDS,

        'institution.university': UNIVERSITIES,
        'institution.football_club': FOOTBALL_CLUBS,
        'institution.museum': MUSEUMS,
      },
    },
    stats: {
      animals: ANIMALS.length + BIRDS.length + DOG_BREEDS.length + CAT_BREEDS.length
        + FISH.length + INSECTS.length + FARM_ANIMALS.length + PET_NAMES.length,
      food: FRUITS.length + VEGETABLES.length + HERBS_AND_SPICES.length + CHEESES.length
        + DISHES.length + DESSERTS.length,
      people: PHILOSOPHERS.length + SCIENTISTS.length + COMPOSERS.length + ARTISTS.length
        + EXPLORERS.length + ACTORS.length + MUSICIANS.length + ATHLETES.length,
    },
  }
}
