// CoreGraphics predates Swift concurrency and marks nothing `Sendable`. The
// `CGPath` values held here are `.copy()` results and are never mutated after
// construction, so they are safe to share; `@preconcurrency` states that without
// the blanket unsafety of an `@unchecked Sendable` conformance.
@preconcurrency import CoreGraphics
import Foundation
import SWULabelsCore

/// The five rarity icons for one asset mode, parsed once.
///
/// Loaded from a directory URL rather than a bundle, so the same type serves the
/// CLI reading a repository checkout, the Mac app reading its own bundle, and a
/// future iOS app reading its container. Nothing here assumes where content
/// lives.
public struct IconStore: Sendable {
    private let icons: [Rarity: SVGIcon]
    public let mode: AssetsMode

    /// Parses all five icons for `mode` from `assetsRoot`.
    ///
    /// Every icon is parsed up front, so a malformed asset fails at load rather
    /// than partway through a print run.
    public init(assetsRoot: URL, mode: AssetsMode) throws {
        let directory = assetsRoot.appendingPathComponent(mode.directoryName, isDirectory: true)
        var parsed: [Rarity: SVGIcon] = [:]
        for rarity in Rarity.allCases {
            let url = directory.appendingPathComponent("\(rarity.assetBasename).svg")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SVGIconError.iconNotFound(
                    rarity: rarity.rawValue, directory: directory.path
                )
            }
            parsed[rarity] = try SVGIcon.parse(contentsOf: url)
        }
        icons = parsed
        self.mode = mode
    }

    public func icon(for rarity: Rarity) -> SVGIcon? {
        icons[rarity]
    }
}
