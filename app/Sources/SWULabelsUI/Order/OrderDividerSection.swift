import SwiftUI
import SWULabelsCore

/// The divider-label option, which only means anything once something orders
/// cards inside a sheet.
struct OrderDividerSection: View {
    @Bindable var model: AppModel

    var body: some View {
        if let key = model.sheetOrder.thenBy.first?.key {
            Section {
                Toggle(isOn: $model.sheetOrder.showsDividers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Divider labels")
                        Text("Opens each run of \(key.displayName.lowercased()) with a labelled divider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
