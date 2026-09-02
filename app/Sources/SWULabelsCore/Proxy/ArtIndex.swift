import Foundation

/// Where each card's front art lives.
///
/// **A sidecar file, deliberately not a field on ``Card``.** The per-set
/// snapshot files are byte-exact artifacts: their SHA-256 digests are recorded
/// in `meta.json` and in every replay record, and `SnapshotSerializerTests`
/// requires this codebase to reproduce them exactly. Adding an art URL to `Card`
/// would rewrite all of them and invalidate every recorded hash, to carry a
/// field the label pipeline never reads.
///
/// So art lives beside the snapshot in `art.json`, fetched separately and
/// updated independently. Labels stay unaffected; proxies get what they need.
public struct ArtIndex: Codable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// Matches ``Card/id`` — title, subtitle and expansion code.
        public var id: String
        /// Absolute URL of the largest art the CDN offers for this card.
        public var url: String
        /// Whether the art is landscape, as Leaders and Bases are.
        public var horizontal: Bool
        /// Pixel dimensions of that art, used to report print resolution
        /// honestly rather than making a claim about sharpness nobody checked.
        public var pixelWidth: Int
        public var pixelHeight: Int

        public init(
            id: String,
            url: String,
            horizontal: Bool,
            pixelWidth: Int,
            pixelHeight: Int
        ) {
            self.id = id
            self.url = url
            self.horizontal = horizontal
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        /// The resolution this art reaches at printed card size.
        public var effectiveDPI: Double {
            CardGeometry.effectiveDPI(pixelsOnLongEdge: max(pixelWidth, pixelHeight))
        }
    }

    /// The snapshot these entries were built from.
    public var snapshotTag: String
    public var entries: [Entry]

    public init(snapshotTag: String, entries: [Entry]) {
        self.snapshotTag = snapshotTag
        self.entries = entries
    }

    /// Entries keyed by card id.
    ///
    /// A `Dictionary` is safe here because it is only ever subscripted, never
    /// iterated into output — the rule that keeps randomized iteration order out
    /// of anything printed.
    public var byCardID: [String: Entry] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The proxy card for one card, when its art is known.
    public func proxyCard(for card: Card, using index: [String: Entry]) -> ProxyCard? {
        guard let entry = index[card.id] else { return nil }
        return ProxyCard(
            id: card.id,
            title: card.title,
            subtitle: card.subtitle,
            expansionCode: card.expansionCode,
            artURL: entry.url,
            isHorizontal: entry.horizontal
        )
    }

    // MARK: - Persistence

    public static let filename = "art.json"

    public static func load(snapshotRoot: URL) throws -> ArtIndex {
        let url = snapshotRoot.appending(path: filename)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ArtIndexError.notFetched(snapshot: snapshotRoot.lastPathComponent)
        }
        return try JSONDecoder().decode(ArtIndex.self, from: Data(contentsOf: url))
    }

    /// Writes the index beside its snapshot.
    ///
    /// Sorted by id and pretty-printed so two runs over unchanged upstream data
    /// produce identical bytes and a real change shows as a readable diff.
    public func write(snapshotRoot: URL) throws {
        var sorted = self
        sorted.entries = entries.sorted { UTF16Order.isLessThan($0.id, $1.id) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(sorted).write(to: snapshotRoot.appending(path: Self.filename))
    }

    /// The share of art below the soft-print threshold, for an honest warning.
    public var softPrintSummary: (total: Int, belowThreshold: Int, medianDPI: Double) {
        let dpis = entries.map(\.effectiveDPI).sorted()
        let median = dpis.isEmpty ? 0 : dpis[dpis.count / 2]
        return (
            total: entries.count,
            belowThreshold: dpis.count { $0 < CardGeometry.softPrintDPIThreshold },
            medianDPI: median
        )
    }
}

public enum ArtIndexError: Error, CustomStringConvertible, Equatable {
    case notFetched(snapshot: String)
    case artMissing(cardIDs: [String])

    public var description: String {
        switch self {
        case let .notFetched(snapshot):
            "no art index for snapshot \(snapshot) — run `swu-labels art --snapshot \(snapshot)` first"
        case let .artMissing(cardIDs):
            "no art for \(cardIDs.count) selected card(s), e.g. \(cardIDs.prefix(3).joined(separator: ", "))"
        }
    }
}
