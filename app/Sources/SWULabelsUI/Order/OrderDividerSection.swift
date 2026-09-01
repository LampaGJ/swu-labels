import SwiftUI
import SWULabelsCore

/// The divider-label option.
///
/// Always shown, and disabled with a reason when it cannot apply. Hiding a
/// control that does not currently apply makes it unfindable — someone looking
/// for divider labels would have to first guess that adding a sort
/// characteristic is what reveals the switch.
struct OrderDividerSection: View {
    @Bindable var model: AppModel

    /// The characteristic whose runs a divider would open.
    private var runKey: SortKey? {
        model.sheetOrder.thenBy.first?.key
    }

    var body: some View {
        Section {
            Toggle(isOn: $model.sheetOrder.showsDividers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Print divider labels")
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(runKey == nil)

            if model.sheetOrder.showsDividers, runKey != nil {
                LabeledContent("Example") {
                    DividerLabelPreview(lines: exampleLines)
                }
            }
        } header: {
            Text("Dividers")
        }
    }

    private var explanation: String {
        guard let runKey else {
            return "Add something to \u{201C}Then order by\u{201D} first \u{2014} a divider marks where one run ends and the next begins."
        }
        return "Opens each run of \(runKey.displayName.lowercased()) with a label naming the set, so a printed stack can be flipped straight to it."
    }

    /// A real divider from the current plan, or a representative one.
    ///
    /// Taken from the plan rather than invented, so the example cannot promise
    /// something the sheet will not print.
    private var exampleLines: [String] {
        for section in model.sections {
            for slot in section.slots {
                if case let .divider(lines) = slot { return lines.ordered }
            }
        }
        return ["SET", "Set name", "(group) 0/0 cards"]
    }
}
