import Testing

@testable import DecoyAdapterKit

/// The regex shapes libaddressinput uses for postcodes, and what each becomes.
///
/// A mask that is wrong produces postcodes that look right, which is the failure mode this
/// corpus is least able to notice: nothing throws, the field is populated, and the values
/// are invalid only to somebody who knows the country. So both directions are pinned here —
/// the patterns that must convert, and the patterns that must be refused.
///
/// The refusals matter as much as the conversions. Canada and the United Kingdom draw their
/// letters from restricted sets (`[ABCEGHJKLMNPRSTVXY]`, and the fixed list of UK postcode
/// areas), and a mask has no way to say "one of these letters". Generating `ZZZ ZZZ` would
/// satisfy the shape and be deliverable nowhere. Four locales lose the field to that and it
/// is the right trade — `filters.json` records them so the loss is visible rather than
/// inferred.
@Suite("Postcode masks")
struct PostcodeMaskTests {

    @Test("a plain pattern becomes a mask")
    func plainPatterns() {
        #expect(PostalAdapter.mask(for: #"\d{5}"#) == "#####")
        #expect(PostalAdapter.mask(for: #"\d{4}"#) == "####")
        // The optional separator is kept: a Japanese postcode is written `154-0023` and the
        // regex marks the hyphen optional because it is also valid without. Dropping it
        // gives `#######`, which is correct and unrecognisable.
        #expect(PostalAdapter.mask(for: #"\d{3}-?\d{4}"#) == "###-####")
    }

    /// Four countries were losing their postcode to this until the whole-pattern case was
    /// separated from the trailing one.
    @Test("a pattern that is entirely optional keeps its shape")
    func wholePatternOptional() {
        // Nigeria and Honduras — the postcode is optional in the country, which is not the
        // same as the country having none. Read as a trailing group the whole pattern is
        // stripped, leaving an empty mask and no field at all.
        #expect(PostalAdapter.mask(for: #"(\d{6})?"#) == "######")
        #expect(PostalAdapter.mask(for: #"(?:\d{5})?"#) == "#####")
        // Barbados, where the country prefix is part of the code.
        #expect(PostalAdapter.mask(for: #"(BB\d{5})?"#) == "BB#####")
        #expect(PostalAdapter.mask(for: #"(\d{3}[A-Z]{2}\d{3})?"#) == "###??###")
    }

    @Test("an optional prefix is dropped for the base form")
    func leadingOptional() {
        // Armenia: the Soviet-era six-digit form put `37` ahead of the modern four-digit
        // code. Both are written; the shorter is the one to generate.
        #expect(PostalAdapter.mask(for: #"(37)?\d{4}"#) == "####")
        // Oman, where `PC` is a label rather than part of the code.
        #expect(PostalAdapter.mask(for: #"(PC )?\d{3}"#) == "###")
    }

    @Test("an optional suffix is dropped for the base form")
    func trailingOptional() {
        // The US +4, written about as often as it is not. A mask is one shape, so the
        // extension goes.
        #expect(PostalAdapter.mask(for: #"\d{5}(-\d{4})?"#) == "#####")
    }

    /// Refusals. Each of these *could* be given a mask, and the mask would be wrong.
    @Test("a pattern narrower than any-digit-or-letter is refused")
    func refusals() {
        // Canada. `[ABCEGHJKLMNPRSTVXY]` is 18 of 26 letters, and a mask cannot say which.
        #expect(
            PostalAdapter.mask(
                for: #"[ABCEGHJKLMNPRSTVXY]\d[ABCEGHJ-NPRSTV-Z] ?\d[ABCEGHJ-NPRSTV-Z]\d"#) == nil)
        // The United Kingdom, whose areas are a fixed list of two-letter codes.
        #expect(PostalAdapter.mask(for: #"GIR[ ]?0AA|((AB|AL|B|BA)\d\d?[A-Z]{2})"#) == nil)
        // An alternation is more than one shape, and a mask is one.
        #expect(PostalAdapter.mask(for: #"\d{4}|\d{6}"#) == nil)
    }

    @Test("the group helpers only fire on the shape they name")
    func helpersAreNarrow() {
        // `(37)?\d{4}` has a base form outside the group, so it is not a whole-pattern
        // optional — if it were treated as one, Armenia would generate `37`.
        #expect(PostalAdapter.wholePatternOptionalGroup(in: #"(37)?\d{4}"#) == nil)
        #expect(PostalAdapter.wholePatternOptionalGroup(in: #"(\d{6})?"#) == #"\d{6}"#)
        // An alternation inside the group is still more than one shape.
        #expect(PostalAdapter.wholePatternOptionalGroup(in: #"(\d{4}|\d{6})?"#) == nil)
        // A pattern with no optional prefix must not lose its first characters.
        #expect(PostalAdapter.leadingOptionalGroup(in: #"\d{4}"#) == nil)
        #expect(PostalAdapter.leadingOptionalGroup(in: #"(AB)\d{4}"#) == nil)
    }
}
