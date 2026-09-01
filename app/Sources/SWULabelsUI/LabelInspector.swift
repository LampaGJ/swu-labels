import SwiftUI
import SWULabelsCore

/// The design surface: what a label looks like, and how sheets are ordered.
///
/// Two tabs rather than one long scroll. Designing a label and deciding the
/// order of a stack of sheets are different jobs done at different moments, and
/// stacking them in one pane makes both harder to find.
public struct LabelInspector: View {
    @Bindable var model: AppModel
    @State private var tab: Tab = .label

    enum Tab: String, CaseIterable, Identifiable {
        case label = "Label"
        case order = "Order"

        var id: String { rawValue }

        var symbolName: String {
            self == .label ? "tag" : "arrow.up.arrow.down"
        }
    }

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            switch tab {
            case .label: LabelDesignPane(model: model)
            case .order: OrderByEditor(model: model)
            }
        }
        .navigationTitle(tab.rawValue)
    }
}

/// Live preview above, every layout knob below.
struct LabelDesignPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.quaternary.opacity(0.4))

            Divider()

            Form {
                Section("Text sizes") {
                    HalfPointStepper(
                        title: "Title",
                        value: $model.config.titleFontHalfPoints
                    )
                    HalfPointStepper(
                        title: "Title when long",
                        value: $model.config.titleShrinkFontHalfPoints
                    )
                    CountStepper(
                        title: "Shrink title over",
                        unit: "characters",
                        value: $model.config.titleShrinkThreshold,
                        range: 10...80
                    )
                    HalfPointStepper(
                        title: "Subtitle",
                        value: $model.config.subtitleFontHalfPoints
                    )
                    HalfPointStepper(
                        title: "Subtitle when long",
                        value: $model.config.subtitleShrinkFontHalfPoints
                    )
                    CountStepper(
                        title: "Shrink subtitle over",
                        unit: "characters",
                        value: $model.config.subtitleShrinkThreshold,
                        range: 10...80
                    )
                    HalfPointStepper(
                        title: "Stat line",
                        value: $model.config.statLineFontHalfPoints
                    )
                }

                Section("Placement") {
                    Picker("Alignment", selection: $model.config.align) {
                        Text("Centred").tag(LabelLayoutConfig.Align.center)
                        Text("Left").tag(LabelLayoutConfig.Align.left)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Icon baseline") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(model.config.iconBaselineShiftHalfPoints) },
                                    set: { model.config.iconBaselineShiftHalfPoints = Int($0.rounded()) }
                                ),
                                in: -8...4,
                                step: 1
                            )
                            Text("\(model.config.iconBaselineShiftHalfPoints)")
                                .monospacedDigit()
                                .frame(width: 26, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help("Half-points. Negative lowers the rarity icon towards the text baseline.")

                    Toggle("Hanging indent", isOn: $model.config.hangingIndent)
                        .disabled(model.config.align != .left)
                        .help("Only applies to left-aligned labels — centred text has no start to hang from.")
                }

                Section("Unique marker") {
                    TextField("Marker", text: $model.config.uniqueMarker)
                        .help("Printed before a unique card's name. Leave empty to turn it off.")
                }

                TemplateEditor(model: model)

                Section {
                    Button("Reset to shipped defaults") {
                        model.resetConfigToDefault()
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let card = model.previewCard, let icons = model.icons {
            VStack(spacing: 8) {
                LabelPreviewView(card: card, config: model.config, icons: icons)
                Text("Actual size 1.75\u{2033} \u{00D7} 0.5\u{2033}, shown at 4\u{00D7}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a card to preview its label")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
        }
    }
}

/// A stepper over a half-point font size, shown in points.
///
/// The underlying unit is half-points because that is what the document format
/// and the reference generator use, but nobody thinks in half-points, so the
/// interface shows points and converts.
struct HalfPointStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: 8...48, step: 1) {
            LabeledContent(title) {
                Text(Self.format(halfPoints: value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func format(halfPoints: Int) -> String {
        let points = Double(halfPoints) / 2
        return points == points.rounded()
            ? "\(Int(points)) pt"
            : String(format: "%.1f pt", points)
    }
}

/// A stepper over a plain count.
struct CountStepper: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent(title) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
