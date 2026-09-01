import Foundation

/// Which of the two ordering lists a criterion sits in.
///
/// Grouping decides where a fresh sheet starts; ordering arranges cards inside
/// one. Naming the distinction as a type keeps every view that touches the
/// ordering honest about which of the two it is manipulating.
enum OrderByEditorRole {
    case grouping
    case ordering

    var emptyStateTitle: String {
        switch self {
        case .grouping: "No grouping — one continuous run"
        case .ordering: "No ordering — cards keep pool order"
        }
    }

    var moveAcrossTitle: String {
        switch self {
        case .grouping: "Move to ordering"
        case .ordering: "Move to grouping"
        }
    }

    var opposite: OrderByEditorRole {
        switch self {
        case .grouping: .ordering
        case .ordering: .grouping
        }
    }
}
