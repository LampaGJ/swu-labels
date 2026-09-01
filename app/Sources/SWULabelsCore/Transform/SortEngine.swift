import Foundation

/// Orders and sections cards from an arbitrary ``SheetOrder``.
///
/// This generalizes the five shipped layouts. It does not replace them: the
/// fixed layout functions stay exactly as they are, because they are what the
/// fidelity gate validates against the printed reference sheets. The engine is
/// instead proven to reproduce each of them (see `SortEngineParityTests`), so a
/// custom order is built on machinery already shown to agree with the reference
/// on every one of the ~2,800 cards.
///
/// Every comparison is locale-independent and total. A partial ordering would
/// leave equal-ranked cards in whatever order the sort algorithm happened to
/// produce, which is exactly the kind of run-to-run drift the pipeline forbids.
extension Transform {
    /// Groups and orders `cards` per `order`.
    ///
    /// - Parameter precedence: release order for the ``SortKey/set`` key. The
    ///   caller supplies it because it depends on which pool is loaded, and a
    ///   set absent from the list would otherwise silently sort to one end.
    public static func layout(
        _ cards: [Card],
        order: SheetOrder,
        precedence: [String] = SetCatalog.premierPrecedence
    ) throws -> [LabelSection] {
        let comparator = CardComparator(criteria: order.allCriteria, precedence: precedence)
        let sorted = SortKeys.stableSorted(cards) { comparator.compare($0, $1) == .orderedAscending }

        guard !order.groupBy.isEmpty else {
            return [LabelSection(
                key: LabelLayoutConfig.alphabeticalSectionKey,
                slots: sorted.map(LabelSlot.card)
            )]
        }

        // Sections are cut wherever a grouping key's value changes. The list is
        // already sorted by those keys first, so equal values are adjacent and
        // one pass finds every boundary.
        var sections: [LabelSection] = []
        var currentKey: String?
        var currentCards: [Card] = []

        for card in sorted {
            let key = sectionKey(for: card, groupBy: order.groupBy)
            if key != currentKey {
                if let currentKey, !currentCards.isEmpty {
                    sections.append(section(key: currentKey, cards: currentCards, order: order))
                }
                currentKey = key
                currentCards = []
            }
            currentCards.append(card)
        }
        if let currentKey, !currentCards.isEmpty {
            sections.append(section(key: currentKey, cards: currentCards, order: order))
        }
        return sections
    }

    /// Builds one section's slots, inserting divider labels when asked.
    static func section(key: String, cards: [Card], order: SheetOrder) -> LabelSection {
        guard let dividerKey = order.dividerKey else {
            return LabelSection(key: key, slots: cards.map(LabelSlot.card))
        }

        // Cards are already sorted by the divider characteristic, so each run of
        // equal values is contiguous and a single pass finds every run.
        var slots: [LabelSlot] = []
        var runValue: String?
        var run: [Card] = []

        func flush() {
            guard let runValue, !run.isEmpty else { return }
            slots.append(.divider(DividerLines(
                setCode: key,
                fullName: SetCatalog.fullNames[key] ?? key,
                breakdown: "(\(runValue)) \(run.count)/\(cards.count) cards"
            )))
            slots.append(contentsOf: run.map(LabelSlot.card))
        }

        for card in cards {
            let value = displayValue(of: dividerKey, for: card)
            if value != runValue {
                flush()
                runValue = value
                run = []
            }
            run.append(card)
        }
        flush()
        return LabelSection(key: key, slots: slots)
    }

    /// The section label a card falls under.
    static func sectionKey(for card: Card, groupBy: [SortCriterion]) -> String {
        groupBy.map { displayValue(of: $0.key, for: card) }.joined(separator: " · ")
    }

    /// A characteristic's value, as it reads on a section heading.
    public static func displayValue(of key: SortKey, for card: Card) -> String {
        switch key {
        case .set: return card.expansionCode
        case .aspect: return card.aspectGroup.rawValue
        case .title: return String(card.title.prefix(1)).uppercased()
        case .cost: return card.cost.map(String.init) ?? "None"
        case .power: return card.power.map(String.init) ?? "None"
        case .hp: return card.hp.map(String.init) ?? "None"
        case .rarity: return card.rarity.rawValue
        case .type: return card.typeName.rawValue
        case .unique: return card.unique ? "Unique" : "Not unique"
        }
    }
}

/// Compares two cards against an ordered list of criteria.
struct CardComparator {
    let criteria: [SortCriterion]
    let precedence: [String]

    /// Position of each set code in release order, so a comparison is a lookup
    /// rather than a scan of the precedence array per pair.
    private let setRank: [String: Int]

    init(criteria: [SortCriterion], precedence: [String]) {
        self.criteria = criteria
        self.precedence = precedence
        setRank = Dictionary(
            uniqueKeysWithValues: precedence.enumerated().map { ($0.element, $0.offset) }
        )
    }

    func compare(_ lhs: Card, _ rhs: Card) -> ComparisonResult {
        for criterion in criteria {
            let result = compare(lhs, rhs, by: criterion.key)
            guard result != .orderedSame else { continue }
            return criterion.direction == .ascending ? result : result.reversed
        }
        // A total order needs a final tie-break that no two distinct cards can
        // share, or equal-ranked cards land in an order the sort happened to
        // produce. Title then subtitle then set is unique per printing.
        return UTF16Order.chain([
            UTF16Order.compare(lhs.title, rhs.title),
            UTF16Order.compare(lhs.subtitle ?? "", rhs.subtitle ?? ""),
            UTF16Order.compare(lhs.expansionCode, rhs.expansionCode),
        ])
    }

    func compare(_ lhs: Card, _ rhs: Card, by key: SortKey) -> ComparisonResult {
        switch key {
        case .set:
            return compareRank(setRank[lhs.expansionCode], setRank[rhs.expansionCode]) {
                UTF16Order.compare(lhs.expansionCode, rhs.expansionCode)
            }

        case .aspect:
            let order = AspectGroup.sheetOrder
            return compareRank(
                order.firstIndex(of: lhs.aspectGroup),
                order.firstIndex(of: rhs.aspectGroup)
            ) { .orderedSame }

        case .title:
            return UTF16Order.chain([
                UTF16Order.compare(
                    SortKeys.foldSortKey(title: lhs.title, subtitle: lhs.subtitle),
                    SortKeys.foldSortKey(title: rhs.title, subtitle: rhs.subtitle)
                ),
                UTF16Order.compare(lhs.title, rhs.title),
                UTF16Order.compare(lhs.subtitle ?? "", rhs.subtitle ?? ""),
            ])

        case .cost:
            return compareOptional(lhs.cost, rhs.cost)
        case .power:
            return compareOptional(lhs.power ?? lhs.upgradePower, rhs.power ?? rhs.upgradePower)
        case .hp:
            return compareOptional(lhs.hp ?? lhs.upgradeHp, rhs.hp ?? rhs.upgradeHp)

        case .rarity:
            let order = Rarity.allCases
            return compareRank(
                order.firstIndex(of: lhs.rarity), order.firstIndex(of: rhs.rarity)
            ) { .orderedSame }

        case .type:
            let order = CardType.allCases
            return compareRank(
                order.firstIndex(of: lhs.typeName), order.firstIndex(of: rhs.typeName)
            ) { .orderedSame }

        case .unique:
            if lhs.unique == rhs.unique { return .orderedSame }
            return lhs.unique ? .orderedAscending : .orderedDescending
        }
    }

    /// Compares two ranks, falling back when either is unranked.
    ///
    /// An unranked value sorts last rather than first. A set code missing from
    /// the precedence list is a data problem, and burying it at the end of the
    /// sheet makes it visible instead of silently leading the run.
    func compareRank(
        _ lhs: Int?,
        _ rhs: Int?,
        fallback: () -> ComparisonResult
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (nil, nil): return fallback()
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }

    /// Compares two optional numbers, placing "no value" last.
    ///
    /// A Base has no cost and a Credit Token has no stats at all. Sorting those
    /// to the front of a cost-ordered sheet would put every statless card ahead
    /// of the one-cost cards, which reads as a bug to anyone holding the stack.
    func compareOptional(_ lhs: Int?, _ rhs: Int?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }
}

extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
