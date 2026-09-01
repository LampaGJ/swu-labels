import SwiftUI
import SWULabelsCore

/// One row: what the label will say, in list form.
struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if card.unique {
                        Text(verbatim: "\u{25CA}")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Unique")
                    }
                    Text(card.title).bold()
                }
                if let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
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
            .joined(separator: " \u{00B7} ")
    }
}
