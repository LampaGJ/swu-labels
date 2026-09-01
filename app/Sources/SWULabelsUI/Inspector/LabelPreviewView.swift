import SwiftUI
import SWULabelsCore
import SWULabelsRender

/// A live, true-to-print preview of one label.
///
/// **This draws through the real renderer, not a SwiftUI approximation.** The
/// obvious implementation is a `VStack` of `Text` views styled to look like the
/// label, and it is wrong: it would be a second layout engine, free to disagree
/// with the printed sheet in exactly the ways a preview exists to catch. Instead
/// the view builds a one-label ``SheetPlan``, hands it to ``SheetRenderer``, and
/// draws that renderer's output scaled up. What is on screen is what the printer
/// receives, magnified.
///
/// `Canvas` is used rather than an `NSView`/`UIView` bridge because it exists on
/// every SwiftUI platform, keeping the preview available unchanged on iPad.
public struct LabelPreviewView: View {
    public let card: Card
    public let config: LabelLayoutConfig
    public let icons: IconStore
    /// How many times larger than life to draw. A label is 1.75in by 0.5in, far
    /// too small to judge typography at actual size on screen.
    public var magnification: CGFloat = 4

    public init(
        card: Card,
        config: LabelLayoutConfig,
        icons: IconStore,
        magnification: CGFloat = 4
    ) {
        self.card = card
        self.config = config
        self.icons = icons
        self.magnification = magnification
    }

    /// The renderer for this single label, rebuilt whenever the card or config changes.
    private var renderer: SheetRenderer? {
        let section = LabelSection(key: "preview", slots: [.card(card)])
        guard let plan = try? SheetPlanner.plan(sections: [section], config: config) else {
            return nil
        }
        return SheetRenderer(plan: plan, icons: icons)
    }

    private var labelSize: CGSize {
        CGSize(
            width: Avery5167.points(fromTwips: Avery5167.labelWidthTwips) * magnification,
            height: Avery5167.points(fromTwips: Avery5167.rowHeightTwips) * magnification
        )
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )

            if let renderer {
                Canvas { context, size in
                    context.withCGContext { cgContext in
                        Self.draw(renderer: renderer, in: cgContext, viewSize: size)
                    }
                }
                // The preview always renders on white regardless of appearance:
                // it is a proof of what lands on white label stock, not a
                // surface that should restyle itself for dark mode.
                .colorScheme(.light)
            } else {
                Text("This card cannot be laid out with the current template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: labelSize.width, height: labelSize.height)
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityDescription(card: card, config: config))
    }

    /// Maps the renderer's page coordinates onto the view and draws one label.
    ///
    /// The renderer works in PDF space: y increases upward from the bottom-left
    /// of a US Letter page. `Canvas` hands over a context whose y increases
    /// downward from the top-left of the view. The flip is what reconciles them;
    /// without it the label draws upside down and off-screen.
    static func draw(renderer: SheetRenderer, in context: CGContext, viewSize: CGSize) {
        guard let page = renderer.pages.first else { return }
        let cell = renderer.cellFrame(row: 0, column: 0)
        guard cell.width > 0, cell.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: 0, y: viewSize.height)
        context.scaleBy(x: 1, y: -1)

        let scale = min(viewSize.width / cell.width, viewSize.height / cell.height)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cell.minX, y: -cell.minY)

        renderer.draw(page: page, in: context)
    }

    /// Reads the label aloud the way it reads on paper.
    ///
    /// Built from the card rather than from the rendered runs, because the
    /// rendered form is a picture as far as assistive technology is concerned.
    static func accessibilityDescription(card: Card, config: LabelLayoutConfig) -> String {
        var parts: [String] = []
        if card.unique { parts.append("Unique") }
        parts.append(card.title)
        if let subtitle = card.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        parts.append("\(card.rarity.rawValue) from \(card.expansionCode)")
        let stats = Transform.statLineSegments(for: card)
            .map { "\($0.value) \($0.suffix.rawValue)" }
        if !stats.isEmpty { parts.append(stats.joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }
}
