@preconcurrency import CoreGraphics
import CoreText
import Foundation
import SWULabelsCore

/// Draws a ``SheetPlan`` onto Avery 5167 sheets, at exactly 1:1.
///
/// Scale is a correctness property here, not a preference: the page is printed
/// onto pre-cut label stock, so a sheet scaled even slightly misaligns all
/// eighty labels at once. Every dimension comes from ``Avery5167`` in twips and
/// converts to points once, at the draw site.
///
/// Platform-free by construction. CoreGraphics and CoreText are present on
/// macOS, iOS, iPadOS and visionOS, so this type compiles unchanged for a future
/// iPad build; only the code that hands the finished PDF to a printer is
/// platform-specific, and that lives behind ``PrintService``.
public struct SheetRenderer: Sendable {
    public let plan: SheetPlan
    public let icons: IconStore
    private let resolver: LabelStyleResolver

    public init(plan: SheetPlan, icons: IconStore) {
        self.plan = plan
        self.icons = icons
        resolver = LabelStyleResolver(config: plan.config)
    }

    /// Page size in points.
    public var pageSize: CGSize {
        CGSize(
            width: Avery5167.points(fromTwips: plan.geometry.pageWidthTwips),
            height: Avery5167.points(fromTwips: plan.geometry.pageHeightTwips)
        )
    }

    /// One page's worth of rows, paired with the section it came from.
    public struct Page: Sendable {
        public let sectionKey: String
        public let rows: [PlanRow]
    }

    /// Paginates the plan.
    ///
    /// Every section starts a fresh sheet, which is the whole point of sections:
    /// an aspect group must not share a sheet with the next one, or the stack
    /// coming off the printer cannot be split by colour without cutting a sheet.
    public var pages: [Page] {
        plan.sections.flatMap { section -> [Page] in
            let rowsPerSheet = plan.geometry.rowsPerSheet
            guard !section.rows.isEmpty else {
                return [Page(sectionKey: section.key, rows: [])]
            }
            return stride(from: 0, to: section.rows.count, by: rowsPerSheet).map { start in
                let end = min(start + rowsPerSheet, section.rows.count)
                return Page(sectionKey: section.key, rows: Array(section.rows[start..<end]))
            }
        }
    }

    // MARK: - PDF output

    /// Renders the whole plan to PDF data.
    public func renderPDF() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw RenderError.couldNotCreatePDFConsumer
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.couldNotCreatePDFContext
        }
        for page in pages {
            context.beginPDFPage(nil)
            draw(page: page, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Draws one page. Public so a live preview draws the identical path.
    ///
    /// The interface's label preview calls this rather than approximating the
    /// layout in SwiftUI. A preview that reimplemented the layout would drift
    /// from print output, and drift is the failure this whole design avoids.
    public func draw(page: Page, in context: CGContext) {
        for (rowIndex, row) in page.rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() {
                guard columnIndex < Avery5167.columnsPerSheet else { continue }
                draw(cell: cell, row: rowIndex, column: columnIndex, in: context)
            }
        }
    }

    /// The rectangle one label occupies, in PDF points with the origin at the
    /// bottom-left of the page.
    public func cellFrame(row: Int, column: Int) -> CGRect {
        let originXTwips = Avery5167.labelOriginXTwips(column: column)
        let originYTwips = Avery5167.labelOriginYTwips(row: row)
        let width = Avery5167.points(fromTwips: Avery5167.labelWidthTwips)
        let height = Avery5167.points(fromTwips: plan.geometry.rowHeightTwips)
        let topDownY = Avery5167.points(fromTwips: originYTwips)
        return CGRect(
            x: Avery5167.points(fromTwips: originXTwips),
            y: pageSize.height - topDownY - height,
            width: width,
            height: height
        )
    }

    /// The text area inside a label, after the cell insets.
    func textFrame(row: Int, column: Int) -> CGRect {
        cellFrame(row: row, column: column)
            .insetBy(dx: Avery5167.points(fromTwips: Avery5167.cellInsetTwips), dy: 0)
    }

    func draw(cell: PlanCell, row: Int, column: Int, in context: CGContext) {
        guard cell.kind != .empty, !cell.paragraphs.isEmpty else { return }
        let frame = textFrame(row: row, column: column)
        let lines = cell.paragraphs.map { paragraph in
            TypesetLine(
                paragraph: paragraph,
                rarity: cell.rarity,
                resolver: resolver,
                icons: icons,
                maxWidth: frame.width
            )
        }

        // Vertically centred in the cell, matching the reference table cell's
        // VerticalAlign.CENTER. Rows are an exact height and never grow, so a
        // block taller than the cell overflows symmetrically rather than
        // dropping its last line off the bottom.
        let totalHeight = lines.reduce(0) { $0 + $1.height }
        var cursorY = frame.midY + totalHeight / 2

        for line in lines {
            cursorY -= line.ascent
            line.draw(at: CGPoint(x: frame.minX, y: cursorY), width: frame.width, in: context, icons: icons, config: plan.config)
            cursorY -= line.height - line.ascent
        }
    }

    public enum RenderError: Error, CustomStringConvertible {
        case couldNotCreatePDFConsumer
        case couldNotCreatePDFContext

        public var description: String {
            switch self {
            case .couldNotCreatePDFConsumer: return "could not create a PDF data consumer"
            case .couldNotCreatePDFContext: return "could not create a PDF drawing context"
            }
        }
    }
}
