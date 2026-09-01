import Foundation

/// Deterministic, locale-independent sort keys and orderings.
///
/// Nothing here consults the host locale. `localizedStandardCompare`,
/// `compare(_:options:range:locale:)` and `String`'s own `<` are all banned in
/// the sort path: the first two vary with installed ICU data, and the third
/// disagrees with the TypeScript generator (see ``UTF16Order``).
public enum SortKeys {
    /// The fold key both implementations sort on.
    ///
    /// Mirrors `foldSortKey` in `src/transform.ts`: join title and subtitle with
    /// a single space, decompose to NFD, drop every non-spacing combining mark,
    /// then lowercase. `decomposedStringWithCanonicalMapping` is NFD, and
    /// `lowercased()` is the locale-independent Unicode default case conversion
    /// that JavaScript's `toLowerCase` also performs.
    public static func foldSortKey(title: String, subtitle: String?) -> String {
        let joined = "\(title) \(subtitle ?? "")"
        let decomposed = joined.decomposedStringWithCanonicalMapping
        let stripped = String(String.UnicodeScalarView(
            decomposed.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
        ))
        return stripped.lowercased()
    }

    /// Orders cards alphabetically within one section.
    ///
    /// Mirrors `sortWithinGroup`: fold key first, then raw title, then raw
    /// subtitle — every comparison in UTF-16 code-unit order. The sort is stable
    /// so that equal keys preserve input order, matching the TypeScript engine's
    /// guaranteed-stable `Array.prototype.sort`.
    public static func sortWithinGroup(_ cards: [Card]) -> [Card] {
        stableSorted(cards) { lhs, rhs in
            UTF16Order.chain([
                UTF16Order.compare(
                    foldSortKey(title: lhs.title, subtitle: lhs.subtitle),
                    foldSortKey(title: rhs.title, subtitle: rhs.subtitle)
                ),
                UTF16Order.compare(lhs.title, rhs.title),
                UTF16Order.compare(lhs.subtitle ?? "", rhs.subtitle ?? ""),
            ]) == .orderedAscending
        }
    }

    /// Orders set codes by their fold key, for the `alphabetical` set ordering.
    public static func sortedSetCodes(_ codes: [String]) -> [String] {
        stableSorted(codes) { lhs, rhs in
            UTF16Order.compare(
                foldSortKey(title: lhs, subtitle: nil),
                foldSortKey(title: rhs, subtitle: nil)
            ) == .orderedAscending
        }
    }

    /// A guaranteed-stable sort.
    ///
    /// `Array.sort(by:)` in the standard library is an introsort and is *not*
    /// documented as stable. The TypeScript generator relies on JavaScript's
    /// specified-stable sort to break remaining ties by input order, so a stable
    /// sort is required here for parity, not merely preferred.
    static func stableSorted<T>(_ elements: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
        elements.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
