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

    public var layoutMode: LayoutMode = .aspectSet {
        didSet { if layoutMode != oldValue { reload() } }
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
    public private(set) var plan: SheetPlan?
    public private(set) var icons: IconStore?

    /// The card currently shown in the label editor's preview.
    public var previewCard: Card?

    public init(contentRoot: URL) {
        self.contentRoot = contentRoot
        snapshotTag = ""
        availableSnapshots = Self.discoverSnapshots(in: contentRoot)
        // Newest tag first: tags are `vYYYY-MM-DD`, so lexicographic order is
        // chronological order without parsing a date — and without a `Date`,
        // which the determinism rules keep out of this codebase entirely.
        snapshotTag = availableSnapshots.sorted().last ?? ""
        reloadIcons()
        reload()
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
        let mode = layoutMode
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
            let pipeline = LabelPipeline(store: snapshotStore, config: config)
            let sections = try pipeline.sections(for: layoutMode, cards: cards)
            plan = try SheetPlanner.plan(sections: sections, config: config)
            phase = .ready
            if previewCard == nil { previewCard = cards.first }
        } catch {
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
}
