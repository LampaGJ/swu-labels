import Foundation

/// Every way the label pipeline refuses to produce a sheet.
///
/// Each case mirrors a `throw` in the TypeScript generator. The pipeline fails
/// loudly at the point of detection rather than shipping a sheet that looks
/// complete and is quietly wrong: a missing set, a dropped card, or a template
/// typo all cost a page of Avery stock to discover by eye.
public enum LabelError: Error, Equatable, Sendable {
    /// A grouping produced a section key outside ``AspectGroup/sheetOrder``.
    case unrecognizedAspectGroup(String)

    /// Set codes present in the card pool that the requested ordering does not place.
    case unaccountedSetCodes(codes: [String], order: String)

    /// Premier-legal sets with no per-set file that are not known promo/dedupe codes.
    case premierSetsWithoutFileNotPromo([String])

    /// The per-set files on disk are not exactly the expected premier file set.
    case premierFileSetsMismatch(actual: [String], expected: [String])

    /// A set code reached the divider layout with no pinned full name.
    case missingSetFullName(String)

    /// `kept + dropped != parsed` after dedupe. A bug guard, not a data check.
    case dedupeAccountingMismatch(kept: Int, parsed: Int, dropped: Int)

    /// A template line referenced a `{variable}` outside the catalog.
    case unknownTemplateVariable(String)

    /// The deduped pool size fell outside the expected magnitude for its pool.
    case poolSizeOutOfRange(pool: String, count: Int, minimum: Int, maximum: Int)

    /// A full-rotation layout was requested without the rotated-out sets on disk.
    case missingRotationSets([String])

    /// `--sets` named codes that this mode's pool does not carry.
    case setsFilterUnavailable(requested: [String], available: [String])

    /// The targeted snapshot directory does not exist.
    case snapshotNotFound(String)

    /// Total labels across sections did not equal the deduped card count.
    case labelAccountingMismatch(labels: Int, cards: Int)
}

extension LabelError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unrecognizedAspectGroup(key):
            return "unrecognized aspect group key \"\(key)\""
        case let .unaccountedSetCodes(codes, order):
            return "set code(s) [\(codes.joined(separator: ", "))] not accounted for in '\(order)' order"
        case let .premierSetsWithoutFileNotPromo(sets):
            return "premier sets without a per-set file are not known promo codes: \(sets.joined(separator: ", "))"
        case let .premierFileSetsMismatch(actual, expected):
            return "available per-set files [\(actual.joined(separator: ", "))] are not exactly [\(expected.joined(separator: ", "))]"
        case let .missingSetFullName(code):
            return "no full name pinned for set code \"\(code)\""
        case let .dedupeAccountingMismatch(kept, parsed, dropped):
            return "dedupe accounting mismatch: kept \(kept), parsed \(parsed), dropped \(dropped)"
        case let .unknownTemplateVariable(name):
            return "unknown template variable \"{\(name)}\""
        case let .poolSizeOutOfRange(pool, count, minimum, maximum):
            return "\(pool) deduped total \(count) is outside the expected \(minimum)-\(maximum) magnitude — stopping instead of shipping"
        case let .missingRotationSets(sets):
            return "a full-rotation-history layout needs [\(sets.joined(separator: ", "))] but they have no per-set file in this snapshot"
        case let .setsFilterUnavailable(requested, available):
            return "--sets code(s) [\(requested.joined(separator: ", "))] not in this mode's pool (available: \(available.joined(separator: ", ")))"
        case let .snapshotNotFound(path):
            return "snapshot directory not found: \(path)"
        case let .labelAccountingMismatch(labels, cards):
            return "total labels across groups (\(labels)) does not equal deduped total (\(cards))"
        }
    }
}
