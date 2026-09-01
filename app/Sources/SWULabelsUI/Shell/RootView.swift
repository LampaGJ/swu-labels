import SwiftUI
import SWULabelsCore

/// The app's whole interface: sources on the left, cards in the middle, the
/// label being designed on the right.
///
/// A three-column `NavigationSplitView` is the shape every Apple utility of this
/// kind takes, and it adapts on its own to a stack on iPhone and a collapsible
/// sidebar on iPad — which is why the layout is expressed once here rather than
/// forked per platform.
public struct RootView: View {
    @State private var model: AppModel
    @State private var printFailure: String?
    @State private var isShowingPrintFailure = false

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            SourceSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            CardBrowser(model: model)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            LabelInspector(model: model)
                .navigationSplitViewColumnWidth(min: 340, ideal: 400)
        }
        .searchable(text: $model.searchText, prompt: "Search cards")
        .toolbar { toolbar }
        .alert("Could not print", isPresented: $isShowingPrintFailure) { } message: {
            Text(printFailure ?? "")
        }
        .overlay {
            if let message = model.phase.errorMessage {
                PipelineFailureView(message: message, retry: model.reload)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            SheetSummaryLabel(model: model)
        }
        ToolbarItemGroup {
            Picker("Rarity icons", selection: $model.assetsMode) {
                ForEach(AssetsMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Colour icons read better on screen; monochrome prints better.")

            Button("Print", systemImage: "printer", action: print)
                .keyboardShortcut("p")
                .disabled(model.renderer == nil)
                .help("Print the current sheet at 100% scale")
        }
    }

    private func print() {
        guard let renderer = model.renderer else { return }
        do {
            try PrintService.shared.print(renderer: renderer, jobName: model.printJobName)
        } catch {
            // Surfaced rather than logged: a print that quietly does nothing is
            // indistinguishable from a printer that is merely slow.
            printFailure = error.localizedDescription
            isShowingPrintFailure = true
        }
    }
}
