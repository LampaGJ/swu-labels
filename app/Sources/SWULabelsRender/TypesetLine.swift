@preconcurrency import CoreGraphics
import CoreText
import Foundation
import SWULabelsCore

/// One typeset label line, with the rarity icon reserved inline.
///
/// The icon is not drawn beside the text — it sits *in* the line, on the text
/// baseline, exactly as the reference DOCX embeds it as a run inside the
/// paragraph. Reserving its width with a `CTRunDelegate` is what makes the rest
/// of the line lay out around it correctly; measuring the text and then painting
/// an icon on top would centre the line as if the icon were not there.
struct TypesetLine {
    /// Icon height in twips, matching the reference generator's embed height.
    static let iconHeightTwips = 200

    /// The character CoreText reserves space for when a run delegate is attached.
    static let objectReplacement = "\u{FFFC}"

    private let line: CTLine
    private let iconPlacements: [IconPlacement]
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    /// Where one icon lands, once the line is positioned.
    struct IconPlacement {
        let rarity: Rarity
        /// Offset from the line's own origin, before alignment is applied.
        let offsetX: CGFloat
        let size: CGSize
    }

    var height: CGFloat { ascent + descent }

    init(
        paragraph: PlanParagraph,
        rarity: Rarity?,
        resolver: LabelStyleResolver,
        icons: IconStore,
        maxWidth: CGFloat
    ) {
        let iconHeight = Avery5167.points(fromTwips: Self.iconHeightTwips)
        let attributed = NSMutableAttributedString()
        var pendingIcons: [(index: Int, size: CGSize)] = []

        for run in paragraph.runs {
            switch run.kind {
            case .text:
                guard let text = run.text, !text.isEmpty else { continue }
                let style = resolver.resolve(run: run, inParagraph: paragraph.style)
                attributed.append(NSAttributedString(
                    string: text,
                    attributes: [.ctFont: LabelStyleResolver.font(for: style)]
                ))

            case .image:
                // Aspect ratio comes from the icon itself, measured at layout
                // time rather than assumed square. Reserving a square box for a
                // wider glyph would push the rest of the line left and shift a
                // centred stat line off centre.
                let aspect = rarity.flatMap { icons.icon(for: $0)?.aspectRatio } ?? 1
                let size = CGSize(width: iconHeight * aspect, height: iconHeight)
                pendingIcons.append((index: attributed.length, size: size))
                attributed.append(NSAttributedString(
                    string: Self.objectReplacement,
                    attributes: [.runDelegateKey: Self.runDelegate(for: size)]
                ))
            }
        }

        // No CoreText paragraph style is attached. A `CTLine` is a single line
        // and takes its position from `CTLineDraw`'s text origin, so alignment
        // is applied by offsetting that origin in `draw(at:width:in:icons:config:)`.
        // Setting an alignment here would be inert and imply otherwise.
        let created = CTLineCreateWithAttributedString(attributed)
        line = created

        var lineAscent: CGFloat = 0
        var lineDescent: CGFloat = 0
        var lineLeading: CGFloat = 0
        width = CGFloat(CTLineGetTypographicBounds(created, &lineAscent, &lineDescent, &lineLeading))
        ascent = lineAscent
        descent = lineDescent

        iconPlacements = pendingIcons.compactMap { pending in
            guard let rarity else { return nil }
            let offset = CTLineGetOffsetForStringIndex(created, pending.index, nil)
            return IconPlacement(rarity: rarity, offsetX: offset, size: pending.size)
        }
    }

    /// Draws the line with its baseline at `origin.y`, aligned within `width`.
    func draw(
        at origin: CGPoint,
        width containerWidth: CGFloat,
        in context: CGContext,
        icons: IconStore,
        config: LabelLayoutConfig
    ) {
        let alignmentOffset = config.align == .center
            ? max(0, (containerWidth - width) / 2)
            : 0
        let baseline = CGPoint(x: origin.x + alignmentOffset, y: origin.y)

        context.saveGState()
        context.textPosition = baseline
        CTLineDraw(line, context)
        context.restoreGState()

        // Negative half-points lower the icon, matching the reference's OOXML
        // `w:position`. Halving converts half-points to points.
        let baselineShift = CGFloat(config.iconBaselineShiftHalfPoints) / 2

        for placement in iconPlacements {
            guard let icon = icons.icon(for: placement.rarity) else { continue }
            let frame = CGRect(
                x: baseline.x + placement.offsetX,
                y: baseline.y + baselineShift,
                width: placement.size.width,
                height: placement.size.height
            )
            IconRenderer.draw(icon, in: frame, context: context)
        }
    }

    /// Builds the delegate that reserves an icon's box inside the line.
    static func runDelegate(for size: CGSize) -> CTRunDelegate {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateCurrentVersion,
            dealloc: { pointer in
                pointer.assumingMemoryBound(to: CGSize.self).deallocate()
            },
            getAscent: { pointer in
                pointer.assumingMemoryBound(to: CGSize.self).pointee.height
            },
            getDescent: { _ in 0 },
            getWidth: { pointer in
                pointer.assumingMemoryBound(to: CGSize.self).pointee.width
            }
        )
        let box = UnsafeMutablePointer<CGSize>.allocate(capacity: 1)
        box.initialize(to: size)
        guard let delegate = CTRunDelegateCreate(&callbacks, box) else {
            box.deallocate()
            preconditionFailure("CTRunDelegateCreate returned nil for a valid callback set")
        }
        return delegate
    }
}

extension NSAttributedString.Key {
    /// CoreText's own font attribute.
    ///
    /// Deliberately not `NSAttributedString.Key.font`, which lives in AppKit on
    /// macOS and UIKit on iOS. Naming the CoreText key directly keeps this
    /// target free of both, which is what lets the renderer compile unchanged
    /// for an iPad build.
    static let ctFont = NSAttributedString.Key(kCTFontAttributeName as String)

    /// CoreText's run delegate attribute, which has no Foundation constant.
    static let runDelegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
}
