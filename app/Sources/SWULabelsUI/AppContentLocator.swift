import Foundation

/// Finds the rarity icons and pinned snapshots the app reads.
///
/// The app looks in its own bundle first and falls back to a repository
/// checkout, which is what makes `swift run` work during development without a
/// second code path. Every candidate is reported on failure, because "content
/// not found" with no list of where it looked is not a diagnosis.
public enum AppContentLocator {
    public struct NotFound: Error, CustomStringConvertible {
        public let searched: [String]

        public var description: String {
            """
            Could not find the card data. The app needs a directory containing \
            both assets/rarities and data/snapshots.

            Searched:
            \(searched.map { "  \($0)" }.joined(separator: "\n"))
            """
        }
    }

    public static func resolve(override: URL? = nil) throws -> URL {
        if let override, isContentRoot(override) { return override }

        var searched: [String] = []
        for candidate in candidates() {
            searched.append(candidate.path)
            if isContentRoot(candidate) { return candidate }
        }
        throw NotFound(searched: searched)
    }

    static func candidates() -> [URL] {
        var results: [URL] = []
        if let resources = Bundle.main.resourceURL {
            results.append(resources)
        }
        results.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true))

        // Walking up from the executable covers a `swift run` from a checkout,
        // where the binary sits several levels inside `.build`.
        var current = Bundle.main.bundleURL.resolvingSymlinksInPath()
        for _ in 0..<8 {
            results.append(current)
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return results
    }

    static func isContentRoot(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let hasIcons = fileManager.fileExists(
            atPath: url.appendingPathComponent("assets/rarities").path, isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let hasSnapshots = fileManager.fileExists(
            atPath: url.appendingPathComponent("data/snapshots").path, isDirectory: &isDirectory
        ) && isDirectory.boolValue
        return hasIcons && hasSnapshots
    }
}
