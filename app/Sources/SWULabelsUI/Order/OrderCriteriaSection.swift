import SwiftUI
import SWULabelsCore

/// One of the two ordered criterion lists.
struct OrderCriteriaSection: View {
    @Bindable var model: AppModel
    let role: OrderByEditorRole

    private var criteria: [SortCriterion] {
        switch role {
        case .grouping: model.sheetOrder.groupBy
        case .ordering: model.sheetOrder.thenBy
        }
    }

    private var title: String {
        switch role {
        case .grouping: "Group into sheets by"
        case .ordering: "Then order by"
        }
    }

    private var footnote: String {
        switch role {
        case .grouping: "Each distinct value starts a fresh sheet."
        case .ordering: "Arranges the cards within each sheet."
        }
    }

    var body: some View {
        Section {
            if criteria.isEmpty {
                EmptyDropTarget(title: role.emptyStateTitle)
            } else {
                ForEach(criteria) { criterion in
                    CriterionRow(model: model, criterion: criterion, role: role)
                        .draggable(criterion.key.rawValue)
                }
                .onMove { offsets, destination in
                    model.moveCriteria(in: role, from: offsets, to: destination)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let key = SortKey(rawValue: raw) else { return false }
            model.place(key, into: role)
            return true
        }
    }
}
