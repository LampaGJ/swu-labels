import SwiftUI

/// Menu-bar commands and their shortcuts.
///
/// Every action the toolbar offers also has a menu item, because a
/// toolbar-only control is unreachable by keyboard and this app's primary
/// action is printing.
///
/// `Commands` exists on every platform; an iOS build simply renders nothing for
/// it, so this file needs no platform fork of its own.
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
            Button("Install Command Line Tool\u{2026}", action: CommandLineInstaller.presentInstructions)
                .help("Links swu-labels into /usr/local/bin, pointing at this app.")
        }
        #endif
    }
}
