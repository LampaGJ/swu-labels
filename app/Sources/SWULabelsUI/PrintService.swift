import Foundation
import SWULabelsRender

#if os(macOS)
import AppKit
import PDFKit
#elseif os(iOS)
import UIKit
#endif

/// Hands a rendered sheet to the platform's printing system.
///
/// **This is the only platform fork in the whole app.** Everything upstream —
/// parsing, grouping, templating, planning, drawing — is platform-free and
/// produces PDF data. Printing is where macOS and iOS genuinely differ, so the
/// difference is isolated to one file rather than spread through the interface.
/// Adding iPad support means this file already compiles; nothing else changes.
///
/// Scale is fixed at 100% on every path. "Fit to page" or "scale to fit" would
/// misalign all eighty labels against the pre-cut stock, so the option is never
/// offered and never defaulted to.
public struct PrintService: Sendable {
    public static let shared = PrintService()

    public enum PrintError: Error, CustomStringConvertible {
        case couldNotBuildDocument
        case noPrintingAvailable

        public var description: String {
            switch self {
            case .couldNotBuildDocument:
                return "the rendered sheet could not be prepared for printing"
            case .noPrintingAvailable:
                return "printing is not available on this platform"
            }
        }
    }

    /// Renders and presents the print dialog.
    @MainActor
    public func print(renderer: SheetRenderer, jobName: String) throws {
        let data = try renderer.renderPDF()
        try present(pdf: data, jobName: jobName, pageSize: renderer.pageSize)
    }

    #if os(macOS)
    @MainActor
    private func present(pdf data: Data, jobName: String, pageSize: CGSize) throws {
        guard let document = PDFDocument(data: data) else {
            throw PrintError.couldNotBuildDocument
        }

        let info = NSPrintInfo()
        info.paperSize = pageSize
        // Zero margins and no scaling: the PDF already places every label at its
        // exact position on the page, so any margin the print system adds would
        // shift the whole grid off the die-cut labels.
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.scalingFactor = 1.0
        info.jobDisposition = .spool

        guard let operation = document.printOperation(
            for: info, scalingMode: .pageScaleNone, autoRotate: false
        ) else {
            throw PrintError.couldNotBuildDocument
        }
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
    #elseif os(iOS)
    @MainActor
    private func present(pdf data: Data, jobName: String, pageSize: CGSize) throws {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = .general
        info.orientation = .portrait
        controller.printInfo = info
        // The PDF is already laid out at exactly 1:1 for the sheet, so it must
        // be handed over unscaled — `printingItem` prints the page as authored,
        // where a formatter would re-lay it out and defeat the alignment.
        controller.printingItem = data
        controller.present(animated: true)
    }
    #else
    @MainActor
    private func present(pdf data: Data, jobName: String, pageSize: CGSize) throws {
        throw PrintError.noPrintingAvailable
    }
    #endif
}
