/// TEMPORARY. A hand-written stub so the `Forge` API can be exercised end to end
/// before the extracted faker-js corpus exists. Everything here is replaced by the
/// binary corpus reader; only the *shape* of these namespaces is meant to survive.

public enum Gender: Sendable, CaseIterable {
    case female
    case male
}

extension Faker {
    /// The name namespace.
    ///
    /// The getter/setter pair is what lets `$0.name.firstName()` mutate a value
    /// type: Swift reads the namespace, calls the mutating method on it, then writes
    /// it back — carrying the advanced RNG with it. Every namespace follows this
    /// shape, and omitting the setter would silently discard the RNG advance,
    /// making every call return the same value.
    public var name: NameFaker {
        get { NameFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct NameFaker {
    var faker: Faker

    /// Returns a first name, optionally constrained to a gender.
    ///
    /// The gendered overload is the reason Decoy vendors faker-js: its corpus models
    /// names as `{ generic, female, male }` rather than one flat list, so a row
    /// marked `.male` can be given a name that agrees with it. Passing `nil` draws
    /// from the full pool.
    public mutating func firstName(_ gender: Gender? = nil) -> String {
        switch gender {
        case .female: return faker.pick(StubCorpus.femaleFirstNames)
        case .male: return faker.pick(StubCorpus.maleFirstNames)
        case nil:
            return faker.pick(StubCorpus.femaleFirstNames + StubCorpus.maleFirstNames)
        }
    }

    public mutating func lastName() -> String {
        faker.pick(StubCorpus.lastNames)
    }

    public mutating func fullName(_ gender: Gender? = nil) -> String {
        "\(firstName(gender)) \(lastName())"
    }
}

extension Faker {
    public var internet: InternetFaker {
        get { InternetFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct InternetFaker {
    var faker: Faker

    public mutating func domainName() -> String {
        "\(faker.pick(StubCorpus.domainWords)).\(faker.pick(StubCorpus.topLevelDomains))"
    }

    /// Returns an email address.
    ///
    /// Defaults to `example.com` — RFC 2606 reserves it precisely so test data
    /// cannot reach a real inbox. Seed data escaping into a live mailer is a
    /// genuinely expensive mistake, so the safe choice is the default.
    public mutating func email(firstName: String? = nil, lastName: String? = nil) -> String {
        let first = (firstName ?? faker.name.firstName()).asEmailComponent
        let last = (lastName ?? faker.name.lastName()).asEmailComponent
        return "\(first).\(last)@example.com"
    }

    public mutating func username() -> String {
        "\(faker.name.firstName().asEmailComponent)\(faker.int(in: 1...9_999))"
    }
}

extension String {
    /// Lowercased and stripped to characters safe in the local part of an address.
    fileprivate var asEmailComponent: String {
        let filtered = self.lowercased().unicodeScalars.filter {
            ("a"..."z").contains(String($0)) || ("0"..."9").contains(String($0))
        }
        let result = String(String.UnicodeScalarView(filtered))
        return result.isEmpty ? "user" : result
    }
}

enum StubCorpus {
    static let femaleFirstNames = [
        "Ada", "Beatriz", "Chiara", "Daniela", "Elif", "Fatima", "Greta", "Hana",
        "Ingrid", "Júlia", "Keiko", "Lucia", "Maya", "Nadia", "Olga", "Priya",
    ]

    static let maleFirstNames = [
        "Arda", "Bruno", "Caleb", "Dmitri", "Emeka", "Farid", "Gustav", "Hugo",
        "Ivan", "Jamie", "Kenji", "Lars", "Mateo", "Niko", "Omar", "Pavel",
    ]

    static let lastNames = [
        "Almeida", "Bergström", "Chen", "Dubois", "Eriksen", "Fischer", "Gallo",
        "Haddad", "Ibrahim", "Jensen", "Kowalski", "Lindqvist", "Moreau", "Nakamura",
        "Oyelaran", "Petrov", "Quintana", "Rossi", "Silva", "Takahashi",
    ]

    static let domainWords = [
        "acme", "globex", "initech", "umbrella", "soylent", "vehement", "massive",
    ]

    static let topLevelDomains = ["com", "net", "org", "io", "dev"]
}
