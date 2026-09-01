import SwiftUI

/// The preview area above the layout knobs.
struct LabelPreviewPanel: View {
    let model: AppModel

    var body: some View {
        Group {
            if let card = model.previewCard, let icons = model.icons {
                VStack(spacing: 8) {
                    LabelPreviewView(card: card, config: model.config, icons: icons)
                    Text("Actual size 1.75\u{2033} \u{00D7} 0.5\u{2033}, shown at 4\u{00D7}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No card selected",
                    systemImage: "tag",
                    description: Text("Choose a card to preview its label.")
                )
                .frame(height: 140)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.4))
    }
}
