import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import SWULabelsCore
@testable import SWULabelsRender

/// Gate 2 of the fidelity gate: the rendered PDF lands on the Avery 5167 grid.
///
/// Gate 1 proves the plan holds the right content. It says nothing about where
/// that content is drawn, and a scaling bug leaves every plan comparison green
/// while ruining every sheet of label stock. This gate closes that step by
/// reading the produced PDF back and asserting that each label's text is
/// physically inside the rectangle the pinned twips geometry defines for its row
/// and column.
///
/// Everything here is measured from the PDF, never from the renderer's own
/// intermediate values. Asserting a renderer's output against numbers the same
/// renderer computed would pass whatever it did.
@Suite
struct GeometryGate {
    static let tolerance: CGFloat = 0.01

    /// The Avery 5167 grid, stated in inches and derived from nothing in the app.
    ///
    /// Deliberately independent of ``Avery5167``. Asserting the renderer's output
    /// against the same constants the renderer positioned it with would pass no
    /// matter where the grid sat — shift every label by a quarter inch and both
    /// sides move together. These are the physical dimensions of the label stock,
    /// so a disagreement here means the printed sheet is wrong.
    enum Sheet {
        static let pointsPerInch: CGFloat = 72
        static let pageWidth: CGFloat = 8.5 * pointsPerInch
        static let pageHeight: CGFloat = 11 * pointsPerInch
        static let labelWidth: CGFloat = 1.75 * pointsPerInch
        static let labelHeight: CGFloat = 0.5 * pointsPerInch
        static let leftMargin: CGFloat = 0.28125 * pointsPerInch
        static let topMargin: CGFloat = 0.5 * pointsPerInch
        static let horizontalGutter: CGFloat = 0.3125 * pointsPerInch
        static let columns = 4
        static let rows = 20

        /// A label's rectangle, with the origin at the page's bottom-left.
        static func cell(row: Int, column: Int) -> CGRect {
            let x = leftMargin + CGFloat(column) * (labelWidth + horizontalGutter)
            let topDownY = topMargin + CGFloat(row) * labelHeight
            return CGRect(
                x: x,
                y: pageHeight - topDownY - labelHeight,
                width: labelWidth,
                height: labelHeight
            )
        }
    }

    /// Builds the renderer for the default layout.
    static func renderer() throws -> SheetRenderer {
        let store = SnapshotStore(root: RepoPaths.snapshot("v2026-08-23"))
        let plan = try LabelPipeline(store: store).plan(mode: .aspectSet)
        let icons = try IconStore(assetsRoot: RepoPaths.assets, mode: .color)
        return SheetRenderer(plan: plan, icons: icons)
    }

    static func renderedDocument() throws -> (PDFDocument, SheetRenderer) {
        let renderer = try renderer()
        let data = try renderer.renderPDF()
        let document = try #require(PDFDocument(data: data), "rendered bytes are not a valid PDF")
        return (document, renderer)
    }

    @Test
    func `every page is US Letter at exactly 1:1`() throws {
        let (document, _) = try Self.renderedDocument()
        // 8.5in x 11in at 72 points per inch. Hardcoded rather than derived from
        // the geometry constants, so a wrong constant fails here instead of
        // agreeing with itself.
        let expected = CGSize(width: Sheet.pageWidth, height: Sheet.pageHeight)

        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let box = page.bounds(for: .mediaBox)
            #expect(abs(box.width - expected.width) < Self.tolerance, "page \(index) width")
            #expect(abs(box.height - expected.height) < Self.tolerance, "page \(index) height")
        }
    }

    @Test
    func `page count matches the paginated plan`() throws {
        let (document, renderer) = try Self.renderedDocument()
        #expect(document.pageCount == renderer.pages.count)
    }

    @Test
    func `each section starts on a fresh sheet`() throws {
        let renderer = try Self.renderer()
        // A section sharing a sheet with the next would make the printed stack
        // impossible to split by aspect without cutting a page in half.
        var seen: [String] = []
        for page in renderer.pages where seen.last != page.sectionKey {
            seen.append(page.sectionKey)
        }
        #expect(seen == renderer.plan.sections.map(\.key), "sections are not contiguous in page order")
        #expect(Set(seen).count == seen.count, "a section's pages are not contiguous")
    }

    @Test
    func `the renderer's grid matches the physical label stock`() throws {
        let renderer = try Self.renderer()

        // Every cell is compared against the independently stated inch grid, not
        // against the constants the renderer used, so a systematic offset fails
        // here rather than agreeing with itself.
        for row in 0..<Sheet.rows {
            for column in 0..<Sheet.columns {
                let actual = renderer.cellFrame(row: row, column: column)
                let expected = Sheet.cell(row: row, column: column)
                #expect(abs(actual.minX - expected.minX) < Self.tolerance, "row \(row) column \(column) x")
                #expect(abs(actual.minY - expected.minY) < Self.tolerance, "row \(row) column \(column) y")
                #expect(abs(actual.width - expected.width) < Self.tolerance, "row \(row) column \(column) width")
                #expect(abs(actual.height - expected.height) < Self.tolerance, "row \(row) column \(column) height")
            }
        }

        // The full grid stays inside the printable page.
        let last = Sheet.cell(row: Sheet.rows - 1, column: Sheet.columns - 1)
        #expect(last.maxX <= Sheet.pageWidth + Self.tolerance, "the grid overflows the page width")
        #expect(last.minY >= -Self.tolerance, "the grid overflows the page height")
    }

    @Test
    func `each label's text is drawn inside its own cell`() throws {
        let (document, renderer) = try Self.renderedDocument()

        // Checking the first two sheets rather than all nineteen: a placement
        // bug is systematic, and reading every glyph box on every page turns a
        // fast gate into one nobody runs.
        var checked = 0
        var mismatches: [String] = []

        for pageIndex in 0..<min(2, document.pageCount) {
            let page = try #require(document.page(at: pageIndex))
            let planPage = renderer.pages[pageIndex]

            for (rowIndex, row) in planPage.rows.enumerated() {
                for (columnIndex, cell) in row.cells.enumerated() {
                    guard cell.kind == .card,
                          let title = Self.titleText(of: cell)
                    else { continue }

                    // The independent grid again, not the renderer's own frame.
                    let frame = Sheet.cell(row: rowIndex, column: columnIndex)
                    let found = page.selection(for: frame)?.string ?? ""
                    checked += 1

                    // Compared on a whitespace-stripped basis: the extracted run
                    // carries the cell's other lines and its own spacing, and
                    // the question here is placement, not transcription.
                    if !Self.normalize(found).contains(Self.normalize(title)) {
                        mismatches.append(
                            "page \(pageIndex) row \(rowIndex) column \(columnIndex): "
                                + "expected \"\(title)\" inside its cell, found \"\(found)\""
                        )
                    }
                }
            }
        }

        #expect(checked > 100, "the gate checked only \(checked) labels, so it proves little")
        #expect(mismatches.isEmpty, "\(mismatches.count) misplaced labels:\n\(mismatches.prefix(5).joined(separator: "\n"))")
    }

    /// The card title from a cell's first paragraph.
    static func titleText(of cell: PlanCell) -> String? {
        guard let paragraph = cell.paragraphs.first(where: { $0.style == "cardTitle" }) else {
            return nil
        }
        let text = paragraph.runs
            .filter { $0.kind == .text && $0.style != .uniqueMarker }
            .compactMap(\.text)
            .joined()
        return text.isEmpty ? nil : text
    }

    static func normalize(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
