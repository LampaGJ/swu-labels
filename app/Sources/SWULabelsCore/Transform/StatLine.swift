import Foundation

/// One numeric field on a card's stat line, and the word that follows it.
public struct StatLineSegment: Equatable, Sendable {
    /// The field a segment describes. The raw value is the printed word.
    public enum Suffix: String, Equatable, Sendable {
        case cost
        case power
        case hp = "HP"
    }

    /// The numeric run, bold when printed. Carries `/` and `+` for the dual and
    /// upgrade-only shapes, so it is a string rather than a number.
    public let value: String
    public let suffix: Suffix

    public init(value: String, suffix: Suffix) {
        self.value = value
        self.suffix = suffix
    }
}

extension Transform {
    /// Builds a card's stat-line segments in the fixed order cost, power, HP.
    ///
    /// Content is driven entirely by which fields are non-nil, never by
    /// `typeName`. A Base shows only HP, an Event only cost, and a Credit Token
    /// none — each because the other fields are absent, not because of a type
    /// special case. Two upgrade shapes fall out of the same rule: a plain
    /// Upgrade carries only the upgrade values and prints `+N`, while a Pilot
    /// unit carries both and prints `unit/upgrade+`, decided per field.
    public static func statLineSegments(for card: Card) -> [StatLineSegment] {
        var segments: [StatLineSegment] = []
        if let cost = card.cost {
            segments.append(StatLineSegment(value: String(cost), suffix: .cost))
        }
        if let power = statSegment(unit: card.power, upgrade: card.upgradePower, suffix: .power) {
            segments.append(power)
        }
        if let hp = statSegment(unit: card.hp, upgrade: card.upgradeHp, suffix: .hp) {
            segments.append(hp)
        }
        return segments
    }

    private static func statSegment(
        unit: Int?,
        upgrade: Int?,
        suffix: StatLineSegment.Suffix
    ) -> StatLineSegment? {
        switch (unit, upgrade) {
        case let (unit?, upgrade?):
            return StatLineSegment(value: "\(unit)/\(upgrade)+", suffix: suffix)
        case let (unit?, nil):
            return StatLineSegment(value: String(unit), suffix: suffix)
        case let (nil, upgrade?):
            return StatLineSegment(value: "+\(upgrade)", suffix: suffix)
        case (nil, nil):
            return nil
        }
    }
}
