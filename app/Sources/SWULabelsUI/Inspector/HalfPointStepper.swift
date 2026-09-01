import SwiftUI

/// A stepper over a half-point font size, shown in points.
///
/// The stored unit is half-points because that is what the document format and
/// the reference generator use. Nobody thinks in half-points, so the interface
/// converts rather than exposing the raw number.
struct HalfPointStepper: View {
    let title: String
    @Binding var halfPoints: Int

    var body: some View {
        Stepper(value: $halfPoints, in: 8...48) {
            LabeledContent(title) {
                Text(points, format: .number.precision(.fractionLength(0...1)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var points: Double {
        Double(halfPoints) / 2
    }
}
