import SwiftUI

/// Menu-bar commands and their shortcuts.
///
/// Every action the toolbar offers also has a keyboard shortcut and a menu item.
/// A toolbar-only control is unreachable by keyboard, and this app's primary
/// action — printing a sheet — should never require a pointer.
///
/// `Commands` is a SwiftUI API on every platform; the iOS build simply renders
/// nothing for it, so the file needs no platform fork.
public struct AppCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            Link(
                "Avery 5167 printing guidance",
                destination: URL(string: "https://www.avery.com/templates/5167")!
            )
        }

        #if os(macOS)
        CommandGroup(after: .appSettings) {
            Button("Install Command Line Tool…") {
                CommandLineInstaller.presentInstructions()
            }
            .help("Adds swu-labels to /usr/local/bin, linked to this app.")
        }
        #endif
    }
}

#if os(macOS)
import AppKit

/// Explains how to link the bundled command-line tool onto `PATH`.
///
/// The app shows the command rather than running it. Writing into
/// `/usr/local/bin` needs privileges the app does not have and should not ask
/// for, and a tool that silently escalates to modify a system directory is a
/// worse trade than one that tells you the single line to run.
enum CommandLineInstaller {
    /// The bundled CLI, which ships beside the app executable so one signature
    /// and one notarization ticket cover both.
    static var bundledToolURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/swu-labels")
    }

    @MainActor
    static func presentInstructions() {
        let command = "sudo ln -sf \"\(bundledToolURL.path)\" /usr/local/bin/swu-labels"

        let alert = NSAlert()
        alert.messageText = "Install the command line tool"
        alert.informativeText = """
        Run this in Terminal to link swu-labels onto your PATH:

        \(command)

        It is a symlink into this app, so updating the app updates the command.
        """
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}
#endif

/// Shown when the app cannot find its card data at launch.
public struct StartupFailureView: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No card data found")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: 520)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
