import Foundation

/// The pinned set-code reference data every layout orders against.
public enum SetCatalog {
    /// Sets legal in Premier today, in chronological release order.
    ///
    /// Doubles as the dedupe tie-break: when a card appears in more than one
    /// per-set file, the earlier code in this list keeps its printing.
    public static let premierPrecedence: [String] = [
        "JTL", "LOF", "SEC", "LAW", "ASH", "IBH",
    ]

    /// Every set that has ever been part of Premier rotation, in release order.
    ///
    /// The three leading codes have since rotated out. They are here because the
    /// full-rotation layouts answer "everything that has ever been Premier-legal",
    /// and because a card first printed in a rotated-out set and later reprinted
    /// to survive rotation should file under its *original* set — which the
    /// keep-first dedupe gives for free once the original precedes the reprint.
    /// HMW (Homeworlds) is previewing officially but is absent from
    /// `formats.json`'s premier set list, so it lives here and not in
    /// ``premierPrecedence``. Moving it across needs two things: the upstream
    /// manifest declaring it legal, and a snapshot carrying its per-set file —
    /// ``Transform/assertPremierSetCoverage(premierSets:availableSetCodes:)``
    /// requires the premier list and the files on disk to match exactly, so
    /// adding it early would make every premier-pool run throw.
    public static let rotationPrecedence: [String] = [
        "SOR", "SHD", "TWI", "JTL", "LOF", "SEC", "LAW", "ASH", "IBH", "HMW",
    ]

    /// Premier-legal codes that legitimately carry no standalone per-set file.
    ///
    /// These are promo and dedupe printings folded into the main sets. A
    /// Premier-legal code missing from disk that is *not* in this set means the
    /// snapshot is incomplete, which ``Transform/assertPremierSetCoverage(premierSets:availableSetCodes:)``
    /// turns into a hard failure.
    public static let knownPromoDedupeCodes: Set<String> = [
        "JTLP", "LOFP", "SECP", "LAWP", "ASHP", "G25", "P25", "P26",
    ]

    /// Full display names for the by-set layout's divider labels.
    ///
    /// Not derivable from ingested data: the official card-list API ships no
    /// expansion name, only a code. Pinned here as reference data.
    public static let fullNames: [String: String] = [
        "SOR": "Spark of Rebellion",
        "SHD": "Shadows of the Galaxy",
        "TWI": "Twilight of the Republic",
        "JTL": "Jump to Lightspeed",
        "LOF": "Legends of the Force",
        "SEC": "Secrets of Power",
        "LAW": "A Lawless Time",
        "ASH": "Ashes of the Empire",
        "IBH": "Intro Battle: Hoth",
        "HMW": "Homeworlds",
    ]
}
