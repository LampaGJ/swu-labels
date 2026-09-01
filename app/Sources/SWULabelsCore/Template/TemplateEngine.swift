import Foundation

/// One piece of a template line's source text.
public enum TemplateToken: Equatable, Sendable {
    case literal(String)
    case variable(String)
}

/// A template line compiled once, ahead of any card.
///
/// `sides` holds one element when the line has no top-level ` - `, and two when
/// it does. Each side is a list of `|`-separated segments, and each segment is a
/// token list. Compiling once and resolving per card keeps the per-label cost to
/// a walk over tokens, and makes an unknown variable fail before the first label
/// is built rather than rendering blank on every one.
public struct ParsedTemplateLine: Equatable, Sendable {
    public let style: String
    public let sides: [[[TemplateToken]]]
}

/// Per-card values the variable catalog resolves against.
struct ResolveContext: Sendable {
    let statSegments: [StatLineSegment]
    let titleSize: Int
    let subtitleSize: Int?

    func statSegment(_ suffix: StatLineSegment.Suffix) -> StatLineSegment? {
        statSegments.first { $0.suffix == suffix }
    }
}

/// One `{variable}`'s resolution rule.
struct VariableDefinition: Sendable {
    let resolve: @Sendable (Card, LabelLayoutConfig, ResolveContext) -> RunSpec?

    /// This variable's own text already ends with a separator space.
    ///
    /// A literal single space immediately after it is then redundant and is
    /// dropped rather than emitted as its own run.
    var absorbsSpaceAfter: Bool = false

    /// This variable's own text already begins with a separator space.
    var absorbsSpaceBefore: Bool = false
}

/// Compiles and resolves the label template language.
///
/// The full contract — variable catalog, joiner precedence, collapsing rules,
/// and the space-absorption exception — is specified in
/// `docs/template-language.md`. This type is the second implementation of that
/// spec; the first is `src/template.ts`, and the fidelity gate compares them.
public enum TemplateEngine {
    /// Every `{variable}` a template line may reference.
    ///
    /// Extending the label language is a one-entry addition here, never a change
    /// to the collapsing engine.
    ///
    /// A `Dictionary` is safe here, unlike everywhere else in the pipeline: the
    /// catalog is only ever subscripted by name, never iterated, so its
    /// randomized iteration order cannot reach printed output.
    static let catalog: [String: VariableDefinition] = [
        "Title": VariableDefinition { card, _, context in
            card.title.isEmpty ? nil : .text(card.title, size: context.titleSize)
        },
        "Subtitle": VariableDefinition { card, _, context in
            guard let subtitle = card.subtitle, !subtitle.isEmpty else { return nil }
            return .text(subtitle, size: context.subtitleSize)
        },
        "unique_indicator": VariableDefinition(
            resolve: { card, config, context in
                guard card.unique else { return nil }
                return .text(config.uniqueMarker, style: .uniqueMarker, size: context.titleSize)
            },
            absorbsSpaceAfter: true
        ),
        "SET": VariableDefinition { card, _, _ in
            card.expansionCode.isEmpty ? nil : .text(card.expansionCode, style: .setName)
        },
        "rarity_symbol": VariableDefinition { _, _, _ in .image },
        "cost_value": VariableDefinition { _, _, context in
            context.statSegment(.cost).map { .text($0.value, style: .costValue) }
        },
        "power_value": VariableDefinition { _, _, context in
            context.statSegment(.power).map { .text($0.value, style: .powerValue) }
        },
        "hp_value": VariableDefinition { _, _, context in
            context.statSegment(.hp).map { .text($0.value, style: .hpValue) }
        },
        "cost_label": VariableDefinition(
            resolve: { _, _, context in
                context.statSegment(.cost).map { .text(" \($0.suffix.rawValue)", style: .costLabel) }
            },
            absorbsSpaceBefore: true
        ),
        "power_label": VariableDefinition(
            resolve: { _, _, context in
                context.statSegment(.power).map { .text(" \($0.suffix.rawValue)", style: .powerLabel) }
            },
            absorbsSpaceBefore: true
        ),
        "hp_label": VariableDefinition(
            resolve: { _, _, context in
                context.statSegment(.hp).map { .text(" \($0.suffix.rawValue)", style: .hpLabel) }
            },
            absorbsSpaceBefore: true
        ),
        "rarity_name": VariableDefinition { card, _, _ in
            .text(card.rarity.rawValue, style: .rarityName)
        },
        "type": VariableDefinition { card, _, _ in
            .text(card.typeName.rawValue, style: .typeName)
        },
        "aspect": VariableDefinition { card, _, _ in
            .text(card.aspectGroup.rawValue, style: .aspectName)
        },
    ]

    /// Every variable name a template may reference.
    ///
    /// Exposed so the interface can list them without reaching into the catalog
    /// itself, and so adding a variable updates the help text for free.
    public static var catalogVariableNames: [String] { Array(catalog.keys) }

    /// The canonical separator between sibling segments within one dash side.
    static let siblingJoiner = " | "

    /// The canonical separator between the two dash sides.
    static let dashJoiner = " - "

    // MARK: - Compile

    /// Compiles one template line, throwing on the first unknown variable.
    ///
    /// A template is never partially valid: a typo anywhere fails the whole run
    /// before a single label renders blank.
    public static func parse(_ line: LabelLayoutConfig.TemplateLine) throws -> ParsedTemplateLine {
        let dashParts = splitOnFirst(line.text, separator: dashJoiner)
        let sides = try dashParts.map { part in
            try part.components(separatedBy: "|").map { segment in
                try tokenize(segment.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return ParsedTemplateLine(style: line.style, sides: sides)
    }

    /// Compiles a whole template.
    public static func parse(_ template: [LabelLayoutConfig.TemplateLine]) throws
        -> [ParsedTemplateLine] {
        try template.map(parse)
    }

    /// Splits on the first occurrence only, mirroring the joiner precedence rule.
    static func splitOnFirst(_ text: String, separator: String) -> [String] {
        guard let range = text.range(of: separator) else { return [text] }
        return [String(text[text.startIndex..<range.lowerBound]),
                String(text[range.upperBound...])]
    }

    /// Splits segment text into literal and variable tokens.
    ///
    /// A variable name is `[A-Za-z_][A-Za-z0-9_]*` inside braces, matching the
    /// reference tokenizer's pattern. Anything else is literal text, including a
    /// lone brace.
    static func tokenize(_ text: String) throws -> [TemplateToken] {
        var tokens: [TemplateToken] = []
        var literal = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "{",
                  let close = text[index...].firstIndex(of: "}"),
                  case let name = String(text[text.index(after: index)..<close]),
                  isValidVariableName(name)
            else {
                literal.append(text[index])
                index = text.index(after: index)
                continue
            }
            guard catalog[name] != nil else {
                throw LabelError.unknownTemplateVariable(name)
            }
            if !literal.isEmpty {
                tokens.append(.literal(literal))
                literal = ""
            }
            tokens.append(.variable(name))
            index = text.index(after: close)
        }
        if !literal.isEmpty {
            tokens.append(.literal(literal))
        }
        return tokens
    }

    static func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first.isLetter && first.isASCII || first == "_" else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    // MARK: - Resolve

    /// Resolves one compiled line for one card.
    ///
    /// Returns `nil` when every segment collapsed empty, which omits the
    /// paragraph entirely rather than emitting a blank one. That is the
    /// mechanism behind the subtitle line vanishing on a subtitle-less card.
    public static func resolve(
        _ line: ParsedTemplateLine,
        card: Card,
        config: LabelLayoutConfig
    ) -> [RunSpec]? {
        let context = ResolveContext(
            statSegments: Transform.statLineSegments(for: card),
            titleSize: card.title.isEmpty
                ? config.titleFontHalfPoints
                : config.titleSize(for: card.title),
            subtitleSize: card.subtitle.flatMap { $0.isEmpty ? nil : config.subtitleSize(for: $0) }
        )

        let sideResults = line.sides.map { resolveSide($0, card: card, config: config, context: context) }
        if line.sides.count == 1 {
            return sideResults[0]
        }
        switch (sideResults[0], sideResults[1]) {
        case let (left?, right?):
            return left + [.text(dashJoiner, style: .statSeparator)] + right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    /// Resolves one dash side, joining surviving segments with the canonical `|`.
    static func resolveSide(
        _ segments: [[TemplateToken]],
        card: Card,
        config: LabelLayoutConfig,
        context: ResolveContext
    ) -> [RunSpec]? {
        let resolved = segments.compactMap {
            resolveSegment($0, card: card, config: config, context: context)
        }
        guard !resolved.isEmpty else { return nil }
        var output: [RunSpec] = []
        for (offset, runs) in resolved.enumerated() {
            if offset > 0 {
                output.append(.text(siblingJoiner, style: .statSeparator))
            }
            output.append(contentsOf: runs)
        }
        return output
    }

    /// Resolves one `|`-separated segment.
    ///
    /// A literal between or beside variables survives only when every variable
    /// touching it rendered, so a missing value never leaves a stray space or a
    /// dangling separator behind. A segment in which no variable rendered
    /// collapses to nothing, and an image run counts as rendered content.
    static func resolveSegment(
        _ tokens: [TemplateToken],
        card: Card,
        config: LabelLayoutConfig,
        context: ResolveContext
    ) -> [RunSpec]? {
        let resolved: [RunSpec?] = tokens.map { token in
            guard case let .variable(name) = token, let definition = catalog[name] else { return nil }
            return definition.resolve(card, config, context)
        }
        guard resolved.contains(where: { $0 != nil }) else { return nil }

        var output: [RunSpec] = []
        for (index, token) in tokens.enumerated() {
            switch token {
            case .variable:
                if let spec = resolved[index] { output.append(spec) }

            case let .literal(text):
                if text.isEmpty { continue }
                if text == " ", absorbsAdjacentSpace(at: index, tokens: tokens, resolved: resolved) {
                    continue
                }
                if keepsLiteral(at: index, tokens: tokens, resolved: resolved) {
                    output.append(.text(text))
                }
            }
        }
        return output.isEmpty ? nil : output
    }

    /// Whether a neighbouring variable already carries this separator space.
    ///
    /// A narrow, documented exception. `{unique_indicator}` resolves to a marker
    /// that already ends with a space, and the three stat labels resolve to text
    /// that already begins with one, so the template's own literal space beside
    /// them would emit a second run. Dropping it reproduces the reference
    /// generator's exact run layout.
    static func absorbsAdjacentSpace(
        at index: Int,
        tokens: [TemplateToken],
        resolved: [RunSpec?]
    ) -> Bool {
        let previousAbsorbs = neighbourDefinition(at: index - 1, tokens: tokens, resolved: resolved)?
            .absorbsSpaceAfter ?? false
        let nextAbsorbs = neighbourDefinition(at: index + 1, tokens: tokens, resolved: resolved)?
            .absorbsSpaceBefore ?? false
        return previousAbsorbs || nextAbsorbs
    }

    /// The catalog entry for a neighbouring token, but only when it rendered.
    static func neighbourDefinition(
        at index: Int,
        tokens: [TemplateToken],
        resolved: [RunSpec?]
    ) -> VariableDefinition? {
        guard tokens.indices.contains(index),
              case let .variable(name) = tokens[index],
              resolved[index] != nil
        else { return nil }
        return catalog[name]
    }

    /// Whether a literal token survives the collapse.
    ///
    /// Kept when every adjacent variable rendered, or when it has no variable
    /// neighbours at all.
    static func keepsLiteral(
        at index: Int,
        tokens: [TemplateToken],
        resolved: [RunSpec?]
    ) -> Bool {
        var neighbours: [Bool] = []
        for offset in [index - 1, index + 1] {
            guard tokens.indices.contains(offset), case .variable = tokens[offset] else { continue }
            neighbours.append(resolved[offset] != nil)
        }
        return neighbours.allSatisfy { $0 }
    }
}
