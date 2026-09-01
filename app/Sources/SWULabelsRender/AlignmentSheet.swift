@preconcurrency import CoreGraphics
import CoreText
import Foundation
import SWULabelsCore

/// A registration sheet, printed on plain paper and held against blank stock.
///
/// **This is the cheapest instrument in the whole pipeline.** Every other check
/// verifies the PDF; none of them can see what a particular printer actually
/// puts on paper. Printer drivers scale, shift, and enforce their own
/// unprintable margins, and any of those ruins all eighty labels at once — a
/// failure discovered by peeling a wasted sheet rather than by reading an error.
///
/// The sheet answers three questions on its own:
///
/// 1. **Is the scale exactly 1:1?** A ruler with inch and centimetre ticks
///    prints across the page. Measured with any physical ruler, a discrepancy
///    means the driver scaled, and the ratio names the factor.
/// 2. **Is the grid registered?** Every label position is outlined with corner
///    marks, so a sheet held to a light against blank stock shows any drift
///    immediately.
/// 3. **Which label is which?** Row and column indices are printed inside each
///    cell, so a misfeed can be described precisely rather than as "the middle
///    ones are off".
public enum AlignmentSheet {
    /// Renders the registration sheet.
    public static func renderPDF() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw SheetRenderer.RenderError.couldNotCreatePDFConsumer
        }
        let pageSize = CGSize(
            width: Avery5167.points(fromTwips: Avery5167.pageWidthTwips),
            height: Avery5167.points(fromTwips: Avery5167.pageHeightTwips)
        )
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SheetRenderer.RenderError.couldNotCreatePDFContext
        }

        context.beginPDFPage(nil)
        draw(in: context, pageSize: pageSize)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    static func draw(in context: CGContext, pageSize: CGSize) {
        drawLabelOutlines(in: context)
        drawRuler(in: context, pageSize: pageSize)
        drawInstructions(in: context, pageSize: pageSize)
    }

    // MARK: - Label grid

    /// Outlines every label position with corner marks.
    ///
    /// Corner marks rather than full rectangles: a complete outline printed onto
    /// real label stock would leave ink on every label, whereas corners fall in
    /// the die-cut gaps and are also easier to align by eye.
    static func drawLabelOutlines(in context: CGContext) {
        let markLength: CGFloat = 6

        for row in 0..<Avery5167.rowsPerSheet {
            for column in 0..<Avery5167.columnsPerSheet {
                let frame = cellFrame(row: row, column: column)

                context.saveGState()
                context.setStrokeColor(gray: 0.55, alpha: 1)
                context.setLineWidth(0.4)

                for corner in corners(of: frame) {
                    context.move(to: CGPoint(x: corner.point.x + corner.dx * markLength, y: corner.point.y))
                    context.addLine(to: corner.point)
                    context.addLine(to: CGPoint(x: corner.point.x, y: corner.point.y + corner.dy * markLength))
                }
                context.strokePath()
                context.restoreGState()

                drawCellLabel("\(row + 1)\u{00B7}\(column + 1)", in: frame, context: context)
            }
        }
    }

    struct Corner {
        let point: CGPoint
        /// Direction the horizontal arm runs, towards the cell's interior.
        let dx: CGFloat
        /// Direction the vertical arm runs, towards the cell's interior.
        let dy: CGFloat
    }

    static func corners(of frame: CGRect) -> [Corner] {
        [
            Corner(point: CGPoint(x: frame.minX, y: frame.minY), dx: 1, dy: 1),
            Corner(point: CGPoint(x: frame.maxX, y: frame.minY), dx: -1, dy: 1),
            Corner(point: CGPoint(x: frame.minX, y: frame.maxY), dx: 1, dy: -1),
            Corner(point: CGPoint(x: frame.maxX, y: frame.maxY), dx: -1, dy: -1),
        ]
    }

    /// The same geometry the real renderer uses, so a registration sheet that
    /// lines up guarantees the label sheet will too.
    static func cellFrame(row: Int, column: Int) -> CGRect {
        let pageHeight = Avery5167.points(fromTwips: Avery5167.pageHeightTwips)
        let height = Avery5167.points(fromTwips: Avery5167.rowHeightTwips)
        let topDownY = Avery5167.points(fromTwips: Avery5167.labelOriginYTwips(row: row))
        return CGRect(
            x: Avery5167.points(fromTwips: Avery5167.labelOriginXTwips(column: column)),
            y: pageHeight - topDownY - height,
            width: Avery5167.points(fromTwips: Avery5167.labelWidthTwips),
            height: height
        )
    }

    static func drawCellLabel(_ text: String, in frame: CGRect, context: CGContext) {
        let line = makeLine(text, size: 6, gray: 0.6)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        context.saveGState()
        context.textPosition = CGPoint(
            x: frame.midX - width / 2,
            y: frame.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: - Ruler

    /// Draws an inch and a centimetre scale across the page.
    ///
    /// The single most useful mark on the sheet: it turns "the labels look a bit
    /// off" into a measurement, and the ratio between printed and true length is
    /// exactly the driver's scale factor.
    ///
    /// It lives entirely inside the bottom margin. The label grid occupies every
    /// point between the top and bottom margins, so anything drawn at a
    /// comfortable-looking height would print *through* the last two rows — as
    /// the first version of this sheet did.
    static func drawRuler(in context: CGContext, pageSize: CGSize) {
        let pointsPerInch: CGFloat = 72
        let originX = Avery5167.points(fromTwips: Avery5167.marginLeftTwips)
        // The bottom margin is half an inch; this baseline leaves the upward
        // inch ticks and the downward centimetre ticks inside it.
        let baselineY: CGFloat = 20
        let inches = 6
        let centimetres = 15
        let pointsPerCentimetre = pointsPerInch / 2.54

        context.saveGState()
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(0.6)

        context.move(to: CGPoint(x: originX, y: baselineY))
        context.addLine(to: CGPoint(x: originX + CGFloat(inches) * pointsPerInch, y: baselineY))
        for step in 0...(inches * 4) {
            let x = originX + CGFloat(step) * pointsPerInch / 4
            context.move(to: CGPoint(x: x, y: baselineY))
            context.addLine(to: CGPoint(x: x, y: baselineY + (step % 4 == 0 ? 9 : 4)))
        }

        // Centimetres tick downward so the two scales cannot be misread as one.
        context.move(to: CGPoint(x: originX, y: baselineY))
        context.addLine(to: CGPoint(
            x: originX + CGFloat(centimetres) * pointsPerCentimetre, y: baselineY
        ))
        for step in 0...centimetres {
            let x = originX + CGFloat(step) * pointsPerCentimetre
            context.move(to: CGPoint(x: x, y: baselineY))
            context.addLine(to: CGPoint(x: x, y: baselineY - (step % 5 == 0 ? 9 : 4)))
        }
        context.strokePath()
        context.restoreGState()

        // Labelled at the ends only. Per-inch numbers would not fit in the
        // margin, and measuring end to end is what actually detects scaling.
        drawText("0", at: CGPoint(x: originX - 6, y: baselineY + 2), size: 6, context: context)
        drawText(
            "\(inches)\u{2033} exactly",
            at: CGPoint(x: originX + CGFloat(inches) * pointsPerInch + 4, y: baselineY + 4),
            size: 7,
            context: context
        )
        drawText(
            "\(centimetres) cm exactly",
            at: CGPoint(
                x: originX + CGFloat(centimetres) * pointsPerCentimetre + 4,
                y: baselineY - 9
            ),
            size: 7,
            context: context
        )
    }

    // MARK: - Instructions

    /// Prints the three checks in the top margin.
    ///
    /// In the margin for the same reason as the ruler: the grid leaves no room
    /// anywhere else, and text overlapping the last rows would obscure the very
    /// marks it is telling you to inspect.
    static func drawInstructions(in context: CGContext, pageSize: CGSize) {
        let originX = Avery5167.points(fromTwips: Avery5167.marginLeftTwips)
        let lines = [
            "Avery 5167 registration sheet \u{2014} print at 100%, never \u{201C}fit to page\u{201D}.",
            "Hold to a light against a blank sheet: corner marks should fall in the die-cut gaps.",
            "Measure the ruler below. If 6\u{2033} is not exactly 6\u{2033}, the printer scaled and every label is wrong.",
        ]
        for (index, text) in lines.enumerated() {
            drawText(
                text,
                at: CGPoint(x: originX, y: pageSize.height - 11 - CGFloat(index) * 9),
                size: 7,
                context: context
            )
        }
    }

    // MARK: - Text helpers

    static func makeLine(_ text: String, size: CGFloat, gray: CGFloat) -> CTLine {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let color = CGColor(gray: gray, alpha: 1)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
        )
        return CTLineCreateWithAttributedString(attributed)
    }

    static func drawText(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        context: CGContext
    ) {
        let line = makeLine(text, size: size, gray: 0)
        context.saveGState()
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
