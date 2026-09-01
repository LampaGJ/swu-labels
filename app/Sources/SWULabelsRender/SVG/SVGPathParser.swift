import CoreGraphics
import Foundation

/// Parses the SVG path-data subset the rarity icons use into a `CGPath`.
///
/// **Why a parser rather than a converter.** The obvious route is converting the
/// icons to PDF at build time with `rsvg-convert`. Measured on this machine,
/// librsvg 2.62.3 emits a different SHA-256 on every run for identical input,
/// which breaks the replay requirement that a pinned input produce a
/// byte-identical output. Rasterizing instead would throw away vector detail at
/// the one size that matters. Parsing the paths keeps the icons vector, makes
/// the conversion reproducible by construction, and removes a Homebrew
/// dependency that would not exist on iOS at all.
///
/// The supported subset is exactly what the ten shipped icons contain, plus the
/// vertical-line commands for symmetry. Anything outside it throws rather than
/// being skipped: an unrecognized command silently dropped would produce a
/// subtly wrong glyph, which at 0.14 inch is indistinguishable from a correct
/// one until a sheet is printed.
public enum SVGPathParser {
    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case unsupportedCommand(Character)
        case malformedNumber(String)
        case missingOperands(command: Character, expected: Int, found: Int)
        case commandBeforeMoveTo(Character)

        public var description: String {
            switch self {
            case let .unsupportedCommand(command):
                return "unsupported SVG path command '\(command)'"
            case let .malformedNumber(text):
                return "malformed number \"\(text)\" in SVG path data"
            case let .missingOperands(command, expected, found):
                return "command '\(command)' needs \(expected) operands, found \(found)"
            case let .commandBeforeMoveTo(command):
                return "command '\(command)' appeared before any moveto"
            }
        }
    }

    /// Builds a `CGPath` from an SVG `d` attribute.
    public static func path(from data: String) throws -> CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Reflection point for a smooth curve continuing a previous cubic.
        var lastControlPoint: CGPoint?
        var hasCurrentPoint = false

        for token in try tokenize(data) {
            let command = token.command
            let values = token.operands

            switch command {
            case "M", "m":
                try consume(values, stride: 2, command: command) { operands in
                    let point = resolve(operands[0], operands[1], relative: command == "m", to: current)
                    path.move(to: point)
                    current = point
                    subpathStart = point
                    hasCurrentPoint = true
                    lastControlPoint = nil
                } continuation: { operands in
                    // Extra coordinate pairs after a moveto are implicit linetos,
                    // per the SVG path grammar.
                    let point = resolve(operands[0], operands[1], relative: command == "m", to: current)
                    path.addLine(to: point)
                    current = point
                    lastControlPoint = nil
                }

            case "L", "l":
                guard hasCurrentPoint else { throw ParseError.commandBeforeMoveTo(command) }
                try consume(values, stride: 2, command: command) { operands in
                    let point = resolve(operands[0], operands[1], relative: command == "l", to: current)
                    path.addLine(to: point)
                    current = point
                    lastControlPoint = nil
                }

            case "H", "h":
                guard hasCurrentPoint else { throw ParseError.commandBeforeMoveTo(command) }
                try consume(values, stride: 1, command: command) { operands in
                    let x = command == "h" ? current.x + operands[0] : operands[0]
                    let point = CGPoint(x: x, y: current.y)
                    path.addLine(to: point)
                    current = point
                    lastControlPoint = nil
                }

            case "V", "v":
                guard hasCurrentPoint else { throw ParseError.commandBeforeMoveTo(command) }
                try consume(values, stride: 1, command: command) { operands in
                    let y = command == "v" ? current.y + operands[0] : operands[0]
                    let point = CGPoint(x: current.x, y: y)
                    path.addLine(to: point)
                    current = point
                    lastControlPoint = nil
                }

            case "C", "c":
                guard hasCurrentPoint else { throw ParseError.commandBeforeMoveTo(command) }
                try consume(values, stride: 6, command: command) { operands in
                    let relative = command == "c"
                    let control1 = resolve(operands[0], operands[1], relative: relative, to: current)
                    let control2 = resolve(operands[2], operands[3], relative: relative, to: current)
                    let end = resolve(operands[4], operands[5], relative: relative, to: current)
                    path.addCurve(to: end, control1: control1, control2: control2)
                    current = end
                    lastControlPoint = control2
                }

            case "S", "s":
                guard hasCurrentPoint else { throw ParseError.commandBeforeMoveTo(command) }
                try consume(values, stride: 4, command: command) { operands in
                    let relative = command == "s"
                    // A smooth cubic reflects the previous curve's second control
                    // point through the current point. With no previous curve the
                    // reflection is the current point itself, per the spec.
                    let reflected = lastControlPoint.map {
                        CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                    } ?? current
                    let control2 = resolve(operands[0], operands[1], relative: relative, to: current)
                    let end = resolve(operands[2], operands[3], relative: relative, to: current)
                    path.addCurve(to: end, control1: reflected, control2: control2)
                    current = end
                    lastControlPoint = control2
                }

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastControlPoint = nil

            default:
                throw ParseError.unsupportedCommand(command)
            }
        }
        return path.copy() ?? path
    }

    // MARK: - Operand handling

    /// Applies `first` to the leading operand group and `continuation` to each
    /// repeat, which is how the SVG grammar treats repeated operand sets.
    static func consume(
        _ values: [CGFloat],
        stride strideLength: Int,
        command: Character,
        _ first: ([CGFloat]) -> Void,
        continuation: (([CGFloat]) -> Void)? = nil
    ) throws {
        guard !values.isEmpty, values.count % strideLength == 0 else {
            throw ParseError.missingOperands(
                command: command, expected: strideLength, found: values.count
            )
        }
        var isFirst = true
        for start in Swift.stride(from: 0, to: values.count, by: strideLength) {
            let group = Array(values[start..<(start + strideLength)])
            if isFirst {
                first(group)
                isFirst = false
            } else if let continuation {
                continuation(group)
            } else {
                first(group)
            }
        }
    }

    static func resolve(
        _ x: CGFloat,
        _ y: CGFloat,
        relative: Bool,
        to current: CGPoint
    ) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    // MARK: - Tokenizing

    struct Token {
        let command: Character
        let operands: [CGFloat]
    }

    static let commandCharacters = Set("MmLlHhVvCcSsQqTtAaZz")

    /// Splits path data into commands and their operands.
    ///
    /// SVG number syntax allows separators to be omitted where unambiguous, so
    /// `1-2` is two numbers and `.5.5` is two more. Splitting on whitespace and
    /// commas alone would silently merge those into one wrong value.
    static func tokenize(_ data: String) throws -> [Token] {
        var tokens: [Token] = []
        var currentCommand: Character?
        var operands: [CGFloat] = []
        var number = ""

        func flushNumber() throws {
            guard !number.isEmpty else { return }
            guard let value = Double(number) else {
                throw ParseError.malformedNumber(number)
            }
            operands.append(CGFloat(value))
            number = ""
        }

        func flushCommand() throws {
            try flushNumber()
            if let command = currentCommand {
                tokens.append(Token(command: command, operands: operands))
            }
            operands = []
        }

        for character in data {
            if commandCharacters.contains(character) {
                try flushCommand()
                currentCommand = character
                continue
            }
            if character == "," || character.isWhitespace {
                try flushNumber()
                continue
            }
            if character == "-" || character == "+" {
                // A sign starts a new number unless it follows an exponent marker.
                if !number.isEmpty, !number.hasSuffix("e"), !number.hasSuffix("E") {
                    try flushNumber()
                }
                number.append(character)
                continue
            }
            if character == "." {
                // A second dot in one token starts the next number: ".5.5".
                if number.contains(".") {
                    try flushNumber()
                }
                number.append(character)
                continue
            }
            number.append(character)
        }
        try flushCommand()
        return tokens
    }
}
