import SwiftUI

/// Shown when the pipeline refuses to build a sheet.
///
/// The pipeline fails loudly by design — a missing set, or a card that would be
/// dropped, stops the run rather than printing a plausible but incomplete sheet.
/// So the interface shows the reason instead of an empty grid.
struct PipelineFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("This sheet cannot be built", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).textSelection(.enabled)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding()
    }
}
