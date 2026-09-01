import Foundation

/// The two halves of the inspector.
enum InspectorTab: String, CaseIterable, Identifiable {
    case label
    case order

    var id: String { rawValue }

    var title: String {
        switch self {
        case .label: "Label"
        case .order: "Order"
        }
    }

    var symbolName: String {
        switch self {
        case .label: "tag"
        case .order: "arrow.up.arrow.down"
        }
    }
}
