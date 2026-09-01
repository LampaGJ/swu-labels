import SwiftUI
import SWULabelsCore

/// Edits the label's lines: their order, and the text of each.
///
/// Array order is the only thing that decides line order, so dragging a row here
/// is the whole mechanism — there is no separate "put stats above" switch to
/// contradict it.
struct TemplateEditor: View {
    @Bindable var model: AppModel
    @State private var isShowingVariables = false

    var body: some View {
        Section {
            // Indexed rather than identified: `TemplateLine` has no stable id
            // of its own, and deriving one from its text would change identity
            // on every keystroke and drop the field's focus mid-edit.
            ForEach(model.config.template.indices, id: \.self) { index in
                TemplateLineRow(line: $model.config.template[index])
            }
            .onMove(perform: model.moveTemplateLines)

            DisclosureGroup("Available variables", isExpanded: $isShowingVariables) {
                FlowLayout(spacing: 4) {
                    ForEach(TemplateEngine.catalogVariableNames.sorted(), id: \.self) { name in
                        Text(verbatim: "{\(name)}")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: .rect(cornerRadius: 4))
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
            .font(.callout)
        } header: {
            Text("Label lines")
        } footer: {
            Text("Drag to reorder. A line whose variables are all empty is left off the label entirely.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
