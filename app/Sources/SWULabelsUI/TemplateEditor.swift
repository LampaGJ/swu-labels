import SwiftUI
import SWULabelsCore

/// Edits the label's lines: their order, and the text of each.
///
/// Array order is the only thing that decides line order, so dragging a row here
/// is the whole mechanism — there is no separate "put stats above" switch to
/// contradict it.
///
/// A template referencing an unknown `{variable}` fails the whole run rather
/// than rendering blank, so the error surfaces here, inline, the moment it is
/// typed. Waiting until print would trade a visible message for a wasted sheet.
struct TemplateEditor: View {
    @Bindable var model: AppModel
    @State private var expandedVariableHelp = false

    var body: some View {
        Section {
            ForEach(Array(model.config.template.enumerated()), id: \.offset) { index, line in
                TemplateLineRow(
                    line: line,
                    error: Self.error(in: line),
                    onChange: { updated in
                        model.config.template[index] = updated
                    }
                )
            }
            .onMove { offsets, destination in
                model.moveTemplateLines(from: offsets, to: destination)
            }

            DisclosureGroup("Available variables", isExpanded: $expandedVariableHelp) {
                FlowLayout(spacing: 4) {
                    ForEach(Self.variableNames, id: \.self) { name in
                        Text("{\(name)}")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
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

    /// The catalog's variable names, sorted for a stable display order.
    ///
    /// Sorted because the catalog is a dictionary: its natural order is
    /// randomized per process, which would shuffle this list between launches.
    static let variableNames: [String] = TemplateEngine.catalogVariableNames.sorted()

    /// Compiles one line and returns the message when it will not compile.
    static func error(in line: LabelLayoutConfig.TemplateLine) -> String? {
        do {
            _ = try TemplateEngine.parse(line)
            return nil
        } catch let error as LabelError {
            return error.description
        } catch {
            return "\(error)"
        }
    }
}

/// One editable template line.
struct TemplateLineRow: View {
    let line: LabelLayoutConfig.TemplateLine
    let error: String?
    let onChange: (LabelLayoutConfig.TemplateLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(line.style)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            TextField(
                "Template",
                text: Binding(
                    get: { line.text },
                    set: { onChange(LabelLayoutConfig.TemplateLine(style: line.style, text: $0)) }
                ),
                axis: .vertical
            )
            .font(.callout.monospaced())
            .textFieldStyle(.roundedBorder)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
