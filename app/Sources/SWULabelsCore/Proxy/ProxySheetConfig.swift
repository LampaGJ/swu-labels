import Foundation

/// Every knob on a proxy sheet.
///
/// Card size is deliberately absent: it is fixed by ``CardGeometry`` and is not
/// a preference. Everything here is a genuine choice about the sheet the cards
/// are printed on, not about the cards themselves.
public struct ProxySheetConfig: Codable, Equatable, Sendable {
    /// How cutting guides are drawn.
    public enum CutGuides: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Nothing. Cleanest, and correct when cutting on a guillotine with a
        /// measured stop rather than by following a line.
        case none
        /// Short marks in the page margins, level with each card edge.
        ///
        /// The default, because they mark every cut line without printing ink
        /// anywhere on a card. A crop mark inside the card face shows on the
        /// finished proxy; one in the margin is thrown away with the offcut.
        case cropMarks
        /// A thin outline around each card.
        ///
        /// Easiest to follow by hand, at the cost of a hairline on the card's
        /// own edge — usually hidden once sleeved.
        case outline

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .none: "None"
            case .cropMarks: "Crop marks"
            case .outline: "Card outlines"
            }
        }
    }

    public var pageSize: ProxyPageSize
    /// Cards per row and per column. Clamped to what the paper actually fits.
    public var columns: Int
    public var rows: Int
    /// Space between adjacent cards, in millimetres.
    ///
    /// Zero abuts the cards, so one cut separates two of them — fastest, and it
    /// fits the most per sheet. A small gutter tolerates a slightly crooked cut
    /// at the cost of twice the cutting.
    public var gutterMillimetres: Double
    /// Minimum clear space at the page edge, in millimetres.
    ///
    /// Not decoration: most printers cannot image the outer few millimetres of a
    /// page at all, and a card placed there is silently clipped.
    public var marginMillimetres: Double
    public var cutGuides: CutGuides
    /// Copies of every selected card.
    public var copiesPerCard: Int

    public init(
        pageSize: ProxyPageSize = .usLetter,
        columns: Int = 3,
        rows: Int = 3,
        gutterMillimetres: Double = 0,
        marginMillimetres: Double = 6,
        cutGuides: CutGuides = .cropMarks,
        copiesPerCard: Int = 1
    ) {
        self.pageSize = pageSize
        self.columns = columns
        self.rows = rows
        self.gutterMillimetres = gutterMillimetres
        self.marginMillimetres = marginMillimetres
        self.cutGuides = cutGuides
        self.copiesPerCard = copiesPerCard
    }

    /// The shipped default: nine cards on US Letter, abutted, with crop marks.
    public static let `default` = ProxySheetConfig()

    /// The grid this page size can actually hold at the current spacing.
    public var maximumGrid: (columns: Int, rows: Int) {
        pageSize.maximumGrid(
            gutterMillimetres: gutterMillimetres,
            marginMillimetres: marginMillimetres
        )
    }

    /// The config with its grid clamped to what fits.
    ///
    /// Clamping rather than throwing: asking for four columns on A4 is a
    /// reasonable thing to try, and silently printing a clipped card is the only
    /// unacceptable outcome. The interface reports the clamp so the request is
    /// not quietly ignored.
    public var clamped: ProxySheetConfig {
        var result = self
        let limit = maximumGrid
        result.columns = min(max(1, columns), max(1, limit.columns))
        result.rows = min(max(1, rows), max(1, limit.rows))
        result.copiesPerCard = max(1, copiesPerCard)
        return result
    }

    /// Whether the requested grid had to be reduced to fit.
    public var isGridClamped: Bool {
        let fitted = clamped
        return fitted.columns != columns || fitted.rows != rows
    }

    public var cardsPerPage: Int {
        let fitted = clamped
        return fitted.columns * fitted.rows
    }

    /// The rectangle, in points from the page's bottom-left, that one grid
    /// position occupies.
    ///
    /// The grid is centred on the page rather than pinned to the top-left
    /// margin. Centring splits any leftover space evenly, which keeps the outer
    /// cards away from the unprintable edge on both sides instead of crowding
    /// one of them.
    public func cardFrame(row: Int, column: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        let fitted = clamped
        let cardWidth = CardGeometry.widthPoints
        let cardHeight = CardGeometry.heightPoints
        let gutter = CardGeometry.points(fromMillimetres: fitted.gutterMillimetres)

        let gridWidth = Double(fitted.columns) * cardWidth + Double(fitted.columns - 1) * gutter
        let gridHeight = Double(fitted.rows) * cardHeight + Double(fitted.rows - 1) * gutter
        let originX = (fitted.pageSize.widthPoints - gridWidth) / 2
        let originY = (fitted.pageSize.heightPoints - gridHeight) / 2

        return (
            x: originX + Double(column) * (cardWidth + gutter),
            // Row 0 is the top row, so it sits at the far end of the page's
            // upward-growing y axis.
            y: originY + Double(fitted.rows - 1 - row) * (cardHeight + gutter),
            width: cardWidth,
            height: cardHeight
        )
    }
}
