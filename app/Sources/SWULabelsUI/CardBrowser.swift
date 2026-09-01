import SwiftUI
import SWULabelsCore

/// The card list, in the order it will print.
///
/// This is not a neutral table of the pool — it shows the cards in the exact
/// sequence the current ordering puts them in, section by section. Seeing the
/// printed order before printing is the point; a table sorted some other way
/// would be a second, contradictory answer to "what comes out of the printer".
public struct CardBrowser: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.phase.isLoading {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleCards.isEmpty {
                EmptyBrowserState(hasSearch: !model.searchText.isEmpty) {
                    model.searchText = ""
                }
            } else {
                cardList
            }
        }
        .navigationTitle("Cards")
    }

    private var cardList: some View {
        List(selection: Binding(
            get: { model.previewCard.map(CardID.init) },
            set: { id in
                model.previewCard = model.visibleCards.first { CardID($0) == id }
            }
        )) {
            ForEach(sections, id: \.key) { section in
                Section(section.key) {
                    ForEach(section.cards, id: \.self) { card in
                        CardRow(card: card)
                            .tag(CardID(card))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    /// The visible cards, cut into the same sections the sheet will use.
    ///
    /// Read straight from the model's grouped sections, so the list and the
    /// sheet cannot disagree about where a card falls.
    private var sections: [(key: String, cards: [Card])] {
        let visible = Set(model.visibleCards)
        return model.sections.compactMap { section in
            let cards = section.slots.compactMap { slot -> Card? in
                guard case let .card(card) = slot, visible.contains(card) else { return nil }
                return card
            }
            return cards.isEmpty ? nil : (key: section.key, cards: cards)
        }
    }
}

/// A card's identity in the list, so selection survives a re-sort.
struct CardID: Hashable {
    let title: String
    let subtitle: String
    let set: String

    init(_ card: Card) {
        title = card.title
        subtitle = card.subtitle ?? ""
        set = card.expansionCode
    }
}

/// One row: what the label will say, in list form.
struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if card.unique {
                        Text("\u{25CA}").foregroundStyle(.secondary)
                    }
                    Text(card.title).fontWeight(.medium)
                }
                if let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).italic().foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(statSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(card.expansionCode)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
    }

    private var statSummary: String {
        Transform.statLineSegments(for: card)
            .map { "\($0.value) \($0.suffix.rawValue)" }
            .joined(separator: " · ")
    }
}

/// Shown when the list has nothing in it.
struct EmptyBrowserState: View {
    let hasSearch: Bool
    let clearSearch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasSearch ? "No cards match your search" : "No cards in this selection")
                .font(.headline)
            Text(hasSearch
                ? "Try a different term, or clear the search."
                : "Choose more sets in the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if hasSearch {
                Button("Clear search", action: clearSearch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
