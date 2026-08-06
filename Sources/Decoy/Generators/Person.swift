public enum Gender: Sendable, CaseIterable {
    case female
    case male
}

extension Faker {
    /// The person namespace.
    ///
    /// The getter/setter pair is what lets `$0.person.firstName()` mutate a value
    /// type: Swift reads the namespace, calls the mutating method on it, then writes
    /// it back — carrying the advanced RNG with it. **Every namespace must have both
    /// accessors**; omitting the setter compiles fine and silently discards the RNG
    /// advance, so every call returns the same value.
    public var person: PersonFaker {
        get { PersonFaker(faker: self) }
        set { self = newValue.faker }
    }
}

public struct PersonFaker {
    var faker: Faker

    /// Returns a first name, optionally constrained to a gender.
    ///
    /// The gendered form is the reason Decoy vendors faker-js: its corpus models names
    /// as `{ generic, female, male }` rather than one flat list, so a row marked
    /// `.male` can be given a name that agrees with it.
    ///
    /// With no gender, a locale's `generic` pool is preferred when it has one. Not
    /// every locale has one — Afrikaans defines only `female` and `male` — so the
    /// fallback picks a gender first and then a name, keeping the result coherent
    /// rather than merging two pools the locale never intended to merge.
    public mutating func firstName(_ gender: Gender? = nil) -> String {
        gendered("person.first_name", gender)
    }

    public mutating func middleName(_ gender: Gender? = nil) -> String {
        gendered("person.middle_name", gender)
    }

    public mutating func lastName(_ gender: Gender? = nil) -> String {
        gendered("person.last_name", gender)
    }

    public mutating func prefix(_ gender: Gender? = nil) -> String {
        gendered("person.prefix", gender)
    }

    public mutating func suffix() -> String {
        faker.require("person.suffix")
    }

    /// An ABO/Rh blood group.
    ///
    /// Uniform across the eight groups. Real frequencies vary widely by population — O+
    /// is about 37% in the US and Rh-negative is rare across East Asia — so weighting
    /// this correctly is per-locale data rather than a constant, and belongs with the
    /// rest of the frequency work rather than baked in here.
    public mutating func bloodType() -> String {
        faker.pick(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"])
    }

    /// A US Social Security Number, `AAA-GG-SSSS`.
    ///
    /// US-specific, and named without a country prefix only because every other faker
    /// does the same. The excluded ranges are real: area `000`, `666` and `900`-`999`
    /// are never issued, nor is a `00` group or a `0000` serial, so a validator that
    /// checks them accepts these.
    ///
    /// National identifiers for other countries are a per-country format problem and
    /// are not built; see `docs/corpus-strategy.md`.
    public mutating func ssn() -> String {
        var area = faker.int(in: 1...899)
        if area == 666 { area = 665 }
        let group = faker.int(in: 1...99)
        let serial = faker.int(in: 1...9999)

        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: Swift.max(0, width - digits.count)) + digits
        }
        return "\(pad(area, 3))-\(pad(group, 2))-\(pad(serial, 4))"
    }

    /// A full name assembled from the locale's own name pattern.
    ///
    /// Order and components are data, not code: `hu` puts the family name first, and
    /// some locales weight patterns so prefixes appear only occasionally. Hard-coding
    /// `"\(first) \(last)"` would be wrong outside Western Europe.
    public mutating func fullName(_ gender: Gender? = nil) -> String {
        if let pattern = faker.draw("person.name") {
            return faker.expand(pattern)
        }
        return "\(firstName(gender)) \(lastName(gender))"
    }

    public mutating func sex() -> String {
        faker.require("person.sex")
    }

    public mutating func gender() -> String {
        faker.require("person.gender")
    }

    public mutating func jobTitle() -> String {
        if let pattern = faker.draw("person.job_title_pattern") {
            return faker.expand(pattern)
        }
        return "\(jobDescriptor()) \(jobArea()) \(jobType())"
    }

    public mutating func jobDescriptor() -> String { faker.require("person.job_descriptor") }
    public mutating func jobArea() -> String { faker.require("person.job_area") }
    public mutating func jobType() -> String { faker.require("person.job_type") }
    public mutating func zodiacSign() -> String { faker.require("person.western_zodiac_sign") }

    public mutating func bio() -> String {
        guard let pattern = faker.draw("person.bio_pattern") else {
            return faker.require("person.bio_part")
        }
        return faker.expand(pattern)
    }

    /// Draws from `<path>.<gender>`, falling back to `<path>.generic` and then to the
    /// bare path, which is the shape locales without a gender split use.
    private mutating func gendered(_ path: String, _ gender: Gender?) -> String {
        switch gender {
        case .female:
            if let value = faker.draw("\(path).female") { return value }
        case .male:
            if let value = faker.draw("\(path).male") { return value }
        case nil:
            if let value = faker.draw("\(path).generic") { return value }
            // No generic pool: choose a gender, then a name from that pool, rather
            // than merging pools the locale kept separate.
            let picked: Gender = faker.bool() ? .female : .male
            if let value = faker.draw("\(path).\(picked == .female ? "female" : "male")") {
                return value
            }
        }
        if let value = faker.draw("\(path).generic") { return value }
        return faker.require(path)
    }
}
