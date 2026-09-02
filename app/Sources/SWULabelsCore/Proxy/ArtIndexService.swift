import Foundation

/// The card-list shapes needed to locate art, and nothing else.
enum ArtAPI {
    struct File: Decodable, Sendable {
        let url: String
        let width: Int?
        let height: Int?
    }

    struct Attributes: Decodable, Sendable {
        let title: String
        let subtitle: String?
        let artFrontHorizontal: Bool?
        let expansion: SWUAPI.ToOne<SWUAPI.NamedCode>
        let artFront: SWUAPI.ToOne<File>?
        let variantOf: SWUAPI.ToOne<SWUAPI.Presence>
    }

    struct Card: Decodable, Sendable {
        let id: Int
        let attributes: Attributes
    }

    struct PageResponse: Decodable, Sendable {
        let data: [Card]
        let meta: SWUAPI.Meta
    }
}

/// Builds the art sidecar for a snapshot.
///
/// Art is fetched separately from the card data on purpose. The snapshot files
/// are byte-exact artifacts whose digests are recorded in replay records, so
/// they must not gain a field; and art URLs change independently of card data,
/// so refetching them should not mean re-ingesting three thousand cards.
public struct ArtIndexService: Sendable {
    /// Used when the API returns a site-relative art path rather than a full URL.
    public static let cdnBase = "https://cdn.starwarsunlimited.com"

    public let client: CardListClient

    public init(client: CardListClient = CardListClient()) {
        self.client = client
    }

    /// Fetches art for every canonical printing.
    ///
    /// Filtered to canonical printings by the same `variantOf` rule the snapshot
    /// itself uses. Without it an alternate-art variant could claim a card's id
    /// and put the wrong picture on a proxy.
    public func buildIndex(
        snapshotTag: String,
        progress: @Sendable (_ pagesDone: Int, _ pageCount: Int, _ found: Int) -> Void = { _, _, _ in }
    ) async throws -> ArtIndex {
        let populate = CardListClient.artPopulateFields + ["variantOf"]
        let first = try await client.fetchPage(1, populate: populate, as: ArtAPI.PageResponse.self)
        let pageCount = first.meta.pagination.pageCount

        var entries: [ArtIndex.Entry] = []
        var seen = Set<String>()

        func absorb(_ cards: [ArtAPI.Card]) {
            for card in cards where card.attributes.variantOf.data == nil {
                guard
                    let expansion = card.attributes.expansion.data?.attributes.code,
                    let file = card.attributes.artFront?.data?.attributes
                else { continue }
                let id = Self.cardID(
                    title: card.attributes.title,
                    subtitle: card.attributes.subtitle,
                    expansionCode: expansion
                )
                guard seen.insert(id).inserted else { continue }
                entries.append(ArtIndex.Entry(
                    id: id,
                    url: Self.absoluteURL(file.url),
                    horizontal: card.attributes.artFrontHorizontal ?? false,
                    pixelWidth: file.width ?? 0,
                    pixelHeight: file.height ?? 0
                ))
            }
        }

        absorb(first.data)
        progress(1, pageCount, entries.count)

        if pageCount > 1 {
            var completed = 1
            var nextPage = 2
            try await withThrowingTaskGroup(of: (Int, [ArtAPI.Card]).self) { group in
                for _ in 0..<min(CardListClient.pageConcurrency, pageCount - 1) {
                    let page = nextPage
                    nextPage += 1
                    group.addTask {
                        (page, try await client.fetchPage(
                            page, populate: populate, as: ArtAPI.PageResponse.self
                        ).data)
                    }
                }
                // Pages are absorbed as they land. Order does not matter here,
                // unlike the card ingest: entries are keyed by card id and the
                // index is sorted before it is written.
                while let (_, cards) = try await group.next() {
                    absorb(cards)
                    completed += 1
                    progress(completed, pageCount, entries.count)
                    if nextPage <= pageCount {
                        let page = nextPage
                        nextPage += 1
                        group.addTask {
                            (page, try await client.fetchPage(
                                page, populate: populate, as: ArtAPI.PageResponse.self
                            ).data)
                        }
                    }
                }
            }
        }

        return ArtIndex(
            snapshotTag: snapshotTag,
            entries: entries.sorted { UTF16Order.isLessThan($0.id, $1.id) }
        )
    }

    /// The card identity the snapshot uses, so the two sides line up.
    static func cardID(title: String, subtitle: String?, expansionCode: String) -> String {
        "\(title)|\(subtitle ?? "")|\(expansionCode)"
    }

    /// Completes a site-relative art path against the CDN.
    static func absoluteURL(_ url: String) -> String {
        url.hasPrefix("http") ? url : cdnBase + url
    }
}
