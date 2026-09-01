@preconcurrency import CoreGraphics
import CoreText
import Foundation
import SWULabelsCore

/// Resolves a run's font from its paragraph style, character style and override.
///
/// Mirrors `buildStyles` in `src/render.ts`. The reference generator registers
/// real Word paragraph and character styles rather than inline formatting, and
/// the printed appearance is the result of that cascade. Reproducing the cascade
/// here — rather than hardcoding "title is bold" at the draw site — is what lets
/// a config change reach the page the same way in both implementations.
///
/// Precedence, weakest first: paragraph style, then character style, then the
/// run's own `size`. That is the order Word resolves them in.
public struct LabelStyleResolver: Sendable {
    /// The typeface both implementations name.
    public static let fontFamily = "Helvetica"

    public enum Weight: Sendable {
        case regular
        case bold
        case italic
    }

    /// A resolved paragraph or character style.
    public struct Style: Sendable {
        public var weight: Weight
        public var halfPoints: Int

        public var points: CGFloat { CGFloat(halfPoints) / 2 }
    }

    public let config: LabelLayoutConfig

    public init(config: LabelLayoutConfig) {
        self.config = config
    }

    /// The paragraph styles the shipped template names.
    ///
    /// An unrecognized style id falls back to the stats style rather than
    /// throwing: a custom template may legitimately name its own ids, and a
    /// label that prints in the wrong weight is a better failure than one that
    /// does not print at all.
    public func paragraphStyle(_ id: String) -> Style {
        switch id {
        case "cardTitle":
            return Style(weight: .bold, halfPoints: config.titleFontHalfPoints)
        case "cardSubtitle":
            return Style(weight: .italic, halfPoints: config.subtitleFontHalfPoints)
        default:
            return Style(weight: .regular, halfPoints: config.statLineFontHalfPoints)
        }
    }

    /// A character style's contribution, or nil when it changes nothing.
    public func characterStyle(_ style: CharacterStyle) -> Style? {
        let statSize = config.statLineFontHalfPoints
        switch style {
        case .costValue, .powerValue, .hpValue:
            return Style(weight: .bold, halfPoints: statSize)
        case .setName, .statSeparator, .costLabel, .powerLabel, .hpLabel,
             .rarityName, .typeName, .aspectName:
            return Style(weight: .regular, halfPoints: statSize)
        case .uniqueMarker:
            return Style(weight: .bold, halfPoints: config.titleFontHalfPoints)
        case .rarityIcon:
            // The reference registers this style with no run properties at all;
            // it exists to carry the icon's baseline shift, not to restyle text.
            return nil
        }
    }

    /// The font a run draws in.
    public func resolve(run: RunSpec, inParagraph paragraphStyleID: String) -> Style {
        var style = paragraphStyle(paragraphStyleID)
        if let characterStyleID = run.style, let override = characterStyle(characterStyleID) {
            style = override
        }
        if let size = run.size {
            style.halfPoints = size
        }
        return style
    }

    /// Builds the CoreText font for a resolved style.
    ///
    /// Helvetica ships on every Apple platform, so this needs no per-platform
    /// fallback. The trait variants are requested by PostScript name because
    /// `CTFontCreateCopyWithSymbolicTraits` silently returns the original font
    /// when a trait is unavailable, which would print a bold title in regular
    /// weight with no error anywhere.
    public static func font(for style: Style) -> CTFont {
        let name: String
        switch style.weight {
        case .regular: name = "Helvetica"
        case .bold: name = "Helvetica-Bold"
        case .italic: name = "Helvetica-Oblique"
        }
        return CTFontCreateWithName(name as CFString, style.points, nil)
    }

    /// Paragraph alignment, as CoreText expects it.
    public var textAlignment: CTTextAlignment {
        config.align == .center ? .center : .left
    }
}
