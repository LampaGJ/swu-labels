import SwiftUI
import SWULabelsCore

/// Builds a sheet's ordering by dragging characteristics into place.
///
/// Two ordered lists and a palette. What lands in **Group into sheets** decides
/// where a fresh sheet starts; what lands in **Then order by** arranges cards
/// inside a sheet. That distinction is the one thing a person has to understand
/// here, so it is stated in the interface rather than left to be inferred from
/// the result.
///
/// Every drag has a keyboard-and-menu equivalent. Drag-and-drop alone would put
/// the app's central control out of reach of anyone not using a pointer, and
/// reordering is the whole point of this screen.
public struct OrderByEditor: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var order: SheetOrder { model.sheetOrder }

    public var body: some View {
        List {
            presetSection
            criteriaSection(
                title: "Group into sheets by",
                footnote: "Each distinct value starts a fresh sheet.",
                criteria: order.groupBy,
                role: .grouping
            )
            criteriaSection(
                title: "Then order by",
                footnote: "Arranges the cards within each sheet.",
                criteria: order.thenBy,
                role: .ordering
            )
            paletteSection
            if order.dividerKey != nil || !order.thenBy.isEmpty {
                dividerSection
            }
        }
        .animation(.snappy(duration: 0.2), value: order)
    }

    // MARK: - Presets

    private var presetSection: some View {
        Section {
            Menu {
                ForEach(LayoutMode.allCases, id: \.self) { mode in
                    Button {
                        model.apply(preset: mode)
                    } label: {
                        Text(mode.displayName)
                    }
                }
            } label: {
                HStack {
                    Text("Preset")
                    Spacer()
                    Text(model.matchingPreset?.displayName ?? "Custom")
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Card pool", selection: $model.poolKind) {
                ForEach(AppModel.PoolKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .help(model.poolKind.summary)
        }
    }

    // MARK: - Criteria lists

    @ViewBuilder
    private func criteriaSection(
        title: String,
        footnote: String,
        criteria: [SortCriterion],
        role: OrderByEditorRole
    ) -> some View {
        Section {
            if criteria.isEmpty {
                EmptyDropTarget(title: role == .grouping
                    ? "No grouping — one continuous run"
                    : "No ordering — cards keep pool order")
            } else {
                ForEach(criteria) { criterion in
                    CriterionRow(
                        criterion: criterion,
                        role: role,
                        isQuestionable: role == .grouping && !criterion.key.isReasonableToGroupBy,
                        onToggleDirection: { toggleDirection(criterion.key) },
                        onMoveAcross: { moveAcross(criterion.key, from: role) },
                        onRemove: { remove(criterion.key) }
                    )
                    .draggable(criterion.key.rawValue)
                }
                .onMove { offsets, destination in
                    move(in: role, from: offsets, to: destination)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footnote).font(.caption).foregroundStyle(.secondary)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let key = SortKey(rawValue: raw) else { return false }
            place(key, into: role)
            return true
        }
    }

    // MARK: - Palette

    @ViewBuilder
    private var paletteSection: some View {
        let unused = order.unusedKeys
        if !unused.isEmpty {
            Section {
                // A wrapping flow of chips rather than another list: these are
                // an inventory to pull from, not an ordered sequence, and
                // showing them as rows would imply an order they do not have.
                FlowLayout(spacing: 6) {
                    ForEach(unused) { key in
                        Menu {
                            Button("Group into sheets by \(key.displayName)") {
                                place(key, into: .grouping)
                            }
                            Button("Order by \(key.displayName)") {
                                place(key, into: .ordering)
                            }
                        } label: {
                            CharacteristicChip(key: key)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .draggable(key.rawValue)
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

    private var dividerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.sheetOrder.showsDividers },
                set: { model.sheetOrder.showsDividers = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Divider labels")
                    if let key = order.thenBy.first?.key {
                        Text("Opens each run of \(key.displayName.lowercased()) with a labelled divider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(order.thenBy.isEmpty)
        }
    }

    // MARK: - Mutations

    private func place(_ key: SortKey, into role: OrderByEditorRole) {
        var next = order
        next.groupBy.removeAll { $0.key == key }
        next.thenBy.removeAll { $0.key == key }
        switch role {
        case .grouping: next.groupBy.append(SortCriterion(key: key))
        case .ordering: next.thenBy.append(SortCriterion(key: key))
        }
        model.sheetOrder = next
    }

    private func remove(_ key: SortKey) {
        var next = order
        next.groupBy.removeAll { $0.key == key }
        next.thenBy.removeAll { $0.key == key }
        model.sheetOrder = next
    }

    private func moveAcross(_ key: SortKey, from role: OrderByEditorRole) {
        place(key, into: role == .grouping ? .ordering : .grouping)
    }

    private func toggleDirection(_ key: SortKey) {
        var next = order
        for index in next.groupBy.indices where next.groupBy[index].key == key {
            next.groupBy[index].direction =
                next.groupBy[index].direction == .ascending ? .descending : .ascending
        }
        for index in next.thenBy.indices where next.thenBy[index].key == key {
            next.thenBy[index].direction =
                next.thenBy[index].direction == .ascending ? .descending : .ascending
        }
        model.sheetOrder = next
    }

    private func move(in role: OrderByEditorRole, from offsets: IndexSet, to destination: Int) {
        var next = order
        switch role {
        case .grouping: next.groupBy.move(fromOffsets: offsets, toOffset: destination)
        case .ordering: next.thenBy.move(fromOffsets: offsets, toOffset: destination)
        }
        model.sheetOrder = next
    }
}

/// One characteristic in an ordered list.
struct CriterionRow: View {
    let criterion: SortCriterion
    let role: OrderByEditorRole
    let isQuestionable: Bool
    let onToggleDirection: () -> Void
    let onMoveAcross: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: criterion.key.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(criterion.key.displayName)

            if isQuestionable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This has many distinct values, so grouping by it starts a great many sheets.")
            }

            Spacer()

            Button(action: onToggleDirection) {
                Image(systemName: criterion.direction.symbolName)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(criterion.direction.displayName)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(criterion.direction == .ascending ? "Sort descending" : "Sort ascending",
                   action: onToggleDirection)
            Button(role == .grouping ? "Move to ordering" : "Move to grouping",
                   action: onMoveAcross)
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}

/// Mirrors ``OrderByEditor``'s private role, so ``CriterionRow`` can name it.
enum OrderByEditorRole {
    case grouping
    case ordering
}

/// A draggable characteristic in the palette.
struct CharacteristicChip: View {
    let key: SortKey

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: key.symbolName)
            Text(key.displayName)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

/// The placeholder an empty ordering list shows.
///
/// An empty list with no explanation reads as a broken screen. Saying what the
/// empty state *means* — one continuous run — turns it into information.
struct EmptyDropTarget: View {
    let title: String

    var body: some View {
        HStack {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// Lays chips out in wrapping rows.
///
/// SwiftUI has no built-in wrapping stack, and a `LazyVGrid` with fixed columns
/// would either clip the longer names or leave ragged gaps beside the short
/// ones. `Layout` measures each chip and breaks the line when the next one no
/// longer fits.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, availableWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in layout(subviews: subviews, availableWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if projected > availableWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
