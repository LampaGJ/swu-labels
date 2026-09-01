import Foundation

/// Card rarity, closed on exactly the five values the pipeline ships icons for.
///
/// Closed on purpose. The TypeScript pipeline guards this seam with a Zod
/// `z.enum`, which throws on an unrecognized value rather than coercing it, and
/// Swift's synthesized `Decodable` conformance for a `String`-raw enum throws
/// `DecodingError.dataCorrupted` in the same situation. A new upstream rarity
/// therefore fails the parse instead of reaching the renderer as a blank icon.
public enum Rarity: String, Codable, CaseIterable, Sendable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case legendary = "Legendary"
    case special = "Special"

    /// Basename of this rarity's icon asset, in both the color and mono sets.
    public var assetBasename: String {
        rawValue.lowercased()
    }
}

/// A card's aspect colour.
///
/// `Neutral` is deliberately absent: upstream models a neutral card as an empty
/// `aspects` array, and the label sheet's seventh group is synthesized from that
/// absence by ``AspectGroup/init(firstAspect:)``. Adding a `neutral` case here
/// would create a second, conflicting way to express the same fact.
public enum Aspect: String, Codable, CaseIterable, Sendable {
    case vigilance = "Vigilance"
    case command = "Command"
    case aggression = "Aggression"
    case cunning = "Cunning"
    case villainy = "Villainy"
    case heroism = "Heroism"
}

/// The card type name, closed on the nine values upstream emits.
public enum CardType: String, Codable, CaseIterable, Sendable {
    case leader = "Leader"
    case base = "Base"
    case unit = "Unit"
    case event = "Event"
    case upgrade = "Upgrade"
    case tokenUnit = "Token Unit"
    case tokenUpgrade = "Token Upgrade"
    case forceToken = "Force Token"
    case creditToken = "Credit Token"
}

/// One label-sheet section key in the aspect-grouped layouts.
///
/// Ordering is pinned by ``AspectGroup/sheetOrder`` and is load-bearing: each
/// group starts a fresh Avery 5167 sheet, so a reordering here reorders the
/// physical stack of printed pages.
public enum AspectGroup: String, Codable, CaseIterable, Sendable {
    case vigilance = "Vigilance"
    case command = "Command"
    case aggression = "Aggression"
    case cunning = "Cunning"
    case villainy = "Villainy"
    case heroism = "Heroism"
    case neutral = "Neutral"

    /// The spec-pinned section order: one fresh sheet per entry, in this sequence.
    public static let sheetOrder: [AspectGroup] = [
        .vigilance, .command, .aggression, .cunning, .villainy, .heroism, .neutral,
    ]

    /// Maps a card's first aspect to its sheet group, treating "no aspect" as Neutral.
    public init(firstAspect: Aspect?) {
        guard let firstAspect else {
            self = .neutral
            return
        }
        switch firstAspect {
        case .vigilance: self = .vigilance
        case .command: self = .command
        case .aggression: self = .aggression
        case .cunning: self = .cunning
        case .villainy: self = .villainy
        case .heroism: self = .heroism
        }
    }
}
