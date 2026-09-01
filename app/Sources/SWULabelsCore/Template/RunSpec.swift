import Foundation

/// A named character style a run can carry.
///
/// These are the reference generator's Word character-style ids, kept as a
/// closed enum so a typo is a compile error. They survive into the PDF path as
/// styling hooks even though PDF has no style gallery: the ``SheetPlan`` is the
/// fidelity-gate artifact, and dropping the style ids would make the plan
/// unable to prove parity with the DOCX the sheet was validated against.
public enum CharacterStyle: String, Codable, Equatable, Sendable {
    case setName
    case statSeparator
    case costValue
    case costLabel
    case powerValue
    case powerLabel
    case hpValue
    case hpLabel
    case rarityIcon
    case uniqueMarker
    case rarityName
    case typeName
    case aspectName
}

/// One resolved piece of a label line: a text run, or the rarity icon.
///
/// Renderer-agnostic on purpose. The template engine produces these without
/// knowing whether a PDF, a DOCX or a live preview will draw them, which keeps
/// the collapsing rules unit-testable with no graphics context in sight.
///
/// The JSON encoding is the reference generator's `TemplateRunSpec` shape:
/// `kind` always present, `text`/`style`/`size` omitted when absent, matching
/// `JSON.stringify` dropping `undefined` properties.
public struct RunSpec: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    public var kind: Kind
    public var text: String?
    public var style: CharacterStyle?
    public var size: Int?

    public static func text(
        _ text: String,
        style: CharacterStyle? = nil,
        size: Int? = nil
    ) -> RunSpec {
        RunSpec(kind: .text, text: text, style: style, size: size)
    }

    public static let image = RunSpec(kind: .image, text: nil, style: nil, size: nil)

    enum CodingKeys: String, CodingKey {
        case kind, text, style, size
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(size, forKey: .size)
    }
}
