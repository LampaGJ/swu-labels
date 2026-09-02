import SwiftUI
import SWULabelsCore
import SWULabelsRender

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
            Group {
                switch model.outputMode {
                case .labels: LabelInspector(model: model)
                case .proxies: ProxyInspector(model: model)
                }
            }
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
            Picker("Output", selection: $model.outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Print adhesive labels, or proxy cards at exact card size.")

            if model.outputMode == .labels {
                Picker("Rarity icons", selection: $model.assetsMode) {
                    ForEach(AssetsMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Colour icons read better on screen; monochrome prints better.")
            }

            Button("Print", systemImage: "printer") {
                Task { await print() }
            }
            .keyboardShortcut("p")
            .disabled(isPrintDisabled)
            .help("Print at 100% scale")

            Menu("More print options", systemImage: "ellipsis.circle") {
                Button("Print Registration Sheet\u{2026}", action: printAlignmentSheet)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            .menuIndicator(.hidden)
            .help("Check a printer's scale and alignment before using label stock")
        }
    }

    /// Prints the registration sheet, so a printer can be checked on plain
    /// paper rather than on a sheet of label stock.
    private func printAlignmentSheet() {
        do {
            try PrintService.shared.printAlignmentSheet()
        } catch {
            printFailure = error.localizedDescription
            isShowingPrintFailure = true
        }
    }

    private var isPrintDisabled: Bool {
        switch model.outputMode {
        case .labels: model.renderer == nil
        case .proxies: model.proxyPlan.pages.isEmpty
        }
    }

    private func print() async {
        do {
            switch model.outputMode {
            case .labels:
                guard let renderer = model.renderer else { return }
                try PrintService.shared.print(renderer: renderer, jobName: model.printJobName)
            case .proxies:
                // Art is downloaded before the print panel opens. Presenting the
                // panel first would leave someone waiting at a dialog while
                // hundreds of images fetched behind it.
                await model.prefetchProxyArt()
                let images = try await model.proxyImages()
                try PrintService.shared.printProxies(
                    renderer: ProxyRenderer(plan: model.proxyPlan, images: images),
                    jobName: "SWU proxies"
                )
            }
        } catch {
            // Surfaced rather than logged: a print that quietly does nothing is
            // indistinguishable from a printer that is merely slow.
            printFailure = error.localizedDescription
            isShowingPrintFailure = true
        }
    }
}
