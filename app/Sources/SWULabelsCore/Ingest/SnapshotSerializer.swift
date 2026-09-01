import Foundation

/// Writes snapshot JSON in exactly the reference generator's byte layout.
///
/// **Hand-rolled rather than `JSONEncoder`, on purpose.** The committed
/// snapshots are tab-indented, list their keys in declaration order rather than
/// alphabetically, and spell an absent value as an explicit `null`.
/// `JSONEncoder` offers none of those: it indents with spaces, sorts keys or
/// emits them in an unspecified order, and omits nil rather than writing null.
/// Any one of those differences would make a Swift-written snapshot merely
/// *equivalent* to the reference instead of identical, which would leave the
/// two ingests unable to verify each other.
///
/// Because this emits exactly the reference layout, a Swift ingest of unchanged
/// upstream data reproduces the committed files byte for byte — which is the
/// gate `SnapshotSerializerTests` asserts.
public enum SnapshotSerializer {
    /// Key order for a card object, matching the reference's object literal.
    ///
    /// Order is part of the output contract here, not a stylistic choice, so it
    /// lives in one list rather than being implied by a struct's field order.
    static let cardKeyOrder = [
        "title", "subtitle", "cost", "power", "hp",
        "upgrade_power", "upgrade_hp", "unique",
        "type_name", "rarity", "expansion_code", "aspects",
    ]

    /// Serializes one per-set file: a tab-indented array, with a trailing newline.
    public static func perSetJSON(_ cards: [Card]) -> String {
        let body = cards.map { card(indent: 1, $0) }.joined(separator: ",\n")
        return cards.isEmpty ? "[]\n" : "[\n\(body)\n]\n"
    }

    static func card(indent level: Int, _ card: Card) -> String {
        let pad = String(repeating: "\t", count: level)
        let innerPad = String(repeating: "\t", count: level + 1)
        let values: [String: String] = [
            "title": string(card.title),
            "subtitle": card.subtitle.map(string) ?? "null",
            "cost": card.cost.map(String.init) ?? "null",
            "power": card.power.map(String.init) ?? "null",
            "hp": card.hp.map(String.init) ?? "null",
            "upgrade_power": card.upgradePower.map(String.init) ?? "null",
            "upgrade_hp": card.upgradeHp.map(String.init) ?? "null",
            "unique": card.unique ? "true" : "false",
            "type_name": string(card.typeName.rawValue),
            "rarity": string(card.rarity.rawValue),
            "expansion_code": string(card.expansionCode),
            "aspects": array(card.aspects.map(\.rawValue), indent: level + 1),
        ]
        let lines = cardKeyOrder.map { key in
            "\(innerPad)\(string(key)): \(values[key] ?? "null")"
        }
        return "\(pad){\n\(lines.joined(separator: ",\n"))\n\(pad)}"
    }

    /// A string array, expanded one element per line like the reference does.
    static func array(_ values: [String], indent level: Int) -> String {
        guard !values.isEmpty else { return "[]" }
        let pad = String(repeating: "\t", count: level)
        let innerPad = String(repeating: "\t", count: level + 1)
        let body = values.map { "\(innerPad)\(string($0))" }.joined(separator: ",\n")
        return "[\n\(body)\n\(pad)]"
    }

    /// A JSON string literal.
    ///
    /// Escapes exactly what `JSON.stringify` escapes: the two mandatory
    /// characters, the short escapes, and any other C0 control as `\u00XX`.
    /// Notably it does **not** escape `/` or non-ASCII, both of which the
    /// reference leaves literal.
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Serializes `meta.json`, in the reference's key order.
    public static func metaJSON(_ meta: SnapshotMeta) -> String {
        var lines: [String] = []
        lines.append("\t\(string("tag")): \(string(meta.tag))")
        lines.append("\t\(string("schema_version")): \(meta.schemaVersion)")
        lines.append("\t\(string("source_url")): \(string(meta.sourceURL))")
        lines.append("\t\(string("total_cards_fetched")): \(meta.totalCardsFetched)")
        lines.append("\t\(string("canonical_cards")): \(meta.canonicalCards)")
        lines.append("\t\(string("sets")): \(array(meta.sets, indent: 1))")
        lines.append("\t\(string("set_counts")): \(intMap(meta.setCounts, keys: meta.sets, indent: 1))")
        lines.append("\t\(string("set_sha256")): \(stringMap(meta.setSHA256, keys: meta.sets, indent: 1))")
        return "{\n\(lines.joined(separator: ",\n"))\n}\n"
    }

    static func intMap(_ map: [String: Int], keys: [String], indent level: Int) -> String {
        guard !keys.isEmpty else { return "{}" }
        let pad = String(repeating: "\t", count: level)
        let innerPad = String(repeating: "\t", count: level + 1)
        let body = keys
            .map { "\(innerPad)\(string($0)): \(map[$0] ?? 0)" }
            .joined(separator: ",\n")
        return "{\n\(body)\n\(pad)}"
    }

    static func stringMap(_ map: [String: String], keys: [String], indent level: Int) -> String {
        guard !keys.isEmpty else { return "{}" }
        let pad = String(repeating: "\t", count: level)
        let innerPad = String(repeating: "\t", count: level + 1)
        let body = keys
            .map { "\(innerPad)\(string($0)): \(string(map[$0] ?? ""))" }
            .joined(separator: ",\n")
        return "{\n\(body)\n\(pad)}"
    }
}

/// What `meta.json` records about a snapshot.
public struct SnapshotMeta: Sendable {
    public var tag: String
    public var schemaVersion: Int
    public var sourceURL: String
    public var totalCardsFetched: Int
    public var canonicalCards: Int
    /// Set codes, sorted — this is also the key order of the two maps below.
    public var sets: [String]
    public var setCounts: [String: Int]
    public var setSHA256: [String: String]

    public init(
        tag: String,
        schemaVersion: Int = 1,
        sourceURL: String,
        totalCardsFetched: Int,
        canonicalCards: Int,
        sets: [String],
        setCounts: [String: Int],
        setSHA256: [String: String]
    ) {
        self.tag = tag
        self.schemaVersion = schemaVersion
        self.sourceURL = sourceURL
        self.totalCardsFetched = totalCardsFetched
        self.canonicalCards = canonicalCards
        self.sets = sets
        self.setCounts = setCounts
        self.setSHA256 = setSHA256
    }
}
