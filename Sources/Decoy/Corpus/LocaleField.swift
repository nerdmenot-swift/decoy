/// The kinds of data a locale either supplies itself or inherits.
///
/// Grouped rather than listed per path because there are more than a thousand paths and
/// nobody reads that. Each case names the data whose absence would be *felt*: a caller
/// picking a locale cares whether names look local, not which of eleven name paths exist.
///
/// ## Why this lives in the library
///
/// It was a table inside `decoy-inspect`, used to generate a Markdown matrix. That made the
/// documentation the only place coverage was legible, so a user had to read a file in the
/// repository to find out whether the locale they had chosen could supply a street name —
/// and nothing stopped the table and the corpus disagreeing.
///
/// The same declaration now answers both. `LocaleCorpus.supplies(_:)` reads it at run time
/// and `--matrix` generates its table from it, so the published table cannot describe a
/// corpus that is not shipping.
public enum LocaleField: String, CaseIterable, Sendable {
    case givenNames
    case surnames
    case cities
    case streets
    case postcodes
    case addresses
    case phoneNumbers
    case subdivisions
    case countries
    case colours
    case compass
    case zodiac
    case companyForms
    case products
    case departments
    case jobTitles
    case vocabulary
    case inventedNames
    case realWorldLists

    /// The heading this field appears under in the published matrix.
    public var title: String {
        switch self {
        case .givenNames: return "Given names"
        case .surnames: return "Surnames"
        case .cities: return "Cities"
        case .streets: return "Streets"
        case .postcodes: return "Postcodes"
        case .addresses: return "Addresses"
        case .phoneNumbers: return "Phone numbers"
        case .subdivisions: return "Subdivisions"
        case .countries: return "Countries"
        case .colours: return "Colours"
        case .compass: return "Compass"
        case .zodiac: return "Zodiac"
        case .companyForms: return "Company forms"
        case .products: return "Products"
        case .departments: return "Departments"
        case .jobTitles: return "Job titles"
        case .vocabulary: return "Vocabulary"
        case .inventedNames: return "Invented names"
        case .realWorldLists: return "Real-world lists"
        }
    }

    /// The ways a locale can satisfy this field: a list of alternatives, each a set of
    /// paths that must *all* be present. `[[a], [b, c]]` means "a, or both b and c".
    ///
    /// The distinction is not pedantry. This was once a flat list tested with
    /// `contains(where:)`, so any one path sufficed — which over-reported: Danish, Croatian,
    /// Persian, Georgian and Macedonian were marked as supplying given names while holding
    /// male names only, and every one produced *entirely English* full names. `allSatisfy`
    /// over the same flat list would have been as wrong in the other direction, because for
    /// surnames the two paths are alternatives and most locales carry only `generic`.
    public var requirements: [[String]] {
        switch self {
        // Either an ungendered list, or both sexes. One sex alone cannot compose a name.
        case .givenNames:
            return [
                ["person.first_name.generic"],
                ["person.first_name.female", "person.first_name.male"],
            ]
        case .surnames: return [["person.last_name.generic"], ["person.last_name.male"]]
        case .cities: return [["location.city_name"]]
        case .streets: return [["location.street_pattern"], ["location.street_name"]]
        case .postcodes: return [["location.postcode"]]
        case .addresses: return [["location.postal_address"]]
        case .phoneNumbers: return [["phone_number.format.national"]]
        case .subdivisions: return [["location.state"]]
        case .countries: return [["location.country"]]
        case .colours: return [["color.human"]]
        case .compass: return [["location.direction.cardinal"]]
        case .zodiac: return [["person.western_zodiac_sign"]]
        case .companyForms: return [["company.legal_entity_type"]]
        case .products: return [["commerce.product_name.product"]]
        case .departments: return [["commerce.department"]]
        case .jobTitles: return [["person.job_title"]]
        case .vocabulary: return [["word.noun"]]
        case .inventedNames:
            return [["whimsy.creature"], ["sport.discipline"], ["beverage.beer_style"]]
        case .realWorldLists:
            return [["animal.animal"], ["food.fruit"], ["notable.scientist"]]
        }
    }

    /// Fields English supplies and no other locale is expected to.
    ///
    /// Not a gap. `person.job_title` comes from a US labour-market register with no
    /// counterpart elsewhere, and the invented and real-world lists are written here in
    /// English on purpose — translating them would mean inventing the translation, which is
    /// the line this corpus does not cross.
    ///
    /// Counting them against other locales would make the best possible score unreachable
    /// and every locale look worse than it is, so `achievable` excludes them and `tier`
    /// measures against that.
    public static let englishOnly: Set<LocaleField> = [
        .jobTitles, .inventedNames, .realWorldLists,
    ]

    /// What a locale other than English can actually supply.
    public static var achievable: [LocaleField] {
        allCases.filter { !englishOnly.contains($0) }
    }
}

/// How much of its own data a locale carries.
///
/// A coarse label for a quick decision — "is this locale rich enough for my fixtures" — with
/// `LocaleCorpus.nativeFields` underneath for anyone who needs the specifics.
///
/// The boundaries are a judgement, and drawn where the data actually separates rather than
/// at round numbers. Every shipping locale supplies its own names, cities, addresses, phone
/// numbers, subdivisions and countries; that universal set is `core`. Above it the fields
/// thin out unevenly, so `complete` is defined as leaving at most one out rather than as a
/// percentage.
///
/// ## A low tier is not a poor locale
///
/// This measures what a locale supplies *itself*, so a regional variant that inherits its
/// parent's language scores low by construction and is not the worse for it. `en_GB` is
/// `core` because almost everything it needs already exists in `en` — it adds British
/// postcodes and phone formats and sensibly inherits the rest. Reading that as a deficiency
/// gets it exactly backwards.
///
/// The number to compare is a locale against *its own language*, not against `en`. For a
/// language root the tier says how much of its own data exists; for a variant it says how
/// much it adds to the parent it inherits from.
public enum LocaleTier: String, Sendable, Comparable {
    /// Names and places of its own, which every shipping locale has.
    case core
    /// Most of what a locale can supply, but not all of it.
    case extended
    /// Everything a locale other than English can have, give or take one field.
    case complete

    private var rank: Int {
        switch self {
        case .core: return 0
        case .extended: return 1
        case .complete: return 2
        }
    }

    public static func < (lhs: LocaleTier, rhs: LocaleTier) -> Bool { lhs.rank < rhs.rank }
}
