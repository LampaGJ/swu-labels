import SwiftUI

/// The design surface: what a label looks like, and how sheets are ordered.
///
/// Two tabs rather than one long scroll. Designing a label and deciding the
/// order of a stack of sheets are different jobs done at different moments, and
/// stacking them in one pane makes both harder to find.
public struct LabelInspector: View {
    @Bindable var model: AppModel
    @State private var tab: InspectorTab = .label

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
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
        .navigationTitle(tab.title)
    }
}
