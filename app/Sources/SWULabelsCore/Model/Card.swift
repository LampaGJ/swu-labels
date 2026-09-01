import Foundation

/// One card as it is pinned in a snapshot file (`data/snapshots/v<TAG>/per-set/<CODE>.json`).
///
/// This mirrors the TypeScript `CardSchema` (`src/schema.ts`) field for field.
/// Both sides are closed on `rarity`, `type_name` and each `aspects` entry, and
/// both are open to extra keys the label pipeline does not consume: Zod through
/// `z.looseObject`, Swift because `Decodable` ignores unrecognized keys. The two
/// implementations therefore accept and reject exactly the same documents.
///
/// `power`, `hp`, `upgradePower` and `upgradeHp` are optional AND nullable
/// upstream. The synthesized decoder collapses "key absent" and "key present but
/// null" to the same `nil`, which is what the TypeScript
/// `.nullable().optional()` chain does.
public struct Card: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var subtitle: String?
    public var cost: Int?
    public var power: Int?
    public var hp: Int?
    public var upgradePower: Int?
    public var upgradeHp: Int?
    public var typeName: CardType
    public var rarity: Rarity
    public var expansionCode: String
    public var unique: Bool
    public var aspects: [Aspect]

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case cost
        case power
        case hp
        case upgradePower = "upgrade_power"
        case upgradeHp = "upgrade_hp"
        case typeName = "type_name"
        case rarity
        case expansionCode = "expansion_code"
        case unique
        case aspects
    }

    public init(
        title: String,
        subtitle: String? = nil,
        cost: Int? = nil,
        power: Int? = nil,
        hp: Int? = nil,
        upgradePower: Int? = nil,
        upgradeHp: Int? = nil,
        typeName: CardType,
        rarity: Rarity,
        expansionCode: String,
        unique: Bool = false,
        aspects: [Aspect] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.cost = cost
        self.power = power
        self.hp = hp
        self.upgradePower = upgradePower
        self.upgradeHp = upgradeHp
        self.typeName = typeName
        self.rarity = rarity
        self.expansionCode = expansionCode
        self.unique = unique
        self.aspects = aspects
    }

    /// The sheet section this card belongs to in the aspect-grouped layouts.
    public var aspectGroup: AspectGroup {
        AspectGroup(firstAspect: aspects.first)
    }

    /// A stable identity for list selection.
    ///
    /// Computed, never stored, so it is absent from the encoded form and the
    /// fidelity gate's JSON comparison is unaffected. Title, subtitle and set
    /// together identify one printing: the first two alone collide across a
    /// reprint, which would make two rows of the browser share an identity.
    public var id: String {
        "\(title)|\(subtitle ?? "")|\(expansionCode)"
    }
}
