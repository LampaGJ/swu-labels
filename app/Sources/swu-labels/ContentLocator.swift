import Foundation

/// Finds the rarity icons and pinned snapshots, wherever this binary is running.
///
/// The same executable runs from three places: a developer's `.build` directory,
/// `SWULabels.app/Contents/MacOS/` once bundled, and `/usr/local/bin` through the
/// symlink the app installs. Each sees content at a different path, so the
/// location is resolved rather than assumed, and every candidate is reported
/// when the search fails — a bare "not found" would leave no way to tell which
/// of the three situations went wrong.
enum ContentLocator {
    struct NotFound: Error, CustomStringConvertible {
        let searched: [String]

        var description: String {
            """
            could not find the content directory (needs assets/rarities and data/snapshots).
            Searched:
            \(searched.map { "  \($0)" }.joined(separator: "\n"))
            Pass --content-root to point at it explicitly.
            """
        }
    }

    /// Resolves the content root, preferring an explicit override.
    static func resolve(override: String?) throws -> URL {
        if let override {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            guard isContentRoot(url) else { throw NotFound(searched: [url.path]) }
            return url
        }

        var searched: [String] = []
        for candidate in candidates() {
            searched.append(candidate.path)
            if isContentRoot(candidate) { return candidate }
        }
        throw NotFound(searched: searched)
    }

    /// Candidate roots, most specific first.
    static func candidates() -> [URL] {
        var results: [URL] = []

        // 1. Inside an app bundle: Contents/Resources.
        results.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true))
        if let resourceURL = Bundle.main.resourceURL {
            results.append(resourceURL)
        }

        // 2. Walking up from the executable, which covers `.build/debug/` in a
        //    checkout and a symlinked binary alike once the symlink is resolved.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        results.append(contentsOf: ancestors(of: executable))

        // 3. The working directory and its ancestors, for a plain `swift run`.
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        results.append(contentsOf: ancestors(of: workingDirectory))

        return results
    }

    /// A URL and its ancestors, up to a bounded depth.
    ///
    /// Bounded because an unbounded walk from a deep path would stat its way to
    /// the filesystem root on every miss.
    static func ancestors(of url: URL, limit: Int = 8) -> [URL] {
        var results: [URL] = []
        var current = url.standardizedFileURL
        for _ in 0..<limit {
            results.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { break }
            current = parent
        }
        return results
    }

    /// Whether a directory holds both things a run needs.
    ///
    /// Checks for both, not either: a directory with icons but no snapshots
    /// would satisfy a looser test and then fail later, further from the cause.
    static func isContentRoot(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let hasIcons = fileManager.fileExists(
            atPath: url.appendingPathComponent("assets/rarities").path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let hasSnapshots = fileManager.fileExists(
            atPath: url.appendingPathComponent("data/snapshots").path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        return hasIcons && hasSnapshots
    }
}
