import SwiftUI
import SWULabelsUI

/// The macOS app shell.
///
/// Deliberately tiny, and deliberately free of any platform fork. The whole
/// interface lives in `SWULabelsUI`, a library, so an iPad or iPhone app is a
/// second file of about this size wrapping the same `RootView` — not a fork of
/// the interface.
///
/// The four `#if os(macOS)` blocks in the whole codebase all sit in
/// `SWULabelsUI`: two in `PrintService` (NSPrintOperation versus
/// UIPrintInteractionController) and two around the "Install Command Line Tool"
/// menu item, which has no meaning off the Mac.
@main
struct SWULabelsApp: App {
    @State private var model: AppModel?
    @State private var startupFailure: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else if let startupFailure {
                    StartupFailureView(message: startupFailure)
                } else {
                    ProgressView().task { start() }
                }
            }
            .frame(minWidth: 980, minHeight: 620)
        }
        .commands { AppCommands() }
    }

    @MainActor
    private func start() {
        do {
            model = AppModel(contentRoot: try AppContentLocator.resolve())
        } catch {
            startupFailure = "\(error)"
        }
    }
}
