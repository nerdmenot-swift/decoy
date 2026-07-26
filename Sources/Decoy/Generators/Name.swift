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
    /// The gendered form is the reason Decoy vendors faker-js: its corpus models names
    /// as `{ generic, female, male }` rather than one flat list, so a row marked
    /// `.male` can be given a name that agrees with it.
    ///
    /// With no gender, a locale's `generic` pool is preferred when it has one. Not
    /// every locale does — Afrikaans defines only `female` and `male` — so the
    /// fallback picks a gender first and then a name, which keeps the result coherent
    /// rather than merging two pools the locale never intended to merge.
    public mutating func firstName(_ gender: Gender? = nil) -> String {
        switch gender {
        case .female:
            return faker.require("person.first_name.female")
        case .male:
            return faker.require("person.first_name.male")
        case nil:
            if let generic = faker.draw("person.first_name.generic") { return generic }
            return firstName(faker.bool() ? .female : .male)
        }
    }

    public mutating func lastName() -> String {
        // Some locales split surnames by gender; `generic` is the common case and the
        // only one the built-in corpus provides.
        if let name = faker.draw("person.last_name.generic") { return name }
        return faker.require("person.last_name")
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

    public mutating func domainSuffix() -> String {
        faker.require("internet.domain_suffix")
    }

    public mutating func domainName() -> String {
        "\(faker.name.lastName().asSlug).\(domainSuffix())"
    }

    /// Returns an email address.
    ///
    /// Defaults to `example.com` — RFC 2606 reserves it precisely so test data cannot
    /// reach a real inbox. Seed data escaping into a live mailer is a genuinely
    /// expensive mistake, so the safe choice is the default; pass `domain:` to opt out
    /// deliberately.
    public mutating func email(
        firstName: String? = nil,
        lastName: String? = nil,
        domain: String = "example.com"
    ) -> String {
        let first = (firstName ?? faker.name.firstName()).asSlug
        let last = (lastName ?? faker.name.lastName()).asSlug
        return "\(first).\(last)@\(domain)"
    }

    public mutating func username() -> String {
        "\(faker.name.firstName().asSlug)\(faker.int(in: 1...9_999))"
    }
}

extension String {
    /// Lowercased and reduced to ASCII alphanumerics.
    ///
    /// Deliberately lossy: corpus names carry diacritics and non-Latin scripts, and an
    /// address local part or domain label built from them must still be something a
    /// naive validator accepts. Falls back to `"user"` when nothing survives — a
    /// Japanese or Arabic name reduces to the empty string, and an address beginning
    /// with `.` is malformed.
    fileprivate var asSlug: String {
        var out = String()
        out.reserveCapacity(count)
        for scalar in lowercased().unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9": out.unicodeScalars.append(scalar)
            default: break
            }
        }
        return out.isEmpty ? "user" : out
    }
}
