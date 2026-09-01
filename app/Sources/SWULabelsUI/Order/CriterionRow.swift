import SwiftUI
import SWULabelsCore

/// One characteristic in an ordered list, with its direction and menu actions.
struct CriterionRow: View {
    @Bindable var model: AppModel
    let criterion: SortCriterion
    let role: OrderByEditorRole

    /// Grouping by a characteristic with many distinct values starts a great
    /// many sheets. Warned about rather than forbidden, because a deliberate
    /// one-sheet-per-cost run is a legitimate thing to want.
    private var isQuestionable: Bool {
        role == .grouping && !criterion.key.isReasonableToGroupBy
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(criterion.key.displayName, systemImage: criterion.key.symbolName)

            if isQuestionable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Warning: this has many distinct values, so grouping by it starts a great many sheets.")
            }

            Spacer()

            // Carries its text label for VoiceOver even though it reads as an
            // icon; an icon-only button here would be unreachable by name.
            Button(
                criterion.direction.displayName,
                systemImage: criterion.direction.symbolName,
                action: toggleDirection
            )
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .contextMenu {
            Button(oppositeDirectionTitle, action: toggleDirection)
            Button(role.moveAcrossTitle, action: moveAcross)
            Divider()
            Button("Remove", role: .destructive, action: remove)
        }
    }

    private var oppositeDirectionTitle: String {
        criterion.direction == .ascending ? "Sort descending" : "Sort ascending"
    }

    private func toggleDirection() {
        model.toggleDirection(of: criterion.key)
    }

    private func moveAcross() {
        model.place(criterion.key, into: role.opposite)
    }

    private func remove() {
        model.remove(criterion.key)
    }
}
