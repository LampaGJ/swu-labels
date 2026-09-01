import SwiftUI
import SWULabelsCore

/// Live preview above, every layout knob below.
struct LabelDesignPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            LabelPreviewPanel(model: model)

            Divider()

            Form {
                Section("Text sizes") {
                    HalfPointStepper(title: "Title", halfPoints: $model.config.titleFontHalfPoints)
                    HalfPointStepper(title: "Title when long", halfPoints: $model.config.titleShrinkFontHalfPoints)
                    CountStepper(
                        title: "Shrink title over",
                        value: $model.config.titleShrinkThreshold,
                        range: 10...80
                    )
                    HalfPointStepper(title: "Subtitle", halfPoints: $model.config.subtitleFontHalfPoints)
                    HalfPointStepper(title: "Subtitle when long", halfPoints: $model.config.subtitleShrinkFontHalfPoints)
                    CountStepper(
                        title: "Shrink subtitle over",
                        value: $model.config.subtitleShrinkThreshold,
                        range: 10...80
                    )
                    HalfPointStepper(title: "Stat line", halfPoints: $model.config.statLineFontHalfPoints)
                }

                Section("Placement") {
                    Picker("Alignment", selection: $model.config.align) {
                        Text("Centred").tag(LabelLayoutConfig.Align.center)
                        Text("Left").tag(LabelLayoutConfig.Align.left)
                    }
                    .pickerStyle(.segmented)

                    IconBaselineSlider(halfPoints: $model.config.iconBaselineShiftHalfPoints)

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
                    Button("Reset to shipped defaults", action: model.resetConfigToDefault)
                }
            }
            .formStyle(.grouped)
        }
    }
}
