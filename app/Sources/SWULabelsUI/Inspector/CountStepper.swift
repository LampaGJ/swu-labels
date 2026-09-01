import SwiftUI

/// A stepper over a plain character count.
struct CountStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent(title) {
                Text("^[\(value) character](inflect: true)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
