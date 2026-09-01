import SwiftUI

/// The placeholder an empty ordering list shows.
///
/// An empty list with no explanation reads as a broken screen. Saying what the
/// empty state *means* — one continuous run — turns it into information.
struct EmptyDropTarget: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "tray")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
