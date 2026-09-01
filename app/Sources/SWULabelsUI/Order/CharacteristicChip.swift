import SwiftUI
import SWULabelsCore

/// A draggable characteristic in the palette.
struct CharacteristicChip: View {
    let key: SortKey

    var body: some View {
        Label(key.displayName, systemImage: key.symbolName)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
    }
}
