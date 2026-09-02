import SwiftUI

/// A one-line statement of what the current settings would put on paper.
///
/// Sheet count is the number that matters before pressing print: label stock is
/// consumed a sheet at a time, and the difference between eighteen and nineteen
/// sheets is a wasted page nobody notices until it prints.
struct SheetSummaryLabel: View {
    let model: AppModel

    var body: some View {
        if model.phase.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading cards\u{2026}")
                    .foregroundStyle(.secondary)
            }
        } else {
            switch model.outputMode {
            case .labels:
                if model.plan != nil {
                    Text("^[\(model.labelCount) label](inflect: true) \u{00B7} ^[\(model.sheetCount) sheet](inflect: true)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .proxies:
                let plan = model.proxyPlan
                if plan.totalCards > 0 {
                    Text("^[\(plan.totalCards) card](inflect: true) \u{00B7} ^[\(plan.pages.count) sheet](inflect: true)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
