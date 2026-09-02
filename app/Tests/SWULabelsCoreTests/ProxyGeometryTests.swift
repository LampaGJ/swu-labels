import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import SWULabelsCore
@testable import SWULabelsRender

/// Proxy cards must print at exactly card size.
///
/// This is the proxy equivalent of the Avery grid gate, and it matters for the
/// same reason: a card even a millimetre off will not sit in a sleeve alongside
/// real cards, and a deck containing one card of a different size is marked from
/// the back. Nothing here is asserted against the app's own constants — the
/// dimensions below are the physical card, stated independently.
@Suite
struct ProxyGeometry {
    static let tolerance = 0.01

    /// A standard TCG card, in points, derived from the physical millimetres.
    ///
    /// 63mm x 88mm at 72 points per 25.4mm. Deliberately not
    /// `CardGeometry.widthPoints`: checking the renderer against the same
    /// constant it used would pass whatever that constant said.
    enum RealCard {
        static let widthPoints = 63.0 / 25.4 * 72.0
        static let heightPoints = 88.0 / 25.4 * 72.0
    }

    @Test
    func `a card frame is exactly 63mm by 88mm`() {
        let frame = ProxySheetConfig.default.cardFrame(row: 0, column: 0)
        #expect(abs(frame.width - RealCard.widthPoints) < Self.tolerance)
        #expect(abs(frame.height - RealCard.heightPoints) < Self.tolerance)

        // Restated in inches, because that is how a ruler at hand is marked:
        // 63mm is 2.4803in and 88mm is 3.4646in.
        #expect(abs(frame.width / 72.0 - 2.4803) < 0.001)
        #expect(abs(frame.height / 72.0 - 3.4646) < 0.001)
    }

    /// The commonly quoted "2.5 by 3.5 inches" is a different, larger card.
    @Test
    func `card size is metric, not the rounded inch figure`() {
        let frame = ProxySheetConfig.default.cardFrame(row: 0, column: 0)
        #expect(abs(frame.width - 2.5 * 72) > 1.0, "2.5in would be 63.5mm, half a millimetre oversize")
        #expect(abs(frame.height - 3.5 * 72) > 2.0, "3.5in would be 88.9mm, nearly a millimetre oversize")
    }

    @Test(arguments: ProxyPageSize.allCases)
    func `nine cards fit on a page with room for margins`(page: ProxyPageSize) {
        let grid = page.maximumGrid(gutterMillimetres: 0, marginMillimetres: 6)
        #expect(grid.columns >= 3, "\(page.displayName) should hold three columns")
        #expect(grid.rows >= 3, "\(page.displayName) should hold three rows")
    }

    @Test(arguments: ProxyPageSize.allCases)
    func `the grid never overflows the page`(page: ProxyPageSize) {
        // Asking for far more than fits must clamp, not overflow. An overflowing
        // grid does not fail loudly — it prints a clipped card.
        let config = ProxySheetConfig(pageSize: page, columns: 9, rows: 9).clamped
        for row in 0..<config.rows {
            for column in 0..<config.columns {
                let frame = config.cardFrame(row: row, column: column)
                #expect(frame.x >= -Self.tolerance)
                #expect(frame.y >= -Self.tolerance)
                #expect(frame.x + frame.width <= page.widthPoints + Self.tolerance)
                #expect(frame.y + frame.height <= page.heightPoints + Self.tolerance)
            }
        }
    }

    @Test
    func `cards do not overlap`() {
        let config = ProxySheetConfig.default.clamped
        var frames: [CGRect] = []
        for row in 0..<config.rows {
            for column in 0..<config.columns {
                let frame = config.cardFrame(row: row, column: column)
                frames.append(CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
            }
        }
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                // Shrunk a hair before testing, so abutted cards at a zero
                // gutter touch without counting as an overlap.
                #expect(!frame.insetBy(dx: 0.01, dy: 0.01).intersects(other.insetBy(dx: 0.01, dy: 0.01)))
            }
        }
    }

    @Test
    func `row zero is the top row`() {
        let config = ProxySheetConfig.default.clamped
        let top = config.cardFrame(row: 0, column: 0)
        let below = config.cardFrame(row: 1, column: 0)
        #expect(top.y > below.y, "row 0 should sit higher up the page than row 1")
    }

    @Test
    func `copies are expanded and pages padded to a full grid`() {
        let card = ProxyCard(
            id: "a", title: "A", expansionCode: "JTL",
            artURL: "https://example.invalid/a.png", isHorizontal: false
        )
        var config = ProxySheetConfig.default
        config.copiesPerCard = 4

        let plan = ProxyPlanner.plan(cards: [card], config: config)
        #expect(plan.totalCards == 4)
        #expect(plan.pages.count == 1)
        // Nine slots on a 3x3 sheet, four of them cards: the rest are explicit
        // empties so the cut grid stays uniform on a part-filled page.
        #expect(plan.pages[0].slots.count == 9)
        #expect(plan.pages[0].cardCount == 4)
    }

    @Test
    func `a full run paginates without losing a card`() {
        let cards = (0..<20).map { index in
            ProxyCard(
                id: "\(index)", title: "Card \(index)", expansionCode: "JTL",
                artURL: "https://example.invalid/\(index).png", isHorizontal: false
            )
        }
        var config = ProxySheetConfig.default
        config.copiesPerCard = 3

        let plan = ProxyPlanner.plan(cards: cards, config: config)
        #expect(plan.totalCards == 60)
        #expect(plan.pages.count == 7, "60 cards at 9 per sheet needs 7 sheets")
    }

    @Test
    func `the rendered PDF pages are the requested paper size`() throws {
        let card = ProxyCard(
            id: "a", title: "A", expansionCode: "JTL",
            artURL: "https://example.invalid/a.png", isHorizontal: false
        )
        for page in ProxyPageSize.allCases {
            var config = ProxySheetConfig.default
            config.pageSize = page
            let plan = ProxyPlanner.plan(cards: [card], config: config)
            // Rendered with no images at all, which also exercises the
            // missing-art path: a proxy run must still produce a page rather
            // than failing outright when one image could not be fetched.
            let data = try ProxyRenderer(plan: plan, images: [:]).renderPDF()
            let document = try #require(PDFDocument(data: data))
            #expect(document.pageCount == 1)
            let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
            #expect(abs(box.width - page.widthPoints) < Self.tolerance)
            #expect(abs(box.height - page.heightPoints) < Self.tolerance)
        }
    }

    @Test
    func `print resolution is reported honestly`() {
        // The official CDN's largest art is 300 x 418. Over an 88mm card that is
        // about 121 DPI, well under the 300 DPI print standard — a real limit of
        // the source images that the interface must not paper over.
        let dpi = CardGeometry.effectiveDPI(pixelsOnLongEdge: 418)
        #expect(dpi > 118 && dpi < 124, "expected about 121 DPI, got \(dpi)")
        #expect(dpi < CardGeometry.softPrintDPIThreshold)
    }
}
