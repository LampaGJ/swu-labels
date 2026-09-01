import Foundation

/// The pure grouping, ordering and dedupe stage of the pipeline.
///
/// Every function here is deterministic and side-effect free: same cards in,
/// byte-identical ordering out, on any machine and in any process. That is the
/// property the whole fidelity gate rests on, so nothing in this file may read
/// the clock, the locale, a random source, or a `Dictionary`'s iteration order.
public enum Transform {}

/// The three lines of a by-set layout's divider label.
public struct DividerLines: Equatable, Codable, Sendable {
    public let setCode: String
    public let fullName: String
    public let breakdown: String

    public init(setCode: String, fullName: String, breakdown: String) {
        self.setCode = setCode
        self.fullName = fullName
        self.breakdown = breakdown
    }

    /// The lines in render order.
    public var ordered: [String] { [setCode, fullName, breakdown] }
}

/// One cell's worth of content in the label grid.
///
/// The by-set layout interleaves real card labels with divider labels that
/// carry no card at all. A closed union lets the renderer switch on the case
/// instead of the caller fabricating a placeholder card to smuggle text through.
public enum LabelSlot: Equatable, Sendable {
    case card(Card)
    case divider(DividerLines)
}

/// One printed section: a section key and the slots that fill its sheets.
///
/// Sections are an ordered array rather than a keyed collection, because the
/// order *is* the output — it decides which sheet comes off the printer first.
public struct LabelSection: Equatable, Sendable {
    public let key: String
    public let slots: [LabelSlot]

    public init(key: String, slots: [LabelSlot]) {
        self.key = key
        self.slots = slots
    }

    /// Card slots only, for accounting checks.
    public var cardCount: Int {
        slots.reduce(0) { count, slot in
            if case .card = slot { return count + 1 }
            return count
        }
    }
}

// MARK: - Dedupe

extension Transform {
    /// The identity two printings of the same card share.
    ///
    /// Deliberately excludes the set code: collapsing a card's original printing
    /// with its later reprint is the entire point.
    static func dedupeKey(_ card: Card) -> String {
        "\(card.title)|\(card.subtitle ?? "")|\(card.typeName.rawValue)"
    }

    /// Keeps the first printing of each card, in the order given.
    ///
    /// Declared effect: **reduces**. Callers must concatenate the pools in set
    /// precedence order first, because "first" is what decides which set's
    /// printing survives onto the sheet.
    public static func dedupe(
        cardsInPrecedenceOrder cards: [Card]
    ) -> (kept: [Card], droppedCount: Int) {
        var seen = Set<String>()
        var kept: [Card] = []
        kept.reserveCapacity(cards.count)
        var droppedCount = 0
        for card in cards {
            let key = dedupeKey(card)
            if seen.contains(key) {
                droppedCount += 1
                continue
            }
            seen.insert(key)
            kept.append(card)
        }
        return (kept, droppedCount)
    }
}

// MARK: - Coverage guard

extension Transform {
    /// Fails unless the snapshot's per-set files cover Premier exactly.
    ///
    /// A silent mismatch here — a new set added upstream with no file, or a
    /// missing main-set file — produces a sheet that looks complete and is not.
    public static func assertPremierSetCoverage(
        premierSets: [String],
        availableSetCodes: [String]
    ) throws {
        let available = Set(availableSetCodes)
        let unexpectedWithoutFile = premierSets
            .filter { !available.contains($0) }
            .filter { !SetCatalog.knownPromoDedupeCodes.contains($0) }
        guard unexpectedWithoutFile.isEmpty else {
            throw LabelError.premierSetsWithoutFileNotPromo(unexpectedWithoutFile)
        }
        let expected = SortKeys.sortedSetCodes(SetCatalog.premierPrecedence)
        let actual = SortKeys.sortedSetCodes(availableSetCodes)
        guard actual == expected else {
            throw LabelError.premierFileSetsMismatch(actual: actual, expected: expected)
        }
    }
}

// MARK: - Set ordering

extension Transform {
    /// Buckets cards by expansion code, preserving first-seen order.
    static func bucketBySet(_ cards: [Card]) -> OrderedBuckets<String, Card> {
        var buckets = OrderedBuckets<String, Card>()
        for card in cards {
            buckets.append(card, to: card.expansionCode)
        }
        return buckets
    }

    /// Resolves the printed order of the set codes present in `buckets`.
    ///
    /// Throws when a set code present in the pool would not be placed, so a set
    /// can never vanish from the sheet by falling through the ordering.
    static func orderedSetCodes(
        in buckets: OrderedBuckets<String, Card>,
        setOrder: LabelLayoutConfig.SetOrder,
        precedence: [String]
    ) throws -> [String] {
        let present = buckets.keys
        let ordered: [String]
        switch setOrder {
        case .release:
            ordered = precedence.filter { buckets.contains($0) }
        case .alphabetical:
            ordered = SortKeys.sortedSetCodes(present)
        }
        guard ordered.count == present.count else {
            let placed = Set(ordered)
            let missing = present.filter { !placed.contains($0) }
            throw LabelError.unaccountedSetCodes(codes: missing, order: setOrder.rawValue)
        }
        return ordered
    }

    /// Orders one aspect's cards by set, then alphabetically within each set.
    ///
    /// Sets flow continuously: the grid is unaware of the set boundary, so no
    /// page break falls where one set ends and the next begins.
    public static func orderWithinAspectBySet(
        _ cards: [Card],
        setOrder: LabelLayoutConfig.SetOrder,
        precedence: [String] = SetCatalog.premierPrecedence
    ) throws -> [Card] {
        let buckets = bucketBySet(cards)
        let codes = try orderedSetCodes(in: buckets, setOrder: setOrder, precedence: precedence)
        return codes.flatMap { code in
            SortKeys.sortWithinGroup(buckets[code] ?? [])
        }
    }
}

// MARK: - Aspect grouping

extension Transform {
    /// Buckets cards into the seven aspect sections, in sheet order.
    ///
    /// Empty sections are dropped, so an aspect with no cards costs no blank sheet.
    public static func groupByAspect(_ cards: [Card]) -> OrderedBuckets<AspectGroup, Card> {
        var buckets = OrderedBuckets<AspectGroup, Card>()
        for card in cards {
            buckets.append(card, to: card.aspectGroup)
        }
        return buckets.reordered(by: AspectGroup.sheetOrder).removingEmptyBuckets()
    }
}

// MARK: - The five layouts

extension Transform {
    /// `aspect-set` and `rotation-aspect-set`: one section per aspect, sets
    /// flowing continuously within, alphabetical inside each set.
    public static func layoutAspectThenSet(
        _ cards: [Card],
        config: LabelLayoutConfig,
        precedence: [String] = SetCatalog.premierPrecedence
    ) throws -> [LabelSection] {
        try groupByAspect(cards).entries.map { entry in
            let ordered = try orderWithinAspectBySet(
                entry.values, setOrder: config.setOrder, precedence: precedence
            )
            return LabelSection(key: entry.key.rawValue, slots: ordered.map(LabelSlot.card))
        }
    }

    /// `aspect`: one section per aspect, every set interleaved alphabetically.
    public static func layoutAspectOnly(_ cards: [Card]) -> [LabelSection] {
        groupByAspect(cards).entries.map { entry in
            LabelSection(
                key: entry.key.rawValue,
                slots: SortKeys.sortWithinGroup(entry.values).map(LabelSlot.card)
            )
        }
    }

    /// `alphabetical`: one continuous section, no breaks at all.
    public static func layoutAlphabetical(_ cards: [Card]) -> [LabelSection] {
        [LabelSection(
            key: LabelLayoutConfig.alphabeticalSectionKey,
            slots: SortKeys.sortWithinGroup(cards).map(LabelSlot.card)
        )]
    }

    /// `set`: one section per set, each aspect within prefaced by a divider label.
    ///
    /// The divider's counts are `aspect cards / set total`, both taken from the
    /// already-deduped pool the caller passes in.
    public static func layoutBySetWithDividers(
        _ cards: [Card],
        config: LabelLayoutConfig,
        precedence: [String] = SetCatalog.premierPrecedence
    ) throws -> [LabelSection] {
        let buckets = bucketBySet(cards)
        let codes = try orderedSetCodes(
            in: buckets, setOrder: config.setOrder, precedence: precedence
        )
        return try codes.map { code in
            let setCards = buckets[code] ?? []
            guard let fullName = SetCatalog.fullNames[code] else {
                throw LabelError.missingSetFullName(code)
            }
            var slots: [LabelSlot] = []
            for entry in groupByAspect(setCards).entries {
                let sorted = SortKeys.sortWithinGroup(entry.values)
                slots.append(.divider(DividerLines(
                    setCode: code,
                    fullName: fullName,
                    breakdown: "(\(entry.key.rawValue)) \(sorted.count)/\(setCards.count) cards"
                )))
                slots.append(contentsOf: sorted.map(LabelSlot.card))
            }
            return LabelSection(key: code, slots: slots)
        }
    }
}
