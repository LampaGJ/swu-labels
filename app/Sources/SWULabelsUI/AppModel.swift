import Foundation
import Observation
import SWULabelsCore
import SWULabelsRender

/// The interface's single source of truth.
///
/// Holds no layout logic of its own. Every decision about what a label contains
/// or where it sits comes from ``LabelPipeline`` and ``SheetRenderer``, the same
/// path the command line takes, so the window cannot show one thing and the
/// printer produce another.
///
/// `@MainActor` because it drives the interface; the expensive work — parsing a
/// snapshot, planning a sheet, rendering a PDF — is handed to a background task
/// and only its result returns here.
@Observable
@MainActor
public final class AppModel {
    /// Where the pipeline is in its load-plan-render cycle.
    public enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)

        public var isLoading: Bool { self == .loading }

        public var errorMessage: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }

    // MARK: - Content location

    public let contentRoot: URL
    public private(set) var availableSnapshots: [String] = []

    // MARK: - Selection

    public var snapshotTag: String {
        didSet { if snapshotTag != oldValue { reload() } }
    }

    /// Which card pool is loaded.
    ///
    /// Mapped onto a representative ``LayoutMode`` rather than given its own
    /// loader, so both pools keep the coverage and magnitude guards the shipped
    /// pipeline already applies — a pool that silently loaded without them
    /// could ship an incomplete sheet.
    public enum PoolKind: String, CaseIterable, Identifiable, Sendable {
        case premierToday
        case fullRotation

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .premierToday: return "Premier-legal today"
            case .fullRotation: return "Full rotation history"
            }
        }

        public var summary: String {
            switch self {
            case .premierToday: return "The six sets currently legal in Premier."
            case .fullRotation: return "Every set that has ever been Premier-legal, rotated-out ones included."
            }
        }

        var representativeMode: LayoutMode {
            self == .premierToday ? .aspectSet : .rotationAspectSet
        }

        public var precedence: [String] {
            representativeMode.precedence
        }
    }

    public var poolKind: PoolKind = .fullRotation {
        didSet {
            guard poolKind != oldValue else { return }
            // A pool the current snapshot cannot satisfy would throw on load and
            // show an error where a working sheet is expected. Moving to a
            // snapshot that carries the pool's sets is the useful behaviour;
            // `reload()` follows from the snapshot change, or is called here
            // when the snapshot already suited both pools.
            if let better = bestSnapshot(for: poolKind), better != snapshotTag {
                snapshotTag = better
            } else {
                reload()
            }
        }
    }

    /// How sheets are divided and ordered.
    public var sheetOrder: SheetOrder = .aspectThenSet {  // matches the aspect-set preset
        didSet { if sheetOrder != oldValue { replan() } }
    }

    public var assetsMode: AssetsMode = .color {
        didSet { if assetsMode != oldValue { reloadIcons() } }
    }

    /// Set codes to restrict to. Empty means every set in the mode's pool.
    public var selectedSets: Set<String> = [] {
        didSet { if selectedSets != oldValue { replan() } }
    }

    public var searchText: String = ""

    /// The live-edited layout configuration.
    public var config: LabelLayoutConfig = .default {
        didSet { if config != oldValue { replan() } }
    }

    // MARK: - Derived state

    public private(set) var phase: Phase = .idle
    public private(set) var pool: CardPool?
    /// The grouped, ordered sections behind the current plan.
    ///
    /// Kept alongside the plan because the browser lists cards in printed order.
    /// Recovering that order from the plan would mean matching resolved label
    /// text back to cards, which is both slower and wrong for two cards sharing
    /// a title.
    public private(set) var sections: [LabelSection] = []
    public private(set) var plan: SheetPlan?
    public private(set) var icons: IconStore?

    /// The card currently shown in the label editor's preview.
    public var previewCard: Card?

    public init(contentRoot: URL) {
        self.contentRoot = contentRoot
        snapshotTag = ""
        availableSnapshots = Self.discoverSnapshots(in: contentRoot)
        // Prefer the newest snapshot that can actually satisfy the starting
        // pool. Taking the newest tag unconditionally is what hid SOR, SHD and
        // TWI: the most recent snapshot carries only the six currently-legal
        // sets, so the app opened on a pool three sets short with nothing to
        // say why.
        snapshotTag = Self.bestSnapshot(
            for: poolKind, among: availableSnapshots, contentRoot: contentRoot
        ) ?? availableSnapshots.sorted().last ?? ""
        reloadIcons()
        reload()
    }

    /// The newest snapshot carrying every set `pool` needs.
    ///
    /// Tags are `vYYYY-MM-DD`, so sorting them lexicographically sorts them
    /// chronologically — no date parsing, and no `Date`, which the determinism
    /// rules keep out of this codebase entirely.
    static func bestSnapshot(
        for pool: PoolKind,
        among tags: [String],
        contentRoot: URL
    ) -> String? {
        let required: [String] = pool == .fullRotation
            ? LabelPipeline.requiredRotationSets
            : SetCatalog.premierPrecedence
        return tags.sorted().reversed().first { tag in
            let store = SnapshotStore(
                root: contentRoot
                    .appendingPathComponent("data/snapshots", isDirectory: true)
                    .appendingPathComponent(tag, isDirectory: true)
            )
            let available = Set((try? store.availableSetCodes()) ?? [])
            return required.allSatisfy(available.contains)
        }
    }

    func bestSnapshot(for pool: PoolKind) -> String? {
        Self.bestSnapshot(for: pool, among: availableSnapshots, contentRoot: contentRoot)
    }

    /// Snapshots that cannot satisfy the current pool, for the sidebar to mark.
    public func snapshotSupportsCurrentPool(_ tag: String) -> Bool {
        bestSnapshotCandidates.contains(tag)
    }

    var bestSnapshotCandidates: Set<String> {
        let required: [String] = poolKind == .fullRotation
            ? LabelPipeline.requiredRotationSets
            : SetCatalog.premierPrecedence
        return Set(availableSnapshots.filter { tag in
            let store = SnapshotStore(
                root: contentRoot
                    .appendingPathComponent("data/snapshots", isDirectory: true)
                    .appendingPathComponent(tag, isDirectory: true)
            )
            let available = Set((try? store.availableSetCodes()) ?? [])
            return required.allSatisfy(available.contains)
        })
    }

    // MARK: - Loading

    static func discoverSnapshots(in root: URL) -> [String] {
        let snapshotsRoot = root.appendingPathComponent("data/snapshots", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
    }

    var snapshotStore: SnapshotStore {
        SnapshotStore(
            root: contentRoot
                .appendingPathComponent("data/snapshots", isDirectory: true)
                .appendingPathComponent(snapshotTag, isDirectory: true)
        )
    }

    func reloadIcons() {
        do {
            icons = try IconStore(
                assetsRoot: contentRoot.appendingPathComponent("assets", isDirectory: true),
                mode: assetsMode
            )
        } catch {
            phase = .failed("Could not load rarity icons: \(error)")
        }
    }

    /// Reloads the card pool for the current snapshot and layout, then replans.
    public func reload() {
        guard !snapshotTag.isEmpty else {
            phase = .failed("No snapshots found under \(contentRoot.path).")
            return
        }
        phase = .loading
        let store = snapshotStore
        let mode = poolKind.representativeMode
        let config = config

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CardPool, any Error> in
                do {
                    return .success(try LabelPipeline(store: store, config: config).loadPool(for: mode))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }
            switch result {
            case let .success(pool):
                self.pool = pool
                // Selections are reset rather than carried over: a set code
                // valid in one pool may not exist in another, and a stale
                // filter would silently narrow the sheet.
                self.selectedSets = []
                self.replan()
            case let .failure(error):
                self.pool = nil
                self.plan = nil
                self.phase = .failed(Self.describe(error))
            }
        }
    }

    /// Regroups and replans from the pool already in memory.
    ///
    /// Separate from ``reload()`` because editing a font size or reordering a
    /// template line must not re-read and re-parse thousands of cards.
    public func replan() {
        guard let pool else { return }
        do {
            let cards = try pool.filtered(toSets: selectedSets.isEmpty ? nil : Array(selectedSets))
            let sections = try Transform.layout(
                cards, order: sheetOrder, precedence: poolKind.precedence
            )
            self.sections = sections
            plan = try SheetPlanner.plan(sections: sections, config: config)
            phase = .ready
            if previewCard == nil { previewCard = cards.first }
        } catch {
            sections = []
            plan = nil
            phase = .failed(Self.describe(error))
        }
    }

    static func describe(_ error: any Error) -> String {
        (error as? LabelError)?.description ?? "\(error)"
    }

    // MARK: - Browsing

    /// Every card in the current pool, filtered by the search field.
    ///
    /// Search is a plain case-insensitive substring test over title and
    /// subtitle. It never touches the print path, so it is free to use ordinary
    /// locale-aware matching that the sort path must not.
    public var visibleCards: [Card] {
        guard let pool else { return [] }
        let cards = (try? pool.filtered(
            toSets: selectedSets.isEmpty ? nil : Array(selectedSets)
        )) ?? []
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return cards }
        return cards.filter { card in
            card.title.localizedCaseInsensitiveContains(query)
                || (card.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Set codes the current pool actually carries, in precedence order.
    public var availableSets: [String] {
        pool?.setsLoaded ?? []
    }

    /// Sheets the current plan would print.
    public var sheetCount: Int {
        guard let plan else { return 0 }
        return plan.sections.reduce(0) { $0 + $1.sheetCount(rowsPerSheet: plan.geometry.rowsPerSheet) }
    }

    /// Labels the current plan would print.
    public var labelCount: Int {
        guard let plan else { return 0 }
        return plan.sections.reduce(0) { total, section in
            total + section.rows.reduce(0) { rowTotal, row in
                rowTotal + row.cells.count { $0.kind == .card }
            }
        }
    }

    /// A renderer for the current plan, or nil while one is not available.
    public var renderer: SheetRenderer? {
        guard let plan, let icons else { return nil }
        return SheetRenderer(plan: plan, icons: icons)
    }

    // MARK: - Config editing

    /// Restores every layout knob to the shipped default.
    public func resetConfigToDefault() {
        config = .default
    }

    /// Moves a template line, which is the only thing that reorders label lines.
    public func moveTemplateLines(from offsets: IndexSet, to destination: Int) {
        var template = config.template
        template.move(fromOffsets: offsets, toOffset: destination)
        config.template = template
    }

    // MARK: - Order presets

    /// Applies a shipped layout, setting both the pool and the ordering.
    public func apply(preset mode: LayoutMode) {
        poolKind = mode.usesRotationPool ? .fullRotation : .premierToday
        sheetOrder = SheetOrder.preset(for: mode)
    }

    /// The shipped layout the current order matches, or nil when it is custom.
    public var matchingPreset: LayoutMode? {
        LayoutMode.allCases.first { mode in
            SheetOrder.preset(for: mode) == sheetOrder
                && (mode.usesRotationPool ? PoolKind.fullRotation : .premierToday) == poolKind
        }
    }
}
