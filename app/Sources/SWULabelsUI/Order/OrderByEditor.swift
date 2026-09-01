import SwiftUI
import SWULabelsCore

/// Builds a sheet's ordering by dragging characteristics into place.
///
/// Two ordered lists and a palette. What lands in **Group into sheets** decides
/// where a fresh sheet starts; what lands in **Then order by** arranges cards
/// inside a sheet. That distinction is the one thing a person has to understand
/// here, so the interface states it rather than leaving it to be inferred from
/// the result.
///
/// Every drag has a menu equivalent. Drag-and-drop alone would put the app's
/// central control out of reach of anyone not using a pointer, and reordering is
/// the whole point of this screen.
public struct OrderByEditor: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            OrderPresetSection(model: model)
            OrderCriteriaSection(model: model, role: .grouping)
            OrderCriteriaSection(model: model, role: .ordering)
            OrderPaletteSection(model: model)
            OrderDividerSection(model: model)
        }
        .animation(.snappy(duration: 0.2), value: model.sheetOrder)
    }
}
