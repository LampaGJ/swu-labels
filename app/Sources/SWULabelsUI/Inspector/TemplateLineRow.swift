import SwiftUI
import SWULabelsCore

/// One editable template line, with its compile error shown inline.
///
/// A template naming an unknown `{variable}` fails the whole run rather than
/// rendering blank, so the error belongs here, the moment it is typed. Waiting
/// until print would trade a visible message for a wasted sheet.
struct TemplateLineRow: View {
    @Binding var line: LabelLayoutConfig.TemplateLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(line.style, systemImage: "line.3.horizontal")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            TextField("Template", text: $line.text, axis: .vertical)
                .font(.callout.monospaced())
                .textFieldStyle(.roundedBorder)

            if let error = compileError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var compileError: String? {
        do {
            _ = try TemplateEngine.parse(line)
            return nil
        } catch let error as LabelError {
            return error.description
        } catch {
            return error.localizedDescription
        }
    }
}
