import SwiftUI
import SWULabelsCore

/// What the current selection and settings would actually print.
///
/// Sheet count and print resolution are both stated before printing. Card stock
/// is consumed a sheet at a time, and art resolution varies by more than a
/// factor of two between sets — discovering either after a run is expensive.
struct ProxyRunSummary: View {
    let model: AppModel

    private var plan: ProxyPlan { model.proxyPlan }

    var body: some View {
        Section {
            if model.artIndex == nil {
                ArtIndexMissingNotice(snapshotTag: model.snapshotTag)
            } else if plan.totalCards == 0 {
                Text("No cards in the current selection have art.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Cards") {
                    Text("^[\(plan.totalCards) card](inflect: true)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Sheets") {
                    Text("^[\(plan.pages.count) sheet](inflect: true)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let dpi = model.proxyMedianDPI {
                    PrintResolutionRow(dpi: dpi)
                }
                if model.proxyCardsMissingArt > 0 {
                    Label(
                        "^[\(model.proxyCardsMissingArt) selected card](inflect: true) have no art and will be left out.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if let progress = model.artFetchProgress {
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total))) {
                        Text("Downloading art \(progress.done) of \(progress.total)")
                            .font(.caption)
                    }
                }
                if let failure = model.artFailure {
                    Label(failure, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("This run")
        }
    }
}

/// States the print resolution plainly, including when it is poor.
struct PrintResolutionRow: View {
    let dpi: Double

    private var isSoft: Bool { dpi < CardGeometry.softPrintDPIThreshold }

    var body: some View {
        LabeledContent("Print resolution") {
            HStack(spacing: 4) {
                if isSoft {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text("\(dpi, format: .number.precision(.fractionLength(0))) DPI")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .help(isSoft
            ? "Below the 300 DPI print standard, so these will look soft. That is the resolution the official art is served at; no setting here improves it. The two newest sets ship sharper art."
            : "Close to the 300 DPI print standard.")
    }
}

/// Shown when the snapshot has no art sidecar yet.
struct ArtIndexMissingNotice: View {
    let snapshotTag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No card art for this snapshot", systemImage: "photo.on.rectangle.angled")
                .font(.callout.weight(.medium))
            Text("Card art is a separate download, because the label pipeline never needs it. Fetch it with:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "swu-labels art --snapshot \(snapshotTag)")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }
}
