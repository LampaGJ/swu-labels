import SwiftUI
import SWULabelsCore

/// The app's whole interface: sources on the left, cards in the middle, the
/// label being designed on the right.
///
/// A three-column `NavigationSplitView` is the shape every Apple utility of this
/// kind takes, and it adapts on its own to a single stack on iPhone and to a
/// collapsible sidebar on iPad — which is why the layout is expressed once here
/// rather than forked per platform.
public struct RootView: View {
    @State private var model: AppModel
    @State private var isPrinting = false
    @State private var printError: String?

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            SourceSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } content: {
            CardBrowser(model: model)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            LabelInspector(model: model)
                .navigationSplitViewColumnWidth(min: 340, ideal: 400)
        }
        .searchable(text: $model.searchText, prompt: "Search cards")
        .toolbar { toolbarContent }
        .alert(
            "Could not print",
            isPresented: Binding(
                get: { printError != nil },
                set: { if !$0 { printError = nil } }
            ),
            presenting: printError
        ) { _ in
            Button("OK", role: .cancel) { printError = nil }
        } message: { message in
            Text(message)
        }
        .overlay {
            if let message = model.phase.errorMessage {
                PipelineFailureView(message: message) { model.reload() }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            SheetSummaryLabel(model: model)
        }
        ToolbarItemGroup {
            Picker("Icons", selection: $model.assetsMode) {
                ForEach(AssetsMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Colour icons read better on screen; monochrome prints better.")

            Button {
                print()
            } label: {
                Label("Print", systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model.renderer == nil)
            .help("Print the current sheet at 100% scale")
        }
    }

    private func print() {
        guard let renderer = model.renderer else { return }
        isPrinting = true
        defer { isPrinting = false }
        do {
            try PrintService.shared.print(
                renderer: renderer,
                jobName: "SWU labels — \(model.matchingPreset?.displayName ?? "Custom order")"
            )
        } catch {
            printError = "\(error)"
        }
    }
}

/// A one-line statement of what the current settings would put on paper.
///
/// Sheet count is the number that matters before pressing print: label stock is
/// consumed a sheet at a time, and the difference between eighteen and nineteen
/// sheets is a wasted page nobody notices until it prints.
struct SheetSummaryLabel: View {
    let model: AppModel

    var body: some View {
        if model.phase.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading cards…").foregroundStyle(.secondary)
            }
        } else if model.plan != nil {
            Text("\(model.labelCount) labels · \(model.sheetCount) sheets")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown when the pipeline refuses to build a sheet.
///
/// The pipeline fails loudly by design — a missing set or a card that would be
/// dropped stops the run rather than printing a plausible, incomplete sheet — so
/// the interface shows the reason rather than an empty grid.
struct PipelineFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("This sheet cannot be built")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 420)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20, y: 8)
        .padding()
    }
}
