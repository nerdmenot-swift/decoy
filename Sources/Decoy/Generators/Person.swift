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

    /// Returns a middle name, optionally constrained to a gender.
    ///
    /// Honours a locale's middle-name pattern where it has one, the same way
    /// ``lastName(_:)`` does — `ku_ckb` carries one and it was unreachable.
    public mutating func middleName(_ gender: Gender? = nil) -> String {
        if gender == nil, let pattern = faker.draw("person.middle_name_pattern.generic") {
            return faker.expand(pattern)
        }
        return gendered("person.middle_name", gender)
    }

    /// Returns a surname no real person is recorded as having.
    ///
    /// **This is the difference, and it is the only one worth choosing on.** Measured
    /// over ten thousand draws: ``lastName(_:)`` returns a real Census surname 9,499
    /// times, because it draws from a list of 24,889 real American surnames. This returns
    /// one zero times. Every candidate is checked against the training set and redrawn on
    /// a hit — see ``NGramModel/wasTrainedOn(_:)`` for why that check is safe to rely on.
    ///
    /// It matters wherever fixtures escape the machine that made them: a support ticket,
    /// a screenshot in a bug report, a staging database somebody exports. "Jennifer
    /// Williams" in a demo is a real person somewhere, and `Bednardt` is not.
    ///
    /// Two things it is *not* better at, despite being the obvious guesses:
    ///
    /// - **Not unique-rule capacity.** That was the original argument and it does not
    ///   survive measurement here: `en`'s surname pattern produces a double-barrelled
    ///   form 5% of the time, so the list's effective pool is 24,889 plus its own square,
    ///   and it fills a 400,000-row unique column without complaint. The capacity
    ///   argument only bites in locales whose patterns do not compound.
    /// - **Not distribution.** The model is trained on each name once regardless of how
    ///   many people bear it, so its output is not Zipf-distributed and real collision
    ///   rates do not occur. ``lastName(_:)`` carries the true Census weights and is the
    ///   right choice for anything measuring shape — deduplication logic, analytics,
    ///   fuzzy matching.
    ///
    /// Falls back to ``lastName(_:)`` in locales with no model, which is every locale but
    /// `en` today. A caller that must know the difference should check
    /// ``LocaleCorpus/resolve(_:)`` for `person.last_name_model`.
    public mutating func novelLastName() -> String {
        faker.drawModel("person.last_name_model") ?? lastName()
    }

    /// Returns a surname, optionally constrained to a gender.
    ///
    /// Locales that define a surname *pattern* get it: `en` weights a double-barrelled
    /// form at 5%, which is the kind of variety a fixture set needs and which nothing
    /// produced, because the pattern was compiled into three locales and read by none.
    /// Locales without one draw the table directly, which is every locale but three.
    public mutating func lastName(_ gender: Gender? = nil) -> String {
        // Ten locales inflect surnames and carry a pattern per gender; three carry only
        // a generic one. Reading `.generic` alone left twenty gendered patterns compiled
        // and unreachable, which `decoy-validate` reports as exactly that.
        //
        // The gendered pattern is preferred when a gender was asked for, and the generic
        // one is used only when none was — its tokens point at
        // `person.last_name.generic`, so honouring it under a gender request would
        // quietly discard the constraint.
        switch gender {
        case .female:
            if let pattern = faker.draw("person.last_name_pattern.female") {
                return faker.expand(pattern)
            }
        case .male:
            if let pattern = faker.draw("person.last_name_pattern.male") {
                return faker.expand(pattern)
            }
        case nil:
            if let pattern = faker.draw("person.last_name_pattern.generic") {
                return faker.expand(pattern)
            }
        }
        return gendered("person.last_name", gender)
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

    /// A job title, composed from the locale's parts or taken whole.
    ///
    /// Two locales — `sl_SI` and `uz_UZ_latin` — carry a flat list of eighteen titles
    /// instead of the descriptor/area/type breakdown, and it was unreachable, so both
    /// composed Slovenian and Uzbek titles out of English parts.
    public mutating func jobTitle() -> String {
        if let pattern = faker.draw("person.job_title_pattern") {
            return faker.expand(pattern)
        }
        if let whole = faker.draw("person.job_title") { return whole }
        return "\(jobDescriptor()) \(jobArea()) \(jobType())"
    }

    public mutating func jobDescriptor() -> String { faker.require("person.job_descriptor") }
    public mutating func jobArea() -> String { faker.require("person.job_area") }
    public mutating func jobType() -> String { faker.require("person.job_type") }
    public mutating func zodiacSign() -> String { faker.require("person.western_zodiac_sign") }

    public mutating func bio() -> String {
        guard let pattern = faker.draw("person.bio_pattern") else {
            // `uz_UZ_latin` spells it `bio_parts`. One locale out of seventy-six using the
            // plural is not worth a rule about naming; it is worth reading both.
            if let part = faker.draw("person.bio_part") { return part }
            return faker.require("person.bio_parts")
        }
        return faker.expand(pattern)
    }

    /// The other spelling a locale may use for a gendered honorific.
    ///
    /// `id_ID` carries `person.female_title` and `person.male_title` rather than
    /// `person.prefix.female` and `person.prefix.male`. Same concept, different name, and
    /// ten honorifics were unreachable because of it — Indonesian records got English
    /// ones instead.
    private static func alternateSpelling(_ path: String, _ gender: String) -> String {
        path == "person.prefix" ? "person.\(gender)_title" : "\(path).\(gender)"
    }

    /// Draws from `<path>.<gender>`, falling back to `<path>.generic` and then to the
    /// bare path, which is the shape locales without a gender split use.
    private mutating func gendered(_ path: String, _ gender: Gender?) -> String {
        // Asked before the children, not after. A locale declaring `person.prefix` empty
        // is saying it has no honorifics at all, but the children are asked first and
        // `az` defines none of them, so the walk used to continue into English and put
        // "Dr." on an Azeri record — the exact failure `explicitlyEmpty` exists to
        // prevent, cited as its reason for being in four separate files. The declaration
        // lives on the parent path, so the parent has to be consulted first.
        if faker.locale.declaresEmpty(path) { return "" }

        switch gender {
        case .female:
            if let value = faker.draw("\(path).female") { return value }
            if let value = faker.draw(Self.alternateSpelling(path, "female")) { return value }
        case .male:
            if let value = faker.draw("\(path).male") { return value }
            if let value = faker.draw(Self.alternateSpelling(path, "male")) { return value }
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
