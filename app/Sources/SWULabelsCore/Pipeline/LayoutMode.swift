import Foundation

/// The five sheet organizations the generator can emit.
public enum LayoutMode: String, CaseIterable, Codable, Sendable {
    /// One section per aspect, sets flowing continuously within. The default.
    case aspectSet = "aspect-set"
    /// One section per set, each aspect within prefaced by a divider label.
    case set
    /// One section per aspect, every set interleaved alphabetically.
    case aspect
    /// One continuous section, no breaks at all.
    case alphabetical
    /// `aspectSet`'s shape over the full rotation history pool.
    case rotationAspectSet = "rotation-aspect-set"

    /// Modes that read the full-rotation-history pool rather than Premier-today.
    public static let rotationPoolModes: Set<LayoutMode> = [.set, .rotationAspectSet]

    /// Whether this mode needs the rotated-out sets on disk.
    public var usesRotationPool: Bool {
        LayoutMode.rotationPoolModes.contains(self)
    }

    /// The set precedence this mode orders and dedupes against.
    public var precedence: [String] {
        usesRotationPool ? SetCatalog.rotationPrecedence : SetCatalog.premierPrecedence
    }

    /// The filename segment this mode contributes to its output.
    public var filenameSuffix: String {
        switch self {
        case .aspectSet: return ""
        case .set: return "-by-set"
        case .aspect: return "-by-aspect"
        case .alphabetical: return "-alphabetical"
        case .rotationAspectSet: return "-rotation-by-aspect-by-set"
        }
    }

    /// Human-readable name for the interface's layout picker.
    public var displayName: String {
        switch self {
        case .aspectSet: return "By Aspect, then Set"
        case .set: return "By Set"
        case .aspect: return "By Aspect"
        case .alphabetical: return "Alphabetical"
        case .rotationAspectSet: return "By Aspect, then Set (full rotation)"
        }
    }

    /// One line explaining what this layout is for.
    public var summary: String {
        switch self {
        case .aspectSet:
            return "A fresh sheet per aspect colour. Sets flow continuously inside each aspect."
        case .set:
            return "A fresh sheet per set, with a divider label opening each aspect within it."
        case .aspect:
            return "A fresh sheet per aspect colour, every set interleaved alphabetically."
        case .alphabetical:
            return "One continuous alphabetical run, with no section breaks at all."
        case .rotationAspectSet:
            return "Aspect then set, widened to every set that has ever been Premier-legal."
        }
    }
}

/// Which rarity icon set a run draws.
public enum AssetsMode: String, CaseIterable, Codable, Sendable {
    /// The screen-legible icons, carrying rarity-specific hues.
    case color
    /// Print-optimized monochrome icons.
    ///
    /// The colour icons' hues convert to low-contrast grey at label size — the
    /// uncommon icon's inner glyph nearly vanishes. These keep the silhouette
    /// and letter and recolour the glyph solid black, so rarity stays readable
    /// by shape even with colour read out entirely.
    case bw

    /// The asset directory name for this mode.
    public var directoryName: String {
        switch self {
        case .color: return "rarities"
        case .bw: return "rarities-bw"
        }
    }

    /// The filename segment this mode contributes to its output.
    public var filenameSuffix: String {
        switch self {
        case .color: return ""
        case .bw: return "-bw"
        }
    }

    public var displayName: String {
        switch self {
        case .color: return "Colour"
        case .bw: return "Monochrome"
        }
    }
}
