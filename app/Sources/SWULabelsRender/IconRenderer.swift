@preconcurrency import CoreGraphics
import Foundation

/// Paints a parsed ``SVGIcon`` into a rectangle.
public enum IconRenderer {
    /// Draws `icon` scaled to fit `frame`, preserving its aspect ratio.
    ///
    /// SVG's coordinate system runs y-downward and CoreGraphics' runs y-upward,
    /// so the transform flips vertically. Without the flip the glyphs render
    /// upside down, which at label size reads as "the icon looks slightly wrong"
    /// rather than as an obvious error.
    public static func draw(_ icon: SVGIcon, in frame: CGRect, context: CGContext) {
        guard icon.viewBox.width > 0, icon.viewBox.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = min(
            frame.width / icon.viewBox.width,
            frame.height / icon.viewBox.height
        )
        // Centre within the frame, so a mismatched aspect ratio does not shift
        // the icon against the text it sits beside.
        let drawnWidth = icon.viewBox.width * scale
        let drawnHeight = icon.viewBox.height * scale
        let offsetX = frame.minX + (frame.width - drawnWidth) / 2
        let offsetY = frame.minY + (frame.height - drawnHeight) / 2

        context.translateBy(x: offsetX, y: offsetY + drawnHeight)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -icon.viewBox.minX, y: -icon.viewBox.minY)

        for shape in icon.shapes {
            if let fill = shape.fill {
                context.addPath(shape.path)
                context.setFillColor(
                    red: fill.red, green: fill.green, blue: fill.blue, alpha: 1
                )
                context.fillPath()
            }
            if let stroke = shape.stroke, shape.strokeWidth > 0 {
                context.addPath(shape.path)
                context.setStrokeColor(
                    red: stroke.red, green: stroke.green, blue: stroke.blue, alpha: 1
                )
                context.setLineWidth(shape.strokeWidth)
                context.setMiterLimit(10)
                context.strokePath()
            }
        }
    }
}
