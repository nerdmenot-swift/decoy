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
    /// A middle name, which is a given name.
    ///
    /// No locale carries a separate middle-name list any more. faker did, for a handful,
    /// and `person.middle_name` went with it — so this drew on a path nothing filled, and
    /// `require` traps rather than returning empty.
    ///
    /// Drawing from the given names is not a workaround for that, it is what a middle name
    /// is: English, German and French middle names come from the same stock as first names,
    /// and a separate list would be the same names typed twice. The consequence is that
    /// `firstName()` and `middleName()` can return the same value in one row, which happens
    /// to real people and is not worth suppressing.
    ///
    /// It also means middle names inherit every registry improvement automatically — they
    /// are weighted by INSEE and the Spanish census like given names, which the old
    /// separate list never was.
    public mutating func middleName(_ gender: Gender? = nil) -> String {
        gendered("person.first_name", gender)
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
        faker.drawModel("person.last_name_model.generic") ?? lastName()
    }

    /// Returns a surname, optionally constrained to a gender.
    ///
    /// Locales that define a surname *pattern* get it: `en` weights a double-barrelled
    /// form at 5%, which is the kind of variety a fixture set needs and which nothing
    /// produced, because the pattern was compiled into three locales and read by none.
    /// Locales without one draw the table directly, which is every locale but three.
    public mutating func lastName(_ gender: Gender? = nil) -> String {
        // A model first, when asked for: the surname pattern below composes *real* names
        // from the list, so honouring it under `novelNames` would hand back real people
        // joined by a hyphen.
        if let generated = modelled("person.last_name", gender) { return generated }

        // Ten locales inflect surnames and carry a pattern per gender; three carry only
        // a generic one. Reading `.generic` alone left twenty gendered patterns compiled
        // and unreachable, which `decoy-validate` reports as exactly that.
        //
        // `person.last_name_pattern` used to be consulted here, per gender, so that a
        // locale could compose a double-barrelled surname. Only faker supplied those
        // patterns — in `en`, `de` and `ja` — and the paths went with it, so all three
        // branches read something nothing fills.
        //
        // What is lost is worth naming rather than dropping quietly: German surnames can
        // no longer come out as `Dittmer-Kick`. Composing them again wants a rule per
        // language about which surnames hyphenate and in what order, which is the same
        // grammar problem as the inflecting street names, not a list.
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
    /// A full name in the locale's own order and spacing.
    ///
    /// The pattern is taken from a corpus that also carries the given names it
    /// interpolates, rather than from whichever corpus mentions `person.name` first.
    /// Resolving those independently let `zh_CN` pair its own Han pattern — correctly
    /// spaceless — with an English given name, and produce `ChengAaliyah`. See
    /// ``LocaleCorpus/stringsAgreeing(_:requires:)``.
    public mutating func fullName(_ gender: Gender? = nil) -> String {
        let coherent = faker.locale.agreeing(
            on: ["person.first_name.female", "person.first_name.male"])
        if coherent.chain.count != faker.locale.chain.count {
            // The whole composition is narrowed, not just the pattern: expanding against
            // the full chain would still pull the surname from the front of it.
            var scoped = faker
            scoped.locale = coherent
            let name = scoped.person.fullName(gender)
            faker.rng = scoped.rng
            return name
        }
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
        // The plural spelling `person.bio_parts` used to be read here too, because
        // `uz_UZ_latin` used it. That was a faker locale's spelling and went with faker,
        // so reading it now is a `require` on a path nothing fills.
        guard let pattern = faker.draw("person.bio_pattern") else {
            return faker.require("person.bio_part")
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
    /// Draws from a model at `<path>_model.<gender>` when the mode is on and one exists.
    ///
    /// Rewriting the path rather than branching in each generator keeps the model and the
    /// list resolving through the same chain, so a locale that defines a model inherits
    /// and overrides it exactly the way it does a list — including
    /// `explicitlyEmpty` blocking fallback, which a parallel lookup path would have got
    /// wrong the first time somebody declared a field empty.
    private mutating func modelled(_ path: String, _ gender: Gender?) -> String? {
        guard faker.novelNames else { return nil }
        let base = "\(path)_model"
        switch gender {
        case .female: return faker.drawModel("\(base).female") ?? faker.drawModel("\(base).generic")
        case .male: return faker.drawModel("\(base).male") ?? faker.drawModel("\(base).generic")
        case nil:
            if let value = faker.drawModel("\(base).generic") { return value }
            let picked: Gender = faker.bool() ? .female : .male
            return faker.drawModel("\(base).\(picked == .female ? "female" : "male")")
        }
    }

    private mutating func gendered(_ path: String, _ gender: Gender?) -> String {
        // Asked before the children, not after. A locale declaring `person.prefix` empty
        // is saying it has no honorifics at all, but the children are asked first and
        // `az` defines none of them, so the walk used to continue into English and put
        // "Dr." on an Azeri record — the exact failure `explicitlyEmpty` exists to
        // prevent, cited as its reason for being in four separate files. The declaration
        // lives on the parent path, so the parent has to be consulted first.
        if faker.locale.declaresEmpty(path) { return "" }

        // A model where the locale has one and the caller asked for it. Falls through to
        // the list otherwise, which is every locale for the fields no model was viable
        // for — see `isViable` in the trainer for why that is a refusal rather than a gap.
        if let generated = modelled(path, gender) { return generated }

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
