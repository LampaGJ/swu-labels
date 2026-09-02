import Foundation

/// What the app is producing.
///
/// Labels and proxies share their card selection but almost nothing else: one
/// prints text onto adhesive stock, the other prints card art at exact card
/// size. A single inspector holding both would force every control to explain
/// which output it applies to.
enum OutputMode: String, CaseIterable, Identifiable, Sendable {
    case labels
    case proxies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .labels: "Labels"
        case .proxies: "Proxies"
        }
    }

    var symbolName: String {
        switch self {
        case .labels: "tag"
        case .proxies: "rectangle.on.rectangle"
        }
    }
}
