import SwiftUI
import SWULabelsCore

/// Sheet settings for printing proxy cards.
struct ProxyInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            ProxyRunSummary(model: model)

            Section("Sheet") {
                Picker("Paper", selection: $model.proxyConfig.pageSize) {
                    ForEach(ProxyPageSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }

                ProxyGridStepper(
                    title: "Columns",
                    value: $model.proxyConfig.columns,
                    limit: model.proxyConfig.maximumGrid.columns
                )
                ProxyGridStepper(
                    title: "Rows",
                    value: $model.proxyConfig.rows,
                    limit: model.proxyConfig.maximumGrid.rows
                )

                MillimetreStepper(title: "Gutter", millimetres: $model.proxyConfig.gutterMillimetres)
                    .help("Space between cards. Zero abuts them, so one cut separates two.")
                MillimetreStepper(title: "Page margin", millimetres: $model.proxyConfig.marginMillimetres)
                    .help("Most printers cannot image the outer few millimetres of a page.")

                Picker("Cut guides", selection: $model.proxyConfig.cutGuides) {
                    ForEach(ProxySheetConfig.CutGuides.allCases) { guide in
                        Text(guide.displayName).tag(guide)
                    }
                }
            }

            Section("Copies") {
                Stepper(value: $model.proxyConfig.copiesPerCard, in: 1...12) {
                    LabeledContent("Copies of each card") {
                        Text(model.proxyConfig.copiesPerCard, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Card size") {
                    Text(verbatim: "63 \u{00D7} 88 mm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Card size is fixed, not a setting \u{2014} a proxy that is not exactly this will not sleeve with real cards. Print at 100%, never \u{201C}fit to page\u{201D}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A stepper over one grid dimension, showing what the paper allows.
struct ProxyGridStepper: View {
    let title: String
    @Binding var value: Int
    let limit: Int

    var body: some View {
        Stepper(value: $value, in: 1...max(1, limit)) {
            LabeledContent(title) {
                Text("\(value) of \(max(1, limit))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .help("This paper and spacing fits at most \(max(1, limit)).")
    }
}

/// A stepper over a millimetre measurement.
struct MillimetreStepper: View {
    let title: String
    @Binding var millimetres: Double

    var body: some View {
        Stepper(value: $millimetres, in: 0...25, step: 1) {
            LabeledContent(title) {
                Text("\(millimetres, format: .number.precision(.fractionLength(0))) mm")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
