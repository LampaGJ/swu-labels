import Foundation

/// Snapshot in, ``SheetPlan`` out. The one path both the CLI and the app take.
///
/// The interface never reimplements a step of this. A live preview in the app
/// and a sheet printed from the command line resolve through the same call, so
/// what the window shows is what the printer receives.
public struct LabelPipeline: Sendable {
    /// Magnitude guards. A pool far outside its expected size means the snapshot
    /// or the filter is wrong, and stopping costs less than a ruined sheet.
    public enum PoolBounds {
        public static let premier = (minimum: 1200, maximum: 1450)
        public static let rotation = (minimum: 1800, maximum: 2800)
    }

    /// Sets a full-rotation layout cannot be built without.
    public static let requiredRotationSets = ["SOR", "SHD", "TWI"]

    public let store: SnapshotStore
    public let config: LabelLayoutConfig

    public init(store: SnapshotStore, config: LabelLayoutConfig = .default) {
        self.store = store
        self.config = config
    }

    /// Loads the pool a mode reads, with its coverage and magnitude guards applied.
    public func loadPool(for mode: LayoutMode) throws -> CardPool {
        try store.validateExists()
        let pool = try store.loadPool(precedence: mode.precedence)

        if mode.usesRotationPool {
            let missing = Self.requiredRotationSets.filter { !pool.setsLoaded.contains($0) }
            guard missing.isEmpty else {
                throw LabelError.missingRotationSets(missing)
            }
            try Self.assertMagnitude(
                pool.kept.count, bounds: PoolBounds.rotation, pool: "full-rotation"
            )
        } else {
            let formats = try store.loadFormats()
            try Transform.assertPremierSetCoverage(
                premierSets: formats.premierSets, availableSetCodes: pool.setsLoaded
            )
            try Self.assertMagnitude(
                pool.kept.count, bounds: PoolBounds.premier, pool: "premier-legal-today"
            )
        }
        return pool
    }

    static func assertMagnitude(
        _ count: Int,
        bounds: (minimum: Int, maximum: Int),
        pool: String
    ) throws {
        guard count >= bounds.minimum, count <= bounds.maximum else {
            throw LabelError.poolSizeOutOfRange(
                pool: pool, count: count, minimum: bounds.minimum, maximum: bounds.maximum
            )
        }
    }

    /// Groups a card list into the sections a mode prints.
    public func sections(for mode: LayoutMode, cards: [Card]) throws -> [LabelSection] {
        switch mode {
        case .aspectSet:
            return try Transform.layoutAspectThenSet(
                cards, config: config, precedence: mode.precedence
            )
        case .rotationAspectSet:
            return try Transform.layoutAspectThenSet(
                cards, config: config, precedence: mode.precedence
            )
        case .aspect:
            return Transform.layoutAspectOnly(cards)
        case .alphabetical:
            return Transform.layoutAlphabetical(cards)
        case .set:
            return try Transform.layoutBySetWithDividers(
                cards, config: config, precedence: mode.precedence
            )
        }
    }

    /// The whole path: load, filter, group, verify accounting, plan.
    public func plan(mode: LayoutMode, setsFilter: [String]? = nil) throws -> SheetPlan {
        let pool = try loadPool(for: mode)
        let cards = try pool.filtered(toSets: setsFilter)
        let sections = try sections(for: mode, cards: cards)

        // Every card the pool handed over must appear exactly once on the sheet.
        // A grouping that quietly drops one produces a plausible-looking sheet
        // with a card missing, which is only ever found by not finding the card.
        let labelCount = sections.reduce(0) { $0 + $1.cardCount }
        guard labelCount == cards.count else {
            throw LabelError.labelAccountingMismatch(labels: labelCount, cards: cards.count)
        }

        return try SheetPlanner.plan(sections: sections, config: config)
    }

    /// The output basename a run writes, matching the reference generator's.
    public static func outputBasename(
        snapshotTag: String,
        mode: LayoutMode,
        assets: AssetsMode,
        setsFilter: [String]?
    ) -> String {
        let filterSuffix = setsFilter.map { "-" + $0.joined(separator: "-") } ?? ""
        return "premier-labels-avery5167-\(snapshotTag)"
            + mode.filenameSuffix + filterSuffix + assets.filenameSuffix
    }
}
