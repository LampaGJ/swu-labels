import Foundation

/// The Strapi card-list API's wire shapes.
///
/// Closed on every field the pipeline consumes and open to everything else — the
/// same contract the TypeScript boundary schema states. A renamed field or a new
/// rarity value fails the parse loudly rather than arriving downstream as a
/// silent nil. Swift gives the "open to extra keys" half for free, because
/// `Decodable` ignores keys it does not model.
///
/// Internal on purpose. These are the transport's shapes, not the pipeline's;
/// ``IngestService`` is the public surface, so a change upstream cannot ripple
/// into callers. `Sendable` throughout, because pages decode inside a task group.
enum SWUAPI {
    /// A Strapi to-one relation, which is `{ data: {...} | null }`.
    struct ToOne<Attributes: Decodable & Sendable>: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let id: Int
            let attributes: Attributes
        }

        let data: Entry?
    }

    /// A Strapi to-many relation, which is `{ data: [...] }`.
    struct ToMany<Attributes: Decodable & Sendable>: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let id: Int
            let attributes: Attributes
        }

        let data: [Entry]
    }

    struct NamedCode: Decodable, Sendable {
        let code: String
    }

    struct NamedType: Decodable, Sendable {
        let name: CardType
    }

    struct NamedRarity: Decodable, Sendable {
        let name: Rarity
    }

    struct NamedAspect: Decodable, Sendable {
        let name: Aspect
    }

    /// A relation whose presence is all that matters.
    struct Presence: Decodable, Sendable {}

    struct CardAttributes: Decodable, Sendable {
        let title: String
        let subtitle: String?
        let cardNumber: Int?
        let cost: Int?
        let power: Int?
        let hp: Int?
        let upgradePower: Int?
        let upgradeHp: Int?
        let unique: Bool
        let updatedAt: String
        let expansion: ToOne<NamedCode>
        let type: ToOne<NamedType>
        let rarity: ToOne<NamedRarity>
        let aspects: ToMany<NamedAspect>
        let variantOf: ToOne<Presence>
        let reprintOf: ToOne<Presence>
    }

    struct APICard: Decodable, Sendable {
        let id: Int
        let attributes: CardAttributes
    }

    struct Pagination: Decodable, Sendable {
        let page: Int
        let pageSize: Int
        let pageCount: Int
        let total: Int
    }

    struct Meta: Decodable, Sendable {
        let pagination: Pagination
    }

    struct PageResponse: Decodable, Sendable {
        let data: [APICard]
        let meta: Meta
    }
}

extension SWUAPI.APICard {
    /// Whether this row is the printing a label sheet should carry.
    ///
    /// Excludes foil and alternate-art *variants* only. It deliberately does not
    /// exclude reprints: when a rotated-out card is reprinted into a later set to
    /// survive rotation, that reprint has `reprintOf` set and `variantOf` null,
    /// and it is the correct printing to represent *that* set. Genuine cross-set
    /// duplicates are collapsed later by dedupe, which is the right place to
    /// decide which set's printing wins.
    var isCanonicalPrinting: Bool {
        attributes.variantOf.data == nil
    }

    /// Converts a wire row into the pinned snapshot shape.
    ///
    /// Throws rather than defaulting when a required relation is missing: a card
    /// with no expansion cannot be filed onto any sheet, and inventing a code
    /// would put it silently on the wrong one.
    func toCard() throws -> (card: Card, updatedAt: String) {
        guard let expansionCode = attributes.expansion.data?.attributes.code else {
            throw IngestError.missingRelation(cardID: id, relation: "expansion")
        }
        guard let typeName = attributes.type.data?.attributes.name else {
            throw IngestError.missingRelation(cardID: id, relation: "type")
        }
        guard let rarity = attributes.rarity.data?.attributes.name else {
            throw IngestError.missingRelation(cardID: id, relation: "rarity")
        }
        let card = Card(
            title: attributes.title,
            subtitle: attributes.subtitle,
            cost: attributes.cost,
            power: attributes.power,
            hp: attributes.hp,
            upgradePower: attributes.upgradePower,
            upgradeHp: attributes.upgradeHp,
            typeName: typeName,
            rarity: rarity,
            expansionCode: expansionCode,
            unique: attributes.unique,
            aspects: attributes.aspects.data.map(\.attributes.name)
        )
        return (card, attributes.updatedAt)
    }
}

/// Everything ingest refuses to continue past.
public enum IngestError: Error, CustomStringConvertible, Equatable {
    case missingRelation(cardID: Int, relation: String)
    case httpStatus(page: Int, status: Int)
    /// The upstream shape no longer matches the boundary schema.
    ///
    /// Distinct from a transport failure because it is never retried: identical
    /// bytes decode identically, and the useful signal is that upstream changed.
    case decodingFailed(page: Int, underlying: String)
    case noCardsToDeriveTagFrom
    case formatsManifestMissing(String)

    public var description: String {
        switch self {
        case let .missingRelation(cardID, relation):
            "card \(cardID) has no \(relation) relation"
        case let .httpStatus(page, status):
            "HTTP \(status) fetching page \(page)"
        case let .decodingFailed(page, underlying):
            "page \(page) did not match the expected card-list shape: \(underlying)"
        case .noCardsToDeriveTagFrom:
            "no cards to derive a snapshot tag from"
        case let .formatsManifestMissing(path):
            "formats.json not found at \(path)"
        }
    }
}
