import CryptoKit
import Foundation

/// Fetches the live card list and writes a pinned snapshot.
///
/// The public face of ingest. Everything about the transport stays behind it, so
/// an upstream shape change is contained here rather than rippling into callers.
///
/// Determinism is the property that matters. The snapshot tag comes from the
/// data's own maximum `updatedAt`, never from the clock, so two ingests of
/// unchanged upstream data produce the same tag and byte-identical files. Cards
/// are sorted on a fixed key before bucketing, so the order pages happened to
/// arrive in cannot reach the output. Nothing here calls `Date`, a random
/// source, or a locale-aware comparison.
public struct IngestService: Sendable {
    public struct Summary: Sendable {
        public let tag: String
        public let totalCardsFetched: Int
        public let canonicalCards: Int
        /// Set codes, sorted, with their card counts.
        public let setCounts: [(code: String, count: Int)]
        public let snapshotURL: URL
    }

    public let client: CardListClient
    /// Directory holding `data/` and the vendored `formats.json`.
    public let contentRoot: URL

    public init(contentRoot: URL, client: CardListClient = CardListClient()) {
        self.contentRoot = contentRoot
        self.client = client
    }

    /// Runs a full ingest and writes the snapshot.
    ///
    /// - Parameter tagOverride: pins the snapshot tag instead of deriving it,
    ///   for redoing a failed ingest under the same name.
    public func run(
        tagOverride: String? = nil,
        progress: @Sendable (_ pagesDone: Int, _ pageCount: Int, _ cardsFetched: Int) -> Void = { _, _, _ in }
    ) async throws -> Summary {
        let apiCards = try await client.fetchAllPages(progress: progress)
        let canonical = apiCards.filter(\.isCanonicalPrinting)
        let mapped = try canonical.map { try $0.toCard() }

        let tag = try tagOverride ?? Self.deriveTag(fromUpdatedAt: mapped.map(\.updatedAt))

        // Card number is the primary sort key; a card without one sorts last
        // rather than first, so a missing number never displaces real cards.
        let sortable = zip(canonical, mapped).map { apiCard, entry in
            (card: entry.card, cardNumber: apiCard.attributes.cardNumber)
        }
        let sorted = SortKeys.stableSorted(sortable) { lhs, rhs in
            Self.compare(lhs, rhs) == .orderedAscending
        }
        let cards = sorted.map(\.card)

        return try write(cards: cards, tag: tag, totalFetched: apiCards.count)
    }

    /// The snapshot tag, derived from the data rather than the clock.
    ///
    /// `updatedAt` is fixed-width ISO-8601, so the maximum can be found by plain
    /// string comparison — no date parsing, and therefore no `Date`, which the
    /// determinism rules exclude from this codebase.
    public static func deriveTag(fromUpdatedAt values: [String]) throws -> String {
        guard var maximum = values.first else {
            throw IngestError.noCardsToDeriveTagFrom
        }
        for value in values where UTF16Order.compare(value, maximum) == .orderedDescending {
            maximum = value
        }
        return "v\(String(maximum.prefix(10)))"
    }

    static func compare(
        _ lhs: (card: Card, cardNumber: Int?),
        _ rhs: (card: Card, cardNumber: Int?)
    ) -> ComparisonResult {
        switch (lhs.cardNumber, rhs.cardNumber) {
        case let (left?, right?) where left != right:
            return left < right ? .orderedAscending : .orderedDescending
        case (nil, .some):
            return .orderedDescending
        case (.some, nil):
            return .orderedAscending
        default:
            break
        }
        return UTF16Order.chain([
            UTF16Order.compare(lhs.card.title, rhs.card.title),
            UTF16Order.compare(lhs.card.subtitle ?? "", rhs.card.subtitle ?? ""),
        ])
    }

    // MARK: - Writing

    func write(cards: [Card], tag: String, totalFetched: Int) throws -> Summary {
        let snapshotURL = contentRoot.appending(path: "data/snapshots").appending(path: tag)
        let perSetURL = snapshotURL.appending(path: "per-set")
        try FileManager.default.createDirectory(at: perSetURL, withIntermediateDirectories: true)

        // Bucketed in insertion order, which is the sorted order, so each
        // bucket is already correctly ordered without a second sort.
        var buckets = OrderedBuckets<String, Card>()
        for card in cards {
            buckets.append(card, to: card.expansionCode)
        }

        let setCodes = buckets.keys.sorted()
        var counts: [String: Int] = [:]
        var digests: [String: String] = [:]

        for code in setCodes {
            let setCards = buckets[code] ?? []
            let text = SnapshotSerializer.perSetJSON(setCards)
            try Data(text.utf8).write(to: perSetURL.appending(path: "\(code).json"))
            counts[code] = setCards.count
            digests[code] = SnapshotStore.sha256(Data(text.utf8))
        }

        // The vendored manifest is copied in verbatim so the snapshot records
        // which sets were Premier-legal when it was taken.
        let formatsSource = contentRoot.appending(path: "formats.json")
        guard let formats = try? Data(contentsOf: formatsSource) else {
            throw IngestError.formatsManifestMissing(formatsSource.path(percentEncoded: false))
        }
        try formats.write(to: snapshotURL.appending(path: "formats.json"))

        let meta = SnapshotMeta(
            tag: tag,
            sourceURL: CardListClient.baseURL,
            totalCardsFetched: totalFetched,
            canonicalCards: cards.count,
            sets: setCodes,
            setCounts: counts,
            setSHA256: digests
        )
        try Data(SnapshotSerializer.metaJSON(meta).utf8)
            .write(to: snapshotURL.appending(path: "meta.json"))

        return Summary(
            tag: tag,
            totalCardsFetched: totalFetched,
            canonicalCards: cards.count,
            setCounts: setCodes.map { (code: $0, count: counts[$0] ?? 0) },
            snapshotURL: snapshotURL
        )
    }
}
