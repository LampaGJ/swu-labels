import Foundation

/// Every layout knob, in one typed value.
///
/// Nothing else in the pipeline hardcodes a layout decision. The JSON encoding
/// matches the TypeScript `LabelLayoutConfig` key for key and value for value,
/// because this type is embedded verbatim in both the replay record and the
/// ``SheetPlan`` that the fidelity gate compares.
public struct LabelLayoutConfig: Codable, Equatable, Sendable {
    /// Paragraph alignment for every label line.
    public enum Align: String, Codable, Sendable {
        case center
        case left
    }

    /// How sets are ordered within a section.
    public enum SetOrder: String, Codable, Sendable {
        /// Chronological release order, taken from the caller's precedence list.
        case release
        /// Fold-sorted set codes. Deterministic, never locale-aware.
        case alphabetical
    }

    /// One label line: the paragraph style it carries, and its template text.
    public struct TemplateLine: Codable, Equatable, Sendable {
        public var style: String
        public var text: String

        public init(style: String, text: String) {
            self.style = style
            self.text = text
        }
    }

    public var align: Align
    /// Vertical offset of the rarity icon run, in half-points, negative lowers it.
    ///
    /// Sits the icon on the stat line's baseline instead of riding above it.
    /// `-4` prints too low and `0` too high; `-2` is the shipped value.
    public var iconBaselineShiftHalfPoints: Int
    /// Indents wrapped text under the title start. Meaningful only in `.left`.
    public var hangingIndent: Bool
    public var hangingIndentTwips: Int
    public var setOrder: SetOrder
    public var statLineFontHalfPoints: Int
    public var titleFontHalfPoints: Int
    public var titleShrinkFontHalfPoints: Int
    /// Title length above which the shrunk size applies.
    public var titleShrinkThreshold: Int
    public var subtitleFontHalfPoints: Int
    public var subtitleShrinkFontHalfPoints: Int
    public var subtitleShrinkThreshold: Int
    /// Text `{unique_indicator}` resolves to on a unique card. Empty disables it.
    public var uniqueMarker: String
    /// The label's lines, in render order. Array order is the only thing that
    /// controls line order.
    public var template: [TemplateLine]

    public init(
        align: Align = .center,
        iconBaselineShiftHalfPoints: Int = -2,
        hangingIndent: Bool = false,
        hangingIndentTwips: Int = 360,
        setOrder: SetOrder = .release,
        statLineFontHalfPoints: Int = 12,
        titleFontHalfPoints: Int = 14,
        titleShrinkFontHalfPoints: Int = 12,
        titleShrinkThreshold: Int = 30,
        subtitleFontHalfPoints: Int = 12,
        subtitleShrinkFontHalfPoints: Int = 11,
        subtitleShrinkThreshold: Int = 34,
        uniqueMarker: String = "\u{25CA} ",
        template: [TemplateLine] = LabelLayoutConfig.defaultTemplate
    ) {
        self.align = align
        self.iconBaselineShiftHalfPoints = iconBaselineShiftHalfPoints
        self.hangingIndent = hangingIndent
        self.hangingIndentTwips = hangingIndentTwips
        self.setOrder = setOrder
        self.statLineFontHalfPoints = statLineFontHalfPoints
        self.titleFontHalfPoints = titleFontHalfPoints
        self.titleShrinkFontHalfPoints = titleShrinkFontHalfPoints
        self.titleShrinkThreshold = titleShrinkThreshold
        self.subtitleFontHalfPoints = subtitleFontHalfPoints
        self.subtitleShrinkFontHalfPoints = subtitleShrinkFontHalfPoints
        self.subtitleShrinkThreshold = subtitleShrinkThreshold
        self.uniqueMarker = uniqueMarker
        self.template = template
    }

    /// The shipped three-line label: title, subtitle, stat line.
    public static let defaultTemplate: [TemplateLine] = [
        TemplateLine(style: "cardTitle", text: "{unique_indicator} {Title}"),
        TemplateLine(style: "cardSubtitle", text: "{Subtitle}"),
        TemplateLine(
            style: "cardStats",
            text: "{rarity_symbol} {SET} - {cost_value} {cost_label} | {power_value} {power_label} | {hp_value} {hp_label}"
        ),
    ]

    /// The shipped default, matching `DEFAULT_CONFIG` in `src/config.ts`.
    public static let `default` = LabelLayoutConfig()

    /// Sole section key of the `alphabetical` layout.
    public static let alphabeticalSectionKey = "All Cards"

    /// Title size for one card, after the length-based shrink.
    ///
    /// Length is measured in UTF-16 code units, not characters. JavaScript's
    /// `String.length` counts UTF-16 code units, while Swift's `String.count`
    /// counts grapheme clusters, and the two disagree for any accented or
    /// astral-plane title. Using `count` here would shrink a different set of
    /// titles than the reference generator does.
    public func titleSize(for title: String) -> Int {
        title.utf16.count > titleShrinkThreshold ? titleShrinkFontHalfPoints : titleFontHalfPoints
    }

    /// Subtitle size for one card, after the length-based shrink.
    ///
    /// Measured in UTF-16 code units, for the reason given on ``titleSize(for:)``.
    public func subtitleSize(for subtitle: String) -> Int {
        subtitle.utf16.count > subtitleShrinkThreshold
            ? subtitleShrinkFontHalfPoints
            : subtitleFontHalfPoints
    }

    /// The paragraph indent, or `nil` when hanging indent does not apply.
    ///
    /// Centered text has no start for wrapped lines to hang from, so the knob is
    /// ignored outside `.left`.
    public var resolvedHangingIndent: Int? {
        guard align == .left, hangingIndent else { return nil }
        return hangingIndentTwips
    }
}
