import CoreGraphics
import Foundation
import Observation
import SWULabelsCore
import SWULabelsRender

/// The interface's single source of truth.
///
/// Holds no layout logic of its own. Every decision about what a label contains
/// or where it sits comes from `SWULabelsCore` and `SWULabelsRender`, the same
/// path the command line takes, so the window cannot show one thing and the
/// printer produce another.
///
/// `@MainActor` because it drives the interface. The expensive work — parsing a
/// snapshot of several thousand cards — runs on a `nonisolated` function, so it
/// leaves the main actor without a detached task and keeps the caller's
/// priority and cancellation.
@Observable
@MainActor
public final class AppModel {
    // MARK: - Phase

    /// Where the pipeline is in its load-plan cycle.
    public enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)

        public var isLoading: Bool { self == .loading }

        public var errorMessage: String? {
            if case let .failed(message) = self { message } else { nil }
        }
    }

    /// Which card pool is loaded.
    ///
    /// Mapped onto a representative ``LayoutMode`` rather than given its own
    /// loader, so both pools keep the coverage and magnitude guards the shipped
    /// pipeline already applies. A pool loaded without them could ship an
    /// incomplete sheet that looks complete.
    public enum PoolKind: String, CaseIterable, Identifiable, Sendable {
        case premierToday
        case fullRotation

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .premierToday: "Premier-legal today"
            case .fullRotation: "Full rotation history"
            }
        }

        public var summary: String {
            switch self {
            case .premierToday:
                "The six sets currently legal in Premier."
            case .fullRotation:
                "Every set that has ever been Premier-legal, rotated-out ones included."
            }
        }

        var representativeMode: LayoutMode {
            self == .premierToday ? .aspectSet : .rotationAspectSet
        }

        public var precedence: [String] { representativeMode.precedence }

        /// Sets a snapshot must carry to satisfy this pool.
        var requiredSets: [String] {
            switch self {
            case .premierToday: SetCatalog.premierPrecedence
            case .fullRotation: LabelPipeline.requiredRotationSets
            }
        }
    }

    // MARK: - Stored state

    public let contentRoot: URL
    public private(set) var availableSnapshots: [String] = []

    public var snapshotTag: String {
        didSet {
            guard snapshotTag != oldValue else { return }
            reload()
            // The art sidecar is per-snapshot, so it must follow the snapshot or
            // proxies would be built from another snapshot's art.
            loadArtIndexIfPresent()
        }
    }

    public var poolKind: PoolKind = .fullRotation {
        didSet {
            guard poolKind != oldValue else { return }
            // A pool the current snapshot cannot satisfy would throw on load and
            // show an error where a working sheet is expected. Moving to a
            // snapshot that carries the pool's sets is the useful behaviour.
            if let better = bestSnapshot(for: poolKind), better != snapshotTag {
                snapshotTag = better
            } else {
                reload()
            }
        }
    }

    /// How sheets are divided and ordered.
    public var sheetOrder: SheetOrder = .aspectThenSet {
        didSet { if sheetOrder != oldValue { replan() } }
    }

    public var assetsMode: AssetsMode = .color {
        didSet { if assetsMode != oldValue { reloadIcons() } }
    }

    /// Set codes to restrict to. Empty means every set in the pool.
    public var selectedSets: Set<String> = [] {
        didSet { if selectedSets != oldValue { replan() } }
    }

    public var searchText = "" {
        didSet { if searchText != oldValue { refreshVisible() } }
    }

    /// The live-edited layout configuration.
    public var config: LabelLayoutConfig = .default {
        didSet { if config != oldValue { replan() } }
    }

    /// The card the label preview shows.
    public var selectedCardID: Card.ID?

    // MARK: - Proxies

    /// Whether the app is producing labels or proxy cards.
    var outputMode: OutputMode = .labels

    /// Sheet settings for proxy printing.
    var proxyConfig: ProxySheetConfig = .default

    /// Card art locations for the current snapshot, when they have been fetched.
    ///
    /// Absent is a normal state, not an error: art is a separate, optional
    /// download, and the label pipeline never needs it.
    private(set) var artIndex: ArtIndex?
    private(set) var artFetchProgress: (done: Int, total: Int)?
    private(set) var artFailure: String?

    // MARK: - Derived state

    public private(set) var phase: Phase = .idle
    public private(set) var pool: CardPool?
    /// The grouped, ordered sections behind the current plan.
    ///
    /// Kept alongside the plan because the browser lists cards in printed order.
    /// Recovering that order from the plan would mean matching resolved label
    /// text back to cards, which is slower and wrong for two cards sharing a
    /// title.
    public private(set) var sections: [LabelSection] = []
    public private(set) var plan: SheetPlan?
    public private(set) var icons: IconStore?

    /// The cards the browser lists, and the sections it lists them under.
    ///
    /// Stored rather than computed. Deriving them in `body` re-filtered several
    /// thousand cards on every view evaluation, and — because selecting a row
    /// mutates this object while the list is drawing it — AppKit reported a
    /// reentrant operation in its table delegate. Both are the same bug: an
    /// expensive transform read from a view body that also writes to it.
    ///
    /// Invalidation is explicit and lives in ``refreshVisible()``, called from
    /// the two places the inputs change: a replan, and a search edit.
    public private(set) var visibleCards: [Card] = []
    private(set) var visibleSections: [CardListSection] = []

    public init(contentRoot: URL) {
        self.contentRoot = contentRoot
        snapshotTag = ""
        availableSnapshots = Self.discoverSnapshots(in: contentRoot)
        // Prefer the newest snapshot that can satisfy the starting pool. Taking
        // the newest tag unconditionally is what hid SOR, SHD and TWI: the most
        // recent snapshot carries only the six currently-legal sets, so the app
        // opened three sets short with nothing to say why.
        snapshotTag = Self.bestSnapshot(
            for: poolKind, among: availableSnapshots, contentRoot: contentRoot
        ) ?? availableSnapshots.max() ?? ""
        reloadIcons()
        reload()
        loadArtIndexIfPresent()
    }

    // MARK: - Snapshot discovery

    static func discoverSnapshots(in root: URL) -> [String] {
        let snapshotsRoot = root.appending(path: "data/snapshots")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
    }

    static func store(for tag: String, contentRoot: URL) -> SnapshotStore {
        SnapshotStore(root: contentRoot.appending(path: "data/snapshots").appending(path: tag))
    }

    var snapshotStore: SnapshotStore {
        Self.store(for: snapshotTag, contentRoot: contentRoot)
    }

    /// The newest snapshot carrying every set `pool` needs.
    ///
    /// Tags are `vYYYY-MM-DD`, so sorting them lexicographically sorts them
    /// chronologically. No date parsing, and no `Date`, which the determinism
    /// rules keep out of this codebase entirely.
    static func bestSnapshot(
        for pool: PoolKind,
        among tags: [String],
        contentRoot: URL
    ) -> String? {
        tags.sorted().reversed().first { tag in
            supports(pool: pool, tag: tag, contentRoot: contentRoot)
        }
    }

    static func supports(pool: PoolKind, tag: String, contentRoot: URL) -> Bool {
        let available = Set(
            (try? store(for: tag, contentRoot: contentRoot).availableSetCodes()) ?? []
        )
        return pool.requiredSets.allSatisfy(available.contains)
    }

    func bestSnapshot(for pool: PoolKind) -> String? {
        Self.bestSnapshot(for: pool, among: availableSnapshots, contentRoot: contentRoot)
    }

    /// Whether a snapshot can satisfy the pool now selected.
    public func snapshotSupportsCurrentPool(_ tag: String) -> Bool {
        Self.supports(pool: poolKind, tag: tag, contentRoot: contentRoot)
    }

    // MARK: - Loading

    func reloadIcons() {
        do {
            icons = try IconStore(
                assetsRoot: contentRoot.appending(path: "assets"), mode: assetsMode
            )
        } catch {
            phase = .failed("Could not load rarity icons: \(error.localizedDescription)")
        }
    }

    /// Parses a pool off the main actor.
    ///
    /// `nonisolated` rather than `Task.detached`: the work is pure and its
    /// inputs are `Sendable`, so it runs off the main actor on its own while
    /// still inheriting the caller's priority and cancellation, which a detached
    /// task discards.
    nonisolated static func loadPool(
        store: SnapshotStore,
        mode: LayoutMode,
        config: LabelLayoutConfig
    ) async throws -> CardPool {
        try LabelPipeline(store: store, config: config).loadPool(for: mode)
    }

    /// Reloads the card pool for the current snapshot and pool, then replans.
    public func reload() {
        guard !snapshotTag.isEmpty else {
            phase = .failed("No snapshots found under \(contentRoot.path(percentEncoded: false)).")
            return
        }
        phase = .loading
        let store = snapshotStore
        let mode = poolKind.representativeMode
        let config = config

        Task {
            do {
                let loaded = try await Self.loadPool(store: store, mode: mode, config: config)
                pool = loaded
                // Selections reset rather than carry over: a set code valid in
                // one pool may not exist in another, and a stale filter would
                // silently narrow the sheet.
                selectedSets = []
                replan()
            } catch {
                pool = nil
                sections = []
                plan = nil
                phase = .failed(Self.describe(error))
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
            sections = try Transform.layout(
                cards, order: sheetOrder, precedence: poolKind.precedence
            )
            plan = try SheetPlanner.plan(sections: sections, config: config)
            refreshVisible()
            phase = .ready
            // Selection is deliberately NOT seeded here. Writing it during a
            // replan mutates state the list is already rendering, which AppKit
            // reports as a reentrant operation in its table delegate.
            // ``previewCard`` falls back to the first visible card instead, so
            // the preview is populated without the model writing to selection.
        } catch {
            sections = []
            plan = nil
            refreshVisible()
            phase = .failed(Self.describe(error))
        }
    }

    static func describe(_ error: any Error) -> String {
        (error as? LabelError)?.description ?? error.localizedDescription
    }

    // MARK: - Browsing

    /// Recomputes the browser's cards and sections from the current pool,
    /// set filter and search text.
    ///
    /// `localizedStandardContains` is the right matcher for user-entered
    /// search: it folds case and diacritics the way the rest of the system
    /// does. It appears only here, never in the sort path, which stays
    /// locale-independent because the printed order must not depend on the
    /// host's locale data.
    func refreshVisible() {
        guard let pool else {
            visibleCards = []
            visibleSections = []
            return
        }
        let cards = (try? pool.filtered(
            toSets: selectedSets.isEmpty ? nil : Array(selectedSets)
        )) ?? []
        let query = searchText.trimmingCharacters(in: .whitespaces)
        visibleCards = query.isEmpty ? cards : cards.filter { card in
            card.title.localizedStandardContains(query)
                || (card.subtitle?.localizedStandardContains(query) ?? false)
        }

        let visible = Set(visibleCards.map(\.id))
        visibleSections = sections.compactMap { section in
            let sectionCards = section.slots.compactMap { slot -> Card? in
                guard case let .card(card) = slot, visible.contains(card.id) else { return nil }
                return card
            }
            return sectionCards.isEmpty
                ? nil
                : CardListSection(key: section.key, cards: sectionCards)
        }
    }

    /// The card the preview shows.
    public var previewCard: Card? {
        guard let selectedCardID else { return visibleCards.first }
        return visibleCards.first { $0.id == selectedCardID } ?? visibleCards.first
    }

    /// Set codes the current pool carries, in precedence order.
    public var availableSets: [String] { pool?.setsLoaded ?? [] }

    /// Sheets the current plan would print.
    public var sheetCount: Int {
        guard let plan else { return 0 }
        return plan.sections.reduce(0) {
            $0 + $1.sheetCount(rowsPerSheet: plan.geometry.rowsPerSheet)
        }
    }

    /// Labels the current plan would print.
    public var labelCount: Int {
        sections.reduce(0) { $0 + $1.cardCount }
    }

    /// A renderer for the current plan, or nil while one is unavailable.
    public var renderer: SheetRenderer? {
        guard let plan, let icons else { return nil }
        return SheetRenderer(plan: plan, icons: icons)
    }

    public var printJobName: String {
        "SWU labels — \(matchingPreset?.displayName ?? "custom order")"
    }

    // MARK: - Proxies

    /// Loads the art sidecar for the current snapshot, if one has been fetched.
    func loadArtIndexIfPresent() {
        artIndex = try? ArtIndex.load(snapshotRoot: snapshotStore.root)
    }

    /// The cards a proxy run would print: whatever the browser is showing.
    ///
    /// Reusing the visible selection rather than adding a second, parallel
    /// selection mechanism — filter the list to what you want, then print it.
    var proxyCards: [ProxyCard] {
        guard let artIndex else { return [] }
        let index = artIndex.byCardID
        return visibleCards.compactMap { artIndex.proxyCard(for: $0, using: index) }
    }

    /// Visible cards whose art is not in the index, so the gap is stated rather
    /// than silently shrinking the print run.
    var proxyCardsMissingArt: Int {
        guard let artIndex else { return 0 }
        let index = artIndex.byCardID
        return visibleCards.count { index[$0.id] == nil }
    }

    var proxyPlan: ProxyPlan {
        ProxyPlanner.plan(cards: proxyCards, config: proxyConfig)
    }

    /// Median print resolution across the cards a run would print.
    ///
    /// Reported per selection rather than per snapshot because it varies by a
    /// factor of more than two between sets: the two newest sets ship art near
    /// 289 DPI, while everything older is about 121 DPI.
    var proxyMedianDPI: Double? {
        guard let artIndex else { return nil }
        let index = artIndex.byCardID
        let dpis = visibleCards.compactMap { index[$0.id]?.effectiveDPI }.sorted()
        return dpis.isEmpty ? nil : dpis[dpis.count / 2]
    }

    var artCacheDirectory: URL {
        ArtImageStore.defaultCacheDirectory(contentRoot: contentRoot)
    }

    /// Downloads any art the current selection needs.
    func prefetchProxyArt() async {
        let urls = Array(Set(proxyCards.map(\.artURL)))
        guard !urls.isEmpty else { return }
        artFailure = nil
        artFetchProgress = (done: 0, total: urls.count)
        let store = ArtImageStore(cacheDirectory: artCacheDirectory)
        do {
            try await store.prefetch(urls) { done, total in
                Task { @MainActor in self.artFetchProgress = (done: done, total: total) }
            }
            artFetchProgress = nil
        } catch {
            artFetchProgress = nil
            artFailure = error.localizedDescription
        }
    }

    /// Decoded art for the current selection, for rendering or preview.
    func proxyImages() async throws -> [String: CGImage] {
        let store = ArtImageStore(cacheDirectory: artCacheDirectory)
        var images: [String: CGImage] = [:]
        for url in Set(proxyCards.map(\.artURL)) {
            images[url] = try await store.image(for: url)
        }
        return images
    }

    // MARK: - Set filtering

    public func isSetIncluded(_ code: String) -> Bool {
        selectedSets.isEmpty || selectedSets.contains(code)
    }

    public var setSelectionSummary: String {
        selectedSets.isEmpty
            ? "Every set in the pool is included."
            : "\(selectedSets.count) of \(availableSets.count) sets included."
    }

    /// Includes or excludes one set.
    ///
    /// An empty selection means "everything", so the first click has to become
    /// "everything except this one" rather than "only this one", which is what a
    /// naive insert would do.
    public func toggleSet(_ code: String) {
        var next = selectedSets.isEmpty ? Set(availableSets) : selectedSets
        if next.contains(code) {
            next.remove(code)
        } else {
            next.insert(code)
        }
        selectedSets = next.count == availableSets.count ? [] : next
    }

    // MARK: - Ordering

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

    /// Moves a characteristic into one of the two ordering lists.
    func place(_ key: SortKey, into role: OrderByEditorRole) {
        var next = sheetOrder
        next.groupBy.removeAll { $0.key == key }
        next.thenBy.removeAll { $0.key == key }
        switch role {
        case .grouping: next.groupBy.append(SortCriterion(key: key))
        case .ordering: next.thenBy.append(SortCriterion(key: key))
        }
        sheetOrder = next
    }

    public func remove(_ key: SortKey) {
        var next = sheetOrder
        next.groupBy.removeAll { $0.key == key }
        next.thenBy.removeAll { $0.key == key }
        sheetOrder = next
    }

    public func toggleDirection(of key: SortKey) {
        var next = sheetOrder
        for index in next.groupBy.indices where next.groupBy[index].key == key {
            next.groupBy[index].direction = next.groupBy[index].direction.opposite
        }
        for index in next.thenBy.indices where next.thenBy[index].key == key {
            next.thenBy[index].direction = next.thenBy[index].direction.opposite
        }
        sheetOrder = next
    }

    func moveCriteria(
        in role: OrderByEditorRole,
        from offsets: IndexSet,
        to destination: Int
    ) {
        var next = sheetOrder
        switch role {
        case .grouping: next.groupBy.move(fromOffsets: offsets, toOffset: destination)
        case .ordering: next.thenBy.move(fromOffsets: offsets, toOffset: destination)
        }
        sheetOrder = next
    }

    // MARK: - Template

    /// Restores every layout knob to the shipped default.
    public func resetConfigToDefault() {
        config = .default
    }

    /// Moves a template line, which is the only thing that reorders label lines.
    public func moveTemplateLines(from offsets: IndexSet, to destination: Int) {
        config.template.move(fromOffsets: offsets, toOffset: destination)
    }
}
