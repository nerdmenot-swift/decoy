// Generators over `common-knowledge`: real things, recorded from general knowledge
// rather than fetched from a registry.
//
// These are the categories the project refused for months, on a rule that turned out to
// be stricter than its own reasoning — see `Tools/adapters/adapters/common-knowledge.mjs`
// for that argument. What matters at the call site is the guarantee: these values are
// *facts*, so unlike `whimsy` they can be wrong, and unlike `location` they were not
// checked against anything. Accuracy is high and unverified.
//
// English only. A locale without its own data falls through to English, which is what
// already happens for vocabulary and job titles. Inventing a German animal list would be
// translating, not sourcing.

extension Faker {
    public var animal: AnimalFaker {
        get { AnimalFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var food: FoodFaker {
        get { FoodFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var nature: NatureFaker {
        get { NatureFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var media: MediaFaker {
        get { MediaFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var notable: NotableFaker {
        get { NotableFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var brand: BrandFaker {
        get { BrandFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var institution: InstitutionFaker {
        get { InstitutionFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct AnimalFaker {
    var faker: Faker

    /// A mammal, mostly — the colloquial sense of "an animal" rather than the taxonomic
    /// one, which is why birds, fish and insects have their own draws.
    public mutating func animal() -> String { faker.require("animal.animal") }
    public mutating func bird() -> String { faker.require("animal.bird") }
    public mutating func fish() -> String { faker.require("animal.fish") }
    public mutating func insect() -> String { faker.require("animal.insect") }
    public mutating func farmAnimal() -> String { faker.require("animal.farm_animal") }
    public mutating func dogBreed() -> String { faker.require("animal.dog_breed") }
    public mutating func catBreed() -> String { faker.require("animal.cat_breed") }
    public mutating func horseBreed() -> String { faker.require("animal.horse_breed") }

    /// A reptile or an amphibian, drawn together because the colloquial category is
    /// "cold-blooded thing that is not a fish" rather than either clade on its own.
    public mutating func reptileOrAmphibian() -> String {
        faker.require("animal.reptile_or_amphibian")
    }

    /// A pet's name, which is the one draw here that is not a fact about the world —
    /// it is what people call their animals, and drawn from the same stock of ordinary
    /// given names and food words that real pet names come from.
    public mutating func petName() -> String { faker.require("animal.pet_name") }
}

public struct FoodFaker {
    var faker: Faker

    public mutating func fruit() -> String { faker.require("food.fruit") }
    public mutating func vegetable() -> String { faker.require("food.vegetable") }
    public mutating func herbOrSpice() -> String { faker.require("food.herb_or_spice") }
    public mutating func cheese() -> String { faker.require("food.cheese") }

    /// A named dish, as a menu or a recipe index lists one.
    ///
    /// Distinct from ``WhimsyFaker/dishName()``, which invents a menu line that never
    /// existed. This one is real cooking; that one is composition.
    public mutating func dish() -> String { faker.require("food.dish") }
    public mutating func dessert() -> String { faker.require("food.dessert") }
    public mutating func grainOrPulse() -> String { faker.require("food.grain_or_pulse") }
    public mutating func nutOrSeed() -> String { faker.require("food.nut_or_seed") }
    public mutating func seafood() -> String { faker.require("food.seafood") }
    public mutating func bread() -> String { faker.require("food.bread") }

    /// An ingredient of any kind, for the column that does not care which.
    public mutating func ingredient() -> String {
        switch faker.int(in: 0...6) {
        case 0: return fruit()
        case 1: return vegetable()
        case 2: return herbOrSpice()
        case 3: return cheese()
        case 4: return grainOrPulse()
        case 5: return nutOrSeed()
        default: return seafood()
        }
    }
}

public struct NatureFaker {
    var faker: Faker

    public mutating func mountain() -> String { faker.require("nature.mountain") }
    public mutating func river() -> String { faker.require("nature.river") }
    public mutating func tree() -> String { faker.require("nature.tree") }
    public mutating func flower() -> String { faker.require("nature.flower") }
    public mutating func gemstone() -> String { faker.require("nature.gemstone") }
    public mutating func lake() -> String { faker.require("nature.lake") }
    public mutating func island() -> String { faker.require("nature.island") }
    public mutating func desert() -> String { faker.require("nature.desert") }

    /// A weather condition, in the register a forecast uses.
    public mutating func weather() -> String { faker.require("nature.weather") }
}

public struct MediaFaker {
    var faker: Faker

    /// A book title, biased toward the long-out-of-copyright.
    ///
    /// Titles are not copyrightable, so a modern one would be legal to list — the
    /// classics are simply better fixtures: recognisable everywhere, and they do not date.
    public mutating func bookTitle() -> String { faker.require("media.book_title") }
    public mutating func bookAuthor() -> String { faker.require("media.book_author") }
    public mutating func bookGenre() -> String { faker.require("media.book_genre") }
    public mutating func filmGenre() -> String { faker.require("media.film_genre") }
    public mutating func musicGenre() -> String { faker.require("media.music_genre") }
    public mutating func instrument() -> String { faker.require("media.instrument") }
    public mutating func filmTitle() -> String { faker.require("media.film_title") }
    public mutating func songTitle() -> String { faker.require("media.song_title") }
    public mutating func artMovement() -> String { faker.require("media.art_movement") }

    /// A book as a coherent `(title, author, genre)` row.
    ///
    /// Drawn independently, and deliberately so — unlike ``LocationFaker/place()``, where
    /// pairing a city with the wrong state produces a record that fails validation, an
    /// author paired with a title they did not write is obviously fake data and harms
    /// nothing. Correlating them would need a real bibliography, which is the sourcing
    /// problem this whole namespace sidesteps.
    public mutating func book() -> (title: String, author: String, genre: String) {
        (bookTitle(), bookAuthor(), bookGenre())
    }
}

public struct NotableFaker {
    var faker: Faker

    public mutating func philosopher() -> String { faker.require("notable.philosopher") }
    public mutating func scientist() -> String { faker.require("notable.scientist") }
    public mutating func composer() -> String { faker.require("notable.composer") }
    public mutating func artist() -> String { faker.require("notable.artist") }
    public mutating func explorer() -> String { faker.require("notable.explorer") }
    public mutating func mathematician() -> String { faker.require("notable.mathematician") }
    public mutating func inventor() -> String { faker.require("notable.inventor") }
    public mutating func architect() -> String { faker.require("notable.architect") }

    /// A living public figure.
    ///
    /// The one draw in this namespace naming people who are alive, and kept deliberately
    /// small and uncontroversial. Decoy refuses rosters of real people — an
    /// election-candidate database was declined on that ground — and the distinction is
    /// between identifying private individuals and naming people already universally
    /// known. Nothing here is paired with an address or a date of birth, so no output
    /// resembles a record *about* the person named.
    public mutating func actor() -> String { faker.require("notable.actor") }
    public mutating func musician() -> String { faker.require("notable.musician") }
    public mutating func athlete() -> String { faker.require("notable.athlete") }

    /// Any historical figure, for the column that does not care which field.
    public mutating func historicalFigure() -> String {
        switch faker.int(in: 0...7) {
        case 0: return philosopher()
        case 1: return scientist()
        case 2: return mathematician()
        case 3: return inventor()
        case 4: return composer()
        case 5: return artist()
        case 6: return architect()
        default: return explorer()
        }
    }
}

public struct BrandFaker {
    var faker: Faker

    /// Trademarks, named to refer to the things they name.
    ///
    /// That is nominative use, which is not what trademark law restricts — the
    /// restriction is on marks used so as to suggest endorsement or cause confusion in
    /// trade. Decoy claims no affiliation with any of them.
    public mutating func camera() -> String { faker.require("brand.camera") }
    public mutating func phone() -> String { faker.require("brand.phone") }
    public mutating func appliance() -> String { faker.require("brand.appliance") }
    public mutating func watch() -> String { faker.require("brand.watch") }
    public mutating func fashion() -> String { faker.require("brand.fashion") }
    public mutating func sportswear() -> String { faker.require("brand.sportswear") }
    public mutating func motorcycle() -> String { faker.require("brand.motorcycle") }

    /// A car manufacturer, which lives in `vehicle` because it was there first.
    public mutating func car() -> String { faker.require("vehicle.manufacturer") }
}

public struct InstitutionFaker {
    var faker: Faker

    public mutating func university() -> String { faker.require("institution.university") }
    public mutating func footballClub() -> String {
        faker.require("institution.football_club")
    }
    public mutating func museum() -> String { faker.require("institution.museum") }
    public mutating func newspaper() -> String { faker.require("institution.newspaper") }
    public mutating func orchestra() -> String { faker.require("institution.orchestra") }
}
