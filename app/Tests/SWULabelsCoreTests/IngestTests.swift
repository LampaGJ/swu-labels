import Foundation
import Testing

@testable import SWULabelsCore

/// The pure parts of ingest: tag derivation and the deterministic sort.
///
/// The end-to-end proof is stronger than anything here — a live ingest run
/// reproduced the committed `v2026-08-14` snapshot byte for byte, including the
/// SHA-256 digests inside `meta.json`, which would have exposed any difference.
/// These tests exist because that proof needs the network and a cooperative
/// upstream, whereas the rules below can be pinned unconditionally.
@Suite
struct IngestRules {
    // MARK: - Tag derivation

    @Test
    func `the tag is the newest updatedAt, not the clock`() throws {
        let tag = try IngestService.deriveTag(fromUpdatedAt: [
            "2026-08-01T10:00:00.000Z",
            "2026-08-14T23:59:59.999Z",
            "2026-07-30T00:00:00.000Z",
        ])
        #expect(tag == "v2026-08-14")
    }

    @Test
    func `deriving a tag from no cards fails rather than inventing one`() {
        #expect(throws: IngestError.noCardsToDeriveTagFrom) {
            try IngestService.deriveTag(fromUpdatedAt: [])
        }
    }

    @Test
    func `tag derivation is order independent`() throws {
        let values = [
            "2026-01-02T00:00:00.000Z",
            "2026-08-14T12:00:00.000Z",
            "2026-03-04T00:00:00.000Z",
        ]
        // Same input in any order must give the same tag, or two ingests of one
        // dataset could disagree purely on the order pages arrived in.
        let forward = try IngestService.deriveTag(fromUpdatedAt: values)
        let backward = try IngestService.deriveTag(fromUpdatedAt: values.reversed())
        let rotated = try IngestService.deriveTag(fromUpdatedAt: Array(values[1...] + values[..<1]))
        #expect(forward == backward)
        #expect(forward == rotated)
        #expect(forward == "v2026-08-14")
    }

    // MARK: - Sort order

    static func entry(_ title: String, number: Int?, subtitle: String? = nil)
        -> (card: Card, cardNumber: Int?) {
        (
            card: Card(
                title: title,
                subtitle: subtitle,
                typeName: .unit,
                rarity: .common,
                expansionCode: "JTL"
            ),
            cardNumber: number
        )
    }

    @Test
    func `cards sort by card number first`() {
        let a = Self.entry("Zeta", number: 1)
        let b = Self.entry("Alpha", number: 2)
        #expect(IngestService.compare(a, b) == .orderedAscending)
    }

    /// A card with no number sorts last, not first.
    ///
    /// Sorting it first would let a single unnumbered card displace every real
    /// card on the sheet by one position.
    @Test
    func `a missing card number sorts last`() {
        let numbered = Self.entry("Alpha", number: 99)
        let unnumbered = Self.entry("Alpha", number: nil)
        #expect(IngestService.compare(numbered, unnumbered) == .orderedAscending)
        #expect(IngestService.compare(unnumbered, numbered) == .orderedDescending)
    }

    @Test
    func `ties break on title then subtitle, by code unit`() {
        let a = Self.entry("Alpha", number: 1, subtitle: "A")
        let b = Self.entry("Alpha", number: 1, subtitle: "B")
        #expect(IngestService.compare(a, b) == .orderedAscending)

        let c = Self.entry("Alpha", number: 1)
        let d = Self.entry("Beta", number: 1)
        #expect(IngestService.compare(c, d) == .orderedAscending)
    }

    // MARK: - Request shape

    @Test
    func `the page URL requests only the relations the pipeline consumes`() throws {
        let url = CardListClient.pageURL(page: 7)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []

        #expect(items.contains { $0.name == "pagination[page]" && $0.value == "7" })
        #expect(items.contains { $0.name == "pagination[pageSize]" && $0.value == "100" })

        // Art fields would multiply the payload for output that carries no card
        // images, so their absence is asserted rather than assumed.
        let populated = items.filter { $0.name.hasPrefix("populate[") }.compactMap(\.value)
        #expect(populated.contains("expansion"))
        #expect(populated.contains("aspects"))
        #expect(populated.contains("variantOf"))
        #expect(!populated.contains { $0.localizedCaseInsensitiveContains("art") })
    }
}
