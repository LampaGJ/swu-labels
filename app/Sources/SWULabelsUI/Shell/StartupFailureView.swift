import SwiftUI

/// Shown when the app cannot find its card data at launch.
public struct StartupFailureView: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label("No card data found", systemImage: "questionmark.folder")
        } description: {
            Text(message).textSelection(.enabled)
        }
    }
}
