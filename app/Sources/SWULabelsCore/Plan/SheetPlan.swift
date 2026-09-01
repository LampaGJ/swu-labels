import Foundation

/// The fully resolved label sheet: what goes in every cell, before anything draws it.
///
/// This is the seam the whole port is built around, and the artifact the
/// fidelity gate compares. `SWULabelsCore` decides the plan; `SWULabelsRender`
/// and `SWULabelsDocx` only decide how to draw one. The reference TypeScript
/// generator emits the identical JSON through `--emit-plan`, taken from the same
/// data it already holds immediately before it constructs DOCX objects, so byte
/// equality of the two plans proves the Swift pipeline puts the same content in
/// the same cell as the sheet that was validated on paper.
///
/// Encoding rules that parity depends on: keys sorted, no escaped slashes,
/// absent optionals omitted rather than encoded as null.
public struct SheetPlan: Codable, Equatable, Sendable {
    /// Bumped when the plan's shape changes, so a stale plan cannot silently
    /// compare equal against a newer one.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var geometry: PlanGeometry
    public var config: LabelLayoutConfig
    public var sections: [PlanSection]

    public init(
        schemaVersion: Int = SheetPlan.currentSchemaVersion,
        geometry: PlanGeometry = .avery5167,
        config: LabelLayoutConfig,
        sections: [PlanSection]
    ) {
        self.schemaVersion = schemaVersion
        self.geometry = geometry
        self.config = config
        self.sections = sections
    }
}

/// The sheet geometry a plan was laid out against, carried in the plan itself.
///
/// Embedded rather than assumed, so a plan is self-describing and a geometry
/// change shows up as a plan diff instead of a silently reprinted sheet.
public struct PlanGeometry: Codable, Equatable, Sendable {
    public var pageWidthTwips: Int
    public var pageHeightTwips: Int
    public var marginTopTwips: Int
    public var marginBottomTwips: Int
    public var marginLeftTwips: Int
    public var marginRightTwips: Int
    public var columnWidthsTwips: [Int]
    public var labelColumnIndices: [Int]
    public var rowHeightTwips: Int
    public var rowsPerSheet: Int

    public static let avery5167 = PlanGeometry(
        pageWidthTwips: Avery5167.pageWidthTwips,
        pageHeightTwips: Avery5167.pageHeightTwips,
        marginTopTwips: Avery5167.marginTopTwips,
        marginBottomTwips: Avery5167.marginBottomTwips,
        marginLeftTwips: Avery5167.marginLeftTwips,
        marginRightTwips: Avery5167.marginRightTwips,
        columnWidthsTwips: Avery5167.columnWidthsTwips,
        labelColumnIndices: Avery5167.labelColumnIndices,
        rowHeightTwips: Avery5167.rowHeightTwips,
        rowsPerSheet: Avery5167.rowsPerSheet
    )
}

/// One section of the plan. Every section starts a fresh sheet.
public struct PlanSection: Codable, Equatable, Sendable {
    public var key: String
    public var rows: [PlanRow]

    public init(key: String, rows: [PlanRow]) {
        self.key = key
        self.rows = rows
    }

    /// Sheets this section occupies, at ``PlanGeometry/rowsPerSheet`` rows each.
    public func sheetCount(rowsPerSheet: Int) -> Int {
        max(1, Int((Double(rows.count) / Double(rowsPerSheet)).rounded(.up)))
    }
}

/// One grid row: always exactly one cell per label column, padded with empties.
public struct PlanRow: Codable, Equatable, Sendable {
    public var cells: [PlanCell]

    public init(cells: [PlanCell]) {
        self.cells = cells
    }
}

/// One label cell's resolved content.
public struct PlanCell: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case card
        case divider
        /// A grid position with no content. Printed as blank label stock.
        case empty
    }

    public var kind: Kind
    /// Which rarity icon this cell's image runs draw. Absent on non-card cells.
    public var rarity: Rarity?
    public var paragraphs: [PlanParagraph]

    public init(kind: Kind, rarity: Rarity? = nil, paragraphs: [PlanParagraph] = []) {
        self.kind = kind
        self.rarity = rarity
        self.paragraphs = paragraphs
    }

    public static let empty = PlanCell(kind: .empty)

    enum CodingKeys: String, CodingKey {
        case kind, rarity, paragraphs
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(rarity, forKey: .rarity)
        try container.encode(paragraphs, forKey: .paragraphs)
    }
}

/// One paragraph inside a label cell.
public struct PlanParagraph: Codable, Equatable, Sendable {
    /// The paragraph style id, e.g. `cardTitle`.
    public var style: String
    public var runs: [RunSpec]

    public init(style: String, runs: [RunSpec]) {
        self.style = style
        self.runs = runs
    }
}

// MARK: - Canonical encoding

extension SheetPlan {
    /// Encodes the plan the one way the gate compares.
    ///
    /// Sorted keys and pretty printing make a mismatch readable as a line diff
    /// rather than a single changed byte offset. `withoutEscapingSlashes` keeps
    /// the output identical to `JSON.stringify`, which does not escape `/`.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> SheetPlan {
        try JSONDecoder().decode(SheetPlan.self, from: data)
    }
}
