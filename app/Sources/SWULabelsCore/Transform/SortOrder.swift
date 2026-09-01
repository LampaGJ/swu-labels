import Foundation

/// A characteristic cards can be grouped or ordered by.
///
/// The five shipped layouts are fixed compositions of these. Exposing the
/// characteristics themselves lets a sheet be organized any way the binder
/// needs — by cost inside aspect, by rarity inside set — without a new layout
/// mode per combination.
public enum SortKey: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Expansion code, in the active pool's release order.
    case set
    /// Aspect colour, in the pinned sheet order.
    case aspect
    /// Card title, fold-sorted. The alphabetical characteristic.
    case title
    case cost
    case power
    case hp
    case rarity
    case type
    /// Unique cards first or last.
    case unique

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .set: return "Set"
        case .aspect: return "Aspect"
        case .title: return "Alphabetical"
        case .cost: return "Cost"
        case .power: return "Power"
        case .hp: return "HP"
        case .rarity: return "Rarity"
        case .type: return "Card type"
        case .unique: return "Unique"
        }
    }

    /// An SF Symbol naming the characteristic in the editor.
    public var symbolName: String {
        switch self {
        case .set: return "shippingbox"
        case .aspect: return "circle.hexagongrid.fill"
        case .title: return "textformat.abc"
        case .cost: return "creditcard"
        case .power: return "bolt.fill"
        case .hp: return "heart.fill"
        case .rarity: return "sparkles"
        case .type: return "square.stack.3d.up"
        case .unique: return "diamond"
        }
    }

    /// Whether grouping sheets by this characteristic is sensible.
    ///
    /// Grouping starts a fresh sheet per distinct value, so a characteristic
    /// with many values wastes stock: grouping by title would start a new sheet
    /// per card. The editor uses this to warn rather than to forbid, because a
    /// deliberate one-sheet-per-cost run is a legitimate thing to want.
    public var isReasonableToGroupBy: Bool {
        switch self {
        case .set, .aspect, .rarity, .type, .unique: return true
        case .title, .cost, .power, .hp: return false
        }
    }
}

/// One step in a sheet's ordering.
public struct SortCriterion: Codable, Equatable, Sendable, Identifiable {
    public enum Direction: String, Codable, Sendable {
        case ascending
        case descending

        public var displayName: String {
            self == .ascending ? "Ascending" : "Descending"
        }

        public var symbolName: String {
            self == .ascending ? "arrow.up" : "arrow.down"
        }
    }

    public var key: SortKey
    public var direction: Direction

    /// Stable across reordering, so SwiftUI animates a move rather than a
    /// delete-and-insert. Two criteria on the same key stay distinguishable.
    public var id: String { key.rawValue }

    public init(key: SortKey, direction: Direction = .ascending) {
        self.key = key
        self.direction = direction
    }
}

/// How a sheet is divided into sections and ordered within them.
///
/// `groupBy` decides where a fresh sheet starts; `thenBy` orders cards inside a
/// section. Splitting the two is the whole point: "a fresh sheet per aspect,
/// then by set, then alphabetically" and "one continuous run sorted by aspect
/// then set" produce very different stacks of paper from the same card list.
public struct SheetOrder: Codable, Equatable, Sendable {
    public var groupBy: [SortCriterion]
    public var thenBy: [SortCriterion]

    /// Whether to open each run of the first `thenBy` characteristic with a
    /// divider label.
    ///
    /// This is what the shipped by-set layout does: inside a set's section, each
    /// aspect run is prefaced by a label giving the set code, its full name and
    /// an "x/y cards" count, so a binder sorted by set can still be flipped
    /// straight to one colour. Generalized here, the same option prefaces runs
    /// of whatever characteristic is sorted first inside a section.
    public var showsDividers: Bool

    public init(
        groupBy: [SortCriterion] = [],
        thenBy: [SortCriterion] = [],
        showsDividers: Bool = false
    ) {
        self.groupBy = groupBy
        self.thenBy = thenBy
        self.showsDividers = showsDividers
    }

    /// The characteristic whose runs dividers open, when dividers are on.
    public var dividerKey: SortKey? {
        showsDividers ? thenBy.first?.key : nil
    }

    /// Every criterion, grouping first. Grouping keys also order, since a
    /// section boundary only makes sense between sorted values.
    public var allCriteria: [SortCriterion] { groupBy + thenBy }

    /// Characteristics not yet used, offered in the editor's palette.
    public var unusedKeys: [SortKey] {
        let used = Set(allCriteria.map(\.key))
        return SortKey.allCases.filter { !used.contains($0) }
    }

    // MARK: - Presets

    /// `aspect-set`: a fresh sheet per aspect, sets flowing within, then title.
    public static let aspectThenSet = SheetOrder(
        groupBy: [SortCriterion(key: .aspect)],
        thenBy: [SortCriterion(key: .set), SortCriterion(key: .title)]
    )

    /// `aspect`: a fresh sheet per aspect, titles interleaved across sets.
    public static let aspectOnly = SheetOrder(
        groupBy: [SortCriterion(key: .aspect)],
        thenBy: [SortCriterion(key: .title)]
    )

    /// `alphabetical`: one continuous run.
    public static let alphabetical = SheetOrder(
        groupBy: [],
        thenBy: [SortCriterion(key: .title)]
    )

    /// `set`: a fresh sheet per set, aspects within, then title.
    public static let setThenAspect = SheetOrder(
        groupBy: [SortCriterion(key: .set)],
        thenBy: [SortCriterion(key: .aspect), SortCriterion(key: .title)],
        showsDividers: true
    )

    /// The order a shipped layout mode corresponds to.
    public static func preset(for mode: LayoutMode) -> SheetOrder {
        switch mode {
        case .aspectSet, .rotationAspectSet: return .aspectThenSet
        case .aspect: return .aspectOnly
        case .alphabetical: return .alphabetical
        case .set: return .setThenAspect
        }
    }
}
