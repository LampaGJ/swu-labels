import ArgumentParser
import CoreGraphics
import Foundation
import SWULabelsCore
import SWULabelsRender

/// Builds the art sidecar a snapshot needs before proxies can be printed.
struct Art: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "art",
        abstract: "Fetch card art locations for a snapshot, so proxies can be printed."
    )

    @Option(name: .customLong("snapshot"), help: "Snapshot tag to index art for.")
    var snapshot: String = "v2026-08-14"

    @Option(name: .customLong("content-root"), help: "Directory holding assets/ and data/.")
    var contentRoot: String?

    @Flag(name: .customLong("download"), help: "Also download every image into the art cache.")
    var download = false

    func run() async throws {
        let root = try ContentLocator.resolve(override: contentRoot)
        let snapshotRoot = root.appending(path: "data/snapshots").appending(path: snapshot)

        let index = try await ArtIndexService().buildIndex(snapshotTag: snapshot) { done, total, found in
            FileHandle.standardError.write(Data("\rpages \(done)/\(total) · \(found) with art".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        try index.write(snapshotRoot: snapshotRoot)

        print("Wrote \(snapshotRoot.appending(path: ArtIndex.filename).path(percentEncoded: false))")
        print("  \(index.entries.count) cards with art")

        // Print resolution is stated up front rather than discovered on paper.
        let summary = index.softPrintSummary
        print("  median print resolution \(Int(summary.medianDPI.rounded())) DPI at card size")
        if summary.belowThreshold > 0 {
            print("""
              note: \(summary.belowThreshold) of \(summary.total) are below \
            \(Int(CardGeometry.softPrintDPIThreshold)) DPI, so proxies will look soft. \
            That is the resolution the official CDN serves; no setting here improves it.
            """)
        }

        if download {
            let store = ArtImageStore(
                cacheDirectory: ArtImageStore.defaultCacheDirectory(contentRoot: root)
            )
            try await store.prefetch(index.entries.map(\.url)) { done, total in
                FileHandle.standardError.write(Data("\rdownloading \(done)/\(total)".utf8))
            }
            FileHandle.standardError.write(Data("\n".utf8))
            print("  art cached under \(ArtImageStore.defaultCacheDirectory(contentRoot: root).path(percentEncoded: false))")
        }
    }
}

/// Renders proxy card sheets at exact card size.
struct Proxy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proxy",
        abstract: "Render proxy card sheets at exact 63mm x 88mm card size."
    )

    @Option(name: .customLong("snapshot"), help: "Snapshot tag to read.")
    var snapshot: String = "v2026-08-14"

    @Option(name: .customLong("sets"), help: "Restrict to a comma-separated list of set codes.")
    var sets: String?

    @Option(name: .customLong("search"), help: "Only cards whose title or subtitle contains this.")
    var search: String?

    @Option(
        name: .customLong("deck"),
        help: "A text file of card titles, one per line; blank lines and # comments ignored."
    )
    var deck: String?

    @Option(name: .customLong("copies"), help: "Copies of each selected card.")
    var copies: Int = 1

    @Option(name: .customLong("limit"), help: "Stop after this many distinct cards.")
    var limit: Int?

    @Option(name: .customLong("page"), help: "Page size: usLetter or a4.")
    var page: ProxyPageSize = .usLetter

    @Option(name: .customLong("columns"), help: "Cards per row. Clamped to what fits.")
    var columns: Int = 3

    @Option(name: .customLong("rows"), help: "Cards per column. Clamped to what fits.")
    var rows: Int = 3

    @Option(name: .customLong("gutter"), help: "Millimetres between cards.")
    var gutter: Double = 0

    @Option(name: .customLong("margin"), help: "Minimum millimetres of clear page edge.")
    var margin: Double = 6

    @Option(name: .customLong("cut-guides"), help: "none, cropMarks or outline.")
    var cutGuides: ProxySheetConfig.CutGuides = .cropMarks

    @Option(name: .customLong("out"), help: "Output directory. Defaults to ./reports.")
    var outputDirectory: String?

    @Option(name: .customLong("content-root"), help: "Directory holding assets/ and data/.")
    var contentRoot: String?

    func run() async throws {
        let root = try ContentLocator.resolve(override: contentRoot)
        let snapshotRoot = root.appending(path: "data/snapshots").appending(path: snapshot)
        let store = SnapshotStore(root: snapshotRoot)
        let index = try ArtIndex.load(snapshotRoot: snapshotRoot)
        let byID = index.byCardID

        let pool = try store.loadPool(precedence: SetCatalog.rotationPrecedence)
        let selected = try select(from: pool)
        guard !selected.isEmpty else {
            throw ValidationError("no cards matched. Try a wider --search, or drop --sets.")
        }

        // Cards whose art is unknown are reported rather than silently dropped:
        // a proxy run that quietly prints 58 of 60 cards is discovered by
        // counting a cut stack.
        var proxies: [ProxyCard] = []
        var missing: [String] = []
        for card in selected {
            if let proxy = index.proxyCard(for: card, using: byID) {
                proxies.append(proxy)
            } else {
                missing.append(card.title)
            }
        }
        if !missing.isEmpty {
            FileHandle.standardError.write(Data(
                "warning: no art for \(missing.count) card(s): \(missing.prefix(5).joined(separator: ", "))\n".utf8
            ))
        }

        let config = ProxySheetConfig(
            pageSize: page,
            columns: columns,
            rows: rows,
            gutterMillimetres: gutter,
            marginMillimetres: margin,
            cutGuides: cutGuides,
            copiesPerCard: copies
        )
        if config.isGridClamped {
            let fitted = config.clamped
            FileHandle.standardError.write(Data(
                "note: \(columns)x\(rows) does not fit \(page.displayName) at this spacing; using \(fitted.columns)x\(fitted.rows)\n".utf8
            ))
        }

        let plan = ProxyPlanner.plan(cards: proxies, config: config)

        let imageStore = ArtImageStore(
            cacheDirectory: ArtImageStore.defaultCacheDirectory(contentRoot: root)
        )
        let urls = Array(Set(proxies.map(\.artURL)))
        try await imageStore.prefetch(urls) { done, total in
            FileHandle.standardError.write(Data("\rfetching art \(done)/\(total)".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        var images: [String: CGImage] = [:]
        for url in urls {
            images[url] = try await imageStore.image(for: url)
        }

        let reports = URL(fileURLWithPath: outputDirectory ?? root.appending(path: "reports").path(percentEncoded: false))
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let name = "proxies-\(snapshot)-\(plan.config.columns)x\(plan.config.rows)"
        let url = reports.appending(path: "\(name).pdf")
        try ProxyRenderer(plan: plan, images: images).renderPDF().write(to: url)

        print("Wrote \(url.path(percentEncoded: false))")
        print("  \(plan.totalCards) cards on \(plan.pages.count) sheet(s), \(plan.config.columns)x\(plan.config.rows) per sheet")
        print("  card size 63mm x 88mm — print at 100%, never \"fit to page\"")
    }

    /// Applies the selection flags, in the order a person would expect.
    private func select(from pool: CardPool) throws -> [Card] {
        var cards = pool.kept

        if let sets {
            let codes = Set(sets.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            cards = cards.filter { codes.contains($0.expansionCode) }
        }
        if let search, !search.isEmpty {
            cards = cards.filter {
                $0.title.localizedStandardContains(search)
                    || ($0.subtitle?.localizedStandardContains(search) ?? false)
            }
        }
        if let deck {
            let wanted = try Self.readDeckList(path: deck)
            // Matched on title alone, which is how a deck list is written. A
            // title present in several sets keeps the earliest printing, the
            // same rule the label pipeline's dedupe uses.
            var byTitle: [String: Card] = [:]
            for card in cards where byTitle[card.title.lowercased()] == nil {
                byTitle[card.title.lowercased()] = card
            }
            var resolved: [Card] = []
            var unmatched: [String] = []
            for title in wanted {
                if let card = byTitle[title.lowercased()] {
                    resolved.append(card)
                } else {
                    unmatched.append(title)
                }
            }
            if !unmatched.isEmpty {
                FileHandle.standardError.write(Data(
                    "warning: \(unmatched.count) deck line(s) matched no card: \(unmatched.prefix(5).joined(separator: ", "))\n".utf8
                ))
            }
            cards = resolved
        }
        if let limit, cards.count > limit {
            cards = Array(cards.prefix(limit))
        }
        return cards
    }

    static func readDeckList(path: String) throws -> [String] {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

extension ProxyPageSize: ExpressibleByArgument {}
extension ProxySheetConfig.CutGuides: ExpressibleByArgument {}
