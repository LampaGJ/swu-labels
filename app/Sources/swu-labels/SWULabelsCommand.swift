import ArgumentParser
import Foundation
import SWULabelsCore
import SWULabelsRender

/// The command-line face of the label generator.
///
/// Ships inside `SWULabels.app/Contents/MacOS/`, so one code signature and one
/// notarization ticket cover both this and the GUI. `install-cli` symlinks it
/// onto `PATH` rather than copying it, which keeps the two in step: updating the
/// app updates the command.
@main
struct SWULabelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swu-labels",
        abstract: "Generate printable Star Wars Unlimited card labels for Avery 5167 sheets.",
        version: "0.1.0",
        subcommands: [Generate.self, Plan.self, Snapshots.self, InstallCLI.self],
        defaultSubcommand: Generate.self
    )
}

/// Flags every content-reading subcommand shares.
struct ContentOptions: ParsableArguments {
    @Option(
        name: .customLong("snapshot"),
        help: "Pinned snapshot tag to read, e.g. v2026-08-23."
    )
    var snapshot: String = "v2026-08-23"

    @Option(
        name: .customLong("groups"),
        help: "Layout: aspect-set, set, aspect, alphabetical, rotation-aspect-set, or all."
    )
    var groups: String = LayoutMode.aspectSet.rawValue

    @Option(name: .customLong("assets"), help: "Rarity icon set: color or bw.")
    var assets: AssetsMode = .color

    @Option(
        name: .customLong("sets"),
        help: "Restrict to a comma-separated list of set codes, e.g. SOR,SHD,TWI."
    )
    var sets: String?

    @Option(
        name: .customLong("content-root"),
        help: "Directory holding assets/ and data/. Resolved automatically when omitted."
    )
    var contentRoot: String?

    /// The requested layouts, or all five.
    func layoutModes() throws -> [LayoutMode] {
        if groups == "all" { return LayoutMode.allCases }
        return try groups.split(separator: ",").map { token in
            let name = token.trimmingCharacters(in: .whitespaces)
            guard let mode = LayoutMode(rawValue: name) else {
                throw ValidationError(
                    "unrecognized --groups value \"\(name)\". Expected one of "
                        + LayoutMode.allCases.map(\.rawValue).joined(separator: ", ")
                        + ", or \"all\"."
                )
            }
            return mode
        }
    }

    var setsFilter: [String]? {
        sets.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    func resolvedContentRoot() throws -> URL {
        try ContentLocator.resolve(override: contentRoot)
    }
}

extension AssetsMode: ExpressibleByArgument {}

/// Renders sheets to PDF.
struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Render label sheets to PDF at exactly 1:1 scale."
    )

    @OptionGroup var content: ContentOptions

    @Option(name: .customLong("out"), help: "Output directory. Defaults to ./reports.")
    var outputDirectory: String?

    func run() async throws {
        let root = try content.resolvedContentRoot()
        let icons = try IconStore(
            assetsRoot: root.appendingPathComponent("assets", isDirectory: true),
            mode: content.assets
        )
        let reports = URL(
            fileURLWithPath: outputDirectory ?? root.appendingPathComponent("reports").path
        )
        try FileManager.default.createDirectory(
            at: reports, withIntermediateDirectories: true
        )

        for mode in try content.layoutModes() {
            let store = SnapshotStore(
                root: root
                    .appendingPathComponent("data/snapshots", isDirectory: true)
                    .appendingPathComponent(content.snapshot, isDirectory: true)
            )
            let plan = try LabelPipeline(store: store)
                .plan(mode: mode, setsFilter: content.setsFilter)
            let renderer = SheetRenderer(plan: plan, icons: icons)
            let pdf = try renderer.renderPDF()

            let name = LabelPipeline.outputBasename(
                snapshotTag: content.snapshot,
                mode: mode,
                assets: content.assets,
                setsFilter: content.setsFilter
            )
            let url = reports.appendingPathComponent("\(name).pdf")
            try pdf.write(to: url)
            print("Wrote \(url.path)")
            print("  \(renderer.pages.count) sheets, \(plan.sections.count) sections")
        }
    }
}

/// Emits the resolved sheet plan, the artifact the fidelity gate compares.
struct Plan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Emit the resolved sheet plan as JSON, without rendering."
    )

    @OptionGroup var content: ContentOptions

    @Option(name: .customLong("out"), help: "Output directory. Defaults to ./reports.")
    var outputDirectory: String?

    func run() async throws {
        let root = try content.resolvedContentRoot()
        let reports = URL(
            fileURLWithPath: outputDirectory ?? root.appendingPathComponent("reports").path
        )
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)

        for mode in try content.layoutModes() {
            let store = SnapshotStore(
                root: root
                    .appendingPathComponent("data/snapshots", isDirectory: true)
                    .appendingPathComponent(content.snapshot, isDirectory: true)
            )
            let plan = try LabelPipeline(store: store)
                .plan(mode: mode, setsFilter: content.setsFilter)
            let name = LabelPipeline.outputBasename(
                snapshotTag: content.snapshot,
                mode: mode,
                assets: content.assets,
                setsFilter: content.setsFilter
            )
            let url = reports.appendingPathComponent("\(name).swift-plan.json")
            try plan.canonicalJSON().write(to: url)
            print("Wrote \(url.path)")
        }
    }
}

/// Lists what is available to print from.
struct Snapshots: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshots",
        abstract: "List the pinned snapshots and the sets each carries."
    )

    @Option(name: .customLong("content-root"), help: "Directory holding assets/ and data/.")
    var contentRoot: String?

    func run() async throws {
        let root = try ContentLocator.resolve(override: contentRoot)
        let snapshotsRoot = root.appendingPathComponent("data/snapshots", isDirectory: true)
        let entries = try FileManager.default
            .contentsOfDirectory(at: snapshotsRoot, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
            .map(\.lastPathComponent)
            .sorted()

        guard !entries.isEmpty else {
            print("No snapshots under \(snapshotsRoot.path).")
            return
        }
        for tag in entries {
            let store = SnapshotStore(root: snapshotsRoot.appendingPathComponent(tag))
            let codes = ((try? store.availableSetCodes()) ?? []).sorted()
            print("\(tag)  \(codes.count) sets: \(codes.joined(separator: ", "))")
        }
    }
}

/// Symlinks this binary onto `PATH`.
struct InstallCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-cli",
        abstract: "Symlink swu-labels into a directory on PATH."
    )

    @Option(name: .customLong("prefix"), help: "Install directory.")
    var prefix: String = "/usr/local/bin"

    func run() async throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let destination = URL(fileURLWithPath: prefix).appendingPathComponent("swu-labels")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: prefix) else {
            throw ValidationError("\(prefix) does not exist. Create it, or pass --prefix.")
        }
        // Replaces an existing link rather than failing, so re-running after an
        // app update is the normal way to repoint it.
        if fileManager.fileExists(atPath: destination.path)
            || (try? destination.checkResourceIsReachable()) == true {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        print("Linked \(destination.path) -> \(source.path)")
    }
}
