import DecoyAdapterKit
import Testing

/// `Endpoint.usable`, which decides what a Wikidata query is allowed to contribute.
///
/// It is a filter, and a filter that drops the wrong things leaves no evidence: the corpus
/// records what arrived, never what was discarded on the way. This one had a minimum length
/// of two written for Latin script, and it deleted almost every Korean and Chinese surname
/// in Wikidata — 138 of 143, and 403 of 445 — because a single character is the normal form
/// of a surname in both. `ko` was reported as a locale with no surname data for months while
/// the data was being fetched and thrown away every build.
@Suite("Wikidata label filter")
struct LabelFilterTests {

    @Test("a single Han or Hangul character is a whole name")
    func ideographicSingles() {
        // The three commonest surnames in Korea and in China. Nothing about them is a
        // fragment, and each is one UTF-16 code unit.
        for name in ["김", "이", "박", "李", "王", "張", "林", "谷"] {
            #expect(Endpoint.usable(name), "\(name) should be usable")
        }
    }

    @Test("a single Latin or Cyrillic character is still noise")
    func latinSinglesStillRejected() {
        for fragment in ["A", "M", "é", "Д", "z"] {
            #expect(!Endpoint.usable(fragment), "\(fragment) should be rejected")
        }
    }

    /// Kana is excluded on purpose. A lone hiragana is a grammatical particle, and Japanese
    /// surnames written in kana run to several characters, so admitting single kana would
    /// let back in the noise the floor exists to stop.
    @Test("a single kana is not a name")
    func kanaSinglesRejected() {
        for particle in ["の", "は", "ア", "ン"] {
            #expect(!Endpoint.usable(particle), "\(particle) should be rejected")
        }
    }

    @Test("multi-character names are unaffected in every script")
    func multiCharacterUnchanged() {
        for name in ["Müller", "홍길동", "歐陽", "田中", "Иванов", "Nguyễn"] {
            #expect(Endpoint.usable(name), "\(name) should be usable")
        }
    }

    /// The rules that were already there, still there. A label with a space, a bracket or a
    /// digit is a disambiguator or a full person's name, not a surname — and that holds
    /// whatever the script, which is why `도간 망절씨` is rejected despite being Hangul.
    @Test("disambiguators and full names are still rejected")
    func noiseStillRejected() {
        for label in ["Müller (Familienname)", "John Smith", "도간 망절씨", "Smith2", "A.B."] {
            #expect(!Endpoint.usable(label), "\(label) should be rejected")
        }
    }

    @Test("the upper bound still holds")
    func tooLong() {
        #expect(!Endpoint.usable(String(repeating: "文", count: 25)))
        #expect(Endpoint.usable(String(repeating: "文", count: 24)))
    }
}
