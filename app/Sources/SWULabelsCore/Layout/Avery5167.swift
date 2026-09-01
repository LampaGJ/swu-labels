import Foundation

/// The Avery 5167 sheet geometry, in twips.
///
/// Every number here is load-bearing for physical alignment: the sheet is
/// 0.5in by 1.75in labels, 80 to a US Letter page, four columns by twenty rows.
/// A wrong value does not produce a visibly broken page — it produces a page
/// that looks right and prints half a millimetre off, which is only discovered
/// on a ruined sheet of label stock. Nothing downstream may improvise a
/// dimension; the renderer reads all of them from here.
///
/// Twips are 1/1440 inch, the OOXML unit the reference generator emits. The
/// renderer converts to PostScript points (1/72 inch) at the last moment via
/// ``points(fromTwips:)``, so the pinned integers stay exact.
public enum Avery5167 {
    /// US Letter, in twips: 8.5in by 11in.
    public static let pageWidthTwips = 12_240
    public static let pageHeightTwips = 15_840

    public static let marginTopTwips = 720
    public static let marginBottomTwips = 576
    public static let marginLeftTwips = 405
    public static let marginRightTwips = 405

    /// Alternating label and gutter columns, left to right.
    ///
    /// Seven entries, not four: the gutters between labels are real table
    /// columns in the reference layout, and collapsing them would change every
    /// label's horizontal position.
    public static let columnWidthsTwips = [2520, 450, 2520, 450, 2520, 450, 2520]

    /// Indices into ``columnWidthsTwips`` that hold labels rather than gutters.
    public static let labelColumnIndices = [0, 2, 4, 6]

    /// Exact row height. Not a minimum — rows never grow to fit content.
    public static let rowHeightTwips = 720

    public static let rowsPerSheet = 20

    /// Labels per row, derived rather than pinned twice.
    public static var columnsPerSheet: Int { labelColumnIndices.count }

    /// Labels per sheet.
    public static var labelsPerSheet: Int { columnsPerSheet * rowsPerSheet }

    /// Converts twips to PostScript points, the unit CoreGraphics draws in.
    public static func points(fromTwips twips: Int) -> Double {
        Double(twips) / 20.0
    }

    /// The horizontal offset of a label column, in twips, measured from the
    /// page's left edge including the left margin.
    public static func labelOriginXTwips(column: Int) -> Int {
        precondition(
            column >= 0 && column < columnsPerSheet,
            "column \(column) is outside the \(columnsPerSheet)-column grid"
        )
        let tableColumn = labelColumnIndices[column]
        let precedingWidth = columnWidthsTwips[..<tableColumn].reduce(0, +)
        return marginLeftTwips + precedingWidth
    }

    /// The vertical offset of a label row, in twips, measured from the page's
    /// top edge including the top margin.
    public static func labelOriginYTwips(row: Int) -> Int {
        precondition(
            row >= 0 && row < rowsPerSheet,
            "row \(row) is outside the \(rowsPerSheet)-row grid"
        )
        return marginTopTwips + row * rowHeightTwips
    }

    /// A label cell's width in twips.
    public static let labelWidthTwips = 2520

    /// Left and right inset inside a label cell, matching the reference
    /// generator's table cell margins.
    public static let cellInsetTwips = 40
}
