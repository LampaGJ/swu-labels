import SwiftUI
import SWULabelsCore

/// Where the cards come from: which pinned snapshot, and which sets within it.
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
                        // list mysteriously short; marking it explains why
                        // choosing it would fail.
                        Text(model.snapshotSupportsCurrentPool(tag) ? tag : "\(tag) — incomplete")
                            .tag(tag)
                    }
                }
                .labelsHidden()
                .disabled(model.availableSnapshots.count < 2)

                Picker("Card pool", selection: $model.poolKind) {
                    ForEach(AppModel.PoolKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                LabeledContent("Cards") {
                    Text("\(model.pool?.kept.count ?? 0)")
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
                    Text("No sets loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.availableSets, id: \.self) { code in
                        SetRow(
                            code: code,
                            isOn: model.selectedSets.isEmpty || model.selectedSets.contains(code),
                            isNarrowed: !model.selectedSets.isEmpty
                        ) {
                            toggle(code)
                        }
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
                // States what "nothing selected" means, because an all-unchecked
                // list normally means "nothing", and here it means "everything".
                Text(model.selectedSets.isEmpty
                    ? "Every set in the pool is included."
                    : "\(model.selectedSets.count) of \(model.availableSets.count) sets included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cards")
    }

    private func toggle(_ code: String) {
        var next = model.selectedSets
        // An empty selection means "everything", so the first click has to
        // become "everything except this one" rather than "only this one",
        // which is what a naive insert would do.
        if next.isEmpty {
            next = Set(model.availableSets)
        }
        if next.contains(code) {
            next.remove(code)
        } else {
            next.insert(code)
        }
        model.selectedSets = next.count == model.availableSets.count ? [] : next
    }
}

/// One set code with its full name and an inclusion toggle.
struct SetRow: View {
    let code: String
    let isOn: Bool
    let isNarrowed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(code).font(.callout.monospaced())
                    if let name = SetCatalog.fullNames[code] {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
