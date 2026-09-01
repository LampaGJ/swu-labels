import SwiftUI
import SWULabelsCore

/// The characteristics not yet in use, to drag or choose from.
struct OrderPaletteSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let unused = model.sheetOrder.unusedKeys
        if !unused.isEmpty {
            Section {
                // A wrapping flow rather than another list: these are an
                // inventory to pull from, not an ordered sequence, and rows
                // would imply an order they do not have.
                FlowLayout(spacing: 6) {
                    ForEach(unused) { key in
                        Menu {
                            Button("Group into sheets by \(key.displayName)") {
                                model.place(key, into: .grouping)
                            }
                            Button("Order by \(key.displayName)") {
                                model.place(key, into: .ordering)
                            }
                        } label: {
                            CharacteristicChip(key: key)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .draggable(key.rawValue)
                        .accessibilityLabel("Add \(key.displayName) to the sheet order")
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Available characteristics")
            } footer: {
                Text("Drag one into a list above, or click it to choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
