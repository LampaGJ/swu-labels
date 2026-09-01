import Foundation
import Testing

@testable import SWULabelsCore

/// Gate 1 of the fidelity gate: the Swift pipeline and the reference TypeScript
/// generator must put the same content in the same cell.
///
/// The chain of custody this closes:
///
/// 1. The reference generator's replay records already pin a
///    `documentXmlSha256` for a DOCX that was validated on printed Avery stock.
///    That proves *reference plan produces the correct sheet*.
/// 2. `--emit-plan` writes that same plan out, taken from the data `render.ts`
///    holds immediately before it builds a single docx object. Adding the flag
///    left every existing hash unchanged, so it observes rather than alters.
/// 3. These tests prove *Swift plan equals reference plan*.
///
/// Together those give: the Swift pipeline puts the same content in the same
/// cell as a sheet that was checked against real label stock. Byte-comparing
/// DOCX output would have proven less, at far higher cost — it would gate on
/// OOXML serialization trivia rather than on what is printed.
@Suite
struct PlanParity {
    /// One reference plan to compare against.
    struct Fixture: CustomStringConvertible {
        let mode: LayoutMode
        let snapshotTag: String

        var planURL: URL {
            let name = LabelPipeline.outputBasename(
                snapshotTag: snapshotTag, mode: mode, assets: .color, setsFilter: nil
            )
            return RepoPaths.reports.appendingPathComponent("\(name).plan.json")
        }

        var description: String { "\(mode.rawValue) @ \(snapshotTag)" }
    }

    /// Every layout, across both pinned snapshots.
    ///
    /// The two rotation layouts read `v2026-08-14` because it is the only pinned
    /// snapshot carrying per-set files for the three rotated-out sets.
    static let fixtures: [Fixture] = [
        Fixture(mode: .aspectSet, snapshotTag: "v2026-08-23"),
        Fixture(mode: .aspect, snapshotTag: "v2026-08-23"),
        Fixture(mode: .alphabetical, snapshotTag: "v2026-08-23"),
        Fixture(mode: .set, snapshotTag: "v2026-08-14"),
        Fixture(mode: .rotationAspectSet, snapshotTag: "v2026-08-14"),
    ]

    @Test(arguments: fixtures)
    func `Swift plan matches the reference plan cell for cell`(fixture: Fixture) throws {
        let reference = try #require(
            try Self.loadReferencePlan(fixture),
            "missing reference plan at \(fixture.planURL.path) — regenerate with `npx tsx src/index.ts --groups \(fixture.mode.rawValue) --snapshot \(fixture.snapshotTag) --emit-plan`"
        )

        let pipeline = LabelPipeline(
            store: SnapshotStore(root: RepoPaths.snapshot(fixture.snapshotTag))
        )
        let actual = try pipeline.plan(mode: fixture.mode)

        // Compared through a `Bool` rather than by expanding the two plans in the
        // expectation. A `SheetPlan` describes thousands of labels, and letting
        // the testing library render both sides buries the one differing cell
        // under megabytes of matching ones.
        let matches = actual == reference
        if !matches {
            Issue.record("\(fixture): \(Self.firstDifference(actual: actual, reference: reference))")
        }
        #expect(matches)
    }

    /// Guards against the typed comparison passing because Swift never saw a field.
    ///
    /// ``SheetPlan`` decoding ignores keys it does not model, so a reference plan
    /// carrying an extra field would decode cleanly and compare equal. Comparing
    /// the two documents as untyped JSON closes that hole: anything the reference
    /// emits and the Swift plan does not is a mismatch here even though the typed
    /// test passed.
    @Test(arguments: fixtures)
    func `reference plan carries no field the Swift plan omits`(fixture: Fixture) throws {
        let referenceData = try #require(try? Data(contentsOf: fixture.planURL))
        let pipeline = LabelPipeline(
            store: SnapshotStore(root: RepoPaths.snapshot(fixture.snapshotTag))
        )
        let actualData = try pipeline.plan(mode: fixture.mode).canonicalJSON()

        let referenceObject = try JSONSerialization.jsonObject(with: referenceData)
        let actualObject = try JSONSerialization.jsonObject(with: actualData)

        // Reduced to a `Bool` before the expectation, for the reason given above.
        let matches = (referenceObject as AnyObject).isEqual(actualObject)
        #expect(
            matches,
            "\(fixture): the plans differ as untyped JSON, so one carries a field the other does not"
        )
    }

    static func loadReferencePlan(_ fixture: Fixture) throws -> SheetPlan? {
        guard let data = try? Data(contentsOf: fixture.planURL) else { return nil }
        return try SheetPlan.decode(from: data)
    }

    /// Names the first cell that differs, so a failure points at a label rather
    /// than at a three-megabyte document.
    static func firstDifference(actual: SheetPlan, reference: SheetPlan) -> String {
        if actual.schemaVersion != reference.schemaVersion {
            return "schemaVersion \(actual.schemaVersion) != \(reference.schemaVersion)"
        }
        if actual.geometry != reference.geometry {
            return "geometry differs"
        }
        if actual.config != reference.config {
            return "config differs"
        }
        if actual.sections.count != reference.sections.count {
            return "section count \(actual.sections.count) != \(reference.sections.count)"
        }
        for (sectionIndex, pair) in zip(actual.sections, reference.sections).enumerated() {
            let (actualSection, referenceSection) = pair
            if actualSection.key != referenceSection.key {
                return "section \(sectionIndex) key \"\(actualSection.key)\" != \"\(referenceSection.key)\""
            }
            if actualSection.rows.count != referenceSection.rows.count {
                return "section \"\(actualSection.key)\" row count \(actualSection.rows.count) != \(referenceSection.rows.count)"
            }
            for (rowIndex, rowPair) in zip(actualSection.rows, referenceSection.rows).enumerated() {
                let (actualRow, referenceRow) = rowPair
                guard actualRow != referenceRow else { continue }
                for (columnIndex, cellPair) in zip(actualRow.cells, referenceRow.cells).enumerated() {
                    let (actualCell, referenceCell) = cellPair
                    guard actualCell != referenceCell else { continue }
                    return """
                    section "\(actualSection.key)" row \(rowIndex) column \(columnIndex):
                      swift:     \(describe(actualCell))
                      reference: \(describe(referenceCell))
                    """
                }
            }
        }
        return "no structural difference found, yet the plans compare unequal"
    }

    static func describe(_ cell: PlanCell) -> String {
        let paragraphs = cell.paragraphs.map { paragraph in
            let runs = paragraph.runs.map { run -> String in
                switch run.kind {
                case .image: return "<icon>"
                case .text: return "\"\(run.text ?? "")\"[\(run.style?.rawValue ?? "-"):\(run.size.map(String.init) ?? "-")]"
                }
            }
            return "\(paragraph.style){\(runs.joined(separator: " "))}"
        }
        return "\(cell.kind.rawValue) \(paragraphs.joined(separator: " | "))"
    }
}

/// Locations inside the repository checkout, resolved from this file.
///
/// Tests read the pinned snapshots and the reference plans in place rather than
/// copying them into a bundle. `#filePath` is the right macro here and is
/// confined to test code: production code uses `#fileID`, which does not leak a
/// build machine's directory layout into a shipped binary.
enum RepoPaths {
    /// The repository root: four levels up from `app/Tests/SWULabelsCoreTests/`.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var reports: URL { root.appendingPathComponent("reports", isDirectory: true) }
    static var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }

    static func snapshot(_ tag: String) -> URL {
        root
            .appendingPathComponent("data/snapshots", isDirectory: true)
            .appendingPathComponent(tag, isDirectory: true)
    }
}
