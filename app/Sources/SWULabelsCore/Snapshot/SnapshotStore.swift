import CryptoKit
import Foundation

/// The pinned formats manifest: which set codes are legal in Premier today.
///
/// Only the path the pipeline consumes is modelled. Every other format entry
/// passes through untouched, matching the reference schema's loose object.
public struct FormatsManifest: Codable, Sendable {
    public struct Formats: Codable, Sendable {
        public struct Premier: Codable, Sendable {
            public var sets: [String]
        }

        public var premier: Premier
    }

    public var formats: Formats

    public var premierSets: [String] { formats.premier.sets }
}

/// One parsed, deduped pool of cards, plus the provenance the replay record needs.
public struct CardPool: Sendable {
    public let kept: [Card]
    public let parsedCount: Int
    public let droppedCount: Int
    /// SHA-256 of every file read, keyed by path relative to the snapshot root.
    public let inputHashes: [(path: String, sha256: String)]
    public let setsLoaded: [String]

    /// Cards restricted to `codes`, preserving pool order.
    public func filtered(toSets codes: [String]?) throws -> [Card] {
        guard let codes else { return kept }
        let available = Set(setsLoaded)
        let unavailable = codes.filter { !available.contains($0) }
        guard unavailable.isEmpty else {
            throw LabelError.setsFilterUnavailable(requested: unavailable, available: setsLoaded)
        }
        let wanted = Set(codes)
        return kept.filter { wanted.contains($0.expansionCode) }
    }
}

/// Reads pinned snapshots off disk, parsing every file at the boundary.
///
/// Takes URLs rather than resolving paths itself. That keeps the type free of
/// any assumption about where content lives, which is what lets the same code
/// serve the CLI reading a repo checkout, the Mac app reading its bundle, and a
/// future iOS app reading its own container.
public struct SnapshotStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var perSetDirectory: URL {
        root.appendingPathComponent("per-set", isDirectory: true)
    }

    public var formatsURL: URL { root.appendingPathComponent("formats.json") }
    public var metaURL: URL { root.appendingPathComponent("meta.json") }

    /// Fails early when the snapshot directory is absent.
    public func validateExists() throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw LabelError.snapshotNotFound(root.path)
        }
    }

    /// Parses the formats manifest at the boundary.
    public func loadFormats() throws -> FormatsManifest {
        let data = try Data(contentsOf: formatsURL)
        return try JSONDecoder().decode(FormatsManifest.self, from: data)
    }

    /// Set codes that actually have a per-set file, in no particular order.
    public func availableSetCodes() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: perSetDirectory, includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Loads, concatenates and dedupes one pool.
    ///
    /// Files are concatenated in `precedence` order because "first wins" in
    /// dedupe is precisely how a card's original printing beats its reprint.
    /// Codes with no file on disk are skipped rather than failing: a snapshot
    /// legitimately carries only the sets its ingest returned.
    public func loadPool(precedence: [String]) throws -> CardPool {
        let available = Set(try availableSetCodes())
        let setsToLoad = precedence.filter { available.contains($0) }

        var inputHashes: [(path: String, sha256: String)] = []
        var cardsInPrecedenceOrder: [Card] = []
        var parsedCount = 0

        let decoder = JSONDecoder()
        for code in setsToLoad {
            let relativePath = "per-set/\(code).json"
            let data = try Data(contentsOf: perSetDirectory.appendingPathComponent("\(code).json"))
            inputHashes.append((path: relativePath, sha256: Self.sha256(data)))
            let cards = try decoder.decode([Card].self, from: data)
            parsedCount += cards.count
            cardsInPrecedenceOrder.append(contentsOf: cards)
        }

        let (kept, droppedCount) = Transform.dedupe(cardsInPrecedenceOrder: cardsInPrecedenceOrder)
        guard kept.count == parsedCount - droppedCount else {
            throw LabelError.dedupeAccountingMismatch(
                kept: kept.count, parsed: parsedCount, dropped: droppedCount
            )
        }

        return CardPool(
            kept: kept,
            parsedCount: parsedCount,
            droppedCount: droppedCount,
            inputHashes: inputHashes,
            setsLoaded: setsToLoad
        )
    }

    /// SHA-256 of the shared inputs every layout reads.
    public func sharedInputHashes() throws -> [(path: String, sha256: String)] {
        [
            (path: "formats.json", sha256: Self.sha256(try Data(contentsOf: formatsURL))),
            (path: "meta.json", sha256: Self.sha256(try Data(contentsOf: metaURL))),
        ]
    }

    /// Lowercase hex SHA-256, matching the digests the replay records carry.
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
