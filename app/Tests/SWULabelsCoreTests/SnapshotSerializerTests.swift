import Foundation
import Testing

@testable import SWULabelsCore

/// Proves the Swift ingest writes snapshots in the reference's exact byte layout.
///
/// Ingest is the one stage whose output is not a printed sheet but a file other
/// tools read, so "equivalent JSON" is not good enough: the pinned snapshots are
/// hashed in every replay record, and a snapshot that differs only in whitespace
/// would invalidate every one of those hashes while containing identical data.
///
/// This runs entirely against committed files. It needs no network, so it is a
/// real gate rather than something that only passes when the API is reachable
/// and unchanged.
@Suite
struct SnapshotSerialization {
    /// Only snapshots this repository's own ingest produced.
    ///
    /// `v2026-08-23` is deliberately excluded. It was migrated in from the
    /// original project and carries twenty-five fields per card — art URLs,
    /// rules text, traits, keywords — where this pipeline's ingest writes the
    /// twelve it consumes. It is a valid snapshot and the generator reads it
    /// happily, because both boundary schemas ignore unknown keys; it simply is
    /// not something this ingest could have written, so asking the serializer to
    /// reproduce it would be asserting the wrong thing.
    static let snapshotTags = ["v2026-08-14"]

    /// Every committed per-set file, as (tag, code, url).
    static var perSetFiles: [(tag: String, code: String, url: URL)] {
        snapshotTags.flatMap { tag -> [(tag: String, code: String, url: URL)] in
            let directory = RepoPaths.snapshot(tag).appending(path: "per-set")
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            return contents
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { (tag: tag, code: $0.deletingPathExtension().lastPathComponent, url: $0) }
        }
    }

    @Test
    func `re-serializing every committed per-set file reproduces it byte for byte`() throws {
        let files = Self.perSetFiles
        #expect(files.count > 20, "expected the pinned snapshot to carry many per-set files")

        var mismatches: [String] = []
        for file in files {
            let original = try String(contentsOf: file.url, encoding: .utf8)
            let cards = try JSONDecoder().decode([Card].self, from: Data(original.utf8))
            let rewritten = SnapshotSerializer.perSetJSON(cards)

            guard rewritten != original else { continue }
            mismatches.append(
                "\(file.tag)/\(file.code): \(Self.describeFirstDifference(rewritten, original))"
            )
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) file(s) differ:\n\(mismatches.prefix(3).joined(separator: "\n"))")
    }

    @Test
    func `decoding then re-encoding preserves every card field`() throws {
        let file = try #require(Self.perSetFiles.first { $0.code == "JTL" })
        let original = try Data(contentsOf: file.url)
        let cards = try JSONDecoder().decode([Card].self, from: original)
        let rewritten = Data(SnapshotSerializer.perSetJSON(cards).utf8)
        let reparsed = try JSONDecoder().decode([Card].self, from: rewritten)
        #expect(cards == reparsed)
    }

    /// Escaping is asserted directly, because the committed data may not happen
    /// to contain the characters that would otherwise expose a wrong escape.
    @Test
    func `string escaping matches JSON stringify`() {
        #expect(SnapshotSerializer.string("plain") == "\"plain\"")
        #expect(SnapshotSerializer.string("a\"b") == "\"a\\\"b\"")
        #expect(SnapshotSerializer.string("a\\b") == "\"a\\\\b\"")
        #expect(SnapshotSerializer.string("a\nb") == "\"a\\nb\"")
        #expect(SnapshotSerializer.string("a\tb") == "\"a\\tb\"")
        // A forward slash is NOT escaped, and neither is non-ASCII: the
        // reference leaves both literal, and escaping either would change the
        // bytes of any snapshot containing them.
        #expect(SnapshotSerializer.string("a/b") == "\"a/b\"")
        #expect(SnapshotSerializer.string("Chirrut \u{00CE}mwe") == "\"Chirrut \u{00CE}mwe\"")
        #expect(SnapshotSerializer.string("\u{0001}") == "\"\\u0001\"")
    }

    /// Names the first differing line, so a failure points somewhere useful.
    static func describeFirstDifference(_ actual: String, _ expected: String) -> String {
        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")
        for (index, pair) in zip(actualLines, expectedLines).enumerated() where pair.0 != pair.1 {
            return "line \(index + 1): wrote \(pair.0.debugDescription), expected \(pair.1.debugDescription)"
        }
        return "line counts differ: wrote \(actualLines.count), expected \(expectedLines.count)"
    }
}
