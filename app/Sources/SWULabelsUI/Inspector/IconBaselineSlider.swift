import SwiftUI

/// Adjusts how far the rarity icon sits below the text baseline.
struct IconBaselineSlider: View {
    @Binding var halfPoints: Int

    var body: some View {
        LabeledContent("Icon baseline") {
            HStack {
                Slider(value: sliderValue, in: -8...4, step: 1)
                Text(halfPoints, format: .number)
                    .monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Half-points. Negative lowers the rarity icon towards the text baseline.")
    }

    /// `Slider` needs a floating-point binding; the stored value is an integer
    /// count of half-points, so it is rounded rather than stored as a Double.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(halfPoints) },
            set: { halfPoints = Int($0.rounded()) }
        )
    }
}
