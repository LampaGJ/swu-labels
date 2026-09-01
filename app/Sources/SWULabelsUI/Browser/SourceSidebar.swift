import SwiftUI
import SWULabelsCore

/// Where the cards come from: which pinned snapshot, which pool, which sets.
///
/// Deliberately short. The sidebar answers "what am I printing from", and
/// everything about *how* it prints lives in the inspector — splitting them
/// keeps either from becoming a wall of controls.
public struct SourceSidebar: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                Picker("Snapshot", selection: $model.snapshotTag) {
                    ForEach(model.availableSnapshots, id: \.self) { tag in
                        // A snapshot that cannot satisfy the current pool is
                        // marked rather than hidden. Hiding it would leave the
                        // list mysteriously short; marking it says why picking
                        // it would fail.
                        Text(model.snapshotSupportsCurrentPool(tag) ? tag : "\(tag) — incomplete")
                            .tag(tag)
                    }
                }
                .disabled(model.availableSnapshots.count < 2)

                Picker("Card pool", selection: $model.poolKind) {
                    ForEach(AppModel.PoolKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                LabeledContent("Cards") {
                    Text(model.pool?.kept.count ?? 0, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Source")
            } footer: {
                Text(model.poolKind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.availableSets.isEmpty {
                    Text("No sets loaded").foregroundStyle(.secondary)
                } else {
                    ForEach(model.availableSets, id: \.self) { code in
                        SetRow(
                            code: code,
                            isIncluded: model.isSetIncluded(code),
                            toggle: { model.toggleSet(code) }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Sets")
                    Spacer()
                    if !model.selectedSets.isEmpty {
                        Button("All") { model.selectedSets = [] }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            } footer: {
                // States what "nothing selected" means, because an empty
                // selection normally means "nothing" and here means "everything".
                Text(model.setSelectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Source")
    }
}
