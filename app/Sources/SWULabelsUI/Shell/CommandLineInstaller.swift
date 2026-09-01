#if os(macOS)
import AppKit
import Foundation

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
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/swu-labels")
    }

    static var installCommand: String {
        "sudo ln -sf \"\(bundledToolURL.path(percentEncoded: false))\" /usr/local/bin/swu-labels"
    }

    @MainActor
    static func presentInstructions() {
        let alert = NSAlert()
        alert.messageText = "Install the command line tool"
        alert.informativeText = """
        Run this in Terminal to link swu-labels onto your PATH:

        \(installCommand)

        It is a symlink into this app, so updating the app updates the command.
        """
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(installCommand, forType: .string)
        }
    }
}
#endif
