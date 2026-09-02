import Foundation

/// One card's art, as a proxy sheet needs it.
public struct ProxyCard: Codable, Equatable, Sendable, Identifiable {
    /// Matches ``Card/id``, so a proxy can be traced back to its card.
    public var id: String
    public var title: String
    public var subtitle: String?
    public var expansionCode: String
    /// Absolute URL of the card's front art.
    public var artURL: String
    /// Whether the art is landscape, as Leaders and Bases are.
    ///
    /// It does **not** mean the card slot changes shape. Every slot on a proxy
    /// sheet stays the same portrait rectangle so the whole page can be cut on
    /// one uniform grid; landscape art is rotated into its slot instead. A sheet
    /// mixing portrait and landscape slots could not be cut in straight lines.
    public var isHorizontal: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        expansionCode: String,
        artURL: String,
        isHorizontal: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.expansionCode = expansionCode
        self.artURL = artURL
        self.isHorizontal = isHorizontal
    }
}

/// One position on a proxy sheet.
public enum ProxySlot: Equatable, Sendable {
    case card(ProxyCard)
    /// A grid position with no card. Printed blank and cut away.
    case empty
}

/// One printed page of proxies.
public struct ProxyPage: Equatable, Sendable {
    public var slots: [ProxySlot]

    public init(slots: [ProxySlot]) {
        self.slots = slots
    }

    public var cardCount: Int {
        slots.count { if case .card = $0 { true } else { false } }
    }
}

/// A fully resolved proxy print run.
///
/// The same seam as ``SheetPlan``: this decides *what card is in which position
/// on which page*, and the renderer decides only how to draw it. Keeping the
/// decision here means the layout can be checked without a graphics context, and
/// means a preview cannot disagree with what prints.
public struct ProxyPlan: Equatable, Sendable {
    public var config: ProxySheetConfig
    public var pages: [ProxyPage]

    public init(config: ProxySheetConfig, pages: [ProxyPage]) {
        self.config = config
        self.pages = pages
    }

    public var totalCards: Int {
        pages.reduce(0) { $0 + $1.cardCount }
    }
}

/// Lays a selection of cards out across proxy sheets.
public enum ProxyPlanner {
    /// Builds the plan.
    ///
    /// Copies of one card are emitted consecutively, so a page of a deck's
    /// three-ofs comes off the printer in blocks rather than scattered — which
    /// matters when cutting and sorting a stack by hand.
    ///
    /// - Parameter cards: the selection, already in the order to print.
    public static func plan(
        cards: [ProxyCard],
        config: ProxySheetConfig
    ) -> ProxyPlan {
        let fitted = config.clamped
        let expanded = cards.flatMap { card in
            Array(repeating: card, count: fitted.copiesPerCard)
        }
        let perPage = fitted.cardsPerPage

        guard perPage > 0, !expanded.isEmpty else {
            return ProxyPlan(config: fitted, pages: [])
        }

        let pages = stride(from: 0, to: expanded.count, by: perPage).map { start in
            // Every page carries a full complement of slots, padded with empties.
            // A short final page that simply omitted its trailing slots would
            // leave the renderer to infer the grid, and the cut guides with it.
            let slots = (0..<perPage).map { offset -> ProxySlot in
                let index = start + offset
                return index < expanded.count ? .card(expanded[index]) : .empty
            }
            return ProxyPage(slots: slots)
        }
        return ProxyPlan(config: fitted, pages: pages)
    }
}
