import SwiftUI

/// Shows a divider label's three lines the way they print.
struct DividerLabelPreview: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Indexed rather than identified: these are three positional lines
            // of one label, not a collection of things with identities, and
            // `enumerated()` would need an array conversion to be iterated here.
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(.caption)
                    .bold(index == 0)
                    .italic(index == 1)
                    .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
