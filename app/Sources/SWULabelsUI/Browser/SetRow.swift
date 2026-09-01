import SwiftUI
import SWULabelsCore

/// One set code with its full name and an inclusion toggle.
struct SetRow: View {
    let code: String
    let isIncluded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isIncluded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(code).font(.callout.monospaced())
                    if let name = SetCatalog.fullNames[code] {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SetCatalog.fullNames[code] ?? code)
        .accessibilityValue(isIncluded ? "Included" : "Excluded")
        .accessibilityAddTraits(isIncluded ? [.isButton, .isSelected] : .isButton)
    }
}
