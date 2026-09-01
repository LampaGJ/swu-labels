import SwiftUI
import SWULabelsCore

/// The card list, in the order it will print.
///
/// Not a neutral table of the pool: it shows cards in the exact sequence the
/// current ordering puts them in, section by section. Seeing the printed order
/// before printing is the point, and a table sorted some other way would be a
/// second, contradictory answer to "what comes out of the printer".
public struct CardBrowser: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.phase.isLoading {
                ProgressView("Loading cards\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleCards.isEmpty {
                emptyState
            } else {
                List(selection: $model.selectedCardID) {
                    ForEach(model.visibleSections) { section in
                        Section(section.key) {
                            ForEach(section.cards) { card in
                                CardRow(card: card)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Cards")
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.searchText.isEmpty {
            ContentUnavailableView(
                "No cards in this selection",
                systemImage: "tray",
                description: Text("Choose more sets in the sidebar.")
            )
        } else {
            // Carries the search term automatically, which is why this is the
            // built-in rather than a hand-written empty state.
            ContentUnavailableView.search
        }
    }
}
