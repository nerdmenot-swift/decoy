/// Ordering strings the way the pipeline being replaced ordered them.
///
/// JavaScript's `Array.prototype.sort()` with no comparator compares strings by UTF-16
/// code unit. Swift's `<` on String compares by Unicode canonical equivalence, which is a
/// better ordering for almost every purpose and a different one.
///
/// For ASCII the two agree exactly, which is why twenty-one adapters ported without
/// noticing. They diverge the moment a list holds Hebrew with niqqud or Japanese: the
/// wordnet adapter produced the right *words* in a different sequence, and a corpus table
/// is an ordered thing — the compiler stores it as written, so a reordered table is a
/// changed table even though the set is identical.
///
/// This is not a claim that code-unit order is correct. It is a claim that reproducing the
/// existing corpus requires it, and that changing every non-ASCII table's order is a
/// decision to take deliberately rather than as a side effect of a port.
public enum CodeUnitOrder {

    /// Whether `left` sorts before `right` by UTF-16 code unit.
    public static func before(_ left: String, _ right: String) -> Bool {
        var a = left.utf16.makeIterator()
        var b = right.utf16.makeIterator()
        while true {
            switch (a.next(), b.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case (let x?, let y?):
                if x != y { return x < y }
            }
        }
    }

    public static func sorted(_ strings: [String]) -> [String] {
        strings.sorted(by: before)
    }
}
