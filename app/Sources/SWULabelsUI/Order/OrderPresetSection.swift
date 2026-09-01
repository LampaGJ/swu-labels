import SwiftUI
import SWULabelsCore

/// Shipped layouts and the card pool they read from.
struct OrderPresetSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Picker("Preset", selection: presetSelection) {
                Text("Custom").tag(LayoutMode?.none)
                ForEach(LayoutMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(LayoutMode?.some(mode))
                }
            }

            Picker("Card pool", selection: $model.poolKind) {
                ForEach(AppModel.PoolKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
        } footer: {
            Text(model.poolKind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Selecting a preset applies it; "Custom" is a readout, not a command, so
    /// choosing it leaves the current order alone rather than resetting it.
    private var presetSelection: Binding<LayoutMode?> {
        Binding(
            get: { model.matchingPreset },
            set: { mode in
                if let mode { model.apply(preset: mode) }
            }
        )
    }
}
