@preconcurrency import CoreGraphics
import CoreText
import Foundation
import SWULabelsCore

/// Draws a ``ProxyPlan`` at exact card size.
///
/// Scale is the correctness property, as it is for the label sheets: a proxy
/// printed even a millimetre off will not sleeve with real cards, and one that
/// differs from the rest of a deck marks itself from the back. Nothing here
/// scales to fit, and the print path never offers to.
///
/// Platform-free. CoreGraphics and CoreText are on every Apple platform, so this
/// compiles unchanged for an iPad build.
public struct ProxyRenderer: Sendable {
    public let plan: ProxyPlan
    /// Decoded art, keyed by art URL. Resolved before rendering so drawing needs
    /// no `await` and cannot stall mid-page.
    public let images: [String: CGImage]

    public init(plan: ProxyPlan, images: [String: CGImage]) {
        self.plan = plan
        self.images = images
    }

    public var pageSize: CGSize {
        CGSize(
            width: plan.config.pageSize.widthPoints,
            height: plan.config.pageSize.heightPoints
        )
    }

    /// Renders every page to PDF.
    public func renderPDF() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw SheetRenderer.RenderError.couldNotCreatePDFConsumer
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SheetRenderer.RenderError.couldNotCreatePDFContext
        }
        for page in plan.pages {
            context.beginPDFPage(nil)
            draw(page: page, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Draws one page. Public so a preview draws the identical path.
    public func draw(page: ProxyPage, in context: CGContext) {
        let config = plan.config
        for (index, slot) in page.slots.enumerated() {
            let row = index / config.columns
            let column = index % config.columns
            guard row < config.rows else { continue }
            let frame = cardFrame(row: row, column: column)

            if case let .card(card) = slot {
                draw(card: card, in: frame, context: context)
            }
            // Guides are drawn for every position including empty ones, so the
            // cut grid stays uniform on a part-filled final page.
            drawCutGuides(for: frame, context: context)
        }
    }

    /// One card's rectangle, in points from the page's bottom-left.
    public func cardFrame(row: Int, column: Int) -> CGRect {
        let frame = plan.config.cardFrame(row: row, column: column)
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    // MARK: - Card art

    func draw(card: ProxyCard, in frame: CGRect, context: CGContext) {
        guard let image = images[card.artURL] else {
            drawMissingArt(card: card, in: frame, context: context)
            return
        }

        context.saveGState()
        defer { context.restoreGState() }

        // Clipped to the card's rectangle so a fractionally different art aspect
        // crops rather than bleeding into the neighbouring card.
        context.clip(to: frame)

        if card.isHorizontal {
            // Landscape art rotated into the portrait slot. Every slot keeps the
            // same shape so the page can be cut on one uniform grid; the player
            // turns the cut card to read it, exactly as with a real Leader.
            context.translateBy(x: frame.midX, y: frame.midY)
            context.rotate(by: .pi / 2)
            let rotated = CGRect(
                x: -frame.height / 2,
                y: -frame.width / 2,
                width: frame.height,
                height: frame.width
            )
            context.draw(image, in: aspectFillRect(image: image, in: rotated))
        } else {
            context.draw(image, in: aspectFillRect(image: image, in: frame))
        }
    }

    /// The rectangle that fills `bounds` while preserving the image's aspect.
    ///
    /// Fill rather than fit. Card art is 300 × 418 against a 63 × 88 card, an
    /// aspect difference of about a quarter of a percent — fitting would leave a
    /// white hairline along two edges of every proxy, while filling crops an
    /// invisible sliver of art.
    func aspectFillRect(image: CGImage, in bounds: CGRect) -> CGRect {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let boundsAspect = bounds.width / bounds.height
        let size: CGSize = if imageAspect > boundsAspect {
            CGSize(width: bounds.height * imageAspect, height: bounds.height)
        } else {
            CGSize(width: bounds.width, height: bounds.width / imageAspect)
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Marks a card whose art could not be loaded.
    ///
    /// Drawn rather than skipped: a silently blank slot on a cut sheet is
    /// indistinguishable from a deliberate gap, and would be discovered only
    /// after cutting.
    func drawMissingArt(card: ProxyCard, in frame: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(gray: 0.94, alpha: 1)
        context.fill(frame)
        context.setStrokeColor(gray: 0.6, alpha: 1)
        context.setLineWidth(0.5)
        context.stroke(frame)

        let label = "\(card.title)\n(art unavailable)"
        let font = CTFontCreateWithName("Helvetica" as CFString, 8, nil)
        for (index, line) in label.components(separatedBy: "\n").enumerated() {
            let attributed = NSAttributedString(
                string: line,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            context.textPosition = CGPoint(
                x: frame.midX - width / 2,
                y: frame.midY - CGFloat(index) * 11
            )
            CTLineDraw(ctLine, context)
        }
    }

    // MARK: - Cut guides

    func drawCutGuides(for frame: CGRect, context: CGContext) {
        switch plan.config.cutGuides {
        case .none:
            return

        case .outline:
            context.saveGState()
            context.setStrokeColor(gray: 0.7, alpha: 1)
            context.setLineWidth(0.25)
            context.stroke(frame)
            context.restoreGState()

        case .cropMarks:
            // Marks sit outside the card and stop short of it, so no ink lands
            // on the finished proxy — they are thrown away with the offcut.
            let length: CGFloat = 8
            let gap: CGFloat = 2

            context.saveGState()
            context.setStrokeColor(gray: 0.45, alpha: 1)
            context.setLineWidth(0.25)

            for x in [frame.minX, frame.maxX] {
                context.move(to: CGPoint(x: x, y: frame.minY - gap))
                context.addLine(to: CGPoint(x: x, y: frame.minY - gap - length))
                context.move(to: CGPoint(x: x, y: frame.maxY + gap))
                context.addLine(to: CGPoint(x: x, y: frame.maxY + gap + length))
            }
            for y in [frame.minY, frame.maxY] {
                context.move(to: CGPoint(x: frame.minX - gap, y: y))
                context.addLine(to: CGPoint(x: frame.minX - gap - length, y: y))
                context.move(to: CGPoint(x: frame.maxX + gap, y: y))
                context.addLine(to: CGPoint(x: frame.maxX + gap + length, y: y))
            }
            context.strokePath()
            context.restoreGState()
        }
    }
}
