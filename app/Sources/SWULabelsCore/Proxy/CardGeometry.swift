import Foundation

/// Physical dimensions for proxy cards, in millimetres.
///
/// **Exact size is the whole point of a proxy.** A card printed even a
/// millimetre off will not sit in a sleeve with real cards, and one that is
/// visibly different from the rest of a deck is worse than useless — it marks
/// itself from the back. So size here is a correctness property in exactly the
/// way the Avery grid is, and it is gated the same way.
///
/// Millimetres rather than points because that is how card and sleeve stock is
/// specified everywhere; points are computed at the draw site.
public enum CardGeometry {
    /// Standard TCG card size, shared by Star Wars Unlimited, Magic and Pokémon.
    ///
    /// Often quoted as 2.5in × 3.5in, which is 63.5mm × 88.9mm — close, but not
    /// the same card. The metric figures are the real ones; using the rounded
    /// inch values would print every card about half a millimetre oversize.
    public static let widthMillimetres = 63.0
    public static let heightMillimetres = 88.0

    /// Points per millimetre. PostScript points are 1/72in, and an inch is 25.4mm.
    public static let pointsPerMillimetre = 72.0 / 25.4

    public static func points(fromMillimetres millimetres: Double) -> Double {
        millimetres * pointsPerMillimetre
    }

    public static var widthPoints: Double { points(fromMillimetres: widthMillimetres) }
    public static var heightPoints: Double { points(fromMillimetres: heightMillimetres) }

    /// The resolution a card's art actually reaches at print size.
    ///
    /// The official CDN's largest art is 300 × 418 pixels, which over an 88mm
    /// card is about 121 DPI against a 300 DPI print standard. Proxies from it
    /// are perfectly playable and no amount of code changes that — the limit is
    /// the source image. Surfaced rather than hidden so nobody prints a hundred
    /// sheets expecting retail sharpness.
    public static func effectiveDPI(pixelsOnLongEdge: Int) -> Double {
        Double(pixelsOnLongEdge) / (heightMillimetres / 25.4)
    }

    /// Print resolution below which art is noticeably soft.
    public static let softPrintDPIThreshold = 200.0
}

/// A page a proxy sheet can be printed on.
///
/// Both sizes are offered because card games are played internationally and A4
/// is not interchangeable with US Letter: A4 is narrower and taller, so a layout
/// that fits one can overflow the other.
public enum ProxyPageSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case usLetter
    case a4

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .usLetter: "US Letter"
        case .a4: "A4"
        }
    }

    public var widthMillimetres: Double {
        switch self {
        case .usLetter: 215.9
        case .a4: 210.0
        }
    }

    public var heightMillimetres: Double {
        switch self {
        case .usLetter: 279.4
        case .a4: 297.0
        }
    }

    public var widthPoints: Double { CardGeometry.points(fromMillimetres: widthMillimetres) }
    public var heightPoints: Double { CardGeometry.points(fromMillimetres: heightMillimetres) }

    /// The largest whole grid of cards that fits, given a gutter and margin.
    ///
    /// Computed rather than pinned per page size, so a changed gutter cannot
    /// leave a hardcoded column count silently overflowing the paper.
    public func maximumGrid(
        gutterMillimetres: Double,
        marginMillimetres: Double
    ) -> (columns: Int, rows: Int) {
        (
            columns: fitCount(
                available: widthMillimetres - 2 * marginMillimetres,
                item: CardGeometry.widthMillimetres,
                gutter: gutterMillimetres
            ),
            rows: fitCount(
                available: heightMillimetres - 2 * marginMillimetres,
                item: CardGeometry.heightMillimetres,
                gutter: gutterMillimetres
            )
        )
    }

    /// How many items of `item` fit in `available` with `gutter` between them.
    func fitCount(available: Double, item: Double, gutter: Double) -> Int {
        guard available >= item else { return 0 }
        // n items need n*item + (n-1)*gutter. Solving for n and flooring gives
        // the count that fits; the epsilon keeps a value landing exactly on the
        // boundary from being lost to floating-point representation.
        let count = (available + gutter) / (item + gutter)
        return max(1, Int(count + 1e-9))
    }
}
