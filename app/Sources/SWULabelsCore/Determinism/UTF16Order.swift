import Foundation

/// Lexicographic comparison over UTF-16 code units.
///
/// **This exists because Swift's `<` on `String` is not JavaScript's, and the
/// difference silently reorders the printed sheet.**
///
/// Swift compares `String` by Unicode canonical equivalence over grapheme
/// clusters, so `"e\u{301}"` and `"\u{e9}"` compare *equal*. JavaScript compares
/// UTF-16 code units, so the same pair is never equal and the precomposed form
/// sorts after the decomposed one. The TypeScript generator tie-breaks
/// `sortWithinGroup` on raw `title` and then raw `subtitle` using `<`, so any
/// card whose title carries an accent can land in a different row of the sheet
/// depending on which language sorted it.
///
/// Every ordering decision that reaches printed output goes through this type.
/// Using `<` on `String` anywhere in the sort path is a defect, not a shortcut.
public enum UTF16Order {
    /// Compares two strings the way JavaScript's relational operators do.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        var lhsIterator = lhs.utf16.makeIterator()
        var rhsIterator = rhs.utf16.makeIterator()
        while true {
            switch (lhsIterator.next(), rhsIterator.next()) {
            case (nil, nil):
                return .orderedSame
            case (nil, _):
                return .orderedAscending
            case (_, nil):
                return .orderedDescending
            case let (lhsUnit?, rhsUnit?):
                if lhsUnit != rhsUnit {
                    return lhsUnit < rhsUnit ? .orderedAscending : .orderedDescending
                }
            }
        }
    }

    /// True when `lhs` sorts strictly before `rhs` in UTF-16 code-unit order.
    public static func isLessThan(_ lhs: String, _ rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    /// Applies a chain of comparisons, returning the first that is not equal.
    ///
    /// Keeps multi-key sorts readable without nesting, and without the early
    /// `return` ladders that make a missing tie-break easy to overlook.
    public static func chain(_ comparisons: [ComparisonResult]) -> ComparisonResult {
        for comparison in comparisons where comparison != .orderedSame {
            return comparison
        }
        return .orderedSame
    }
}
